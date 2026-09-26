#!/usr/bin/env python3
"""Generates the placeholder sound effects and music for Willow VS The World.

Everything is synthesized from scratch out of square, triangle, saw, sine and
noise waves (roughly what an old game console had), so there are no samples to
license and every sound can be tweaked right here.

  game/assets/sounds/<name>.wav   sound effects (16-bit mono)
  game/assets/music/<name>.ogg    looping music (seamless loops)

These are *placeholders*. To use a real sound, drop a .wav or .ogg with the
same name into the same folder and delete its entry here. The game looks each
sound up by name (see game/scripts/autoload/audio.gd).

Usage:
    pip install numpy soundfile
    python3 tools/make_sounds.py               # everything
    python3 tools/make_sounds.py laser war     # just these sounds / songs
    python3 tools/make_sounds.py --list        # every name, with its length
"""
from __future__ import annotations

import argparse
import sys
import zlib
from pathlib import Path
from typing import Callable

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
SOUND_DIR = ROOT / "game" / "assets" / "sounds"
MUSIC_DIR = ROOT / "game" / "assets" / "music"

SR = 22050        # sound effects
MUSIC_SR = 32000  # music

rng = np.random.default_rng(0)  # re-seeded for every sound, so output is repeatable


# ==================================================================== notes

_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(note: str | int) -> int:
    """'C4' -> 60, 'F#3', 'Bb5'..."""
    if isinstance(note, (int, np.integer)):
        return int(note)
    semis = _NOTE[note[0].upper()]
    rest = note[1:]
    while rest and rest[0] in "#b":
        semis += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + semis


def hz(note: str | float) -> float:
    if isinstance(note, str):
        return 440.0 * 2 ** ((midi(note) - 69) / 12)
    return float(note)


def mhz(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


# ============================================================= building blocks

def n_of(dur: float, sr: int = SR) -> int:
    return max(1, int(round(dur * sr)))


def times(n: int, sr: int = SR) -> np.ndarray:
    return np.arange(n) / sr


def curve(points, dur: float, sr: int = SR) -> np.ndarray:
    """A piecewise-linear curve through (seconds, value) points."""
    ts, vs = zip(*points)
    return np.interp(times(n_of(dur, sr), sr), ts, vs)


def expcurve(points, dur: float, sr: int = SR) -> np.ndarray:
    """Like curve(), but glides evenly in pitch (log space)."""
    return np.exp(curve([(t, np.log(hz(v))) for t, v in points], dur, sr))


def glide(f0, f1, dur: float, sr: int = SR) -> np.ndarray:
    return expcurve([(0, f0), (dur, f1)], dur, sr)


def _blep(ph: np.ndarray, dt: np.ndarray) -> np.ndarray:
    """PolyBLEP correction: takes the harsh aliasing off square and saw waves."""
    out = np.zeros_like(ph)
    m = ph < dt
    t = ph[m] / dt[m]
    out[m] = t + t - t * t - 1.0
    m = ph > 1.0 - dt
    t = (ph[m] - 1.0) / dt[m]
    out[m] = t * t + t + t + 1.0
    return out


def osc(kind: str, freq, dur: float | None = None, duty: float = 0.5, sr: int = SR) -> np.ndarray:
    """One oscillator. `freq` is a note, a number, or a per-sample array."""
    if isinstance(freq, np.ndarray):
        f = freq
    else:
        f = np.full(n_of(dur, sr), hz(freq))
    dt = np.clip(f / sr, 1e-7, 0.5)
    ph = np.cumsum(dt) % 1.0
    if kind == "sine":
        return np.sin(2 * np.pi * ph)
    if kind == "tri":
        return 4.0 * np.abs(ph - 0.5) - 1.0
    if kind == "saw":
        return 2.0 * ph - 1.0 - _blep(ph, dt)
    if kind == "square":
        sq = np.where(ph < duty, 1.0, -1.0) + _blep(ph, dt) - _blep((ph - duty) % 1.0, dt)
        return sq - (2.0 * duty - 1.0)
    raise ValueError(kind)


def vibrato(f: np.ndarray, depth: float, rate: float, delay: float = 0.0, sr: int = SR) -> np.ndarray:
    """Wobbles a pitch curve by `depth` semitones, fading in after `delay` seconds."""
    t = times(len(f), sr)
    fade = np.clip((t - delay) / 0.08, 0.0, 1.0) if delay > 0 else 1.0
    return f * 2 ** (depth / 12 * np.sin(2 * np.pi * rate * t) * fade)


def noise(dur: float, rate=None, sr: int = SR) -> np.ndarray:
    """White noise, or "crunchy" sample-and-hold noise changing `rate` times a second."""
    n = n_of(dur, sr)
    if rate is None:
        return rng.uniform(-1.0, 1.0, n)
    r = np.broadcast_to(np.asarray(rate, float), (n,))
    idx = np.floor(np.cumsum(r / sr)).astype(int)
    return rng.uniform(-1.0, 1.0, idx[-1] + 1)[idx]


def lowpass(x: np.ndarray, cutoff, sr: int = SR) -> np.ndarray:
    """One-pole low-pass. `cutoff` can be a number or a per-sample curve."""
    c = np.broadcast_to(np.asarray(cutoff, float), x.shape)
    a = (1.0 - np.exp(-2 * np.pi * np.minimum(c, sr * 0.45) / sr)).tolist()
    out = [0.0] * len(x)
    acc = 0.0
    for i, v in enumerate(x.tolist()):
        acc += a[i] * (v - acc)
        out[i] = acc
    return np.array(out)


def highpass(x: np.ndarray, cutoff, sr: int = SR) -> np.ndarray:
    return x - lowpass(x, cutoff, sr)


def svf(x: np.ndarray, cutoff, q: float = 0.5, mode: str = "lp", sr: int = SR) -> np.ndarray:
    """Resonant state-variable filter (smaller q = more resonance). Good for vowels and wahs."""
    c = np.broadcast_to(np.asarray(cutoff, float), x.shape)
    f = (2 * np.sin(np.pi * np.minimum(c, sr / 6.5) / sr)).tolist()
    low = band = 0.0
    out = [0.0] * len(x)
    for i, v in enumerate(x.tolist()):
        low += f[i] * band
        high = v - low - q * band
        band += f[i] * high
        out[i] = low if mode == "lp" else band if mode == "bp" else high
    return np.array(out)


def decay(dur: float, tau: float, attack: float = 0.002, sr: int = SR) -> np.ndarray:
    t = times(n_of(dur, sr), sr)
    e = np.exp(-t / tau)
    if attack > 0:
        e *= np.minimum(1.0, t / attack)
    return e


def env(points, dur: float, sr: int = SR) -> np.ndarray:
    return curve(points, dur, sr)


def adsr(dur: float, a: float, d: float, s: float, r: float, sr: int = SR) -> np.ndarray:
    """Attack, decay (time constant) toward the sustain level, then a linear release."""
    n = n_of(dur + r, sr)
    t = times(n, sr)
    e = np.minimum(1.0, t / a) if a > 0 else np.ones(n)
    e = e * (s + (1.0 - s) * np.exp(-np.maximum(t - a, 0.0) / max(d, 1e-4)))
    off = min(n_of(dur, sr), n - 1)
    e[off:] = e[off] * np.clip(1.0 - (t[off:] - dur) / max(r, 1e-4), 0.0, 1.0)
    return e


def place(parts, sr: int = SR) -> np.ndarray:
    """Mixes [(start_seconds, signal), ...] into one buffer."""
    end = max(int(round(s * sr)) + len(x) for s, x in parts)
    out = np.zeros(end)
    for s, x in parts:
        i = int(round(s * sr))
        out[i:i + len(x)] += x
    return out


def mix(*xs: np.ndarray) -> np.ndarray:
    return place([(0.0, x) for x in xs])


# ============================================================ little recipes

def blip(note, dur: float, duty: float = 0.5, tau: float | None = None, kind: str = "square") -> np.ndarray:
    return osc(kind, note, dur, duty) * decay(dur, tau or dur * 0.5)


def bell(note, dur: float = 0.5, bright: float = 1.0) -> np.ndarray:
    f = hz(note)
    return (osc("sine", f, dur) * decay(dur, dur * 0.4)
            + 0.3 * bright * osc("sine", f * 2.0, dur) * decay(dur, dur * 0.15)
            + 0.12 * bright * osc("sine", f * 3.01, dur) * decay(dur, dur * 0.07))


def woodblock(note, dur: float = 0.08) -> np.ndarray:
    f = hz(note)
    return (osc("sine", f, dur) * decay(dur, 0.022)
            + 0.35 * osc("sine", f * 2.7, dur) * decay(dur, 0.008)
            + 0.25 * highpass(noise(dur), 2500) * decay(dur, 0.003))


def whoosh(dur: float, lo: float = 500, hi: float = 2400, q: float = 0.7) -> np.ndarray:
    cut = curve([(0, lo), (dur * 0.45, hi), (dur, lo)], dur)
    return svf(noise(dur), cut, q, "bp") * env([(0, 0), (dur * 0.45, 1), (dur, 0)], dur)


def thump(dur: float = 0.3, f0: float = 150, f1: float = 40, tau: float = 0.09) -> np.ndarray:
    return osc("sine", glide(f0, f1, dur), sr=SR) * decay(dur, tau)


def burst(dur: float, cutoff: float, tau: float) -> np.ndarray:
    return lowpass(noise(dur), cutoff) * decay(dur, tau)


def chirp(f0: float, f1: float, dur: float) -> np.ndarray:
    return osc("sine", glide(f0, f1, dur)) * env([(0, 0), (dur * 0.2, 1), (dur, 0)], dur)


def arpeggio(notes, step: float, tail: float = 0.2, duty: float = 0.25, tau: float = 0.12) -> np.ndarray:
    return place([(k * step, blip(n, step + tail, duty, tau)) for k, n in enumerate(notes)])


# ================================================================== voices

def meow(f0: float = 680, dur: float = 0.42, sad: bool = False) -> np.ndarray:
    """'Mi-a-ow': a buzzy source through a resonant filter that opens and closes like a mouth."""
    if sad:
        f = expcurve([(0, f0), (0.15, f0 * 1.06), (dur, f0 * 0.55)], dur)
        cut = curve([(0, 500), (0.12, 2000), (dur * 0.6, 1400), (dur, 500)], dur)
    else:
        f = expcurve([(0, f0 * 0.8), (0.12, f0 * 1.1), (0.28, f0 * 1.15), (dur, f0 * 0.78)], dur)
        cut = curve([(0, 500), (0.1, 2300), (0.26, 2000), (dur, 700)], dur)
    f = vibrato(f, 0.25, 6.0, 0.1)
    src = 0.8 * osc("saw", f) + 0.2 * osc("square", f, duty=0.3)
    x = svf(src, cut, 0.3, "lp")
    e = env([(0, 0), (0.05, 0.7), (0.14, 1), (dur * 0.7, 0.8), (dur, 0)], dur)
    if sad:
        e = e * (0.75 + 0.25 * np.sin(2 * np.pi * 28 * times(len(e))))  # a little growl
    return x * e


def woof(f0: float = 260, dur: float = 0.16, bright: float = 1500) -> np.ndarray:
    f = expcurve([(0, f0 * 1.15), (0.04, f0), (dur, f0 * 0.75)], dur)
    src = osc("saw", f) + 0.35 * noise(dur)
    x = svf(src, curve([(0, 600), (0.03, bright), (dur, 450)], dur), 0.45, "lp")
    return x * env([(0, 0), (0.01, 1), (0.06, 0.8), (dur, 0)], dur)


def robot_babble(freqs, step: float = 0.07) -> np.ndarray:
    parts = []
    for k in range(len(freqs) - 1):
        parts.append((k * step, osc("square", glide(freqs[k], freqs[k + 1], step * 0.9), duty=0.25)
                      * env([(0, 0), (0.005, 1), (step * 0.7, 0.8), (step * 0.9, 0)], step * 0.9)))
    return place(parts)


def wub(dur: float = 0.4) -> np.ndarray:
    t = times(n_of(dur))
    cut = 250 + 700 * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t - np.pi / 2))
    return lowpass(osc("saw", 55.0, dur) + 0.5 * osc("square", 110.0, dur), cut) * env([(0, 0), (0.02, 1), (dur, 0)], dur)


