#!/usr/bin/env python3
"""Synthesize Drift Station's original sound effects and ambience.

Usage:  python3 tools/generate_audio.py   (writes assets/audio/*.wav, prints a level table)

Everything here is synthesized from scratch (no samples, no downloads), so the
output is original and owned by the project. The generator is deterministic:
every sound draws from its own seeded RNG, so re-running reproduces the files.

Dependencies: Python 3 standard library plus numpy (used for vectorised maths
and FFT convolution). Recursive filters are hand-written (TPT state-variable
filter, one-pole), reverb is a synthesized frequency-dependent impulse response,
loops are made seamless by periodic synthesis plus an equal-power end crossfade.

Mix notes (Android first: phone speakers roll off below ~250 Hz):
* every low element (hums, thuds, rumbles) carries harmonics or a mid-range
  body between 150 Hz and 1 kHz so it still reads on a phone speaker;
* ambience is normalised to about -24 dBFS RMS (emergency a little softer),
  effects to about -14..-18 dBFS "active" RMS (RMS of the non-silent part),
  with a look-ahead soft limiter holding every peak at or under -1 dBFS.
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

try:
    import numpy as np
except ImportError:  # pragma: no cover - environment guard
    sys.exit("generate_audio.py needs numpy (pip install numpy)")

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
SR = 44100      # effects
AMB_SR = 22050  # ambience beds (low-frequency material, halves the file size)
TAU = 2.0 * math.pi


# --------------------------------------------------------------------------
# Basic helpers
# --------------------------------------------------------------------------

def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(name.encode("utf-8")) ^ 0x5D51F7)


def timeline(dur: float, sr: int) -> np.ndarray:
    return np.arange(int(round(dur * sr))) / sr


def db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-12))


def undb(d: float) -> float:
    return 10.0 ** (d / 20.0)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)) + 1e-20))


def unit_rms(x: np.ndarray) -> np.ndarray:
    return x / rms(x)


def ramp(t: np.ndarray, t0: float, t1: float) -> np.ndarray:
    """0 before t0, 1 after t1, linear in between."""
    return np.clip((t - t0) / max(t1 - t0, 1e-9), 0.0, 1.0)


def smooth(x: np.ndarray) -> np.ndarray:
    return x * x * (3.0 - 2.0 * x)


def geo(a: float, b: float, x: np.ndarray) -> np.ndarray:
    """Geometric (exponential) interpolation a->b for x in [0, 1]."""
    return a * (b / a) ** x


def strike(t: np.ndarray, t0: float, tau: float, attack: float = 0.0008) -> np.ndarray:
    """Fast attack, exponential decay envelope starting at t0."""
    tt = t - t0
    e = np.exp(-np.maximum(tt, 0.0) / tau) * ramp(tt, 0.0, attack)
    e[tt < 0] = 0.0
    return e


def bell_curve(t: np.ndarray, t0: float, t_peak: float, t1: float, p: float = 1.0) -> np.ndarray:
    """Smooth rise t0->t_peak, smooth fall t_peak->t1."""
    up = smooth(ramp(t, t0, t_peak))
    down = 1.0 - smooth(ramp(t, t_peak, t1))
    return (up * down) ** p


def phase_of(f: np.ndarray, sr: int, phase0: float = 0.0) -> np.ndarray:
    """Running phase for a (possibly swept) frequency array, starting at phase0."""
    f = np.asarray(f, dtype=float)
    ph = TAU * np.cumsum(f) / sr
    return ph - ph[0] + phase0


def additive(f: np.ndarray, sr: int, amps, phase0: float = 0.0, rng=None) -> np.ndarray:
    """Band-limited harmonic oscillator. amps[k-1] is the k-th harmonic level.
    Harmonics fade out smoothly as they approach Nyquist (no aliasing)."""
    f = np.asarray(f, dtype=float)
    ph = phase_of(f, sr, phase0)
    out = np.zeros_like(ph)
    lim = sr * 0.45
    for k, a in enumerate(amps, 1):
        if a == 0.0:
            continue
        mask = np.clip((lim - k * f) / (0.04 * sr), 0.0, 1.0)
        if not mask.any():
            break
        off = 0.0 if rng is None else rng.uniform(0, TAU)
        out += a * mask * np.sin(k * ph + off)
    return out


def saw_amps(n: int, tilt: float = 1.0):
    return [1.0 / (k ** tilt) for k in range(1, n + 1)]


def square_amps(n: int, even: float = 0.0):
    return [(1.0 / k) if k % 2 else even / k for k in range(1, n + 1)]


def sine_sweep(t: np.ndarray, f: np.ndarray, sr: int) -> np.ndarray:
    return np.sin(phase_of(np.broadcast_to(f, t.shape), sr))


def fm(t, fc, ratio, index, sr):
    """Two-operator FM. fc may be swept, index may be an envelope array."""
    fc = np.broadcast_to(np.asarray(fc, float), t.shape)
    pc = phase_of(fc, sr)
    pm = phase_of(fc * ratio, sr)
    return np.sin(pc + np.asarray(index) * np.sin(pm))


def place(buf: np.ndarray, sig: np.ndarray, start: int, wrap: bool = False) -> None:
    """Mix sig into buf at sample index start (optionally wrapping circularly)."""
    n = len(buf)
    if wrap:
        idx = (np.arange(len(sig)) + start) % n
        np.add.at(buf, idx, sig)
        return
    if start >= n:
        return
    end = min(n, start + len(sig))
    buf[start:end] += sig[: end - start]


def softclip(x: np.ndarray, drive: float = 1.5) -> np.ndarray:
    """tanh saturation normalised so that a full-scale input maps to itself."""
    peak = np.max(np.abs(x)) + 1e-12
    y = np.tanh(drive * x / peak) / math.tanh(drive)
    return y * peak


def fades(x: np.ndarray, sr: int, fin: float = 0.001, fout: float = 0.02) -> np.ndarray:
    n_in = max(1, int(fin * sr))
    n_out = max(1, int(fout * sr))
    x = x.copy()
    x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    x[-n_out:] *= np.cos(np.linspace(0.0, math.pi / 2, n_out)) ** 2
    return x


# --------------------------------------------------------------------------
# Filters
# --------------------------------------------------------------------------

def svf(x: np.ndarray, fc, q: float = 0.707, mode: str = "lp", sr: int = SR) -> np.ndarray:
    """Topology-preserving-transform state-variable filter (Zavalishin).
    fc may be an array (per-sample cutoff sweeps). mode: lp / bp (unity peak) / hp."""
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    g = np.tan(math.pi * np.clip(fc, 10.0, sr * 0.47) / sr)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = (g * a1).tolist()
    a3 = (g * g * a1).tolist()
    a1 = a1.tolist()
    xs = x.tolist()
    out = [0.0] * n
    ic1 = ic2 = 0.0
    sel = {"lp": 0, "bp": 1, "hp": 2}[mode]
    for i in range(n):
        v0 = xs[i]
        v3 = v0 - ic2
        v1 = a1[i] * ic1 + a2[i] * v3
        v2 = ic2 + a2[i] * ic1 + a3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if sel == 0:
            out[i] = v2
        elif sel == 1:
            out[i] = k * v1
        else:
            out[i] = v0 - k * v1 - v2
    return np.asarray(out)


def onepole(x: np.ndarray, fc: float, sr: int, mode: str = "lp") -> np.ndarray:
    a = math.exp(-TAU * fc / sr)
    b = 1.0 - a
    xs = x.tolist()
    out = [0.0] * len(xs)
    y = 0.0
    for i, v in enumerate(xs):
        y = b * v + a * y
        out[i] = y
    lp = np.asarray(out)
    return lp if mode == "lp" else x - lp


def spectral(x: np.ndarray, sr: int, mag) -> np.ndarray:
    """Zero-phase circular filter (multiply the spectrum by mag(f)).
    Used for loops (perfectly seamless) and stationary noise shaping."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    return np.fft.irfft(X * mag(f), len(x))


