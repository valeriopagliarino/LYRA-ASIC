/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : adat_encoder_4ch.sv
 *  Project     : LYRA Audio System
 *  Module      : adat_encoder_4ch
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.0
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    4-channel ADAT (Alesis Digital Audio Tape) encoder module.
 *    Converts 4 channels of 16-bit audio samples into a serialized ADAT bitstream
 *    with NRZI encoding, suitable for driving an optical TOSLINK transmitter.
 *    The module handles the ADAT frame structure, including sync pattern,
 *    channel data, and user nibble, ensuring proper timing and atomic sample
 *    updates at the end of each frame.
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/

// =============================================================================
// adat_encoder_4ch.sv
//
// Encoder ottico ADAT (Alesis Digital Audio Tape) - 8 canali totali,
// dei quali vengono utilizzati i primi 4 (canali 5-8 trasmessi a zero/silenzio).
//
// FORMATO FRAME ADAT (256 bit per frame, uno per ogni periodo di campionamento):
//
//   [ SYNC: 10 zeri + 1 uno ]  (11 bit)
//   [ CH0: 6 nibble da 4 bit, ognuno seguito da 1 bit di stuffing = '1' ]  (30 bit)
//   [ CH1 ... ]                                                          (30 bit)
//   ...
//   [ CH7 ... ]                                                          (30 bit)
//   [ USER NIBBLE: 4 bit + 1 bit di stuffing ]                           (5 bit)
//
//   Totale: 11 + 8*30 + 5 = 256 bit/frame
//
// Il bit di stuffing forzato a '1' dopo ogni nibble garantisce che nei dati
// non possano mai comparire piu' di 4 zeri consecutivi: questo rende il pattern
// di sync (10 zeri consecutivi) univoco e riconoscibile dal ricevitore per il
// recovery del clock.
//
// Ogni bit del frame viene poi codificato in NRZI prima di uscire sulla linea
// ottica:
//     bit dato = 0  -> transizione di livello (toggle)
//     bit dato = 1  -> nessuna transizione (livello mantenuto)
//
// CLOCK RICHIESTO (clk_bit):
//     clk_bit = 256 * Fs
//     Fs = 44.1 kHz  ->  clk_bit = 11.2896 MHz
//   Questo clock va generato esternamente (PLL/MMCM) con la precisione
//   necessaria per un trasmettitore ottico TOSLINK; il modulo non lo deriva
//   internamente.
//
// USCITA:
//     adat_out : bitstream NRZI, pronta a pilotare un driver ottico TOSLINK.
//                ATTENZIONE alla polarita': alcuni driver ottici si aspettano
//                '1' = LED acceso, altri il contrario. Se il flusso ottico
//                risultasse invertito rispetto a quanto atteso dal ricevitore,
//                aggiungere un semplice invertitore sul segnale adat_out.
//
// INGRESSI CAMPIONI:
//     chN_data  [15:0] : campione audio a 16 bit, canale N (N = 0..3)
//     chN_valid        : impulso (anche di 1 solo ciclo) che indica che
//                        chN_data e' un nuovo campione valido. Deve arrivare
//                        una volta ogni periodo di campionamento (~1/44.1kHz).
//                        Il dato deve restare stabile per almeno un ciclo di
//                        clk_bit intorno all'impulso di valid.
//
// I campioni vengono catturati in un buffer "shadow" non appena arriva il
// relativo valid, e vengono trasferiti nel buffer "attivo" (quello davvero
// trasmesso) in modo atomico alla fine di ogni frame ADAT, cosi' da evitare
// che un frame venga trasmesso con dati "strappati" a meta'.
// =============================================================================

