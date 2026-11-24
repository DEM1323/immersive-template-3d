#!/usr/bin/env python3
"""Procedural ethereal audio synthesizer for Immersive Ephemeral Jeopardy.

Generates nine deterministic 44.1 kHz / 16-bit / mono PCM ``.wav`` files into
``res://audio/`` using only the Python standard library.

    python tools/generate_audio.py            # generate + verify
    python tools/generate_audio.py --verify   # verify existing files only

Design notes
------------
* Every one-shot uses raised-cosine attacks, exponential decays, a light
  Freeverb-style reverb and a cosine fade-out so the first and last samples
  are exactly zero (no clicks).
* ``ambient_drone.wav`` is built only from sinusoids whose frequencies are exact
  multiples of 1 / LOOP_SECONDS (and a circularly-filtered noise bed), so the
  waveform is mathematically periodic: sample N wraps perfectly to sample 0.
  A RIFF ``smpl`` chunk with forward-loop points is appended so Godot's WAV
  importer ("Detect From WAV") loops it seamlessly as well.
* Output is byte-for-byte reproducible (fixed random seeds, no timestamps).
"""

import math
import random
import struct
import sys
import wave
from pathlib import Path

SR = 44100
TAU = 2.0 * math.pi
ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "audio"
MAX_PEAK = 0.92
LOOP_SECONDS = 12.0

# ----------------------------------------------------------------------------
# Pitch helpers
# ----------------------------------------------------------------------------
_NOTE_OFFSETS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    """Convert a note name such as 'C#4' or 'Bb3' to frequency (A4 = 440 Hz)."""
    letter = name[0].upper()
    rest = name[1:]
    semis = _NOTE_OFFSETS[letter]
    while rest and rest[0] in "#b":
        semis += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    midi = 12 * (int(rest) + 1) + semis
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# ----------------------------------------------------------------------------
# DSP building blocks
# ----------------------------------------------------------------------------
def silence(seconds):
    return [0.0] * int(round(seconds * SR))


def add_tone(
    buf,
    start,
    freq,
    amp,
    attack=0.004,
    decay=0.4,
    hold=0.0,
    phase=0.0,
    vib_rate=0.0,
    vib_depth=0.0,
    freq_end=None,
    glide=0.0,
):
    """Add one enveloped sinusoid (raised-cosine attack, hold, exponential decay)."""
    i0 = int(round(start * SR))
    if i0 >= len(buf) or amp == 0.0 or freq >= SR * 0.45:
        return
    att_n = max(3, int(attack * SR))
    hold_n = int(hold * SR)
    k = math.exp(-1.0 / (max(decay, 1e-4) * SR))
    w0 = TAU * freq / SR
    w1 = TAU * (freq_end if freq_end else freq) / SR
    glide_n = max(1, int(glide * SR))
    ratio = w1 / w0
    vib_w = TAU * vib_rate / SR
    sin = math.sin
    cos = math.cos
    pi = math.pi
    ph = phase
    tail = 1.0
    for j in range(len(buf) - i0):
        if j < att_n:
            env = 0.5 - 0.5 * cos(pi * j / att_n)
        elif j < att_n + hold_n:
            env = 1.0
        else:
            tail *= k
            env = tail
            if env < 1e-5:
                break
        if freq_end is not None and j < glide_n:
            w = w0 * ratio ** (j / glide_n)
        else:
            w = w1
        if vib_depth:
            w *= 1.0 + vib_depth * sin(vib_w * j)
        buf[i0 + j] += amp * env * sin(ph)
        ph += w


# Inharmonic partial tables: (frequency ratio, relative amplitude, decay multiplier)
GLASS = [(1.0, 1.0, 1.0), (2.0, 0.38, 0.55), (2.76, 0.20, 0.38), (5.40, 0.07, 0.22), (8.93, 0.025, 0.14)]
CHIME = [(1.0, 1.0, 1.0), (2.0, 0.30, 0.6), (3.01, 0.12, 0.4), (4.17, 0.05, 0.25)]
BOWL = [(1.0, 1.0, 1.0), (2.71, 0.45, 0.62), (5.15, 0.20, 0.38), (8.43, 0.07, 0.22)]