# ================================================================ registry

SOUNDS: dict[str, tuple[Callable[[], np.ndarray], float]] = {}


def sound(name: str, level: float = 1.0):
    """Registers a sound effect. `level` is its loudness relative to the others."""
    def deco(fn):
        SOUNDS[name] = (fn, level)
        return fn
    return deco


# ------------------------------------------------------------------ weapons

@sound("laser", 0.75)
def _():
    d = 0.14
    f = glide(1900, 320, d)
    return osc("square", f, duty=0.25) * decay(d, 0.06) + 0.4 * osc("square", f * 1.01) * decay(d, 0.04)


@sound("ball", 0.5)
def _():
    d = 0.07
    return osc("sine", glide(640, 330, d)) * decay(d, 0.02) + 0.6 * burst(d, 2600, 0.006)


@sound("bazooka", 1.0)
def _():
    d = 0.4
    hiss = lowpass(noise(d), curve([(0, 5000), (d, 500)], d)) * decay(d, 0.12)
    pop = osc("square", glide(520, 150, 0.06)) * decay(0.06, 0.015)
    return mix(thump(d, 230, 48, 0.1), 0.8 * hiss, 0.4 * pop)


@sound("egg_drop", 0.6)
def _():
    d = 0.16
    return mix(osc("sine", glide(1500, 520, d)) * env([(0, 0), (0.01, 1), (d, 0)], d), 0.3 * blip("C6", 0.04, 0.5))


@sound("toaster", 0.85)
def _():
    d = 0.3
    spring = osc("tri", vibrato(glide(170, 380, d), 3.0, 22)) * decay(d, 0.1)
    ding = mix(bell("C7", 0.5), 0.4 * bell("E7", 0.4))
    return place([(0.0, spring), (0.0, 0.6 * burst(0.03, 3000, 0.006)), (0.1, 0.45 * ding)])


@sound("lob", 0.7)
def _():
    return mix(whoosh(0.25, 400, 1800), 0.6 * osc("tri", glide(260, 620, 0.1)) * decay(0.1, 0.05))


@sound("dust", 0.75)
def _():
    d = 0.22
    pff = lowpass(noise(d), curve([(0, 4500), (d, 700)], d)) * env([(0, 0), (0.008, 1), (d, 0)], d)
    return mix(pff, 0.5 * thump(0.12, 160, 70, 0.04))


@sound("whoosh", 0.8)
def _():
    return mix(whoosh(0.3, 350, 2200), 0.3 * thump(0.2, 90, 60, 0.1))


@sound("sub", 0.9)
def _():
    d = 0.38
    x = osc("sine", glide(110, 38, d)) * decay(d, 0.16) + 0.5 * osc("tri", glide(220, 76, d)) * decay(d, 0.07)
    return np.tanh(2.0 * x)


# ------------------------------------------------------------ close-up moves
# One per "look" of a melee move: "sfx" in roster.gd, or "m_" + its look.

@sound("m_swipe", 0.75)
def _():
    # Willow's pounce: a butt-wiggle rustle, a chirpy "mrrp!", then a claw swish.
    rustle = svf(noise(0.12), 1800, 0.6, "bp") * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * times(n_of(0.12)))) * env([(0, 0), (0.02, 0.6), (0.12, 0)], 0.12)
    mrrp = meow(900, 0.12)
    swish = whoosh(0.1, 2500, 6000, 0.9)
    return place([(0, 0.5 * rustle), (0.08, 0.7 * mrrp), (0.16, swish)])


@sound("m_knead", 0.8)
def _():
    # Biscuit making biscuits: a deep purr under soft paw pats.
    d = 0.4
    t = times(n_of(d))
    purr = lowpass(osc("saw", 55.0, d) + 0.4 * noise(d), 500) * (0.55 + 0.45 * np.sin(2 * np.pi * 25 * t)) * env([(0, 0), (0.05, 1), (d, 0)], d)
    pat = lambda: burst(0.05, 1200, 0.012) + 0.6 * thump(0.05, 220, 150, 0.015)
    return place([(0, 0.6 * purr), (0.02, pat()), (0.15, 0.8 * pat()), (0.28, 0.7 * pat())])


