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
 *    Stereo I2S-to-Parallel decoder module optimized for ASIC synthesis.
 *    Decodes 16-bit 44.1 kHz audio using an 11.2896 MHz system clock.
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/

`timescale 1ns / 1ps

module i2s_decoder (
    input  logic        clk,        // System clock (11.2896 MHz)
    input  logic        rst_n,      // Asynchronous reset, active low
    
    // I2S Interface (Input)
    input  logic        i2s_bclk,   // Bit Clock
    input  logic        i2s_ws,     // Word Select (0 = Left, 1 = Right)
    input  logic        i2s_sdata,  // Serial Data
    
    // Parallel Interface (Output)
    output logic [15:0] left_data,
    output logic [15:0] right_data,
    output logic        valid       // 1-clock-cycle high pulse when stereo sampling is complete
);

    // Synchronization registers (3-stage Clock Domain Crossing for ASIC stability)
    logic [2:0] bclk_sync;
    logic [2:0] ws_sync;
    logic [2:0] sdata_sync;

    // Synchronization of I2S signals into the system clock domain
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_sync  <= 3'b000;
            ws_sync    <= 3'b000;
            sdata_sync <= 3'b000;
        end else begin
            bclk_sync  <= {bclk_sync[1:0], i2s_bclk};
            ws_sync    <= {ws_sync[1:0], i2s_ws};
            sdata_sync <= {sdata_sync[1:0], i2s_sdata};
        end
    end

    // Rising edge detection of the synchronized BCLK
    logic bclk_rising;
    assign bclk_rising = (bclk_sync[2:1] == 2'b01);

    // Internal registers and counters
    logic        ws_prev;
    logic [4:0]  bit_cnt;
    logic [15:0] shift_reg;
    logic        current_ch;
    logic        left_ready; // Flag to ensure the left channel arrived before the right channel

    // State machine / Datapath
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws_prev    <= 1'b0;
            bit_cnt    <= 5'd0;
            shift_reg  <= 16'd0;
            current_ch <= 1'b0;
            left_ready <= 1'b0;
            left_data  <= 16'd0;
            right_data <= 16'd0;
            valid      <= 1'b0;
        end else begin
            valid <= 1'b0; // Default: the pulse lasts for exactly one clock cycle (11.2896 MHz)

            if (bclk_rising) begin
                ws_prev <= ws_sync[2];

                if (ws_sync[2] != ws_prev) begin
                    // Edge detected on Word Select. 
                    // The I2S standard specifies that the MSB arrives 1 bclk cycle *after* the ws transition.
                    // Reset the bit counter; actual sampling will start on the next bclk_rising.
                    bit_cnt    <= 5'd0;
                    current_ch <= ws_sync[2]; // Save the incoming channel (0 = Left, 1 = Right)
                end else begin
                    // We are receiving the channel bits
                    if (bit_cnt < 5'd16) begin
                        // Shift the data in (I2S is MSB-first)
                        shift_reg <= {shift_reg[14:0], sdata_sync[2]};
                        
                        // If we have received the last bit (the 16th)
                        if (bit_cnt == 5'd15) begin
                            if (current_ch == 1'b0) begin
                                // Left channel completed
                                left_data  <= {shift_reg[14:0], sdata_sync[2]};
                                left_ready <= 1'b1;
                            end else begin
                                // Right channel completed
                                right_data <= {shift_reg[14:0], sdata_sync[2]};
                                // Assert valid only if we correctly received a Left-Right packet
                                if (left_ready) begin
                                    valid      <= 1'b1;
                                    left_ready <= 1'b0; // Reset for the next frame
                                end
                            end
                        end
                        bit_cnt <= bit_cnt + 5'd1;
                    end
                end
            end
        end
    end

endmodule