def add_bell(buf, start, freq, amp, decay, rng, partials=GLASS, attack=0.004, beat=0.0):
    for ratio, rel, dmul in partials:
        f = freq * ratio
        if f > 15000.0:
            continue
        att = max(0.003, attack / math.sqrt(ratio))
        if beat:
            # Split each partial into a slowly beating pair (singing-bowl shimmer).
            for sign in (-1.0, 1.0):
                add_tone(buf, start, f + sign * beat * ratio**0.5, amp * rel * 0.5, att, decay * dmul,
                         phase=rng.random() * TAU)
        else:
            add_tone(buf, start, f, amp * rel, att, decay * dmul, phase=rng.random() * TAU)


def add_harp(buf, start, freq, amp, decay, rng, harmonics=6):
    """Soft plucked-string tone: harmonic series with faster-decaying overtones."""
    for n in range(1, harmonics + 1):
        f = freq * n * (1.0 + 0.0004 * (n - 1) ** 2)  # tiny string inharmonicity
        if f > 15000.0:
            break
        add_tone(buf, start, f, amp / n**1.6, 0.003, decay / (1.0 + 0.7 * (n - 1)), phase=rng.random() * TAU)


def add_pad(buf, start, freq, amp, attack, decay, rng, hold=0.0, cents=5.0, harmonics=(1.0, 0.33, 0.13, 0.05),
            vib=0.0018):
    """Warm chorused pad: two detuned harmonic stacks with slow vibrato."""
    for detune in (-cents, cents):
        base = freq * 2.0 ** (detune / 1200.0)
        rate = 4.2 + rng.random() * 1.2
        for n, rel in enumerate(harmonics, start=1):
            add_tone(buf, start, base * n, amp * rel * 0.5, attack, decay / (1.0 + 0.35 * (n - 1)), hold=hold,
                     phase=rng.random() * TAU, vib_rate=rate, vib_depth=vib)


def lowpass(x, cutoff):
    a = 1.0 - math.exp(-TAU * cutoff / SR)
    y = 0.0
    out = [0.0] * len(x)
    for i, s in enumerate(x):
        y += a * (s - y)
        out[i] = y
    return out


def highpass(x, cutoff):
    low = lowpass(x, cutoff)
    return [s - lo for s, lo in zip(x, low)]


def reverb(x, wet=0.3, room=0.86, damp=0.3, predelay=0.012):
    """Mono Freeverb-style reverb (8 damped combs -> 4 allpasses)."""
    n = len(x)
    pre = int(predelay * SR)
    src = [0.0] * pre + x[: max(0, n - pre)]
    acc = [0.0] * n
    for length in (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617):
        line = [0.0] * length
        idx = 0
        store = 0.0
        for i in range(n):
            o = line[idx]
            store = o * (1.0 - damp) + store * damp
            line[idx] = src[i] * 0.015 + store * room
            acc[i] += o
            idx += 1
            if idx == length:
                idx = 0
    for length in (556, 441, 341, 225):
        line = [0.0] * length
        idx = 0
        for i in range(n):
            bo = line[idx]
            inp = acc[i]
            acc[i] = bo - inp
            line[idx] = inp + bo * 0.5
            idx += 1
            if idx == length:
                idx = 0
    return [d * (1.0 - wet * 0.35) + w * 3.0 * wet for d, w in zip(x, acc)]


def normalize(x, peak):
    m = max(abs(s) for s in x) or 1.0
    g = peak / m
    return [s * g for s in x]


def finalize(x, peak, fade_out=0.06, fade_in=0.002, smooth=11000.0):
    """Gentle top-end smoothing, DC removal, click-free fades and normalization."""
    x = lowpass(x, smooth)
    x = highpass(x, 25.0)
    n = len(x)
    fi = max(2, int(fade_in * SR))
    for i in range(min(fi, n)):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / fi)
    fo = max(2, int(fade_out * SR))
    for i in range(min(fo, n)):
        t = i / (fo - 1)
        x[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * t)
    x[0] = 0.0
    x[-1] = 0.0
    return normalize(x, peak)


