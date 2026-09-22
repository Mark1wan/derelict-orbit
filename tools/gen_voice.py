#!/usr/bin/env python3
"""The radio voice: Gateway Control, your own readback, and the thing that answers at night.

    python3 tools/gen_voice.py     # audio/voice/*.wav (one per comms/log.json entry) + the console sounds

Written with nothing but the standard library, like tools/gen_flicker_audio.py - the story hangs on
these files, so they have to be rebuildable anywhere.

There is no speech engine here and no recorded asset in this repository. What this builds is a
**formant voice**: a glottal pulse train pushed through three resonators whose centre frequencies
walk between one letter's target and the next, unvoiced letters turned into shaped noise instead,
with syllable-length timing, a falling pitch across each sentence and a rise on a question. It is
the Apollo-loop cadence of somebody reading a report at you. You do not make out the words - the
console prints those while it talks - you make out that a person is talking, and on the last two
nights that the person is wrong.

Then the radio: 8 kHz - the voice band is 300-3000 Hz, so a comms channel that sounds like a comms
channel is genuinely this narrow - clipped through the transmitter, hissed, dropped out here and
there, and topped and tailed with squelch. The three speakers are the same synth on different
settings (VOICES): Gateway is a compressed distant baritone with light-time slap, your own readback
is closer and cleaner, and "other" is slow, low and overdriven.
"""

import json
import math
import os
import random
import struct
import wave

SR = 8000                       # the voice band is 300-3000 Hz: a radio channel is this narrow
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(ROOT, "audio", "voice")
LOG = os.path.join(ROOT, "comms", "log.json")

# ---------------------------------------------------------------- the mouth
# letter -> (F1, F2, F3, voiced, noise, seconds, loudness). Vowels carry the tune; consonants are
# short and mostly get out of the way, which is what makes the result read as speech and not song.
VOWELS = {
    "a": (700, 1200, 2500), "e": (500, 1800, 2500), "i": (350, 2100, 2800),
    "o": (500, 900, 2400), "u": (380, 900, 2300), "y": (400, 1900, 2600),
}
CONSONANTS = {
    "m": (280, 900, 2200, 1, 0.0, 0.070, 0.55), "n": (280, 1700, 2600, 1, 0.0, 0.060, 0.55),
    "l": (360, 1100, 2600, 1, 0.0, 0.060, 0.70), "r": (330, 1000, 1600, 1, 0.0, 0.060, 0.70),
    "w": (300, 700, 2300, 1, 0.0, 0.055, 0.65),
    "v": (300, 1100, 2400, 1, 0.45, 0.050, 0.45), "z": (300, 1600, 2500, 1, 0.60, 0.060, 0.45),
    "j": (300, 1700, 2500, 1, 0.55, 0.060, 0.45),
    "b": (300, 900, 2200, 1, 0.25, 0.035, 0.50), "d": (300, 1700, 2600, 1, 0.30, 0.030, 0.50),
    "g": (300, 1400, 2200, 1, 0.30, 0.035, 0.50),
    "s": (600, 2600, 3200, 0, 1.0, 0.085, 0.30), "f": (500, 1600, 2400, 0, 1.0, 0.070, 0.24),
    "h": (500, 1500, 2500, 0, 0.8, 0.045, 0.20),
    "t": (500, 2400, 3000, 0, 1.0, 0.030, 0.38), "k": (500, 1900, 2600, 0, 1.0, 0.035, 0.38),
    "p": (400, 1200, 2200, 0, 1.0, 0.030, 0.34),
    "c": (500, 1900, 2600, 0, 1.0, 0.035, 0.38), "q": (500, 1900, 2600, 0, 1.0, 0.035, 0.38),
    "x": (600, 2400, 3000, 0, 1.0, 0.070, 0.34),
}
PLOSIVES = "bdgptkcq"            # a beat of closed mouth before the burst
BW = (90.0, 110.0, 160.0)        # resonator bandwidths

