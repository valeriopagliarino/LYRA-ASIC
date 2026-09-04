/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : i2s_decoder.sv
 *  Project     : LYRA Audio System
 *  Module      : i2s_decoder
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 2.0 (Area-Optimized Architecture)
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Stereo I2S-to-Parallel decoder module optimized for ASIC synthesis area.
 *    Decodes 16-bit 44.1 kHz audio using an 11.2896 MHz system clock.
 *******************************************************************************/
module i2s_decoder (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        i2s_bclk,
    input  logic        i2s_ws,
    input  logic        i2s_sdata,

    input  logic        mute,

    output logic [15:0] left_data,
    output logic [15:0] right_data,
    output logic        valid
);

    // ============================================================
    // Input synchronizers
    // ============================================================

    logic [1:0] bclk_sync;
    logic [1:0] ws_sync;
    logic [1:0] sdata_sync;

    logic bclk_prev;

    wire bclk_rising = bclk_sync[1] && !bclk_prev;


    // ============================================================
    // Receiver state
    // ============================================================

    logic [15:0] shift_reg;

    // Number of bits already captured:
    //
    // 0  = no bits
    // 1  = MSB captured
    // ...
    // 16 = complete word
    //
    logic [4:0] bit_cnt;

    // Current I2S channel:
    //
    // 0 = LEFT
    // 1 = RIGHT
    //
    logic current_ws;

    // Set after WS transition.
    // The next BCLK contains the MSB.
    logic wait_first_bit;

    // Indicates that a LEFT word is ready and we are
    // waiting for the corresponding RIGHT word.
    logic left_ready;


    // ============================================================
    // Synchronizers
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bclk_sync  <= 2'b00;
            ws_sync    <= 2'b00;
            sdata_sync <= 2'b00;
            bclk_prev  <= 1'b0;
        end
        else begin
            bclk_sync  <= {bclk_sync[0], i2s_bclk};
            ws_sync    <= {ws_sync[0], i2s_ws};
            sdata_sync <= {sdata_sync[0], i2s_sdata};

            bclk_prev <= bclk_sync[1];
        end
    end


    // ============================================================
    // I2S decoder
    // ============================================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            left_data      <= 16'h0000;
            right_data     <= 16'h0000;
            valid          <= 1'b0;

            shift_reg      <= 16'h0000;
            bit_cnt        <= 5'd0;

            // IMPORTANT:
            //
            // BFM starts with WS = 0.
            //
            // Initializing this to 1 forces the first WS=0
            // to be detected as a channel transition.
            //
            current_ws     <= 1'b1;

            wait_first_bit <= 1'b0;
            left_ready     <= 1'b0;

        end
        else begin

            // valid is a one-clock pulse
            valid <= 1'b0;


            // ====================================================
            // BCLK rising edge
            // ====================================================

            if (bclk_rising) begin


                // =================================================
                // WS transition
                // =================================================
                //
                // Philips I2S:
                //
                //       WS transition
                //            |
                //            | delay
                //            v
                //       MSB on next BCLK
                //
                // Therefore SDATA is NOT sampled here.
                //
                // =================================================

                if (ws_sync[1] != current_ws) begin

                    current_ws <= ws_sync[1];

                    shift_reg <= 16'h0000;
                    bit_cnt   <= 5'd0;

                    wait_first_bit <= 1'b1;
                end


                // =================================================
                // First data bit = MSB
                // =================================================

                else if (wait_first_bit) begin

                    shift_reg <= {
                        15'b0,
                        sdata_sync[1]
                    };

                    bit_cnt <= 5'd1;

                    wait_first_bit <= 1'b0;
                end


                // =================================================
                // Remaining data bits
                // =================================================

                else if (bit_cnt < 5'd16) begin

                    shift_reg <= {
                        shift_reg[14:0],
                        sdata_sync[1]
                    };


                    // =============================================
                    // 16th bit
                    // =============================================

                    if (bit_cnt == 5'd15) begin

                        bit_cnt <= 5'd16;


                        // =========================================
                        // LEFT channel
                        // =========================================

                        if (current_ws == 1'b0) begin

                            if (mute)
                                left_data <= 16'h0000;
                            else
                                left_data <= {
                                    shift_reg[14:0],
                                    sdata_sync[1]
                                };

                            left_ready <= 1'b1;
                        end


                        // =========================================
                        // RIGHT channel
                        // =========================================

                        else begin

                            if (mute)
                                right_data <= 16'h0000;
                            else
                                right_data <= {
                                    shift_reg[14:0],
                                    sdata_sync[1]
                                };


                            // Complete stereo sample
                            if (left_ready) begin
                                valid      <= 1'b1;
                                left_ready <= 1'b0;
                            end
                        end
                    end

                    else begin

                        bit_cnt <= bit_cnt + 5'd1;

                    end
                end
            end
        end
    end

endmodule