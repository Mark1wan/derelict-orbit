#!/usr/bin/env python3
"""Synthesise every sound in Sowbelly, and write Godot's .import sidecars beside them.

    python3 caves/tools/gen_audio.py

Same approach as derelict-orbit's tools/gen_audio.py: numpy, a handful of helpers, and a
block per sound that reads as a recipe. Nothing here is sampled or downloaded, so the whole
project still has no third-party assets.

A cave is a quiet place with a very short list of sounds in it, and that list is almost
entirely about you: your breath, your suit on rock, your helmet finding the ceiling. The only
things that are not you are water and the size of the room. So the bank is small, and three
of the eleven are your own body.

The one that matters most is `scrape`. It is a loop whose gain and filter are driven by
contact pressure, and it is the difference between a passage that looks tight and one that
feels tight - you hear the rock on your shoulders before the screen tells you anything.
"""

import math
import os
import struct
import sys
import wave

import numpy as np

SR = 22050
RNG = np.random.default_rng(11)
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio")

# Sounds that are held rather than triggered, and so have to loop without a seam.
LOOPS = {"deep", "water", "scrape", "breath", "wind"}


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, a, r):
    """Linear attack / release envelope over n samples."""
    e = np.ones(n)
    na, nr = int(SR * a), int(SR * r)
    if na:
        e[:na] = np.linspace(0, 1, na)
    if nr:
        e[-nr:] = np.linspace(1, 0, nr)
    return e


def lowpass(x, cutoff):
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = v * (1.0 - a) + acc * a
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def band(x, lo, hi):
    return lowpass(x, hi) - lowpass(x, lo)


def sweep(f, amp=1.0):
    """Integrate a frequency array to phase - the idiom the whole file leans on."""
    return amp * np.sin(2.0 * np.pi * np.cumsum(f) / SR)


def save(name, x, loop=False):
    x = np.asarray(x, dtype=float)
    if loop:
        # Crossfade the tail over the head so the loop point is inaudible.
        n = int(SR * 0.25)
        ramp = np.linspace(0, 1, n)
        x[:n] = x[:n] * ramp + x[-n:] * (1 - ramp)
        x = x[:-n]
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x / peak * 0.9
    data = (x * 32767).astype("<i2")
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    write_import(name)
    return len(data) / SR, os.path.getsize(path)


# ---------------------------------------------------------------- Godot sidecars

IMPORT_TEMPLATE = """[remap]

importer="wav"
type="AudioStreamWAV"
uid="uid://{uid}"
path="res://.godot/imported/{name}.wav-{hash}.sample"

[deps]

source_file="res://audio/{name}.wav"
dest_files=["res://.godot/imported/{name}.wav-{hash}.sample"]

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=2
"""


def write_import(name):
    """Godot needs a .import next to every asset or the editor has to be opened once by hand.

    The cache filename is the md5 of the resource path and the uid is derived from the name,
    exactly as derelict-orbit's tools/build_props.py does it. Existing files are left alone so
    a regenerated wav keeps the uid everything already refers to.
    """
    import hashlib

    path = os.path.join(OUT, name + ".wav.import")
    if os.path.exists(path):
        return
    res = f"res://audio/{name}.wav"
    digest = hashlib.md5(res.encode()).hexdigest()
    seed = int(hashlib.md5(("uid:" + name).encode()).hexdigest()[:16], 16)
    chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    uid = ""
    for _ in range(13):
        uid += chars[seed % 36]
        seed //= 36
    with open(path, "w", encoding="utf-8") as f:
        f.write(IMPORT_TEMPLATE.format(uid=uid, name=name, hash=digest))


# ---------------------------------------------------------------- the bank

