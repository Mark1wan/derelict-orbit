"""The night stalker's rig: bones, the parts hung off them, and the poses it snaps between.

This is the single source of truth for the creature. `tools/build_creature.py` writes it to
kit/creature_rig.json, `scripts/creature.gd` builds the thing in Godot from that file, and
tools/render_creature.py draws the same data - so the reference images cannot drift from the
asset the game shows.

Conventions: 1 unit = 1 m, Y up, the creature faces -Z (Godot's forward), origin on the floor
under it. Limb bones run down their own local -Y, so a rotation of 0 is a straight limb and the
"broken" angles in the poses are honest joint angles, not fudged offsets.
"""

import math
import random

from render3d import euler, mat_mul, translate, xform


def tip_of(base, rot, length):
    """Where a `cone` part of this length, at this rotation, ends - so the next segment of a horn
    or a claw can start exactly there instead of floating near it."""
    d = xform(euler(rot), (0.0, length, 0.0))
    return (base[0] + d[0], base[1] + d[1], base[2] + d[2])

# ---------------------------------------------------------------- materials
# albedo, emission (added after shading), roughness. Kept extremely dark on purpose: the thing
# has to disappear into an unlit corridor and only resolve when the flashlight is on it.
MATERIALS = {
    "hide":   {"albedo": [0.052, 0.048, 0.052], "emission": [0, 0, 0], "roughness": 1.0},
    "belly":  {"albedo": [0.085, 0.072, 0.078], "emission": [0, 0, 0], "roughness": 0.95},
    "hair":   {"albedo": [0.028, 0.026, 0.030], "emission": [0, 0, 0], "roughness": 1.0},
    "horn":   {"albedo": [0.105, 0.095, 0.088], "emission": [0, 0, 0], "roughness": 0.75},
    "claw":   {"albedo": [0.135, 0.125, 0.115], "emission": [0, 0, 0], "roughness": 0.45},
    "tooth":  {"albedo": [0.320, 0.300, 0.265], "emission": [0, 0, 0], "roughness": 0.55},
    # painted marks: dark wine, barely self-lit, so they read as paint by torchlight and as a
    # faint smear of colour in the dark rather than as glowing decals
    "rune":   {"albedo": [0.115, 0.012, 0.030], "emission": [0.085, 0.004, 0.014], "roughness": 0.85},
    "spore":  {"albedo": [0.175, 0.195, 0.120], "emission": [0.030, 0.038, 0.014], "roughness": 0.9},
    "eye":    {"albedo": [0.400, 0.040, 0.020], "emission": [0.900, 0.070, 0.035], "roughness": 0.3},
}

# ---------------------------------------------------------------- skeleton
# (name, parent, offset from the parent's origin)
HIP_Y = 0.98

BONES = [
    ("root",    "",        [0.0, HIP_Y, 0.0]),
    ("spine_a", "root",    [0.0, 0.16, 0.0]),
    ("spine_b", "spine_a", [0.0, 0.18, 0.0]),
    ("chest",   "spine_b", [0.0, 0.18, 0.0]),
    ("neck",    "chest",   [0.0, 0.17, -0.01]),
    ("head",    "neck",    [0.0, 0.11, -0.02]),
    ("jaw",     "head",    [0.0, -0.03, -0.06]),
    ("tail_0",  "root",    [0.0, 0.02, 0.12]),
    ("tail_1",  "tail_0",  [0.0, 0.0, 0.15]),
    ("tail_2",  "tail_1",  [0.0, 0.0, 0.15]),
    ("tail_3",  "tail_2",  [0.0, 0.0, 0.14]),
    ("tail_4",  "tail_3",  [0.0, 0.0, 0.13]),
    ("tail_5",  "tail_4",  [0.0, 0.0, 0.12]),
]
for s, sx in (("L", 1.0), ("R", -1.0)):
    BONES += [
        ("clav_%s" % s,  "chest",        [sx * 0.07, 0.09, 0.0]),
        ("arm_%s" % s,   "clav_%s" % s,  [sx * 0.11, -0.02, 0.0]),
        ("fore_%s" % s,  "arm_%s" % s,   [0.0, -0.31, 0.0]),
        ("hand_%s" % s,  "fore_%s" % s,  [0.0, -0.29, 0.0]),
        ("hip_%s" % s,   "root",         [sx * 0.11, -0.05, 0.0]),
        ("thigh_%s" % s, "hip_%s" % s,   [0.0, -0.02, 0.0]),
        ("shin_%s" % s,  "thigh_%s" % s, [0.0, -0.38, 0.0]),
        ("foot_%s" % s,  "shin_%s" % s,  [0.0, -0.40, 0.0]),
    ]

