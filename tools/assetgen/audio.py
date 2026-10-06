"""Chiptune synthesis: sound effects and looping music, rendered with numpy.

Voices mimic a classic 8-bit sound chip: band-limited (PolyBLEP) pulse waves
for leads, a triangle for bass and sample-and-hold noise for percussion.
All melodies are original. Music files carry a RIFF 'smpl' loop chunk so
Godot's WAV importer loops them automatically ("Detect From WAV").
"""

import struct

import numpy as np

SR = 22050
_NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(note: str) -> float:
    """'A4' -> 440.0. Sharps only ('C#5')."""
    name, octave = note[:-1], int(note[-1])
    midi = 12 * (octave + 1) + _NOTES[name]
    return 440.0 * 2 ** ((midi - 69) / 12)


# ------------------------------------------------------------------- oscillators

def _phase(f, n: int):
    f = np.broadcast_to(np.asarray(f, dtype=np.float64), (n,))
    dt = f / SR
    return np.mod(np.cumsum(dt) - dt, 1.0), dt


def _blep(t, dt):
    out = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    out[m] = x * x + x + x + 1.0
    return out


def pulse(f, dur: float, duty: float = 0.5):
    n = int(SR * dur)
    t, dt = _phase(f, n)
    naive = np.where(t < duty, 1.0, -1.0)
    return naive + _blep(t, dt) - _blep(np.mod(t - duty + 1.0, 1.0), dt)


def triangle(f, dur: float):
    t, _ = _phase(f, int(SR * dur))
    return 4.0 * np.abs(t - 0.5) - 1.0


def sine(f, dur: float):
    t, _ = _phase(f, int(SR * dur))
    return np.sin(2 * np.pi * t)


def noise(dur: float, rate: float = SR, seed: int = 0):
    """Sample-and-hold noise; lower ``rate`` = lower, grittier pitch."""
    n = int(SR * dur)
    hold = max(1, int(SR / rate))
    vals = np.random.default_rng(seed).uniform(-1.0, 1.0, n // hold + 2)
    return np.repeat(vals, hold)[:n]


def glide(f0: float, f1: float, dur: float):
    """Exponential frequency sweep, as an array usable by any oscillator."""
    n = int(SR * dur)
    return f0 * (f1 / f0) ** np.linspace(0.0, 1.0, n)


# --------------------------------------------------------------------- envelopes

def decay(n: int, tau: float):
    return np.exp(-np.arange(n) / (tau * SR))


def adsr(n: int, a=0.004, d=0.06, s=0.7, r=0.03):
    env = np.full(n, s)
    na, nd, nr = int(a * SR), int(d * SR), min(int(r * SR), n)
    env[:na] = np.linspace(0, 1, na, endpoint=False)
    env[na:na + nd] = np.linspace(1, s, len(env[na:na + nd]), endpoint=False)
    if nr:
        env[-nr:] *= np.linspace(1, 0, nr)
    return env


def seq(*parts):
    """Concatenate signals end to end."""
    return np.concatenate([np.asarray(p, dtype=np.float64) for p in parts])


def mix(length: float, *placed):
    """``placed`` = (start_seconds, signal, gain) tuples mixed into one buffer."""
    buf = np.zeros(int(SR * length))
    for start, sig, gain in placed:
        i = int(SR * start)
        end = min(len(buf), i + len(sig))
        buf[i:end] += sig[:end - i] * gain
    return buf


def tone(note: str, dur: float, duty=0.25, vib=0.0, a=0.004, d=0.05, s=0.75, r=0.03):
    f = freq(note)
    n = int(SR * dur)
    if vib:
        t = np.arange(n) / SR
        f = f * (1 + vib * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.12) / 0.2, 0, 1))
    return pulse(f, dur, duty) * adsr(n, a, d, s, r)


def melody(notes, beat: float, duty=0.25, vib=0.004, gap=0.92):
    """[(note|None, beats)] -> signal. Notes sound for ``gap`` of their length."""
    out = []
    for note, beats in notes:
        dur = beats * beat
        if note is None:
            out.append(np.zeros(int(SR * dur)))
            continue
        sig = tone(note, dur * gap, duty, vib)
        out.append(np.concatenate([sig, np.zeros(int(SR * dur) - len(sig))]))
    return seq(*out)


# ---------------------------------------------------------------------------- SFX

