#!/usr/bin/env python3
"""Procedural sound-effect generator for Omadungeon (jsfxr-style, pure Python).

Writes one 16-bit mono 22050 Hz WAV per sound id into assets/sfx/. Each sound is a
list of layers; a layer is an oscillator (square / saw / sine / tri / noise) with an
ADSR-ish envelope, pitch slides, vibrato, arpeggio, retrigger and a one-pole low-pass
plus high-pass. Layers can start at an offset so short note sequences are possible.
Output is normalised to -3 dBFS with 2 ms fades. Deterministic (fixed seed per id).

Usage: tools/gen-sfx.py [out_dir]    (default assets/sfx)
"""
import math
import os
import random
import struct
import sys
import wave
import zlib

SR = 22050
PEAK = 10 ** (-3.0 / 20.0)  # -3 dBFS
FADE_SAMPLES = int(SR * 0.002)

try:
    import numpy as np  # noqa: F401  (optional; not required)
except Exception:  # pragma: no cover - numpy is optional
    np = None


def layer(
    wave_type="square",
    freq=440.0,
    slide=0.0,
    dslide=0.0,
    freq_min=20.0,
    attack=0.0,
    sustain=0.1,
    punch=0.0,
    decay=0.1,
    duty=0.5,
    duty_sweep=0.0,
    vib_depth=0.0,
    vib_speed=0.0,
    arp_mod=1.0,
    arp_time=0.0,
    repeat=0.0,
    lpf=0.0,
    lpf_sweep=0.0,
    hpf=0.0,
    volume=1.0,
    start=0.0,
):
    """Returns a layer parameter dict (slides are octaves per second)."""
    return dict(
        wave_type=wave_type,
        freq=freq,
        slide=slide,
        dslide=dslide,
        freq_min=freq_min,
        attack=attack,
        sustain=sustain,
        punch=punch,
        decay=decay,
        duty=duty,
        duty_sweep=duty_sweep,
        vib_depth=vib_depth,
        vib_speed=vib_speed,
        arp_mod=arp_mod,
        arp_time=arp_time,
        repeat=repeat,
        lpf=lpf,
        lpf_sweep=lpf_sweep,
        hpf=hpf,
        volume=volume,
        start=start,
    )


def render_layer(p, rng):
    """Renders one layer to a list of floats."""
    attack, sustain, decay = p["attack"], p["sustain"], p["decay"]
    total = attack + sustain + decay
    n = int(total * SR)
    out = [0.0] * n
    if n == 0:
        return out
    freq = p["freq"]
    slide = p["slide"]
    phase = 0.0
    duty = p["duty"]
    lp_state = 0.0
    hp_state_in = 0.0
    hp_state_out = 0.0
    noise_val = rng.uniform(-1, 1)
    noise_acc = 0.0
    last_repeat = 0.0
    arp_done = False
    dt = 1.0 / SR
    lpf = p["lpf"]
    for i in range(n):
        t = i * dt
        # Retrigger (jsfxr "repeat speed").
        if p["repeat"] > 0 and t - last_repeat >= p["repeat"]:
            last_repeat = t
            freq = p["freq"]
            slide = p["slide"]
            arp_done = False
        # Pitch slides (octaves per second).
        slide += p["dslide"] * dt
        freq *= 2.0 ** (slide * dt)
        if p["arp_time"] > 0 and not arp_done and t - last_repeat >= p["arp_time"]:
            freq *= p["arp_mod"]
            arp_done = True
        if freq < p["freq_min"]:
            break
        f = freq
        if p["vib_depth"] > 0:
            f *= 1.0 + p["vib_depth"] * math.sin(2 * math.pi * p["vib_speed"] * t)
        # Envelope.
        if t < attack:
            env = t / attack if attack > 0 else 1.0
        elif t < attack + sustain:
            k = (t - attack) / sustain if sustain > 0 else 1.0
            env = 1.0 + p["punch"] * (1.0 - k)
        else:
            k = (t - attack - sustain) / decay if decay > 0 else 1.0
            env = max(0.0, 1.0 - k)
        # Oscillator.
        wt = p["wave_type"]
        if wt == "noise":
            noise_acc += f * 8.0 * dt
            if noise_acc >= 1.0:
                noise_acc -= 1.0
                noise_val = rng.uniform(-1, 1)
            s = noise_val
        else:
            phase += f * dt
            if phase >= 1.0:
                phase -= 1.0
            if wt == "square":
                duty = min(0.95, max(0.05, duty + p["duty_sweep"] * dt))
                s = 1.0 if phase < duty else -1.0
            elif wt == "saw":
                s = 2.0 * phase - 1.0
            elif wt == "tri":
                s = 4.0 * abs(phase - 0.5) - 1.0
            else:
                s = math.sin(2 * math.pi * phase)
        s *= env
        # One-pole low-pass with optional sweep (octaves per second).
        if lpf > 0:
            lpf *= 2.0 ** (p["lpf_sweep"] * dt)
            lpf = min(lpf, SR * 0.45)
            a = 1.0 - math.exp(-2.0 * math.pi * lpf * dt)
            lp_state += a * (s - lp_state)
            s = lp_state
        # One-pole high-pass.
        if p["hpf"] > 0:
            rc = 1.0 / (2.0 * math.pi * p["hpf"])
            a = rc / (rc + dt)
            hp_state_out = a * (hp_state_out + s - hp_state_in)
            hp_state_in = s
            s = hp_state_out
        out[i] = s * p["volume"]
    return out