SIDES = (("L", 1.0), ("R", -1.0))

# ---------------------------------------------------------------- parts
PARTS = []


def part(bone, shape, mat, pos=(0, 0, 0), rot=(0, 0, 0), size=(0.1, 0.1, 0.1), r=0.0, h=0.0, r2=None):
    PARTS.append({"bone": bone, "shape": shape, "mat": mat, "pos": list(pos), "rot": list(rot),
                  "size": list(size), "r": r, "h": h, "r2": r if r2 is None else r2})


def limb(bone, mat, length, r_top, r_bot):
    """A tapered segment running down the bone's local -Y."""
    part(bone, "cone", mat, pos=(0, -length, 0), rot=(0, 0, 0), h=length, r=r_bot, r2=r_top)


def quills(bone, mat, n, along, spread, length, seed, rot_base=(0, 0, 0)):
    """A patch of coarse hair: thin tapered spines, scattered but baked in so the model is fixed."""
    rng = random.Random(seed)
    for _ in range(n):
        t = rng.uniform(0.0, 1.0)
        pos = [along[i][0] + (along[i][1] - along[i][0]) * t + rng.uniform(-spread, spread) for i in range(3)]
        rot = [rot_base[0] + rng.uniform(-22, 22), rot_base[1] + rng.uniform(-22, 22), rot_base[2] + rng.uniform(-22, 22)]
        part(bone, "cone", mat, pos=pos, rot=rot, h=length * rng.uniform(0.6, 1.35), r=0.007, r2=0.0)


def rune(bone, pos, rot, scale=1.0, seed=0):
    """A painted mark: a spine stroke with two or three bars across it, pressed onto the hide."""
    rng = random.Random(seed)
    t = 0.009
    part(bone, "box", "rune", pos=pos, rot=rot, size=(t, 0.11 * scale, t * 1.6))
    for i in range(rng.randint(2, 3)):
        y = 0.045 * scale - i * 0.042 * scale
        w = rng.uniform(0.035, 0.075) * scale
        skew = rng.uniform(-18, 18)
        part(bone, "box", "rune", pos=(pos[0], pos[1] + y, pos[2]), rot=(rot[0], rot[1], rot[2] + skew),
             size=(w, t, t * 1.6))
    if rng.random() < 0.5:
        part(bone, "box", "rune", pos=(pos[0], pos[1] - 0.055 * scale, pos[2]),
             rot=(rot[0], rot[1], rot[2] + 45), size=(0.05 * scale, t, t * 1.6))


# torso: emaciated, ribbed, the belly plate paler than the back
part("root", "sph", "hide", pos=(0, 0.03, 0), size=(0.30, 0.26, 0.24))
part("root", "cone", "hide", pos=(0, 0.02, 0), h=0.16, r=0.13, r2=0.12)
part("spine_a", "sph", "hide", pos=(0, 0.09, 0), size=(0.27, 0.30, 0.22))
part("spine_a", "cone", "hide", pos=(0, -0.02, 0), h=0.20, r=0.12, r2=0.13)
part("spine_b", "sph", "hide", pos=(0, 0.09, 0), size=(0.31, 0.30, 0.24))
part("spine_b", "cone", "hide", pos=(0, -0.02, 0), h=0.20, r=0.13, r2=0.15)
part("chest", "sph", "hide", pos=(0, 0.05, 0), size=(0.38, 0.30, 0.26))
part("chest", "cone", "hide", pos=(0, -0.02, 0), h=0.16, r=0.15, r2=0.17)
part("chest", "sph", "belly", pos=(0, 0.03, -0.08), size=(0.26, 0.26, 0.14))
part("spine_a", "sph", "belly", pos=(0, 0.09, -0.07), size=(0.22, 0.26, 0.12))
for i in range(4):                      # ribs pressing through the hide
    y = 0.01 + i * 0.055
    w = 0.31 - i * 0.015
    part("spine_b" if i < 2 else "chest", "box", "hide",
         pos=(0, y if i < 2 else y - 0.11, -0.035), size=(w, 0.016, 0.15))
