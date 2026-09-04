/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : clock_divider_256.sv
 *  Project     : LYRA Audio System
 *  Module      : clock_divider_256
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 2.0 (Area-Optimized Architecture)
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Clock divider to the sampling frequency
 *******************************************************************************/

module clock_divider_256 (
    input  wire clk_in,
    input  wire rst_n,
    output reg  clk_out
);

    reg [7:0] count;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n)
            count <= 8'b0;
        else
            count <= count + 8'd1;
    end

    always @(*) begin
        clk_out = count[7];
    end

endmodule