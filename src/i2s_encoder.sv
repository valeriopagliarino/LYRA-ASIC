/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : i2s_encoder.sv
 *  Project     : LYRA Audio System
 *  Module      : i2s_encoder
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.1
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Stereo I2S-to-Parallel encoder module optimized for ASIC synthesis.
 *    Features independent Left/Right valid signals and a single 16-bit 
 *    active transmission buffer to prevent data tearing with minimal area.
 *    Decodes 16-bit 44.1 kHz audio using an 11.2896 MHz system clock.
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *    1.1   2026-09-03  V. Pagliarino    Added dual valid ports and TX snapshot buffer
 *******************************************************************************/

`timescale 1ns / 1ps

module i2s_encoder (
    input  logic        clk,         // System clock (11.2896 MHz)
    input  logic        rst_n,       // Asynchronous active-low reset
    
    // I2S Interface (Outputs)
    output logic        i2s_bclk,    // Bit Clock (2.8224 MHz)
    output logic        i2s_ws,      // Word Select (0 = Left, 1 = Right)
    output logic        i2s_sdata,   // Serial Data
    
    // Parallel Interface (Inputs)
    input  logic [15:0] left_data,   // Parallel input data for Left channel
    input  logic        left_valid,  // 1-clock pulse when left_data is valid
    input  logic [15:0] right_data,  // Parallel input data for Right channel
    input  logic        right_valid  // 1-clock pulse when right_data is valid
);

    // Staging registers for independent incoming audio channels (32 FFs)
    logic [15:0] left_in_reg;
    logic [15:0] right_in_reg;

    // Active transmission buffer (16 FFs)
    // Prevents data tearing if left_valid/right_valid arrive mid-frame
    logic [15:0] tx_reg;

    // Master 8-bit system counter (8 FFs)
    // 256 clock cycles @ 11.2896 MHz = 1 I2S frame @ 44.1 kHz
    logic [7:0] cnt;

    // Bit index mapping for MSB-first transmission
    logic [3:0] bit_idx;
    assign bit_idx = 4'd16 - cnt[6:2];

    //--------------------------------------------------------------------------
    // 1. Independent Input Data Capture
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            left_in_reg  <= 16'd0;
            right_in_reg <= 16'd0;
        end else begin
            if (left_valid)  left_in_reg  <= left_data;
            if (right_valid) right_in_reg <= right_data;
        end
    end

    //--------------------------------------------------------------------------
    // 2. Master System Counter
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 8'd0;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // 3. I2S Generation & Active Buffer Snapshot
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_reg    <= 16'd0;
            i2s_bclk  <= 1'b0;
            i2s_ws    <= 1'b0;
            i2s_sdata <= 1'b0;
        end else begin
            // Generate Bit Clock (11.2896 MHz / 4 = 2.8224 MHz)
            i2s_bclk <= ~cnt[1];

            // Drive outputs on BCLK falling edge (cnt[1:0] == 2'b01)
            if (cnt[1:0] == 2'b01) begin
                // Update Word Select (changes 1 BCLK cycle before MSB)
                i2s_ws <= cnt[7]; // 0 = Left Channel, 1 = Right Channel

                // Snapshot the relevant channel buffer at the start of its slot (BCLK 0)
                if (cnt[6:2] == 5'd0) begin
                    tx_reg <= cnt[7] ? right_in_reg : left_in_reg;
                end

                // Transmit audio bits (MSB to LSB) during BCLK cycles 1 to 16
                if (cnt[6:2] >= 5'd1 && cnt[6:2] <= 5'd16) begin
                    i2s_sdata <= tx_reg[bit_idx];
                end else begin
                    i2s_sdata <= 1'b0; // Pad remaining 16 BCLK cycles with zero
                end
            end
        end
    end

endmodule