def lp_mag(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def hp_mag(fc, order=2):
    return lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def peak_mag(fc, q, gain_db):
    g = undb(gain_db) - 1.0
    return lambda f: 1.0 + g / (1.0 + ((f / fc - fc / np.maximum(f, 1e-3)) * q) ** 2)


def periodic_noise(n: int, sr: int, mag, rng) -> np.ndarray:
    """Coloured noise synthesized in the frequency domain: exactly periodic over n."""
    f = np.fft.rfftfreq(n, 1.0 / sr)
    spec = (rng.standard_normal(len(f)) + 1j * rng.standard_normal(len(f))) * mag(f)
    spec[0] = 0.0
    return unit_rms(np.fft.irfft(spec, n))


def fftconv(x: np.ndarray, h: np.ndarray, circular: bool = False) -> np.ndarray:
    if circular:
        hh = np.zeros(len(x))
        m = min(len(h), len(x))
        hh[:m] = h[:m]
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(hh), len(x))
    n = len(x) + len(h) - 1
    nfft = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(h, nfft), nfft)
    return y[: len(x)]


# --------------------------------------------------------------------------
# Space: reverb and delay
# --------------------------------------------------------------------------

def make_ir(sr: int, rt60: float, rng, bright: float = 0.5, predelay: float = 0.012,
            early: int = 8, er_span: float = 0.045, metallic: float = 0.0) -> np.ndarray:
    """Synthesized room impulse response with frequency-dependent decay
    (lows ring longest, highs die quickest) and sparse early reflections.
    metallic > 0 adds a few faint resonant modes for a hull/corridor colour."""
    length = int(sr * min(rt60 * 1.15 + predelay, 6.0))
    t = np.arange(length) / sr
    base = rng.standard_normal(length)
    X = np.fft.rfft(base)
    f = np.fft.rfftfreq(length, 1.0 / sr)
    w_low = 1.0 / (1.0 + (f / 450.0) ** 4)
    w_high = (f / 3500.0) ** 4 / (1.0 + (f / 3500.0) ** 4)
    w_mid = np.clip(1.0 - w_low - w_high, 0.0, 1.0)
    ir = np.zeros(length)
    for w, rt in ((w_low, rt60), (w_mid, rt60 * 0.8), (w_high, rt60 * (0.25 + 0.45 * bright))):
        band = np.fft.irfft(X * w, length)
        ir += band * 10.0 ** (-3.0 * t / rt)
    if metallic > 0.0:
        for _ in range(5):
            fm_ = rng.uniform(300.0, 2600.0)
            ir += metallic * 0.02 * np.sin(TAU * fm_ * t + rng.uniform(0, TAU)) * 10.0 ** (-3.0 * t / (rt60 * 0.6))
    onset = ramp(t, predelay, predelay + 0.012)
    ir *= onset
    for _ in range(early):
        d = predelay + rng.uniform(0.0, er_span)
        i = int(d * sr)
        if i < length:
            ir[i] += rng.choice([-1.0, 1.0]) * rng.uniform(0.4, 1.0) * 3.0 * math.exp(-d / 0.05)
    return ir / math.sqrt(np.sum(ir * ir))


def reverb(x: np.ndarray, sr: int, rt60: float, wet: float, rng, dry: float = 1.0,
           circular: bool = False, **kw) -> np.ndarray:
    ir = make_ir(sr, rt60, rng, **kw)
    return dry * x + wet * fftconv(x, ir, circular=circular)


def echo(x: np.ndarray, sr: int, time: float, fb: float, taps: int = 3, lp: float = 4000.0) -> np.ndarray:
    d = int(time * sr)
    y = x.copy()
    tap = x
    for _ in range(taps):
        shifted = np.zeros_like(x)
        if d < len(x):
            shifted[d:] = tap[:-d]
        tap = onepole(shifted, lp, sr) * fb
        y += tap
    return y


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

def modal(t: np.ndarray, t0: float, modes, attack: float = 0.0004, rng=None, jitter: float = 0.0) -> np.ndarray:
    """Struck-object resonator bank: sum of exponentially decaying sines.
    modes = [(freq, decay_tau, amp), ...]."""
    out = np.zeros_like(t)
    tt = t - t0
    m = tt >= 0
    ts = tt[m]
    env = ramp(ts, 0.0, attack)
    for fq, tau, a in modes:
        if rng is not None and jitter:
            fq *= 1.0 + rng.uniform(-jitter, jitter)
        out[m] += a * np.sin(TAU * fq * ts) * np.exp(-ts / tau) * env
    return out


def thump(t: np.ndarray, t0: float, f_end: float, f_start: float, sweep_tau: float,
          tau: float, sr: int, harm: float = 0.3) -> np.ndarray:
    """Pitch-dropping sine kick (with a 2nd harmonic for small speakers)."""
    tt = np.maximum(t - t0, 0.0)
    f = f_end + (f_start - f_end) * np.exp(-tt / sweep_tau)
    ph = phase_of(f, sr)
    sig = np.sin(ph) + harm * np.sin(2.0 * ph + 0.3)
    return sig * strike(t, t0, tau, 0.0015)


def noise_burst(t, t0, tau, rng, fc=None, mode="lp", q=0.7, sr=SR, attack=0.0003):
    n = rng.standard_normal(len(t))
    if fc is not None:
        n = svf(n, fc, q, mode, sr)
    return n * strike(t, t0, tau, attack)


def crackle_gate(n: int, sr: int, rate: float, rng, width: float = 0.0015) -> np.ndarray:
    """Sparse random grains (electrical crackle / fabric crinkle)."""
    g = np.zeros(n)
    count = int(rate * n / sr)
    w = max(2, int(width * sr))
    shape = np.hanning(w)
    for _ in range(count):
        i = int(rng.integers(0, max(1, n - w)))
        g[i:i + w] += shape * rng.uniform(0.2, 1.0)
    return g


def stick_slip(dur: float, sr: int, rate0: float, rate1: float, rng, jitter: float = 0.25) -> np.ndarray:
    """Impulse train with drifting rate: the excitation of a metal creak."""
    n = int(dur * sr)
    x = np.zeros(n)
    t = 0.0
    while True:
        u = t / dur
        rate = rate0 * (rate1 / rate0) ** u * (1.0 + rng.uniform(-jitter, jitter))
        t += 1.0 / rate
        if t >= dur:
            break
        x[int(t * sr)] += rng.uniform(0.4, 1.0) * rng.choice([-1.0, 1.0])
    x += 0.04 * rng.standard_normal(n)
    env = np.sin(np.linspace(0.0, math.pi, n)) ** 1.5
    return x * env


def creak(sr: int, dur: float, base: float, rate0: float, rate1: float, rng,
          ratios=(1.0, 2.32, 4.25, 6.63), taus=(0.09, 0.06, 0.04, 0.025)) -> np.ndarray:
    exc = stick_slip(dur, sr, rate0, rate1, rng)
    th = np.arange(int(0.5 * sr)) / sr
    ir = np.zeros_like(th)
    for i, (r, tau) in enumerate(zip(ratios, taus)):
        ir += (0.75 ** i) * np.sin(TAU * base * r * (1 + rng.uniform(-0.02, 0.02)) * th) * np.exp(-th / tau)
    n = len(exc)
    y = fftconv(np.concatenate([exc, np.zeros(len(ir))]), ir)
    return y[: n + len(ir)]


