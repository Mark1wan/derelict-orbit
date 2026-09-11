"""The apparitions: smoke figures, not bodies. One module per figure in the suite.

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

The **ghul** of pre-Islamic Arabia is the second figure here, and it works differently: a desert
demon that waits off the road wearing the shape of a person to draw travellers in, eats the dead,
and cannot hide its hooves whatever else it changes. So that one carries two layouts - what you
see from down the corridor, and what is actually standing there - and `morph` between them.

Shared with the game: tools/build_apparition.py writes kit/apparition_*.json, which
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


def smoke_alpha(u, v, plateau=0.0):
    """Alpha of the puff sprite at (u, v) in 0..1. Soft round falloff chewed by three octaves of
    noise, so the edge frays instead of reading as a circle.

    `plateau` is how much of the middle is flat-out opaque before the falloff starts. At 0 the
    puff is a soft blob and a cloud of them looks like smoke; raise it and overlapping puffs merge
    into one mass instead of reading as a string of beads, which is what a figure pretending to be
    a person needs."""
    dx, dy = u - 0.5, v - 0.5
    r = math.sqrt(dx * dx + dy * dy) * 2.0
    if r >= 1.0:
        return 0.0
    fall = min(1.0, (1.0 - r) / max(1e-3, 1.0 - plateau)) ** 1.7
    n = 0.0
    amp = 0.5
    cells = 4
    for _ in range(3):
        n += _value_noise(u * cells, v * cells, cells, NOISE_SEED + cells) * amp
        amp *= 0.5
        cells *= 2
    n /= 0.875
    return max(0.0, min(1.0, fall * (0.62 + 0.52 * n)))




# ------------------------------------------------------------------ figures
class Figure:
    """A cloud of soft camera-facing puffs holding a shape, plus the embers burning inside it.

    Every puff has an anchor, a drift orbit (so the mass boils and never holds still) and a
    dissolve direction. `form` 1 -> 0 slides each puff out along that direction and fades it,
    which is how these things arrive and leave. A figure with `morph` anchors has a second pose:
    what it looks like once it stops pretending.
    """

    def __init__(self, name, core, haze, embers_by_key, plateau=0.0):
        self.name = name
        self.plateau = plateau
        self.colors = {"core": core, "haze": haze}
        self.colors.update(embers_by_key)
        self.puffs = []
        self.embers = []

    def puff(self, pos, size, alpha, drift=0.05, spin=0.4, out=None, rise=0.0, tint="core",
             pos2=None, size2=None, seed=None):
        rng = random.Random(seed if seed is not None else len(self.puffs) * 7919 + 13)
        if out is None:
            d = [pos[0], max(0.15, pos[1] - 1.0) * 0.35, pos[2]]
            n = math.sqrt(sum(v * v for v in d)) or 1.0
            out = [d[0] / n, d[1] / n + 0.55, d[2] / n]
        p = {
            "tint": tint,
            "pos": [round(v, 4) for v in pos],
            "size": round(size, 4),
            "alpha": round(alpha, 4),
            "drift": drift,
            "spin": spin,
            "rise": rise,
            "out": [round(v, 4) for v in out],
            "phase": [round(rng.uniform(0, math.tau), 3) for _ in range(3)],
            "rate": [round(rng.uniform(0.35, 0.95), 3) for _ in range(3)],
        }
        if pos2 is not None:
            p["pos2"] = [round(v, 4) for v in pos2]
            p["size2"] = round(size2 if size2 is not None else size, 4)
        self.puffs.append(p)

    def ember(self, pos, size, energy, key="ember", pos2=None, size2=None, energy2=None):
        e = {"pos": [round(v, 4) for v in pos], "size": size, "energy": energy, "key": key}
        if pos2 is not None or energy2 is not None:
            e["pos2"] = [round(v, 4) for v in (pos2 if pos2 is not None else pos)]
            e["size2"] = size2 if size2 is not None else size
            e["energy2"] = energy if energy2 is None else energy2
        self.embers.append(e)

    def spec(self):
        return {
            "name": self.name,
            "smoke": self.colors,
            "puffs": self.puffs,
            "embers": self.embers,
            "texture": {"size": 96, "noise_seed": NOISE_SEED, "plateau": self.plateau},
        }


# ------------------------------------------------------------------ the corridor vulto
def corridor_figure(seed=7):
    """A standing vulto, about 1.9 m: hooded head, heavy shoulders, a body that thins and frays
    into a trailing skirt with nothing under it. Nothing is symmetrical on purpose."""
    f = Figure(
        "corridor",
        core=[0.010, 0.009, 0.014],      # the body of it: near enough a hole in the corridor
        haze=[0.085, 0.075, 0.115],      # the faint violet edge that makes the hole visible
        embers_by_key={"ember": [1.0, 0.35, 0.08]},   # smokeless fire
    )
    rng = random.Random(seed)

    def j(x, y, z, s):
        return (x + rng.uniform(-s, s), y + rng.uniform(-s, s), z + rng.uniform(-s, s))

    f.puff(j(0, 1.72, 0, 0.01), 0.25, 0.97, drift=0.020, spin=0.25)
    for _ in range(4):
        f.puff(j(0, 1.77, 0.02, 0.07), 0.20, 0.72, drift=0.035, spin=0.5)
    for sx in (-1, 1):
        f.puff(j(sx * 0.24, 1.46, 0, 0.03), 0.31, 0.95, drift=0.030, spin=0.3)
        f.puff(j(sx * 0.36, 1.37, 0, 0.05), 0.25, 0.85, drift=0.045, spin=0.45)
    f.puff((0, 1.52, 0), 0.30, 0.95, drift=0.025)
    for i, (y, r, a) in enumerate([(1.34, 0.33, 0.97), (1.22, 0.33, 0.97), (1.10, 0.32, 0.96),
                                   (0.98, 0.31, 0.94), (0.86, 0.30, 0.92), (0.74, 0.28, 0.88),
                                   (0.62, 0.26, 0.82), (0.52, 0.24, 0.72)]):
        f.puff(j(0, y, 0, 0.035), r, a, drift=0.03 + i * 0.006, spin=0.35)
    for sx in (-1, 1):
        for i, y in enumerate([1.32, 1.19, 1.06, 0.93, 0.80]):
            f.puff(j(sx * (0.33 + i * 0.010), y, 0, 0.03), 0.185 - i * 0.018,
                   0.88 - i * 0.13, drift=0.045 + i * 0.018, spin=0.5)
    for i, (y, r, a) in enumerate([(0.43, 0.26, 0.62), (0.34, 0.25, 0.50), (0.26, 0.23, 0.38),
                                   (0.18, 0.20, 0.26), (0.11, 0.17, 0.16), (0.05, 0.14, 0.09)]):
        f.puff(j(0, y, 0, 0.05), r, a, drift=0.07 + i * 0.03, spin=0.6, rise=-0.1)
    for y, r, a in [(1.62, 0.42, 0.10), (1.40, 0.52, 0.12), (1.12, 0.54, 0.12),
                    (0.84, 0.50, 0.10), (0.56, 0.44, 0.08), (0.30, 0.38, 0.06)]:
        f.puff(j(0, y, 0, 0.05), r, a, drift=0.05, spin=0.2, tint="haze")
    for _ in range(7):
        a = rng.uniform(0, math.tau)
        rad = rng.uniform(0.22, 0.46)
        f.puff((math.cos(a) * rad, rng.uniform(0.5, 1.75), math.sin(a) * rad * 0.5),
               rng.uniform(0.08, 0.15), rng.uniform(0.10, 0.26),
               drift=rng.uniform(0.09, 0.18), spin=0.8, rise=rng.uniform(0.05, 0.16))
    f.ember((-0.062, 1.735, -0.10), 0.045, 0.55)
    f.ember((0.058, 1.740, -0.10), 0.042, 0.55)
    return f


# ------------------------------------------------------------------ the ghul
def ghoul_figure(seed=11):
    """The ghul of pre-Islamic Arabia: the thing that waits off the road, takes the shape of a
    person to bring travellers close, and eats what it finds. Two layouts in one figure.

    **Lure** (`morph` 0): a crew member standing quietly down the corridor, facing away. Nothing
    is lit about it - it is a shape against the light at the far end, which is all anyone ever
    actually sees down a corridor. Upright, ordinary proportions, and - this is the point - it has
    legs,
    which the vulto never does. What it does not have is boots. The folklore is consistent that
    whatever else a ghul can change, it cannot hide its hooves; they are down there from the first
    frame, too small and too dark and pointed the wrong way, for anyone who looks.

    **True** (`morph` 1): the lure comes apart at the joints - the shoulders rise into a hunch
    above the head, the neck runs forward, the jaw carries on past where a face would stop, the
    arms lengthen until the hands are on the floor, and it settles over its meal. Two eyes open,
    the colour of something gone off, and they are the first light it has shown.

    The morph is per-puff, so it does not cut between two models: the person unfolds into it while
    you watch, and the hooves are the only part that does not move.
    """
    f = Figure(
        "ghoul",
        core=[0.030, 0.023, 0.018],      # carrion-dark: browner and heavier than the vulto's cold black
        haze=[0.105, 0.080, 0.062],      # dust, not violet
        embers_by_key={
            "eye": [0.62, 0.78, 0.14],   # sickly; the only light it ever shows, and only at the end
            # the hooves are the only part of it that is not smoke, so they are the only part that
            # takes the light - horn-coloured, and far too small to be boots
            "hoof": [0.155, 0.125, 0.095],
        },
        plateau=0.55,   # it has to pass for solid; the vulto does not
    )
    rng = random.Random(seed)

    def j(x, y, z, s):
        return (x + rng.uniform(-s, s), y + rng.uniform(-s, s), z + rng.uniform(-s, s))

    # --- head: upright and level, then dropped forward and forward again into a muzzle
    f.puff(j(0, 1.66, 0, 0.01), 0.235, 0.97, drift=0.018, spin=0.22,
           pos2=(0, 1.06, -0.44), size2=0.21)
    for i in range(3):
        f.puff(j(0, 1.70, 0.03, 0.05), 0.19, 0.72, drift=0.03, spin=0.4,
               pos2=(0, 1.12, -0.30 - i * 0.04), size2=0.175)
    # the jaw only exists in the true shape: it grows out of the face
    for i, d in enumerate([0.13, 0.24, 0.34]):
        f.puff(j(0, 1.60, -0.07, 0.02), 0.115 - i * 0.012, 0.12 if i == 0 else 0.0, drift=0.02,
               spin=0.3, pos2=(0, 1.00 - i * 0.015, -0.44 - d), size2=0.145 - i * 0.026)

    # --- shoulders: level and human, then hunched up over the head, which is the whole silhouette
    for sx in (-1, 1):
        f.puff(j(sx * 0.19, 1.44, 0, 0.02), 0.29, 0.96, drift=0.025, spin=0.3,
               pos2=(sx * 0.30, 1.33, -0.10), size2=0.33)
        f.puff(j(sx * 0.28, 1.35, 0, 0.03), 0.23, 0.88, drift=0.04, spin=0.45,
               pos2=(sx * 0.36, 1.22, -0.02), size2=0.23)
    f.puff((0, 1.52, 0), 0.27, 0.94, drift=0.02, pos2=(0, 1.36, 0.02), size2=0.27)

    # --- torso: a person's column, then a short compact barrel pitched forward over the meal
    for i, (y, r, a) in enumerate([(1.34, 0.29, 0.97), (1.24, 0.30, 0.97), (1.14, 0.30, 0.97),
                                   (1.04, 0.29, 0.96), (0.94, 0.28, 0.95), (0.84, 0.26, 0.93)]):
        f.puff(j(0, y, 0, 0.03), r, a, drift=0.028 + i * 0.005, spin=0.32,
               pos2=(0, 1.22 - i * 0.075, 0.10 - i * 0.030), size2=r * 1.12)

    # --- arms: hanging by the sides, then long enough to put the knuckles on the deck
    for sx in (-1, 1):
        for i, y in enumerate([1.30, 1.20, 1.10, 1.00, 0.90, 0.80]):
            f.puff(j(sx * (0.25 + i * 0.006), y, 0, 0.02), 0.165 - i * 0.008, 0.92 - i * 0.05,
                   drift=0.035 + i * 0.012, spin=0.5,
                   pos2=(sx * (0.34 + i * 0.018), 1.20 - i * 0.20, -0.18 - i * 0.045),
                   size2=0.17 - i * 0.012)
        # hands - claws down on the floor in the true shape, nothing much in the lure
        f.puff(j(sx * 0.27, 0.72, 0, 0.02), 0.115, 0.70, drift=0.05, spin=0.6,
               pos2=(sx * 0.40, 0.09, -0.44), size2=0.135)

    # --- legs: the lure has them, straight and ordinary; folded under in the true shape
    for sx in (-1, 1):
        for i, y in enumerate([0.76, 0.65, 0.54, 0.43, 0.32, 0.21]):
            f.puff(j(sx * 0.115, y, 0, 0.015), 0.155 - i * 0.008, 0.95 - i * 0.03,
                   drift=0.018, spin=0.3,
                   pos2=(sx * (0.17 + i * 0.022), 0.72 - i * 0.10, 0.24 - i * 0.04),
                   size2=0.165 - i * 0.008)

    # --- hooves. The tell. They are in both layouts, in the same place, at the same size: the one
    # thing about it that never changes and never looks right.
    for sx in (-1, 1):
        f.puff((sx * 0.115, 0.105, -0.01), 0.115, 1.0, drift=0.004, spin=0.04, tint="hoof",
               pos2=(sx * 0.145, 0.105, 0.05), size2=0.115)
        f.puff((sx * 0.118, 0.055, -0.05), 0.098, 1.0, drift=0.004, spin=0.04, tint="hoof",
               pos2=(sx * 0.148, 0.055, 0.01), size2=0.098)
        # the split toe, which is the detail nobody is meant to notice until they do
        for tx in (-1, 1):
            f.puff((sx * 0.115 + tx * 0.042, 0.028, -0.085), 0.062, 1.0, drift=0.003, spin=0.03,
                   tint="hoof", pos2=(sx * 0.145 + tx * 0.042, 0.028, -0.025), size2=0.062)

    # --- haze
    for y, r, a in [(1.60, 0.38, 0.09), (1.36, 0.48, 0.11), (1.10, 0.50, 0.11),
                    (0.84, 0.46, 0.10), (0.54, 0.40, 0.08), (0.26, 0.32, 0.06)]:
        f.puff(j(0, y, 0, 0.04), r, a, drift=0.045, spin=0.2, tint="haze",
               pos2=(0, y * 0.78, -0.12), size2=r * 1.15)

    # --- a few wisps, fewer than the vulto has: this one is meant to pass for solid
    for _ in range(4):
        a = rng.uniform(0, math.tau)
        rad = rng.uniform(0.20, 0.38)
        y = rng.uniform(0.8, 1.6)
        f.puff((math.cos(a) * rad, y, math.sin(a) * rad * 0.5), rng.uniform(0.07, 0.13),
               rng.uniform(0.08, 0.20), drift=rng.uniform(0.08, 0.15), spin=0.8,
               rise=rng.uniform(0.04, 0.12), pos2=(math.cos(a) * rad, y * 0.8, math.sin(a) * rad))

    # no lamp, no glow, nothing: until it turns, the only thing to see is the shape
    f.ember((-0.055, 1.665, -0.09), 0.040, 0.0, key="eye",
            pos2=(-0.055, 1.045, -0.55), size2=0.042, energy2=0.85)
    f.ember((0.052, 1.668, -0.09), 0.038, 0.0, key="eye",
            pos2=(0.052, 1.050, -0.55), size2=0.040, energy2=0.85)
    return f


FIGURES = {"corridor": corridor_figure, "ghoul": ghoul_figure}