VOICES = {
    # f0, jitter, rate, band (hi-pass, lo-pass), drive, hiss, slap (light-time echo), dropouts/s
    "earth": dict(f0=112.0, jitter=0.012, rate=0.75, band=(350, 2650), drive=2.4, hiss=0.030,
                  slap=0.22, drops=0.35, wobble=0.0),
    "self":  dict(f0=132.0, jitter=0.016, rate=0.72, band=(300, 3000), drive=1.5, hiss=0.016,
                  slap=0.0, drops=0.12, wobble=0.0),
    "other": dict(f0=86.0, jitter=0.030, rate=1.05, band=(260, 2300), drive=3.6, hiss=0.055,
                  slap=0.30, drops=0.9, wobble=0.05),
}


def segments(text, rate):
    """Text -> [(seconds, F1, F2, F3, voiced, noise, loudness, stressed)]. Punctuation becomes
    silence, which is most of what makes a line sound like it was read rather than emitted."""
    out = []
    for word in text.replace("\n", " ").split(" "):
        if not word:
            continue
        tail = ""
        while word and word[-1] in ".,?!:;-":
            tail = word[-1] + tail
            word = word[:-1]
        letters = [c for c in word.lower() if c.isalpha()]
        if not letters and any(c.isdigit() for c in word):
            letters = ["o", "n"]          # a number still gets a syllable
        first_vowel = True
        for i, c in enumerate(letters):
            if c in VOWELS:
                f1, f2, f3 = VOWELS[c]
                dur = 0.115 * rate
                if i == len(letters) - 1 and c == "e" and len(letters) > 2:
                    dur *= 0.35           # trailing silent e
                stressed = first_vowel
                first_vowel = False
                out.append((dur, f1, f2, f3, 1, 0.0, 1.0, stressed))
            elif c in CONSONANTS:
                f1, f2, f3, voiced, noise, dur, amp = CONSONANTS[c]
                if c in PLOSIVES:
                    out.append((0.022 * rate, f1, f2, f3, 0, 0.0, 0.0, False))
                out.append((dur * rate, f1, f2, f3, voiced, noise, amp, False))
        out.append((0.055 * rate, 400, 1200, 2400, 0, 0.0, 0.0, False))   # between words
        if tail:
            gap = 0.34 if tail[0] in ".?!" else 0.17
            out.append((gap * rate, 400, 1200, 2400, 0, 0.0, 0.0, False))
    return out