# ----------------------------------------------------------------------------
# Sound designs
# ----------------------------------------------------------------------------
def tap_glass():
    rng = random.Random(101)
    buf = silence(0.32)
    add_bell(buf, 0.0, hz("C6"), 0.55, 0.085, rng, attack=0.004)
    add_bell(buf, 0.004, hz("G6"), 0.16, 0.05, rng, partials=CHIME)
    add_tone(buf, 0.0, hz("C5"), 0.18, 0.006, 0.07, phase=rng.random() * TAU)  # soft body
    buf = reverb(buf, wet=0.2, room=0.78, damp=0.35)
    return finalize(buf, 0.74, fade_out=0.07)


def tile_dissolve():
    rng = random.Random(202)
    dur = 0.75
    buf = silence(dur)
    run = ["E5", "G5", "A5", "C6", "D6", "E6", "G6", "A6", "C7"]
    for i, name in enumerate(run):
        t = i * 0.05
        swell = math.sin(math.pi * (i + 1) / (len(run) + 1)) ** 0.7
        add_bell(buf, t, hz(name) * (1.0 + (rng.random() - 0.5) * 0.002), 0.30 * swell, 0.16, rng, partials=CHIME)
    # Rising airy glissando shimmer ("evaporating into light").
    for f0, f1, a in ((1200.0, 2600.0, 0.07), (1800.0, 3900.0, 0.035)):
        add_tone(buf, 0.03, f0, a, attack=0.22, decay=0.16, hold=0.08, freq_end=f1, glide=0.5,
                 vib_rate=7.0, vib_depth=0.004, phase=rng.random() * TAU)
    buf = reverb(buf, wet=0.36, room=0.84, damp=0.3)
    return finalize(buf, 0.78, fade_out=0.16)


def correct_chord():
    rng = random.Random(303)
    buf = silence(1.25)
    # C major 9 (C E G B D) arpeggiated bell bloom.
    arp = ["C4", "E4", "G4", "B4", "D5", "E5"]
    for i, name in enumerate(arp):
        t = i * 0.055
        add_harp(buf, t, hz(name), 0.26, 0.9, rng)
        add_bell(buf, t, hz(name) * 2.0, 0.08, 0.45, rng, partials=CHIME)
    add_pad(buf, 0.02, hz("C3"), 0.20, 0.16, 0.9, rng, hold=0.15)
    add_pad(buf, 0.06, hz("G3"), 0.14, 0.2, 0.85, rng, hold=0.1)
    for t, name in ((0.32, "G6"), (0.40, "D7"), (0.50, "B6")):
        add_bell(buf, t, hz(name), 0.05, 0.35, rng)
    buf = reverb(buf, wet=0.34, room=0.86, damp=0.28)
    return finalize(buf, 0.85, fade_out=0.28)


def wrong_tone():
    rng = random.Random(404)
    buf = silence(0.85)
    # Gentle descending minor third (A -> F#), bell over a soft cello-like voice.
    for t, name, amp in ((0.0, "A3", 0.26), (0.23, "F#3", 0.30)):
        f = hz(name)
        for n, rel in enumerate((1.0, 0.55, 0.32, 0.17, 0.08, 0.04), start=1):
            add_tone(buf, t, f * n, amp * rel, attack=0.07, decay=0.42 / (1.0 + 0.3 * (n - 1)), hold=0.05,
                     vib_rate=5.0, vib_depth=0.003, phase=rng.random() * TAU)
        add_bell(buf, t, f * 2.0, amp * 0.55, 0.35, rng, attack=0.006)
    buf = lowpass(buf, 3200.0)
    buf = reverb(buf, wet=0.3, room=0.84, damp=0.4)
    return finalize(buf, 0.78, fade_out=0.22)