def render_sound(layers, seed):
    """Mixes layers, normalises to -3 dBFS and applies fades. Returns float samples."""
    rng = random.Random(seed)
    rendered = []
    length = 0
    for p in layers:
        samples = render_layer(p, rng)
        offset = int(p["start"] * SR)
        rendered.append((offset, samples))
        length = max(length, offset + len(samples))
    mix = [0.0] * length
    for offset, samples in rendered:
        for i, s in enumerate(samples):
            mix[offset + i] += s
    fade = min(FADE_SAMPLES, len(mix) // 2)
    for i in range(fade):
        k = i / fade
        mix[i] *= k
        mix[len(mix) - 1 - i] *= k
    peak = max((abs(s) for s in mix), default=0.0)
    if peak > 0:
        gain = PEAK / peak
        mix = [s * gain for s in mix]
    return mix


def write_wav(path, samples):
    """Writes 16-bit mono PCM."""
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


def note(freq, start, dur, wave_type="square", volume=0.8, **kw):
    """Convenience: a short plucked note at an offset."""
    return layer(
        wave_type=wave_type,
        freq=freq,
        sustain=dur * 0.4,
        decay=dur * 0.6,
        volume=volume,
        start=start,
        **kw,
    )


N = {  # a few named pitches (Hz)
    "C4": 261.6, "E4": 329.6, "G4": 392.0, "A4": 440.0, "B4": 493.9,
    "C5": 523.3, "D5": 587.3, "E5": 659.3, "G5": 784.0, "A5": 880.0,
    "C6": 1046.5, "E6": 1318.5, "G6": 1568.0,
}

SOUNDS = {
    "ui_move": [layer("square", N["A5"], sustain=0.02, decay=0.05, duty=0.3, volume=0.6, lpf=6000)],
    "ui_accept": [
        note(N["E5"], 0.0, 0.08, duty=0.4),
        note(N["A5"], 0.06, 0.14, duty=0.4),
    ],
    "ui_back": [
        note(N["E5"], 0.0, 0.08, duty=0.4),
        note(N["A4"], 0.06, 0.14, duty=0.4),
    ],
    "hit_melee": [
        layer("noise", 900, slide=-6, sustain=0.03, decay=0.09, lpf=3500, lpf_sweep=-10),
        layer("saw", 220, slide=-8, sustain=0.02, punch=0.5, decay=0.1, lpf=1500, volume=0.7),
    ],
    "hit_ranged": [
        layer("tri", 700, slide=-12, sustain=0.02, decay=0.07, volume=0.8),
        layer("noise", 2000, slide=-8, sustain=0.01, decay=0.06, hpf=800, volume=0.5),
    ],
    "shoot_bow": [
        layer("noise", 3000, slide=-4, attack=0.01, sustain=0.04, decay=0.12, hpf=1200, volume=0.7),
        layer("sine", 1100, slide=-10, sustain=0.02, decay=0.08, volume=0.6),
    ],
    "shoot_wand": [
        layer("square", 1400, slide=-3, sustain=0.05, decay=0.15, duty=0.25, vib_depth=0.04, vib_speed=30, arp_mod=0.75, arp_time=0.06, lpf=5000),
    ],
    "dodge": [
        layer("noise", 1200, slide=3, attack=0.02, sustain=0.06, decay=0.12, lpf=900, lpf_sweep=8, hpf=200),
    ],
    "potion": [
        layer("sine", 380, slide=4, sustain=0.03, decay=0.03, repeat=0.07, attack=0.0, volume=0.8, punch=0.3),
        layer("sine", 560, slide=6, sustain=0.03, decay=0.04, repeat=0.09, start=0.03, volume=0.6),
        layer("tri", 700, slide=2, sustain=0.05, decay=0.2, start=0.2, volume=0.5),
    ],
    "stat_up": [
        note(N["C5"], 0.0, 0.1, duty=0.35),
        note(N["E5"], 0.09, 0.1, duty=0.35),
        note(N["G5"], 0.18, 0.28, duty=0.35, vib_depth=0.01, vib_speed=8),
    ],
    "ability_cast": [
        layer("saw", 240, slide=5, attack=0.01, sustain=0.12, decay=0.15, vib_depth=0.03, vib_speed=18, lpf=2500, lpf_sweep=4, volume=0.8),
        layer("noise", 2500, slide=2, attack=0.05, sustain=0.05, decay=0.15, hpf=2000, volume=0.3),
    ],
    "trap_spike": [
        layer("square", 2200, slide=-14, sustain=0.02, decay=0.08, duty=0.2, volume=0.7),
        layer("noise", 4000, slide=-6, sustain=0.01, decay=0.09, hpf=1500, volume=0.6),
    ],
    "trap_fire": [
        layer("noise", 600, sustain=0.15, decay=0.25, attack=0.02, lpf=900, volume=0.8),
        layer("noise", 3000, sustain=0.02, decay=0.02, repeat=0.045, hpf=2500, volume=0.35),
    ],
    "explosion": [
        layer("noise", 800, slide=-2, attack=0.005, sustain=0.1, punch=0.6, decay=0.5, lpf=4000, lpf_sweep=-6),
        layer("sine", 90, slide=-3, sustain=0.05, punch=0.8, decay=0.3, volume=0.9),
    ],
    "door_close": [
        layer("sine", 110, slide=-4, sustain=0.03, punch=0.6, decay=0.18, volume=0.9),
        layer("noise", 500, slide=-4, sustain=0.02, decay=0.12, lpf=1200, volume=0.6),
        layer("square", 160, slide=-1, sustain=0.01, decay=0.05, start=0.02, lpf=600, volume=0.3),
    ],
    "door_open": [
        layer("saw", 180, slide=1.2, attack=0.02, sustain=0.15, decay=0.12, vib_depth=0.02, vib_speed=25, lpf=700, volume=0.6),
        layer("noise", 800, slide=3, attack=0.02, sustain=0.1, decay=0.15, lpf=500, lpf_sweep=6, volume=0.6),
    ],
    "chest_open": [
        layer("saw", 150, slide=1.5, attack=0.01, sustain=0.08, decay=0.06, lpf=600, volume=0.4),
        note(N["C5"], 0.08, 0.1, "tri"),
        note(N["E5"], 0.16, 0.1, "tri"),
        note(N["G5"], 0.24, 0.1, "tri"),
        note(N["C6"], 0.32, 0.3, "tri", vib_depth=0.01, vib_speed=7),
    ],
    "coin": [
        layer("square", 1320, sustain=0.05, decay=0.01, duty=0.5, volume=0.7),
        layer("square", 1760, sustain=0.08, decay=0.2, duty=0.5, start=0.05, volume=0.7),
    ],
    "level_up": [
        note(N["C5"], 0.0, 0.11),
        note(N["E5"], 0.1, 0.11),
        note(N["G5"], 0.2, 0.11),
        note(N["C6"], 0.3, 0.11),
        note(N["E6"], 0.4, 0.35, vib_depth=0.012, vib_speed=7),
        note(N["G6"], 0.4, 0.35, volume=0.4),
    ],
    "boss_roar": [
        layer("saw", 95, slide=-0.8, attack=0.05, sustain=0.35, decay=0.4, vib_depth=0.06, vib_speed=9, lpf=500, volume=0.9),
        layer("square", 70, slide=-0.6, attack=0.05, sustain=0.35, decay=0.4, duty=0.3, lpf=350, volume=0.5),
        layer("noise", 400, attack=0.1, sustain=0.3, decay=0.4, lpf=700, volume=0.35),
    ],
    "honk": [
        layer("square", 370, attack=0.01, sustain=0.12, decay=0.05, duty=0.3, vib_depth=0.02, vib_speed=12, lpf=2500, volume=0.8),
        layer("square", 290, attack=0.01, sustain=0.14, decay=0.1, duty=0.3, vib_depth=0.02, vib_speed=12, lpf=2200, start=0.15, volume=0.8),
    ],
    "clown_pop": [
        layer("sine", 700, slide=-16, sustain=0.01, punch=0.8, decay=0.06, volume=0.9),
        layer("noise", 3000, sustain=0.005, decay=0.03, hpf=1000, volume=0.6),
    ],
    "tome_thud": [
        layer("sine", 75, slide=-2, sustain=0.04, punch=0.7, decay=0.22, volume=0.9),
        layer("noise", 300, slide=-3, sustain=0.02, decay=0.1, lpf=350, volume=0.7),
    ],
    "teleport": [
        layer("sine", 300, slide=4, attack=0.02, sustain=0.2, decay=0.2, vib_depth=0.05, vib_speed=22, volume=0.8),
        layer("square", 600, slide=4, attack=0.05, sustain=0.15, decay=0.2, duty=0.2, lpf=3000, start=0.05, volume=0.35),
    ],
    "freeze": [
        layer("sine", 2600, slide=-1.5, attack=0.01, sustain=0.15, decay=0.3, vib_depth=0.01, vib_speed=14, volume=0.7),
        layer("noise", 6000, attack=0.02, sustain=0.05, decay=0.3, hpf=4000, volume=0.4),
        layer("tri", 1300, slide=-1, sustain=0.05, decay=0.2, start=0.08, volume=0.4),
    ],
    "burn": [
        layer("noise", 700, attack=0.03, sustain=0.12, decay=0.2, lpf=1400, lpf_sweep=-3, volume=0.8),
        layer("noise", 2500, sustain=0.015, decay=0.02, repeat=0.06, hpf=1800, volume=0.4),
        layer("saw", 120, slide=-2, sustain=0.05, decay=0.15, lpf=300, volume=0.4),
    ],
    "shock": [
        layer("square", 1900, slide=-6, sustain=0.01, decay=0.02, repeat=0.025, duty=0.15, volume=0.6),
        layer("noise", 5000, sustain=0.008, decay=0.02, repeat=0.03, hpf=2500, volume=0.5),
        layer("saw", 90, sustain=0.05, decay=0.15, lpf=400, volume=0.4),
    ],
    "hurt": [
        layer("saw", 240, slide=-9, sustain=0.03, punch=0.4, decay=0.14, lpf=2200, volume=0.9),
        layer("noise", 1500, slide=-8, sustain=0.01, decay=0.08, lpf=2500, volume=0.5),
    ],
    "heal": [
        note(N["E5"], 0.0, 0.14, "sine", vib_depth=0.01, vib_speed=6),
        note(N["G5"], 0.1, 0.14, "sine", vib_depth=0.01, vib_speed=6),
        note(N["C6"], 0.2, 0.3, "sine", vib_depth=0.015, vib_speed=6),
        layer("tri", 1300, slide=1, attack=0.05, sustain=0.1, decay=0.2, start=0.15, volume=0.25),
    ],
    "death": [
        layer("saw", 320, slide=-5, dslide=-4, attack=0.01, sustain=0.15, decay=0.4, vib_depth=0.03, vib_speed=10, lpf=1800, volume=0.9),
        layer("noise", 800, slide=-3, attack=0.05, sustain=0.1, decay=0.4, lpf=1000, volume=0.5),
    ],
    "room_clear": [
        note(N["G4"], 0.0, 0.12, duty=0.4),
        note(N["C5"], 0.11, 0.12, duty=0.4),
        note(N["E5"], 0.22, 0.12, duty=0.4),
        note(N["G5"], 0.33, 0.4, duty=0.4, vib_depth=0.012, vib_speed=7),
        note(N["C6"], 0.33, 0.4, duty=0.4, volume=0.45),
        note(N["E6"], 0.44, 0.35, "tri", volume=0.35),
    ],
    "equip": [
        layer("noise", 2500, sustain=0.008, decay=0.03, hpf=1200, volume=0.7),
        layer("tri", 760, slide=2, sustain=0.03, decay=0.09, start=0.02, volume=0.7),
        layer("tri", 1140, sustain=0.02, decay=0.07, start=0.06, volume=0.4),
    ],
    "laser": [
        layer("saw", 1600, slide=-10, sustain=0.2, decay=0.08, repeat=0.05, lpf=6000, volume=0.8),
        layer("square", 800, slide=-10, sustain=0.2, decay=0.08, repeat=0.05, duty=0.3, start=0.01, volume=0.4),
    ],
    "pit_fall": [
        layer("sine", 900, slide=-2.5, attack=0.02, sustain=0.3, decay=0.35, vib_depth=0.05, vib_speed=8, volume=0.9),
        layer("noise", 1500, slide=-3, attack=0.05, sustain=0.25, decay=0.3, lpf=2000, lpf_sweep=-3, volume=0.25),
    ],
    "shield": [
        layer("sine", 330, slide=3, attack=0.005, sustain=0.06, decay=0.2, volume=0.8),
        layer("tri", 990, slide=1, sustain=0.04, decay=0.18, start=0.01, volume=0.4),
        layer("sine", 1650, sustain=0.03, decay=0.15, start=0.02, volume=0.25),
        layer("noise", 3000, sustain=0.005, decay=0.03, hpf=2000, volume=0.4),
    ],
}


def main(argv):
    out_dir = argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
    os.makedirs(out_dir, exist_ok=True)
    for sid, layers in sorted(SOUNDS.items()):
        # Seed from the id, not the position, so adding or reordering a sound never
        # re-renders the others (each WAV depends only on its own name and parameters).
        samples = render_sound(layers, seed=zlib.crc32(sid.encode("utf-8")))
        path = os.path.join(out_dir, sid + ".wav")
        write_wav(path, samples)
        print("%-14s %5d ms" % (sid, int(1000 * len(samples) / SR)))
    print("wrote %d sounds to %s" % (len(SOUNDS), os.path.abspath(out_dir)))


if __name__ == "__main__":
    main(sys.argv)
