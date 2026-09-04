"""
Standard ADAT (Alesis Digital Audio Tape) optical "Lightpipe" 8-channel
decoder, implemented as a passive cocotb bus functional model.

Frame format implemented (256 bits/frame @ Fs, matching the publicly
documented ADAT protocol - see e.g. https://ackspace.nl/wiki/ADAT_project
and https://www.soundonsound.com/glossary/adat-lightpipe):

    [10 x '0']  sync run
    [1  x '1' ] sync-run terminator
    [4  x user bit]
    [1  x '1' ] user-field terminator
    8 x channel slots, 30 bits each:
        6 nibbles of (4 data bits + 1 forced '1' sync bit)
        -> 24 audio bits per channel, MSB first
    Total = 10 + 1 + 4 + 1 + 8*30 = 256 bits

The physical signal is NRZI-encoded: a logical '1' is a transition on
the wire, a logical '0' is no transition. One raw wire bit is
transmitted per bit-clock cycle; in this design the ADAT bit clock IS
the 11.2896 MHz system clock (adat_encoder_6ch.clk_bit == clk, and
256 * 44100 Hz = 11.2896 MHz), so we sample `opt_drive` on every rising
edge of `clk`.

Because LYRA uses 16-bit audio words (not the full 24-bit ADAT word),
this decoder assumes the standard's own padding rule applies -
"padding zeros are introduced automatically if the word length is less
than 24 bits" (per the ADAT spec) - i.e. the 16 significant bits occupy
the MSBs of the 24-bit slot and the low 8 bits are padding. We
therefore report the top 16 bits of each recovered 24-bit sample.

NOTE: adat_encoder_6ch.sv was not provided with this project, so this
decoder implements the public ADAT standard as closely as documented,
rather than a verified bit-exact match to that specific RTL. Only 6 of
the 8 channels are driven by lyra_topl (ch0..ch3 = DSP/raw outputs,
ch4..ch5 = raw ch0/ch1); channels 6 and 7 are expected to decode as
silence (zero-padding to complete a standard ADAT8 frame). If your
encoder differs (different sync length, bit order, or padding
position), adjust the constants below accordingly.
"""
"""
Standard ADAT (Alesis Digital Audio Tape) optical "Lightpipe" 8-channel
decoder, implemented as a passive cocotb bus functional model.

Frame format implemented (256 bits/frame @ Fs, matching the publicly
documented ADAT protocol):

    [10 x '0']  sync run
    [1  x '1' ] sync-run terminator
    [4  x user bit]
    [1  x '1' ] user-field terminator
    8 x channel slots, 30 bits each:
        6 nibbles of (4 data bits + 1 forced '1' sync bit)
        -> 24 audio bits per channel, MSB first
    Total = 10 + 1 + 4 + 1 + 8*30 = 256 bits

"""

import cocotb
from cocotb.triggers import RisingEdge

FRAME_BITS = 256
NUM_CHANNELS = 8
BITS_PER_CHANNEL = 30
PAYLOAD_BITS = 24

FRAME_SYNC_BITS = [0, 0, 0, 0, 0, 1]


def bits_to_uint(bits):
    value = 0
    for bit in bits:
        value = (value << 1) | (int(bit) & 1)
    return value


def uint_to_signed(value, width):
    value &= (1 << width) - 1

    if value & (1 << (width - 1)):
        return value - (1 << width)

    return value


def pcm24_leftjustified_to_pcm16(payload24):
    pcm16_unsigned = (payload24 >> 8) & 0xFFFF
    return uint_to_signed(pcm16_unsigned, 16)


class AdatFrameError(Exception):
    pass


class AdatDecoder:

    def __init__(
        self,
        clk,
        adat_signal,
        max_sync_cycles=4096,
        strict=True
    ):
        self.clk = clk
        self.adat_signal = adat_signal
        self.max_sync_cycles = max_sync_cycles
        self.strict = strict

        self.previous_nrzi = None
        self.frame_count = 0

    async def _read_raw_bit(self):

        await RisingEdge(self.clk)

        level = int(self.adat_signal.value) & 1

        if self.previous_nrzi is None:
            self.previous_nrzi = level
            return None

        raw_bit = level ^ self.previous_nrzi

        self.previous_nrzi = level

        return raw_bit

    async def _read_valid_raw_bit(self):

        while True:

            bit = await self._read_raw_bit()

            if bit is not None:
                return bit

    async def _find_sync(self):

        window = []

        for _ in range(self.max_sync_cycles):

            bit = await self._read_valid_raw_bit()

            window.append(bit)

            if len(window) > 6:
                window.pop(0)

            if window == FRAME_SYNC_BITS:
                return

        raise TimeoutError(
            f"ADAT sync not found within "
            f"{self.max_sync_cycles} cycles"
        )

    async def _read_frame_after_sync(self):

        frame = list(FRAME_SYNC_BITS)

        for _ in range(FRAME_BITS - len(FRAME_SYNC_BITS)):

            bit = await self._read_valid_raw_bit()

            frame.append(bit)

        return frame

    def _validate_frame(self, frame):

        if len(frame) != 256:
            raise AdatFrameError(
                f"Invalid frame length {len(frame)}"
            )

        if frame[0:6] != FRAME_SYNC_BITS:
            raise AdatFrameError(
                f"Invalid sync {frame[0:6]}"
            )

        if frame[10] != 1:
            raise AdatFrameError(
                "Invalid USER stuffing bit"
            )

        for channel in range(8):

            channel_start = 11 + channel * 30

            for group in range(6):

                stuffing_bit = (
                    channel_start
                    + group * 5
                    + 4
                )

                if frame[stuffing_bit] != 1:

                    raise AdatFrameError(
                        f"Invalid stuffing bit "
                        f"channel={channel} "
                        f"group={group}"
                    )

        if frame[251:256] != [0, 0, 0, 0, 0]:

            raise AdatFrameError(
                f"Invalid frame tail "
                f"{frame[251:256]}"
            )

    def _extract_payload(self, frame, channel):

        channel_start = 11 + channel * 30

        bits = []

        for group in range(6):

            group_start = channel_start + group * 5

            bits.extend(
                frame[group_start:group_start + 4]
            )

        return bits_to_uint(bits)

    def _decode_channels(self, frame):

        channels = []

        for channel in range(8):

            payload24 = self._extract_payload(
                frame,
                channel
            )

            pcm16 = pcm24_leftjustified_to_pcm16(
                payload24
            )

            channels.append(pcm16)

        return channels

    async def read_frame(self, resync=False):

        if resync or self.frame_count == 0:

            await self._find_sync()

            frame = await self._read_frame_after_sync()

        else:

            frame = []

            for _ in range(FRAME_BITS):

                bit = await self._read_valid_raw_bit()

                frame.append(bit)

        self._validate_frame(frame)

        channels = self._decode_channels(frame)

        frame_number = self.frame_count

        self.frame_count += 1

        return frame_number, channels