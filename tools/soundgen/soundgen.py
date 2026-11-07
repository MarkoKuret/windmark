#!/usr/bin/env python3
"""soundgen: synthesises the default sound set of docs/specs/audio.md (§10) from noise, tones and impulses.

Every file is our own (no samples, no recordings), so the set needs no third-party licence. Loops are built on a
circular buffer (noise shaped in the frequency domain, modulations whose periods divide the loop length), so they
repeat without a seam. Output: Ogg Vorbis, 22.05 kHz, written through ffmpeg (its built-in Vorbis encoder, which
wants two channels: mono sounds are written as identical channels).

    python3 tools/soundgen/soundgen.py                 # writes game/audio/default
    python3 tools/soundgen/soundgen.py --out DIR --wav # WAV instead of Ogg (no ffmpeg needed)
    python3 tools/soundgen/soundgen.py --only boat/wake_loop

Needs NumPy and, for Ogg output, ffmpeg on the path.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 22050
PEAK_MAX = 10 ** (-1.0 / 20)  # -1 dBFS
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFAULT_OUT = os.path.join(REPO, "game", "audio", "default")


# ---- building blocks ----

def rng(seed):
    return np.random.default_rng(seed)


def n_of(seconds):
    return int(round(seconds * SR))


def freqs(n):
    return np.fft.rfftfreq(n, 1.0 / SR)


def shaped_noise(n, shape, r, stereo=False):
    """White noise shaped in the frequency domain by shape(f) (amplitude): circular, so it loops seamlessly."""
    f = freqs(n)
    g = shape(f)
    g[0] = 0.0
    chans = []
    for _ in range(2 if stereo else 1):
        spec = np.fft.rfft(r.standard_normal(n)) * g
        chans.append(np.fft.irfft(spec, n))
    return np.stack(chans, 1) if stereo else chans[0]


def band(lo, hi, slope=2.0):
    """Band-pass magnitude with soft skirts (order `slope` on each side)."""
    def g(f):
        f = np.maximum(f, 1e-3)
        a = 1.0 / np.sqrt(1.0 + (lo / f) ** (2 * slope))
        b = 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * slope))
        return a * b
    return g


def pink(lo, hi, slope=2.0):
    return lambda f: band(lo, hi, slope)(f) / np.sqrt(np.maximum(f, 20.0))


def brown(lo, hi, slope=2.0):
    return lambda f: band(lo, hi, slope)(f) / np.maximum(f, 20.0)


def resonant(fc, q):
    return lambda f: 1.0 / np.sqrt(1.0 + (q * (f / fc - fc / np.maximum(f, 1e-3))) ** 2)


def lowpass(x, fc, order=2):
    n = x.shape[0]
    f = freqs(n)
    g = 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x, axis=0) * (g[:, None] if x.ndim == 2 else g), n, axis=0)


def highpass(x, fc, order=2):
    n = x.shape[0]
    f = np.maximum(freqs(n), 1e-3)
    g = 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x, axis=0) * (g[:, None] if x.ndim == 2 else g), n, axis=0)


def periodic_lfo(n, cycles, r, harmonics=4, depth=1.0):
    """A smooth random modulation in [0, 1] with whole cycles over n samples (loops)."""
    t = np.arange(n) / n
    y = np.zeros(n)
    for h in range(1, harmonics + 1):
        y += r.uniform(0.3, 1.0) / h * np.sin(2 * np.pi * cycles * h * t + r.uniform(0, 2 * np.pi))
    y = (y - y.min()) / max(y.max() - y.min(), 1e-9)
    return 1.0 - depth + depth * y


def env_ad(n, attack, decay, sustain=0.0):
    """Attack (s) then exponential decay (time constant, s)."""
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / decay)
    return a * (sustain + (1 - sustain) * d)


def env_asr(n, attack, release):
    t = np.arange(n) / SR
    dur = n / SR
    return np.clip(t / attack, 0, 1) * np.clip((dur - t) / release, 0, 1)


def place(dst, src, at, circular=True):
    """Add src into dst at sample `at` (wrapping round the end for loops)."""
    n = dst.shape[0]
    idx = (np.arange(src.shape[0]) + at)
    if circular:
        idx %= n
        np.add.at(dst, idx, src)
    else:
        keep = idx < n
        dst[idx[keep]] += src[keep]


def tone(n, freqs_hz, amps=None, phase_r=None):
    t = np.arange(n) / SR
    y = np.zeros(n)
    amps = amps or [1.0] * len(freqs_hz)
    for f, a in zip(freqs_hz, amps):
        ph = phase_r.uniform(0, 2 * np.pi) if phase_r is not None else 0.0
        y += a * np.sin(2 * np.pi * f * t + ph)
    return y


def chirp(n, f0, f1, curve=1.0):
    t = np.arange(n) / n
    f = f0 + (f1 - f0) * t ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def loop_freq(f, seconds):
    """Nearest frequency with a whole number of cycles in the loop."""
    return max(1, round(f * seconds)) / seconds


def rms_to(x, db):
    r = np.sqrt(np.mean(x ** 2))
    return x * (10 ** (db / 20) / max(r, 1e-9))


def peak_to(x, db):
    p = np.max(np.abs(x))
    return x * (10 ** (db / 20) / max(p, 1e-9))


# ---- the sounds ----

def hull_loop(r):
    s = 4.0
    n = n_of(s)
    x = shaped_noise(n, brown(60, 500), r) * periodic_lfo(n, 2, r, depth=0.5)
    gurgle = shaped_noise(n, band(250, 900), r) * periodic_lfo(n, 6, r, harmonics=6, depth=0.9) ** 3
    x = rms_to(x, -20) + rms_to(gurgle, -30)
    for k in range(5):  # soft hull knocks
        m = n_of(0.18)
        knock = (np.sin(2 * np.pi * r.uniform(90, 140) * np.arange(m) / SR) * env_ad(m, 0.004, 0.035)
                 + 0.3 * lowpass(r.standard_normal(m), 900) * env_ad(m, 0.002, 0.02))
        place(x, knock * r.uniform(0.08, 0.16), int(r.uniform(0, n)))
    return rms_to(x, -18)


def wake_loop(r):
    s = 4.0
    n = n_of(s)
    x = shaped_noise(n, pink(250, 3500), r) * periodic_lfo(n, 3, r, depth=0.45)
    fizz = shaped_noise(n, band(2500, 8000), r) * periodic_lfo(n, 9, r, harmonics=6, depth=0.8)
    return rms_to(rms_to(x, -18) + rms_to(fizz, -30), -18)


def bow_loop(r):
    s = 3.0
    n = n_of(s)
    x = shaped_noise(n, pink(180, 3000), r) * periodic_lfo(n, 3, r, harmonics=3, depth=0.6)
    return rms_to(x, -18)


def slap(seed):
    def make(r):
        n = n_of(0.45)
        f0 = r.uniform(55, 85)
        body = np.sin(2 * np.pi * np.cumsum(np.linspace(f0 * 1.6, f0, n)) / SR) * env_ad(n, 0.003, 0.07)
        splash = lowpass(r.standard_normal(n), r.uniform(1200, 2000)) * env_ad(n, 0.004, 0.09)
        spray = highpass(r.standard_normal(n), 2500) * env_ad(n, 0.02, 0.12) * 0.15
        return peak_to(body + 0.7 * splash + spray, -3)
    return make


def rig_loop(r):
    s = 4.0
    n = n_of(s)
    hum = tone(n, [loop_freq(110, s), loop_freq(220, s), loop_freq(331, s)], [1.0, 0.4, 0.15], r)
    hum *= periodic_lfo(n, 2, r, depth=0.6)
    x = rms_to(hum, -30) + rms_to(shaped_noise(n, band(300, 1500), r), -38)
    for k in range(2):  # creaks
        m = n_of(r.uniform(0.25, 0.4))
        c = np.sign(chirp(m, r.uniform(160, 220), r.uniform(120, 150))) * env_asr(m, 0.05, 0.1)
        place(x, lowpass(c, 1500) * 0.05, int(r.uniform(0, n)))
    return rms_to(x, -20)


def flog(rate_hz, lo, hi, weight):
    """Luffing and flogging cloth: noise cracks at a periodic, slightly irregular rhythm."""
    def make(r):
        s = 2.0
        n = n_of(s)
        cloth = shaped_noise(n, pink(lo, hi), r)
        k = max(1, round(rate_hz * s))
        am = np.zeros(n)
        for i in range(k):
            at = int((i + r.uniform(-0.2, 0.2)) * n / k) % n
            m = n_of(0.12)
            place(am, env_ad(m, 0.002, r.uniform(0.015, 0.04)) * r.uniform(0.6, 1.0), at)
        base = periodic_lfo(n, 1, r, depth=0.3) * 0.25
        x = cloth * (base + am)
        low = shaped_noise(n, brown(40, 250), r) * am
        return rms_to(x + weight * rms_to(low, -24), -16)
    return make


def winch_loop(r):
    s = 1.0
    n = n_of(s)
    x = np.zeros(n)
    k = 14
    for i in range(k):
        m = n_of(0.05)
        click = highpass(r.standard_normal(m), 2500) * env_ad(m, 0.0005, 0.004)
        ring = np.sin(2 * np.pi * 2300 * np.arange(m) / SR) * env_ad(m, 0.0005, 0.012) * 0.3
        place(x, (click + ring) * r.uniform(0.8, 1.0), int(i * n / k))
    x += rms_to(shaped_noise(n, band(150, 600), r), -40)
    return rms_to(x, -18)


def sheet_run(r):
    s = 2.0
    n = n_of(s)
    x = shaped_noise(n, band(900, 6000), r) * periodic_lfo(n, 30, r, harmonics=2, depth=0.5)
    return rms_to(x, -20)


def sheet_load(r):
    n = n_of(0.55)
    creak = lowpass(np.sign(chirp(n, 240, 150, 0.7)) * env_asr(n, 0.02, 0.2), 1400)
    thump = np.sin(2 * np.pi * 90 * np.arange(n) / SR) * env_ad(n, 0.002, 0.05)
    return peak_to(0.5 * creak + thump, -4)


def boom_cross(r):
    n = n_of(0.9)
    bang = lowpass(r.standard_normal(n), 1800) * env_ad(n, 0.001, 0.05)
    body = np.sin(2 * np.pi * np.cumsum(np.linspace(110, 60, n)) / SR) * env_ad(n, 0.002, 0.18)
    rattle = np.zeros(n)
    for i in range(5):
        m = n_of(0.03)
        place(rattle, highpass(r.standard_normal(m), 1500) * env_ad(m, 0.001, 0.006), n_of(0.08 + 0.05 * i + r.uniform(0, 0.02)), circular=False)
    return peak_to(bang + body + 0.4 * rattle * env_ad(n, 0.0, 0.3), -2)


def halyard_loop(r):
    s = 2.0
    n = n_of(s)
    squeak = np.sin(2 * np.pi * np.cumsum(loop_freq(900, s) + 60 * np.sin(2 * np.pi * 4 * np.arange(n) / n)) / SR)
    zip_ = shaped_noise(n, band(700, 5000), r) * periodic_lfo(n, 16, r, harmonics=3, depth=0.6)
    return rms_to(0.15 * squeak * periodic_lfo(n, 3, r, depth=0.8) + zip_, -20)


def fill(r):
    n = n_of(1.0)
    whump = lowpass(r.standard_normal(n), 400) * env_ad(n, 0.06, 0.25)
    body = np.sin(2 * np.pi * np.cumsum(np.linspace(70, 50, n)) / SR) * env_ad(n, 0.05, 0.2)
    crack = highpass(r.standard_normal(n), 1500) * env_ad(n, 0.05, 0.05) * 0.3
    return peak_to(whump + body + crack, -3)


def furl_loop(r):
    s = 2.0
    n = n_of(s)
    x = rms_to(shaped_noise(n, brown(60, 400), r) * periodic_lfo(n, 4, r, depth=0.4), -26)
    k = 16
    for i in range(k):
        m = n_of(0.03)
        place(x, highpass(r.standard_normal(m), 1200) * env_ad(m, 0.0005, 0.006) * 0.15, int(i * n / k))
    x += rms_to(shaped_noise(n, band(1000, 5000), r) * periodic_lfo(n, 8, r, depth=0.7), -30)
    return rms_to(x, -20)


def drop_loop(r):
    s = 2.0
    n = n_of(s)
    x = shaped_noise(n, pink(400, 5000), r) * periodic_lfo(n, 11, r, harmonics=6, depth=0.9) ** 2
    return rms_to(x, -20)


def collide_boat(seed):
    def make(r):
        n = n_of(0.9)
        f0 = r.uniform(85, 130)
        thud = np.sin(2 * np.pi * np.cumsum(np.linspace(f0 * 1.3, f0, n)) / SR) * env_ad(n, 0.002, 0.12)
        knock = np.sin(2 * np.pi * r.uniform(350, 480) * np.arange(n) / SR) * env_ad(n, 0.001, 0.03)
        crunch = lowpass(r.standard_normal(n), 2500) * env_ad(n, 0.001, 0.06)
        return peak_to(thud + 0.5 * knock + 0.6 * crunch, -1)
    return make


def collide_mark(r):
    n = n_of(0.7)
    thump = np.sin(2 * np.pi * np.cumsum(np.linspace(160, 110, n)) / SR) * env_ad(n, 0.004, 0.1)
    squeak = chirp(n, 700, 500) * env_asr(n, 0.02, 0.4) * env_ad(n, 0.0, 0.15) * 0.2
    splash = lowpass(r.standard_normal(n), 1500) * env_ad(n, 0.01, 0.12) * 0.4
    return peak_to(thump + squeak + splash, -2)


def collide_hard(r):
    n = n_of(1.3)
    x = np.zeros(n)
    for i in range(6):
        m = n_of(0.3)
        hit = lowpass(r.standard_normal(m), r.uniform(1500, 3500)) * env_ad(m, 0.001, r.uniform(0.02, 0.06))
        place(x, hit * r.uniform(0.4, 1.0), n_of(i * r.uniform(0.02, 0.06)), circular=False)
    body = np.sin(2 * np.pi * np.cumsum(np.linspace(80, 45, n)) / SR) * env_ad(n, 0.002, 0.25)
    return peak_to(x + body, -1)


def rub_loop(r):
    s = 1.5
    n = n_of(s)
    x = shaped_noise(n, band(250, 1400), r) * periodic_lfo(n, 5, r, harmonics=6, depth=0.8)
    squeal = np.sin(2 * np.pi * np.cumsum(loop_freq(520, s) + 40 * np.sin(2 * np.pi * 3 * np.arange(n) / n)) / SR)
    return rms_to(x + 0.2 * squeal * periodic_lfo(n, 2, r, depth=1.0), -20)


def wind_bed(r):
    s = 6.0
    n = n_of(s)
    x = shaped_noise(n, lambda f: pink(200, 2400, 1.5)(f) * (0.4 + resonant(800, 1.2)(f)), r, stereo=True)
    x *= periodic_lfo(n, 3, r, depth=0.45)[:, None]
    return rms_to(x, -16)


def wind_whistle(r):
    s = 4.0
    n = n_of(s)
    a = shaped_noise(n, resonant(1350, 40), r) * periodic_lfo(n, 2, r, depth=0.8)
    b = shaped_noise(n, resonant(2050, 50), r) * periodic_lfo(n, 3, r, depth=0.9)
    return rms_to(a + 0.6 * b, -20)


def horn(seconds, f1=440.0, f2=554.0):
    def make(r):
        n = n_of(seconds)
        t = np.arange(n) / SR
        y = np.zeros(n)
        for f in (f1, f2):
            for h in range(1, 8):  # a brassy spectrum
                y += (0.9 ** h) / h * np.sin(2 * np.pi * f * h * t + r.uniform(0, 2 * np.pi))
        y = lowpass(y, 2200)
        return peak_to(y * env_asr(n, 0.12, 0.12), -2)
    return make


def penalty(r):
    n = n_of(0.75)
    t = np.arange(n) / SR
    f = np.where(t < 0.35, 523.0, 392.0)
    y = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR))
    y = lowpass(y, 1800)
    e = np.clip(t / 0.01, 0, 1) * np.clip((0.75 - t) / 0.05, 0, 1) * np.where(np.abs(t - 0.35) < 0.02, 0.2, 1.0)
    return peak_to(y * e, -9)


def penalty_done(r):
    n = n_of(0.9)
    y = tone(n, [659.3], [1.0]) * env_ad(n, 0.003, 0.25)
    y2 = np.zeros(n)
    place(y2, tone(n_of(0.7), [880.0, 1760.0], [1.0, 0.2]) * env_ad(n_of(0.7), 0.003, 0.3), n_of(0.18), circular=False)
    return peak_to(y + y2, -4)


def beep(r):
    n = n_of(0.13)
    return peak_to(tone(n, [1000.0]) * env_asr(n, 0.005, 0.02), -6)


def ui_click(f0, f1, seconds, db):
    """Menu sounds (menus.md section 4): a short pitched click with a fast decay, a breath of noise on the attack."""
    def make(r):
        n = n_of(seconds)
        y = tone(n, [f0, f1], [1.0, 0.35]) * env_ad(n, 0.002, seconds * 0.35)
        click = highpass(r.standard_normal(n), 2000) * env_ad(n, 0.0005, 0.006) * 0.25
        return peak_to(y + click, db)
    return make


def ambience(level):
    """Sea ambience beds, calm to strong (level 0..3), stereo."""
    def make(r):
        s = 8.0
        n = n_of(s)
        lap = shaped_noise(n, brown(50, 700), r, stereo=True)
        lap *= np.stack([periodic_lfo(n, 5, r, depth=0.7), periodic_lfo(n, 6, r, depth=0.7)], 1)
        wash = shaped_noise(n, pink(150, 2500 + 1200 * level), r, stereo=True)
        wash *= np.stack([periodic_lfo(n, 2 + level, r, depth=0.6), periodic_lfo(n, 3 + level, r, depth=0.6)], 1)
        x = rms_to(lap, -20) + rms_to(wash, -34 + 5 * level)
        if level >= 2:  # breaking crests
            caps = shaped_noise(n, band(1500, 8000), r, stereo=True)
            caps *= np.stack([periodic_lfo(n, 4, r, harmonics=6, depth=1.0) ** 4,
                              periodic_lfo(n, 5, r, harmonics=6, depth=1.0) ** 4], 1)
            x += rms_to(caps, -36 + 4 * level)
        return rms_to(x, -18)
    return make


def gull(r):
    n = n_of(1.4)
    y = np.zeros(n)
    at = 0.0
    for i in range(3):
        m = n_of(r.uniform(0.18, 0.3))
        f = np.linspace(r.uniform(1500, 1800), r.uniform(900, 1100), m) * (1 + 0.03 * np.sin(2 * np.pi * 25 * np.arange(m) / SR))
        call = np.zeros(m)
        ph = 2 * np.pi * np.cumsum(f) / SR
        for h, a in ((1, 1.0), (2, 0.5), (3, 0.25), (4, 0.1)):
            call += a * np.sin(h * ph)
        call *= env_asr(m, 0.02, 0.08)
        place(y, call, n_of(at), circular=False)
        at += r.uniform(0.3, 0.42)
    y += lowpass(r.standard_normal(n), 3000) * 0.02
    return peak_to(y, -6)


def halyard_clink(r):
    """A halyard slapping an alloy mast on a moored boat: short metallic impacts (a noise burst through a broad
    resonant band around 1 to 3 kHz, falling 20 dB in 40 to 80 ms), three or four hits at irregular spacing. No
    sustained pure tone: the earlier bell-like pings read as a race signal or a beep (penalty_done is two pure pings)."""
    n = n_of(1.6)
    y = np.zeros(n)
    at = r.uniform(0.02, 0.1)
    for i in range(int(r.integers(3, 5))):
        m = n_of(0.3)
        fc = r.uniform(1300, 2400)
        ring = shaped_noise(m, lambda f, fc=fc: resonant(fc, 1.2)(f) * band(700, 4500, 1.5)(f), r)
        ring = ring * env_ad(m, 0.0007, r.uniform(0.02, 0.038))
        knock = shaped_noise(m, band(250, 1500, 1.5), r) * env_ad(m, 0.0005, 0.007)
        hit = rms_to(ring, -18) + 0.5 * rms_to(knock, -18)
        place(y, hit * r.uniform(0.45, 1.0), n_of(at), circular=False)
        at += r.uniform(0.12, 0.45)
    return peak_to(y, -6)


def distant_engine(r):
    n = n_of(6.0)
    t = np.arange(n) / SR
    y = np.zeros(n)
    f = 38.0 * (1 + 0.02 * np.sin(2 * np.pi * 0.3 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    for h in range(1, 9):
        y += np.sin(h * ph + r.uniform(0, 6.3)) / h
    y = lowpass(y, 350) + 0.2 * lowpass(r.standard_normal(n), 300)
    return peak_to(y * env_asr(n, 2.0, 2.5), -8)


def buoy_loop(r):
    s = 4.0
    n = n_of(s)
    x = shaped_noise(n, brown(80, 1200), r) * periodic_lfo(n, 4, r, harmonics=3, depth=0.9) ** 2
    return rms_to(x, -20)


def committee_loop(r):
    s = 2.0
    n = n_of(s)
    k = round(12.5 * s)
    x = np.zeros(n)
    for i in range(k):
        m = n_of(0.08)
        pulse = lowpass(r.standard_normal(m), 400) * env_ad(m, 0.002, 0.02)
        place(x, pulse * (1.0 if i % 2 == 0 else 0.7), int(i * n / k))
    x += tone(n, [loop_freq(50, s), loop_freq(100, s)], [0.03, 0.015], r)
    return rms_to(lowpass(x, 500), -20)


SOUNDS = {
    "boat/hull_loop": hull_loop,
    "boat/wake_loop": wake_loop,
    "boat/bow_loop": bow_loop,
    "boat/slap_1": slap(1), "boat/slap_2": slap(2), "boat/slap_3": slap(3), "boat/slap_4": slap(4),
    "boat/rig_loop": rig_loop,
    "boat/luff_main": flog(6.0, 150, 3000, 0.6),
    "boat/luff_front": flog(8.0, 200, 4000, 0.4),
    "boat/luff_kite": flog(4.0, 120, 2500, 0.9),
    "boat/winch_loop": winch_loop,
    "boat/sheet_run": sheet_run,
    "boat/sheet_load": sheet_load,
    "boat/boom_cross": boom_cross,
    "boat/halyard_loop": halyard_loop,
    "boat/fill": fill,
    "boat/furl_loop": furl_loop,
    "boat/drop_loop": drop_loop,
    "boat/collide_boat_1": collide_boat(1), "boat/collide_boat_2": collide_boat(2),
    "boat/collide_boat_3": collide_boat(3),
    "boat/collide_mark": collide_mark,
    "boat/collide_hard": collide_hard,
    "boat/rub_loop": rub_loop,
    "wind/bed_loop": wind_bed,
    "wind/whistle_loop": wind_whistle,
    "race/horn": horn(1.0),
    "race/horn_long": horn(2.5),
    "race/horn_finish": horn(1.0, 392.0, 494.0),
    "race/penalty": penalty,
    "race/penalty_done": penalty_done,
    "race/beep": beep,
    "amb/calm": ambience(0), "amb/moderate": ambience(1), "amb/fresh": ambience(2), "amb/strong": ambience(3),
    "amb/gull_1": gull,
    "amb/halyard_1": halyard_clink,
    "amb/engine_1": distant_engine,
    "venue/buoy_loop": buoy_loop,
    "venue/committee_loop": committee_loop,
    "ui/focus": ui_click(1320.0, 2640.0, 0.045, -18),
    "ui/accept": ui_click(880.0, 1760.0, 0.09, -12),
    "ui/back": ui_click(587.0, 1174.0, 0.08, -14),
}


def write_wav(path, x):
    x = np.clip(x, -1.0, 1.0)
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    pcm = (x * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--wav", action="store_true", help="write WAV files (no ffmpeg)")
    ap.add_argument("--quality", type=int, default=2, help="Vorbis quality (ffmpeg -q:a)")
    ap.add_argument("--only", nargs="*", help="names to write (default: all)")
    args = ap.parse_args()
    if not args.wav and shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found (use --wav)")
    total = 0
    for i, (name, make) in enumerate(SOUNDS.items()):
        if args.only and name not in args.only:
            continue
        seed = sum(ord(c) * (k + 1) for k, c in enumerate(name))
        x = make(rng(seed))
        x = x * min(1.0, PEAK_MAX / max(np.max(np.abs(x)), 1e-9))  # never clip (flogs and clicks peak high)
        dst = os.path.join(args.out, name + (".wav" if args.wav else ".ogg"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if args.wav:
            write_wav(dst, x)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                src = os.path.join(tmp, "x.wav")
                write_wav(src, x)
                subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src,
                                "-c:a", "vorbis", "-strict", "-2", "-q:a", str(args.quality),
                                "-map_metadata", "-1", "-fflags", "+bitexact", dst], check=True)
        size = os.path.getsize(dst)
        total += size
        print("%-24s %5.2f s %7d bytes" % (name, x.shape[0] / SR, size))
    print("total %d bytes" % total)


if __name__ == "__main__":
    main()
