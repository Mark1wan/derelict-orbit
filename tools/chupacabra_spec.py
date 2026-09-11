"""The chupacabra: the thing on board that drinks.

Deliberately the **1995 Puerto Rican** one - the Canovanas sightings, the description Madelyne
Tolentino gave and every witness after her repeated - not the mangy Texas coyote the name got
attached to a decade later. That means: bipedal, about waist height on a grown adult, grey-green
and leathery, enormous black oval eyes with nothing in them, a row of spines down the back that
*move*, small clawed forelimbs held up against the chest, huge hind legs, and no tail. It does not
run. It hops, and the hops are far too long for the size of it.

What it is famous for is not the encounter. It is the evidence: livestock found in the morning,
not torn up, not eaten - drained, through two neat punctures, with nothing spilled. That is the
part this station gets. It feeds on whatever holds pressure: canisters, coolant drums, power
cells. You find it crouched over one with its head down, or you find the thing it emptied.

And in zero g a hopper is worse than a walker. It does not need a floor. It kicks off a wall and
crosses the corridor in one go.
"""

import math

from riglib import Rig, tip_of

MATERIALS = {
    # grey-green and leathery, and much lighter than the stalker: this one you are supposed to see
    "hide":   {"albedo": [0.115, 0.135, 0.100], "emission": [0, 0, 0], "roughness": 0.85},
    "mottle": {"albedo": [0.075, 0.090, 0.068], "emission": [0, 0, 0], "roughness": 0.9},
    "belly":  {"albedo": [0.165, 0.175, 0.150], "emission": [0, 0, 0], "roughness": 0.8},
    "spine":  {"albedo": [0.085, 0.070, 0.050], "emission": [0, 0, 0], "roughness": 0.6},
    "claw":   {"albedo": [0.180, 0.170, 0.145], "emission": [0, 0, 0], "roughness": 0.35},
    "fang":   {"albedo": [0.320, 0.305, 0.270], "emission": [0, 0, 0], "roughness": 0.4},
    # the eyes are the whole face: black, oval, wet, and far too big. They do not glow - they are
    # the one part of it that is darker than everything around it, which is worse
    "eye":    {"albedo": [0.020, 0.020, 0.024], "emission": [0, 0, 0], "roughness": 0.15},
    "maw":    {"albedo": [0.115, 0.030, 0.030], "emission": [0, 0, 0], "roughness": 0.7},
}

HIP_Y = 0.62

rig = Rig("chupacabra", MATERIALS)

# ---------------------------------------------------------------- skeleton
rig.bone("root", "", [0.0, HIP_Y, 0.0])
rig.bone("spine", "root", [0.0, 0.11, -0.02])
rig.bone("chest", "spine", [0.0, 0.13, -0.03])
rig.bone("neck", "chest", [0.0, 0.11, -0.05])
rig.bone("head", "neck", [0.0, 0.08, -0.05])
rig.bone("jaw", "head", [0.0, -0.03, -0.05])
rig.bone("crest_a", "chest", [0.0, 0.06, 0.06])      # the spines are on their own chain so they
rig.bone("crest_b", "crest_a", [0.0, 0.10, 0.02])    # can flatten and stand up


def _limbs(side, sx):
    rig.bone("clav_%s" % side, "chest", [sx * 0.055, 0.045, 0.0])
    rig.bone("arm_%s" % side, "clav_%s" % side, [sx * 0.055, -0.02, 0.0])
    rig.bone("fore_%s" % side, "arm_%s" % side, [0.0, -0.145, 0.0])
    rig.bone("hand_%s" % side, "fore_%s" % side, [0.0, -0.125, 0.0])
    rig.bone("hip_%s" % side, "root", [sx * 0.085, -0.03, 0.0])
    rig.bone("thigh_%s" % side, "hip_%s" % side, [0.0, -0.01, 0.0])
    rig.bone("shin_%s" % side, "thigh_%s" % side, [0.0, -0.29, 0.0])
    rig.bone("foot_%s" % side, "shin_%s" % side, [0.0, -0.30, 0.0])


