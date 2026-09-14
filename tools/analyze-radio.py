#!/usr/bin/env python3
"""Measures every bundled radio track and writes data/music/track_moods.json.

Why this exists: the in-game analyser reads the spectrum of what is *playing*, which is
nothing under the headless Dummy audio driver and, live, a relative number ("louder than this
track usually is") that says nothing about which track it is. The mood of a track - is it a
loud fast bright one or a quiet slow dark one - is a property of the file, so it is measured
here once, offline, and shipped as data. `MusicMood` (src/music/music_mood.gd) reads the table
by file name; a track that is not in it (a fallback loop, a custom stream) gets a neutral
mood derived from its title hash, so nothing depends on the table being complete.

Per track, from a 16 kHz mono decode:
  loudness_db   RMS of the whole track in dBFS.
  brightness_db RMS above 2 kHz (one-pole high-pass) minus the full-band RMS, in dB: how much
                of the energy is treble. -6 dB is bright, -20 dB is dark.
  onset_rate    onsets per second in the 10 ms envelope (a rise of more than 4 dB over the
                previous 100 ms, 120 ms refractory): how busy the track is.
  tempo_bpm     autocorrelation peak of the onset strength over 60-200 BPM, folded to 70-180.
  live_quiet/   the 10th, 50th and 90th percentile of the track's *own* live energy series -
  live_mid/     what `MusicManager._push_energy` would report while this track plays, mirrored
  live_loud     here from the same two exponential means over the same windows. This is what
                the game means by "what is happening over the current track": 0.5 is as loud as
                this track usually is, under it a breakdown, over it a drop.
  quiet_at/     seconds into the track at which the quietest and loudest sustained passages sit,
  loud_at       so a capture can photograph the room at a real moment of a real track rather
                than at a number somebody picked.
Then, across the set, `energy` and `brightness` are rank-normalised to 0..1 so the calmest
bundled track reads 0 and the loudest 1 whatever the mastering did. energy ranks the sum of
the loudness z-score and half the onset-rate z-score; brightness ranks brightness_db.

Deterministic; requires ffmpeg. Usage: tools/analyze-radio.py [assets/music/radio/playlist.json]
"""
import array
import json
import math
import os
import subprocess
import sys

RATE = 16000
FRAME = RATE // 100  # 10 ms
HIGHPASS_HZ = 2000.0
ONSET_DB = 4.0
ONSET_LOOKBACK = 10  # frames (100 ms)
ONSET_REFRACTORY = 12  # frames (120 ms)


def decode(path):
    """Mono 16 kHz signed 16-bit PCM as an array of ints."""
    raw = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE),
            "-f", "s16le", "-acodec", "pcm_s16le", "-",
        ],
        check=True, capture_output=True,
    ).stdout
    samples = array.array("h")
    samples.frombytes(raw[: len(raw) - len(raw) % 2])
    return samples


def rms_db(values):
    if not values:
        return -120.0
    acc = 0.0
    for v in values:
        acc += v * v
    return 10.0 * math.log10(max(acc / len(values), 1e-12) / (32768.0 * 32768.0))


def highpass(samples):
    rc = 1.0 / (2.0 * math.pi * HIGHPASS_HZ)
    dt = 1.0 / RATE
    a = rc / (rc + dt)
    out = array.array("d", [0.0]) * len(samples)
    prev_x = 0.0
    prev_y = 0.0
    for i, x in enumerate(samples):
        y = a * (prev_y + x - prev_x)
        out[i] = y
        prev_x = x
        prev_y = y
    return out


def envelope_db(samples):
    """RMS per 10 ms frame, in dB."""
    out = []
    for start in range(0, len(samples) - FRAME, FRAME):
        acc = 0.0
        for v in samples[start:start + FRAME]:
            acc += v * v
        out.append(10.0 * math.log10(max(acc / FRAME, 1e-12) / (32768.0 * 32768.0)))
    return out


def onsets(env):
    """Onset strength per frame (dB rise over the last 100 ms, clipped at 0) and onset count."""
    strength = [0.0] * len(env)
    count = 0
    last = -ONSET_REFRACTORY
    for i in range(ONSET_LOOKBACK, len(env)):
        rise = env[i] - max(env[i - ONSET_LOOKBACK:i])
        strength[i] = max(rise, 0.0)
        if rise > ONSET_DB and i - last >= ONSET_REFRACTORY and env[i] > -50.0:
            count += 1
            last = i
    return strength, count


def tempo(strength):
    """Autocorrelation peak over 60..200 BPM, preferring 70..180 by folding."""
    n = len(strength)
    mean = sum(strength) / max(n, 1)
    centred = [s - mean for s in strength]
    best_lag = 0
    best = -1.0
    for lag in range(30, 101):  # 100 frames = 1 s = 60 BPM; 30 frames = 200 BPM
        acc = 0.0
        for i in range(lag, n):
            acc += centred[i] * centred[i - lag]
        # Mild bias toward the middle of the range so half/double time does not win by noise.
        bpm = 6000.0 / lag
        weight = 1.0 - 0.15 * abs(math.log2(bpm / 120.0))
        score = acc * weight
        if score > best:
            best = score
            best_lag = lag
    if best_lag == 0 or best <= 0.0:
        return 0.0
    bpm = 6000.0 / best_lag
    while bpm < 70.0:
        bpm *= 2.0
    while bpm > 180.0:
        bpm /= 2.0
    return round(bpm, 1)


