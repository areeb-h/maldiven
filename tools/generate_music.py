#!/usr/bin/env python3
"""Synthesize Drift Station's music: the 80 s trailer score and three in-game loops.

Usage:  python3 tools/generate_music.py            (all)
        python3 tools/generate_music.py trailer    (only the trailer + cue sheet)
        python3 tools/generate_music.py loops      (only the in-game loops)

Writes assets/audio/music/:
  trailer_theme.wav    80.5 s, 44.1 kHz stereo, mastered ~-14 LUFS, peaks <= -1 dBFS; timed to
                       keyart's cut (CUT dict mirrors tools/trailer/cut.gd: edit it and re-run)
  trailer_cues.txt     timestamps of every hit, generated from the same event list
  lobby_theme.wav      32 s loop, 90 BPM   (chill, curious)          ~-23 LUFS
  round_tension.wav    32 s loop, 75 BPM   (subtle, sparse)           ~-27 LUFS
  extraction_drive.wav 30 s loop, 128 BPM  (urgent)                   ~-21 LUFS
The in-game loops are 22.05 kHz stereo, exactly periodic (every tail wraps into
the start and all effects are processed in steady state), get a gentle dip in
the 1-3 kHz voice band so proximity chat sits on top, and carry a WAV loop chunk.

Everything is synthesized here (PolyBLEP supersaws, additive "filtered saw"
synths with time-varying cutoff, FM keys/bells/plucks, synthesized drums,
STFT-swept noise risers, a block-vectorised Freeverb, ping-pong delay, glue
compression, BS.1770-style loudness and a look-ahead limiter), deterministic
(seeded), and original: owned by the project. Needs numpy; reuses the DSP
helpers in generate_audio.py.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_audio as ga  # noqa: E402
from generate_audio import np, TAU, ramp, smooth, strike, geo, undb, db  # noqa: E402

ROOT = ga.ROOT
OUT = ROOT / "assets" / "audio" / "music"
TRAILER_SR = 44100
LOOP_SR = 22050

NOTE_PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
           "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(name: str) -> float:
    pc, octave = (name[:2], name[2:]) if name[1:2] in "#b" else (name[:1], name[1:])
    midi = 12 * (int(octave) + 1) + NOTE_PC[pc]
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def chord(*names):
    return [hz(n) for n in names]


# --------------------------------------------------------------------------
# Mixer
# --------------------------------------------------------------------------

def pan_gains(pan):
    a = (np.clip(pan, -1.0, 1.0) + 1.0) * math.pi / 4.0
    return np.cos(a), np.sin(a)


def to_stereo(sig, pan=0.0):
    if sig.ndim == 2:
        return sig
    gl, gr = pan_gains(np.asarray(pan, float))
    return np.vstack([sig * gl, sig * gr])


class Mix:
    """Stereo dry bus plus reverb and delay send buses. With loop=True, sounds
    running past the end wrap around to the start (exactly what a looping
    player would hear)."""

    def __init__(self, dur: float, sr: int, loop: bool = False):
        self.sr = sr
        self.n = int(round(dur * sr))
        self.loop = loop
        self.dry = np.zeros((2, self.n))
        self.rev = np.zeros((2, self.n))
        self.dly = np.zeros((2, self.n))

    def _put(self, buf, st, start):
        n, m = self.n, st.shape[1]
        if not self.loop:
            if start >= n:
                return
            if start < 0:
                st, m, start = st[:, -start:], m + start, 0
            end = min(n, start + m)
            buf[:, start:end] += st[:, :end - start]
            return
        pos, off = start % n, 0
        while off < m:
            take = min(m - off, n - pos)
            buf[:, pos:pos + take] += st[:, off:off + take]
            off += take
            pos = 0

    def add(self, sig, t0: float, pan=0.0, gain: float = 1.0, rev: float = 0.0, dly: float = 0.0):
        st = to_stereo(np.asarray(sig, float), pan) * gain
        start = int(round(t0 * self.sr))
        self._put(self.dry, st, start)
        if rev:
            self._put(self.rev, st * rev, start)
        if dly:
            self._put(self.dly, st * dly, start)


def steady(fn, x, loop: bool):
    """Run a stateful process on a loop in steady state: process three copies
    and keep the middle one, so the result wraps seamlessly."""
    if not loop:
        return fn(x)
    n = x.shape[-1]
    y = fn(np.concatenate([x, x, x], axis=-1))
    return y[..., n:2 * n]


# --------------------------------------------------------------------------
# Oscillators and synths
# --------------------------------------------------------------------------

def polyblep_saw(f, sr, phase0=0.0):
    f = np.asarray(f, float)
    dt = f / sr
    ph = (phase0 + np.cumsum(dt) - dt[0]) % 1.0
    y = 2.0 * ph - 1.0
    m = ph < dt
    tt = ph[m] / dt[m]
    y[m] -= tt + tt - tt * tt - 1.0
    m = ph > 1.0 - dt
    tt = (ph[m] - 1.0) / dt[m]
    y[m] -= tt * tt + tt + tt + 1.0
    return y


def supersaw(f0, n, sr, rng, voices=7, spread=0.22, width=0.9, vib=0.0, period=None):
    """Detuned saw stack (spread in semitones, edge to edge), voices panned across the field.
    period: quantise every voice to whole cycles over this many seconds (seamless loops)."""
    out = np.zeros((2, n))
    t = np.arange(n) / sr
    offs = np.linspace(-1.0, 1.0, voices)
    for o in offs:
        drift = 1.0 + vib * np.sin(TAU * rng.uniform(0.1, 0.3) * t + rng.uniform(0, TAU))
        fv = f0 * 2.0 ** (o * spread / 12.0)
        if period:
            fv, drift = round(fv * period) / period, 1.0
        f = np.full(n, fv) * drift
        v = polyblep_saw(f, sr, rng.uniform(0, 1)) * (1.0 if abs(o) < 1e-9 else 0.8)
        out += to_stereo(v, o * width)
    return out / math.sqrt(voices)


def lp_resp(fk, fc, res=0.0, order=2):
    h = 1.0 / np.sqrt(1.0 + (fk / fc) ** (2 * order))
    if res:
        h = h * (1.0 + res * np.exp(-0.5 * (np.log2(fk / fc) / 0.25) ** 2))
    return h


def filtered_saw(f0, n, sr, fc, rng, res=0.0, square=0.0, order=2):
    """Additive saw (square mix) through a time-varying resonant low-pass: each
    harmonic is weighted by the filter response at its own frequency, so cutoff
    envelopes are exact, alias-free and fully vectorised."""
    t = np.arange(n) / sr
    fc = np.broadcast_to(np.asarray(fc, float), (n,))
    nh = int(min(0.45 * sr / f0, 3.5 * float(np.max(fc)) / f0 + 2))
    out = np.zeros(n)
    for k in range(1, max(nh, 1) + 1):
        a = 1.0 / k
        if k % 2 == 0:
            a *= 1.0 - square
        if a == 0.0:
            continue
        out += a * lp_resp(k * f0, fc, res, order) * np.sin(TAU * k * f0 * t + rng.uniform(0, TAU))
    return out


def fm_tone(f, n, sr, ratio, index, tau, attack=0.002, rel=0.0):
    t = np.arange(n) / sr
    env = ramp(t, 0.0, attack) * np.exp(-t / tau)
    if rel:
        env *= 1.0 - smooth(ramp(t, (n / sr) - rel, n / sr))
    return np.sin(TAU * f * t + index * np.sin(TAU * f * ratio * t)) * env


def pluck(f, dur, sr, bright=2.5):
    n = int(dur * sr)
    t = np.arange(n) / sr
    idx = bright * np.exp(-t / 0.05) + 0.2
    return (np.sin(TAU * f * t + idx * np.sin(TAU * 2.0 * f * t)) * ramp(t, 0, 0.002) * np.exp(-t / (dur * 0.45))
            + 0.3 * np.sin(TAU * 2 * f * t) * np.exp(-t / 0.08))


def bell(f, dur, sr, index=1.4, ratio=3.5):
    n = int(dur * sr)
    t = np.arange(n) / sr
    idx = index * np.exp(-t / (dur * 0.2))
    return (np.sin(TAU * f * t + idx * np.sin(TAU * f * ratio * t)) * ramp(t, 0, 0.003) * np.exp(-t / (dur * 0.35))
            + 0.25 * np.sin(TAU * f * 2.0 * t) * np.exp(-t / (dur * 0.15)))


def epiano(f, dur, sr):
    """FM electric piano: body (1:1) plus a short bright tine (14:1)."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    body = np.sin(TAU * f * t + (1.1 * np.exp(-t / 0.35) + 0.15) * np.sin(TAU * f * t))
    tine = np.sin(TAU * f * t + 0.6 * np.exp(-t / 0.015) * np.sin(TAU * 14.0 * f * t)) * np.exp(-t / 0.05)
    env = ramp(t, 0, 0.003) * np.exp(-t / 1.4) * (1.0 - smooth(ramp(t, dur - 0.15, dur)))
    return (body + 0.35 * tine) * env