rig.mirror_bones(_limbs)
SIDES = (("L", 1.0), ("R", -1.0))

# ---------------------------------------------------------------- body
# narrow chest, deep belly, the ribs showing through - it is always hungry, that is the point of it
rig.part("root", "sph", "hide", pos=(0, 0.02, 0), size=(0.195, 0.185, 0.185))
rig.part("spine", "sph", "hide", pos=(0, 0.05, 0), size=(0.210, 0.205, 0.195))
rig.part("chest", "sph", "hide", pos=(0, 0.05, -0.01), size=(0.240, 0.225, 0.210))
rig.part("chest", "cone", "hide", pos=(0, -0.04, 0), h=0.12, r=0.11, r2=0.13)
rig.part("spine", "sph", "belly", pos=(0, 0.04, -0.075), size=(0.150, 0.170, 0.085))
rig.part("chest", "sph", "belly", pos=(0, 0.04, -0.085), size=(0.160, 0.155, 0.080))
rig.part("root", "sph", "belly", pos=(0, 0.01, -0.075), size=(0.135, 0.135, 0.075))
for i in range(3):
    rig.part("chest", "box", "mottle", pos=(0, 0.02 + i * 0.045, -0.085), size=(0.20, 0.012, 0.10))
rig.scatter("chest", "mottle", (0, 0.05, 0.02), (0.13, 0.11, 0.10), 14, 0.026, 41, flatten=0.5)
rig.scatter("spine", "mottle", (0, 0.05, 0.02), (0.12, 0.10, 0.10), 12, 0.024, 42, flatten=0.5)
rig.scatter("root", "mottle", (0, 0.02, 0.02), (0.11, 0.09, 0.10), 10, 0.022, 43, flatten=0.5)

# the crest: a row of spines from the skull to the hips, standing in two ranks
rig.spines("crest_a", "spine", [(0, -0.02, 0.0), (0, 0.09, 0.01)], 5, 0.115, (-22, 0, 0), 51, thick=0.014)
rig.spines("crest_b", "spine", [(0, -0.01, 0.0), (0, 0.10, 0.01)], 5, 0.125, (-14, 0, 0), 52, thick=0.013)
rig.spines("spine", "spine", [(0, 0.0, 0.09), (0, 0.10, 0.09)], 4, 0.095, (-30, 0, 0), 53, thick=0.012)
rig.spines("root", "spine", [(0, -0.02, 0.09), (0, 0.06, 0.09)], 3, 0.075, (-40, 0, 0), 54, thick=0.011)
for s, sx in SIDES:      # a smaller rank down each flank
    rig.spines("chest", "spine", [(sx * 0.10, 0.0, 0.05), (sx * 0.12, 0.08, 0.06)], 3, 0.070,
               (-20, 0, sx * -35), 55 + int(sx), thick=0.010)

# ---------------------------------------------------------------- head
rig.part("neck", "cone", "hide", pos=(0, -0.01, 0), h=0.10, r=0.055, r2=0.05)
rig.part("head", "sph", "hide", pos=(0, 0.01, -0.01), size=(0.145, 0.145, 0.165))      # cranium
rig.part("head", "sph", "hide", pos=(0, -0.02, -0.10), size=(0.105, 0.090, 0.120))     # muzzle
rig.part("head", "cone", "hide", pos=(0, -0.025, -0.13), rot=(-90, 0, 0), h=0.07, r=0.042, r2=0.028)
rig.part("head", "sph", "belly", pos=(0, -0.045, -0.12), size=(0.07, 0.035, 0.10))
for s, sx in SIDES:
    # the eyes: oval, black, wrapped round the sides of the skull, and much too large for it
    rig.part("head", "sph", "eye", pos=(sx * 0.056, 0.020, -0.092), rot=(0, sx * 26, sx * -18),
             size=(0.062, 0.085, 0.078))
    rig.part("head", "sph", "hide", pos=(sx * 0.052, 0.055, -0.080), size=(0.075, 0.030, 0.085))
    rig.part("head", "sph", "mottle", pos=(sx * 0.022, -0.020, -0.160), size=(0.016, 0.014, 0.016))