for i in range(5):                      # spine knuckles down the back
    part("spine_b" if i < 3 else "chest", "sph", "hide",
         pos=(0, 0.02 + (i % 3) * 0.07, 0.10), size=(0.05, 0.05, 0.05))

# hair: heaviest over the shoulders, back and hips
quills("chest", "hair", 26, [(-0.16, 0.16), (-0.02, 0.14), (0.06, 0.12)], 0.03, 0.16, 1, (-30, 0, 0))
quills("spine_b", "hair", 22, [(-0.13, 0.13), (0.0, 0.16), (0.06, 0.12)], 0.03, 0.14, 2, (-25, 0, 0))
quills("root", "hair", 18, [(-0.12, 0.12), (-0.02, 0.10), (0.05, 0.12)], 0.03, 0.12, 3, (-20, 0, 0))
quills("neck", "hair", 14, [(-0.06, 0.06), (0.0, 0.14), (0.03, 0.07)], 0.02, 0.13, 4, (-40, 0, 0))

# neck and head: humanoid skull, soft lizard snout, horns sweeping down past the jaw
limb("neck", "hide", 0.0, 0, 0)
part("neck", "cone", "hide", pos=(0, 0.0, 0), h=0.13, r=0.055, r2=0.05)
part("head", "sph", "hide", pos=(0, 0.03, 0.01), size=(0.19, 0.20, 0.22))       # cranium
part("head", "sph", "hide", pos=(0, -0.005, -0.10), size=(0.155, 0.145, 0.18))  # muzzle root
part("head", "cone", "hide", pos=(0, -0.015, -0.15), rot=(-90, 0, 0), h=0.14, r=0.062, r2=0.030)
part("head", "sph", "hide", pos=(0, -0.015, -0.28), size=(0.06, 0.05, 0.05))    # nose pad
part("head", "sph", "belly", pos=(0, -0.05, -0.17), size=(0.10, 0.05, 0.16))    # soft snout underside
part("head", "box", "hide", pos=(0, 0.085, -0.105), rot=(-16, 0, 0), size=(0.17, 0.035, 0.11))  # brow
for s, sx in SIDES:
    part("head", "sph", "eye", pos=(sx * 0.070, 0.040, -0.155), size=(0.034, 0.028, 0.028))
    # horn: a thick root sweeping out from the temple, then a tip curving back down past the jaw
    # a ram's curve: up off the temple, over, then down the side of the face past the jaw
    h_base = (sx * 0.072, 0.105, 0.030)
    segs = [((10, 0, sx * -58), 0.080, 0.046, 0.037),
            ((6, 0, sx * -112), 0.085, 0.037, 0.028),
            ((0, 0, sx * -150), 0.090, 0.028, 0.018),
            ((-6, 0, sx * -178), 0.095, 0.018, 0.003)]
    p = h_base
    for rot, ln, r0, r1 in segs:
        part("head", "cone", "horn", pos=p, rot=rot, h=ln, r=r0, r2=r1)
        p = tip_of(p, rot, ln)
    quills("head", "hair", 6, [(sx * 0.02, sx * 0.09), (0.10, 0.16), (0.02, 0.10)], 0.02, 0.10, 5 + int(sx), (-35, 0, 0))