@sound("m_chomp", 0.85)
def _():
    # Pepper's "Gimme!": an excited yip and a wet cartoon chomp.
    yip = woof(560, 0.08, 3200)
    snap = svf(noise(0.05), 1600, 0.3, "bp") * decay(0.05, 0.012)
    return place([(0, 0.6 * yip), (0.09, snap), (0.09, 0.6 * thump(0.08, 240, 110, 0.02))])


@sound("m_peck", 0.55)
def _():
    # One peck of Kiwi's mashed woodpecker routine (plus a tiny chirp now and then).
    return mix(woodblock(2600, 0.05), 0.25 * chirp(3200, 4200, 0.04))


@sound("m_spin", 0.75)
def _():
    # Zoomba's spot clean: a rising brush whirr with plasticky flicks.
    d = 0.4
    t = times(n_of(d))
    brush = lowpass(noise(d), curve([(0, 1200), (d, 4000)], d)) * (0.5 + 0.5 * np.sin(2 * np.pi * 36 * t))
    motor = 0.35 * osc("saw", glide(160, 380, d)) * env([(0, 0), (0.05, 1), (d, 0)], d)
    flicks = place([(0.1 + 0.08 * k, 0.5 * woodblock(900 + 150 * k, 0.04)) for k in range(3)])
    return mix(brush * env([(0, 0), (0.05, 1), (d, 0)], d), motor, flicks)


@sound("m_flip", 0.8)
def _():
    # Unit-7's spatula: a metal "shwing", a springy BOING, then a little sizzle.
    shwing = highpass(noise(0.08), 4000) * env([(0, 0), (0.01, 1), (0.08, 0)], 0.08) + 0.3 * osc("sine", glide(2500, 3500, 0.08)) * decay(0.08, 0.04)
    boing = osc("tri", vibrato(glide(150, 420, 0.3), 8.0, 16)) * decay(0.3, 0.12)
    sizzle = highpass(noise(0.3), 5000) * env([(0, 0), (0.05, 0.3), (0.3, 0)], 0.3)
    return place([(0, 0.6 * shwing), (0.06, boing), (0.2, sizzle)])


@sound("m_yoink", 0.75)
def _():
    # The Claw's yoink: claw-machine clack-clack, then a slide whistle going up.
    clack = lambda: mix(burst(0.03, 5000, 0.006), 0.5 * woodblock(1400, 0.04))
    whistle = osc("sine", vibrato(expcurve([(0, 600), (0.25, 1800)], 0.25), 0.3, 7)) * env([(0, 0), (0.03, 1), (0.22, 0.8), (0.25, 0)], 0.25)
    return place([(0, clack()), (0.07, clack()), (0.13, 0.5 * whistle)])


@sound("m_feedback", 0.75)
def _():
    # Bass's feedback: a rising mic squeal into a subwoofer thump, with rattling china.
    d = 0.3
    f = vibrato(glide(1600, 2900, d), 1.0, 11)
    squeal = (osc("sine", f) + 0.25 * osc("square", f * 0.5, duty=0.3)) * env([(0, 0), (0.04, 0.8), (d, 1)], d)
    rattle = place([(0.02 * k, 0.25 * woodblock(3000 + 400 * (k % 3), 0.03)) for k in range(8)])
    return place([(0, 0.55 * squeal), (d, thump(0.25, 90, 40, 0.08)), (d, rattle)])


# ----------------------------------------------------------------- specials

@sound("bark", 1.1)
def _():
    return mix(woof(230, 0.2, 1700), 0.6 * thump(0.3, 120, 45, 0.1))


@sound("feathers", 0.6)
def _():
    d = 0.3
    flutter = lowpass(noise(d), 1800) * (0.5 + 0.5 * np.sin(2 * np.pi * 32 * times(n_of(d)))) * env([(0, 0), (0.03, 1), (d, 0)], d)
    return place([(0, flutter), (0.02, 0.5 * chirp(2800, 4000, 0.06)), (0.12, 0.4 * chirp(3200, 4400, 0.06))])


@sound("suck", 0.8)
def _():
    d = 0.45
    rush = lowpass(noise(d), curve([(0, 300), (d, 4200)], d)) * env([(0, 0), (d * 0.8, 1), (d, 0.6)], d)
    tone = 0.3 * osc("sine", glide(200, 750, d)) * env([(0, 0), (d, 1)], d)
    return place([(0, rush + tone), (d - 0.01, 0.8 * thump(0.08, 200, 90, 0.025))])


@sound("rocket", 0.9)
def _():
    d = 0.45
    hiss = lowpass(noise(d), 3200) * env([(0, 0), (0.03, 1), (d, 0)], d)
    rise = 0.3 * osc("square", glide(180, 900, 0.3)) * decay(0.3, 0.12)
    return mix(hiss, rise, 0.5 * thump(0.2, 140, 60, 0.05))


@sound("jump", 0.6)
def _():
    d = 0.2
    return osc("tri", glide(210, 700, d)) * env([(0, 0), (0.01, 1), (d, 0)], d)


@sound("servo", 0.6)
def _():
    d = 0.42
    f = glide(520, 260, d)
    x = lowpass(osc("square", f), 1500) * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 60 * times(n_of(d)))))
    return x * env([(0, 0), (0.02, 1), (d, 0.4)], d)


@sound("slam", 1.15)
def _():
    d = 0.5
    return mix(thump(d, 110, 32, 0.16), 0.7 * burst(0.25, 1000, 0.07), 0.3 * noise(0.2, 1200) * decay(0.2, 0.08))


@sound("clank", 1.0)
def _():
    d = 0.6
    ring = sum(a * osc("sine", f, d) * decay(d, t) for f, a, t in
               [(620, 1.0, 0.18), (1233, 0.6, 0.12), (1871, 0.45, 0.08), (2750, 0.3, 0.05)])
    return mix(0.5 * ring, thump(0.3, 130, 50, 0.07), 0.4 * burst(0.05, 5000, 0.01))


@sound("hype", 0.8)
def _():
    return mix(arpeggio(["C5", "E5", "G5", "C6", "E6"], 0.05, 0.15, 0.125, 0.1), 0.6 * thump(0.2, 140, 50, 0.06))


@sound("gag_ready", 0.6)
def _():
    return place([(k * 0.06, 0.6 * bell(n, 0.4)) for k, n in enumerate(["G5", "C6", "E6", "G6"])])


@sound("poof", 0.45)
def _():
    d = 0.25
    return lowpass(noise(d), 1300) * env([(0, 0), (0.03, 1), (d, 0)], d) + 0.2 * osc("sine", glide(320, 150, d)) * decay(d, 0.08)


# --------------------------------------------------------------- explosions

@sound("boom", 1.15)
def _():
    d = 0.75
    body = lowpass(noise(d), expcurve([(0, 5000), (d, 250)], d)) * decay(d, 0.18)
    crackle = 0.3 * noise(d, 2500) * decay(d, 0.25)
    return mix(body, thump(0.45, 120, 32, 0.13), crackle)


@sound("splat", 0.8)
def _():
    d = 0.2
    squish = svf(noise(d), 1200, 0.4, "bp") * decay(d, 0.05)
    drop = osc("sine", vibrato(glide(700, 120, 0.16), 2.0, 30)) * decay(0.16, 0.05)
    return mix(squish, 0.8 * drop)


@sound("thud", 0.55)
def _():
    return mix(thump(0.1, 160, 70, 0.03), 0.4 * burst(0.04, 900, 0.01))


@sound("poof_big", 0.9)
def _():
    d = 0.7
    cloud = lowpass(noise(d), expcurve([(0, 2600), (d, 500)], d)) * env([(0, 0), (0.04, 1), (d, 0)], d)
    return mix(cloud, 0.6 * thump(0.5, 90, 40, 0.15))


# --------------------------------------------------------------- getting hit

