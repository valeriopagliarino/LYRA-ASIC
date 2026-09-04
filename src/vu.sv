/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : vu.sv
 *  Project     : LYRA Audio System
 *  Module      : vu
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 2.0 (Ultra-Compact Low-Area Architecture)
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  DESCRIPTION:
 *    Ultra-compact VU meter with pulse density output and clipping detection.
 *    Optimized for minimum gate count and small silicon area.
 *******************************************************************************/

module vu (
    input  logic        clk,                  // 12 MHz system clock
    input  logic        rst_n,                // Active-low asynchronous reset
    input  logic [15:0] audio_data_in,        // Signed 16-bit PCM audio input
    output logic        clip_out,             // Active HIGH for 1 second on clip
    output logic        vu_pulse_density_out  // 10 us pulse density output
);

    // ------------------------------------------------------------------------
    // 1. Approximate Absolute Value (1's complement - zero adders)
    // ------------------------------------------------------------------------
    logic [14:0] abs_audio;
    assign abs_audio = audio_data_in[15] ? ~audio_data_in[14:0] : audio_data_in[14:0];

    // ------------------------------------------------------------------------
    // 2. Clip Detection & Prescaled 1-Second Timer
    // ------------------------------------------------------------------------
    logic is_clipping;
    assign is_clipping = &abs_audio[14:2]; // AND-reduction over top 13 bits

    // 16-bit free-running prescaler (~5.46 ms tick @ 12 MHz)
    logic [15:0] clip_presc;
    logic        presc_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clip_presc <= '0;
        end else begin
            clip_presc <= clip_presc + 1'b1;
        end
    end

    assign presc_tick = (clip_presc == 16'hFFFF);

    // 8-bit down counter (183 ticks * 5.461 ms = 0.9994 s hold)
    logic [7:0] clip_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clip_cnt <= '0;
        end else if (is_clipping) begin
            clip_cnt <= 8'd183;
        end else if (presc_tick && (clip_cnt != '0)) begin
            clip_cnt <= clip_cnt - 1'b1;
        end
    end

    assign clip_out = (clip_cnt != '0);

    // ------------------------------------------------------------------------
    // 3. Compact 15-bit PFM Accumulator
    // Using top 8 bits of absolute amplitude (256 levels = ~48 dB dynamic range)
    // ------------------------------------------------------------------------
    logic [14:0] acc;
    logic [15:0] acc_sum;
    logic        acc_overflow;

    assign acc_sum      = acc + abs_audio[14:7];
    assign acc_overflow = acc_sum[15];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= '0;
        end else begin
            acc <= acc_sum[14:0];
        end
    end

    // ------------------------------------------------------------------------
    // 4. 10 us Pulse Generator (120 clock cycles @ 12 MHz)
    // ------------------------------------------------------------------------
    logic [6:0] pulse_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_cnt <= '0;
        end else if (acc_overflow) begin
            pulse_cnt <= 7'd120;
        end else if (pulse_cnt != '0) begin
            pulse_cnt <= pulse_cnt - 1'b1;
        end
    end

    assign vu_pulse_density_out = (pulse_cnt != '0);

endmodule