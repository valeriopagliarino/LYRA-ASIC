"""
Generates a simple stereo test-tone wav file (44.1 kHz, 16-bit PCM) to
feed into the LYRA testbench: 440 Hz on the left channel, 554.37 Hz
(a major third above) on the right channel, at -6 dBFS, 0.5 seconds
long, with a short fade-in/out to avoid clicks.

Usage:
    python3 gen_test_tone.py [output.wav]
"""
import sys
import math
import wave
import struct

FS = 44100
DURATION_S = 0.5
AMPLITUDE = 0.5  # -6 dBFS
FADE_S = 0.01


def main(path="input.wav"):
    n = int(FS * DURATION_S)
    fade_n = int(FS * FADE_S)
    left = []
    right = []
    for i in range(n):
        t = i / FS
        env = 1.0
        if i < fade_n:
            env = i / fade_n
        elif i > n - fade_n:
            env = (n - i) / fade_n
        l = AMPLITUDE * env * math.sin(2 * math.pi * 440.0 * t)
        r = AMPLITUDE * env * math.sin(2 * math.pi * 554.37 * t)
        left.append(int(l * 32767))
        right.append(int(r * 32767))

    interleaved = [0] * (2 * n)
    interleaved[0::2] = left
    interleaved[1::2] = right

    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(FS)
        wf.writeframes(struct.pack("<{}h".format(len(interleaved)), *interleaved))

    print(f"Wrote {path}: {n} stereo samples @ {FS} Hz")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "input.wav")