@sound("hit", 0.75)
def _():
    d = 0.1
    return mix(osc("tri", glide(760, 220, d)) * decay(d, 0.035), 0.5 * svf(noise(0.02), 2000, 0.5, "bp") * decay(0.02, 0.004))


@sound("hit_big", 1.0)
def _():
    return mix(thump(0.22, 190, 80, 0.06), 0.6 * osc("tri", glide(950, 300, 0.06)) * decay(0.06, 0.02),
               0.5 * burst(0.1, 1600, 0.02))


@sound("ambush", 0.85)
def _():
    d = 0.45
    swell = highpass(noise(0.12), 3000) * env([(0, 0), (0.1, 1), (0.12, 0)], 0.12)
    sting = (osc("square", "E6", d, 0.25) + osc("square", "F6", d, 0.25)) * decay(d, 0.1)
    return place([(0, 0.5 * swell), (0.1, 0.5 * sting), (0.1, 0.5 * thump(0.2, 200, 60, 0.05))])


@sound("flip", 0.75)
def _():
    d = 0.5
    t = times(n_of(d))
    f = 260 * (1 + 0.35 * np.sin(2 * np.pi * 16 * t)) * np.linspace(1.0, 1.6, len(t))
    return osc("tri", f) * decay(d, 0.16)


@sound("respawn", 0.65)
def _():
    return arpeggio(["C5", "E5", "G5", "C6"], 0.045, 0.12, 0.5, 0.06)


@sound("dash", 0.45)
def _():
    return whoosh(0.15, 1200, 3200, 0.8)


# ------------------------------------------------------------------ voices
# hi_<voice> plays when you pick that character; ko_<voice> when they get KO'd.

@sound("hi_cat", 0.85)
def _():
    return meow(700, 0.42)


@sound("ko_cat", 0.85)
def _():
    return meow(600, 0.75, sad=True)


@sound("hi_dog", 0.9)
def _():
    return place([(0, woof(300)), (0.2, woof(340))])


@sound("ko_dog", 0.85)
def _():
    d = 0.42
    f = expcurve([(0, 700), (0.06, 1150), (d, 480)], d)
    x = svf(osc("saw", f) + 0.4 * osc("sine", f), curve([(0, 1500), (0.06, 2600), (d, 900)], d), 0.4, "lp")
    return place([(0, x * env([(0, 0), (0.02, 1), (d, 0)], d)), (0.45, 0.6 * woof(600, 0.12, 2200))])


@sound("hi_bird", 0.7)
def _():
    return place([(0, chirp(2800, 4200, 0.07)), (0.1, chirp(3000, 4600, 0.07)), (0.2, chirp(3700, 2800, 0.1))])


@sound("ko_bird", 0.7)
def _():
    d = 0.55
    f = vibrato(glide(4200, 1500, d), 1.2, 20)
    return osc("sine", f) * env([(0, 0), (0.03, 1), (d * 0.7, 0.7), (d, 0)], d)


@sound("hi_robot", 0.65)
def _():
    return robot_babble([900, 1350, 980, 1500, 1760, 1300])


@sound("ko_robot", 0.8)
def _():
    d = 0.75
    t = times(n_of(d))
    trem = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * np.cumsum(np.linspace(30, 5, len(t))) / SR))
    x = osc("square", glide(900, 55, d), duty=0.25) * trem * env([(0, 1), (d * 0.8, 0.7), (d, 0)], d)
    return place([(0, x), (d - 0.05, 0.4 * noise(0.1, 4000) * decay(0.1, 0.03))])


@sound("hi_vacuum", 0.7)
def _():
    d = 0.35
    motor = lowpass(osc("saw", glide(60, 150, d)) + 0.4 * noise(d), 900) * env([(0, 0), (0.05, 1), (d, 0.3)], d)
    return place([(0, motor), (0.28, blip("E6", 0.07, 0.25)), (0.37, blip("A6", 0.1, 0.25))])


@sound("ko_vacuum", 0.75)
def _():
    d = 0.6
    spin = lowpass(osc("saw", glide(150, 30, d)) + 0.3 * noise(d), 800) * env([(0, 1), (d, 0)], d)
    return place([(0, spin), (0.1, blip("A5", 0.12, 0.25)), (0.28, blip("E5", 0.12, 0.25)), (0.46, blip("C5", 0.3, 0.25))])


@sound("hi_claw", 0.65)
def _():
    d = 0.26
    f = glide(300, 540, d)
    whirr = lowpass(osc("square", f), 1600) * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 50 * times(n_of(d)))))
    return place([(0, whirr * env([(0, 0), (0.02, 1), (d, 0.5)], d)), (0.27, woodblock("A5", 0.06)), (0.27, 0.6 * burst(0.03, 6000, 0.005))])


@sound("ko_claw", 0.8)
def _():
    d = 0.5
    droop = lowpass(osc("square", glide(540, 110, d)), 1400) * env([(0, 1), (d, 0.3)], d)
    return place([(0, droop), (0.5, thump(0.3, 120, 45, 0.08)), (0.5, 0.5 * burst(0.08, 2500, 0.02))])


@sound("hi_speaker", 0.75)
def _():
    return place([(0, wub(0.35)), (0.3, 0.6 * bell("E6", 0.4)), (0.46, 0.6 * bell("B5", 0.5))])


@sound("ko_speaker", 0.8)
def _():
    d = 0.75
    slow = curve([(0, 1.0), (d, 0.04)], d) ** 1.5  # a tape slowing to a stop
    chord = sum(osc("saw", hz(n) * slow) for n in ["C4", "E4", "G4"])
    return lowpass(chord, curve([(0, 3000), (d, 300)], d)) * env([(0, 1), (d * 0.8, 0.8), (d, 0)], d)


# ----------------------------------------------------------------------- gags

@sound("tada", 0.9)
def _():
    long = n_of(0.45 + 0.1)
    lead = place([(0, osc("square", "G4", 0.07 + 0.02, 0.5) * adsr(0.07, 0.003, 0.05, 0.7, 0.02)),
                  (0.11, osc("square", vibrato(np.full(long, hz("C5")), 0.3, 6, 0.15)) * adsr(0.45, 0.004, 0.2, 0.7, 0.1))])
    harm = place([(0.11, 0.5 * osc("square", "E5", 0.45 + 0.1, 0.25) * adsr(0.45, 0.004, 0.2, 0.6, 0.1)),
                  (0.11, 0.4 * osc("tri", "C3", 0.45 + 0.1) * adsr(0.45, 0.004, 0.3, 0.6, 0.1))])
    return mix(lead, harm)


@sound("flock", 0.85)
def _():
    d = 1.3
    flutter = lowpass(noise(d), 2000) * (0.55 + 0.45 * np.sin(2 * np.pi * 26 * times(n_of(d)))) * env([(0, 0), (0.1, 1), (d * 0.7, 0.8), (d, 0)], d)
    parts = [(0.0, 0.7 * flutter)]
    for _k in range(16):
        f0 = rng.uniform(2400, 4200)
        parts.append((rng.uniform(0.0, d - 0.12), 0.35 * chirp(f0, f0 * rng.uniform(1.15, 1.45), rng.uniform(0.05, 0.09))))
    return place(parts)


@sound("vacuum", 0.9)
def _():
    d = 3.0
    f = expcurve([(0, 70), (0.6, 160), (d, 178)], d)
    motor = lowpass(osc("saw", f) + 0.5 * osc("square", f * 2.01, duty=0.3), 1400)
    rush = lowpass(noise(d), curve([(0, 400), (0.8, 3500), (d, 3800)], d))
    whine = 0.12 * osc("sine", glide(900, 1500, d))
    return (0.6 * motor + 0.6 * rush + whine) * env([(0, 0), (0.15, 1), (d - 0.35, 1), (d, 0)], d)


@sound("gulp", 0.85)
def _():
    return place([(0, osc("sine", glide(520, 150, 0.12)) * decay(0.12, 0.05)),
                  (0.14, osc("sine", glide(330, 110, 0.1)) * decay(0.1, 0.04))])