def sfx_sword():
    n = noise(0.14, 9000, seed=1) * decay(int(SR * 0.14), 0.04)
    s = pulse(glide(1400, 350, 0.1), 0.1, 0.125) * decay(int(SR * 0.1), 0.03)
    return mix(0.15, (0, n, 0.5), (0, s, 0.25))


def sfx_hit():
    s = pulse(glide(900, 260, 0.09), 0.09, 0.25) * decay(int(SR * 0.09), 0.04)
    return mix(0.1, (0, s, 0.6), (0, noise(0.05, 6000, 2) * decay(int(SR * 0.05), 0.015), 0.3))


def sfx_enemy_die():
    n = noise(0.32, 4000, seed=3) * decay(int(SR * 0.32), 0.09)
    s = pulse(glide(500, 70, 0.3), 0.3, 0.5) * decay(int(SR * 0.3), 0.1)
    return mix(0.33, (0, n, 0.55), (0, s, 0.3))


def sfx_hurt():
    t = np.arange(int(SR * 0.28)) / SR
    f = glide(520, 140, 0.28) * (1 + 0.05 * np.sin(2 * np.pi * 30 * t))
    return pulse(f, 0.28, 0.5) * decay(len(t), 0.12) * 0.55


def sfx_gem():
    return seq(tone("E6", 0.05, 0.25, s=0.9), tone("A6", 0.14, 0.25, d=0.1, s=0.5, r=0.06)) * 0.45


def sfx_heart():
    return seq(*[tone(n, 0.045, 0.5, s=0.9, r=0.01) for n in ("C6", "E6", "G6")],
               tone("C7", 0.12, 0.5, s=0.5, r=0.06)) * 0.4


def sfx_key():
    return seq(*[tone(n, 0.065, 0.25, s=0.9, r=0.01) for n in ("G5", "C6", "E6", "G6")],
               tone("C7", 0.35, 0.25, vib=0.006, d=0.1, s=0.6, r=0.15)) * 0.45


def sfx_unlock():
    thunk = noise(0.1, 1500, 4) * decay(int(SR * 0.1), 0.03)
    chime = seq(tone("A5", 0.08, 0.25), tone("E6", 0.3, 0.25, d=0.1, s=0.5, r=0.15))
    return mix(0.45, (0, thunk, 0.7), (0.06, chime, 0.4))


def sfx_item_get():
    beat = 60 / 160
    lead = melody([("G4", .25), ("B4", .25), ("D5", .25), ("G5", .25), ("B5", .25), ("D6", 1.6)], beat, vib=0.006)
    harm = melody([("D4", .25), ("G4", .25), ("B4", .25), ("D5", .25), ("G5", .25), ("B5", 1.6)], beat, duty=0.5)
    bass = triangle(freq("G3"), 1.15) * adsr(int(SR * 1.15), d=0.2, s=0.6, r=0.3)
    return mix(1.2, (0, lead, 0.3), (0, harm, 0.14), (0, bass, 0.35))


def sfx_text():
    return pulse(1100, 0.022, 0.5) * decay(int(SR * 0.022), 0.012) * 0.25


def sfx_shield():
    s = pulse(glide(2700, 2100, 0.07), 0.07, 0.125) * decay(int(SR * 0.07), 0.02)
    return mix(0.08, (0, s, 0.4), (0, triangle(1300, 0.07) * decay(int(SR * 0.07), 0.025), 0.3))


def sfx_stairs():
    notes = ["C6", "B5", "A#5", "A5", "G#5", "G5", "F#5", "F5", "E5", "D#5", "D5", "C#5"]
    return seq(*[tone(n, 0.045, 0.5, s=0.9, r=0.01) for n in notes]) * 0.3


def sfx_game_over():
    beat = 60 / 96
    lead = melody([("E5", .5), ("D5", .5), ("C5", .5), ("B4", .5), ("A4", .75), ("G#4", .25), ("A4", 2.2)],
                  beat, duty=0.5, vib=0.006)
    bass = triangle(freq("A2"), len(lead) / SR) * adsr(len(lead), d=0.4, s=0.5, r=0.4)
    return mix(len(lead) / SR + 0.1, (0, lead, 0.3), (0, bass, 0.3))