def daily_double():
    rng = random.Random(505)
    buf = silence(1.65)
    # Two-octave D major pentatonic harp cascade with chime sparkles.
    cascade = ["D4", "E4", "F#4", "A4", "B4", "D5", "E5", "F#5", "A5", "B5", "D6", "E6", "F#6", "A6"]
    for i, name in enumerate(cascade):
        t = i * 0.052
        add_harp(buf, t, hz(name), 0.2 + 0.06 * (i / len(cascade)), 0.75, rng)
        if i % 2 == 1:
            add_bell(buf, t + 0.01, hz(name) * 2.0, 0.06, 0.4, rng, partials=CHIME)
    # Warm sub-pad swell.
    add_pad(buf, 0.0, hz("D2"), 0.22, 0.55, 0.9, rng, hold=0.35, cents=4.0)
    add_pad(buf, 0.05, hz("A2"), 0.15, 0.6, 0.85, rng, hold=0.3, cents=4.0)
    add_pad(buf, 0.1, hz("F#3"), 0.08, 0.6, 0.8, rng, hold=0.25)
    sparkle = ["D7", "A6", "F#7", "E7", "B6", "A7"]
    for i, name in enumerate(sparkle):
        t = 0.78 + i * 0.09 + rng.random() * 0.03
        add_bell(buf, t, hz(name), 0.045, 0.3, rng)
    buf = reverb(buf, wet=0.4, room=0.88, damp=0.28)
    return finalize(buf, 0.86, fade_out=0.36)


def timer_tick():
    rng = random.Random(606)
    buf = silence(0.18)
    # Waterdrop: quick upward pitch blip with fast decay.
    add_tone(buf, 0.0, 720.0, 0.55, attack=0.006, decay=0.034, freq_end=1480.0, glide=0.028)
    add_bell(buf, 0.002, hz("A6"), 0.14, 0.04, rng, partials=CHIME, attack=0.006)
    buf = reverb(buf, wet=0.14, room=0.7, damp=0.4, predelay=0.006)
    return finalize(buf, 0.68, fade_out=0.05)


def time_up():
    rng = random.Random(707)
    buf = silence(1.15)
    # Struck crystal singing bowl with beating partial pairs + low gong body.
    add_bell(buf, 0.0, hz("G3"), 0.5, 1.4, rng, partials=BOWL, attack=0.012, beat=0.8)
    add_bell(buf, 0.0, hz("D5"), 0.08, 0.6, rng, partials=BOWL, attack=0.01, beat=1.1)
    add_tone(buf, 0.0, hz("G2"), 0.3, attack=0.025, decay=0.9, vib_rate=0.9, vib_depth=0.002)
    add_tone(buf, 0.0, hz("G2") * 1.5, 0.07, attack=0.04, decay=0.6)
    buf = reverb(buf, wet=0.3, room=0.87, damp=0.32)
    return finalize(buf, 0.86, fade_out=0.38, smooth=7000.0)


def finale_fanfare():
    rng = random.Random(808)
    buf = silence(2.4)
    # Fmaj9 lift -> radiant Cmaj9 resolution with sparkling overtones.
    first = ["F3", "A3", "C4", "E4", "G4"]
    for i, name in enumerate(first):
        add_harp(buf, i * 0.035, hz(name), 0.18, 0.7, rng)
    add_pad(buf, 0.0, hz("F2"), 0.18, 0.12, 0.45, rng, hold=0.2)
    add_pad(buf, 0.02, hz("C3"), 0.12, 0.14, 0.45, rng, hold=0.2)

    t0 = 0.56
    resolve = ["C3", "G3", "C4", "E4", "G4", "B4", "D5", "E5", "G5"]
    for i, name in enumerate(resolve):
        t = t0 + i * 0.03
        add_harp(buf, t, hz(name), 0.2, 1.3, rng)
        add_bell(buf, t, hz(name) * 2.0, 0.05, 0.7, rng, partials=CHIME)
    add_pad(buf, t0, hz("C2"), 0.24, 0.3, 1.5, rng, hold=0.35, cents=4.0)
    add_pad(buf, t0 + 0.03, hz("G2"), 0.16, 0.35, 1.4, rng, hold=0.3)
    add_pad(buf, t0 + 0.06, hz("E3"), 0.12, 0.4, 1.3, rng, hold=0.3)
    add_pad(buf, t0 + 0.09, hz("D4"), 0.07, 0.45, 1.2, rng, hold=0.25)
    sparkle = ["C6", "E6", "G6", "B6", "D7", "E7", "G7"]
    for i in range(14):
        t = t0 + 0.12 + i * 0.075 + rng.random() * 0.03
        name = sparkle[rng.randrange(len(sparkle))]
        add_bell(buf, t, hz(name), 0.035 * (1.0 - i / 18.0), 0.32, rng)
    add_tone(buf, t0 + 0.1, hz("C7"), 0.025, attack=0.5, decay=0.6, hold=0.3, vib_rate=6.0, vib_depth=0.003)
    buf = reverb(buf, wet=0.42, room=0.89, damp=0.27)
    return finalize(buf, 0.88, fade_out=0.55)


