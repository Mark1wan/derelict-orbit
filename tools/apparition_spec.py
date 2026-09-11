"""The corridor apparition: a smoke figure, not a body.

Two ideas underneath it. The **jinn** of Islamic belief is made of smokeless fire - not a ghost
of a dead person but a thing of another order, present in the same rooms as you; so the figure is
smoke with an ember somewhere inside it. The Brazilian **vulto** is the shadow that stands in the
doorway at the edge of sight, flat, man-shaped, gone the moment you look straight at it; so the
smoke holds a human outline - shoulders, a head, a suggestion of a hood - and never has feet. It
does not walk. It slides, and it comes apart rather than fading out.

Form is a cloud of soft camera-facing puffs. Each has an anchor on the figure, a drift orbit and
a dissolve direction; `form` (1 -> 0) slides every puff from its anchor out along that direction,
which is how it disperses when you stare at it. Alpha is what makes it darker than the dark - the
puffs are near black and stack up, so the middle of the figure is a hole in the corridor.

Shared with the game: tools/build_apparition.py writes kit/apparition_corridor.json, which
scripts/apparition.gd reads. The smoke texture is generated from the same formula in both.
"""

import math
import random

# ------------------------------------------------------------------ smoke texture
# Value noise with an integer hash, so Python and GDScript produce an identical texture.
NOISE_SEED = 1337