# the two fangs that make the two holes, and nothing else worth calling teeth
rig.part("head", "cone", "fang", pos=(-0.028, -0.055, -0.135), rot=(172, 0, 6), h=0.055, r=0.010, r2=0.0)
rig.part("head", "cone", "fang", pos=(0.028, -0.055, -0.135), rot=(172, 0, -6), h=0.055, r=0.010, r2=0.0)
rig.part("jaw", "sph", "maw", pos=(0, -0.015, -0.07), size=(0.075, 0.030, 0.115))
rig.part("jaw", "sph", "hide", pos=(0, -0.025, -0.06), size=(0.085, 0.040, 0.125))
rig.spines("head", "spine", [(0, 0.09, 0.02), (0, 0.06, 0.08)], 4, 0.085, (-35, 0, 0), 61, thick=0.011)

# ---------------------------------------------------------------- limbs
for s, sx in SIDES:
    # forelimbs: short, thin, held up under the chin; the hands are all claw
    rig.part("clav_%s" % s, "sph", "hide", pos=(sx * 0.03, 0, 0), size=(0.09, 0.07, 0.08))
    rig.limb("arm_%s" % s, "hide", 0.145, 0.040, 0.028)
    rig.limb("fore_%s" % s, "hide", 0.125, 0.030, 0.022)
    rig.part("hand_%s" % s, "sph", "hide", pos=(0, -0.025, -0.005), size=(0.048, 0.055, 0.042))
    for f in range(3):
        rig.part("hand_%s" % s, "cone", "claw", pos=((-0.016 + f * 0.016) * sx, -0.050, -0.012),
                 rot=(20 + f * 4, 0, sx * (f - 1) * 12), h=0.062, r=0.008, r2=0.0)

    # hind legs: everything this thing has goes here. Long shin, long foot, claws that hold metal
    rig.part("hip_%s" % s, "sph", "hide", pos=(0, -0.02, 0.01), size=(0.135, 0.130, 0.145))
    rig.limb("thigh_%s" % s, "hide", 0.29, 0.072, 0.044)
    rig.limb("shin_%s" % s, "hide", 0.30, 0.046, 0.029)
    rig.part("thigh_%s" % s, "sph", "hide", pos=(0, -0.10, 0.01), size=(0.105, 0.21, 0.125))  # the spring
    rig.part("foot_%s" % s, "sph", "hide", pos=(0, -0.02, -0.05), size=(0.062, 0.045, 0.135))
    for f in range(3):
        rig.part("foot_%s" % s, "cone", "claw", pos=(sx * (-0.020 + f * 0.020), -0.035, -0.105),
                 rot=(112, 0, sx * (f - 1) * 14), h=0.070, r=0.010, r2=0.0)
    rig.part("foot_%s" % s, "cone", "claw", pos=(0, -0.030, 0.045), rot=(56, 0, 0), h=0.055, r=0.009, r2=0.0)
    rig.scatter("shin_%s" % s, "mottle", (0, -0.15, 0), (0.034, 0.12, 0.034), 7, 0.020, 70 + int(sx))


# ---------------------------------------------------------------- poses
def _perch(d):
    """Crouched on a surface with its weight back on the haunches, forelimbs off it, watching.
    This is the one you find it in: it was already here and it has already stopped what it was
    doing."""
    d["spine"] = [14, 0, 0]
    d["chest"] = [10, 0, 0]
    d["neck"] = [-26, -12, 0]
    d["head"] = [-14, -18, 4]
    d["crest_a"] = [-18, 0, 0]          # crest half down: it has not decided about you yet
    d["crest_b"] = [-12, 0, 0]
    Rig.both(d, "clav", [0, 0, 10])
    Rig.both(d, "arm", [-52, 0, -14])
    Rig.both(d, "fore", [104, 0, 0])
    Rig.both(d, "hand", [-46, 0, 0])
    Rig.both(d, "thigh", [96, 0, -8])
    Rig.both(d, "shin", [-128, 0, 0])
    Rig.both(d, "foot", [54, 0, 0])