def say(text, v, rng):
    """Render one line as raw (unradioed) voice."""
    segs = segments(text, v["rate"])
    total = sum(s[0] for s in segs)
    n = int(SR * total) + 1
    # per-sample formant targets, walked between segments over a 30 ms glide (coarticulation)
    tf = [0.0] * n
    f1t = [500.0] * n
    f2t = [1400.0] * n
    f3t = [2500.0] * n
    amp = [0.0] * n
    voi = [0.0] * n
    noi = [0.0] * n
    stress = [0.0] * n
    i = 0
    for (dur, f1, f2, f3, voiced, noise, a, st) in segs:
        k = max(1, int(SR * dur))
        for j in range(k):
            if i >= n:
                break
            f1t[i], f2t[i], f3t[i] = f1, f2, f3
            # a short attack and release keeps every segment from clicking
            e = min(1.0, j / (0.012 * SR + 1), (k - j) / (0.012 * SR + 1))
            amp[i] = a * e
            voi[i] = 1.0 if voiced else 0.0
            noi[i] = noise
            stress[i] = 1.0 if st else 0.0
            i += 1
    n = i
    f1t, f2t, f3t, amp, voi, noi, stress = (x[:n] for x in (f1t, f2t, f3t, amp, voi, noi, stress))
    f1t, f2t, f3t = smooth(f1t, 0.030), smooth(f2t, 0.030), smooth(f3t, 0.030)
    amp = smooth(amp, 0.006)

    # pitch: declination across the line, a rise if it is a question, vibrato, jitter, stress
    rising = text.strip().endswith("?")
    f0 = []
    for i in range(n):
        p = i / max(1, n - 1)
        f = v["f0"] * (1.10 - 0.22 * p)
        if rising and p > 0.80:
            f *= 1.0 + 0.55 * (p - 0.80)
        f *= 1.0 + 0.025 * math.sin(2 * math.pi * 4.7 * i / SR)
        f *= 1.0 + v["jitter"] * (rng.random() - 0.5)
        f *= 1.0 + 0.06 * stress[i]
        if v["wobble"]:
            f *= 1.0 + v["wobble"] * math.sin(2 * math.pi * 0.7 * i / SR)
        f0.append(f)

    # source: Rosenberg-ish glottal pulses for the voiced part, white noise for the rest
    src = [0.0] * n
    phase = 0.0
    for i in range(n):
        phase += f0[i] / SR
        if phase >= 1.0:
            phase -= 1.0
        pulse = 0.0
        if phase < 0.42:
            x = phase / 0.42
            pulse = 0.5 - 0.5 * math.cos(2 * math.pi * x) if x < 0.5 else (1.0 - x) * 2.0
            pulse = pulse - 0.35
        src[i] = voi[i] * pulse * 1.3 + (noi[i] + (1.0 - voi[i])) * 0.35 * (rng.random() * 2 - 1)

    # three resonators, coefficients refreshed every 32 samples (cheap, inaudible)
    y = src
    for band, bw in enumerate(BW):
        tgt = (f1t, f2t, f3t)[band]
        out = [0.0] * n
        y1 = y2 = 0.0
        a1 = a2 = g = 0.0
        for i in range(n):
            if i % 32 == 0:
                r = math.exp(-math.pi * bw / SR)
                th = 2 * math.pi * min(tgt[i], SR * 0.45) / SR
                a1 = 2 * r * math.cos(th)
                a2 = -r * r
                g = (1 - r) * math.sqrt(1 + r * r - 2 * r * math.cos(2 * th))
            v0 = g * y[i] + a1 * y1 + a2 * y2
            y2, y1 = y1, v0
            out[i] = v0
        y = out
    return [y[i] * amp[i] for i in range(n)]


# ---------------------------------------------------------------- the radio
def smooth(x, sec):
    a = 1.0 / max(1.0, sec * SR)
    out = [0.0] * len(x)
    acc = x[0] if x else 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        out[i] = acc
    for i in range(len(x) - 2, -1, -1):      # backwards too, so the glide is not late
        acc += a * (out[i] - acc)
        out[i] = acc
    return out


def onepole_lp(x, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    a = (1.0 / SR) / (rc + 1.0 / SR)
    out = [0.0] * len(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        out[i] = acc
    return out


def onepole_hp(x, cutoff):
    lo = onepole_lp(x, cutoff)
    return [x[i] - lo[i] for i in range(len(x))]


def radio(x, v, rng):
    """Transmitter, channel and receiver: band, clip, hiss, dropouts, light-time slap."""
    lo, hi = v["band"]
    x = onepole_hp(onepole_hp(onepole_lp(x, hi), lo), lo)
    d = v["drive"]
    x = [math.tanh(d * s) / math.tanh(d) for s in x]
    if v["slap"]:                                    # the distance, heard as a short repeat
        k = int(0.019 * SR)
        x = [x[i] + v["slap"] * x[i - k] for i in range(len(x))]
    n = len(x)
    gate = [1.0] * n                                 # squelch dropouts: the channel losing it
    i = 0
    while i < n:
        if rng.random() < v["drops"] / SR:
            w = int(rng.uniform(0.035, 0.11) * SR)
            for j in range(i, min(n, i + w)):
                gate[j] = 0.06
            i += w
        i += 1
    gate = smooth(gate, 0.004)
    out = [x[i] * gate[i] + v["hiss"] * (rng.random() * 2 - 1) for i in range(n)]
    return onepole_lp(onepole_hp(out, lo), hi)


def squelch(rng, v, open_=True):
    """The click and the breath of noise around a keyed mic."""
    n = int(SR * (0.09 if open_ else 0.13))
    out = []
    for i in range(n):
        p = i / n
        e = (1 - p) ** 2 if open_ else p ** 0.4 * (1 - p)
        out.append(1.4 * v["hiss"] * (rng.random() * 2 - 1) * (0.5 + 4.0 * e))
    for i in range(int(SR * 0.004)):                 # the relay
        if i < len(out):
            out[i] += (rng.random() * 2 - 1) * 0.22 * (1 - i / (SR * 0.004))
    return onepole_hp(onepole_lp(out, v["band"][1]), v["band"][0])


def save(path, x, peak=0.92):
    m = max((abs(s) for s in x), default=1.0) or 1.0
    x = [s / m * peak for s in x]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in x))
    print("wrote %-34s %5.1f s" % (os.path.relpath(path, ROOT), len(x) / SR))