@sound("spit", 0.85)
def _():
    return place([(0, svf(noise(0.05), 2500, 0.5, "bp") * decay(0.05, 0.012)),
                  (0.02, osc("sine", glide(950, 230, 0.16)) * decay(0.16, 0.06))])


@sound("sat_lock", 0.6)
def _():
    beeps = [0.0, 0.3, 0.5, 0.66, 0.78, 0.88, 0.96, 1.03, 1.09, 1.14]
    parts = [(t, blip(1400, 0.04, 0.5, 0.03)) for t in beeps]
    parts.append((0.0, 0.25 * osc("sine", glide(400, 1600, 1.2)) * env([(0, 0), (1.1, 1), (1.2, 0)], 1.2)))
    return place(parts)


@sound("sat_beam", 1.2)
def _():
    d = 0.95
    t = times(n_of(d))
    trem = 0.7 + 0.3 * np.sin(2 * np.pi * 40 * t)
    beam = sum(osc("saw", f, d) for f in (110, 165, 220.5)) / 3 * trem
    beam = lowpass(beam + 0.4 * noise(d), 3500) * decay(d, 0.4, 0.01)
    return mix(beam, thump(0.5, 140, 32, 0.15), 0.5 * burst(0.5, 3000, 0.12))


@sound("claw_machine", 0.8)
def _():
    notes = ["C6", "E6", "G6", "C7", "G6", "E6", "C6", "G5", "C6"]
    tune = arpeggio(notes, 0.07, 0.08, 0.125, 0.05)
    d = len(notes) * 0.07 + 0.1
    whirr = 0.3 * lowpass(osc("square", 180.0, d), 900) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 40 * times(n_of(d)))))
    return mix(tune, whirr * env([(0, 0), (0.05, 1), (d, 0)], d))


@sound("grab", 0.9)
def _():
    d = 0.4
    ring = sum(a * osc("sine", f, d) * decay(d, t) for f, a, t in [(880, 1.0, 0.1), (1760 * 1.02, 0.5, 0.06), (2630, 0.3, 0.04)])
    return place([(0, 0.5 * ring), (0, 0.6 * thump(0.15, 180, 80, 0.04)), (0.12, 0.5 * arpeggio(["G5", "C6"], 0.06, 0.08))])


@sound("disco", 0.9)
def _():
    return render_disco()


# ------------------------------------------------------------- the house

@sound("crack", 0.7)
def _():
    parts = [(t, a * svf(noise(0.03), 1800, 0.5, "bp") * decay(0.03, 0.008)) for t, a in [(0, 1.0), (0.03, 0.7), (0.07, 0.5)]]
    parts.append((0, 0.6 * osc("sine", 160, 0.1) * decay(0.1, 0.03)))
    return place(parts)


@sound("crash", 1.2)
def _():
    d = 1.0
    body = lowpass(noise(d), expcurve([(0, 6000), (d, 400)], d)) * decay(d, 0.25)
    parts = [(0, body), (0, thump(0.35, 100, 40, 0.1))]
    for k in range(9):
        parts.append((0.08 + k * 0.08 + rng.uniform(0, 0.04), (0.9 - k * 0.08) * woodblock(rng.uniform(500, 2200), 0.07)))
    return place(parts)


@sound("rebuilt", 0.85)
def _():
    parts = [(k * 0.045, highpass(noise(0.012), 2500) * decay(0.012, 0.003)) for k in range(6)]
    parts += [(0.3, 0.6 * bell("C6", 0.6)), (0.3, 0.45 * bell("E6", 0.6)), (0.3, 0.35 * bell("G6", 0.6))]
    return place(parts)


@sound("knock", 0.75)
def _():
    parts = [(t, a * woodblock(f, 0.07)) for t, a, f in [(0, 1.0, 900), (0.06, 0.7, 1250), (0.13, 0.5, 760)]]
    parts.append((0, 0.5 * thump(0.12, 140, 70, 0.03)))
    return place(parts)


@sound("tidy", 0.7)
def _():
    return place([(k * 0.045, 0.6 * bell(n, 0.35)) for k, n in enumerate(["E6", "G#6", "B6", "E7"])]
                 + [(0, 0.15 * highpass(noise(0.3), 5000) * env([(0, 0), (0.05, 1), (0.3, 0)], 0.3))])


@sound("scrub", 0.45)
def _():
    swish = svf(noise(0.12), 2800, 0.8, "bp") * env([(0, 0), (0.05, 1), (0.12, 0)], 0.12)
    return place([(0, 0.6 * swish), (0.06, bell("E7", 0.25))])


# -------------------------------------------------------------- the remote

@sound("pickup", 0.7)
def _():
    return place([(0, blip("B5", 0.06, 0.5, 0.05)), (0.06, blip("E6", 0.18, 0.5, 0.08))])


@sound("throw", 0.65)
def _():
    return mix(whoosh(0.22, 700, 2600), 0.5 * osc("square", glide(500, 950, 0.08), duty=0.25) * decay(0.08, 0.03))


@sound("drop", 0.6)
def _():
    return place([(0, blip("A5", 0.06, 0.5, 0.04)), (0.07, blip("E5", 0.1, 0.5, 0.05)), (0.07, 0.5 * woodblock(700, 0.06))])


@sound("remote_home", 0.6)
def _():
    return place([(0, osc("tri", glide(400, 820, 0.12)) * decay(0.12, 0.06)), (0.1, blip("G6", 0.1, 0.25, 0.04))])


@sound("channel_tick", 0.55)
def _():
    return blip("C6", 0.07, 0.25, 0.03)


@sound("score", 1.0)
def _():
    static = noise(0.25, 9000) * env([(0, 0), (0.01, 1), (0.2, 0.8), (0.25, 0)], 0.25)
    return place([(0, 0.5 * static), (0.22, render_jingle("score"))])


# ------------------------------------------------------------------ phases

@sound("parents_leave", 1.0)
def _():
    door = mix(thump(0.3, 85, 42, 0.07), 0.5 * burst(0.15, 400, 0.04))
    latch = highpass(noise(0.015), 3000) * decay(0.015, 0.004)
    d = 2.2
    f = expcurve([(0, 38), (0.4, 52), (1.4, 78), (d, 70)], d)
    putt = 0.65 + 0.35 * np.sin(2 * np.pi * np.cumsum(f * 0.5) / SR)
    engine = lowpass(osc("saw", f) + 0.3 * noise(d), 500) * putt * env([(0, 0), (0.15, 1), (0.8, 0.8), (d, 0)], d)
    return place([(0, door), (0.12, 0.5 * latch), (0.55, 0.9 * engine)])


@sound("car_horn", 1.1)
def _():
    def honk(dur):
        x = osc("square", 370.0, dur) + 0.8 * osc("square", 466.0, dur)
        return lowpass(x, 1800) * env([(0, 0), (0.01, 1), (dur - 0.03, 1), (dur, 0)], dur)
    return place([(0, honk(0.16)), (0.23, honk(0.34))])


@sound("whistle", 0.9)
def _():
    d = 0.45
    f = 2600 * (1 + 0.04 * np.sin(2 * np.pi * 28 * times(n_of(d))))
    tone = osc("sine", f) + 0.25 * osc("sine", f * 2)
    breath = 0.3 * svf(noise(d), 3000, 0.7, "bp")
    return (tone + breath) * env([(0, 0), (0.02, 1), (0.36, 0.9), (d, 0)], d)


@sound("tick", 0.55)
def _():
    return woodblock(1800, 0.08)


@sound("spotless", 1.0)
def _():
    return render_jingle("spotless")


@sound("fine", 1.0)
def _():
    return render_jingle("fine")


@sound("grounded", 1.0)
def _():
    notes = [("G3", 0.0, 0.42), ("F#3", 0.48, 0.42), ("F3", 0.96, 0.42), ("E3", 1.44, 1.2)]
    parts = []
    for k, (n, t, d) in enumerate(notes):
        f = np.full(n_of(d), hz(n))
        if k == 3:
            f = vibrato(f, 0.5, 5.5, 0.25)
        cut = curve([(0, 300), (0.1, 1500), (d, 500)], d)  # "wah"
        x = svf(osc("saw", f) + 0.3 * osc("square", f), cut, 0.35, "lp")
        parts.append((t, x * env([(0, 0), (0.03, 1), (d - 0.06, 0.8), (d, 0)], d)))
    return place(parts)