def ambient_drone():
    """Exactly periodic 12 s celestial pad: every component completes whole cycles."""
    rng = random.Random(909)
    n = int(LOOP_SECONDS * SR)  # 529200 samples
    buf = [0.0] * n
    sin = math.sin

    def add_periodic(k_cycles, amp, lfo_cycles=0, lfo_depth=0.0, lfo_phase=0.0, shape=1):
        """Sinusoid with exactly ``k_cycles`` cycles per loop and optional periodic LFO."""
        k = int(k_cycles)
        ph = rng.random() * TAU
        for i in range(n):
            # (k * i) % n keeps the phase argument exact so the loop wraps perfectly.
            s = sin(TAU * ((k * i) % n) / n + ph)
            if lfo_cycles:
                lfo = 0.5 - 0.5 * math.cos(TAU * ((lfo_cycles * i) % n) / n + lfo_phase)
                g = (1.0 - lfo_depth) + lfo_depth * lfo**shape
                s *= g
            buf[i] += amp * s

    def cycles(freq):
        return round(freq * LOOP_SECONDS)

    # D lydian/maj9 sanctuary voicing with slow chorus (+/-2 cycles per loop).
    voices = [
        ("D2", 0.50, 1), ("A2", 0.36, 2), ("E3", 0.24, 3), ("A3", 0.20, 1),
        ("F#4", 0.11, 2), ("C#5", 0.06, 3), ("E5", 0.045, 1),
    ]
    for name, amp, lfo in voices:
        k = cycles(hz(name))
        for spread in (-2, 2):
            add_periodic(k + spread, amp * 0.5, lfo, 0.4, rng.random() * TAU)
        add_periodic(2 * k, amp * 0.12, lfo, 0.5, rng.random() * TAU)
    # Celestial shimmer partials that bloom and vanish within each loop.
    for name, amp, lfo in (("A5", 0.03, 1), ("E6", 0.02, 2), ("B6", 0.012, 3)):
        add_periodic(cycles(hz(name)), amp, lfo, 1.0, rng.random() * TAU, shape=2)

    # Airy breath bed: noise band-limited with circular filters so it wraps cleanly.
    def circular_lowpass(x, cutoff):
        a = 1.0 - math.exp(-TAU * cutoff / SR)
        y = 0.0
        for s in x:  # warm-up pass: the end state becomes the start state
            y += a * (s - y)
        out = [0.0] * len(x)
        for i, s in enumerate(x):
            y += a * (s - y)
            out[i] = y
        return out

    noise = [rng.gauss(0.0, 1.0) for _ in range(n)]
    band = circular_lowpass(circular_lowpass(noise, 900.0), 900.0)
    low = circular_lowpass(band, 180.0)
    for i in range(n):
        swell = 0.5 - 0.5 * math.cos(TAU * i / n)
        buf[i] += 0.035 * (band[i] - low[i]) * (0.3 + 0.7 * swell)

    mean = sum(buf) / n
    buf = [s - mean for s in buf]
    return normalize(buf, 0.45)