def sfx_victory():
    beat = 60 / 150
    lead = melody([("G4", 1 / 3), ("C5", 1 / 3), ("E5", 1 / 3), ("G5", 1), ("E5", .5), ("G5", .5), ("C6", 2),
                   ("A5", .5), ("B5", .5), ("C6", .5), ("D6", .5), ("E6", 3.2)], beat, vib=0.006)
    harm = melody([("E4", 1 / 3), ("G4", 1 / 3), ("C5", 1 / 3), ("E5", 1), ("C5", .5), ("E5", .5), ("E5", 2),
                   ("F5", .5), ("G5", .5), ("A5", .5), ("B5", .5), ("C6", 3.2)], beat, duty=0.5)
    bass = []
    for note, beats in (("C3", 2), ("C3", 2), ("F3", 1), ("G3", 1), ("C3", 3.2)):
        d = beats * beat
        bass.append(triangle(freq(note), d) * adsr(int(SR * d), d=0.1, s=0.7, r=0.05))
    bass = seq(*bass)
    return mix(len(lead) / SR + 0.2, (0, lead, 0.28), (0, harm, 0.13), (0, bass, 0.38))


def sfx_spawn():
    return noise(0.16, 7000, 5) * np.linspace(0.0, 1.0, int(SR * 0.16)) ** 0.5 * decay(int(SR * 0.16), 0.06) * 0.35


def sfx_shoot():
    pop = noise(0.06, 3000, 6) * decay(int(SR * 0.06), 0.015)
    blip = pulse(glide(300, 160, 0.06), 0.06, 0.5) * decay(int(SR * 0.06), 0.02)
    return mix(0.07, (0, pop, 0.4), (0, blip, 0.3))


def sfx_pause():
    return seq(tone("E6", 0.05, 0.5, s=0.9, r=0.01), np.zeros(int(SR * 0.03)), tone("E6", 0.05, 0.5, s=0.9, r=0.01)) * 0.3


def sfx_start():
    return seq(*[tone(n, 0.05, 0.25, s=0.9, r=0.01) for n in ("C5", "G5", "C6")],
               tone("G6", 0.2, 0.25, d=0.08, s=0.5, r=0.1)) * 0.4


SFX = {
    "sword": sfx_sword, "hit": sfx_hit, "enemy_die": sfx_enemy_die, "hurt": sfx_hurt, "gem": sfx_gem,
    "heart": sfx_heart, "key": sfx_key, "unlock": sfx_unlock, "item_get": sfx_item_get, "text": sfx_text,
    "shield": sfx_shield, "stairs": sfx_stairs, "game_over": sfx_game_over, "victory": sfx_victory,
    "spawn": sfx_spawn, "shoot": sfx_shoot, "pause": sfx_pause, "start": sfx_start,
}


# -------------------------------------------------------------------------- music

CHORDS = {"C": ("C", "E", "G"), "G": ("G", "B", "D"), "Am": ("A", "C", "E"), "F": ("F", "A", "C"),
          "Dm": ("D", "F", "A"), "E": ("E", "G#", "B")}

OVERWORLD = [  # (chord, melody bar); every bar is 4 beats
    ("C", [("C5", .5), ("E5", .5), ("G5", 1), ("E5", .5), ("G5", .5), ("C6", 1)]),
    ("G", [("B5", 1.5), ("A5", .5), ("G5", 1), ("D5", 1)]),
    ("Am", [("C6", .5), ("B5", .5), ("A5", 1), ("E5", 1), ("A5", 1)]),
    ("F", [("G5", 1), ("F5", .5), ("E5", .5), ("F5", 1), ("A5", 1)]),
    ("C", [("G5", .5), ("E5", .5), ("C5", 1), ("E5", .5), ("G5", .5), ("C6", 1)]),
    ("G", [("D6", 1.5), ("C6", .5), ("B5", 1), ("G5", 1)]),
    ("F", [("A5", 1), ("C6", 1), ("F5", 1), ("A5", 1)]),
    ("G", [("G5", 2), ("D5", 1), (None, 1)]),
    ("Am", [("E5", 1), ("A5", 1), ("C6", 1), ("B5", .5), ("A5", .5)]),
    ("F", [("F5", 1), ("A5", 1), ("C6", 1.5), ("A5", .5)]),
    ("C", [("G5", 1), ("E5", .5), ("G5", .5), ("C6", 1), ("E6", 1)]),
    ("G", [("D6", 2), ("B5", 1), ("G5", 1)]),
    ("Am", [("A5", .5), ("B5", .5), ("C6", 1), ("E6", 1), ("D6", .5), ("C6", .5)]),
    ("F", [("C6", 1), ("A5", 1), ("F5", 1), ("A5", 1)]),
    ("G", [("B5", 1), ("D6", 1), ("G6", 1), ("F6", .5), ("D6", .5)]),
    ("G", [("G5", 2), ("B5", .5), ("D6", .5), (None, 1)]),
]

