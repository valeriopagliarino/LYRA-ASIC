/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : i2s_encoder.sv
 *  Project     : LYRA Audio System
 *  Module      : i2s_encoder
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.0
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Stereo I2S-to-Parallel encoder module optimized for ASIC synthesis.
 *    Decodes 16-bit 44.1 kHz audio using an 11.2896 MHz system clock.
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/

`timescale 1ns / 1ps

module i2s_encoder (
    input  logic        clk,        // System clock (11.2896 MHz)
    input  logic        rst_n,      // Asynchronous reset, active low
    
    // I2S Interface (Input)
    output  logic        i2s_bclk,   // Bit Clock
    output  logic        i2s_ws,     // Word Select (0 = Left, 1 = Right)
    output  logic        i2s_sdata,  // Serial Data
    
    // Parallel Interface (Input)
    input logic [15:0] left_data,
    input logic [15:0] right_data,
    input logic        valid       // 1-clock-cycle high pulse when stereo sampling is complete
);

endmodule