def stft_filter(x, sr, fc_at, kind="lp", order=2, q=1.0, nfft=2048, hop=512):
    """Time-varying zero-phase filter by STFT overlap-add (sqrt-Hann, 75 % overlap).
    fc_at(times) -> cutoff/centre per frame. kind: lp / hp / bp."""
    n = len(x)
    win = np.sqrt(np.hanning(nfft + 1)[:-1])
    pad = np.concatenate([np.zeros(nfft), x, np.zeros(nfft)])
    frames = 1 + (len(pad) - nfft) // hop
    idx = np.arange(nfft)[None, :] + hop * np.arange(frames)[:, None]
    X = np.fft.rfft(pad[idx] * win, axis=1)
    centres = (np.arange(frames) * hop + nfft / 2 - nfft) / sr
    fc = np.maximum(np.asarray(fc_at(centres), float), 10.0)[:, None]
    f = np.maximum(np.fft.rfftfreq(nfft, 1.0 / sr), 1.0)[None, :]
    if kind == "lp":
        H = 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))
    elif kind == "hp":
        H = 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))
    else:
        H = 1.0 / np.sqrt(1.0 + (q * (f / fc - fc / f)) ** 2)
    Y = np.fft.irfft(X * H, nfft, axis=1) * win
    out = np.zeros(len(pad))
    for i in range(frames):
        out[i * hop:i * hop + nfft] += Y[i]
    return out[nfft:nfft + n] / 2.0


def noise(n, rng):
    return rng.standard_normal(n)


# --------------------------------------------------------------------------
# Drums (rendered once per variant, reused)
# --------------------------------------------------------------------------

def kick(sr, rng, weight=1.0, dur=0.55):
    t = ga.timeline(dur, sr)
    f = 44.0 * weight + 110.0 * np.exp(-t / 0.03) + 260.0 * np.exp(-t / 0.004)
    body = np.sin(ga.phase_of(f, sr)) * (np.exp(-t / (0.22 * weight)) * ramp(t, 0, 0.001))
    click = ga.noise_burst(t, 0.0, 0.003, rng, 2500.0, "hp", sr=sr) * 0.35
    return ga.softclip(body + click, 2.0)


def snare(sr, rng, dur=0.4):
    t = ga.timeline(dur, sr)
    tone = (np.sin(TAU * 185.0 * t) * np.exp(-t / 0.07) + 0.6 * np.sin(TAU * 330.0 * t) * np.exp(-t / 0.045))
    nz = ga.svf(noise(len(t), rng), 4200.0, 0.6, "bp", sr) * 1.6 + ga.svf(noise(len(t), rng), 2000.0, 0.7, "hp", sr)
    nz *= strike(t, 0.0, 0.11, 0.001)
    return ga.softclip(0.7 * tone * ramp(t, 0, 0.001) + 0.8 * nz, 1.6)


def clap(sr, rng, dur=0.35):
    t = ga.timeline(dur, sr)
    nz = ga.svf(noise(len(t), rng), 1300.0, 1.2, "bp", sr)
    env = np.zeros_like(t)
    for d in (0.0, 0.011, 0.022):
        env += strike(t, d, 0.008, 0.0005)
    env += 0.7 * strike(t, 0.03, 0.09, 0.001)
    return nz * env


def hat(sr, rng, open_=False):
    dur = 0.35 if open_ else 0.08
    t = ga.timeline(dur, sr)
    metal = np.zeros_like(t)
    for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0):
        metal += np.sign(np.sin(TAU * f * 1.9 * t + rng.uniform(0, TAU)))
    x = metal * 0.15 + noise(len(t), rng)
    x = ga.svf(x, min(7000.0, sr * 0.4), 0.7, "hp", sr)
    return x * strike(t, 0.0, 0.12 if open_ else 0.018, 0.0005)


def tick(sr, rng, f=3200.0):
    t = ga.timeline(0.06, sr)
    return (ga.modal(t, 0.0, [(f, 0.006, 1.0), (f * 1.53, 0.004, 0.5), (f * 0.61, 0.01, 0.4)])
            + 0.3 * ga.noise_burst(t, 0.0, 0.0008, rng, 2000.0, "hp", sr=sr))


def tom(sr, rng, f=110.0):
    t = ga.timeline(0.6, sr)
    return (ga.thump(t, 0.0, f, f * 2.0, 0.02, 0.18, sr, harm=0.5)
            + 0.3 * ga.noise_burst(t, 0.0, 0.03, rng, 900.0, "lp", sr=sr))


def taiko(sr, rng, dur=1.6):
    t = ga.timeline(dur, sr)
    return (ga.thump(t, 0.0, 48.0, 150.0, 0.03, 0.45, sr, harm=0.6)
            + 0.5 * ga.modal(t, 0.0, [(95, 0.3, 1.0), (152, 0.22, 0.6), (231, 0.15, 0.4), (340, 0.1, 0.25)])
            + 0.4 * ga.noise_burst(t, 0.0, 0.06, rng, 700.0, "lp", sr=sr))


def sub_boom(sr, dur=2.5, f_end=31.0):
    t = ga.timeline(dur, sr)
    return ga.thump(t, 0.0, f_end, 110.0, 0.08, 0.9, sr, harm=0.35)


def crash(sr, rng, dur=2.5):
    t = ga.timeline(dur, sr)
    x = noise(len(t), rng)
    for f in (3150.0, 4720.0, 5830.0, 7110.0):
        x += 0.6 * np.sin(TAU * f * t + rng.uniform(0, TAU)) * np.exp(-t / 0.6)
    x = ga.svf(x, min(3500.0, sr * 0.3), 0.7, "hp", sr)
    return x * strike(t, 0.0, dur * 0.3, 0.002)


def heartbeat(sr, rng):
    t = ga.timeline(0.6, sr)
    lub = ga.thump(t, 0.0, 48.0, 95.0, 0.02, 0.09, sr, harm=0.8)
    dub = 0.7 * ga.thump(t, 0.16, 52.0, 105.0, 0.02, 0.08, sr, harm=0.8)
    return ga.onepole(lub + dub, 900.0, sr)


# --------------------------------------------------------------------------
# Effects and mastering
# --------------------------------------------------------------------------

def _comb(x, D, fb, damp):
    """buffer[n] = x[n] + fb * lowpass(buffer[n-D]); output = buffer[n-D].
    Vectorised in blocks of D samples (every block only reads older blocks)."""
    n = len(x)
    y = np.zeros(n)
    a = 1.0 - damp
    for s in range(0, n, D):
        e = min(s + D, n)
        if s >= D:
            d0 = y[s - D:e - D]
            d1 = y[s - D - 1:e - D - 1] if s - D >= 1 else np.concatenate([[0.0], y[0:e - D - 1]])
            y[s:e] = x[s:e] + fb * (a * d0 + damp * d1)
        else:
            y[s:e] = x[s:e]
    out = np.zeros(n)
    out[D:] = y[:-D]
    return out


def _allpass(x, D, g=0.5):
    v = _comb(x, D, g, 0.0)  # v delayed by D: v[n-D]
    # Freeverb allpass: buf[n] = x[n] + g*buf[n-D]; out = buf[n-D] - x[n]
    return v - x


def freeverb(st, sr, room=0.8, damp=0.4, width=1.0, predelay=0.02):
    """Freeverb (8 damped combs + 4 allpasses per channel, 23-sample stereo spread)."""
    scale = sr / 44100.0
    combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    aps = [556, 441, 341, 225]
    fb = room * 0.28 + 0.7
    dmp = damp * 0.4
    mono = 0.5 * (st[0] + st[1])
    pd = int(predelay * sr)
    if pd:
        mono = np.concatenate([np.zeros(pd), mono[:-pd]])
    outs = []
    for spread in (0, 23):
        acc = np.zeros_like(mono)
        for c in combs:
            acc += _comb(mono, max(2, int((c + spread) * scale)), fb, dmp)
        for a in aps:
            acc = _allpass(acc, max(2, int((a + spread) * scale)))
        outs.append(acc)
    wl, wr = outs
    w1, w2 = (width / 2 + 0.5), ((1 - width) / 2)
    out = np.vstack([wl * w1 + wr * w2, wr * w1 + wl * w2])
    return out * (ga.rms(mono) / (ga.rms(out) + 1e-12))


def pingpong(st, sr, time, fb=0.4, taps=5, lp=4000.0, loop=False):
    d = int(time * sr)
    mono = 0.5 * (st[0] + st[1])
    out = np.zeros_like(st)
    tap = mono
    for k in range(1, taps + 1):
        tap = ga.spectral(tap, sr, ga.lp_mag(lp, 1)) * fb
        sh = np.roll(tap, d * k) if loop else np.concatenate([np.zeros(min(d * k, len(tap))), tap[:max(0, len(tap) - d * k)]])
        out[(k + 1) % 2] += sh
    return out


def spectral_st(st, sr, mag):
    return np.vstack([ga.spectral(st[0], sr, mag), ga.spectral(st[1], sr, mag)])


def mono_bass(st, sr, below=120.0):
    """Collapse the side signal below `below` Hz (tight, mono-safe low end)."""
    m, s = 0.5 * (st[0] + st[1]), 0.5 * (st[0] - st[1])
    s = ga.spectral(s, sr, ga.hp_mag(below, 2))
    return np.vstack([m + s, m - s])


