/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : dsp.sv
 *  Project     : LYRA Audio System
 *  Module      : dsp
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 6.0 (Bug-Fixed & Hold-Optimized Architecture)
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  DESCRIPTION:
 *    Dual-channel audio DSP with serial multiplication.
 *    Isolated processing registers protect against input changes, while
 *    combinational MUX delay eliminates post-CTS hold buffer insertion.
 *******************************************************************************/


module dsp #(
    parameter int NUM_CH = 2
) (
    input  logic        clk,
    input  logic        rst_n,

    // Per-channel audio I/O
    input  logic [15:0] ch0_data_in,
    input  logic        ch0_valid_in,
    input  logic [15:0] ch1_data_in,
    input  logic        ch1_valid_in,

    output logic [15:0] ch0_data_out,
    output logic        ch0_valid_out,
    output logic [15:0] ch1_data_out,
    output logic        ch1_valid_out,

    // Shared Control Ports
    input  logic [2:0]  comp_thresh,
    input  logic [1:0]  comp_speed,
    input  logic [1:0]  comp_ratio,
    input  logic [1:0]  exciter_freq,
    input  logic [2:0]  exciter_drive,
    input  logic        comp_bypass_b,
    input  logic        exciter_bypass_b
);

    // -------------------------------------------------------------------
    // Port Packing
    // -------------------------------------------------------------------
    logic [15:0] data_in   [0:NUM_CH-1];
    logic        valid_in  [0:NUM_CH-1];
    logic [15:0] data_out  [0:NUM_CH-1];
    logic        valid_out [0:NUM_CH-1];

    assign data_in[0]  = ch0_data_in;
    assign data_in[1]  = ch1_data_in;
    assign valid_in[0] = ch0_valid_in;
    assign valid_in[1] = ch1_valid_in;

    assign ch0_data_out  = data_out[0];
    assign ch1_data_out  = data_out[1];
    assign ch0_valid_out = valid_out[0];
    assign ch1_valid_out = valid_out[1];

    // -------------------------------------------------------------------
    // Per-Channel State Registers
    // -------------------------------------------------------------------
    logic [15:0] in_sample  [0:NUM_CH-1];
    logic        pending    [0:NUM_CH-1];
    logic [14:0] env        [0:NUM_CH-1];
    logic signed [15:0] lpf [0:NUM_CH-1];
    
    logic [15:0] data_stage [0:NUM_CH-1];
    logic        processed  [0:NUM_CH-1];

    // -------------------------------------------------------------------
    // Arbiter & Channel Muxing
    // -------------------------------------------------------------------
    logic sel;
    logic any_pending;

    always_comb begin
        sel         = 1'b0;
        any_pending = 1'b0;
        if (pending[1]) begin
            sel         = 1'b1;
            any_pending = 1'b1;
        end else if (pending[0]) begin
            sel         = 1'b0;
            any_pending = 1'b1;
        end
    end

    // Selected Channel Wires
    logic signed [15:0] sample_sel;
    logic [14:0]        env_sel;
    logic signed [15:0] lpf_sel;

    assign sample_sel = $signed(in_sample[sel]);
    assign env_sel     = env[sel];
    assign lpf_sel     = lpf[sel];

    // -------------------------------------------------------------------
    // Combinational Envelope & Gain (Evaluated using 'sel')
    // -------------------------------------------------------------------
    logic [14:0] abs_audio;
    // Corretto: negazione completa in complemento a 2 se negativo
    logic signed [15:0] negated_sample;
    assign negated_sample = -sample_sel;
    assign abs_audio      = sample_sel[15] ? negated_sample[14:0] : sample_sel[14:0];

    logic signed [15:0] env_diff;
    assign env_diff = $signed({1'b0, abs_audio}) - $signed({1'b0, env_sel});

    logic [3:0] env_shift;
    always_comb begin
        case (comp_speed)
            2'b00:   env_shift = 4'd4;
            2'b01:   env_shift = 4'd6;
            2'b10:   env_shift = 4'd8;
            default: env_shift = 4'd10;
        endcase
    end

    logic [14:0] new_env;
    assign new_env = env_sel + 15'(env_diff >>> env_shift);

    logic [14:0] thresh;
    always_comb begin
        case (comp_thresh)
            3'b000:  thresh = 15'd30000;
            3'b001:  thresh = 15'd26000;
            3'b010:  thresh = 15'd20600;
            3'b011:  thresh = 15'd16384;
            3'b100:  thresh = 15'd11585;
            3'b101:  thresh = 15'd8192;
            3'b110:  thresh = 15'd5792;
            default: thresh = 15'd4096;
        endcase
    end

    logic [14:0] env_excess;
    assign env_excess = (env_sel > thresh) ? (env_sel - thresh) : 15'd0;

    logic [8:0] gain_sub;
    always_comb begin
        case (comp_ratio)
            2'b00:   gain_sub = env_excess[14:7];
            2'b01:   gain_sub = env_excess[14:6];
            2'b10:   gain_sub = env_excess[14:5];
            default: gain_sub = {env_excess[14:5], 1'b0};
        endcase
    end

    logic [8:0] gain;
    assign gain = (gain_sub >= 9'd192) ? 9'd64 : (9'd256 - gain_sub);

    // -------------------------------------------------------------------
    // Execution Work Registers
    // -------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_MULT,
        ST_FINISH
    } state_t;

    state_t state;

    logic        active_ch;       
    logic signed [15:0] proc_sample;     
    logic [14:0]        proc_env;        
    logic signed [15:0] proc_lpf; 

    logic signed [24:0] mult_acc;
    logic signed [24:0] mult_a;
    logic [8:0]         mult_b;
    logic [3:0]         mult_cnt;

    // -------------------------------------------------------------------
    // Combinational Exciter & Saturation
    // -------------------------------------------------------------------
    logic signed [15:0] comp_audio_calc;
    logic signed [15:0] comp_audio;

    assign comp_audio_calc = mult_acc[23:8];
    assign comp_audio      = (~comp_bypass_b) ? proc_sample : comp_audio_calc;

    logic signed [15:0] hpf;
    logic signed [15:0] lpf_diff;

    assign lpf_diff = comp_audio - proc_lpf;
    assign hpf      = comp_audio - proc_lpf;

    logic [3:0] lpf_shift;
    always_comb begin
        case (exciter_freq)
            2'b00:   lpf_shift = 4'd2;
            2'b01:   lpf_shift = 4'd3;
            2'b10:   lpf_shift = 4'd4;
            default: lpf_shift = 4'd5;
        endcase
    end

    logic signed [15:0] new_lpf;
    assign new_lpf = proc_lpf + (lpf_diff >>> lpf_shift);

    // Corretto: Estrazione armonica simmetrica mantenendo la polarità di hpf
    logic signed [15:0] harmonics;
    assign harmonics = hpf - (hpf >>> 2);

    logic signed [15:0] exc_blend;
    always_comb begin
        if (!exciter_bypass_b) begin
            exc_blend = '0;
        end else begin
            case (exciter_drive)
                3'b001:  exc_blend = harmonics >>> 4;
                3'b010:  exc_blend = harmonics >>> 3;
                3'b011:  exc_blend = (harmonics >>> 3) + (harmonics >>> 4);
                3'b100:  exc_blend = harmonics >>> 2;
                3'b101:  exc_blend = (harmonics >>> 2) + (harmonics >>> 3);
                3'b110:  exc_blend = harmonics >>> 1;
                3'b111:  exc_blend = harmonics;
                default: exc_blend = '0;
            endcase
        end
    end

    logic signed [16:0] sum_out;
    assign sum_out = $signed(comp_audio) + $signed(exc_blend);

    logic [15:0] new_out;
    always_comb begin
        if (sum_out > 17'sd32767) begin
            new_out = 16'sh7FFF;
        end else if (sum_out < -17'sd32768) begin
            new_out = 16'sh8000;
        end else begin
            new_out = sum_out[15:0];
        end
    end

    // Batch completion flag
    logic batch_ready;
    assign batch_ready = processed[~active_ch];

    // -------------------------------------------------------------------
    // Sequential State Block
    // -------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            active_ch   <= 1'b0;
            proc_sample <= '0;
            proc_env    <= '0;
            proc_lpf    <= '0;
            mult_acc    <= '0;
            mult_a      <= '0;
            mult_b      <= '0;
            mult_cnt    <= '0;

            for (int i = 0; i < NUM_CH; i++) begin
                in_sample[i]  <= 16'h0000;
                pending[i]    <= 1'b0;
                processed[i]  <= 1'b0;
                env[i]        <= '0;
                lpf[i]        <= '0;
                data_stage[i] <= 16'h0000;
                data_out[i]   <= 16'h0000;
                valid_out[i]  <= 1'b0;
            end
        end else begin
            valid_out[0] <= 1'b0;
            valid_out[1] <= 1'b0;

            // 1. Independent Input Capture
            if (valid_in[0]) begin
                in_sample[0] <= data_in[0];
                pending[0]   <= 1'b1;
            end
            if (valid_in[1]) begin
                in_sample[1] <= data_in[1];
                pending[1]   <= 1'b1;
            end

            // 2. FSM Execution
            case (state)
                ST_IDLE: begin
                    if (any_pending) begin
                        active_ch    <= sel;
                        pending[sel] <= 1'b0;

                        proc_sample  <= sample_sel;
                        proc_env     <= new_env;
                        proc_lpf     <= lpf_sel;

                        mult_acc     <= 25'sd0;
                        mult_a       <= $signed({{9{sample_sel[15]}}, sample_sel});
                        mult_b       <= gain;
                        mult_cnt     <= 4'd0;

                        state        <= ST_MULT;
                    end
                end

                ST_MULT: begin
                    if (mult_b[0]) begin
                        mult_acc <= mult_acc + mult_a;
                    end
                    mult_a   <= mult_a << 1;
                    mult_b   <= mult_b >> 1;
                    mult_cnt <= mult_cnt + 1'b1;

                    if (mult_cnt == 4'd8) begin
                        state <= ST_FINISH;
                    end
                end

                ST_FINISH: begin
                    env[active_ch]        <= proc_env;
                    lpf[active_ch]        <= new_lpf;
                    data_stage[active_ch] <= new_out;

                    if (batch_ready) begin
                        data_out[active_ch]  <= new_out;
                        data_out[~active_ch] <= data_stage[~active_ch];

                        valid_out[0] <= 1'b1;
                        valid_out[1] <= 1'b1;

                        processed[0] <= 1'b0;
                        processed[1] <= 1'b0;
                    end else begin
                        processed[active_ch] <= 1'b1;
                    end

                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule