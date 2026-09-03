
/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : spi_regfile.sv
 *  Project     : LYRA Audio System
 *  Module      : spi_regfile
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.0
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Configuration register file with SPI interface for LYRA (32 bit)
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/

module spi_regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        spi_sck,
    input  logic        spi_mosi,
    input  logic        spi_cs,        // Active-low Chip Select (~CS)
    output logic        spi_miso,
    output logic [31:0] config_reg
);

    // MISO unused for write-only operations
    assign spi_miso = 1'b0;

    // --- Resynchronizers (2-FF chain for CDC) ---
    logic [1:0] cs_q;
    logic [2:0] sck_q;
    logic [1:0] mosi_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_q   <= 2'b11; // Inactive high
            sck_q  <= 3'b000;
            mosi_q <= 2'b00;
        end else begin
            cs_q   <= {cs_q[0],   spi_cs};
            sck_q  <= {sck_q[1:0], spi_sck};
            mosi_q <= {mosi_q[0],  spi_mosi};
        end
    end

    // SCK rising edge detection and active CS evaluation
    wire sck_rising = (sck_q[2:1] == 2'b01);
    wire cs_active  = ~cs_q[1];

    // --- Shift Register & Counter ---
    logic [31:0] shift_reg;
    logic [4:0]  bit_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt    <= '0;
            shift_reg  <= '0;
            config_reg <= '0;
        end else begin
            if (cs_active) begin
                if (sck_rising) begin
                    shift_reg <= {shift_reg[30:0], mosi_q[1]};
                    bit_cnt   <= bit_cnt + 1'b1;

                    // Update output register directly on 32nd bit arrival
                    if (bit_cnt == 5'd31) begin
                        config_reg <= {shift_reg[30:0], mosi_q[1]};
                    end
                end
            end else begin
                bit_cnt <= '0; // Reset counter when CS becomes inactive
            end
        end
    end

endmodule