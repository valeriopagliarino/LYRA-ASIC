
/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : lyra_topl.sv
 *  Project     : LYRA Audio System
 *  Module      : lyra_topl
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.0
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Stereo I2S-to-Parallel decoder module optimized for ASIC synthesis.
 *    Decodes 16-bit 44.1 kHz audio using an 11.2896 MHz system clock. Top Level.
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/

module lyra_topl  (
        input logic clk,
        input logic rst_n,

        input logic i2s0_ck,
        input logic i2s0_ad,
        input logic i2s0_ws,

        input logic i2s1_ck,
        input logic i2s1_ad,
        input logic i2s1_ws,

        output logic i2so_ck,
        output logic i2so_ad,
        output logic i2so_ws,

        output logic opt_drive,

        input logic mute_01,
        input logic mute_23,

        input  logic spi_sck,
        input  logic spi_mosi,
        input  logic spi_cs,
        output logic spi_miso,

        output logic vu_meter_0,
        output logic vu_meter_1,
        output logic vu_meter_2,
        output logic vu_meter_3,
        output logic vu_meter_mon,
        output logic vu_meter_clip,

        output logic sampling_clock
    );

    ///////////////////////////////////////////////////////
    //// Routing Signals
    ///////////////////////////////////////////////////////

    logic vu_meter_clip_0;
    logic vu_meter_clip_1;
    logic vu_meter_clip_2;
    logic vu_meter_clip_3;
    assign vu_meter_mon = 1'b0;

    logic [15:0] audio_data_0;
    logic [15:0] audio_data_1;
    logic [15:0] audio_data_2;
    logic [15:0] audio_data_3;
    logic [15:0] audio_data_out_0;
    logic [15:0] audio_data_out_1;
    logic [15:0] audio_data_adat0;
    logic [15:0] audio_data_adat1;
    logic [15:0] audio_data_adat2;
    logic [15:0] audio_data_adat3;

    logic        audio_data_valid_0;
    logic        audio_data_valid_1;
    logic        audio_data_valid_2;
    logic        audio_data_valid_3; 
    logic        audio_data_out_valid_0;
    logic        audio_data_out_valid_1;
    logic        audio_data_adat0_valid;
    logic        audio_data_adat1_valid;
    logic        audio_data_adat2_valid;
    logic        audio_data_adat3_valid;

    ///////////////////////////////////////////////////////
    //// VU Meter Instances
    ///////////////////////////////////////////////////////

    assign vu_meter_clip = vu_meter_clip_0 | vu_meter_clip_1 | vu_meter_clip_2 | vu_meter_clip_3;

    vu vu_inst0 (
        .clk(clk),
        .rst_n(rst_n),
        .audio_data_in(audio_data_0),
        .clip_out(vu_meter_clip_0),
        .vu_pulse_density_out(vu_meter_0)
    );

    vu vu_inst1 (
        .clk(clk),
        .rst_n(rst_n),
        .audio_data_in(audio_data_1),
        .clip_out(vu_meter_clip_1),
        .vu_pulse_density_out(vu_meter_1)
    );

    vu vu_inst2 (
        .clk(clk),
        .rst_n(rst_n),
        .audio_data_in(audio_data_2),
        .clip_out(vu_meter_clip_2),
        .vu_pulse_density_out(vu_meter_2)
    );

    vu vu_inst3 (
        .clk(clk),
        .rst_n(rst_n),
        .audio_data_in(audio_data_3),
        .clip_out(vu_meter_clip_3),
        .vu_pulse_density_out(vu_meter_3)
    );

    ///////////////////////////////////////////////////////
    //// I2S Decoder Instances
    ///////////////////////////////////////////////////////

    i2s_decoder i2s_decoder_inst0 (
        .clk(clk),
        .rst_n(rst_n),
        .mute(mute_01),
        .i2s_bclk(i2s0_ck),
        .i2s_ws(i2s0_ws),
        .i2s_sdata(i2s0_ad),
        .left_data(audio_data_0),
        .right_data(audio_data_1),
        .valid(audio_data_valid_0)
    );

    i2s_decoder i2s_decoder_inst1 (
        .clk(clk),
        .rst_n(rst_n),
        .mute(mute_23),
        .i2s_bclk(i2s1_ck),
        .i2s_ws(i2s1_ws),
        .i2s_sdata(i2s1_ad),
        .left_data(audio_data_2),
        .right_data(audio_data_3),
        .valid(audio_data_valid_2)
    );

    assign audio_data_valid_1 = audio_data_valid_0;
    assign audio_data_valid_3 = audio_data_valid_2;

    ///////////////////////////////////////////////////////
    //// I2S Encoder Instance
    ///////////////////////////////////////////////////////

    i2s_encoder i2s_encoder_inst (
        .clk(clk),
        .rst_n(rst_n),
        .i2s_bclk(i2so_ck),
        .i2s_ws(i2so_ws),
        .i2s_sdata(i2so_ad),
        .left_data(audio_data_out_0),
        .right_data(audio_data_out_1),
        .left_valid(audio_data_out_valid_0),
        .right_valid(audio_data_out_valid_1)
    );

    ///////////////////////////////////////////////////////
    //// ADAT Encoder Instance
    ///////////////////////////////////////////////////////

    adat_encoder_6ch adat_encoder_inst (
        .clk_bit(clk),
        .rst_n(rst_n),
        .ch0_data(audio_data_adat0),
        .ch0_valid(audio_data_adat0_valid),
        .ch1_data(audio_data_adat1),
        .ch1_valid(audio_data_adat1_valid),
        .ch2_data(audio_data_adat2),
        .ch2_valid(audio_data_adat2_valid),
        .ch3_data(audio_data_adat3),
        .ch3_valid(audio_data_adat3_valid),
        .ch4_data(audio_data_0),
        .ch4_valid(audio_data_valid_0),
        .ch5_data(audio_data_1),
        .ch5_valid(audio_data_valid_1),
        .adat_out(opt_drive)
    );

    ///////////////////////////////////////////////////////
    //// SPI Configuration Interface
    ///////////////////////////////////////////////////////

    // Configuration registers for routing and processing
    logic [15:0] config_reg;

    logic [1:0] route_output;

    logic [2:0]  comp_thresh0;  
    logic [1:0]  comp_speed0;    
    logic [1:0]  comp_ratio0;    
    logic [1:0]  exciter_freq0;  
    logic [2:0]  exciter_drive0; 
    logic        comp_bypass0_b;   
    logic        exciter_bypass0_b;

    logic [2:0]  comp_thresh1;  
    logic [1:0]  comp_speed1;    
    logic [1:0]  comp_ratio1;    
    logic [1:0]  exciter_freq1;  
    logic [2:0]  exciter_drive1; 
    logic        comp_bypass1_b;   
    logic        exciter_bypass1_b;

    assign route_output = config_reg[1:0];
    assign comp_thresh0 = config_reg[4:2];
    assign comp_speed0 = config_reg[6:5];
    assign comp_ratio0 = config_reg[8:7];
    assign exciter_freq0 = config_reg[10:9];
    assign exciter_drive0 = config_reg[13:11];
    assign comp_bypass0_b = config_reg[15];
    assign exciter_bypass0_b = config_reg[15];

    spi_regfile spi_regfile_inst (
        .clk(clk),
        .rst_n(rst_n),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_cs(spi_cs),
        .spi_miso(spi_miso),
        .config_reg(config_reg)
    ); 

    ///////////////////////////////////////////////////////
    //// Digital Signal Processors
    ///////////////////////////////////////////////////////

    dsp dsp_inst0 (
        .clk(clk),
        .rst_n(rst_n),

        .ch0_data_in(audio_data_0),
        .ch0_valid_in(audio_data_valid_0),
        .ch1_data_in(audio_data_1),
        .ch1_valid_in(audio_data_valid_1),

        .ch0_data_out(audio_data_adat0),
        .ch0_valid_out(audio_data_adat0_valid),
        .ch1_data_out(audio_data_adat1),
        .ch1_valid_out(audio_data_adat1_valid),
        
        .comp_thresh(comp_thresh0),   
        .comp_speed(comp_speed0),    
        .comp_ratio(comp_ratio0),    
        .exciter_freq(exciter_freq0),  
        .exciter_drive(exciter_drive0), 
        .comp_bypass_b(comp_bypass0_b),   
        .exciter_bypass_b(exciter_bypass0_b)
    );

    ///////////////////////////////////////////////////////
    //// Audio Routing Matrix
    ///////////////////////////////////////////////////////

    assign audio_data_adat2 = audio_data_2;
    assign audio_data_adat3 = audio_data_3;
    assign audio_data_adat2_valid = audio_data_valid_2;
    assign audio_data_adat3_valid = audio_data_valid_3;

    always_comb begin
        case (route_output)
            2'b00: begin
                audio_data_out_0 = audio_data_adat0;
                audio_data_out_1 = audio_data_adat1;
                audio_data_out_valid_0 = audio_data_adat0_valid;
                audio_data_out_valid_1 = audio_data_adat1_valid;
            end
            2'b01: begin
                audio_data_out_0 = audio_data_adat2;
                audio_data_out_1 = audio_data_adat3;
                audio_data_out_valid_0 = audio_data_adat2_valid;
                audio_data_out_valid_1 = audio_data_adat3_valid;
            end
            2'b10: begin
                audio_data_out_0 = audio_data_0;
                audio_data_out_1 = audio_data_1;
                audio_data_out_valid_0 = audio_data_valid_0;
                audio_data_out_valid_1 = audio_data_valid_1;
            end
            2'b11: begin
                audio_data_out_0 = audio_data_adat0 + audio_data_adat2;
                audio_data_out_1 = audio_data_adat1 + audio_data_adat3;
                audio_data_out_valid_0 = audio_data_adat0_valid & audio_data_adat2_valid;
                audio_data_out_valid_1 = audio_data_adat1_valid & audio_data_adat3_valid;
            end
            default: begin
                audio_data_out_0 = audio_data_adat0;
                audio_data_out_1 = audio_data_adat1;
                audio_data_out_valid_0 = audio_data_adat0_valid;
                audio_data_out_valid_1 = audio_data_adat1_valid;
            end
        endcase
    end

    ///////////////////////////////////////////////////////
    //// Clock Divider
    ///////////////////////////////////////////////////////

    clock_divider_256 clock_divider_256_inst (
        .clk_in(clk),
        .rst_n(rst_n),
        .clk_out(sampling_clock)
    );




endmodule