# ---------------------------------------------------------------------- UI

@sound("click", 0.4)
def _():
    return place([(0, blip(1000, 0.03, 0.5, 0.008)), (0, 0.3 * highpass(noise(0.004), 3000))])


@sound("select", 0.5)
def _():
    return place([(0, blip("E6", 0.05, 0.25, 0.03)), (0.05, blip("B6", 0.09, 0.25, 0.04))])


@sound("start", 0.7)
def _():
    return arpeggio(["C5", "E5", "G5", "C6"], 0.06, 0.25, 0.25, 0.1)


# ==================================================================== music

CHORDS = {"maj": [0, 4, 7], "min": [0, 3, 7], "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11],
          "m7": [0, 3, 7, 10], "m6": [0, 3, 7, 9]}


def chord_bar(spec: str):
    """'E m7 | A 7' -> [(root_pitch_class, intervals, start_beat, beats), ...]"""
    parts = [p.split() for p in spec.split("|")]
    share = 4.0 / len(parts)
    return [(midi(root + "0") % 12, CHORDS[q], k * share, share) for k, (root, q) in enumerate(parts)]


def voicing(pc: int, intervals, lo: int) -> list[int]:
    """Chord tones packed into the octave starting at midi note `lo`."""
    return sorted(lo + (pc + i - lo) % 12 for i in intervals)


def shift(note: str, octaves: int) -> str:
    return note[:-1] + str(int(note[-1]) + octaves) if octaves else note


# Instruments: (frequency, seconds, velocity, sample_rate) -> signal (with its tail).

def i_lead(f, dur, vel, sr, duty=0.25):
    n = n_of(dur + 0.06, sr)
    fr = vibrato(np.full(n, f), 0.2, 5.5, 0.14, sr)
    return 0.26 * vel * osc("square", fr, duty=duty, sr=sr) * adsr(dur, 0.004, 0.15, 0.6, 0.06, sr)


def i_bright(f, dur, vel, sr):
    return i_lead(f, dur, vel, sr, 0.5)


def i_musicbox(f, dur, vel, sr):
    d = max(dur, 0.25) + 0.6
    return 0.4 * vel * (osc("sine", f, d, sr=sr) * decay(d, 0.55, 0.003, sr)
                        + 0.3 * osc("sine", f * 2, d, sr=sr) * decay(d, 0.22, 0.003, sr)
                        + 0.08 * osc("sine", f * 3, d, sr=sr) * decay(d, 0.1, 0.003, sr))


def i_soft(f, dur, vel, sr):
    n = n_of(dur + 0.12, sr)
    fr = vibrato(np.full(n, f), 0.15, 5.0, 0.2, sr)
    x = osc("tri", fr, sr=sr) + 0.25 * osc("square", fr, duty=0.125, sr=sr)
    return 0.22 * vel * x * adsr(dur, 0.02, 0.25, 0.5, 0.12, sr)


def i_keys(f, dur, vel, sr):
    x = osc("tri", f, dur + 0.15, sr=sr) + 0.3 * osc("square", f, dur + 0.15, 0.5, sr)
    return 0.1 * vel * x * adsr(dur, 0.008, 0.25, 0.3, 0.15, sr)


def i_pad(f, dur, vel, sr):
    d = dur + 0.3
    x = osc("tri", f * 1.003, d, sr=sr) + osc("tri", f * 0.997, d, sr=sr)
    return 0.05 * vel * x * adsr(dur, 0.15, 0.6, 0.7, 0.3, sr)


def i_bass(f, dur, vel, sr):
    return 0.5 * vel * osc("tri", f, dur + 0.04, sr=sr) * adsr(dur, 0.003, 0.25, 0.65, 0.04, sr)


def i_pluck_bass(f, dur, vel, sr):
    return 0.55 * vel * osc("tri", f, dur + 0.05, sr=sr) * adsr(dur, 0.003, 0.3, 0.35, 0.05, sr)


def i_arp(f, dur, vel, sr):
    return 0.1 * vel * osc("square", f, dur + 0.03, 0.125, sr) * adsr(dur, 0.002, 0.06, 0.3, 0.03, sr)


def i_stab(f, dur, vel, sr):
    return 0.09 * vel * osc("square", f, dur + 0.03, 0.25, sr) * adsr(dur, 0.002, 0.05, 0.25, 0.03, sr)


_drum_cache: dict[tuple[str, int], np.ndarray] = {}


def drum(name: str, sr: int) -> np.ndarray:
    key = (name, sr)
    if key in _drum_cache:
        return _drum_cache[key]
    if name == "kick":
        d = 0.16
        x = 0.9 * osc("sine", glide(150, 45, d, sr), sr=sr) * decay(d, 0.06, 0.001, sr)
        x[:n_of(0.003, sr)] += 0.3 * noise(0.003, sr=sr)
    elif name == "snare":
        d = 0.16
        x = 0.4 * lowpass(noise(d, sr=sr), 7000, sr) * decay(d, 0.05, 0.001, sr) \
            + 0.3 * osc("tri", 190.0, d, sr=sr) * decay(d, 0.03, 0.001, sr)
    elif name == "hat":
        d = 0.05
        x = 0.16 * highpass(noise(d, sr=sr), 7000, sr) * decay(d, 0.012, 0.001, sr)
    elif name == "ohat":
        d = 0.2
        x = 0.12 * highpass(noise(d, sr=sr), 6000, sr) * decay(d, 0.07, 0.001, sr)
    elif name == "rim":
        d = 0.05
        x = 0.25 * osc("sine", 1700.0, d, sr=sr) * decay(d, 0.012, 0.001, sr) \
            + 0.15 * highpass(noise(d, sr=sr), 3000, sr) * decay(d, 0.004, 0.001, sr)
    elif name == "shaker":
        d = 0.06
        x = 0.07 * highpass(lowpass(noise(d, sr=sr), 9000, sr), 4000, sr) * env([(0, 0), (0.012, 1), (d, 0)], d, sr)
    elif name in ("tick", "tock"):
        d = 0.07
        f = 1800.0 if name == "tick" else 1350.0
        x = 0.22 * (osc("sine", f, d, sr=sr) * decay(d, 0.02, 0.001, sr)
                    + 0.3 * osc("sine", f * 2.7, d, sr=sr) * decay(d, 0.006, 0.001, sr))
    else:
        raise ValueError(name)
    _drum_cache[key] = x
    return x


class Song:
    """A tiny tracker: notes and drum hits placed on a beat grid, with optional swing."""

    def __init__(self, bpm: float, bars: int, swing: float = 0.5, sr: int = MUSIC_SR):
        self.sr = sr
        self.beat = 60.0 / bpm
        self.swing = swing  # where the off-beat eighth lands (0.5 = straight)
        self.beats = bars * 4
        self.n = n_of(self.beats * self.beat, sr)
        self.buf = np.zeros(self.n + sr * 3)

    def time(self, beat: float) -> float:
        whole = np.floor(beat + 1e-9)
        frac = beat - whole
        if frac < 0.5:
            frac = frac / 0.5 * self.swing
        else:
            frac = self.swing + (frac - 0.5) / 0.5 * (1.0 - self.swing)
        return (whole + frac) * self.beat

    def add(self, beat: float, x: np.ndarray, gain: float = 1.0) -> None:
        i = int(round(self.time(beat) * self.sr))
        self.buf[i:i + len(x)] += gain * x[:len(self.buf) - i]

    def note(self, inst, beat: float, beats: float, pitch, vel: float = 1.0) -> None:
        dur = self.time(beat + beats) - self.time(beat)
        f = mhz(pitch) if isinstance(pitch, (int, np.integer)) else hz(pitch)
        self.add(beat, inst(f, dur, vel, self.sr))

    def melody(self, inst, beat: float, tokens: str, vel: float = 1.0, octaves: int = 0) -> float:
        """'E5:0.5 A5:1 r:0.5 ...' (note:beats, r = rest)."""
        for tok in tokens.split():
            note, beats = tok.split(":")
            if note != "r":
                self.note(inst, beat, float(beats) * 0.95, shift(note, octaves), vel)
            beat += float(beats)
        return beat

    def drums(self, bar: int, pattern: dict[str, str], vel: float = 1.0) -> None:
        """16 characters per bar, one per sixteenth: 'x' hit, 'o' soft hit, '.' nothing."""
        for name, steps in pattern.items():
            for k, c in enumerate(steps.replace(" ", "")):
                if c in "xo":
                    self.add(bar * 4 + k * 0.25, drum(name, self.sr), vel * (1.0 if c == "x" else 0.55))

    def loop(self) -> np.ndarray:
        out = self.buf[:self.n].copy()
        tail = self.buf[self.n:]
        out[:len(tail)] += tail[:self.n]  # whatever rings past the end wraps to the start
        return master(out)

    def oneshot(self) -> np.ndarray:
        nz = np.nonzero(np.abs(self.buf) > 1e-4)[0]
        return self.buf[:nz[-1] + 1] if len(nz) else self.buf[:1]


