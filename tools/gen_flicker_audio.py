#!/usr/bin/env python3
"""The flicker family: the two sounds that decide whether a stuttering lamp is the station or not.

    python3 tools/gen_flicker_audio.py      # writes audio/ballast.wav, audio/underbreath.wav

Written without numpy, unlike tools/gen_audio.py which made the rest of the bank - these are the
two sounds the whole doubt mechanic hangs on and they need to be buildable anywhere, including
somewhere with nothing installed.

**ballast** is what a failing fitting sounds like: mains buzz at 120 Hz with its harmonics, gated
into irregular bursts, with the odd contact tick. Every stutter plays it, whatever caused it.

**underbreath** is the trick. It is the sound of something breathing very close to you, pitched
low and rolled right off at the top, so that when it is mixed in *underneath* the buzz at -26 dB
it does not arrive as a sound at all. It arrives as a suspicion that the buzz had something in it.
It plays under about three in five haunted stutters - and under about one in seven of the lamps
that are genuinely broken, because a tell with no false positives is not a tell, it is a label.
"""

import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def lowpass(x, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / SR
    a = dt / (rc + dt)
    acc = 0.0
    out = []
    for v in x:
        acc += a * (v - acc)
        out.append(acc)
    return out


def highpass(x, cutoff):
    lo = lowpass(x, cutoff)
    return [x[i] - lo[i] for i in range(len(x))]


def save(name, x, peak=0.9):
    m = max(abs(v) for v in x) or 1.0
    x = [v / m * peak for v in x]
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in x))
    print("wrote %s (%.2f s, %d B)" % (name, len(x) / SR, os.path.getsize(path)))


def ballast(seconds=1.1, seed=11):
    """A fitting on its way out: 120 Hz and harmonics, chopped into bursts, with contact ticks."""
    rng = random.Random(seed)
    n = int(SR * seconds)
    out = []
    # the gate: irregular on/off, nothing periodic enough to feel like a rhythm
    gate = []
    t = 0
    on = True
    while len(gate) < n:
        run = int(SR * (rng.uniform(0.02, 0.10) if on else rng.uniform(0.01, 0.07)))
        level = rng.uniform(0.55, 1.0) if on else rng.uniform(0.0, 0.12)
        gate.extend([level] * run)
        on = not on
    for i in range(n):
        s = i / SR
        v = (0.60 * math.sin(2 * math.pi * 120 * s)
             + 0.28 * math.sin(2 * math.pi * 240 * s + 0.7)
             + 0.15 * math.sin(2 * math.pi * 360 * s + 1.9)
             + 0.10 * math.sin(2 * math.pi * 600 * s))
        v += rng.uniform(-0.25, 0.25)           # the fizz across the contacts
        out.append(v * gate[i])
    # contact ticks: a few sharp transients, because that is what you actually notice
    for _ in range(rng.randint(3, 6)):
        i = rng.randrange(0, n - 400)
        for k in range(300):
            out[i + k] += rng.uniform(-1.0, 1.0) * math.exp(-k / 40.0) * 0.8
    out = highpass(out, 70)
    # top and tail so it does not click when it starts
    a = int(SR * 0.006)
    for i in range(a):
        out[i] *= i / a
        out[-1 - i] *= i / a
    return out


def underbreath(seconds=1.35, seed=29):
    """Something breathing, close, pitched down and rolled off - made to live under the buzz.

    Two draws: in, out. The pitched part is only there to give the noise a body; on its own it is
    almost nothing, which is exactly the requirement. If you can clearly hear this, it is mixed
    too loud and the mechanic is dead."""
    rng = random.Random(seed)
    n = int(SR * seconds)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    body = lowpass(noise, 520)               # the breath itself: air, no edge to it
    body = highpass(body, 90)
    out = []
    for i in range(n):
        s = i / SR
        # in (slow, swelling), a catch, then out (shorter, heavier)
        if s < 0.55:
            e = math.sin(math.pi * s / 0.55) ** 1.6
        elif s < 0.68:
            e = 0.08
        else:
            e = math.sin(math.pi * (s - 0.68) / (seconds - 0.68)) ** 1.2 * 0.85
        # a low pitched component, right at the bottom, so it has a throat rather than a hiss
        v = body[i] * e + 0.22 * e * math.sin(2 * math.pi * 78 * s + 0.6 * math.sin(2 * math.pi * 3.1 * s))
        out.append(v)
    out = lowpass(out, 900)
    a = int(SR * 0.02)
    for i in range(a):
        out[i] *= i / a
        out[-1 - i] *= i / a
    return out


IMPORT = """[remap]

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
    """Godot's sidecar, so the editor picks the sound up without a manual reimport."""
    import hashlib
    path = os.path.join(OUT, name + ".wav.import")
    if os.path.exists(path):
        return
    digest = hashlib.md5(("res://audio/%s.wav" % name).encode()).hexdigest()
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
    v = int(hashlib.md5(("uid:audio:" + name).encode()).hexdigest(), 16)
    uid = ""
    for _ in range(13):
        uid, v = uid + alphabet[v % len(alphabet)], v // len(alphabet)
    with open(path, "w") as f:
        f.write(IMPORT.format(uid=uid, name=name, hash=digest))


if __name__ == "__main__":
    save("ballast", ballast())
    save("underbreath", underbreath(), peak=0.75)
    for n in ("ballast", "underbreath"):
        write_import(n)
