"""
Standard Philips I2S bus functional model (driver + monitor) for cocotb.

Convention implemented here (the "standard" I2S / Philips format):
  * BCLK (bit clock) free-running, 2 * word_length * Fs, 50% duty cycle.
  * WS (word select / LRCLK): low = left channel, high = right channel.
  * Data: MSB first, 2's complement, with ONE bit-clock delay between the
    WS edge and the first (MSB) bit of the new word - i.e. the bit
    transmitted right at the WS transition still belongs to the word
    that is ending, and the new word's MSB appears on the *next* BCLK
    cycle. This is the classic Philips/I2S alignment (as opposed to
    "left-justified", which has no such delay).
  * Data changes on the BCLK falling edge and is sampled by the
    receiver on the BCLK rising edge.

NOTE: i2s_decoder.sv / i2s_encoder.sv were not provided with this
project, so this convention is an assumption based on the de-facto I2S
standard, as requested. If your RTL instead expects left-justified
framing, set MSB_DELAY = 0 below.
"""

"""
I2S Bus Functional Model (BFM) for LYRA testbench.
Handles bitstream generation, driving, and passive monitoring.
"""

import cocotb
from cocotb.triggers import Timer, RisingEdge


def build_i2s_bitstreams(left_samples, right_samples):
    """Generates I2S WS and DATA bit sequences with MSB-first bit order
    and 1 BCLK delay slot post-WS transition."""
    ws_bits = []
    data_bits = []

    for l_s, r_s in zip(left_samples, right_samples):
        l_val = int(l_s) & 0xFFFF
        r_val = int(r_s) & 0xFFFF

        # --- Left Channel (WS = 0) ---
        ws_bits.append(0)
        data_bits.append(0)

        for bit in range(15, -1, -1):
            ws_bits.append(0)
            data_bits.append((l_val >> bit) & 1)

        # --- Right Channel (WS = 1) ---
        ws_bits.append(1)
        data_bits.append(0)

        for bit in range(15, -1, -1):
            ws_bits.append(1)
            data_bits.append((r_val >> bit) & 1)

    return ws_bits, data_bits


async def drive_i2s_bus(bus_setter, ws_bits, data_bits, half_period_ns):
    """Drives I2S bus signals at the configured clock period."""
    for ws, data in zip(ws_bits, data_bits):
        bus_setter(0, ws, data)
        await Timer(half_period_ns, units="ns")
        bus_setter(1, ws, data)
        await Timer(half_period_ns, units="ns")


async def monitor_i2s_bus(clk, uio_out, callback):
    """Monitors serial I2S output bus using system clock edge detection."""
    shift_reg = 0
    bit_cnt = 0
    ws_latched = 1
    prev_bclk = 0

    while True:
        # Sincronizzazione sul clock di sistema
        await RisingEdge(clk)

        try:
            uio_value = int(uio_out.value)

            # uio_out mapping:
            # [7] = vu_meter_mon
            # [6] = i2so_ws
            # [5] = i2so_ad
            # [4] = i2so_ck
            # [3] = spi_miso

            curr_bclk = (uio_value >> 4) & 1
            curr_ws = (uio_value >> 6) & 1
            curr_sdata = (uio_value >> 5) & 1

        except ValueError:
            continue

        # Rilevamento manuale del fronte di salita di BCLK
        if curr_bclk == 1 and prev_bclk == 0:
            if curr_ws != ws_latched:
                ws_latched = curr_ws
                bit_cnt = 0
                shift_reg = 0

            elif bit_cnt < 16:
                shift_reg = ((shift_reg << 1) | curr_sdata) & 0xFFFF
                bit_cnt += 1

                if bit_cnt == 16:
                    signed_val = (
                        shift_reg
                        if shift_reg < 0x8000
                        else shift_reg - 0x10000
                    )
 
                    ch_label = "L" if ws_latched == 0 else "R"
                    callback(ch_label, signed_val)

        prev_bclk = curr_bclk