def level(x, peak):
    """Bring a block up to a known peak. The formant chain's output level depends on which vowels
    happen to be in the line, and the transmitter has to be driven at a consistent level or the
    clipping - which is most of what makes it sound like radio - does nothing."""
    m = max((abs(s) for s in x), default=0.0)
    return x if m < 1e-9 else [s / m * peak for s in x]


def transmission(lines, voice, seed):
    rng = random.Random(seed)
    v = VOICES[voice]
    speech = []
    for line in lines:
        speech += say(line, v, rng)
        speech += [0.0] * int(SR * rng.uniform(0.10, 0.22))
    out = radio(level(speech, 0.85), v, rng)
    return list(squelch(rng, v, True)) + out + list(squelch(rng, v, False))


# ---------------------------------------------------------------- console sounds
def console_sounds():
    rng = random.Random(41)
    v = VOICES["earth"]
    # incoming hail: two tones over an opening squelch - the sound you learn to dread by day five
    hail = list(squelch(rng, v, True))
    for f, sec in ((760, 0.16), (1180, 0.22)):
        for i in range(int(SR * sec)):
            t = i / SR
            e = min(1.0, t / 0.01, (sec - t) / 0.05)
            hail.append(0.7 * math.sin(2 * math.pi * f * t) * e)
    save(os.path.join(ROOT, "audio", "comms_hail.wav"), onepole_hp(hail, 300))

    # keying the mic to answer: relay clack, then the transmitter coming up
    key = []
    for i in range(int(SR * 0.35)):
        t = i / SR
        click = math.exp(-t * 90) * (rng.random() * 2 - 1)
        carrier = 0.25 * (rng.random() * 2 - 1) * min(1.0, t / 0.02) * math.exp(-t * 3)
        key.append(click + carrier)
    save(os.path.join(ROOT, "audio", "comms_key.wav"), onepole_lp(onepole_hp(key, 300), 2600))

    # open carrier, looping: an empty channel that is nonetheless on
    n = int(SR * 4.0)
    car = [0.35 * (rng.random() * 2 - 1) for _ in range(n)]
    car = onepole_lp(onepole_hp(car, 500), 1800)
    for i in range(n):
        car[i] *= 1.0 + 0.4 * math.sin(2 * math.pi * 0.23 * i / SR)
        car[i] += 0.05 * math.sin(2 * math.pi * 60 * i / SR)
    f = int(SR * 0.25)                               # crossfade the tail into the head
    for i in range(f):
        car[i] = car[i] * (i / f) + car[n - f + i] * (1 - i / f)
    save(os.path.join(ROOT, "audio", "comms_carrier.wav"), car[:n - f], 0.6)


def main():
    with open(LOG) as fh:
        log = json.load(fh)
    for e in log["entries"]:
        if not e.get("voice"):
            continue
        save(os.path.join(OUT, e["id"] + ".wav"),
             transmission(e["text"], e["voice"], sum(ord(c) for c in e["id"])))
    console_sounds()


if __name__ == "__main__":
    main()