def build():
    made = []

    # The room itself. Sixty metres of rock overhead has a sound, and it is mostly the
    # absence of one - two very low tones a fraction apart, beating against each other about
    # once every three seconds, and nothing above 120 Hz at all.
    x = t(9.0)
    deep = (0.55 * np.sin(2 * np.pi * 31.0 * x)
            + 0.45 * np.sin(2 * np.pi * 31.4 * x)
            + 0.18 * np.sin(2 * np.pi * 62.0 * x))
    deep = deep * (0.82 + 0.18 * np.sin(2 * np.pi * 0.07 * x))
    deep += lowpass(RNG.normal(0, 1, len(x)), 90) * 0.30
    made.append(("deep", save("deep", deep, loop=True)))

    # Water moving somewhere you cannot see. Bandpassed noise with a slow swell - it has to
    # sit under everything without ever being identifiable as a particular stream.
    x = t(7.0)
    n = RNG.normal(0, 1, len(x))
    water = band(n, 260, 2400) * (0.55 + 0.45 * np.sin(2 * np.pi * 0.13 * x) ** 2)
    water += band(RNG.normal(0, 1, len(x)), 1800, 5200) * 0.25
    made.append(("water", save("water", water, loop=True)))

    # A single drip landing in a pool. Sowbelly plays these positionally, with a small
    # max_dist, so they localise - you hear which side of the passage the water is on.
    x = t(0.5)
    f = 1500 * np.exp(-x * 26.0) + 380
    drip = sweep(f) * np.exp(-x * 17.0)
    drip += band(RNG.normal(0, 1, len(x)), 900, 6000) * np.exp(-x * 55.0) * 0.5
    made.append(("drip", save("drip", drip)))

    # Your oversuit dragging over limestone. Broadband, gritty, and deliberately dull - it is
    # going to be modulated by contact pressure every frame and must not be interesting on
    # its own or it will drive you mad in the Flatiron.
    x = t(4.0)
    n = RNG.normal(0, 1, len(x))
    scrape = band(n, 420, 4200)
    grit = np.abs(RNG.normal(0, 1, len(x))) ** 2.2
    grit = lowpass(grit, 120)
    scrape = scrape * (0.35 + 0.65 * grit / max(np.max(grit), 1e-9))
    scrape += band(RNG.normal(0, 1, len(x)), 90, 400) * 0.35
    made.append(("scrape", save("scrape", scrape, loop=True)))

    # Breathing, at rest. Pitch-scaled at runtime by exertion, the way derelict-orbit's
    # heartbeat is, so one loop covers everything from a stroll to a squeeze.
    x = t(4.0)
    cycle = np.sin(2 * np.pi * 0.28 * x)
    n = RNG.normal(0, 1, len(x))
    breath = band(n, 300, 2600) * (0.5 + 0.5 * cycle) ** 2.4
    breath += band(RNG.normal(0, 1, len(x)), 120, 700) * ((0.5 - 0.5 * cycle) ** 2.4) * 0.6
    made.append(("breath", save("breath", breath, loop=True)))

    # Letting the last of it go, on purpose. This is the sound of the Devil's Pinch opening.
    x = t(1.1)
    n = RNG.normal(0, 1, len(x))
    exhale = band(n, 260, 2200) * np.exp(-x * 1.9) * env(len(x), 0.05, 0.3)
    made.append(("exhale", save("exhale", exhale)))

    # And taking it back, whether you wanted to or not.
    x = t(0.9)
    n = RNG.normal(0, 1, len(x))
    gasp = band(n, 420, 3400) * (env(len(x), 0.10, 0.45) ** 1.6)
    gasp += sweep(220 + 180 * np.exp(-x * 4.0)) * 0.10 * env(len(x), 0.08, 0.5)
    made.append(("gasp", save("gasp", gasp)))

    # Helmet on rock. Hard, close, and over instantly - five inharmonic partials, which is
    # what stops it sounding like a drum.
    x = t(0.35)
    helmet = np.zeros(len(x))
    for f0, decay, amp in [(320, 22, 1.0), (760, 28, 0.6), (1190, 34, 0.4),
                           (2050, 40, 0.25), (3100, 48, 0.15)]:
        helmet += amp * np.sin(2 * np.pi * f0 * x) * np.exp(-x * decay)
    helmet += band(RNG.normal(0, 1, len(x)), 1200, 7000) * np.exp(-x * 70.0) * 0.6
    made.append(("helmet", save("helmet", helmet)))

    # Loose rock shifting under a boot or a hand.
    x = t(0.6)
    n = RNG.normal(0, 1, len(x))
    gravel = band(n, 200, 3800) * np.exp(-x * 7.0)
    ticks = np.zeros(len(x))
    for _ in range(9):
        i = RNG.integers(0, len(x) - 400)
        ticks[i:i + 400] += np.sin(2 * np.pi * RNG.uniform(400, 1600) * x[:400]) * np.exp(-x[:400] * 40)
    made.append(("gravel", save("gravel", gravel + ticks * 0.4)))

    # A gloved hand closing on rock. Short, dry, almost nothing - but without it, grabbing
    # has no moment.
    x = t(0.22)
    grab = band(RNG.normal(0, 1, len(x)), 300, 3000) * np.exp(-x * 26.0)
    grab += np.sin(2 * np.pi * 150 * x) * np.exp(-x * 40.0) * 0.3
    made.append(("grab", save("grab", grab)))

    # Rope through a descender: a rising hiss with the rhythm of the strands going past.
    x = t(1.4)
    n = RNG.normal(0, 1, len(x))
    rope = band(n, 700, 5200) * env(len(x), 0.08, 0.5)
    rope = rope * (0.6 + 0.4 * (np.sin(2 * np.pi * 17.0 * x) > -0.3))
    rope += band(RNG.normal(0, 1, len(x)), 140, 600) * env(len(x), 0.1, 0.6) * 0.5
    made.append(("rope", save("rope", rope)))

    # Air moving at the entrance, which is the last sound of the outside world.
    x = t(6.0)
    n = RNG.normal(0, 1, len(x))
    wind = band(n, 150, 1400) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.09 * x) ** 2)
    made.append(("wind", save("wind", wind, loop=True)))

    return made


def main():
    os.makedirs(OUT, exist_ok=True)
    made = build()
    print(f"{'sound':<10}{'seconds':>9}{'kB':>8}   loop")
    print("-" * 38)
    total = 0
    for name, (secs, size) in made:
        total += size
        print(f"{name:<10}{secs:>9.2f}{size / 1024:>8.0f}   {'yes' if name in LOOPS else ''}")
    print("-" * 38)
    print(f"{len(made)} sounds, {total / 1024:.0f} kB, all of it generated")
    names = sorted(n for n, _ in made)
    print("\nSfx.NAMES should be:\n  " + str(names).replace("'", '"'))
    return 0


if __name__ == "__main__":
    sys.exit(main())