part("jaw", "sph", "hide", pos=(0, -0.02, -0.10), size=(0.12, 0.05, 0.19))
part("jaw", "sph", "belly", pos=(0, -0.035, -0.09), size=(0.09, 0.03, 0.15))
for i in range(5):                      # teeth, upper and lower
    x = -0.045 + i * 0.0225
    part("head", "cone", "tooth", pos=(x, -0.045, -0.14 - abs(x)), rot=(180, 0, 0), h=0.035, r=0.010, r2=0.0)
    part("jaw", "cone", "tooth", pos=(x, -0.005, -0.13 - abs(x)), h=0.030, r=0.009, r2=0.0)

# arms: long, thin, clawed
for s, sx in SIDES:
    part("clav_%s" % s, "sph", "hide", pos=(sx * 0.05, 0.0, 0.0), size=(0.14, 0.09, 0.12))
    limb("arm_%s" % s, "hide", 0.31, 0.062, 0.042)
    limb("fore_%s" % s, "hide", 0.29, 0.044, 0.032)
    quills("fore_%s" % s, "hair", 10, [(-0.02, 0.02), (-0.26, -0.04), (0.02, 0.03)], 0.02, 0.09, 10 + int(sx), (0, 0, sx * 40))
    part("hand_%s" % s, "sph", "hide", pos=(0, -0.05, -0.01), size=(0.085, 0.10, 0.07))
    for f in range(4):                  # four long claws instead of fingers
        fx = (-0.03 + f * 0.02) * sx
        part("hand_%s" % s, "cone", "claw", pos=(fx, -0.095, -0.02 - abs(f - 1.5) * 0.004),
             rot=(18 + f * 3, 0, sx * (f - 1.5) * 9), h=0.115, r=0.012, r2=0.0)
    part("hand_%s" % s, "cone", "claw", pos=(sx * 0.045, -0.055, 0.02), rot=(0, 0, sx * 62), h=0.075, r=0.011, r2=0.0)

# legs: digitigrade, spore growths up the shin
for s, sx in SIDES:
    part("hip_%s" % s, "sph", "hide", pos=(0, -0.02, 0.0), size=(0.15, 0.14, 0.16))
    limb("thigh_%s" % s, "hide", 0.38, 0.085, 0.050)
    limb("shin_%s" % s, "hide", 0.40, 0.052, 0.034)
    quills("thigh_%s" % s, "hair", 12, [(-0.03, 0.03), (-0.33, -0.05), (0.03, 0.05)], 0.02, 0.11, 20 + int(sx), (-15, 0, 0))
    rng = random.Random(30 + int(sx))
    for _ in range(9):                  # spores: pale growths clustered on the shin
        t = rng.uniform(0.1, 0.95)
        a = rng.uniform(0, math.tau)
        rr = rng.uniform(0.016, 0.032)
        part("shin_%s" % s, "sph", "spore",
             pos=(math.cos(a) * 0.035, -0.40 * t, math.sin(a) * 0.035), size=(rr, rr * 0.8, rr))
    part("foot_%s" % s, "sph", "hide", pos=(0, -0.03, -0.03), size=(0.09, 0.07, 0.14))
    for f in range(3):
        part("foot_%s" % s, "cone", "claw", pos=(sx * (-0.025 + f * 0.025), -0.05, -0.10),
             rot=(115, 0, sx * (f - 1) * 12), h=0.09, r=0.013, r2=0.0)
    part("foot_%s" % s, "cone", "claw", pos=(0, -0.04, 0.06), rot=(58, 0, 0), h=0.07, r=0.012, r2=0.0)

# tail: tapering, quilled, ending in a hooked spike
TAIL_R = [0.075, 0.062, 0.050, 0.040, 0.031, 0.024]
for i in range(6):
    b = "tail_%d" % i
    nxt = TAIL_R[i + 1] if i + 1 < len(TAIL_R) else 0.014
    part(b, "cone", "hide", pos=(0, 0, 0), rot=(-90, 0, 0), h=0.15 if i < 3 else 0.13, r=TAIL_R[i], r2=nxt)
    if i >= 1:
        quills(b, "hair", 5, [(-0.02, 0.02), (0.0, 0.04), (0.02, 0.12)], 0.015, 0.08, 40 + i, (-60, 0, 0))
