#!/usr/bin/env python3
"""Emit frequency-band magnitudes for whatever the default sink is playing.

The media widget's ring reads this: one line per frame, BANDS integers in
0..100, low frequencies first. Reads the sink's own monitor, so it follows the
speakers rather than any one application.

Kept deliberately small -- it runs only while the media panel is open.
"""

import os
import shutil
import subprocess
import sys

import numpy as np

BANDS = 24          # half the ring; the widget mirrors it around the circle
RATE = 44100
FFT = 2048          # ~46 ms window
HOP = 1024          # ~43 frames a second
FMIN, FMAX = 40.0, 14000.0

# A monitor still carries a little noise with nothing playing; below this the
# ring should sit still rather than twitch at amplified silence.
SILENCE_RMS = 1e-4

ATTACK, RELEASE = 0.55, 0.16   # per-frame smoothing, rising faster than falling

# Everything is scaled against a rolling peak so quiet tracks still fill the
# ring, and spread over this many dB below it -- a linear scale would leave
# every band pinned near the top, since loudness is logarithmic.
DB_RANGE = 38.0
PEAK_DECAY = 0.995


def default_monitor():
    try:
        sink = subprocess.run(["pactl", "get-default-sink"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        sink = ""
    return sink + ".monitor" if sink else "@DEFAULT_MONITOR@"


def main():
    if shutil.which("parec") is None:
        sys.exit("parec not found")

    proc = subprocess.Popen(
        ["parec", "--device=" + default_monitor(), "--format=float32le",
         "--rate=" + str(RATE), "--channels=1", "--latency-msec=20"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    window = np.hanning(FFT).astype(np.float32)

    # Log-spaced band edges: pitch is logarithmic, so linear bins would put
    # almost every band in the treble where there is little to see.
    edges = np.logspace(np.log10(FMIN), np.log10(FMAX), BANDS + 1)
    bins = np.clip((edges * FFT / RATE).astype(int), 1, FFT // 2)

    # Music rolls off steeply towards the treble, so without a tilt the upper
    # half of the ring would never move. Roughly +3 dB per octave.
    centres = np.sqrt(edges[:-1] * edges[1:])
    tilt = (centres / FMIN) ** 0.8

    buf = np.zeros(FFT, dtype=np.float32)
    smoothed = np.zeros(BANDS, dtype=np.float32)
    peak_db = -60.0
    chunk_bytes = HOP * 4

    while True:
        raw = proc.stdout.read(chunk_bytes)
        if not raw or len(raw) < chunk_bytes:
            break
        block = np.frombuffer(raw, dtype=np.float32)
        buf = np.concatenate((buf[HOP:], block))

        if np.sqrt(np.mean(buf * buf)) < SILENCE_RMS:
            smoothed *= 0.8
        else:
            spec = np.abs(np.fft.rfft(buf * window))
            raw_bands = np.empty(BANDS, dtype=np.float32)
            for i in range(BANDS):
                lo, hi = bins[i], max(bins[i] + 1, bins[i + 1])
                raw_bands[i] = spec[lo:hi].mean()

            db = 20.0 * np.log10(raw_bands * tilt + 1e-9)

            peak_db = max(float(db.max()), peak_db * PEAK_DECAY + -60.0 * (1 - PEAK_DECAY))
            norm = np.clip((db - (peak_db - DB_RANGE)) / DB_RANGE, 0.0, 1.0)

            rising = norm > smoothed
            smoothed = np.where(rising,
                                smoothed + (norm - smoothed) * ATTACK,
                                smoothed + (norm - smoothed) * RELEASE)

        sys.stdout.write(" ".join(str(int(v * 100)) for v in smoothed) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