def _hash2(ix, iy, seed):
    h = (ix * 374761393 + iy * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def _value_noise(x, y, cells, seed):
    ix, iy = int(math.floor(x)), int(math.floor(y))
    fx, fy = x - ix, y - iy
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    a = _hash2(ix % cells, iy % cells, seed)
    b = _hash2((ix + 1) % cells, iy % cells, seed)
    c = _hash2(ix % cells, (iy + 1) % cells, seed)
    d = _hash2((ix + 1) % cells, (iy + 1) % cells, seed)
    return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy


def smoke_alpha(u, v):
    """Alpha of the puff sprite at (u, v) in 0..1. Soft round falloff, chewed by three octaves of
    noise so the edge frays instead of reading as a circle."""
    dx, dy = u - 0.5, v - 0.5
    r = math.sqrt(dx * dx + dy * dy) * 2.0
    if r >= 1.0:
        return 0.0
    fall = (1.0 - r) ** 1.7
    n = 0.0
    amp = 0.5
    cells = 4
    for _ in range(3):
        n += _value_noise(u * cells, v * cells, cells, NOISE_SEED + cells) * amp
        amp *= 0.5
        cells *= 2
    n /= 0.875
    return max(0.0, min(1.0, fall * (0.62 + 0.52 * n)))


# ------------------------------------------------------------------ the figure
# A puff: anchor on the figure, radius, alpha, how far and which way it drifts, and the direction
# it leaves along when the thing comes apart.
PUFFS = []


def puff(pos, size, alpha, drift=0.05, spin=0.4, out=None, rise=0.0, seed=0, tint="core"):
    rng = random.Random(seed if seed else len(PUFFS) * 7919 + 13)
    if out is None:
        d = [pos[0], max(0.15, pos[1] - 1.0) * 0.35, pos[2]]
        n = math.sqrt(sum(v * v for v in d)) or 1.0
        out = [d[0] / n, d[1] / n + 0.55, d[2] / n]
    PUFFS.append({
        "tint": tint,
        "pos": list(pos),
        "size": size,
        "alpha": alpha,
        "drift": drift,
        "spin": spin,
        "rise": rise,
        "out": [round(v, 4) for v in out],
        "phase": [round(rng.uniform(0, math.tau), 3) for _ in range(3)],
        "rate": [round(rng.uniform(0.35, 0.95), 3) for _ in range(3)],
    })


def build(seed=7):
    """A standing vulto, about 1.9 m: hooded head, heavy shoulders, a body that thins and frays
    into a trailing skirt with nothing under it. Nothing is symmetrical on purpose."""
    PUFFS.clear()
    rng = random.Random(seed)

    def jitter(x, y, z, s):
        return (x + rng.uniform(-s, s), y + rng.uniform(-s, s), z + rng.uniform(-s, s))

    # head - one dense puff with a hood of smaller ones over and behind it
    puff(jitter(0, 1.72, 0, 0.01), 0.25, 0.97, drift=0.020, spin=0.25)
    for _ in range(4):
        puff(jitter(0, 1.77, 0.02, 0.07), 0.20, 0.72, drift=0.035, spin=0.5)
    # shoulders: the widest part, what makes it read as a person at 20 m
    for sx in (-1, 1):
        puff(jitter(sx * 0.24, 1.46, 0, 0.03), 0.31, 0.95, drift=0.030, spin=0.3)
        puff(jitter(sx * 0.36, 1.37, 0, 0.05), 0.25, 0.85, drift=0.045, spin=0.45)
    puff((0, 1.52, 0), 0.30, 0.95, drift=0.025)
    # chest and waist, tapering
    for i, (y, r, a) in enumerate([(1.34, 0.33, 0.97), (1.22, 0.33, 0.97), (1.10, 0.32, 0.96),
                                   (0.98, 0.31, 0.94), (0.86, 0.30, 0.92), (0.74, 0.28, 0.88),
                                   (0.62, 0.26, 0.82), (0.52, 0.24, 0.72)]):
        puff(jitter(0, y, 0, 0.035), r, a, drift=0.03 + i * 0.006, spin=0.35)
    # arms: hanging, thinning to nothing - no hands
    for sx in (-1, 1):
        for i, y in enumerate([1.32, 1.19, 1.06, 0.93, 0.80]):
            puff(jitter(sx * (0.33 + i * 0.010), y, 0, 0.03), 0.185 - i * 0.018,
                 0.88 - i * 0.13, drift=0.045 + i * 0.018, spin=0.5)
    # the skirt: it does not stand on anything, it trails off
    for i, (y, r, a) in enumerate([(0.43, 0.26, 0.62), (0.34, 0.25, 0.50), (0.26, 0.23, 0.38),
                                   (0.18, 0.20, 0.26), (0.11, 0.17, 0.16), (0.05, 0.14, 0.09)]):
        puff(jitter(0, y, 0, 0.05), r, a, drift=0.07 + i * 0.03, spin=0.6, rise=-0.1)
    # haze: big, almost transparent, a shade lighter than the black core and faintly violet. This
    # is what gives the mass an edge - against an unlit bulkhead a pure black figure is nothing at
    # all, and it is the haze you actually catch out of the corner of your eye.
    for y, r, a in [(1.62, 0.42, 0.10), (1.40, 0.52, 0.12), (1.12, 0.54, 0.12),
                    (0.84, 0.50, 0.10), (0.56, 0.44, 0.08), (0.30, 0.38, 0.06)]:
        puff(jitter(0, y, 0, 0.05), r, a, drift=0.05, spin=0.2, tint="haze")

    # loose wisps that peel off and rise - smoke, not cloth
    for _ in range(7):
        a = rng.uniform(0, math.tau)
        rad = rng.uniform(0.22, 0.46)
        puff((math.cos(a) * rad, rng.uniform(0.5, 1.75), math.sin(a) * rad * 0.5),
             rng.uniform(0.08, 0.15), rng.uniform(0.10, 0.26),
             drift=rng.uniform(0.09, 0.18), spin=0.8, rise=rng.uniform(0.05, 0.16))
    return PUFFS


# Embers: the smokeless fire inside it. Not eyes - two coals at about eye height that brighten
# when it is looked at, which is the only part of it that is ever bright.
EMBERS = [
    {"pos": [-0.062, 1.735, -0.10], "size": 0.045, "energy": 0.55},
    {"pos": [0.058, 1.740, -0.10], "size": 0.042, "energy": 0.55},
]

SMOKE = {
    "core": [0.010, 0.009, 0.014],     # the body of it: near enough a hole in the corridor
    "haze": [0.085, 0.075, 0.115],     # the faint violet edge that makes the hole visible
    "ember": [1.0, 0.35, 0.08],        # smokeless fire, the only bright thing about it
}


def spec():
    return {
        "smoke": SMOKE,
        "puffs": build(),
        "embers": EMBERS,
        "texture": {"size": 96, "noise_seed": NOISE_SEED},
    }