part("tail_5", "cone", "claw", pos=(0, 0.01, 0.12), rot=(-115, 0, 0), h=0.10, r=0.016, r2=0.0)

# runes: painted down the belly, across the chest, along the arms, the thigh and the tail
rune("chest", (0, 0.06, -0.115), (0, 0, 0), 1.15, 1)
rune("spine_a", (0, 0.09, -0.105), (0, 0, 0), 1.0, 2)
rune("root", (0, 0.03, -0.10), (0, 0, 0), 0.9, 3)
rune("spine_b", (0, 0.08, 0.11), (0, 180, 0), 1.0, 4)       # one between the shoulder blades
rune("head", (0, 0.10, -0.135), (-35, 0, 0), 0.55, 5)       # across the brow
for s, sx in SIDES:
    rune("arm_%s" % s, (sx * 0.065, -0.16, 0), (0, sx * 90, 0), 0.8, 6 + int(sx))
    rune("thigh_%s" % s, (sx * 0.085, -0.18, 0), (0, sx * 90, 0), 0.9, 8 + int(sx))
    rune("fore_%s" % s, (0, -0.15, -0.045), (0, 0, 0), 0.6, 12 + int(sx))
rune("tail_2", (0, 0.055, 0.07), (-90, 0, 0), 0.7, 20)


# ---------------------------------------------------------------- poses
# Joint angles in degrees, XYZ, applied on top of the rest skeleton. Every pose also carries a
# root offset, because the thing is a different height on all fours than it is standing.
def both(d, bone, rot, mirror=True):
    """Set a left/right pair. Mirroring negates the Y and Z angles, as a real mirror does."""
    d["%s_L" % bone] = list(rot)
    d["%s_R" % bone] = [rot[0], -rot[1], -rot[2]] if mirror else list(rot)


def pose(name, root_pos, root_rot, builder):
    d = {"root": list(root_rot)}
    builder(d)
    POSES[name] = {"root_pos": list(root_pos), "bones": d}


POSES = {}


def _upright(d):
    """Dead still, too tall, head hung forward and turned a few degrees too far."""
    d["spine_a"] = [-3, 0, 0]
    d["spine_b"] = [-4, 2, 0]
    d["chest"] = [6, 0, 0]
    d["neck"] = [16, -8, 0]
    d["head"] = [-26, -14, 4]
    d["jaw"] = [4, 0, 0]
    both(d, "clav", [0, 0, 6])
    both(d, "arm", [8, 0, -6])
    both(d, "fore", [24, 0, 0])
    both(d, "hand", [10, 0, 0])
    both(d, "thigh", [-4, 0, 1])
    both(d, "shin", [8, 0, 0])
    both(d, "foot", [-6, 0, 0])
    for i, a in enumerate([26, 22, 16, 8, -6, -20]):
        d["tail_%d" % i] = [a, 4 if i % 2 else -4, 0]


def _crawl_a(d):
    """The walk. Belly up, head first - which is only possible if the body is also turned through
    180 degrees, so its left hand plants on your right. That mirror is what makes the real thing
    look wrong before you can say why. The spine arches back so the face leads, chin first."""
    d["spine_a"] = [-16, 0, 0]
    d["spine_b"] = [-18, 0, 0]
    d["chest"] = [-16, 0, 0]
    d["neck"] = [-34, 8, 0]
    d["head"] = [-40, 12, 0]          # head hangs back off the neck, looking the way it travels
    d["jaw"] = [16, 0, 0]
    both(d, "clav", [0, 0, -8])
    d["arm_L"] = [-104, 0, -22]       # planted, taking the weight
    d["fore_L"] = [34, 0, 0]
    d["hand_L"] = [-40, 0, 0]
    d["arm_R"] = [-46, 0, 26]         # swinging through
    d["fore_R"] = [72, 0, 0]
    d["hand_R"] = [-22, 0, 0]
    d["thigh_L"] = [-58, 0, -18]      # knee up in the air, the way a spider-walk folds
    d["shin_L"] = [104, 0, 0]
    d["foot_L"] = [-44, 0, 0]
    d["thigh_R"] = [-104, 0, 20]
    d["shin_R"] = [72, 0, 0]
    d["foot_R"] = [-28, 0, 0]
    for i, a in enumerate([28, 22, 14, 6, -8, -18]):
        d["tail_%d" % i] = [a, 10 if i % 2 else -8, 0]


