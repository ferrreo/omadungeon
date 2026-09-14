#!/usr/bin/env python3
"""Generates three short chiptune loops (16-bit mono 22050 Hz WAV) into assets/music/fallback/.

They play when no Omarchy Radio tracks are present (or all are filtered out). Pure Python,
deterministic. Each loop is an exact number of bars so it can loop seamlessly:
  arpeggio_run.wav  140 BPM  square arpeggios, triangle bass, noise drums
  bass_crawl.wav    100 BPM  saw bass with low-pass, sparse square lead
  drum_cave.wav     120 BPM  drum-led, pulse stabs

Usage: tools/gen-music.py [out_dir]    (default assets/music/fallback)
"""
import math
import os
import random
import struct
import sys
import wave

SR = 22050
PEAK = 10 ** (-3.0 / 20.0)


def midi(n):
    """MIDI note number to Hz."""
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


class Song:
    """Accumulates voices into one float buffer of a fixed bar count."""

    def __init__(self, bpm, bars, beats_per_bar=4, seed=7):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.length = bars * beats_per_bar * self.beat
        self.n = int(self.length * SR)
        self.buf = [0.0] * self.n
        self.rng = random.Random(seed)

    def tone(self, wave_type, freq, start, dur, vol=0.3, decay=0.0, duty=0.5, lpf=0.0, slide=0.0):
        """Adds one note. decay: seconds of exponential tail inside dur; lpf: one-pole cutoff."""
        i0 = int(start * SR)
        count = int(dur * SR)
        phase = 0.0
        lp = 0.0
        dt = 1.0 / SR
        a = 1.0 - math.exp(-2.0 * math.pi * lpf * dt) if lpf > 0 else 1.0
        f = freq
        for i in range(count):
            t = i * dt
            f *= 2.0 ** (slide * dt)
            phase += f * dt
            if phase >= 1.0:
                phase -= 1.0
            if wave_type == "square":
                s = 1.0 if phase < duty else -1.0
            elif wave_type == "saw":
                s = 2.0 * phase - 1.0
            elif wave_type == "tri":
                s = 4.0 * abs(phase - 0.5) - 1.0
            else:
                s = math.sin(2 * math.pi * phase)
            env = 1.0
            if decay > 0:
                env = math.exp(-t / decay)
            # Short attack/release to avoid clicks.
            edge = 0.003
            if t < edge:
                env *= t / edge
            rem = dur - t
            if rem < edge:
                env *= max(0.0, rem / edge)
            if lpf > 0:
                lp += a * (s - lp)
                s = lp
            idx = i0 + i
            if idx < self.n:
                self.buf[idx] += s * env * vol
            else:
                self.buf[idx - self.n] += s * env * vol  # wrap tails so the loop stays seamless

    def kick(self, start, vol=0.5):
        i0 = int(start * SR)
        dur = 0.18
        count = int(dur * SR)
        phase = 0.0
        dt = 1.0 / SR
        for i in range(count):
            t = i * dt
            f = 45.0 + 110.0 * math.exp(-t * 40.0)
            phase += f * dt
            env = math.exp(-t * 18.0)
            s = math.sin(2 * math.pi * phase) * env * vol
            idx = (i0 + i) % self.n
            self.buf[idx] += s

    def snare(self, start, vol=0.35):
        i0 = int(start * SR)
        dur = 0.14
        count = int(dur * SR)
        lp = 0.0
        dt = 1.0 / SR
        a = 1.0 - math.exp(-2.0 * math.pi * 3500.0 * dt)
        phase = 0.0
        for i in range(count):
            t = i * dt
            noise = self.rng.uniform(-1, 1)
            lp += a * (noise - lp)
            phase += 190.0 * dt
            body = math.sin(2 * math.pi * phase) * math.exp(-t * 40.0)
            env = math.exp(-t * 22.0)
            idx = (i0 + i) % self.n
            self.buf[idx] += (lp * env + body * 0.5) * vol

    def hat(self, start, vol=0.12, dur=0.04):
        i0 = int(start * SR)
        count = int(dur * SR)
        prev = 0.0
        dt = 1.0 / SR
        for i in range(count):
            t = i * dt
            noise = self.rng.uniform(-1, 1)
            s = noise - prev  # crude high-pass
            prev = noise
            env = math.exp(-t * 90.0)
            idx = (i0 + i) % self.n
            self.buf[idx] += s * env * vol

    def write(self, path):
        peak = max(abs(s) for s in self.buf) or 1.0
        gain = PEAK / peak
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            frames = bytearray()
            for s in self.buf:
                frames += struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767))
            w.writeframes(bytes(frames))