def widen(st, amount=1.25):
    m, s = 0.5 * (st[0] + st[1]), 0.5 * (st[0] - st[1]) * amount
    return np.vstack([m + s, m - s])


def k_weight(x, sr):
    shelf = lambda f: 1.0 + (undb(4.0) - 1.0) * (f / 1500.0) ** 2 / (1.0 + (f / 1500.0) ** 2)
    return ga.spectral(x, sr, lambda f: shelf(f) * ga.hp_mag(38.0, 2)(f))


def lufs(st, sr, block=0.4, hop=0.1):
    """BS.1770-style integrated loudness (K-weighting approximated in the
    frequency domain, 400 ms blocks, absolute and relative gates)."""
    z = [k_weight(c, sr) ** 2 for c in st]
    b, h = int(block * sr), int(hop * sr)
    e = np.array([sum(np.mean(zc[i:i + b]) for zc in z) for i in range(0, st.shape[1] - b + 1, h)])
    loud = -0.691 + 10.0 * np.log10(e + 1e-20)
    e = e[loud > -70.0]
    if len(e) == 0:
        return -99.0
    rel = -0.691 + 10.0 * math.log10(np.mean(e)) - 10.0
    e = e[(-0.691 + 10.0 * np.log10(e)) > rel]
    return -0.691 + 10.0 * math.log10(np.mean(e))


def short_term(st, sr, t0, t1):
    a, b = int(t0 * sr), int(t1 * sr)
    seg = st[:, a:b]
    z = sum(np.mean(k_weight(c, sr) ** 2) for c in seg)
    return -0.691 + 10.0 * math.log10(z + 1e-20)


def glue(st, sr, thresh_db=-18.0, ratio=2.0, attack=0.01, release=0.18):
    """Linked RMS bus compressor (5 ms analysis blocks)."""
    blk = max(1, int(0.005 * sr))
    n = st.shape[1]
    nb = n // blk + 1
    padded = np.zeros((2, nb * blk))
    padded[:, :n] = st
    lvl = np.sqrt(np.mean(padded.reshape(2, nb, blk) ** 2, axis=(0, 2)) + 1e-12)
    over = np.maximum(20.0 * np.log10(lvl) - thresh_db, 0.0)
    want = -over * (1.0 - 1.0 / ratio)
    aa, ar = math.exp(-0.005 / attack), math.exp(-0.005 / release)
    g, cur = np.zeros(nb), 0.0
    for i, w in enumerate(want.tolist()):
        cur = aa * cur + (1 - aa) * w if w < cur else ar * cur + (1 - ar) * w
        g[i] = cur
    gs = np.interp(np.arange(n), np.arange(nb) * blk + blk / 2, g)
    return st * 10.0 ** (gs / 20.0)


def limit_st(st, sr, ceiling_db=-1.0, loop=False):
    peak = np.max(np.abs(st), axis=0)
    gain_ref = np.where(peak > 1e-12, peak, 1e-12)
    # run the mono limiter on the linked peak signal, then apply its gain to both channels
    lim = ga.limiter(gain_ref, sr, ceiling_db, look=0.002, release=0.08, circular=loop)
    g = lim / gain_ref
    return np.clip(st * g, -undb(ceiling_db), undb(ceiling_db))


def master(st, sr, target, loop=False, voice_dip=False, comp=True, gate=None):
    st = spectral_st(st, sr, ga.hp_mag(25.0, 2))
    if voice_dip:  # leave room for speech: gentle wide dip around 1.8 kHz
        st = spectral_st(st, sr, ga.peak_mag(1800.0, 0.6, -3.5))
    st = mono_bass(st, sr)
    if gate is not None:
        st = gate(st)
    if comp:  # normalise first so the compressor always sees the same level
        st = st * undb(target - lufs(st, sr))
        st = steady(lambda v: glue(v, sr, thresh_db=target - 4.0, ratio=2.0), st, loop)
    for _ in range(5):
        st = st * undb(target - lufs(st, sr))
        st = steady(lambda v: limit_st(v, sr, -1.0), st, loop)
    return st


def write_stereo(path: Path, st: np.ndarray, sr: int, loop: bool) -> None:
    import struct
    inter = np.empty(st.shape[1] * 2)
    inter[0::2], inter[1::2] = st[0], st[1]
    pcm = np.clip(np.round(inter * 32767.0), -32768, 32767).astype("<i2").tobytes()
    n = st.shape[1]
    chunks = [b"fmt " + struct.pack("<IHHIIHH", 16, 1, 2, sr, sr * 4, 4, 16)]
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    chunks.append(b"data" + struct.pack("<I", len(pcm)) + pcm)
    body = b"WAVE" + b"".join(chunks)
    path.write_bytes(b"RIFF" + struct.pack("<I", len(body)) + body)


def env_ahr(n, sr, attack, release, curve=1.0):
    t = np.arange(n) / sr
    dur = n / sr
    return (smooth(ramp(t, 0.0, attack)) * (1.0 - smooth(ramp(t, dur - release, dur)))) ** curve


def pad_chord(freqs, dur, sr, rng, fc, attack=0.8, release=0.8, spread=0.2, voices=5, sub=True):
    """Supersaw chord through an STFT low-pass (fc: number or function of time)."""
    n = int(dur * sr)
    st = np.zeros((2, n))
    for f in freqs:
        st += supersaw(f, n, sr, rng, voices=voices, spread=spread, vib=0.0007)
    if sub:
        t = np.arange(n) / sr
        st += 0.5 * np.sin(TAU * min(freqs) / 2.0 * t)[None, :]
    fc_fn = fc if callable(fc) else (lambda tt: np.full(len(tt), fc))
    st = np.vstack([stft_filter(c, sr, fc_fn) for c in st])
    return st * env_ahr(n, sr, attack, release)[None, :] / math.sqrt(len(freqs))


