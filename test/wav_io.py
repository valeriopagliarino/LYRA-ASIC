"""
Minimal WAV (PCM16) helpers for the LYRA cocotb testbench.
Uses only the Python stdlib `wave` module - no external dependencies.
"""
import wave
import struct


def read_wav_stereo16(path):
    """Read a 16-bit PCM wav file and return (left, right) lists of signed ints.
    Mono files are duplicated to both channels."""
    with wave.open(path, "rb") as wf:
        n_channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)
        framerate = wf.getframerate()

    if sampwidth != 2:
        raise ValueError(
            f"{path}: only 16-bit PCM wav files are supported (got {sampwidth * 8}-bit)"
        )

    if framerate != 44100:
        print(
            f"[wav_io] WARNING: {path} sample rate is {framerate} Hz - the LYRA "
            f"design assumes 44.1 kHz. Samples will be streamed as-is at the "
            f"DUT's native 44.1 kHz frame rate (no resampling is performed)."
        )

    fmt = "<{}h".format(len(raw) // 2)
    samples = struct.unpack(fmt, raw)

    if n_channels == 1:
        left = list(samples)
        right = list(samples)
    elif n_channels == 2:
        left = list(samples[0::2])
        right = list(samples[1::2])
    else:
        raise ValueError(
            f"{path}: only mono or stereo wav files are supported (got {n_channels} channels)"
        )

    return left, right


class WavStereoWriter:
    """Accumulates (left, right) 16-bit samples in memory and writes a
    stereo PCM16 wav file when close() is called."""

    def __init__(self, path, framerate=44100):
        self.path = path
        self.framerate = framerate
        self.left = []
        self.right = []

    def _to_signed16(self, val):
        v = int(val) & 0xFFFF
        return v if v < 0x8000 else v - 0x10000

    def push(self, left, right):
        self.left.append(self._to_signed16(left))
        self.right.append(self._to_signed16(right))

    def close(self):
        with wave.open(self.path, "wb") as wf:
            wf.setnchannels(2)
            wf.setsampwidth(2)
            wf.setframerate(self.framerate)
            n = len(self.left)
            interleaved = [0] * (2 * n)
            interleaved[0::2] = self.left
            interleaved[1::2] = self.right
            packed = struct.pack("<{}h".format(len(interleaved)), *interleaved)
            wf.writeframes(packed)