def live_energy(samples, interval=0.05, short_window=1.5, long_window=40.0,
                span_db=3.0, silence_floor_db=-60.0):
    """The energy series `MusicManager` would report over this track, mirrored offline.

    Line for line the same as `_push_energy`: a short and a long exponential mean of the mean
    square, the long one catching up at the running-mean rate while the track is young but
    never faster than the short one, and the result the short mean's dB over the long mean's
    scaled into 0..1 across `span_db` either way. Mirrored rather than approximated so the
    numbers a capture injects are the numbers the game would have produced itself.
    """
    step = max(int(RATE * interval), 1)
    a_short = 1.0 - math.exp(-interval / max(short_window, interval))
    short = long = None
    seen = 0
    out = []
    for start in range(0, len(samples) - step, step):
        block = samples[start:start + step]
        mean_square = sum(float(v) * float(v) for v in block) / (len(block) * 32768.0 * 32768.0)
        seen += 1
        short = mean_square if short is None else short + a_short * (mean_square - short)
        if long is None:
            long = mean_square
        else:
            a_long = min(max(1.0 - math.exp(-interval / max(long_window, interval)), 1.0 / seen),
                         a_short)
            long += a_long * (mean_square - long)
        short_db = 10.0 * math.log10(max(short, 1e-12))
        if short_db <= silence_floor_db:
            out.append(0.0)
            continue
        long_db = 10.0 * math.log10(max(long, 1e-12))
        out.append(min(1.0, max(0.0, 0.5 + (short_db - long_db) / (2.0 * span_db))))
    return out, interval


def percentile(values, q):
    if not values:
        return 0.5
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, int(round((len(ordered) - 1) * q))))]


def sustained_at(series, interval, quietest):
    """Seconds into the track at the middle of its quietest (or loudest) sustained passage.

    Sustained means a four-second window, not an instant: a single quiet frame between two
    loud ones is a gap in the music, not a passage of it, and photographing one would show a
    moment no listener experiences as quiet.
    """
    width = max(int(4.0 / interval), 1)
    if len(series) <= width:
        return 0.0
    best_at, best = 0, None
    for i in range(0, len(series) - width):
        mean = sum(series[i:i + width]) / width
        if best is None or (mean < best if quietest else mean > best):
            best, best_at = mean, i
    return round((best_at + width / 2.0) * interval, 1)


def measure(path):
    samples = decode(path)
    if len(samples) < RATE:
        return None
    env = envelope_db(samples)
    strength, count = onsets(env)
    seconds = len(samples) / RATE
    series, interval = live_energy(samples)
    return {
        "seconds": round(seconds, 1),
        "loudness_db": round(rms_db(samples), 2),
        "brightness_db": round(rms_db(highpass(samples)) - rms_db(samples), 2),
        "onset_rate": round(count / seconds, 3),
        "tempo_bpm": tempo(strength),
        "live_quiet": round(percentile(series, 0.10), 3),
        "live_mid": round(percentile(series, 0.50), 3),
        "live_loud": round(percentile(series, 0.90), 3),
        "quiet_at": sustained_at(series, interval, True),
        "loud_at": sustained_at(series, interval, False),
    }


def zscores(values):
    n = len(values)
    if n < 2:
        return [0.0] * n
    mean = sum(values) / n
    var = sum((v - mean) ** 2 for v in values) / (n - 1)
    sd = math.sqrt(var) if var > 0 else 1.0
    return [(v - mean) / sd for v in values]


def ranks(values):
    """0..1 by rank: the smallest is 0, the largest 1, ties share a rank."""
    order = sorted(range(len(values)), key=lambda i: values[i])
    out = [0.0] * len(values)
    if len(values) < 2:
        return out
    for rank, i in enumerate(order):
        out[i] = rank / (len(values) - 1)
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    playlist_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        root, "assets", "music", "radio", "playlist.json")
    track_dir = os.path.dirname(playlist_path)
    playlist = json.load(open(playlist_path, encoding="utf-8"))
    rows = []
    for track in playlist.get("tracks", []):
        file = track.get("file", "")
        path = os.path.join(track_dir, file)
        if not file or not os.path.isfile(path):
            print("skip  %s (missing)" % file, file=sys.stderr)
            continue
        m = measure(path)
        if m is None:
            print("skip  %s (too short)" % file, file=sys.stderr)
            continue
        m["file"] = file
        m["title"] = track.get("title", "")
        rows.append(m)
        print("%-62s %6.1f dB  %6.1f dB  %5.2f/s  %5.1f bpm" % (
            file, m["loudness_db"], m["brightness_db"], m["onset_rate"], m["tempo_bpm"]),
            file=sys.stderr)
    loud_z = zscores([r["loudness_db"] for r in rows])
    onset_z = zscores([r["onset_rate"] for r in rows])
    energy_rank = ranks([lz + 0.5 * oz for lz, oz in zip(loud_z, onset_z)])
    bright_rank = ranks([r["brightness_db"] for r in rows])
    out = {"rate": RATE, "tracks": {}}
    for r, e, b in zip(rows, energy_rank, bright_rank):
        out["tracks"][r["file"]] = {
            "title": r["title"],
            "energy": round(e, 3),
            "brightness": round(b, 3),
            "tempo": r["tempo_bpm"],
            "loudness_db": r["loudness_db"],
            "brightness_db": r["brightness_db"],
            "onset_rate": r["onset_rate"],
            "seconds": r["seconds"],
            "live_quiet": r["live_quiet"],
            "live_mid": r["live_mid"],
            "live_loud": r["live_loud"],
            "quiet_at": r["quiet_at"],
            "loud_at": r["loud_at"],
        }
    dest = os.path.join(root, "data", "music", "track_moods.json")
    with open(dest, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    print("wrote %s (%d tracks)" % (dest, len(rows)), file=sys.stderr)


if __name__ == "__main__":
    main()