def brass(freqs, dur, sr, rng, peak=3500.0, base=300.0, att=0.05, tau=0.35, detune=6.0, res=0.6):
    """Brassy stab: filtered saws with a fast opening cutoff envelope."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    fc = base + peak * (1.0 - np.exp(-t / att)) * np.exp(-t / tau) + 0.15 * peak
    st = np.zeros((2, n))
    for i, f in enumerate(freqs):
        for c, pan in ((-detune, -0.5), (detune, 0.5)):
            v = filtered_saw(f * 2.0 ** (c / 1200.0), n, sr, fc, rng, res=res)
            st += to_stereo(v, pan * (0.4 + 0.6 * (i % 2)))
    env = ramp(t, 0.0, 0.01) * (0.6 + 0.4 * np.exp(-t / tau)) * (1.0 - smooth(ramp(t, dur - 0.25, dur)))
    return st * env[None, :] / math.sqrt(len(freqs))


def riser(dur, sr, rng, f0=300.0, f1=8000.0, curve=2.0):
    n = int(dur * sr)
    u = lambda tt: np.clip(tt / dur, 0.0, 1.0)
    nz = stft_filter(noise(n, rng), sr, lambda tt: geo(f0, f1, u(tt)), kind="bp", q=1.5)
    t = np.arange(n) / sr
    # Shepard-ish pitch stack rising an octave
    fsw = 110.0 * 2.0 ** (2.0 * (t / dur))
    tone = sum(polyblep_saw(fsw * m, sr, rng.uniform(0, 1)) * w for m, w in ((1, 0.6), (2, 0.4), (4, 0.25)))
    tone = stft_filter(tone, sr, lambda tt: geo(400.0, 6000.0, u(tt)))
    env = (t / dur) ** curve
    return ga.unit_rms(nz) * env, ga.unit_rms(tone) * env


def whoosh(dur, sr, rng, f0=6000.0, f1=300.0):
    n = int(dur * sr)
    t = np.arange(n) / sr
    u = lambda tt: np.clip(tt / dur, 0.0, 1.0)
    x = stft_filter(noise(n, rng), sr, lambda tt: geo(f0, f1, u(tt)), kind="bp", q=1.2)
    env = ramp(t, 0.0, 0.02) * np.exp(-t / (dur * 0.35))
    pan = np.linspace(-0.8, 0.8, n)
    return to_stereo(ga.unit_rms(x) * env, pan)


# --------------------------------------------------------------------------
# Trailer
# --------------------------------------------------------------------------

# Beat times follow keyart's cut (tools/trailer/cut.gd BEATS + cue()/crossed() times).
# Picture is the master: if the cut changes, update CUT below and re-render.
CUT = {
    "visor": 4.6, "title": 7.0, "trust": 7.8, "assemble": 9.5, "wave_hello": 14.7, "reactor": 17.0,
    "cell": 18.0, "power": 18.5, "lights_beat": 20.5, "lights": 20.8, "vault": 23.5, "field": 25.1,
    "lying": 28.0, "snaps": [29.3, 30.0, 30.7, 31.4, 32.1], "gun_beat": 33.5, "gun_pickup": 34.3,
    "shot": 37.2, "betrayal": 38.5, "shove": 40.67, "core_grab": 42.7, "chase": 44.5, "drag": 48.5,
    "console": 52.5, "vent": 55.05, "spaced": 55.5, "countdown": 59.0,
    "cuts": [59.0, 60.1, 61.1, 62.0, 62.8, 63.5, 64.1, 64.6, 65.05, 65.45, 65.8, 66.1, 66.4],
    "launch_sfx": 66.5, "launch": 67.0, "end_card": 72.5, "tagline": 73.9, "platforms": 75.3,
    "black": 79.7, "end": 80.5,
}


def trailer():
    sr = TRAILER_SR
    rng = ga.rng_for("trailer_theme")
    C = CUT
    D = C["end"]
    mx = Mix(D, sr)
    cues = []
    gaps = []  # (start, end): score cut to digital silence

    def cue(t, text):
        cues.append((t, text))

    K = [kick(sr, rng, w) for w in (1.0, 0.95, 1.05)]
    SN = [snare(sr, rng) for _ in range(3)]
    CL = clap(sr, rng)
    HC = [hat(sr, rng) for _ in range(4)]
    HO = hat(sr, rng, True)
    TK = [tick(sr, rng, f) for f in (3200.0, 2900.0)]
    TOMS = [tom(sr, rng, f) for f in (82.0, 110.0, 147.0)]
    TAIKO = taiko(sr, rng)
    HB = heartbeat(sr, rng)
    CR = crash(sr, rng)
    CLUSTER = chord("D3", "Eb3", "A3", "D4", "Eb4")

    def impact(t, size=1.0, notes=None, boom=2.0, crash_g=0.4, whoosh_dur=0.0, peak=3200.0):
        mx.add(TAIKO, t, gain=1.0 * size, rev=0.35)
        mx.add(K[0], t, gain=0.9 * size)
        if boom:
            mx.add(sub_boom(sr, boom), t, gain=0.8 * size)
        if crash_g:
            mx.add(CR, t, gain=crash_g * size, rev=0.4)
        if whoosh_dur:
            mx.add(whoosh(whoosh_dur, sr, rng), t, gain=0.28 * size, rev=0.4)
        if notes:
            mx.add(brass(notes, 2.2, sr, rng, peak=peak), t, gain=0.55 * size, rev=0.45)

    def riser_into(t_end, dur, gain=0.22, roll=True, f1=8000.0):
        nz, tone = riser(dur, sr, rng, 300.0, f1)
        mx.add(nz, t_end - dur, gain=gain, rev=0.2)
        mx.add(widen(to_stereo(tone, 0.0)), t_end - dur, gain=gain * 0.45, rev=0.2)
        rc = crash(sr, rng, min(2.0, dur))[::-1]
        mx.add(rc, t_end - len(rc) / sr, gain=0.3, rev=0.3)
        if roll:
            tr, t0 = t_end - dur * 0.8, t_end - dur * 0.8
            while tr < t_end - 0.03:
                u = (tr - t0) / (t_end - t0)
                mx.add(SN[int(tr * 7) % 3], tr, pan=0.1, gain=0.1 + 0.4 * u ** 2, rev=0.2)
                tr += 0.25 * (1.0 - u) + 0.045 * u

    def suck(t_hit, gap=0.12):
        gaps.append((t_hit - gap, t_hit))

    def stab(t, notes=CLUSTER, gain=0.45, swell=1.0, bell_f=hz("Eb5")):
        if swell:
            rs = pad_chord(notes, swell, sr, rng, fc=1800.0, attack=swell * 0.9, release=0.05, sub=False)
            mx.add(rs * np.linspace(0, 1, rs.shape[1])[None, :] ** 2, t - swell, gain=0.3, rev=0.2)
        mx.add(brass(notes, 1.6, sr, rng, peak=2600.0, res=0.9), t, gain=gain, rev=0.5)
        if bell_f:
            mx.add(bell(bell_f, 2.5, sr, index=2.5, ratio=1.41), t, pan=0.3, gain=0.12, rev=0.6, dly=0.3)

    def bass_note(t, f0, dur, peak=900.0, gain=0.3, res=0.8, square=0.3):
        nn = int(dur * 0.92 * sr)
        tt = np.arange(nn) / sr
        fc = 180.0 + peak * np.exp(-tt / 0.05)
        v = filtered_saw(f0, nn, sr, fc, rng, res=res, square=square) * env_ahr(nn, sr, 0.003, 0.02)
        v += 0.5 * np.sin(TAU * f0 * tt) * env_ahr(nn, sr, 0.003, 0.02)
        mx.add(v, t, gain=gain)

    def pad(t, notes, dur, fc, gain=0.4, attack=0.5, release=0.6, spread=0.22, w=1.3, voices=5, sub=True):
        pc = pad_chord(notes, dur, sr, rng, fc=fc, attack=attack, release=release, spread=spread, voices=voices,
                       sub=sub)
        mx.add(widen(pc, w), t, gain=gain, rev=0.35)

    # ---- 0-7: cold open in the blackout ------------------------------------
    cue(0.0, "Cold open (blackout): low drone, heartbeat quickening")
    n = int(9.5 * sr)
    t = np.arange(n) / sr
    drone = (np.sin(TAU * hz("D1") * t) + 0.7 * np.sin(TAU * hz("D2") * 1.0015 * t)
             + 0.45 * np.sin(TAU * hz("A2") * t + 0.3) + 0.25 * np.sin(TAU * hz("D3") * 0.9985 * t))
    drone *= 1.0 + 0.15 * np.sin(TAU * 0.11 * t)
    air = stft_filter(noise(n, rng), sr, lambda tt: 300.0 + 250.0 * np.sin(TAU * 0.07 * tt) ** 2, kind="bp", q=2.0)
    dark = to_stereo(drone, 0.0) * 0.5 + to_stereo(ga.unit_rms(air), np.sin(TAU * 0.05 * t) * 0.6) * 0.12
    mx.add(dark * env_ahr(n, sr, 2.0, 2.0)[None, :], 0.0, gain=0.5, rev=0.25)
    hb_t, i = 0.8, 0
    while hb_t < C["title"] - 0.3:
        mx.add(HB, hb_t, gain=0.9 * min(1.0, 0.45 + hb_t / 6.0), rev=0.15)
        i += 1
        hb_t += (0.95 - 0.03 * i) if hb_t < C["visor"] else 0.55  # the pulse jumps when the visor wakes
    for tb, f, p in ((1.7, hz("A5"), -0.5), (3.3, hz("F5"), 0.5)):
        mx.add(bell(f, 3.0, sr, index=1.0, ratio=3.5), tb, pan=p, gain=0.08, rev=0.6, dly=0.3)
    cue(C["visor"], "Red visor wakes: low stinger")
    stab(C["visor"], chord("D2", "Eb3", "A3"), gain=0.3, swell=0.6, bell_f=hz("Eb6"))
    mx.add(sub_boom(sr, 1.6, 34.0), C["visor"], gain=0.5)
    riser_into(C["title"], 1.4, gain=0.18, roll=False)

    # ---- 7-9.5: title sting ----------------------------------------------------
    cue(C["title"], "TITLE STING hit (DRIFT STATION)")
    impact(C["title"], 0.9, chord("D2", "A2", "D3", "F3", "A3"), boom=2.2, crash_g=0.3)
    cue(C["trust"], '"TRUST NO ONE": low dissonant brass')
    mx.add(brass(chord("D2", "Eb3", "A3"), 1.6, sr, rng, peak=1400.0, att=0.15, tau=0.8, res=0.6), C["trust"],
           gain=0.35, rev=0.5)
    mx.add(bell(hz("Eb5"), 2.0, sr, index=2.0, ratio=1.41), C["trust"], pan=-0.3, gain=0.08, rev=0.6, dly=0.3)

    # ---- 9.5-17: the crew assembles (warm, hopeful) ---------------------------
    cue(C["assemble"], "Warm hopeful pad + pluck arp (crew assembles): D - Bm - G - A every 1.875 s")
    seg = (C["reactor"] - C["assemble"]) / 4.0
    prog = [chord("D3", "A3", "D4", "F#4", "E5"), chord("B2", "F#3", "D4", "F#4", "A4"),
            chord("G2", "D3", "B3", "D4", "F#4"), chord("A2", "E3", "C#4", "E4", "A4")]
    arp_notes = [["D4", "F#4", "A4", "E5"], ["D4", "F#4", "B4", "D5"], ["D4", "G4", "B4", "D5"], ["C#4", "E4", "A4", "E5"]]
    for k, ch in enumerate(prog):
        t0 = C["assemble"] + seg * k
        pad(t0, ch, seg + (1.6 if k == 3 else 0.8), lambda tt, k=k: 700.0 + 400.0 * k + 500.0 * np.clip(tt / 1.5, 0, 1),
            gain=0.5, attack=1.0 if k == 0 else 0.4, release=0.8)
        root = ("D2", "B1", "G1", "A1")[k]
        nn = int(seg * sr)
        tt = np.arange(nn) / sr
        b = filtered_saw(hz(root), nn, sr, 380.0, rng) * env_ahr(nn, sr, 0.3, 0.3)
        b += 0.6 * np.sin(TAU * hz(root) * tt) * env_ahr(nn, sr, 0.3, 0.3)
        mx.add(b, t0, gain=0.22 if k else 0.14)
        for j in range(16):
            tn = t0 + j * seg / 16.0
            if tn < C["assemble"] + 0.9:
                continue
            f = hz(arp_notes[k][[0, 1, 2, 3, 2, 1, 3, 2][j % 8]]) * (2.0 if j in (7, 15) else 1.0)
            mx.add(pluck(f, 0.5, sr), tn, pan=0.35 * math.sin(j * 0.9), gain=0.09 * (0.8 + 0.2 * (j % 2 == 0)),
                   rev=0.25, dly=0.25)
    mx.add(bell(hz("A5"), 2.0, sr, index=0.8, ratio=2.0), C["wave_hello"], pan=0.4, gain=0.07, rev=0.5, dly=0.3)

    # ---- 17-23.5: reactor, power wave, lights on -----------------------------
    cue(C["reactor"], "Reactor: riser from the cell insert into the power hit")
    riser_into(C["power"] - 0.12, 1.45, gain=0.24)
    suck(C["power"])
    cue(C["power"] - 0.12, "Pre-hit silence (120 ms)")
    cue(C["power"], "POWER HIT: the wave rolls out of the core (impact + L->R whoosh)")
    impact(C["power"], 1.0, chord("D2", "A2", "D3", "A3", "D4"), boom=2.5, crash_g=0.4, whoosh_dur=1.6)
    for j in range(int((C["lights"] - C["power"]) / 0.125)):  # energy pulse rushing through the station
        tn = C["power"] + 0.25 + j * 0.125
        f = hz(("D4", "A4", "D5", "F#5")[j % 4])
        mx.add(pluck(f, 0.3, sr, 1.5), tn, pan=0.5 * math.sin(j), gain=0.04 + 0.04 * j / 16.0, rev=0.3, dly=0.2)
    cue(C["lights"], "Lights come up on the crew: bright D major bloom + sparkle")
    pad(C["lights_beat"], chord("D3", "A3", "D4", "F#4", "A4", "E5"), C["vault"] - C["lights_beat"] + 0.6,
        lambda tt: 1200.0 + 2400.0 * np.clip((tt - 0.3) / 1.2, 0, 1), gain=0.5, attack=0.3, release=0.7, voices=7)
    for i_, f in enumerate((1174.66, 1479.98, 1760.0, 2349.32)):
        mx.add(ga.chime(ga.timeline(1.5, sr), 0.0, f, 0.6, sr, index=0.8), C["lights"] + 0.09 * i_, pan=-0.4 + 0.27 * i_,
               gain=0.06, rev=0.5, dly=0.3)
    mx.add(K[1], C["lights"], gain=0.5)
    mx.add(sub_boom(sr, 1.5, 40.0), C["lights"], gain=0.35)

    # ---- 23.5-28: the vault --------------------------------------------------
    cue(C["vault"], "Vault: mysterious low pad")
    pad(C["vault"], chord("B1", "F#2", "B2", "D3"), 2.0, 600.0, gain=0.35, attack=0.4, release=0.5, sub=False)
    cue(C["field"], "Vault field drops: crystalline Bm9 reveal")
    rs = pad_chord(chord("B3", "D4", "F#4"), 0.8, sr, rng, fc=2500.0, attack=0.75, release=0.03, sub=False)
    mx.add(rs * np.linspace(0, 1, rs.shape[1])[None, :] ** 2, C["field"] - 0.8, gain=0.25, rev=0.3)
    for i_, f in enumerate(chord("B5", "D6", "F#6", "A6", "C#7")):
        mx.add(bell(f, 3.0, sr, index=0.9, ratio=2.0), C["field"] + 0.05 * i_, pan=-0.5 + 0.25 * i_, gain=0.05,
               rev=0.6, dly=0.3)
    pad(C["field"], chord("B2", "F#3", "D4", "A4", "C#5"), C["lying"] - C["field"] - 0.1, 1400.0, gain=0.32,
        attack=0.05, release=0.9)
    mx.add(sub_boom(sr, 2.0, 38.0), C["field"], gain=0.4)
    rs = pad_chord(CLUSTER, 1.0, sr, rng, fc=1500.0, attack=0.95, release=0.03, sub=False)
    mx.add(rs * np.linspace(0, 1, rs.shape[1])[None, :] ** 2.5, C["lying"] - 1.1, gain=0.3, rev=0.2)
    suck(C["lying"], 0.1)

    # ---- 28-33.5: "one of you is lying" ---------------------------------------
    cue(C["lying"], '"ONE OF YOU IS LYING": dissonant stab, then near-silence on the card')
    stab(C["lying"], gain=0.5, swell=0.0)
    mx.add(TAIKO, C["lying"], gain=0.6, rev=0.35)
    mx.add(sub_boom(sr, 2.0, 33.0), C["lying"], gain=0.6)
    snaps = C["snaps"]
    cue(snaps[0], "Snap close-ups: a hit on every cut (%s)" % ", ".join("%.1f" % s for s in snaps))
    dread = pad_chord(chord("D2", "A2", "D3", "Eb3"), C["gun_beat"] - snaps[0] + 0.3, sr, rng, fc=520.0,
                      attack=0.3, release=0.3, spread=0.25, sub=False)
    mx.add(widen(dread, 1.4), snaps[0], gain=0.3, rev=0.3)
    for i_, s in enumerate(snaps):
        last = i_ == len(snaps) - 1
        mx.add(K[i_ % 3], s, gain=0.7 if not last else 0.9)
        mx.add(TK[i_ % 2], s, pan=0.4 * (-1) ** i_, gain=0.25, rev=0.15)
        mx.add(brass([hz("D2") * (2 ** (1 / 12) if i_ % 2 else 1.0)], 0.5, sr, rng, peak=1600.0, tau=0.15), s,
               gain=0.35, rev=0.3)
        if last:
            cue(s, "Lands on purple: big stab")
            stab(s, gain=0.45, swell=0.0, bell_f=hz("A5") * 2 ** (1 / 12))
            mx.add(TAIKO, s, gain=0.7, rev=0.35)
    t_ = snaps[0]
    while t_ < C["gun_beat"] - 0.01:
        bass_note(t_, hz("D2"), 0.35, peak=700.0, gain=0.22)
        t_ += 0.35

    # ---- 33.5-38.5: the gun -------------------------------------------------------
    cue(C["gun_beat"], "The gun: clock pulse locked to the shot (every 0.5 s from 33.7)")
    tick_t = [C["shot"] - 0.5 * k for k in range(8, 0, -1)]
    for k, tk in enumerate(tick_t):
        mx.add(TK[k % 2], tk, pan=0.3 * (-1) ** k, gain=0.15 + 0.03 * k, rev=0.15)
        bass_note(tk, hz("G1"), 0.48, peak=500.0 + 80.0 * k, gain=0.25)
    n = int((C["shot"] - C["gun_pickup"]) * sr)
    sw = pad_chord(chord("G2", "D3", "Ab3", "D4"), n / sr, sr, rng,
                   fc=lambda tt: 400.0 + 2600.0 * np.clip(tt / (n / sr), 0, 1) ** 2, attack=n / sr * 0.9,
                   release=0.02, sub=False)
    mx.add(widen(sw, 1.3), C["gun_pickup"], gain=0.4, rev=0.25)
    nz, _tone = riser(0.9, sr, rng, 800.0, 9000.0, 2.0)
    mx.add(nz, C["shot"] - 0.95, gain=0.16)
    suck(C["shot"], 0.05)
    cue(C["shot"], "GUNSHOT stab")
    impact(C["shot"], 0.8, chord("G2", "D3", "Ab3", "D4"), boom=1.8, crash_g=0.25, peak=2200.0)

    # ---- 38.5-48.5: betrayal and chase -------------------------------------------
    cue(C["betrayal"], "Betrayal: tension pulse (120 BPM grid locked to the shove)")
    beat = 0.5
    t_ = C["shove"] - 4 * beat
    while t_ < C["shove"] - 0.01:
        bass_note(t_, hz("D2"), beat / 2, peak=800.0, gain=0.26)
        bass_note(t_ + beat / 2, hz("D2"), beat / 2, peak=800.0, gain=0.26)
        mx.add(HC[int(t_ * 4) % 4], t_ + beat / 2, pan=0.3, gain=0.08)
        t_ += beat
    pad(C["betrayal"], chord("D3", "F3", "A3"), C["shove"] - C["betrayal"], 500.0, gain=0.25, attack=0.4, release=0.1,
        sub=False)
    cue(C["shove"], "SHOVE: big descending 'betrayal' stab")
    n = int(2.6 * sr)
    tt = np.arange(n) / sr
    bend = 2.0 ** (-2.0 / 12.0 * smooth(ramp(tt, 0.3, 2.2)))
    bet = np.zeros((2, n))
    for i_, f in enumerate(chord("A2", "Bb2", "E3", "A3", "Bb3", "E4")):
        fc = 400.0 + 3000.0 * np.exp(-tt / 0.4)
        for c, p in ((-8.0, -0.6), (8.0, 0.6)):
            ff = f * 2.0 ** (c / 1200.0)
            nh = int(min(0.45 * sr / ff, 3.5 * 3400.0 / ff))
            v = np.zeros(n)
            ph = ga.phase_of(ff * bend, sr, rng.uniform(0, TAU))
            for k in range(1, nh + 1):
                v += (1.0 / k) * lp_resp(k * ff * bend, fc, 0.7) * np.sin(k * ph)
            bet += to_stereo(v, p * (0.3 + 0.1 * i_))
    bet *= (ramp(tt, 0, 0.008) * (1.0 - smooth(ramp(tt, 1.8, 2.6))))[None, :] / math.sqrt(6)
    mx.add(bet, C["shove"], gain=0.6, rev=0.5)
    impact(C["shove"], 0.9, None, boom=2.0, crash_g=0.25)
    t_ = C["shove"] + beat
    while t_ < C["chase"] - 0.01:
        root = hz("D2") if t_ < C["core_grab"] else hz("Bb1")
        for s in range(4):
            bass_note(t_ + s * beat / 4, root * (2.0 if s == 2 else 1.0), beat / 4, peak=1000.0, gain=0.26)
        mx.add(K[int(t_ * 2) % 3], t_, gain=0.6)
        mx.add(HC[int(t_ * 4) % 4], t_ + beat / 2, pan=0.3, gain=0.1)
        t_ += beat
    cue(C["core_grab"], "Green grabs the core: rising stab")
    mx.add(brass(chord("Bb2", "F3", "Bb3", "D4"), 1.0, sr, rng, peak=2400.0, tau=0.3), C["core_grab"], gain=0.35,
           rev=0.4)
    cue(C["chase"], "CHASE: full drums, 16th bass, Dm - Bb (bars of 2.0 s from 44.5)")
    mx.add(CR, C["chase"], gain=0.4, rev=0.4)
    mx.add(TAIKO, C["chase"], gain=0.7, rev=0.3)
    for bar_i, (root, ch) in enumerate((("D2", chord("D3", "A3", "D4", "F4")), ("Bb1", chord("Bb2", "F3", "D4", "F4")))):
        t0 = C["chase"] + 2.0 * bar_i
        pad(t0, ch, 2.05, 1500.0, gain=0.3, attack=0.05, release=0.08, spread=0.3, w=1.4)
        for j in range(16):
            mult = (1.0, 1.0, 2.0, 1.0, 1.0, 2.0, 1.0, 1.5)[j % 8]
            bass_note(t0 + j * beat / 4, hz(root) * mult, beat / 4, peak=1500.0, gain=0.3 * (0.6 if j % 4 == 0 else 1.0))
        for b in range(4):
            tb = t0 + b * beat
            if bar_i == 1 and b == 3:
                break
            mx.add(K[b % 3], tb, gain=0.85)
            if b in (1, 3):
                mx.add(SN[b % 3], tb, pan=0.05, gain=0.5, rev=0.22)
                mx.add(CL, tb, pan=-0.1, gain=0.25, rev=0.3)
            for s in range(4):
                mx.add(HO if s == 2 else HC[s], tb + s * beat / 4, pan=0.35, gain=0.13 if s % 2 else 0.08, rev=0.05)
    for s, tm in enumerate((2, 2, 1, 1, 0, 0)):  # tom fill into the drag
        mx.add(TOMS[tm], C["drag"] - 0.5 + s * beat / 6, pan=(-0.4, 0.0, 0.4)[tm], gain=0.45, rev=0.25)

    # ---- 48.5-59: drag, airlock console, vent, spaced ---------------------------
    cue(C["drag"], "Drag to the airlock: drums drop out; tritone drone + slow heartbeat")
    n = int((C["vent"] - C["drag"]) * sr)
    t = np.arange(n) / sr
    dr = (np.sin(TAU * hz("D1") * t) + 0.5 * np.sin(TAU * hz("Ab1") * t) + 0.3 * np.sin(TAU * hz("D2") * 1.002 * t))
    mx.add(dr * env_ahr(n, sr, 0.4, 0.05), C["drag"], gain=0.4, rev=0.2)
    hb = C["drag"] + 0.2
    while hb < C["console"]:
        mx.add(HB, hb, gain=0.8, rev=0.15)
        hb += 1.0
    pad(C["drag"] + 2.0, chord("D2", "Ab2", "D3"), C["console"] - C["drag"] - 2.0, 700.0, gain=0.3, attack=1.6,
        release=0.1, sub=False)
    cue(C["console"], "Airlock console: warning pulses, accelerating")
    pulses = [C["console"], C["console"] + 0.75, C["console"] + 1.4, C["console"] + 1.9, C["console"] + 2.3]
    for k, tp in enumerate(pulses):
        mx.add(brass(chord("D2", "Eb2", "A2"), 0.45, sr, rng, peak=1200.0 + 200.0 * k, tau=0.2, res=0.8), tp,
               gain=0.4, rev=0.35)
        mx.add(K[2], tp, gain=0.5)
    riser_into(C["vent"] - 0.12, 1.5, gain=0.22)
    suck(C["vent"])
    cue(C["vent"], "VENT HIT: the door blows (impact + outward whoosh)")
    impact(C["vent"], 1.0, chord("D2", "A2", "D3", "F3", "A3"), boom=2.5, crash_g=0.35, whoosh_dur=2.0)
    cue(C["spaced"], "Spaced: vacuum hush, airy pad (fits ghost_drift), faint heartbeat")
    n = int((C["countdown"] - C["spaced"]) * sr)
    t = np.arange(n) / sr
    airy = np.zeros((2, n))
    for i_, f in enumerate(chord("A3", "E4", "B4", "C#5", "E5")):
        airy += to_stereo(np.sin(TAU * f * t + rng.uniform(0, TAU)) * (0.6 + 0.4 * np.sin(TAU * 0.3 * (i_ + 1) * t)),
                          -0.6 + 0.3 * i_)
    breath = stft_filter(noise(n, rng), sr, lambda tt: np.full(len(tt), 2500.0), kind="bp", q=0.8)
    airy += to_stereo(ga.unit_rms(breath) * 0.4, 0.0)
    mx.add(airy * env_ahr(n, sr, 1.0, 0.6)[None, :], C["spaced"], gain=0.05, rev=0.6)
    mx.add(HB, C["spaced"] + 1.5, gain=0.35, rev=0.3)
    mx.add(HB, C["spaced"] + 2.7, gain=0.4, rev=0.3)
    riser_into(C["countdown"], 1.0, gain=0.2, roll=False)

    # ---- 59-66.4: cross-cut countdowns, accelerating ------------------------------
    cuts = C["cuts"]
    cue(C["countdown"], "COUNTDOWN cross-cut: a hit on every cut, tempo accelerating with the cutting")
    cue(cuts[1], "Cuts at " + ", ".join("%.2f" % c for c in cuts[1:-1]) + " (pod = alarm call, shuttle = bright call)")
    for i_ in range(len(cuts) - 1):
        a, b = cuts[i_], cuts[i_ + 1]
        pod = i_ % 2 == 0
        span = b - a
        beats = 4 if span >= 0.7 else 2
        bt = span / beats
        mx.add(TOMS[2 if pod else 1], a, pan=-0.3 if pod else 0.3, gain=0.45, rev=0.25)
        mx.add(CR, a, gain=0.12 + 0.1 * i_ / 12.0, rev=0.3)
        root = hz("D2") if pod else hz("A1")
        for q in range(beats):
            tb = a + q * bt
            mx.add(K[q % 3], tb, gain=0.8)
            if q % 2 == 1:
                mx.add(SN[q % 3], tb, gain=0.45, rev=0.2)
            for s in range(2):
                bass_note(tb + s * bt / 2, root * (2.0 if s else 1.0), bt / 2, peak=1500.0, gain=0.28)
                mx.add(HC[(q + s) % 4], tb + s * bt / 2, pan=0.35, gain=0.1)
        nn = int(min(span, 0.9) * 0.9 * sr)
        tt = np.arange(nn) / sr
        if pod:   # the pod klaxon call (tritone)
            notes = ((0.0, "D5"), (0.5, "G#4"))
        else:     # the shuttle's bright rising fifth
            notes = ((0.0, "A5"), (0.5, "E6"))
        for frac, nm in notes:
            ln = int(nn * 0.5)
            ttt = tt[:ln]
            f = hz(nm) * (1.0 - 0.03 * np.exp(-ttt / 0.03))
            ph = ga.phase_of(f, sr)
            lead = sum((1.0 / k) * np.sin(k * ph) for k in ((1, 3, 5, 7) if pod else (1, 2, 3)))
            lead = ga.svf(lead * env_ahr(ln, sr, 0.01, 0.04), 2600.0, 1.0, "lp", sr)
            mx.add(lead, a + frac * min(span, 0.9) * 0.9, pan=-0.2 if pod else 0.2, gain=0.1, rev=0.3, dly=0.15)
        pad(a, chord("D3", "F3", "A3", "D4") if pod else chord("A2", "E3", "A3", "C#4"), span + 0.05, 1800.0,
            gain=0.22, attack=0.02, release=0.04, spread=0.3, w=1.4, sub=False)
    nz, tone = riser(cuts[-1] - cuts[3], sr, rng, 400.0, 10000.0, 2.2)
    mx.add(nz, cuts[3], gain=0.24, rev=0.15)
    mx.add(widen(to_stereo(tone, 0.0)), cuts[3], gain=0.12, rev=0.15)
    t_ = cuts[-2]
    while t_ < cuts[-1] - 0.01:  # last-cut snare roll
        mx.add(SN[int(t_ * 50) % 3], t_, gain=0.4, rev=0.15)
        t_ += 0.04
    reentry = 68.2
    cue(cuts[-1], "HARD STOP on the last cut: score silent; launch SFX (66.5) and win sting (67.0) play alone")
    gaps.append((cuts[-1], reentry))

    # ---- 68.2-72.5: the shuttle climbs; build to the end card ---------------------
    cue(reentry, "Score re-enters under the climb: D major swell (sits under win_crew), then G -> A build")
    pad(reentry, chord("D3", "A3", "D4", "F#4", "A4"), 70.4 - reentry + 0.3, lambda tt: 700.0 + 900.0 * np.clip(tt / 2, 0, 1),
        gain=0.35, attack=1.5, release=0.3, voices=7)
    pad(70.4, chord("B2", "D3", "G3", "B3", "D4"), 0.95, 1800.0, gain=0.4, attack=0.2, release=0.1, voices=7)
    pad(71.3, chord("A2", "E3", "A3", "D4"), 0.5, 2200.0, gain=0.42, attack=0.05, release=0.05, voices=7, sub=False)
    pad(71.75, chord("A2", "E3", "A3", "C#4", "E4"), C["end_card"] - 71.75, 2600.0, gain=0.45, attack=0.05,
        release=0.02, voices=7)
    for j in range(24):  # timpani-ish roll
        mx.add(TOMS[0], 71.0 + j * (C["end_card"] - 0.15 - 71.0) / 24.0, gain=0.05 + 0.3 * (j / 23.0) ** 2, rev=0.3)
    riser_into(C["end_card"] - 0.12, 1.6, gain=0.2, roll=False)
    suck(C["end_card"])

    # ---- 72.5-80.5: end card -------------------------------------------------------
    cue(C["end_card"], "END CARD hit: heroic D major title swell (G - A - D resolution lands here)")
    impact(C["end_card"], 0.9, chord("D2", "A2", "D3", "F#3", "A3", "D4"), boom=2.2, crash_g=0.35, peak=2600.0)
    dur = C["end"] - C["end_card"]
    pad(C["end_card"], chord("D3", "A3", "D4", "F#4", "A4", "E5"), dur,
        lambda tt: 1500.0 + 2500.0 * np.clip(tt / 3.0, 0, 1), gain=0.5, attack=0.15, release=1.0, voices=7, w=1.5)
    mx.add(brass(chord("D3", "A3", "D4", "F#4"), dur - 0.5, sr, rng, peak=2200.0, att=0.6, tau=4.0, res=0.4),
           C["end_card"], gain=0.3, rev=0.5)
    for tc, f in ((C["tagline"], hz("F#5")), (C["platforms"], hz("A5"))):
        mx.add(ga.chime(ga.timeline(2.0, sr), 0.0, f, 0.7, sr, index=0.7), tc, pan=0.2, gain=0.08, rev=0.5, dly=0.3)
    cue(C["tagline"], "Tagline chime")
    cue(C["platforms"], "'2-8 FRIENDS - ANDROID' chime")
    boom_t = 79.0
    cue(boom_t, "SUB-BOOM (final hit); fades out with the picture 79.7 -> 80.5")
    mx.add(sub_boom(sr, 1.5, 30.0), boom_t, gain=1.0)
    mx.add(TAIKO, boom_t, gain=0.7, rev=0.5)
    mx.add(CR, boom_t, gain=0.25, rev=0.5)
    cue(C["end"], "End")

    # ---- buses, gaps, arc, master -------------------------------------------------
    rev = freeverb(spectral_st(mx.rev, sr, ga.hp_mag(180.0, 2)), sr, room=0.86, damp=0.45, width=1.0)
    dly = pingpong(mx.dly, sr, 0.375, 0.38, 5, 3500.0)
    mixed = mx.dry + 0.9 * rev + 0.5 * dly
    tt = np.arange(mx.n) / sr
    g = np.ones(mx.n)
    for a, b in gaps:
        g = np.minimum(g, np.maximum(1.0 - ramp(tt, a, a + 0.004), ramp(tt, b - 0.004, b)))
    g *= 1.0 - smooth(ramp(tt, C["black"], C["end"])) * 0.98
    g[-int(0.01 * sr):] *= np.linspace(1.0, 0.0, int(0.01 * sr))
    arc_t = [0.0, 4.5, 6.9, 7.0, 9.5, 17.0, 18.3, 18.5, 23.5, 28.0, 33.5, 38.5, 44.5, 48.5, 52.5, 55.0, 55.05, 55.6,
             59.0, 66.4, 68.2, 72.4, 72.5, 80.5]
    arc_db = [-11.0, -9.0, -6.0, -1.5, -6.0, -6.5, -2.5, 0.0, -4.5, -4.0, -3.0, -2.0, -1.0, -5.0, -3.5, -2.5, 0.0, -6.0,
              -0.5, 1.0, -5.0, -1.0, 0.5, 0.5]
    g *= 10.0 ** (np.interp(tt, arc_t, arc_db) / 20.0)
    st = master(mixed, sr, -14.0, gate=lambda v: v * g[None, :])
    return st, sr, cues



# --------------------------------------------------------------------------
# In-game loops
# --------------------------------------------------------------------------

def lobby_theme():
    """Chill, curious: F-lydian-ish FM e-piano, soft sub, lazy drums, a questioning marimba motif."""
    sr = LOOP_SR
    rng = ga.rng_for("lobby_theme")
    bpm, bars = 90.0, 12
    beat = 60.0 / bpm
    bar = 4 * beat
    mx = Mix(bars * bar, sr, loop=True)
    chords_ = [chord("F3", "A3", "C4", "E4"), chord("E3", "G3", "B3", "D4"),
               chord("D3", "F3", "A3", "C4", "E4"), chord("C3", "E3", "G3", "B3", "F#4")]
    roots = ["F1", "E1", "D1", "C2"]
    K_ = kick(sr, rng, 1.05)
    SH = [hat(sr, rng) for _ in range(3)]
    TK_ = tick(sr, rng, 2100.0)
    for b in range(bars):
        t0 = b * bar
        ch = chords_[b % 4]
        for hit, d in ((0.0, 1.4), (1.5 * beat, 2.6)):
            for i, f in enumerate(ch):
                mx.add(epiano(f, d * beat, sr), t0 + hit + 0.012 * i, pan=-0.3 + 0.15 * i, gain=0.11, rev=0.35)
        n = int(3.6 * beat * sr)
        tt = np.arange(n) / sr
        bass = (np.sin(TAU * hz(roots[b % 4]) * 2 * tt) + 0.25 * np.sin(TAU * hz(roots[b % 4]) * 4 * tt))
        mx.add(bass * env_ahr(n, sr, 0.02, 0.3), t0, gain=0.22)
        pc = pad_chord(ch, bar + 0.3, sr, rng, fc=1100.0, attack=1.0, release=0.8, spread=0.18, sub=False)
        mx.add(widen(pc, 1.5), t0, gain=0.08, rev=0.4)
        if b % 4 != 3 or b == bars - 1:
            mx.add(K_, t0, gain=0.35)
            mx.add(K_, t0 + 2.5 * beat, gain=0.25)
        mx.add(TK_, t0 + beat, pan=0.2, gain=0.15, rev=0.2)
        mx.add(TK_, t0 + 3 * beat, pan=0.2, gain=0.15, rev=0.2)
        for e in range(8):
            swing = 0.06 * beat if e % 2 else 0.0
            mx.add(SH[e % 3], t0 + e * beat / 2 + swing, pan=-0.35, gain=0.05 if e % 2 else 0.035)
    motifs = [["C5", "E5", "F#5", "A5", "G5", "F#5", "E5", None], ["B4", "D5", "E5", "G5", "F#5", "D5", "E5", None],
              ["A4", "C5", "E5", "F#5", "E5", "C5", "B4", None]]
    for k, start_bar in enumerate((0, 4, 8)):
        notes = motifs[k]
        for j, nm in enumerate(notes):
            if nm is None:
                continue
            tn = (start_bar + 1) * bar + j * beat / 2 + (beat / 4 if j == 3 else 0.0)
            mx.add(fm_tone(hz(nm), int(1.2 * sr), sr, 4.0, 1.2, 0.35), tn, pan=0.25, gain=0.07, rev=0.3, dly=0.45)
    rev = steady(lambda v: freeverb(v, sr, room=0.78, damp=0.5), spectral_st(mx.rev, sr, ga.hp_mag(200.0, 2)), True)
    dly = pingpong(mx.dly, sr, beat * 0.75, 0.4, 5, 3000.0, loop=True)
    return master(mx.dry + 0.8 * rev + 0.5 * dly, sr, -23.0, loop=True, voice_dip=True), sr


def round_tension():
    """Subtle and sparse: dark breathing drone, soft pulse, clock ticks, glassy tritone notes."""
    sr = LOOP_SR
    rng = ga.rng_for("round_tension")
    bpm, bars = 75.0, 10
    beat = 60.0 / bpm
    bar = 4 * beat
    L = bars * bar
    mx = Mix(L, sr, loop=True)
    n = mx.n
    t = np.arange(n) / sr
    drone = np.zeros((2, n))
    for f in (hz("D2"), hz("A2"), hz("D3")):
        drone += supersaw(f, n, sr, rng, voices=5, spread=0.12, width=0.8, period=L)
    # filter breathes twice per loop (exactly periodic); steady() makes the STFT circular
    breathe = lambda tt: 260.0 + 180.0 * np.sin(TAU * 2.0 * tt / L) ** 2
    drone = steady(lambda v: np.vstack([stft_filter(c, sr, breathe) for c in v]), drone, True)
    drone += 0.6 * np.sin(TAU * round(hz("D1") * L) / L * t)[None, :]
    mx.add(drone, 0.0, gain=0.18, rev=0.25)
    P = tom(sr, rng, 62.0)
    TK_ = tick(sr, rng, 2600.0)
    for b in range(bars):
        t0 = b * bar
        mx.add(P, t0, gain=0.3, rev=0.2)
        if b % 2 == 1:
            mx.add(P, t0 + 2.5 * beat, gain=0.18, rev=0.2)
        for q in range(4 if b < 5 else 8):
            mx.add(TK_, t0 + q * (beat if b < 5 else beat / 2), pan=0.4 * (-1) ** q, gain=0.05, rev=0.15)
    glass = ["Eb5", "A5", "G#5", "D6", "Bb5", "E5", "A5", "Eb6", "D5", "G#5"]
    for b in range(bars):
        tn = b * bar + rng.choice([0.5, 1.0, 1.5, 2.5]) * beat
        mx.add(bell(hz(glass[b]), 4.0, sr, index=1.0, ratio=3.5), tn, pan=rng.uniform(-0.6, 0.6), gain=0.05,
               rev=0.5, dly=0.4)
    for b0 in (4, 8):
        sw = pad_chord(chord("D3", "Eb3", "A3"), 3.0, sr, rng, fc=900.0, attack=2.6, release=0.15, sub=False)
        mx.add(sw, b0 * bar - 3.0, gain=0.12, rev=0.3)
    rev = steady(lambda v: freeverb(v, sr, room=0.9, damp=0.55), spectral_st(mx.rev, sr, ga.hp_mag(150.0, 2)), True)
    dly = pingpong(mx.dly, sr, beat * 1.5, 0.45, 5, 2500.0, loop=True)
    return master(mx.dry + 0.9 * rev + 0.5 * dly, sr, -27.0, loop=True, voice_dip=True), sr


def extraction_drive():
    """Urgent: four-on-the-floor, 16th bass ostinato, pluck arps, the alarm call in the back half."""
    sr = LOOP_SR
    rng = ga.rng_for("extraction_drive")
    bpm, bars = 128.0, 16
    beat = 60.0 / bpm
    bar = 4 * beat
    L = bars * bar
    mx = Mix(L, sr, loop=True)
    K_ = [kick(sr, rng, 1.0), kick(sr, rng, 1.04)]
    SN_ = snare(sr, rng)
    CL_ = clap(sr, rng)
    HC_ = [hat(sr, rng) for _ in range(4)]
    HO_ = hat(sr, rng, True)
    prog = [("D2", ["D4", "F4", "A4", "D5"]), ("Bb1", ["D4", "F4", "Bb4", "D5"]), ("C2", ["C4", "E4", "G4", "C5"]),
            ("A1", ["C#4", "E4", "A4", "E5"])]
    for b in range(bars):
        t0 = b * bar
        root, arp = prog[b % 4]
        f0 = hz(root)
        pc = pad_chord([hz(nm) * 0.5 for nm in arp[:3]], bar + 0.1, sr, rng, fc=1400.0 + 100.0 * (b % 4),
                       attack=0.08, release=0.1, spread=0.3, sub=False)
        mx.add(widen(pc, 1.6), t0, gain=0.07, rev=0.2)  # wide bed for stereo width
        for j in range(16):
            tn = t0 + j * beat / 4
            nn = int(beat / 4 * 0.9 * sr)
            tt = np.arange(nn) / sr
            fc = 200.0 + (900.0 + 60.0 * (b % 8)) * np.exp(-tt / 0.035)
            mult = (1.0, 1.0, 2.0, 1.0)[j % 4]
            v = filtered_saw(f0 * mult, nn, sr, fc, rng, res=0.7, square=0.3) * env_ahr(nn, sr, 0.002, 0.012)
            v += 0.5 * np.sin(TAU * f0 * tt) * env_ahr(nn, sr, 0.002, 0.012)
            mx.add(v, tn, gain=0.22 * (0.55 if j % 4 == 0 else 1.0))
            if b >= 4:
                f = hz(arp[(0, 1, 2, 3, 2, 1, 3, 2)[j % 8]]) * (2.0 if j % 8 == 7 else 1.0)
                mx.add(pluck(f, 0.25, sr, 1.8), tn, pan=0.4 * math.sin(j), gain=0.05, rev=0.2, dly=0.25)
        for q in range(4):
            tb = t0 + q * beat
            mx.add(K_[q % 2], tb, gain=0.5)
            if q in (1, 3):
                mx.add(SN_, tb, gain=0.25, rev=0.2)
                mx.add(CL_, tb, pan=-0.1, gain=0.12, rev=0.25)
            for s in range(4):
                h = HO_ if (s == 2 and b >= 8) else HC_[s]
                mx.add(h, tb + s * beat / 4, pan=0.35, gain=0.07 if s % 2 else 0.045)
        if b >= 8:
            for half, note in ((0.0, "D5"), (2 * beat, "G#4")):
                nn = int(1.8 * beat * sr)
                tt = np.arange(nn) / sr
                ph = ga.phase_of(hz(note) * (1.0 - 0.03 * np.exp(-tt / 0.04)), sr)
                lead = sum((1.0 / k) * np.sin(k * ph) for k in (1, 3, 5, 7)) * env_ahr(nn, sr, 0.02, 0.1)
                mx.add(ga.svf(lead, 2200.0, 0.9, "lp", sr), t0 + half, gain=0.045, rev=0.3, dly=0.2)
    nz, tone = riser(2 * bar, sr, rng, 500.0, 8000.0, 2.0)
    mx.add(nz, L - 2 * bar, gain=0.1, rev=0.2)  # rises into the loop point ...
    mx.add(crash(sr, rng, 2.0), 0.0, gain=0.12, rev=0.3)  # ... and lands on the downbeat
    rev = steady(lambda v: freeverb(v, sr, room=0.7, damp=0.5), spectral_st(mx.rev, sr, ga.hp_mag(250.0, 2)), True)
    dly = pingpong(mx.dly, sr, beat * 0.75, 0.35, 4, 3500.0, loop=True)
    return master(mx.dry + 0.7 * rev + 0.4 * dly, sr, -21.0, loop=True, voice_dip=True), sr


# --------------------------------------------------------------------------

def report(name, st, sr, loop):
    pk = db(float(np.max(np.abs(st))))
    corr = float(np.corrcoef(st[0], st[1])[0, 1])
    seam = ""
    if loop:
        jump = float(np.max(np.abs(st[:, 0] - st[:, -1])))
        step = float(np.percentile(np.abs(np.diff(st, axis=1)), 99))
        seam = f"  loop seam {jump / (step + 1e-12):.2f}x"
    path = OUT / f"{name}.wav"
    print(f"{name + '.wav':<24}{st.shape[1] / sr:6.1f}s {path.stat().st_size / 1048576:5.2f} MB  "
          f"{lufs(st, sr):6.1f} LUFS  peak {pk:5.1f} dBFS  L/R corr {corr:4.2f}{seam}")


def main(argv) -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    which = argv[1] if len(argv) > 1 else "all"
    if which in ("all", "trailer"):
        st, sr, cues = trailer()
        write_stereo(OUT / "trailer_theme.wav", st, sr, loop=False)
        report("trailer_theme", st, sr, False)
        for a, b, label in ((0, 7, "cold open"), (7, 9.5, "title"), (9.5, 17, "assemble"), (18.5, 23.5, "power"),
                            (23.5, 28, "vault"), (28, 38.5, "lying+gun"), (38.5, 48.5, "betrayal"),
                            (48.5, 55, "airlock"), (55.05, 59, "vent+space"), (59, 66.4, "countdown"),
                            (68.2, 72.5, "launch"), (72.5, 80.5, "end card")):
            print(f"    {label:<10} {a:5.1f}-{b:5.1f}s  {short_term(st, sr, a, b):6.1f} LUFS")
        lines = ["Drift Station - trailer_theme.wav cue sheet (generated by tools/generate_music.py)",
                 "80.5 s, 44.1 kHz stereo, mastered ~-14 LUFS. Timed to keyart's cut (tools/trailer/cut.gd BEATS",
                 "and cue()/crossed() times); the picture is the master. Hits land on these frames:", ""]
        lines += [f"{int(t // 60):02d}:{t % 60:05.2f}  ({t:5.2f} s)  {text}" for t, text in sorted(cues)]
        (OUT / "trailer_cues.txt").write_text("\n".join(lines) + "\n")
    if which in ("all", "loops"):
        for name, fn in (("lobby_theme", lobby_theme), ("round_tension", round_tension),
                         ("extraction_drive", extraction_drive)):
            st, sr = fn()
            write_stereo(OUT / f"{name}.wav", st, sr, loop=True)
            report(name, st, sr, True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
