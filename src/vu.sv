/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : i2s_decoder.sv
 *  Project     : LYRA Audio System
 *  Module      : i2s_decoder
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.0
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Vu meter with pulse density output and clipping detection. 
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/


module vu (
    input  logic        clk,                  // 12 MHz system clock
    input  logic        rst_n,                // Active-low asynchronous reset
    input  logic [15:0] audio_data_in,        // Signed 16-bit PCM audio input
    output logic        clip_out,             // Active HIGH for 1 second on clip
    output logic        vu_pulse_density_out  // 10 us pulse density output
);

    // ------------------------------------------------------------------------
    // Timing Constants @ 12 MHz
    // ------------------------------------------------------------------------
    localparam bit [23:0] CLIP_TICKS  = 24'd12_000_000; // 1 second pulse duration
    localparam bit [6:0]  PULSE_TICKS = 7'd120;         // 10 us pulse width (120 cycles)

    // ------------------------------------------------------------------------
    // 1. Approximate Absolute Value (1's complement - zero adders)
    // ------------------------------------------------------------------------
    logic [14:0] abs_audio;
    assign abs_audio = audio_data_in[15] ? ~audio_data_in[14:0] : audio_data_in[14:0];

    // ------------------------------------------------------------------------
    // 2. Clip Detection (Amplitude >= 32764 / -3 dBFS from max range)
    // Saves silicon area by using an AND reduction over top 13 bits instead 
    // of a full 16-bit comparator.
    // ------------------------------------------------------------------------
    logic is_clipping;
    assign is_clipping = &abs_audio[14:2];

    logic [23:0] clip_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clip_cnt <= '0;
        end else if (is_clipping) begin
            clip_cnt <= CLIP_TICKS;
        end else if (clip_cnt != '0) begin
            clip_cnt <= clip_cnt - 1'b1;
        end
    end

    assign clip_out = (clip_cnt != '0);

    // ------------------------------------------------------------------------
    // 3. PFM Accumulator (Integrate & Fire)
    // 22-bit accumulator: at max amplitude (0 dBFS), it overflows every ~10.66 us
    // (~94% duty cycle for 10 us pulses).
    // ------------------------------------------------------------------------
    logic [22:0] acc_sum;
    logic [21:0] acc;
    logic        acc_overflow;

    assign acc_sum      = acc + abs_audio;
    assign acc_overflow = acc_sum[22]; // Carry-out bit

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= '0;
        end else begin
            acc <= acc_sum[21:0];
        end
    end

    // ------------------------------------------------------------------------
    // 4. 10 us Pulse Generator (120 clock cycles @ 12 MHz)
    // ------------------------------------------------------------------------
    logic [6:0] pulse_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_cnt <= '0;
        end else if (pulse_cnt != '0) begin
            pulse_cnt <= pulse_cnt - 1'b1;
        end else if (acc_overflow) begin
            pulse_cnt <= PULSE_TICKS - 1'b1;
        end
    end

    assign vu_pulse_density_out = (pulse_cnt != '0);

endmodule