def _alert(d):
    """Seen you. Head up, crest fully raised, weight loaded onto the back legs - the frame before
    it goes. A cat does this and it is charming. This is not a cat."""
    _perch(d)
    d["spine"] = [-6, 0, 0]
    d["chest"] = [-10, 0, 0]
    d["neck"] = [-34, 0, 0]
    d["head"] = [22, 0, 0]
    d["jaw"] = [16, 0, 0]
    d["crest_a"] = [26, 0, 0]           # every spine standing straight up
    d["crest_b"] = [22, 0, 0]
    Rig.both(d, "arm", [-64, 0, -20])
    Rig.both(d, "fore", [118, 0, 0])
    Rig.both(d, "thigh", [78, 0, -10])
    Rig.both(d, "shin", [-112, 0, 0])
    Rig.both(d, "foot", [40, 0, 0])


def _coil(d):
    """Wound right down onto itself, everything folded, a spring with the load on. It holds this
    for about a third of a second."""
    _alert(d)
    d["spine"] = [26, 0, 0]
    d["chest"] = [20, 0, 0]
    d["neck"] = [-46, 0, 0]
    d["head"] = [28, 0, 0]
    Rig.both(d, "arm", [-86, 0, -26])
    Rig.both(d, "fore", [132, 0, 0])
    Rig.both(d, "thigh", [128, 0, -6])
    Rig.both(d, "shin", [-152, 0, 0])
    Rig.both(d, "foot", [76, 0, 0])


def _leap(d):
    """Off the wall. Legs straight out behind, arms tucked in, head level and pointed where it is
    going. In a corridor with no floor this crosses four metres and does not slow down."""
    d["spine"] = [-16, 0, 0]
    d["chest"] = [-14, 0, 0]
    d["neck"] = [-22, 0, 0]
    d["head"] = [26, 0, 0]
    d["jaw"] = [10, 0, 0]
    d["crest_a"] = [-34, 0, 0]          # crest flat: it is not threatening anything, it is moving
    d["crest_b"] = [-28, 0, 0]
    Rig.both(d, "clav", [0, 0, 22])
    Rig.both(d, "arm", [-24, 0, -30])
    Rig.both(d, "fore", [128, 0, 0])
    Rig.both(d, "hand", [-30, 0, 0])
    Rig.both(d, "thigh", [-82, 0, -4])
    Rig.both(d, "shin", [26, 0, 0])
    Rig.both(d, "foot", [-46, 0, 0])


def _cling(d):
    """Flat against a wall - or a ceiling, this station has no opinion about which. Splayed wide,
    all four sets of claws in, head turned out of the plane to look at the room."""
    d["spine"] = [-8, 0, 0]
    d["chest"] = [-6, 0, 0]
    d["neck"] = [-48, 22, 0]
    d["head"] = [44, 30, 12]
    d["crest_a"] = [-30, 0, 0]
    d["crest_b"] = [-24, 0, 0]
    Rig.both(d, "clav", [0, 0, 32])
    Rig.both(d, "arm", [-96, 0, -62])   # arms out sideways, hands flat on the surface
    Rig.both(d, "fore", [52, 0, 0])
    Rig.both(d, "hand", [-28, 0, -20])
    Rig.both(d, "thigh", [88, 0, -46])  # knees out wide, the way anything flattened does it
    Rig.both(d, "shin", [-120, 0, 0])
    Rig.both(d, "foot", [56, 0, 0])


def _feed(d):
    """Head down on something that holds pressure, both hands on it, spines flat. It does not look
    up while it does this, which is the only reason anyone has ever got close to one."""
    d["spine"] = [-32, 0, 0]            # folded forward over the thing, not sitting back from it
    d["chest"] = [-30, 0, 0]
    d["neck"] = [-26, -6, 0]
    d["head"] = [-18, -8, 0]
    d["jaw"] = [24, 0, 0]
    d["crest_a"] = [-40, 0, 0]
    d["crest_b"] = [-34, 0, 0]
    Rig.both(d, "clav", [0, 0, 18])
    Rig.both(d, "arm", [-58, 0, -30])   # both hands on it, holding it against itself
    Rig.both(d, "fore", [72, 0, 0])
    Rig.both(d, "hand", [-40, 0, 0])
    Rig.both(d, "thigh", [104, 0, -12])
    Rig.both(d, "shin", [-136, 0, 0])
    Rig.both(d, "foot", [62, 0, 0])


