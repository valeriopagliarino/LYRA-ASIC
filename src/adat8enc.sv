/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : adat_encoder_6ch.sv
 *  Project     : LYRA Audio System
 *  Module      : adat_encoder_6ch
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 2.3
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    6-channel ADAT (Alesis Digital Audio Tape) encoder module.
 *    Converts 6 channels of 16-bit audio samples into a serialized ADAT
 *    bitstream with NRZI encoding, suitable for driving an optical TOSLINK
 *    transmitter. Left-justifies 16-bit PCM audio into 24-bit ADAT frames.
 *******************************************************************************/

module adat_encoder_6ch (
    input  logic               clk_bit,     // ADAT bit clock = 256 * Fs (11.2896 MHz @ 44.1 kHz)
    input  logic               rst_n,       // Asynchronous active-low reset

    // Audio input channels - Explicitly signed 16-bit
    input  logic signed [15:0] ch0_data,
    input  logic               ch0_valid,
    input  logic signed [15:0] ch1_data,
    input  logic               ch1_valid,
    input  logic signed [15:0] ch2_data,
    input  logic               ch2_valid,
    input  logic signed [15:0] ch3_data,
    input  logic               ch3_valid,
    input  logic signed [15:0] ch4_data,
    input  logic               ch4_valid,
    input  logic signed [15:0] ch5_data,
    input  logic               ch5_valid,

    output logic               adat_out,    // NRZI bitstream output (to optical driver)
    output logic               frame_sync   // 1 clk_bit pulse at the start of every frame
);

    // -------------------------------------------------------------------
    // Structural frame parameters with explicit 4-bit widths
    // -------------------------------------------------------------------
    localparam logic [3:0] SYNC_LEN  = 4'd11;       // Sync pattern length (bits)
    localparam logic [3:0] SYNC_LAST = SYNC_LEN - 4'd1; // 10
    localparam logic [3:0] NUM_CH    = 4'd8;        // Total audio channels per frame
    localparam logic [3:0] REAL_CH   = 4'd6;        // Active audio channels

    typedef enum logic [1:0] {
        ST_SYNC = 2'b00,
        ST_USER = 2'b01,
        ST_DATA = 2'b10
    } state_t;

    // -------------------------------------------------------------------
    // Frame generator state registers
    // -------------------------------------------------------------------
    state_t          state;
    logic [3:0]      sync_cnt;    // 0..10  position within sync pattern
    logic [3:0]      ch_idx;      // 0..7   audio channel index
    logic [2:0]      nibble_idx;  // 0..5   current nibble within channel
    logic [2:0]      bitpos;      // 0..4   0-3 = data bit, 4 = stuffing bit

    logic            nrzi_level;  // Current output line level
    logic            next_bit;    // Raw pre-NRZI bit

    // -------------------------------------------------------------------
    // Per-channel input packing
    // -------------------------------------------------------------------
    logic signed [15:0] ch_data_in [0:5];
    logic               ch_valid_in[0:5];

    assign ch_data_in[0]  = ch0_data;
    assign ch_data_in[1]  = ch1_data;
    assign ch_data_in[2]  = ch2_data;
    assign ch_data_in[3]  = ch3_data;
    assign ch_data_in[4]  = ch4_data;
    assign ch_data_in[5]  = ch5_data;

    assign ch_valid_in[0] = ch0_valid;
    assign ch_valid_in[1] = ch1_valid;
    assign ch_valid_in[2] = ch2_valid;
    assign ch_valid_in[3] = ch3_valid;
    assign ch_valid_in[4] = ch4_valid;
    assign ch_valid_in[5] = ch5_valid;

    // -------------------------------------------------------------------
    // Shadow buffer and active buffer
    // -------------------------------------------------------------------
    logic [1:0]         v_sync   [0:5];
    logic signed [15:0] ch_shadow[0:5];
    logic signed [15:0] ch_active[0:5];

    genvar gi;
    generate
        for (gi = 0; gi < 6; gi++) begin : g_ch_capture
            always_ff @(posedge clk_bit or negedge rst_n) begin
                if (!rst_n) begin
                    v_sync[gi]    <= 2'b00;
                    ch_shadow[gi] <= 16'sh0000;
                end else begin
                    v_sync[gi] <= {v_sync[gi][0], ch_valid_in[gi]};
                    if (v_sync[gi][0] & ~v_sync[gi][1])
                        ch_shadow[gi] <= ch_data_in[gi];
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------
    // Combinational bit-select logic
    // -------------------------------------------------------------------
    logic [4:0]  local_bit_idx;
    logic [23:0] adat_payload_24;

    always_comb begin
        // Index within the 24-bit ADAT frame payload (0 to 23)
        local_bit_idx = {2'b00, nibble_idx} * 5'd4 + {3'b000, bitpos[1:0]};

        // Left-justify 16-bit signed audio into bits [23:8] with zero padding in [7:0]
        if (ch_idx < REAL_CH) begin
            adat_payload_24 = {ch_active[ch_idx], 8'h00};
        end else begin
            adat_payload_24 = 24'h000000; // Unused channels (6 and 7) transmitted as zero
        end

        unique case (state)
            ST_SYNC: begin
                next_bit = (sync_cnt == SYNC_LAST) ? 1'b1 : 1'b0;
            end

            ST_USER: begin
                // User field: 4 bits of '0' + 1 stuffing bit '1'
                next_bit = (bitpos == 3'd4) ? 1'b1 : 1'b0;
            end

            ST_DATA: begin
                if (bitpos == 3'd4) begin
                    next_bit = 1'b1; // Mandatory ADAT bit stuffing
                end else begin
                    // Transmit MSB first from the 24-bit aligned frame (bit 23 down to 0)
                    next_bit = adat_payload_24[5'd23 - local_bit_idx];
                end
            end

            default: next_bit = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------
    // Sequential state machine (Frame order: SYNC -> USER -> DATA)
    // -------------------------------------------------------------------
    always_ff @(posedge clk_bit or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_SYNC;
            sync_cnt     <= 4'd0;
            ch_idx       <= 4'd0;
            nibble_idx   <= 3'd0;
            bitpos       <= 3'd0;
            nrzi_level   <= 1'b0;
            frame_sync   <= 1'b0;
            for (int i = 0; i < 6; i++)
                ch_active[i] <= 16'sh0000;
        end else begin
            frame_sync <= 1'b0;

            // ADAT NRZI encoding: '1' = toggle output state, '0' = hold current state
            nrzi_level <= nrzi_level ^ next_bit;

            unique case (state)

                // 1. SYNC PHASE (11 bits)
                ST_SYNC: begin
                    if (sync_cnt == SYNC_LAST) begin
                        state    <= ST_USER;
                        sync_cnt <= 4'd0;
                        bitpos   <= 3'd0;
                    end else begin
                        sync_cnt <= sync_cnt + 4'd1;
                    end
                end

                // 2. USER NIBBLE PHASE (5 bits)
                ST_USER: begin
                    if (bitpos < 3'd4) begin
                        bitpos <= bitpos + 3'd1;
                    end else begin
                        state      <= ST_DATA;
                        bitpos     <= 3'd0;
                        ch_idx     <= 4'd0;
                        nibble_idx <= 3'd0;
                    end
                end

                // 3. AUDIO DATA PHASE (8 channels * 30 bits = 240 bits total)
                ST_DATA: begin
                    if (bitpos < 3'd4) begin
                        bitpos <= bitpos + 3'd1;
                    end else begin
                        bitpos <= 3'd0;

                        if (nibble_idx < 3'd5) begin
                            nibble_idx <= nibble_idx + 3'd1;
                        end else begin
                            nibble_idx <= 3'd0;
                            if (ch_idx < (NUM_CH - 4'd1)) begin
                                ch_idx <= ch_idx + 4'd1;
                            end else begin
                                // End of frame -> Loop back to SYNC
                                state      <= ST_SYNC;
                                sync_cnt   <= 4'd0;
                                frame_sync <= 1'b1;

                                for (int i = 0; i < 6; i++)
                                    ch_active[i] <= ch_shadow[i];
                            end
                        end
                    end
                end

            endcase
        end
    end

    assign adat_out = nrzi_level;

endmodule