def _crawl_b(d):
    """The other half of the stride, with the limbs swapped and the head snapped the other way."""
    _crawl_a(d)
    for a, b in (("arm_L", "arm_R"), ("fore_L", "fore_R"), ("hand_L", "hand_R"),
                 ("thigh_L", "thigh_R"), ("shin_L", "shin_R"), ("foot_L", "foot_R")):
        d[a], d[b] = [d[b][0], -d[b][1], -d[b][2]], [d[a][0], -d[a][1], -d[a][2]]
    d["neck"] = [-38, -10, 0]
    d["head"] = [-22, -14, -6]
    d["spine_b"] = [-46, -8, 0]


def _dislocate(d):
    """Mid-step, the moment a joint goes the way it should not: the right leg snapped through its
    own stop and now carries weight backwards, hip rolled out of its socket."""
    _crawl_a(d)
    d["hip_R"] = [0, -22, -16]
    d["thigh_R"] = [-152, 0, 34]        # driven past straight, the wrong side of the hip
    d["shin_R"] = [26, 0, 0]
    d["foot_R"] = [-84, 0, 0]
    d["arm_L"] = [-132, 0, -46]
    d["fore_L"] = [96, 0, 0]
    d["spine_b"] = [-18, -16, 0]
    d["head"] = [-52, 40, 14]
    d["jaw"] = [28, 0, 0]


def _contort(d):
    """Folded into a knot against a wall, limbs over the torso, head turned right round."""
    d["spine_a"] = [58, 20, 0]
    d["spine_b"] = [52, 22, 0]
    d["chest"] = [40, 24, 0]
    d["neck"] = [-30, 70, 0]
    d["head"] = [-40, 86, 22]
    d["jaw"] = [8, 0, 0]
    both(d, "clav", [0, 0, 24])
    d["arm_L"] = [-142, 0, -58]
    d["fore_L"] = [138, 0, 0]
    d["hand_L"] = [-40, 0, 20]
    d["arm_R"] = [-158, 0, 40]
    d["fore_R"] = [146, 0, 0]
    d["hand_R"] = [-30, 0, -20]
    d["thigh_L"] = [140, 0, -34]
    d["shin_L"] = [-150, 0, 0]
    d["foot_L"] = [44, 0, 0]
    d["thigh_R"] = [132, 0, 30]
    d["shin_R"] = [-156, 0, 0]
    d["foot_R"] = [40, 0, 0]
    for i, a in enumerate([-50, -40, -30, -20, -10, 30]):
        d["tail_%d" % i] = [a, -16, 0]


def _freeze(d):
    """Caught in the beam: it was mid-glitch when the light landed and it has not finished."""
    _upright(d)
    d["spine_b"] = [-10, 26, 0]
    d["chest"] = [4, 30, 0]
    d["neck"] = [-14, 46, 0]
    d["head"] = [10, 62, 84]            # head cocked flat onto its side
    d["jaw"] = [22, 0, 0]
    d["arm_L"] = [-168, 0, -18]
    d["fore_L"] = [22, 0, 0]
    d["hand_L"] = [-30, 0, 0]
    d["arm_R"] = [26, 0, -14]
    d["fore_R"] = [96, 0, 0]
    d["hand_R"] = [-46, 0, 0]
    d["thigh_R"] = [-30, 0, 6]
    d["shin_R"] = [46, 0, 0]
    for i, a in enumerate([-14, -6, 8, 20, 26, 10]):
        d["tail_%d" % i] = [a, 22 if i % 2 else -18, 0]