def chime(t, t0, f, tau, sr, index=1.2, ratio=2.0, rng=None):
    """Clean FM bell: modulation index decays faster than the amplitude."""
    tt = t - t0
    env = strike(t, t0, tau, 0.002)
    idx = index * np.exp(-np.maximum(tt, 0.0) / (tau * 0.35))
    tone = fm(t, f, ratio, idx, sr) + 0.25 * np.sin(phase_of(np.full(t.shape, f * 3.01), sr))
    return tone * env


# --------------------------------------------------------------------------
# Loop helpers (ambience / alarm)
# --------------------------------------------------------------------------

def loop_crossfade(x: np.ndarray, n_loop: int, n_x: int) -> np.ndarray:
    """x has n_loop + n_x samples of a continuous aperiodic signal. Fold the
    overhang back over the start with an equal-power crossfade so the result
    loops seamlessly: out[n_loop-1] -> out[0] continues x[n_loop-1] -> x[n_loop]."""
    out = x[:n_loop].copy()
    w = np.linspace(0.0, math.pi / 2, n_x)
    out[:n_x] = x[:n_x] * np.sin(w) + x[n_loop:n_loop + n_x] * np.cos(w)
    return out


def check_periodic(f: float, length: float) -> float:
    cycles = f * length
    assert abs(cycles - round(cycles)) < 1e-6, f"{f} Hz is not periodic over {length}s"
    return f


# --------------------------------------------------------------------------
# Sounds
# --------------------------------------------------------------------------

def ambience_station():
    sr, L = AMB_SR, 10.0
    rng = rng_for("ambience_station")
    n = int(L * sr)
    t = np.arange(n) / sr

    # 1. Deep reactor hum: two slightly detuned generators (0.3 Hz beating) with a
    #    harmonic series, so phone speakers still hear 192-480 Hz partials.
    hum = np.zeros(n)
    harm = {1: 0.75, 2: 0.6, 3: 0.4, 4: 0.28, 5: 0.17, 6: 0.13, 8: 0.08, 10: 0.045, 12: 0.03}
    for f0, lvl in ((check_periodic(48.0, L), 1.0), (check_periodic(48.3, L), 0.3)):
        for k, a in harm.items():
            hum += lvl * a * np.sin(TAU * f0 * k * t + rng.uniform(0, TAU))
    wobble = 1.0 + 0.07 * np.sin(TAU * 0.1 * t) + 0.04 * np.sin(TAU * 0.3 * t + 1.3)
    hum *= wobble
    # transformer buzz: odd-harmonic saturation of the 96 Hz line, band-limited
    buzz = np.tanh(3.0 * np.sin(TAU * 96.0 * t))
    buzz = spectral(buzz, sr, lambda f: lp_mag(900.0, 2)(f) * hp_mag(150.0, 2)(f))
    buzz *= 1.0 + 0.3 * np.sin(TAU * 0.2 * t + 0.4)

    # 2. Sub-structure rumble (periodic coloured noise)
    sub = periodic_noise(n, sr, lambda f: lp_mag(70.0, 3)(f) * hp_mag(18.0, 2)(f), rng)

    # 3. Air handling: pink-ish duct noise with a broad resonance + fan blade chop
    air = periodic_noise(n, sr, lambda f: (np.maximum(f, 20.0) ** -0.5) * hp_mag(160.0, 2)(f)
                         * lp_mag(4500.0, 2)(f) * peak_mag(900.0, 0.8, 6.0)(f)
                         * peak_mag(2300.0, 2.0, 3.0)(f), rng)
    air *= 1.0 + 0.18 * np.sin(TAU * 23.0 * t) + 0.06 * np.sin(TAU * 0.2 * t + 2.0)
    fan = 0.6 * np.sin(TAU * 184.0 * t) + 0.3 * np.sin(TAU * 368.0 * t + 0.7)
    fan *= 1.0 + 0.2 * np.sin(TAU * 0.1 * t + 0.5)

    # 4. Gusts through vents: aperiodic, so generated long and crossfaded.
    nx = int(1.5 * sr)
    walk = np.cumsum(rng.standard_normal(n + nx))
    walk = spectral(walk - np.linspace(walk[0], walk[-1], n + nx), sr, lp_mag(0.4, 2))
    walk = (walk - walk.min()) / (np.ptp(walk) + 1e-9)
    gust = svf(rng.standard_normal(n + nx), 380.0 * 2.0 ** (1.6 * walk), 0.9, "bp", sr)
    gust *= 0.35 + 0.65 * walk
    gust = loop_crossfade(gust, n, nx)

    # 5. Distant metallic events (wrapped circularly so the loop stays seamless)
    events = np.zeros(n)
    slots = [0.6, 2.4, 4.2, 6.3, 8.4]
    for i, s in enumerate(slots):
        start = int((s + rng.uniform(-0.3, 0.3)) * sr)
        if i == 1:      # deep hull groan
            ev = creak(sr, 1.6, rng.uniform(85, 105), 14.0, 22.0, rng, ratios=(1.0, 2.1, 3.3, 4.9),
                       taus=(0.14, 0.1, 0.07, 0.05)) * 1.1
        elif i == 3:    # thermal ping
            tt = np.arange(int(1.6 * sr)) / sr
            b = rng.uniform(650, 900)
            ev = modal(tt, 0.0, [(b, 0.5, 1.0), (b * 2.76, 0.35, 0.5), (b * 5.40, 0.2, 0.3),
                                 (b * 8.93, 0.12, 0.15)]) * 0.35
        else:           # creak
            ev = creak(sr, rng.uniform(0.6, 1.1), rng.uniform(260, 420), rng.uniform(28, 45),
                       rng.uniform(55, 85), rng)
        place(events, unit_rms(ev) * rng.uniform(0.7, 1.0), start, wrap=True)
    events = spectral(events, sr, lambda f: lp_mag(2600.0, 2)(f) * hp_mag(90.0, 2)(f))
    events = reverb(events, sr, 3.2, 1.6, rng, dry=0.25, circular=True, bright=0.3, predelay=0.03,
                    metallic=1.0)

    mix = (unit_rms(hum) * undb(0.0) + unit_rms(buzz) * undb(-18.0) + sub * undb(-7.0)
           + air * undb(-4.5) + unit_rms(fan) * undb(-24.0) + unit_rms(gust) * undb(-15.0)
           + unit_rms(events) * undb(-15.0))
    mix = spectral(mix, sr, hp_mag(20.0, 2))
    return mix, sr, {"target": -24.0, "measure": "full", "loop": True}