CAVE = [
    ("Am", [("E5", 3), ("D5", 1)]),
    ("Am", [("C5", 2), ("B4", 2)]),
    ("F", [("A4", 3), ("C5", 1)]),
    ("F", [("F5", 4)]),
    ("Dm", [("D5", 3), ("F5", 1)]),
    ("Dm", [("A5", 2), ("G5", 2)]),
    ("E", [("E5", 2), ("G#5", 2)]),
    ("E", [("B5", 4)]),
]


def _drum_kick():
    n = int(SR * 0.13)
    return sine(glide(160, 45, 0.13), 0.13) * decay(n, 0.05)


def _drum_snare(seed):
    n = int(SR * 0.12)
    return noise(0.12, 9000, seed) * decay(n, 0.04) * 0.8 + pulse(190, 0.12, 0.5) * decay(n, 0.02) * 0.2


def _drum_hat(seed):
    n = int(SR * 0.035)
    s = noise(0.035, SR, seed)
    return np.diff(s, prepend=0.0) * 0.5 * decay(n, 0.01)


def render_song(bars, bpm: float, *, lead_duty=0.25, arp=True, drums=True, arp_wave="pulse",
                arp_octave=5, bass_octave=3, gains=None) -> np.ndarray:
    g = {"lead": 0.2, "arp": 0.05, "bass": 0.3, "kick": 0.45, "snare": 0.18, "hat": 0.09, **(gains or {})}
    beat = 60.0 / bpm
    total = 4 * len(bars) * beat
    n = round(total * SR)
    buf = np.zeros(n + 2 * SR)

    def put(t, sig, gain):
        i = round(t * SR)
        buf[i:i + len(sig)] += sig * gain

    put(0, melody([note for _, bar in bars for note in bar], beat, duty=lead_duty), g["lead"])
    for b, (chord, _) in enumerate(bars):
        t0 = b * 4 * beat
        root = CHORDS[chord][0]
        for k in range(8):  # bass: octave bounce on eighths
            octave = bass_octave + (k % 2)
            d = beat / 2
            put(t0 + k * d, triangle(freq(f"{root}{octave}"), d * 0.9) * adsr(int(SR * d * 0.9), d=0.05, s=0.8), g["bass"])
        if arp:
            tones = CHORDS[chord]
            for k in range(16):  # sixteenth-note arpeggio
                note = f"{tones[k % 3]}{arp_octave}"
                d = beat / 4
                osc = pulse(freq(note), d * 0.8, 0.5) if arp_wave == "pulse" else triangle(freq(note), d * 0.8)
                put(t0 + k * d, osc * adsr(int(SR * d * 0.8), d=0.02, s=0.6, r=0.01), g["arp"])
        if drums:
            for k in range(8):
                t = t0 + k * beat / 2
                put(t, _drum_hat(1000 + b * 8 + k), g["hat"])
                if k in (0, 4):
                    put(t, _drum_kick(), g["kick"])
                if k in (2, 6):
                    put(t, _drum_snare(b * 8 + k), g["snare"])
    tail = buf[n:]
    buf[:len(tail)] += tail          # fold release tails into the loop start: seamless loop
    return buf[:n]


def music_overworld():
    return render_song(OVERWORLD, 132)


def music_cave():
    return render_song(CAVE, 84, lead_duty=0.125, drums=False, arp_wave="triangle", arp_octave=4,
                       bass_octave=2, gains={"lead": 0.16, "arp": 0.16, "bass": 0.32})


MUSIC = {"overworld": music_overworld, "cave": music_cave}


# ---------------------------------------------------------------------------- WAV

def write_wav(path, signal: np.ndarray, peak: float = 0.8, loop: bool = False) -> None:
    m = np.max(np.abs(signal)) or 1.0
    signal = signal / m * peak
    if not loop:  # de-click one-shots: 1 ms fade in, 6 ms fade out
        fi, fo = min(int(SR * 0.001), len(signal)), min(int(SR * 0.006), len(signal))
        signal = signal.copy()
        signal[:fi] *= np.linspace(0, 1, fi)
        signal[-fo:] *= np.linspace(1, 0, fo)
    pcm = (np.clip(signal, -1.0, 1.0) * 32767).astype("<i2").tobytes()
    chunks = b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16)
    chunks += b"data" + struct.pack("<I", len(pcm)) + pcm
    if loop:
        frames = len(pcm) // 2
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)  # forward loop over the whole file
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
