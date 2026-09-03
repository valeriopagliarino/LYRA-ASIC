
/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : dsp.sv
 *  Project     : LYRA Audio System
 *  Module      : dsp
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.0
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Audio area-optimized DSP for LYRA.
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/

module dsp (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] audio_data_in,
    input  logic        audio_data_valid_in,

    // Programmable Control Ports (13 bits total)
    input  logic [2:0]  comp_thresh,    // 8 Thresholds: -0.8dB to -18dB
    input  logic [1:0]  comp_speed,     // Attack/Release timing: Fast, Med-Fast, Med-Slow, Slow
    input  logic [1:0]  comp_ratio,     // Compression Ratio: 1.5:1, 2:1, 4:1, Inf:1 (Limiter)
    input  logic [1:0]  exciter_freq,   // HPF Cutoff tuning: ~3kHz, ~1.5kHz, ~750Hz, ~375Hz
    input  logic [2:0]  exciter_drive,  // 8 Harmonic blend levels: 0% to 100%
    input  logic        comp_bypass_b,    // 1: Bypass Compressor
    input  logic        exciter_bypass_b, // 1: Bypass Exciter

    output logic [15:0] audio_data_out,
    output logic        audio_data_valid_out
);

    // ------------------------------------------------------------------------
    // 1. Approximate Absolute Value (1's complement - zero adders)
    // ------------------------------------------------------------------------
    logic [14:0] abs_audio;
    assign abs_audio = audio_data_in[15] ? ~audio_data_in[14:0] : audio_data_in[14:0];

    // ------------------------------------------------------------------------
    // 2. Programmable Compressor Envelope Detector
    // ------------------------------------------------------------------------
    logic [14:0] env;
    logic signed [15:0] env_diff;
    assign env_diff = $signed({1'b0, abs_audio}) - $signed({1'b0, env});

    // Muxing shift amount changes attack/release speed with zero extra FFs
    logic [3:0] env_shift;
    always_comb begin
        case (comp_speed)
            2'b00:   env_shift = 4'd4;  // Fast
            2'b01:   env_shift = 4'd6;  // Medium-Fast
            2'b10:   env_shift = 4'd8;  // Medium-Slow
            default: env_shift = 4'd10; // Slow
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            env <= '0;
        end else if (audio_data_valid_in) begin
            env <= env + 15'(env_diff >>> env_shift);
        end
    end

    // ------------------------------------------------------------------------
    // 3. 8-Level Threshold & Programmable Ratio Gain Logic
    // ------------------------------------------------------------------------
    logic [14:0] thresh;
    always_comb begin
        case (comp_thresh)
            3'b000:  thresh = 15'd30000; // -0.8 dBFS
            3'b001:  thresh = 15'd26000; // -2.0 dBFS
            3'b010:  thresh = 15'd20600; // -4.0 dBFS
            3'b011:  thresh = 15'd16384; // -6.0 dBFS
            3'b100:  thresh = 15'd11585; // -9.0 dBFS
            3'b101:  thresh = 15'd8192;  // -12.0 dBFS
            3'b110:  thresh = 15'd5792;  // -15.0 dBFS
            default: thresh = 15'd4096;  // -18.0 dBFS
        endcase
    end

    logic [14:0] env_excess;
    assign env_excess = (env > thresh) ? (env - thresh) : 15'd0;

    // Gain reduction slope controlled by ratio selection
    logic [8:0] gain_sub;
    always_comb begin
        case (comp_ratio)
            2'b00:   gain_sub = env_excess[14:7];          // ~1.5:1 ratio (Soft)
            2'b01:   gain_sub = env_excess[14:6];          // 2:1 ratio
            2'b10:   gain_sub = env_excess[14:5];          // 4:1 ratio
            default: gain_sub = {env_excess[14:5], 1'b0}; // Inf:1 Limiter (Hard)
        endcase
    end

    // Clamp minimum gain to 0.25 (-12dB max attenuation)
    logic [8:0] gain;
    assign gain = (gain_sub >= 9'd192) ? 9'd64 : (9'd256 - gain_sub);

    // ------------------------------------------------------------------------
    // 4. Single Multiplier Gain Application & Compressor Bypass
    // ------------------------------------------------------------------------
    logic signed [24:0] mult_comp;
    logic signed [15:0] comp_audio_calc;
    logic signed [15:0] comp_audio;

    assign mult_comp       = $signed(audio_data_in) * $signed({1'b0, gain});
    assign comp_audio_calc = mult_comp[23:8];
    assign comp_audio      = (~comp_bypass_b) ? audio_data_in : comp_audio_calc;

    // ------------------------------------------------------------------------
    // 5. Programmable Exciter Stage (HPF Tuning + Harmonics)
    // ------------------------------------------------------------------------
    logic signed [15:0] lpf;
    logic signed [15:0] hpf;
    logic signed [15:0] lpf_diff;

    assign lpf_diff = comp_audio - lpf;
    assign hpf      = comp_audio - lpf;

    // Muxing LPF cutoff frequency controls exciter tone/color
    logic [3:0] lpf_shift;
    always_comb begin
        case (exciter_freq)
            2'b00:   lpf_shift = 4'd2; // ~3.0 kHz HPF Cutoff (Air)
            2'b01:   lpf_shift = 4'd3; // ~1.5 kHz HPF Cutoff (Highs)
            2'b10:   lpf_shift = 4'd4; // ~750 Hz HPF Cutoff (Presence)
            default: lpf_shift = 4'd5; // ~375 Hz HPF Cutoff (Warmth)
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lpf <= '0;
        end else if (audio_data_valid_in) begin
            lpf <= lpf + (lpf_diff >>> lpf_shift);
        end
    end

    // Nonlinear harmonic generation (Asymmetric Soft Clipper)
    logic signed [15:0] harmonics;
    assign harmonics = hpf[15] ? -(hpf >>> 2) : (hpf - (hpf >>> 2));

    // 8-Level Drive Control
    logic signed [15:0] exc_blend;
    always_comb begin
        if (!exciter_bypass_b) begin
            exc_blend = '0;
        end else begin
            case (exciter_drive)
                3'b001:  exc_blend = harmonics >>> 4;                        //  6.25%
                3'b010:  exc_blend = harmonics >>> 3;                        // 12.5%
                3'b011:  exc_blend = (harmonics >>> 3) + (harmonics >>> 4);  // 18.75%
                3'b100:  exc_blend = harmonics >>> 2;                        // 25.0%
                3'b101:  exc_blend = (harmonics >>> 2) + (harmonics >>> 3);  // 37.5%
                3'b110:  exc_blend = harmonics >>> 1;                        // 50.0%
                3'b111:  exc_blend = harmonics;                              // 100.0%
                default: exc_blend = '0;                                     // Off
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 6. Final Mix & Saturation Logic
    // ------------------------------------------------------------------------
    logic signed [16:0] sum_out;
    assign sum_out = $signed(comp_audio) + $signed(exc_blend);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            audio_data_out       <= '0;
            audio_data_valid_out <= 1'b0;
        end else begin
            audio_data_valid_out <= audio_data_valid_in;
            if (audio_data_valid_in) begin
                if (sum_out > 17'sd32767) begin
                    audio_data_out <= 16'sh7FFF;
                end else if (sum_out < -17'sd32768) begin
                    audio_data_out <= 16'sh8000;
                end else begin
                    audio_data_out <= sum_out[15:0];
                end
            end
        end
    end

endmodule