def ambience_emergency():
    sr, L = AMB_SR, 10.0
    rng = rng_for("ambience_emergency")
    n = int(L * sr)
    t = np.arange(n) / sr

    # Brownout profile: three wrapped dips where the power sags.
    dip = np.zeros(n)
    for c, w, d in ((1.7, 0.45, 0.65), (5.2, 0.7, 0.45), (8.0, 0.3, 0.8)):
        c += rng.uniform(-0.2, 0.2)
        dist = (t - c + L / 2) % L - L / 2
        dip += d * np.exp(-0.5 * (dist / w) ** 2)
    dip = np.clip(dip, 0.0, 1.0)

    # Hum at 36 Hz, sagging in pitch and level with the dips. The frequency
    # deviation is mean-free so the phase stays periodic over the loop.
    f0 = check_periodic(36.0, L)
    dev = -0.05 * f0 * dip
    dev -= dev.mean()
    ph = TAU * (f0 * t + np.cumsum(dev) / sr)
    hum = np.zeros(n)
    for k, a in {1: 1.0, 2: 0.65, 3: 0.32, 4: 0.2, 5: 0.1, 6: 0.09, 8: 0.045, 10: 0.02}.items():
        hum += a * np.sin(k * ph + rng.uniform(0, TAU))
    flutter = 1.0 - 0.35 * dip * (0.5 + 0.5 * np.sin(TAU * 11.0 * t)) ** 2
    power = (1.0 - 0.55 * dip) * flutter * (1.0 + 0.08 * np.sin(TAU * 0.1 * t + 0.6))
    hum *= power
    # strained transformer: buzzy 72 Hz that gets uglier as the power fails
    strain = np.tanh(4.0 * np.sin(2.0 * ph + 0.2))
    strain = spectral(strain, sr, lambda f: lp_mag(700.0, 2)(f) * hp_mag(120.0, 2)(f))
    strain *= 0.25 + dip

    # Crackle of arcing relays during the dips
    crk = np.zeros(n)
    for _ in range(38):
        c = rng.uniform(0, L)
        tt = np.arange(int(rng.uniform(0.003, 0.014) * sr)) / sr
        burst = rng.standard_normal(len(tt)) * np.exp(-tt / 0.004)
        place(crk, burst * rng.uniform(0.3, 1.0), int(c * sr), wrap=True)
    crk = spectral(crk, sr, lambda f: hp_mag(1400.0, 2)(f) * lp_mag(3800.0, 2)(f))
    crk *= 0.15 + dip

    # Residual air (fans are dead), sub-structure rumble
    air = periodic_noise(n, sr, lambda f: (np.maximum(f, 20.0) ** -0.7) * hp_mag(90.0, 2)(f)
                         * lp_mag(500.0, 2)(f), rng)
    air *= 1.0 + 0.25 * np.sin(TAU * 0.1 * t + 2.2)
    sub = periodic_noise(n, sr, lambda f: lp_mag(55.0, 3)(f) * hp_mag(16.0, 2)(f), rng)
    leak = periodic_noise(n, sr, lambda f: peak_mag(2900.0, 3.0, 24.0)(f) * lp_mag(3500.0, 2)(f)
                          * hp_mag(1800.0, 2)(f), rng)
    leak *= 0.5 + 0.5 * np.sin(TAU * 0.2 * t + 1.0) ** 2

    # Aperiodic low drift (crossfaded)
    nx = int(1.5 * sr)
    walk = np.cumsum(rng.standard_normal(n + nx))
    walk = spectral(walk - np.linspace(walk[0], walk[-1], n + nx), sr, lp_mag(0.3, 2))
    walk = (walk - walk.min()) / (np.ptp(walk) + 1e-9)
    drift = svf(rng.standard_normal(n + nx), 70.0 * 2.0 ** (1.8 * walk), 1.2, "lp", sr)
    drift = loop_crossfade(drift, n, nx)

    # Deep groans of a stressed hull, plus one dark distant ping
    events = np.zeros(n)
    for s, kind in ((3.2, "groan"), (6.6, "ping"), (9.1, "groan")):
        start = int((s + rng.uniform(-0.25, 0.25)) * sr)
        if kind == "groan":
            ev = creak(sr, rng.uniform(1.6, 2.2), rng.uniform(62, 80), 9.0, 16.0, rng,
                       ratios=(1.0, 2.05, 3.1, 4.4), taus=(0.18, 0.12, 0.08, 0.05))
        else:
            tt = np.arange(int(2.0 * sr)) / sr
            b = rng.uniform(380, 460)
            ev = modal(tt, 0.0, [(b, 0.8, 1.0), (b * 2.76, 0.45, 0.4), (b * 5.4, 0.25, 0.2)]) * 0.3
        place(events, unit_rms(ev), start, wrap=True)
    events = spectral(events, sr, lambda f: lp_mag(1600.0, 2)(f) * hp_mag(50.0, 2)(f))
    events = reverb(events, sr, 3.8, 1.6, rng, dry=0.2, circular=True, bright=0.15, predelay=0.04,
                    metallic=1.0)

    mix = (unit_rms(hum) + unit_rms(strain) * undb(-15.0) + unit_rms(crk) * undb(-27.0)
           + air * undb(-9.0) + sub * undb(-5.0) + leak * undb(-34.0)
           + unit_rms(drift) * undb(-12.0) + unit_rms(events) * undb(-10.0))
    mix = spectral(mix, sr, lambda f: hp_mag(18.0, 2)(f) * lp_mag(5000.0, 1)(f))
    return mix, sr, {"target": -26.0, "measure": "full", "loop": True}