def _scuttle(d):
    """Mid-scramble along a surface, out of phase left to right - the gait nobody ever describes
    well because it is over before you have finished seeing it."""
    _perch(d)
    d["spine"] = [20, 0, 8]
    d["neck"] = [-30, 16, 0]
    d["head"] = [-8, 22, -6]
    d["arm_L"] = [-88, 0, -22]
    d["fore_L"] = [64, 0, 0]
    d["arm_R"] = [-26, 0, -10]
    d["fore_R"] = [122, 0, 0]
    d["thigh_L"] = [128, 0, -10]
    d["shin_L"] = [-150, 0, 0]
    d["thigh_R"] = [58, 0, 14]
    d["shin_R"] = [-96, 0, 0]
    d["foot_R"] = [30, 0, 0]


def _peek(d):
    """Round the edge of something. The body is turned away down the side passage, low and pressed
    to the wall - most of it is behind the corner and stays there. What is out in the corridor is
    the head, craned right back over the shoulder, and the eyes. That is the whole encounter,
    nine times out of ten."""
    d["spine"] = [-14, 26, 0]           # body angled away, shoulders tucked in toward the wall
    d["chest"] = [-10, 22, 0]
    d["neck"] = [-28, 70, 0]            # the crane: most of the turn is in the neck
    d["head"] = [10, 64, -14]            # and the rest of it here, head tilted the way animals do
    d["crest_a"] = [-34, 0, 0]          # crest flat: it does not want to be a shape yet
    d["crest_b"] = [-28, 0, 0]
    Rig.both(d, "clav", [0, 0, 16])
    d["arm_L"] = [-74, 0, -34]          # one hand up on the edge it is looking round
    d["fore_L"] = [96, 0, 0]
    d["hand_L"] = [-52, 0, -18]
    d["arm_R"] = [-40, 0, -12]
    d["fore_R"] = [118, 0, 0]
    d["hand_R"] = [-40, 0, 0]
    Rig.both(d, "thigh", [112, 0, -10])  # folded right down: it is a lump at the bottom of a wall
    Rig.both(d, "shin", [-144, 0, 0])
    Rig.both(d, "foot", [66, 0, 0])


def _withdraw(d):
    """Going. Head coming back round to where the body already is, everything loading onto the
    legs. Half a second of this and the corner is empty."""
    _peek(d)
    d["spine"] = [-8, 12, 0]
    d["chest"] = [-6, 8, 0]
    d["neck"] = [-16, 24, 0]
    d["head"] = [0, 20, -4]
    d["crest_a"] = [18, 0, 0]           # crest up on the way out - it has decided about you
    d["crest_b"] = [14, 0, 0]
    d["arm_L"] = [-52, 0, -22]
    d["fore_L"] = [124, 0, 0]
    Rig.both(d, "thigh", [128, 0, -8])
    Rig.both(d, "shin", [-156, 0, 0])


rig.pose("perch", [0, 0, 0], [0, 0, 0], _perch)
rig.pose("alert", [0, 0, 0], [0, 0, 0], _alert)
rig.pose("coil", [0, 0, 0], [0, 0, 0], _coil)
rig.pose("leap", [0, 0.02, 0], [-34, 0, 0], _leap, airborne=True)
rig.pose("cling", [0, 0, 0], [0, 0, 0], _cling)
rig.pose("feed", [0, 0, 0], [0, 0, 0], _feed)
rig.pose("scuttle", [0, 0, 0], [0, 0, 0], _scuttle)
rig.pose("peek", [0, 0, 0], [0, 0, 0], _peek)
rig.pose("withdraw", [0, 0, 0], [0, 0, 0], _withdraw)

POSE_ORDER = ["peek", "withdraw", "alert", "coil", "leap", "cling", "perch", "feed", "scuttle"]


def spec():
    rig.settle()
    return rig.spec()
