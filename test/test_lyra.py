"""
cocotb testbench for tt_um_lyra (LYRA audio ADAT interface).

Workflow:
  1. Generate the 11.2896 MHz system clock (`clk`) and reset the DUT.
  2. Program the SPI config register (16-bit shift register, MSB first).
  3. Stream a stereo 44.1 kHz / 16-bit PCM wav file onto BOTH I2S input
     buses simultaneously and identically (i2s0 -> ch0/ch1,
     i2s1 -> ch2/ch3), as requested.
  4. Passively monitor the I2S output (i2so_ck/ad/ws) and decode the
     8-channel ADAT optical output (opt_drive), writing:
       - i2s_out.wav      (I2S monitor output, stereo)
       - adat_ch0_1.wav   (ADAT channels 0,1)
       - adat_ch2_3.wav   (ADAT channels 2,3)
       - adat_ch4_5.wav   (ADAT channels 4,5)
       - adat_ch6_7.wav   (ADAT channels 6,7 - expected silent, see adat_bfm.py)

Pin mapping used below (from project.sv padring):
  ui_in : [7]=mute_23 [6]=mute_01 [5]=i2s1_ws [4]=i2s1_ad [3]=i2s1_ck
           [2]=i2s0_ws [1]=i2s0_ad [0]=i2s0_ck
  uio_in: [2]=spi_cs [1]=spi_mosi [0]=spi_sck   (bits 3..7 unused as inputs)
  uio_out:[7]=vu_meter_mon [6]=i2so_ws [5]=i2so_ad [4]=i2so_ck [3]=spi_miso
  uo_out: [6]=vu_meter_clip [5:2]=vu_meter_3..0  [1:0]=opt_drive (x2)
"""

import os
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from i2s_bfm import build_i2s_bitstreams, drive_i2s_bus, monitor_i2s_bus
from adat_bfm import AdatDecoder
from spi_bfm import spi_write16
from wav_io import read_wav_stereo16, WavStereoWriter

# LYRA system clock: 256 * 44100 Hz = 11.2896 MHz.
SYS_CLK_HZ = 11_289_600

SYS_CLK_PERIOD_PS = int(round(1e12 / SYS_CLK_HZ))
if SYS_CLK_PERIOD_PS % 2 != 0:
    SYS_CLK_PERIOD_PS += 1

I2S_BCLK_HZ = SYS_CLK_HZ // 8
I2S_HALF_PERIOD_NS = round((1e9 / I2S_BCLK_HZ) / 2, 3)


def _set_ui_in(dut, bclk, data, ws, mute01=0, mute23=0):
    val = (
        (bclk & 1)
        | ((data & 1) << 1)
        | ((ws & 1) << 2)
        | ((bclk & 1) << 3)
        | ((data & 1) << 4)
        | ((ws & 1) << 5)
        | ((mute01 & 1) << 6)
        | ((mute23 & 1) << 7)
    )
    dut.ui_in.value = val


def _set_uio_in(dut, sck, mosi, cs):
    val = (sck & 1) | ((mosi & 1) << 1) | ((cs & 1) << 2)
    dut.uio_in.value = val


@cocotb.test()
async def test_lyra_audio_path(dut):
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_PS, units="ps").start())

    # --- Reset Sequence ---
    dut.rst_n.value = 0
    dut.ena.value = 1
    _set_ui_in(dut, 0, 0, 0)
    _set_uio_in(dut, 0, 0, 1)
    await Timer(500, units="ns")
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 20)

    # --- Program Configuration Register via SPI ---
    route_output = 0b10  # Raw ch0/ch1 straight to I2S monitor output
    comp_thresh0 = 0
    comp_speed0 = 0
    comp_ratio0 = 0
    exciter_freq0 = 0
    exciter_drive0 = 0
    bypass_b = 1

    config_word = (
        (bypass_b << 15)
        | (exciter_drive0 << 11)
        | (exciter_freq0 << 9)
        | (comp_ratio0 << 7)
        | (comp_speed0 << 5)
        | (comp_thresh0 << 2)
        | route_output
    )

    await spi_write16(lambda sck, mosi, cs: _set_uio_in(dut, sck, mosi, cs), config_word)
    await ClockCycles(dut.clk, 20)

    # --- Load Input Audio ---
    in_wav = os.environ.get(
        "LYRA_INPUT_WAV", os.path.join(os.path.dirname(__file__), "input.wav")
    )
    left_full, right_full = read_wav_stereo16(in_wav)
    
    n_samples = min(500, len(left_full))
    left = left_full[:n_samples]
    right = right_full[:n_samples]

    dut._log.info(f"Streaming {n_samples} stereo samples from {in_wav}")

    ws_bits, data_bits = build_i2s_bitstreams(left, right)

    def bus_setter(bclk, ws, data):
        _set_ui_in(dut, bclk, data, ws)

    # --- Output Capture Setup ---
    os.makedirs("out", exist_ok=True)
    i2s_out = WavStereoWriter("out/i2s_out.wav")
    adat_pairs = {
        (0, 1): WavStereoWriter("out/adat_ch0_1.wav"),
        (2, 3): WavStereoWriter("out/adat_ch2_3.wav"),
        (4, 5): WavStereoWriter("out/adat_ch4_5.wav"),
        (6, 7): WavStereoWriter("out/adat_ch6_7.wav"),
    }

    _i2s_pending = {"L": None, "R": None}

    def on_i2s_word(channel, value):
        # Mappatura robusta canale L/R sia da formato stringa che intero
        ch_key = "L" if channel in ("L", "left", 0) else "R"
        _i2s_pending[ch_key] = value
        if _i2s_pending["L"] is not None and _i2s_pending["R"] is not None:
            i2s_out.push(_i2s_pending["L"], _i2s_pending["R"])
            _i2s_pending["L"] = None
            _i2s_pending["R"] = None

    cocotb.start_soon(
        monitor_i2s_bus(dut.clk, dut.uio_out[4], dut.uio_out[6], dut.uio_out[5], on_i2s_word)
    )

    adat = AdatDecoder(dut.clk, dut.uo_out[0], max_sync_cycles=2000)

    async def adat_task():
        first = True
        for _ in range(n_samples):
            _, channels = await adat.read_frame(resync=first)
            first = False
            for (a, b), writer in adat_pairs.items():
                writer.push(channels[a], channels[b])

    # --- Drive Input I2S Buses ---
    cocotb.start_soon(
        drive_i2s_bus(bus_setter, ws_bits, data_bits, I2S_HALF_PERIOD_NS)
    )

    await adat_task()

    await ClockCycles(dut.clk, 1024)

    i2s_out.close()
    for writer in adat_pairs.values():
        writer.close()

    dut._log.info("Test complete - wrote i2s_out.wav and adat_ch*.wav files.")