def alarm_pod():
    """Two-tone klaxon (tritone apart), built exactly periodic over 1.2 s."""
    sr, P = SR, 1.2
    rng = rng_for("alarm_pod")
    n = int(P * sr)
    t = np.arange(n) / sr
    half = P / 2
    hi, lo = 622.25, 440.0
    f = np.where(t < half, hi, lo)
    # horn "scoop": each tone starts a little flat and rises into pitch
    local = np.where(t < half, t, t - half)
    f = f * (1.0 - 0.035 * np.exp(-local / 0.035))
    f = f * (1.0 + 0.004 * np.sin(TAU * 5.0 * t))
    # circular smoothing of the frequency steps (8 ms glide)
    k = np.hanning(int(0.008 * sr))
    f = fftconv(f, k / k.sum(), circular=True)
    f = np.roll(f, -len(k) // 2)
    # force an even integer number of cycles so the waveform (and its sub-octave) loops
    cycles = f.sum() / sr
    f *= (2 * round(cycles / 2)) / cycles
    ph = TAU * np.cumsum(f) / sr
    ph -= ph[0]
    amps = [(1.0 / k) * (1.0 if k % 2 else 0.6) for k in range(1, 40)]
    lim = sr * 0.45
    tone = np.zeros(n)
    for kk, a in enumerate(amps, 1):
        tone += a * np.clip((lim - kk * f) / (0.04 * sr), 0.0, 1.0) * np.sin(kk * ph)
    tone += 0.35 * np.sin(0.5 * ph)  # sub-octave body
    # periodic amplitude shape: swell in, slight sag, dip at each change-over
    seg_env = np.minimum(1.0, local / 0.025) * (1.0 - 0.15 * ramp(local, 0.05, half))
    seg_env *= 1.0 - smooth(ramp(local, half - 0.03, half)) * 0.75
    seg_env = 0.25 + 0.75 * seg_env
    seg_env = fftconv(seg_env, k / k.sum(), circular=True)
    seg_env = np.roll(seg_env, -len(k) // 2)
    tone *= seg_env
    # horn formants (circular filter keeps it loopable)
    tone = spectral(tone, sr, lambda fr: hp_mag(280.0, 2)(fr) * lp_mag(5200.0, 2)(fr)
                    * peak_mag(1150.0, 2.0, 8.0)(fr) * peak_mag(2600.0, 3.0, 5.0)(fr))
    tone = softclip(tone, 1.8)
    tone = reverb(tone, sr, 0.9, 0.35, rng, circular=True, bright=0.6, metallic=0.5)
    return tone, sr, {"target": -16.0, "measure": "full", "loop": True, "pattern": True}


def spin_layers(t, s, sr, rng, rotor_lo=30.0, rotor_hi=200.0, whine_lo=250.0, oct_=3.3):
    """Turbine: rotor harmonic series, FM whine, air rush, all driven by spin s in [0,1]."""
    rotor = additive(rotor_lo + (rotor_hi - rotor_lo) * s, sr,
                     [1.0, 0.55, 0.38, 0.25, 0.18, 0.12, 0.09, 0.06], rng=rng)
    fw = whine_lo * 2.0 ** (oct_ * s)
    whine = fm(t, fw, 2.0, 0.7, sr) + 0.45 * np.sin(phase_of(fw * 1.5 * 1.0023, sr))
    rush = svf(rng.standard_normal(len(t)), 300.0 * 2.0 ** (4.0 * s), 0.9, "bp", sr)
    return rotor, whine, rush


def power_up():
    sr, D = SR, 2.5
    rng = rng_for("power_up")
    t = timeline(D, sr)
    T = 1.85  # the lights-on thunk
    s = np.clip(t / T, 0.0, 1.0) ** 1.6
    rotor, whine, rush = spin_layers(t, s, sr, rng)
    after = ramp(t, T, T + 0.001)
    settle = np.exp(-np.maximum(t - T, 0.0) / 0.45)
    duck = 1.0 - 0.35 * bell_curve(t, T - 0.08, T - 0.01, T + 0.02)
    a_rotor = (0.15 + 0.85 * s ** 0.7) * (1.0 - after * (1.0 - 0.6 * settle)) * duck
    a_whine = (s ** 1.5) * (1.0 - after * (1.0 - 0.7 * settle)) * duck
    a_rush = (0.12 + 0.6 * s) * (1.0 - after * (1.0 - 0.4 * settle)) * duck
    spin = 0.55 * rotor * a_rotor + 0.22 * whine * a_whine + 0.35 * unit_rms(rush) * a_rush
    spin = softclip(spin, 1.4)

    thunk = (1.0 * thump(t, T, 44.0, 110.0, 0.03, 0.2, sr, harm=0.4)
             + 0.9 * modal(t, T, [(96, 0.26, 1.0), (182, 0.18, 0.6), (311, 0.12, 0.45), (523, 0.08, 0.3),
                                  (868, 0.06, 0.22), (1447, 0.035, 0.12), (2330, 0.02, 0.08)])
             + 0.5 * noise_burst(t, T, 0.004, rng, 1800.0, "hp", sr=sr)
             + 0.25 * noise_burst(t, T + 0.004, 0.06, rng, 3200.0, "bp", 1.5, sr=sr)
             * crackle_gate(len(t), sr, 900.0, rng))
    lights = additive(np.full(len(t), 60.0), sr, saw_amps(14, 1.2), rng=rng)
    lights *= strike(t, T + 0.005, 0.5, 0.012) * 0.6 + 0.4 * ramp(t, T + 0.005, T + 0.03) * (1 - ramp(t, 2.0, 2.5))
    shimmer = (np.sin(TAU * 1760.0 * t) + 0.6 * np.sin(TAU * 2637.0 * t + 1.0)) * strike(t, T + 0.01, 0.35, 0.02)

    mix = 0.8 * spin + 1.7 * thunk + 0.14 * lights + 0.05 * shimmer
    mix = reverb(mix, sr, 2.0, 0.28, rng, bright=0.45, metallic=0.6)
    mix = onepole(mix, 22.0, sr, "hp")
    return fades(mix, sr, 0.005, 0.3), sr, {"target": -15.0}


def power_down():
    sr, D = SR, 2.0
    rng = rng_for("power_down")
    t = timeline(D, sr)
    t0 = 0.02
    clack = np.zeros_like(t)
    for dt, a in ((0.0, 1.0), (0.011, 0.45), (0.019, 0.2)):
        tc = t0 + dt
        clack += a * (modal(t, tc, [(1850, 0.012, 1.0), (3100, 0.009, 0.7), (4700, 0.006, 0.5),
                                    (650, 0.03, 0.6), (1220, 0.02, 0.4)], rng=rng, jitter=0.03)
                      + 0.7 * thump(t, tc, 90.0, 150.0, 0.01, 0.03, sr, harm=0.5)
                      + 0.5 * noise_burst(t, tc, 0.0018, rng, 1500.0, "hp", sr=sr))
    arc = noise_burst(t, t0, 0.05, rng, 2500.0, "bp", 1.2, sr=sr) * crackle_gate(len(t), sr, 1200.0, rng)
    whomp = thump(t, t0 + 0.01, 28.0, 70.0, 0.4, 0.35, sr, harm=0.35)

    s = np.exp(-np.maximum(t - t0, 0.0) / 0.55)
    rotor, whine, rush = spin_layers(t, s, sr, rng, rotor_lo=25.0, rotor_hi=200.0, whine_lo=220.0, oct_=3.4)
    tail = 1.0 - ramp(t, 1.5, 1.95)
    spin = 0.55 * rotor * s ** 0.5 + 0.22 * whine * s ** 0.8 + 0.35 * unit_rms(rush) * s
    spin *= ramp(t, t0, t0 + 0.004) * tail
    spin = softclip(spin, 1.3)
    sag = 60.0 * (1.0 - 0.2 * ramp(t, t0, 0.4))
    lights = additive(sag, sr, saw_amps(14, 1.2), rng=rng) * strike(t, 0.0, 0.15, 0.002)

    mix = 0.9 * clack + 0.18 * arc + 0.7 * whomp + spin + 0.1 * lights
    mix = reverb(mix, sr, 2.0, 0.28, rng, bright=0.45, metallic=0.6)
    mix = onepole(mix, 22.0, sr, "hp")
    return fades(mix, sr, 0.001, 0.25), sr, {"target": -15.0}


def pickup():
    sr, D = SR, 0.25
    rng = rng_for("pickup")
    t = timeline(D, sr)
    servo = fm(t, 700.0 + 600.0 * ramp(t, 0.0, 0.07), 3.0, 0.5, sr) * strike(t, 0.0, 0.03, 0.005)
    servo = svf(servo, 1600.0, 1.0, "bp", sr)
    grab = (0.5 * noise_burst(t, 0.008, 0.02, rng, 450.0, "bp", 1.2, sr=sr)
            + 0.45 * thump(t, 0.008, 150.0, 210.0, 0.01, 0.03, sr, harm=0.3))
    tc = 0.072
    click = (modal(t, tc, [(2900, 0.012, 1.0), (4600, 0.008, 0.6), (1700, 0.02, 0.5)])
             + 0.6 * noise_burst(t, tc, 0.0012, rng, 2500.0, "hp", sr=sr))
    latch = fm(t, 880.0, 1.41, 0.8 * strike(t, tc, 0.02), sr) * strike(t, tc, 0.05, 0.001)
    thock = thump(t, tc, 200.0, 260.0, 0.008, 0.022, sr, harm=0.2)
    mix = 0.3 * servo + grab + 0.8 * click + 0.28 * latch + 0.45 * thock
    mix = reverb(mix, sr, 0.6, 0.14, rng, bright=0.6)
    return fades(mix, sr, 0.0005, 0.03), sr, {"target": -17.0}


def drop():
    sr, D = SR, 0.45
    rng = rng_for("drop")
    t = timeline(D, sr)
    plate = [(212, 0.18, 0.6), (337, 0.14, 0.55), (523, 0.12, 0.5), (781, 0.1, 0.4), (1103, 0.07, 0.3),
             (1580, 0.05, 0.25), (2240, 0.035, 0.2), (3150, 0.02, 0.12)]
    mix = np.zeros_like(t)
    for t0, a, dk in ((0.003, 1.0, 1.0), (0.085, 0.3, 0.6), (0.132, 0.12, 0.5)):
        modes = [(f, tau * dk, m) for f, tau, m in plate]
        mix += a * (1.0 * thump(t, t0, 70.0, 120.0, 0.015, 0.07, sr, harm=0.5)
                    + 0.8 * modal(t, t0, modes, rng=rng, jitter=0.02)
                    + 0.7 * noise_burst(t, t0, 0.006, rng, 3000.0, "lp", sr=sr))
    mix = softclip(mix, 1.3)
    mix = reverb(mix, sr, 0.8, 0.16, rng, bright=0.5, metallic=0.5)
    return fades(mix, sr, 0.0005, 0.05), sr, {"target": -16.0}


def insert_cell():
    sr, D = SR, 0.8
    rng = rng_for("insert_cell")
    t = timeline(D, sr)
    tc = 0.14
    slide = unit_rms(svf(rng.standard_normal(len(t)), 1200.0 + 1000.0 * ramp(t, 0.0, tc), 2.0, "bp", sr))
    slide *= ramp(t, 0.0, tc) * (1.0 - ramp(t, tc, tc + 0.004)) * (0.7 + 0.3 * np.sin(TAU * 37 * t))
    clunk = (thump(t, tc, 75.0, 110.0, 0.02, 0.06, sr, harm=0.5)
             + 0.8 * modal(t, tc, [(230, 0.12, 0.6), (415, 0.09, 0.45), (610, 0.08, 0.4), (1150, 0.05, 0.3),
                                   (1980, 0.03, 0.2), (3300, 0.015, 0.15)])
             + 0.6 * noise_burst(t, tc, 0.003, rng, 2000.0, "hp", sr=sr))
    hf = 100.0 + 20.0 * smooth(ramp(t, 0.17, 0.4))
    hum = additive(hf, sr, saw_amps(24, 1.0), rng=rng)
    cut = 300.0 * 2.0 ** (3.0 * bell_curve(t, 0.17, 0.38, 0.72))
    hum = svf(hum, cut, 1.2, "lp", sr) * bell_curve(t, 0.17, 0.36, 0.72, 1.2)
    chirp = np.zeros_like(t)
    for t0, f, tau, a in ((0.48, 1318.5, 0.045, 0.8), (0.545, 1975.5, 0.08, 1.0)):
        fr = f * (1.0 + 0.02 * ramp(t, t0, t0 + 0.04))
        chirp += a * (np.sin(phase_of(fr, sr)) + 0.3 * np.sin(phase_of(2 * fr, sr))) * strike(t, t0, tau, 0.003)
    chirp = echo(chirp, sr, 0.09, 0.3, 2, 5000.0)
    mix = 0.25 * slide + clunk + 0.3 * hum + 0.5 * chirp
    mix = reverb(mix, sr, 0.9, 0.16, rng, bright=0.55, metallic=0.4)
    mix = onepole(mix, 25.0, sr, "hp")
    return fades(mix, sr, 0.001, 0.06), sr, {"target": -16.0}


def shuttle_launch_start():
    sr, D = SR, 1.5
    rng = rng_for("shuttle_launch_start")
    t = timeline(D, sr)
    bells = np.zeros_like(t)
    for i, f in enumerate((880.0, 1108.73, 1318.51)):
        bells += chime(t, 0.02 + 0.11 * i, f, 0.35, sr, index=1.0, ratio=2.0)
    bells = echo(bells, sr, 0.18, 0.35, 3, 4500.0)
    s = smooth(ramp(t, 0.25, 1.5)) ** 1.2
    on = ramp(t, 0.2, 0.35)
    fw = 300.0 * 2.0 ** (2.4 * s)
    whine = (fm(t, fw, 1.5, 0.35, sr) + 0.5 * np.sin(phase_of(fw * 1.335, sr))) * (s ** 1.2) * on
    rumble = svf(rng.standard_normal(len(t)), 80.0 + 220.0 * s, 0.8, "lp", sr)
    engine = additive(45.0 + 30.0 * s, sr, [1.0, 0.6, 0.45, 0.3, 0.2, 0.12, 0.08], rng=rng)
    hiss = svf(rng.standard_normal(len(t)), 800.0 * 2.0 ** (2.1 * s), 0.7, "bp", sr)
    mix = (0.3 * bells + 0.22 * whine + 0.45 * unit_rms(rumble) * (0.15 + 0.85 * s) * on
           + 0.3 * engine * s * on + 0.22 * unit_rms(hiss) * s ** 1.5)
    mix = softclip(mix, 1.2)
    mix = reverb(mix, sr, 1.5, 0.22, rng, bright=0.5, metallic=0.5)
    mix = onepole(mix, 25.0, sr, "hp")
    return fades(mix, sr, 0.001, 0.12), sr, {"target": -16.0}


def countdown_tick():
    sr, D = SR, 0.12
    rng = rng_for("countdown_tick")
    t = timeline(D, sr)
    tone = (np.sin(TAU * 1760.0 * t) + 0.4 * np.sin(TAU * 3520.0 * t + 0.5)) * strike(t, 0.001, 0.018, 0.0005)
    body = 0.3 * np.sin(TAU * 880.0 * t) * strike(t, 0.001, 0.012, 0.0005)
    click = 0.5 * noise_burst(t, 0.001, 0.0008, rng, 3000.0, "hp", sr=sr)
    mix = echo(tone + body + click, sr, 0.023, 0.15, 2, 6000.0)
    return fades(mix, sr, 0.0003, 0.02), sr, {"target": -18.0}


def abort():
    sr, D = SR, 0.6
    rng = rng_for("abort")
    t = timeline(D, sr)
    mix = np.zeros_like(t)
    for t0, t1, f, bend in ((0.0, 0.24, 311.13, 0.0), (0.27, 0.58, 220.0, 0.04)):
        fr = f * (1.0 - bend * ramp(t, t1 - 0.15, t1))
        env = ramp(t, t0, t0 + 0.006) * (1.0 - ramp(t, t1 - 0.03, t1))
        v = (additive(fr, sr, square_amps(40, 0.35), rng=rng)
             + 0.7 * additive(fr * 1.0046, sr, saw_amps(40), rng=rng))
        mix += v * env
    mix = svf(mix, 2200.0, 0.8, "lp", sr)
    mix = softclip(mix, 2.5)
    mix = reverb(mix, sr, 0.5, 0.14, rng, bright=0.5)
    return fades(mix, sr, 0.001, 0.02), sr, {"target": -16.0}


def shove():
    sr, D = SR, 0.35
    rng = rng_for("shove")
    t = timeline(D, sr)
    ti = 0.095
    fc = np.where(t < 0.09, geo(500.0, 2200.0, ramp(t, 0.0, 0.09)), geo(2200.0, 700.0, ramp(t, 0.09, 0.3)))
    whoosh = svf(rng.standard_normal(len(t)), fc, 1.2, "bp", sr) * bell_curve(t, 0.0, 0.09, 0.33)
    rustle = svf(rng.standard_normal(len(t)), 2000.0, 0.7, "hp", sr) * crackle_gate(len(t), sr, 320.0, rng, 0.002)
    rustle *= bell_curve(t, 0.0, 0.1, 0.3)
    impact = (thump(t, ti, 75.0, 140.0, 0.012, 0.06, sr, harm=0.8)
              + 0.5 * modal(t, ti, [(190, 0.05, 1.0), (265, 0.04, 0.7), (330, 0.03, 0.4)])
              + 0.6 * noise_burst(t, ti, 0.015, rng, 900.0, "lp", sr=sr)
              + 0.35 * modal(t, ti, [(420, 0.04, 0.4), (980, 0.025, 0.25), (1650, 0.015, 0.15)]))
    mix = 0.38 * unit_rms(whoosh) + 0.3 * rustle + impact
    mix = softclip(mix, 1.6)
    mix = reverb(mix, sr, 0.5, 0.08, rng, bright=0.5)
    return fades(mix, sr, 0.001, 0.03), sr, {"target": -16.0}


def footstep(variant: int):
    sr, D = SR, 0.18
    rng = rng_for(f"footstep_{variant}")
    t = timeline(D, sr)
    weight = (1.0, 0.94, 1.06)[variant]
    t0 = 0.003
    heel = (0.7 * thump(t, t0, 130.0 * weight, 185.0 * weight, 0.01, 0.03, sr, harm=0.5)
            + 0.4 * noise_burst(t, t0, 0.008, rng, 1500.0, "lp", sr=sr))
    ticks = np.zeros_like(t)
    offs = [0.0, rng.uniform(0.006, 0.012), rng.uniform(0.018, 0.03), rng.uniform(0.04, 0.06)]
    if variant == 2:
        offs.append(rng.uniform(0.065, 0.08))
    for i, dt in enumerate(offs):
        ticks += (0.55 ** i) * modal(t, t0 + dt, [(2300, 0.01, 1.0), (3700, 0.007, 0.6), (5300, 0.005, 0.4),
                                                  (1250, 0.02, 0.5)], rng=rng, jitter=0.07)
    grating = modal(t, t0, [(740, 0.05, 0.25), (1130, 0.04, 0.2), (1610, 0.03, 0.12)], rng=rng, jitter=0.05)
    mag = sine_sweep(t, 900.0 + 600.0 * np.exp(-np.maximum(t - t0, 0) / 0.006), sr) * strike(t, t0, 0.012)
    toe_t = t0 + rng.uniform(0.06, 0.075)
    toe = (0.3 * thump(t, toe_t, 150.0 * weight, 200.0, 0.008, 0.02, sr)
           + 0.15 * modal(t, toe_t, [(2500, 0.008, 1.0), (4100, 0.006, 0.5)], rng=rng, jitter=0.05))
    mix = heel + 0.35 * ticks + grating + 0.12 * mag + toe
    mix = reverb(mix, sr, 0.4, 0.08, rng, bright=0.5)
    return fades(mix, sr, 0.0005, 0.02), sr, {"target": -18.0}


def ui_click():
    sr, D = SR, 0.08
    rng = rng_for("ui_click")
    t = timeline(D, sr)
    fr = 1046.5 * (0.98 + 0.02 * ramp(t, 0.0, 0.01))
    tone = fm(t, fr, 2.0, 0.3 * strike(t, 0.0, 0.015, 0.002), sr) * strike(t, 0.0, 0.022, 0.002)
    tone += 0.35 * np.sin(phase_of(2 * fr, sr)) * strike(t, 0.0, 0.012, 0.002)
    tone += 0.3 * np.sin(phase_of(0.5 * fr, sr)) * strike(t, 0.0, 0.02, 0.003)
    tone = reverb(tone, sr, 0.3, 0.08, rng)
    return fades(tone, sr, 0.0005, 0.015), sr, {"target": -20.0}


def pad_voice(t, f, sr, rng, detune_cents=(-8.0, 0.0, 7.0), max_f=6000.0):
    out = np.zeros_like(t)
    f = np.broadcast_to(np.asarray(f, float), t.shape)
    nh = max(4, int(max_f / float(np.max(f))))
    for c in detune_cents:
        out += additive(f * 2.0 ** (c / 1200.0), sr, saw_amps(nh), phase0=rng.uniform(0, TAU))
    return out / len(detune_cents)


def win_crew():
    sr, D = SR, 3.6
    rng = rng_for("win_crew")
    t = timeline(D, sr)
    # Dsus4 -> D major (add9): the G resolves to F# for the "hopeful" lift
    res = smooth(ramp(t, 0.85, 0.97))
    voices = [(146.83, 0.9), (220.0, 0.8), (293.66, 0.75), (392.0 + (369.99 - 392.0) * res, 0.7),
              (440.0, 0.6), (659.26, 0.45)]
    pad = np.zeros_like(t)
    for f, a in voices:
        pad += a * pad_voice(t, f, sr, rng)
    cut = np.where(t < 1.6, geo(450.0, 3800.0, ramp(t, 0.0, 1.6)), geo(3800.0, 2400.0, ramp(t, 1.6, 3.6)))
    pad = svf(pad, cut, 0.9, "lp", sr)
    pad += 0.5 * np.sin(TAU * 73.42 * t) * smooth(ramp(t, 0.0, 1.2))
    pad *= np.sqrt(smooth(ramp(t, 0.0, 0.6))) * (1.0 - smooth(ramp(t, 2.6, 3.6)))
    sparkle = np.zeros_like(t)
    for i, f in enumerate((1174.66, 1479.98, 1760.0, 2349.32)):
        sparkle += chime(t, 0.95 + 0.1 * i, f, 0.6, sr, index=0.8, ratio=2.0)
    sparkle += 1.3 * (chime(t, 0.01, 587.33, 0.9, sr, index=0.9) + 0.7 * chime(t, 0.01, 880.0, 0.8, sr, index=0.7))
    sparkle = echo(sparkle, sr, 0.21, 0.35, 3, 5000.0)
    # shuttle pass: rises, peaks, Doppler-falls away
    pas = bell_curve(t, 0.3, 1.6, 3.4, 1.3)
    roar_cut = np.where(t < 1.6, geo(250.0, 1800.0, ramp(t, 0.3, 1.6)), geo(1800.0, 400.0, ramp(t, 1.6, 3.4)))
    roar = svf(rng.standard_normal(len(t)), roar_cut, 0.8, "lp", sr)
    rumble = svf(rng.standard_normal(len(t)), 120.0, 0.9, "lp", sr)
    fwh = np.where(t < 1.6, geo(600.0, 900.0, ramp(t, 0.3, 1.6)), geo(900.0, 520.0, ramp(t, 1.6, 2.4)))
    whine = fm(t, fwh, 1.5, 0.4, sr)
    shuttle = (unit_rms(roar) + 0.8 * unit_rms(rumble) + 0.25 * whine) * pas
    mix = unit_rms(pad) * 0.5 + 0.11 * sparkle + 0.2 * shuttle
    mix = softclip(mix, 1.2)
    mix = reverb(mix, sr, 2.6, 0.3, rng, bright=0.55, predelay=0.02)
    mix = onepole(mix, 25.0, sr, "hp")
    return fades(mix, sr, 0.005, 0.25), sr, {"target": -15.0}


def win_infiltrator():
    sr, D = SR, 3.6
    rng = rng_for("win_infiltrator")
    t = timeline(D, sr)
    sink = 2.0 ** (-0.3 / 12.0 * smooth(ramp(t, 2.2, 3.5)))  # whole cluster sags 30 cents
    voices = [(65.41, 0.7), (130.81, 0.8), (261.63, 0.6), (277.18, 0.55), (311.13, 0.55), (392.0, 0.45)]
    cl = np.zeros_like(t)
    for f, a in voices:
        cl += a * pad_voice(t, f * sink, sr, rng, detune_cents=(-11.0, 9.0), max_f=3000.0)
    cut = np.where(t < 0.5, geo(1600.0, 500.0, ramp(t, 0.0, 0.5)), geo(500.0, 1300.0, ramp(t, 0.5, 2.2)))
    cl = svf(cl, cut, 1.1, "lp", sr)
    stab = 1.0 * strike(t, 0.0, 0.35, 0.01) + 0.55 * smooth(ramp(t, 0.15, 2.0))
    cl *= np.minimum(stab, 1.1) * (1.0 - smooth(ramp(t, 2.7, 3.6)))
    cl *= 1.0 + 0.12 * np.sin(TAU * 3.1 * t) * ramp(t, 0.5, 1.5)
    boom = (thump(t, 0.0, 35.0, 55.0, 0.2, 0.6, sr, harm=0.5)
            + 0.4 * noise_burst(t, 0.0, 0.08, rng, 400.0, "lp", sr=sr))
    tp = 0.55
    clamp = (modal(t, tp, [(320, 0.2, 1.0), (710, 0.15, 0.7), (1260, 0.1, 0.5), (2050, 0.06, 0.3)])
             + 0.5 * thump(t, tp, 80.0, 130.0, 0.02, 0.08, sr))
    hiss = noise_burst(t, tp + 0.01, 0.15, rng, 2000.0, "hp", sr=sr, attack=0.01)
    thrust_env = bell_curve(t, tp + 0.08, 1.1, 3.2, 1.2)
    tcut = np.where(t < 1.1, geo(400.0, 2500.0, ramp(t, tp, 1.1)), geo(2500.0, 500.0, ramp(t, 1.1, 3.2)))
    thrust = svf(rng.standard_normal(len(t)), tcut, 0.9, "bp", sr)
    fwh = np.where(t < 1.1, geo(500.0, 1400.0, ramp(t, tp, 1.1)), geo(1400.0, 850.0, ramp(t, 1.1, 2.6)))
    whine = fm(t, fwh, 2.0, 0.5, sr) * thrust_env
    pod = 0.5 * clamp + 0.2 * hiss + 0.5 * unit_rms(thrust) * 0.25 * thrust_env + 0.08 * whine
    mix = 0.55 * unit_rms(cl) * 0.6 + 0.35 * boom + pod
    mix = softclip(mix, 1.4)
    mix = reverb(mix, sr, 3.0, 0.35, rng, bright=0.35, predelay=0.025, metallic=0.8)
    mix = onepole(mix, 22.0, sr, "hp")
    return fades(mix, sr, 0.003, 0.3), sr, {"target": -15.0}


SOUNDS = {
    "ambience_station": ambience_station,
    "ambience_emergency": ambience_emergency,
    "alarm_pod": alarm_pod,
    "power_up": power_up,
    "power_down": power_down,
    "pickup": pickup,
    "drop": drop,
    "insert_cell": insert_cell,
    "shuttle_launch_start": shuttle_launch_start,
    "countdown_tick": countdown_tick,
    "abort": abort,
    "shove": shove,
    "footstep_1": lambda: footstep(0),
    "footstep_2": lambda: footstep(1),
    "footstep_3": lambda: footstep(2),
    "ui_click": ui_click,
    "win_crew": win_crew,
    "win_infiltrator": win_infiltrator,
}


# --------------------------------------------------------------------------
# Levels, limiting, output
# --------------------------------------------------------------------------

def active_rms(x: np.ndarray, sr: int, win: float = 0.05, gate_db: float = 20.0) -> float:
    """RMS of the non-silent part: 50 ms windows within gate_db of the loudest."""
    w = max(8, int(win * sr))
    hop = w // 2
    if len(x) <= w:
        return rms(x)
    energies = np.array([np.mean(x[i:i + w] ** 2) for i in range(0, len(x) - w + 1, hop)])
    gate = energies.max() * 10.0 ** (-gate_db / 10.0)
    return float(math.sqrt(np.mean(energies[energies >= gate]) + 1e-20))


def limiter(x: np.ndarray, sr: int, ceiling_db: float = -1.0, look: float = 0.0015,
            release: float = 0.05, circular: bool = False) -> np.ndarray:
    """Look-ahead peak limiter (offline, zero latency). Gain never exceeds what
    each sample needs, and recovers with a smooth release."""
    c = undb(ceiling_db)
    need = np.minimum(1.0, c / np.maximum(np.abs(x), 1e-12))
    if need.min() >= 1.0:
        return x
    W = max(1, int(look * sr))
    roll = (lambda a, k: np.roll(a, k)) if circular else None
    g = need.copy()
    pad = np.concatenate([np.ones(W), need, np.ones(W)])
    for k in range(-W, W + 1):
        if circular:
            g = np.minimum(g, roll(need, k))
        else:
            g = np.minimum(g, pad[W + k:W + k + len(x)])
    ker = np.ones(W) / W
    g = np.convolve(np.concatenate([np.ones(W), g, np.ones(W)]), ker, "same")[W:W + len(x)]
    g = np.minimum(g, 1.0)
    # release smoothing (only slows gain recovery, so it stays <= need)
    a = 1.0 - math.exp(-1.0 / (release * sr))
    gl = g.tolist()
    y = gl[0]
    for i, v in enumerate(gl):
        y = v if v < y else y + (v - y) * a
        gl[i] = y
    out = x * np.asarray(gl)
    return np.clip(out, -c, c)


def finish(x: np.ndarray, sr: int, meta: dict) -> np.ndarray:
    measure = meta.get("measure", "active")
    loop = meta.get("loop", False)
    m = rms if measure == "full" else (lambda v: active_rms(v, sr))
    for _ in range(4):
        x = x * undb(meta["target"] - db(m(x)))
        x = limiter(x, sr, -1.0, circular=loop)
    return x


def write_wav(path: Path, x: np.ndarray, sr: int, loop: bool = False) -> None:
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2").tobytes()
    n = len(x)
    chunks = [b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16)]
    if loop:  # sampler chunk with one forward loop over the whole file
        smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    data = b"data" + struct.pack("<I", len(pcm)) + pcm
    if len(pcm) % 2:
        data += b"\x00"
    chunks.append(data)
    body = b"WAVE" + b"".join(chunks)
    path.write_bytes(b"RIFF" + struct.pack("<I", len(body)) + body)


def loop_seam(x: np.ndarray) -> float:
    """Jump across the loop point relative to the typical sample-to-sample step."""
    step = np.abs(np.diff(x))
    return float(abs(x[0] - x[-1]) / (np.percentile(step, 99) + 1e-12))


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    print(f"{'file':<26}{'sec':>6}{'kB':>7}{'peak':>8}{'rms':>8}{'active':>8}  notes")
    for name, fn in SOUNDS.items():
        x, sr, meta = fn()
        x = np.asarray(x, dtype=float)
        x = x - (x.mean() if meta.get("loop") else 0.0)
        x = finish(x, sr, meta)
        path = OUT / f"{name}.wav"
        write_wav(path, x, sr, loop=meta.get("loop", False) and not meta.get("pattern", False))
        size = path.stat().st_size
        total += size
        q = np.round(x * 32767.0) / 32767.0
        clipped = int(np.sum(np.abs(q) >= 0.999))
        notes = []
        if meta.get("loop"):
            notes.append(f"loop seam {loop_seam(q):.2f}x")
        if clipped:
            notes.append(f"CLIPPED {clipped}")
        print(f"{name + '.wav':<26}{len(x) / sr:6.2f}{size / 1024:7.0f}{db(np.max(np.abs(q))):8.1f}"
              f"{db(rms(q)):8.1f}{db(active_rms(q, sr)):8.1f}  {' '.join(notes)}")
    print(f"total {total / 1024 / 1024:.2f} MB in {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