def master(x: np.ndarray, peak: float = 0.72) -> np.ndarray:
    x = np.tanh(1.3 * x / max(np.max(np.abs(x)), 1e-9)) / np.tanh(1.3)
    return x * peak


def music_menu() -> np.ndarray:
    """'Lazy Afternoon': jazzy, sleepy, swung. Plays in the menus."""
    s = Song(bpm=88, bars=16, swing=0.62)
    prog = ["F maj7", "E m7 | A 7", "D m7", "C m7 | F 7", "Bb maj7", "Bb m6", "A m7 | D 7", "G m7 | C 7"] * 2
    for bar, spec in enumerate(prog):
        chords = chord_bar(spec)
        next_root = chord_bar(prog[(bar + 1) % len(prog)])[0][0]
        for k, (pc, iv, start, beats) in enumerate(chords):
            b0 = bar * 4 + start
            root = 41 + (pc - 41) % 12  # F2..E3
            # Walking bass: root, fifth, (next root), then a step into the next chord.
            if beats == 4:
                line = [root, root + 7, root + 12 if root < 45 else root + iv[1], None]
            else:
                line = [root, root + 7]
            for j, m in enumerate(line):
                if m is None:
                    target = 41 + (next_root - 41) % 12
                    m = target - 1 if bar % 2 == 0 else target + 1
                s.note(i_pluck_bass, b0 + j, 0.9, m, 0.9 if j == 0 else 0.7)
            for m in voicing(pc, iv, 62):
                s.note(i_keys, b0, 0.75, m, 0.9)
                if beats == 4:
                    s.note(i_keys, b0 + 1.5, 0.5, m, 0.6)
                s.note(i_pad, b0, beats, m - 12, 1.0)
        s.drums(bar, {"kick": "x.....o.x.......", "rim": "....x.......x...",
                      "shaker": "o.x.o.x.o.x.o.x."}, 0.8)
    a = ("C5:0.5 F5:0.5 A5:1 G5:0.5 F5:0.5 E5:1 "
         "D5:0.5 E5:0.5 G5:1 E5:1.5 C#5:0.5 "
         "D5:1.5 F5:0.5 A5:1 C6:1 "
         "Bb5:1 G5:0.5 Eb5:0.5 A5:1 r:1 "
         "D6:1 C6:0.5 Bb5:0.5 A5:1 F5:1 "
         "Db6:1.5 Bb5:0.5 F5:2 "
         "E5:0.5 G5:0.5 C6:1 A5:0.5 F#5:0.5 D5:1 "
         "F5:1 G5:0.5 Bb5:0.5 G5:1 E5:1")
    b = ("A5:0.5 C6:0.5 E6:1 D6:0.5 C6:0.5 A5:1 "
         "B5:0.5 G5:0.5 E5:1 G5:0.5 E5:0.5 C#5:1 "
         "F5:1 A5:1 C6:1.5 A5:0.5 "
         "G5:0.5 Bb5:0.5 Eb6:1 C6:1 A5:1 "
         "F5:0.5 A5:0.5 D6:1.5 C6:0.5 A5:1 "
         "G5:1 F5:0.5 Db5:0.5 F5:2 "
         "E5:0.5 A5:0.5 C6:1 F#5:1 A5:1 "
         "Bb5:1 A5:0.5 G5:0.5 E5:1 r:1")
    s.melody(i_musicbox, 0, a)
    s.melody(i_musicbox, 32, b)
    s.melody(i_soft, 32, b, 0.6, -1)
    return s.loop()


def music_war() -> np.ndarray:
    """'Remote Control': fast and bouncy. Plays during the war."""
    s = Song(bpm=150, bars=16)
    prog = ["A min", "F maj", "C maj", "G maj", "A min", "F maj", "C maj", "E maj",
            "F maj", "G maj", "A min", "A min", "F maj", "G maj", "E maj", "E 7"]
    for bar, spec in enumerate(prog):
        (pc, iv, _start, _beats), = chord_bar(spec)
        root = 33 + (pc - 33) % 12  # A1..G#2
        for k in range(8):
            m = root + (12 if k % 2 else 0)
            if k == 7:
                m = root + 7
            s.note(i_bass, bar * 4 + k * 0.5, 0.42, m, 1.0 if k % 2 == 0 else 0.8)
        tones = voicing(pc, iv[:3], 64)
        ladder = tones + [tones[0] + 12]
        order = [0, 1, 2, 3, 2, 1]
        for k in range(16):
            s.note(i_arp, bar * 4 + k * 0.25, 0.2, ladder[order[k % 6]], 1.0 if k % 4 == 0 else 0.7)
        fill = bar % 8 == 7
        s.drums(bar, {"kick": "x.....x.x.....x." if bar % 2 else "x.......x.......",
                      "snare": "....x.......xxxx" if fill else "....x.......x...",
                      "hat": "x.x.x.x.x.x.x..." if fill else "x.x.x.x.x.x.x.x.",
                      "ohat": "..............x." if not fill else "................"})
    a = ("E5:0.5 A5:0.5 B5:0.5 C6:1 B5:0.5 A5:1 "
         "C6:0.5 A5:0.5 F5:1 G5:0.5 A5:0.5 C6:1 "
         "E5:1 G5:0.5 C6:1 E6:1 D6:0.5 "
         "B5:1.5 A5:0.5 G5:1 D5:1 "
         "E5:0.5 A5:0.5 B5:0.5 C6:1 D6:0.5 E6:1 "
         "F6:1 E6:0.5 D6:0.5 C6:1 A5:1 "
         "G5:0.5 C6:0.5 E6:0.5 G6:1 E6:0.5 C6:1 "
         "B5:1 G#5:1 E5:1 r:1")
    b = ("A5:0.5 A5:0.5 C6:0.5 A5:0.5 F6:1 E6:1 "
         "D6:0.5 D6:0.5 B5:0.5 G5:0.5 D6:1 C6:0.5 B5:0.5 "
         "A5:1 C6:0.5 E6:1.5 D6:0.5 C6:0.5 "
         "B5:0.5 C6:0.5 B5:0.5 A5:0.5 E5:2 "
         "F5:0.5 A5:0.5 C6:0.5 F6:0.5 E6:1 C6:1 "
         "D6:0.5 B5:0.5 G5:0.5 B5:0.5 D6:1 G6:1 "
         "G#6:1.5 F#6:0.5 E6:1 B5:1 "
         "D6:1 B5:0.5 G#5:0.5 E5:1 r:1")
    s.melody(i_lead, 0, a)
    s.melody(i_lead, 32, b)
    s.melody(i_lead, 32, b, 0.35, -1)  # a quiet octave below in the second half
    return s.loop()