def arpeggio_run():
    """140 BPM, 12 bars: Am F C G progression, 16th-note square arps."""
    s = Song(140, 12, seed=11)
    b = s.beat
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]  # Am F C G
    for bar in range(12):
        root, third, fifth = chords[bar % 4]
        t0 = bar * 4 * b
        pattern = [root + 12, third + 12, fifth + 12, root + 24, fifth + 12, third + 12]
        step = b / 4
        for k in range(16):
            n = pattern[k % len(pattern)]
            if bar >= 8 and k % 4 == 3:
                n += 2 if bar % 2 == 0 else -1
            s.tone("square", midi(n), t0 + k * step, step * 0.9, vol=0.16, decay=0.12, duty=0.25)
        for k in range(8):
            n = root - 12 if k % 2 == 0 else root - 5
            s.tone("tri", midi(n), t0 + k * b / 2, b / 2 * 0.95, vol=0.32, decay=0.5)
        for beat in range(4):
            s.kick(t0 + beat * b)
            if beat % 2 == 1:
                s.snare(t0 + beat * b)
            for h in range(2):
                s.hat(t0 + beat * b + h * b / 2, vol=0.10 if h == 0 else 0.06)
        if bar % 4 == 3:
            s.snare(t0 + 3.5 * b, vol=0.25)
    return s


def bass_crawl():
    """100 BPM, 10 bars: brooding E minor saw bass with a sparse square lead."""
    s = Song(100, 10, seed=23)
    b = s.beat
    roots = [40, 40, 43, 38, 40, 40, 36, 38, 40, 43]  # E E G D E E C D E G
    lead_notes = [64, 67, 71, 69, 67, 64, 62, 59]
    for bar in range(10):
        root = roots[bar]
        t0 = bar * 4 * b
        for k in range(8):
            n = root if k in (0, 3, 6) else root + 7 if k in (2, 5) else root + 3
            s.tone("saw", midi(n), t0 + k * b / 2, b / 2 * 0.8, vol=0.30, decay=0.35, lpf=650.0)
        for k in range(16):
            s.tone("square", midi(root + 24), t0 + k * b / 4, b / 8, vol=0.05, decay=0.05, duty=0.15)
        if bar >= 2:
            n = lead_notes[(bar * 2) % len(lead_notes)]
            s.tone("square", midi(n), t0 + b, b * 1.5, vol=0.11, decay=1.2, duty=0.5)
            n2 = lead_notes[(bar * 2 + 1) % len(lead_notes)]
            s.tone("square", midi(n2), t0 + 3 * b, b * 0.9, vol=0.10, decay=0.8, duty=0.5)
        for beat in range(4):
            if beat in (0, 2):
                s.kick(t0 + beat * b, vol=0.55)
            if beat in (1, 3):
                s.snare(t0 + beat * b, vol=0.3)
            s.hat(t0 + beat * b + b / 2, vol=0.07, dur=0.06)
        if bar % 2 == 1:
            s.kick(t0 + 2.5 * b, vol=0.4)
    return s


def drum_cave():
    """120 BPM, 12 bars: drum-led groove with pulse stabs in D minor."""
    s = Song(120, 12, seed=37)
    b = s.beat
    stabs = [(50, 53, 57), (48, 53, 57), (46, 50, 53), (45, 48, 52)]  # Dm Bb Gm A
    for bar in range(12):
        t0 = bar * 4 * b
        chord = stabs[(bar // 2) % 4]
        for beat in range(4):
            s.kick(t0 + beat * b, vol=0.6)
            if beat in (1, 3):
                s.snare(t0 + beat * b, vol=0.38)
            for h in range(4):
                s.hat(t0 + beat * b + h * b / 4, vol=0.11 if h == 0 else 0.05, dur=0.03)
        if bar % 4 == 3:
            for k in range(4):
                s.snare(t0 + 3 * b + k * b / 4, vol=0.2 + 0.05 * k)
        s.kick(t0 + 2.75 * b, vol=0.35)
        for hit in (0.0, 1.5, 2.5):
            for n in chord:
                s.tone("square", midi(n + 12), t0 + hit * b, b * 0.35, vol=0.09, decay=0.15, duty=0.3)
        root = chord[0]
        for k in range(8):
            n = root - 12 if k % 4 != 3 else root - 5
            s.tone("tri", midi(n), t0 + k * b / 2, b / 2 * 0.9, vol=0.28, decay=0.4)
        if bar >= 4 and bar % 2 == 0:
            s.tone("saw", midi(root + 24), t0 + 3.5 * b, b / 2, vol=0.07, decay=0.3, lpf=2500.0, slide=-1.0)
    return s


def main(argv):
    out_dir = argv[1] if len(argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "assets", "music", "fallback"
    )
    os.makedirs(out_dir, exist_ok=True)
    for name, builder in (("arpeggio_run", arpeggio_run), ("bass_crawl", bass_crawl), ("drum_cave", drum_cave)):
        song = builder()
        path = os.path.join(out_dir, name + ".wav")
        song.write(path)
        print("%-14s %3d BPM %5.1f s" % (name, song.bpm, song.length))
    print("wrote 3 loops to %s" % os.path.abspath(out_dir))


if __name__ == "__main__":
    main(sys.argv)