SOUNDS = {
    "tap_glass.wav": tap_glass,
    "tile_dissolve.wav": tile_dissolve,
    "correct_chord.wav": correct_chord,
    "wrong_tone.wav": wrong_tone,
    "daily_double.wav": daily_double,
    "timer_tick.wav": timer_tick,
    "time_up.wav": time_up,
    "finale_fanfare.wav": finale_fanfare,
    "ambient_drone.wav": ambient_drone,
}
LOOPING = {"ambient_drone.wav"}


# ----------------------------------------------------------------------------
# WAV I/O
# ----------------------------------------------------------------------------
def write_wav(path, samples, loop=False):
    ints = [max(-32767, min(32767, int(round(s * 32767.0)))) for s in samples]
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(struct.pack("<%dh" % len(ints), *ints))
    if loop:
        # Append a RIFF 'smpl' chunk with one forward loop over the whole file.
        period_ns = int(round(1e9 / SR))
        smpl = struct.pack("<9I", 0, 0, period_ns, 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(ints) - 1, 0, 0)
        data = bytearray(path.read_bytes())
        data += b"smpl" + struct.pack("<I", len(smpl)) + smpl
        data[4:8] = struct.pack("<I", len(data) - 8)
        path.write_bytes(bytes(data))


def read_wav(path):
    with wave.open(str(path), "rb") as wf:
        params = (wf.getnchannels(), wf.getsampwidth(), wf.getframerate())
        frames = wf.readframes(wf.getnframes())
    count = len(frames) // 2
    return params, [v / 32767.0 for v in struct.unpack("<%dh" % count, frames)]


def verify(names=None):
    """Validate headers, levels, envelopes and loop continuity. Returns True if all pass."""
    ok = True
    print("\n%-20s %7s %7s %7s %9s  %s" % ("file", "secs", "peak", "rms", "edge", "status"))
    for name in names or SOUNDS:
        path = OUT_DIR / name
        problems = []
        if not path.exists():
            print("%-20s MISSING" % name)
            ok = False
            continue
        raw = path.read_bytes()
        if raw[0:4] != b"RIFF" or raw[8:12] != b"WAVE":
            problems.append("bad RIFF/WAVE header")
        if struct.unpack("<I", raw[4:8])[0] != len(raw) - 8:
            problems.append("RIFF size mismatch")
        params, x = read_wav(path)
        if params != (1, 2, SR):
            problems.append("format %s" % (params,))
        peak = max(abs(s) for s in x)
        rms = math.sqrt(sum(s * s for s in x) / len(x))
        if rms < 0.005:
            problems.append("near-silent")
        if peak > MAX_PEAK:
            problems.append("peak %.3f > %.2f" % (peak, MAX_PEAK))
        steps = [abs(x[i + 1] - x[i]) for i in range(len(x) - 1)]
        if name in LOOPING:
            wrap = abs(x[0] - x[-1])
            edge = wrap
            if wrap > max(steps) or wrap > 0.02:
                problems.append("loop seam step %.4f" % wrap)
        else:
            head = max(abs(s) for s in x[:44])
            tail = max(abs(s) for s in x[-44:])
            edge = max(head, tail, abs(x[0]), abs(x[-1]))
            if abs(x[0]) > 1e-4 or abs(x[-1]) > 1e-4 or head > 0.05 or tail > 0.01:
                problems.append("edge not clean (head %.4f tail %.4f)" % (head, tail))
        status = "OK" if not problems else "FAIL: " + "; ".join(problems)
        ok = ok and not problems
        print("%-20s %7.3f %7.3f %7.3f %9.5f  %s" % (name, len(x) / SR, peak, rms, edge, status))
    return ok


def main():
    if "--verify" not in sys.argv:
        OUT_DIR.mkdir(parents=True, exist_ok=True)
        for name, fn in SOUNDS.items():
            samples = fn()
            write_wav(OUT_DIR / name, samples, loop=name in LOOPING)
            print("wrote %-20s %6.2fs" % (name, len(samples) / SR))
    passed = verify()
    print("\nAll audio checks passed." if passed else "\nAudio verification FAILED.")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