def _lunge(d):
    """The jumpscare: off the ground, folded open, everything pointed at your face."""
    d["spine_a"] = [-28, 0, 0]
    d["spine_b"] = [-26, 0, 0]
    d["chest"] = [-22, 0, 0]
    d["neck"] = [-26, 0, 0]
    d["head"] = [-18, 0, 0]
    d["jaw"] = [42, 0, 0]
    both(d, "clav", [0, 0, -20])
    both(d, "arm", [-128, 0, -40])
    both(d, "fore", [42, 0, 0])
    both(d, "hand", [-30, 0, 0])
    both(d, "thigh", [96, 0, -16])
    both(d, "shin", [-116, 0, 0])
    both(d, "foot", [60, 0, 0])
    for i, a in enumerate([-40, -34, -26, -16, -6, 4]):
        d["tail_%d" % i] = [a, 0, 0]


def _coil(d):
    """Waiting: curled on a wall, tail up, head tucked under - the shape you mistake for a bundle."""
    d["spine_a"] = [40, 0, 0]
    d["spine_b"] = [44, 0, 0]
    d["chest"] = [46, 0, 0]
    d["neck"] = [40, 0, 0]
    d["head"] = [34, 16, 0]
    both(d, "clav", [0, 0, 16])
    both(d, "arm", [-150, 0, -30])
    both(d, "fore", [150, 0, 0])
    both(d, "hand", [-20, 0, 0])
    both(d, "thigh", [132, 0, -12])
    both(d, "shin", [-148, 0, 0])
    both(d, "foot", [50, 0, 0])
    for i, a in enumerate([-70, -50, -34, -20, -8, 6]):
        d["tail_%d" % i] = [a, 0, 0]


pose("upright", [0, 0, 0], [0, 0, 0], _upright)
pose("crawl_a", [0, -0.40, 0], [92, 180, 0], _crawl_a)
pose("crawl_b", [0, -0.40, 0], [92, 180, 0], _crawl_b)
pose("dislocate", [0, -0.38, 0], [88, 180, 0], _dislocate)
pose("contort", [0, -0.30, 0], [14, 0, 0], _contort)
pose("freeze", [0, -0.02, 0], [0, 0, 0], _freeze)
pose("lunge", [0, -0.12, 0], [72, 0, 0], _lunge)
pose("coil", [0, -0.52, 0], [30, 0, 0], _coil)


def _pose_min_y(pose):
    """Lowest point of the posed model, by walking the same forward kinematics the game does."""
    bones = {n: (p, o) for n, p, o in BONES}
    xf = {}
    lo = 1e9
    for name, parent, offset in BONES:
        local = mat_mul(translate(offset), euler(pose["bones"].get(name, [0, 0, 0])))
        if name == "root":
            local = mat_mul(translate(pose["root_pos"]), local)
        xf[name] = local if not parent else mat_mul(xf[parent], local)
    for p in PARTS:
        m = mat_mul(xf[p["bone"]], mat_mul(translate(p["pos"]), euler(p["rot"])))
        if p["shape"] == "box":
            ext = [v / 2 for v in p["size"]]
            corners = [(x * ext[0], y * ext[1], z * ext[2]) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        elif p["shape"] == "sph":
            ext = [v / 2 for v in p["size"]]
            corners = [(x * ext[0], y * ext[1], z * ext[2]) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        else:
            r = max(p["r"], p["r2"])
            corners = [(x * r, y, z * r) for x in (-1, 1) for y in (0.0, p["h"]) for z in (-1, 1)]
        for cpt in corners:
            lo = min(lo, xform(m, cpt)[1])
    return lo


def settle(clearance=0.0):
    """Drop or lift each pose so it rests on the floor. `AIRBORNE` poses keep their own height -
    a lunge is supposed to be off the ground."""
    for name, p in POSES.items():
        if name in AIRBORNE:
            continue
        p["root_pos"][1] -= _pose_min_y(p) - clearance


AIRBORNE = {"lunge"}


def spec():
    settle()
    return {
        "materials": MATERIALS,
        "bones": [{"name": n, "parent": p, "offset": o} for n, p, o in BONES],
        "parts": PARTS,
        "poses": POSES,
    }
