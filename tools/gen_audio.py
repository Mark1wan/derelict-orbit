"""Procedurally synthesise the sound bank. No external assets.
Run: python3 tools/gen_audio.py  (writes to audio/*.wav)

Needs numpy. The two sounds the flickering lights depend on - ballast and underbreath - live in
tools/gen_flicker_audio.py instead, written with nothing but the standard library so the part the
doubt mechanic hangs on can be rebuilt anywhere.
"""
import numpy as np, wave, os, math

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

def t(sec): return np.arange(int(SR * sec)) / SR
def env(n, a, r):
    e = np.ones(n); ai = int(SR * a); ri = int(SR * r)
    if ai: e[:ai] = np.linspace(0, 1, ai)
    if ri: e[-ri:] = np.linspace(1, 0, ri)
    return e
def lowpass(x, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff); dt = 1.0 / SR; a = dt / (rc + dt)
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc); y[i] = acc
    return y
def save(name, x, loop_fade=False):
    x = np.asarray(x, dtype=np.float64)
    if loop_fade:  # crossfade tail into head for seamless looping
        n = int(SR * 0.25); ramp = np.linspace(0, 1, n)
        x[:n] = x[:n] * ramp + x[-n:] * (1 - ramp); x = x[:-n]
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print("wrote", name)

# --- station hum (day ambience, loop)
tt = t(6.0)
hum = 0.5 * np.sin(2 * np.pi * 55 * tt) + 0.25 * np.sin(2 * np.pi * 110 * tt + 0.3) + 0.12 * np.sin(2 * np.pi * 165 * tt)
hum += 0.15 * lowpass(rng.normal(0, 1, len(tt)), 400)
hum *= 1 + 0.08 * np.sin(2 * np.pi * 0.35 * tt)
save("hum", hum, loop_fade=True)

# --- night drone (power off, loop): beating low tones + breathy noise
tt = t(8.0)
drone = 0.6 * np.sin(2 * np.pi * 38 * tt) + 0.5 * np.sin(2 * np.pi * 38.7 * tt) + 0.2 * np.sin(2 * np.pi * 77 * tt)
drone += 0.25 * lowpass(rng.normal(0, 1, len(tt)), 180) * (1 + 0.5 * np.sin(2 * np.pi * 0.11 * tt))
save("drone", drone, loop_fade=True)

# --- heartbeat (loop, 1 beat cycle ~0.9s)
tt = t(0.9)
def thump(at, amp):
    e = np.exp(-np.clip(tt - at, 0, None) * 28) * (tt >= at)
    return amp * e * np.sin(2 * np.pi * 48 * (tt - at))
heart = thump(0.0, 1.0) + thump(0.18, 0.7)
save("heartbeat", heart)

# --- metallic bang
tt = t(1.6)
bang = np.zeros_like(tt)
for f, a, d in [(140, 1.0, 6), (390, 0.6, 9), (870, 0.35, 14), (1730, 0.2, 20), (2600, 0.1, 30)]:
    bang += a * np.exp(-tt * d) * np.sin(2 * np.pi * f * tt)
bang += 0.8 * np.exp(-tt * 40) * rng.normal(0, 1, len(tt))
save("bang", bang)

# --- whisper: bandpassed noise bursts with syllable rhythm
tt = t(2.2)
n = lowpass(rng.normal(0, 1, len(tt)), 3200) - lowpass(rng.normal(0, 1, len(tt)), 900)
syl = np.clip(np.sin(2 * np.pi * 5.5 * tt) + 0.2, 0, 1) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.7 * tt))
whisper = n * syl * env(len(tt), 0.2, 0.5)
save("whisper", whisper)

# --- power down: descending tone + dying hum
tt = t(2.8)
f = 420 * np.exp(-tt * 1.6) + 30
ph = 2 * np.pi * np.cumsum(f) / SR
pd = np.sin(ph) * np.exp(-tt * 0.9) + 0.4 * lowpass(rng.normal(0, 1, len(tt)), 300) * np.exp(-tt * 1.5)
pd += 0.5 * np.exp(-tt * 25) * rng.normal(0, 1, len(tt))  # relay clack
save("powerdown", pd)

# --- power up: clack + rising tone settling
tt = t(2.2)
f = 40 + 380 * (1 - np.exp(-tt * 2.5))
ph = 2 * np.pi * np.cumsum(f) / SR
pu = 0.7 * np.sin(ph) * env(len(tt), 0.05, 0.8) + 0.9 * np.exp(-tt * 30) * rng.normal(0, 1, len(tt))
save("powerup", pu)

# --- UI beep / task complete
tt = t(0.12)
save("beep", np.sin(2 * np.pi * 880 * tt) * env(len(tt), 0.01, 0.05))
tt = t(0.5)
comp = np.sin(2 * np.pi * 660 * tt) * (tt < 0.15) + np.sin(2 * np.pi * 990 * tt) * (tt >= 0.18)
save("complete", comp * env(len(tt), 0.01, 0.2))

# --- flicker: electrical buzz burst
tt = t(0.5)
fl = np.sign(np.sin(2 * np.pi * 100 * tt)) * 0.4 + rng.normal(0, 0.6, len(tt))
fl *= (np.sin(2 * np.pi * 13 * tt) > 0.2) * env(len(tt), 0.01, 0.1)
save("flicker", lowpass(fl, 2500))

# --- breath (stalker, loop)
tt = t(3.0)
br = lowpass(rng.normal(0, 1, len(tt)), 1200) - lowpass(rng.normal(0, 1, len(tt)), 300)
br *= (0.5 + 0.5 * np.sin(2 * np.pi * (1 / 3.0) * tt - 1.2)) ** 2.5
save("breath", br, loop_fade=True)

# --- jumpscare scream: distorted descending harmonics + noise wall
tt = t(1.8)
f = 900 * np.exp(-tt * 1.1) + 120
ph = 2 * np.pi * np.cumsum(f) / SR
sc = np.tanh(3 * (np.sin(ph) + 0.6 * np.sin(2 * ph + 0.5) + 0.4 * np.sin(3.01 * ph)))
sc += 1.2 * rng.normal(0, 1, len(tt)) * np.exp(-tt * 2.0)
sc *= env(len(tt), 0.005, 0.6)
save("scream", sc)

# --- static burst (comms)
tt = t(1.0)
save("static", rng.normal(0, 1, len(tt)) * (0.3 + 0.7 * (np.sin(2 * np.pi * 9 * tt) > 0)) * env(len(tt), 0.02, 0.3))
