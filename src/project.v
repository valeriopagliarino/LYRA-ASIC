/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : project.sv
 *  Project     : LYRA Audio System
 *  Module      : tt_um_lyra
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.0
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    LYRA Audio Interface with embedded I2S and ADAT ports, SPI control interface, 
 *    and VU meter outputs and DSP
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/

`default_nettype none

module tt_um_lyra (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  //////////////////////////////////////////////////////////////////////
  //// CORE SIGNALS
  //////////////////////////////////////////////////////////////////////

  //I2S 0 (CH0 CH1)
  wire i2s0_ck;
  wire i2s0_ad;
  wire i2s0_ws;

  //I2S 1 (CH2 CH3)
  wire i2s1_ck;
  wire i2s1_ad;
  wire i2s1_ws;

  //I2S MON (Output)
  wire i2so_ck;
  wire i2so_ad;
  wire i2so_ws;

  //Optical Adat Serial Link Port
  wire opt_drive;

  //Controls inputs
  wire mute_01;
  wire mute_23;

  wire spi_sck;
  wire spi_mosi;
  wire spi_cs;

  //Controls output
  wire spi_miso;

  wire vu_meter_0;
  wire vu_meter_1;
  wire vu_meter_2;
  wire vu_meter_3;
  wire vu_meter_mon;
  wire vu_meter_clip;

  //Clock outputs
  wire sampling_clock;

  //////////////////////////////////////////////////////////////////////
  //// TOP LEVEL INSTANTIATION
  //////////////////////////////////////////////////////////////////////

  lyra_topl lyra_topl_inst (
    .clk(clk),
    .rst_n(rst_n),

    .i2s0_ck(i2s0_ck),
    .i2s0_ad(i2s0_ad),
    .i2s0_ws(i2s0_ws),

    .i2s1_ck(i2s1_ck),
    .i2s1_ad(i2s1_ad),
    .i2s1_ws(i2s1_ws),

    .i2so_ck(i2so_ck),
    .i2so_ad(i2so_ad),
    .i2so_ws(i2so_ws),

    .opt_drive(opt_drive),

    .mute_01(mute_01),
    .mute_23(mute_23),

    .spi_sck(spi_sck),
    .spi_mosi(spi_mosi),
    .spi_cs(spi_cs),
    .spi_miso(spi_miso),

    .vu_meter_0(vu_meter_0),
    .vu_meter_1(vu_meter_1),
    .vu_meter_2(vu_meter_2),
    .vu_meter_3(vu_meter_3),
    .vu_meter_mon(vu_meter_mon),
    .vu_meter_clip(vu_meter_clip),
    .sampling_clock(sampling_clock)
  );


  //////////////////////////////////////////////////////////////////////
  //// PADRING
  //////////////////////////////////////////////////////////////////////

  // Output pins
  assign uo_out[0] = opt_drive;
  assign uo_out[1] = opt_drive;
  assign uo_out[2] = vu_meter_0;
  assign uo_out[3] = vu_meter_1;
  assign uo_out[4] = vu_meter_2;
  assign uo_out[5] = vu_meter_3;
  assign uo_out[6] = vu_meter_clip;
  assign uo_out[7] = sampling_clock;

  // Input pins
  assign i2s0_ck = ui_in[0];
  assign i2s0_ad = ui_in[1];
  assign i2s0_ws = ui_in[2];
  assign i2s1_ck = ui_in[3];
  assign i2s1_ad = ui_in[4];
  assign i2s1_ws = ui_in[5];
  assign mute_01 = ui_in[6];
  assign mute_23 = ui_in[7];

  // Inout pins as inputs
  assign spi_sck    = uio_in[0];
  assign spi_mosi   = uio_in[1];
  assign spi_cs     = uio_in[2];

  assign uio_oe[0]  = 1'b0;   // spi_sck is input
  assign uio_oe[1]  = 1'b0;   // spi_mosi is input
  assign uio_oe[2]  = 1'b0;   // spi_cs is input

  // Inout pins as outputs
  assign uio_out[0] = 1'b0;
  assign uio_out[1] = 1'b0;
  assign uio_out[2] = 1'b0;
  assign uio_out[3] = spi_miso;
  assign uio_out[4] = i2so_ck;
  assign uio_out[5] = i2so_ad;
  assign uio_out[6] = i2so_ws;
  assign uio_out[7] = vu_meter_mon;

  assign uio_oe[3]  = 1'b1;   // spi_miso is output
  assign uio_oe[4]  = 1'b1;   // i2so_ck is output
  assign uio_oe[5]  = 1'b1;   // i2so_ad is output
  assign uio_oe[6]  = 1'b1;   // i2so_ws is output
  assign uio_oe[7]  = 1'b1;   // vu_meter_mon is output

  wire ignored_signals = &{ena, 1'b0}; // to avoid warnings for unused signals

endmodule