module adat_encoder_4ch (
    input  logic        clk_bit,     // clock ADAT = 256 * Fs (es. 11.2896 MHz @ 44.1 kHz)
    input  logic        rst_n,       // reset asincrono attivo basso

    // Canali audio in ingresso (solo i primi 4 vengono usati)
    input  logic [15:0] ch0_data,
    input  logic         ch0_valid,
    input  logic [15:0] ch1_data,
    input  logic         ch1_valid,
    input  logic [15:0] ch2_data,
    input  logic         ch2_valid,
    input  logic [15:0] ch3_data,
    input  logic         ch3_valid,

    output logic        adat_out,    // bitstream NRZI in uscita (verso driver ottico)
    output logic        frame_sync   // impulso di 1 ciclo di clk_bit all'inizio di ogni frame
);

    // -------------------------------------------------------------------
    // Parametri strutturali del frame ADAT
    // -------------------------------------------------------------------
    localparam int SYNC_LEN  = 11;          // lunghezza pattern di sync (bit)
    localparam int SYNC_LAST = SYNC_LEN-1;  // indice dell'ultimo bit di sync (quello a '1')
    localparam int NUM_CH    = 8;           // canali audio totali nel frame ADAT

    typedef enum logic {ST_SYNC = 1'b0, ST_DATA = 1'b1} state_t;

    // -------------------------------------------------------------------
    // Stato del generatore di frame
    // -------------------------------------------------------------------
    state_t          state;
    logic [3:0]      sync_cnt;    // 0..10   posizione nel pattern di sync
    logic [3:0]      ch_idx;      // 0..8    0-7 = canali audio, 8 = nibble utente
    logic [2:0]      nibble_idx;  // 0..5    nibble corrente all'interno del canale
    logic [2:0]      bitpos;      // 0..4    0-3 = bit dato nel nibble, 4 = bit di stuffing

    logic            nrzi_level;  // livello di linea corrente (stato NRZI)
    logic            next_bit;    // valore "raw" (pre-NRZI) del bit che sta per uscire

    // Nibble utente: non utilizzato in questa implementazione, sempre a zero.
    // (punto di estensione futuro se serve trasportare informazioni ausiliarie)
    logic [3:0]      user_nibble;
    assign user_nibble = 4'b0000;

    // Buffer "attivo": e' quello effettivamente serializzato nel frame corrente
    logic [23:0] sample24_active [0:NUM_CH-1];

    // -------------------------------------------------------------------
    // Sincronizzazione ingressi valid + cattura campioni (buffer "shadow")
    // -------------------------------------------------------------------
    logic [1:0] v0_sync, v1_sync, v2_sync, v3_sync;
    logic [15:0] ch0_buf, ch1_buf, ch2_buf, ch3_buf;

    always_ff @(posedge clk_bit or negedge rst_n) begin
        if (!rst_n) begin
            v0_sync <= 2'b00;
            v1_sync <= 2'b00;
            v2_sync <= 2'b00;
            v3_sync <= 2'b00;
            ch0_buf <= 16'h0000;
            ch1_buf <= 16'h0000;
            ch2_buf <= 16'h0000;
            ch3_buf <= 16'h0000;
        end else begin
            v0_sync <= {v0_sync[0], ch0_valid};
            v1_sync <= {v1_sync[0], ch1_valid};
            v2_sync <= {v2_sync[0], ch2_valid};
            v3_sync <= {v3_sync[0], ch3_valid};

            // Fronte di salita del valid sincronizzato -> cattura il campione
            if (v0_sync[0] & ~v0_sync[1]) ch0_buf <= ch0_data;
            if (v1_sync[0] & ~v1_sync[1]) ch1_buf <= ch1_data;
            if (v2_sync[0] & ~v2_sync[1]) ch2_buf <= ch2_data;
            if (v3_sync[0] & ~v3_sync[1]) ch3_buf <= ch3_data;
        end
    end

    // -------------------------------------------------------------------
    // Decodifica combinatoria del bit corrente da trasmettere,
    // in funzione della sola posizione nello stato (Mealy-like, ma pulito)
    // -------------------------------------------------------------------
    always_comb begin
        unique case (state)
            ST_SYNC: begin
                next_bit = (sync_cnt == SYNC_LAST) ? 1'b1 : 1'b0;
            end
            ST_DATA: begin
                if (ch_idx < NUM_CH) begin
                    if (bitpos < 3'd4)
                        // 24 bit del campione, MSB per primo
                        next_bit = sample24_active[ch_idx][23 - (nibble_idx*4 + bitpos)];
                    else
                        next_bit = 1'b1; // bit di stuffing
                end else begin
                    // ch_idx == NUM_CH -> nibble utente finale del frame
                    if (bitpos < 3'd4)
                        next_bit = user_nibble[3-bitpos];
                    else
                        next_bit = 1'b1; // bit di stuffing
                end
            end
            default: next_bit = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------
    // Macchina a stati sequenziale: avanzamento posizione nel frame,
    // codifica NRZI e latch del buffer attivo al confine di frame
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
            for (int i = 0; i < NUM_CH; i++)
                sample24_active[i] <= 24'h000000;
        end else begin
            frame_sync <= 1'b0; // di default basso, va a 1 solo per un ciclo (vedi sotto)

            // Codifica NRZI del bit corrente: '0' = toggle, '1' = mantiene livello
            nrzi_level <= next_bit ? nrzi_level : ~nrzi_level;

            unique case (state)

                // --------------------- FASE DI SYNC ---------------------
                ST_SYNC: begin
                    if (sync_cnt == SYNC_LAST) begin
                        state      <= ST_DATA;
                        sync_cnt   <= 4'd0;
                        ch_idx     <= 4'd0;
                        nibble_idx <= 3'd0;
                        bitpos     <= 3'd0;
                    end else begin
                        sync_cnt <= sync_cnt + 4'd1;
                    end
                end

                // --------------------- FASE DATI ---------------------
                ST_DATA: begin
                    if (bitpos < 3'd4) begin
                        // ancora un bit dato da inviare in questo nibble
                        bitpos <= bitpos + 3'd1;
                    end else begin
                        // bit di stuffing appena inviato -> avanza nibble/canale
                        bitpos <= 3'd0;

                        if (ch_idx < NUM_CH) begin
                            if (nibble_idx == 3'd5) begin
                                nibble_idx <= 3'd0;
                                ch_idx     <= ch_idx + 4'd1;
                            end else begin
                                nibble_idx <= nibble_idx + 3'd1;
                            end
                        end else begin
                            // fine del nibble utente -> fine frame
                            state      <= ST_SYNC;
                            sync_cnt   <= 4'd0;
                            ch_idx     <= 4'd0;
                            frame_sync <= 1'b1; // segnala inizio nuovo frame

                            // Trasferimento atomico buffer shadow -> buffer attivo
                            // Canali 0-3: dati reali, allineati a sinistra su 24 bit
                            sample24_active[0] <= {ch0_buf, 8'h00};
                            sample24_active[1] <= {ch1_buf, 8'h00};
                            sample24_active[2] <= {ch2_buf, 8'h00};
                            sample24_active[3] <= {ch3_buf, 8'h00};
                            // Canali 4-7: non utilizzati -> silenzio
                            sample24_active[4] <= 24'h000000;
                            sample24_active[5] <= 24'h000000;
                            sample24_active[6] <= 24'h000000;
                            sample24_active[7] <= 24'h000000;
                        end
                    end
                end

            endcase
        end
    end

    assign adat_out = nrzi_level;

endmodule