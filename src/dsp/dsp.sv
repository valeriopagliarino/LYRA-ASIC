
/*******************************************************************************
 *  L Y R A   A U D I O   A D A T   I N T E R F A C E
 *******************************************************************************
 *  File        : dsp.sv
 *  Project     : LYRA Audio System
 *  Module      : dsp
 *  Author      : Valerio Pagliarino
 *  Created     : 2026
 *  Revision    : 1.0
 *  License     : Apache-2.0 (SPDX-License-Identifier: Apache-2.0)
 *
 *  Copyright (c) 2026 Valerio Pagliarino. All rights reserved.
 *------------------------------------------------------------------------------
 *  DESCRIPTION:
 *    Audio area-optimized DSP for LYRA.
 *------------------------------------------------------------------------------
 *  REVISION HISTORY:
 *    Ver   Date        Author           Description
 *    1.0   2026-09-03  V. Pagliarino    Initial release
 *******************************************************************************/


module dsp (
        input  logic clk,
        input  logic rst_n,
        input  logic [15:0] audio_data_in,
        input  logic audio_data_valid_in,
        output logic [15:0] audio_data_out,
        output logic audio_data_valid_out
    );

    assign audio_data_out = audio_data_in; // Pass-through for now
    assign audio_data_valid_out = audio_data_valid_in;

endmodule