def music_cleanup() -> np.ndarray:
    """'Hide the Evidence': a frantic chase with a ticking clock. Plays during cleanup."""
    s = Song(bpm=176, bars=16)
    prog = ["C maj", "C maj", "G 7", "G 7", "G 7", "G 7", "C maj", "C maj",
            "F maj", "C maj", "G 7", "C maj", "F maj", "C maj", "G 7", "G 7"]
    for bar, spec in enumerate(prog):
        (pc, iv, _start, _beats), = chord_bar(spec)
        root = 36 + (pc - 36) % 12  # C2..B2
        s.note(i_bass, bar * 4, 0.45, root, 1.0)
        s.note(i_bass, bar * 4 + 2, 0.45, root + 7 - (12 if root + 7 > 47 else 0), 0.9)
        for beat in (1, 3):
            for m in voicing(pc, iv, 60):
                s.note(i_stab, bar * 4 + beat, 0.3, m, 1.0)
        s.drums(bar, {"kick": "x.......x.......", "snare": "....o.......o...",
                      "tick": "x...x...x...x...", "tock": "..x...x...x...x."})
    tune = ("G5:0.5 G5:0.5 A5:0.5 G5:0.5 E5:0.5 C5:0.5 E5:0.5 G5:0.5 "
            "C6:1 B5:0.5 C6:0.5 G5:1 E5:1 "
            "F5:0.5 F5:0.5 G5:0.5 F5:0.5 D5:0.5 B4:0.5 D5:0.5 F5:0.5 "
            "B5:1 A#5:0.5 B5:0.5 G5:1 D5:1 "
            "G5:0.25 A5:0.25 B5:0.25 C6:0.25 D6:0.5 B5:0.5 G5:0.5 F5:0.5 D5:0.5 B4:0.5 "
            "F5:0.5 E5:0.5 D5:0.5 F5:0.5 G5:1 r:1 "
            "E5:0.5 E5:0.5 F5:0.5 E5:0.5 C5:0.5 G4:0.5 C5:0.5 E5:0.5 "
            "G5:0.25 F#5:0.25 G5:0.25 A5:0.25 G5:0.5 E5:0.5 C5:1 r:1 "
            "A5:0.5 A5:0.5 C6:0.5 A5:0.5 F5:0.5 A5:0.5 C6:1 "
            "G5:0.5 G5:0.5 E6:0.5 C6:0.5 G5:1 E5:1 "
            "D6:0.5 C6:0.5 B5:0.5 A5:0.5 G5:0.5 F5:0.5 E5:0.5 D5:0.5 "
            "C5:0.5 E5:0.5 G5:0.5 C6:0.5 E6:1 C6:1 "
            "F5:0.25 G5:0.25 A5:0.25 Bb5:0.25 C6:0.5 A5:0.5 F5:1 C6:1 "
            "E6:0.5 D6:0.5 C6:0.5 G5:0.5 E5:0.5 G5:0.5 C6:1 "
            "B5:0.5 D6:0.5 F6:0.5 D6:0.5 B5:0.5 G5:0.5 F5:0.5 D5:0.5 "
            "G5:0.25 G#5:0.25 A5:0.25 A#5:0.25 B5:1 r:2")
    s.melody(i_bright, 0, tune, 0.9)
    s.melody(i_musicbox, 0, tune, 0.35, 1)  # a xylophone an octave up
    return s.loop()


MUSIC: dict[str, Callable[[], np.ndarray]] = {"menu": music_menu, "war": music_war, "cleanup": music_cleanup}


def render_jingle(which: str) -> np.ndarray:
    s = Song(bpm=160 if which != "spotless" else 140, bars=2, sr=SR)
    if which == "score":
        s.melody(i_bright, 0, "G5:0.5 C6:0.5 E6:0.5 G6:1.5")
        s.melody(i_lead, 0, "E5:0.5 G5:0.5 C6:0.5 E6:1.5", 0.6)
        s.note(i_bass, 0, 1.0, "C3")
        s.note(i_bass, 1.5, 1.5, "C3")
        s.drums(0, {"kick": "x.....x.........", "snare": "......x.........", "ohat": "......x........."})
    elif which == "spotless":
        s.melody(i_bright, 0, "C5:0.5 E5:0.5 G5:0.5 C6:0.5 B5:0.5 C6:0.5 D6:0.5 E6:2.5")
        s.melody(i_lead, 0, "r:2 G5:0.5 A5:0.5 B5:0.5 C6:2.5", 0.6)
        s.melody(i_musicbox, 0, "r:3.5 E6:0.5 G6:0.5 C7:1.5", 0.7)
        for beat, m in [(0, "C3"), (2, "G2"), (3.5, "C3")]:
            s.note(i_bass, beat, 1.4, m)
        s.drums(0, {"kick": "x.......x.....x.", "snare": "....x.......x.x.", "ohat": "..............x."})
    elif which == "fine":
        s.melody(i_bright, 0, "E5:0.5 G5:0.5 D5:0.5 C5:1.5")
        s.melody(i_soft, 0, "C5:0.5 E5:0.5 B4:0.5 G4:1.5", 0.7)
        s.note(i_bass, 0, 1.0, "C3")
        s.note(i_bass, 1.5, 1.5, "C3")
        s.drums(0, {"kick": "x.....x.........", "snare": "......x........."})
    return s.oneshot()


def render_disco() -> np.ndarray:
    s = Song(bpm=124, bars=2, sr=SR)
    for bar in range(2):
        s.drums(bar, {"kick": "x...x...x...x...", "ohat": "..x...x...x...x.", "snare": "....x.......x..."})
        for k in range(8):
            s.note(i_bass, bar * 4 + k * 0.5, 0.4, "A2" if k % 2 == 0 else "A3")
        for beat in (1.5, 3.5):
            for m in voicing(9, CHORDS["m7"], 64):
                s.note(i_stab, bar * 4 + beat, 0.4, m, 1.3)
    s.melody(i_bright, 0, "E6:0.5 G6:0.5 A6:1 r:1 E6:0.25 G6:0.25 A6:0.5 C7:1.5", 0.6)
    x = s.oneshot()
    cut = n_of(2.8)
    x = x[:cut]
    x[-n_of(0.15):] *= np.linspace(1.0, 0.0, n_of(0.15))
    return x


# ================================================================== output

def finish(x: np.ndarray, level: float, sr: int = SR) -> np.ndarray:
    """Removes rumble, evens out loudness between sounds, and fades the edges."""
    x = highpass(np.asarray(x, float), 30, sr)
    win = max(1, int(0.03 * sr))
    energy = np.convolve(x * x, np.ones(win) / win, mode="same")
    loud = np.sqrt(np.max(energy)) if len(x) else 1.0
    x = x * (0.28 * level / max(loud, 1e-9))
    peak = np.max(np.abs(x))
    if peak > 0.95:
        x = np.tanh(x / peak * 1.5) / np.tanh(1.5) * 0.95
    fade_in = min(len(x), n_of(0.001, sr))
    fade_out = min(len(x), n_of(0.008, sr))
    x[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    x[len(x) - fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    return x


def main() -> int:
    global rng
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="only make these sounds / songs")
    ap.add_argument("--list", action="store_true", help="list every sound and song")
    args = ap.parse_args()
    unknown = [n for n in args.names if n not in SOUNDS and n not in MUSIC]
    if unknown:
        print("unknown: " + ", ".join(unknown), file=sys.stderr)
        return 1
    SOUND_DIR.mkdir(parents=True, exist_ok=True)
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    wanted = set(args.names) if args.names else set(SOUNDS) | set(MUSIC)
    for name, (fn, level) in SOUNDS.items():
        if name not in wanted:
            continue
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        x = finish(fn(), level)
        if args.list:
            print(f"{name:16s} {len(x) / SR:5.2f}s")
            continue
        sf.write(SOUND_DIR / f"{name}.wav", x, SR, subtype="PCM_16")
    for name, fn in MUSIC.items():
        if name not in wanted:
            continue
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        x = fn()
        if args.list:
            print(f"{name:16s} {len(x) / MUSIC_SR:5.2f}s (music)")
            continue
        sf.write(MUSIC_DIR / f"{name}.ogg", x, MUSIC_SR, format="OGG", subtype="VORBIS", compression_level=0.55)
    if not args.list:
        print(f"wrote {len([n for n in SOUNDS if n in wanted])} sounds to {SOUND_DIR.relative_to(ROOT)} "
              f"and {len([n for n in MUSIC if n in wanted])} songs to {MUSIC_DIR.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
