#!/usr/bin/env python3
"""Builds the two rooms added after the original kit: kit/room_comms.glb and kit/room_washroom.glb.

The eight original rooms were delivered as finished .glb files; their generator is not in this
repository. Their shell is, though - every one of them is the same 12 x 12 m box (walls, ribs,
panelling, floor, ceiling, light strips, pipe runs, doorway on -Z) with a different fit-out
standing in it. So the shell is lifted straight out of the kit: the triangles that the six plainly
walled rooms (control, power, plant, laboratory, gym, server) all share, exactly, are the shell.
The observation deck (glazed) and the EVA room (hatch) are left out of that vote because their
walls differ. That keeps the new rooms identical to the old ones everywhere the fit-out is not.

The fit-out on top is built from kitlib primitives with the kit's own material names, so
scripts/palette.gd maps them onto the game's textured materials with no changes.

    python3 tools/build_extra_rooms.py            # writes kit/room_comms.glb, kit/room_washroom.glb
    python3 tools/build_extra_rooms.py --check    # ...and re-parses both, checking bounds

Room frame (same as the kit): floor at y = 0, ceiling 3.6, walls' inner face at +-5.5 with the
panelling about 10 cm proud of that, the doorway on the -Z wall (x within +-1.5). The area inside
the doorway stays clear (tools and the wake point are put there) and the door wall is left bare
for the task terminals at x = +-2.65 / +-4.2.

The room-specific numbers the game needs (where the stall is, where the console hangs) are
repeated in scripts/washroom.gd and scripts/station.gd; the constants below are the source.
"""

import argparse
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitlib import Mesh, write_glb, translate, rotate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(ROOT, "kit")
SHELL_FROM = ["control", "power", "plant", "laboratory", "exercise", "server"]

# ---------------------------------------------------------------- washroom numbers
STALL_FRONT = 3.35          # z of the stall fronts (the door line)
STALL_BACK = 5.32           # z where the partitions meet the back wall's ribs
PART_LO = 0.14              # partitions stand off the floor like any public stall...
PART_HI = 2.30              # ...and stop well short of the 3.6 m ceiling
STALLS = [-0.8, 0.8]        # stall centres on x; the +x one is the working stall (runtime door)
STALL_HALF = 0.8            # half the stall width, partition centre to partition centre
DOOR_HALF = 0.4             # half the door opening
TOILET_Z = 4.95             # centre of the bowl

# ---------------------------------------------------------------- comms numbers
CONSOLE_Z = 5.18            # the uplink console hangs on the back wall here (station.gd)


# ---------------------------------------------------------------- reading the shell
def _read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + jlen])
    boff = 20 + jlen
    blen = struct.unpack_from("<I", data, boff)[0]
    return js, data[boff + 8:boff + 8 + blen]


def _accessor(js, blob, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[a["componentType"]]
    stride = bv.get("byteStride", struct.calcsize(fmt) * n)
    out = []
    for k in range(a["count"]):
        v = struct.unpack_from("<" + fmt * n, blob, off + k * stride)
        out.append(v if n > 1 else v[0])
    return out


def _triangles(path):
    """material -> set of triangles, each three rounded (x, y, z) corners in file order."""
    js, blob = _read_glb(path)
    out = {}
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            mat = js["materials"][prim["material"]]["name"]
            pos = _accessor(js, blob, prim["attributes"]["POSITION"])
            idx = _accessor(js, blob, prim["indices"]) if "indices" in prim else list(range(len(pos)))
            tris = out.setdefault(mat, set())
            for i in range(0, len(idx), 3):
                tris.add(tuple(tuple(round(c, 4) for c in pos[idx[i + k]]) for k in range(3)))
    return out


def shell():
    """The triangles every plainly walled room in the kit has in common: the bare room."""
    rooms = [_triangles(os.path.join(KIT, "room_%s.glb" % r)) for r in SHELL_FROM]
    common = {}
    for mat, tris in rooms[0].items():
        s = set(tris)
        for other in rooms[1:]:
            s &= other.get(mat, set())
        if s:
            common[mat] = sorted(s)       # sorted so the output is byte-for-byte repeatable
    return common


def add_shell(m, sh):
    for mat, tris in sh.items():
        for a, b, c in tris:
            m.tri(mat, a, b, c)


# ---------------------------------------------------------------- small parts
def leds(m, x0, x1, y0, y1, z, cols, rows, face=-1, axis="z", seed=1):
    """A grid of little status lamps on a face. `axis` is the face's normal axis."""
    k = seed
    for r in range(rows):
        for c in range(cols):
            k = (k * 1103515245 + 12345) & 0x7FFFFFFF
            mat = ("Light_Green", "Light_Data", "Light_Green", "Hull_Dark")[k % 4]
            u = x0 + (x1 - x0) * (c + 0.5) / cols
            v = y0 + (y1 - y0) * (r + 0.5) / rows
            if axis == "z":
                m.box(mat, (u, v, z + face * 0.008), (0.035, 0.018, 0.016))
            else:
                m.box(mat, (z + face * 0.008, v, u), (0.016, 0.018, 0.035))


def screen(m, center, size, tilt=0.0, facing=-1):
    """A bezel with a lit face, tilted back by `tilt` radians, facing -z (or +z)."""
    cx, cy, cz = center
    w, h = size
    with m.push(translate(cx, cy, cz), rotate("x", tilt * -facing)):
        m.box("Hull_Dark", (0, 0, 0), (w, h, 0.05))
        m.box("Screen_Lit", (0, 0, facing * 0.027), (w - 0.06, h - 0.06, 0.006))
        m.box("Hull_Dark", (0, -h * 0.5 - 0.1, facing * -0.03), (0.06, 0.2, 0.04))


def chair(m, x, z, turn=0.0):
    with m.push(translate(x, 0, z), rotate("y", turn)):
        m.cylinder("Pipe_Steel", (0, 0.22, 0), 0.035, 0.44, "y", 8)
        m.box("Hull_Dark", (0, 0.03, 0), (0.5, 0.06, 0.5))
        m.box("Seat_Fabric", (0, 0.48, 0), (0.48, 0.08, 0.46))
        m.box("Seat_Fabric", (0, 0.84, 0.21), (0.46, 0.6, 0.07))
        m.box("Pipe_Steel", (0, 0.6, 0.25), (0.05, 0.3, 0.04))
        # zero-G: a lap belt, because nothing else keeps you in a chair
        m.box("Mat_Rubber", (0, 0.53, -0.05), (0.5, 0.025, 0.06))


# ---------------------------------------------------------------- the comms room
def comms(m):
    """The uplink room: the deep space console on the back wall between two operator desks, a rack
    wall of transceivers, the orbit plot on the other wall, and the waveguides that carry all of it
    up through the ceiling to the dish."""
    # the uplink bay: a mounting frame proud of the back wall, where the console itself hangs (the
    # console is built at runtime - scripts/comms_station.gd - and is placed at CONSOLE_Z)
    m.box("Hull_Dark", (0, 1.62, 5.30), (1.9, 1.9, 0.08))
    m.box("Hull_Panel", (0, 1.62, 5.255), (1.7, 1.7, 0.02))
    for sx in (-1, 1):
        m.box("Accent_Warn", (sx * 0.93, 1.62, 5.25), (0.05, 1.9, 0.02))
        # waveguides: rectangular copper ducts up each side of the bay and into the ceiling
        m.box("Pipe_Copper", (sx * 1.12, 2.45, 5.2), (0.12, 2.3, 0.08))
        m.box("Pipe_Copper", (sx * 1.12, 3.46, 4.2), (0.12, 0.08, 2.1))
        m.box("Pipe_Steel", (sx * 1.12, 3.46, 5.18), (0.16, 0.12, 0.12))
        for y in (0.9, 1.7, 2.5, 3.2):
            m.box("Pipe_Steel", (sx * 1.12, y, 5.22), (0.18, 0.04, 0.12))
    m.box("Light_Data", (0, 2.63, 5.24), (0.9, 0.035, 0.02))     # ON AIR lamp over the bay

    # operator desks either side of the bay, along the back wall
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 1.45, sx * 4.7))
        xc, w = (x0 + x1) * 0.5, x1 - x0
        m.box("Hull_Dark", (xc, 0.39, 4.93), (w, 0.78, 0.74))
        m.box("Hull_Light", (xc, 0.8, 4.88), (w + 0.04, 0.05, 0.86))
        m.box("Mat_Rubber", (xc, 0.06, 4.56), (w - 0.1, 0.12, 0.02))
        m.box("Accent_Warn", (xc, 0.775, 4.45), (w, 0.02, 0.02))
        # two monitors, tilted back, and a radio stack behind each
        for k, off in enumerate((-0.8, 0.8)):
            screen(m, (xc + off, 1.22, 4.78), (0.7, 0.44), tilt=0.25)
            m.box("Hull_Dark", (xc + off, 1.25, 5.2), (0.9, 0.9, 0.2))
            leds(m, xc + off - 0.38, xc + off + 0.38, 1.5, 1.66, 5.1, 8, 2, seed=7 + k + (3 if sx > 0 else 0))
            for kx in (-0.3, -0.1, 0.1, 0.3):       # tuning knobs across the bottom of the stack
                m.cylinder("Hull_Light", (xc + off + kx, 0.95, 5.09), 0.03, 0.03, "z", 8)
        # handset on a coiled cord, clipped to the desk edge
        m.box("Hull_Dark", (xc - sx * 1.25, 0.86, 4.6), (0.08, 0.06, 0.24))
        m.cylinder("Mat_Rubber", (xc - sx * 1.25, 0.84, 4.8), 0.018, 0.2, "z", 6)
        chair(m, xc, 3.95)

    # -x wall: three transceiver racks, LEDs down every front
    for i, z in enumerate((-1.0, 0.0, 1.0)):
        m.box("Hull_Dark", (-5.0, 1.07, z), (0.66, 2.14, 0.92))
        m.box("Hull_Panel", (-4.665, 1.07, z), (0.02, 2.0, 0.84))
        leds(m, z - 0.36, z + 0.36, 0.4, 1.9, -4.66, 6, 9, face=1, axis="x", seed=31 + i)
        m.box("Screen_Lit", (-4.655, 1.98, z), (0.01, 0.12, 0.6))
        m.box("Hull_Light", (-4.64, 0.25, z), (0.04, 0.05, 0.7))              # pull bar
    m.box("Pipe_Steel", (-4.95, 2.4, 0.0), (0.4, 0.08, 3.0))                   # cable tray over them
    for z in (-1.3, -0.4, 0.4, 1.3):
        m.cylinder("Mat_Rubber", (-4.95, 2.9, z), 0.035, 1.0, "y", 6)

    # +x wall: the orbit plot, and a low cabinet under it
    m.box("Hull_Dark", (5.3, 1.9, 0.0), (0.08, 1.5, 3.4))
    m.box("Screen_Lit", (5.255, 1.9, 0.0), (0.01, 1.36, 3.26))
    m.box("Hull_Dark", (5.1, 0.45, 0.0), (0.5, 0.9, 2.6))
    m.box("Hull_Light", (5.1, 0.92, 0.0), (0.54, 0.04, 2.64))
    leds(m, -1.1, 1.1, 0.5, 0.75, 4.845, 10, 2, face=-1, axis="x", seed=53)

    # the dish's feed runs across the ceiling: a cable tray from the bay to the -x racks
    m.box("Pipe_Steel", (-2.8, 3.42, 4.2), (3.6, 0.06, 0.4))
    m.box("Pipe_Steel", (2.8, 3.42, 4.2), (3.6, 0.06, 0.4))


# ---------------------------------------------------------------- the washroom
def toilet(m, x):
    """A toilet, as a station builds one: a bowl you would recognise, plus the bars that hold you on
    it and the suction hose that makes it work without gravity."""
    z = TOILET_Z
    m.box("Suit_White", (x, 0.95, 5.2), (0.52, 0.5, 0.24))                   # cistern on the wall
    m.box("Hull_Light", (x, 1.215, 5.2), (0.54, 0.03, 0.26))
    m.cylinder("Hull_Dark", (x + 0.12, 1.24, 5.2), 0.035, 0.02, "y", 10)       # flush button
    m.cylinder("Suit_White", (x, 0.15, z), 0.17, 0.3, "y", 14, r_top=0.14)     # pedestal
    m.cylinder("Suit_White", (x, 0.36, z - 0.02), 0.16, 0.14, "y", 16, r_top=0.23)  # bowl
    m.torus("Mat_Rubber", (x, 0.445, z - 0.02), 0.2, 0.035, "y", 18, 6)        # the seat
    m.box("Suit_White", (x, 0.72, 5.07), (0.42, 0.5, 0.03))                    # lid, raised
    # thigh bars: swing down over your legs so you stay sat
    for sx in (-1, 1):
        m.cylinder("Pipe_Steel", (x + sx * 0.3, 0.47, z + 0.08), 0.025, 0.34, "y", 8)
        m.cylinder("Pipe_Steel", (x + sx * 0.3, 0.64, z - 0.12), 0.025, 0.44, "z", 8)
    m.cylinder("Pipe_Steel", (x, 0.64, z - 0.34), 0.025, 0.62, "x", 8)
    # the suction hose, looped off the side of the cistern, and its funnel
    m.cylinder("Mat_Rubber", (x - 0.32, 0.8, 5.12), 0.035, 0.5, "y", 8)
    m.cylinder("Mat_Rubber", (x - 0.32, 0.55, 4.9), 0.035, 0.44, "z", 8)
    m.cylinder("Suit_Orange", (x - 0.32, 0.55, 4.62), 0.03, 0.14, "z", 10, r_top=0.08)
    # foot bar at the front, and a roll of paper on the partition
    m.cylinder("Pipe_Steel", (x, 0.1, 4.35), 0.025, 0.7, "x", 8)
    m.cylinder("Suit_White", (x + 0.68, 0.82, 4.45), 0.06, 0.12, "x", 12)
    m.box("Hull_Dark", (x + 0.73, 0.82, 4.45), (0.02, 0.05, 0.16))


def stall_row(m):
    """Two stalls on the back wall, public-toilet fashion: laminate partitions on legs, open to the
    ceiling, a headrail across the fronts. The +x stall's door is a separate runtime node
    (scripts/washroom.gd); the -x one is shut and taped over and has been for longer than anyone
    remembers."""
    depth = STALL_BACK - STALL_FRONT
    zc = (STALL_FRONT + STALL_BACK) * 0.5
    h = PART_HI - PART_LO
    yc = (PART_LO + PART_HI) * 0.5
    left = STALLS[0] - STALL_HALF
    right = STALLS[-1] + STALL_HALF
    # side partitions: the two ends and the one they share
    for x in (left, (STALLS[0] + STALLS[1]) * 0.5, right):
        m.box("Hull_Light", (x, yc, zc), (0.05, h, depth))
        m.box("Hull_Dark", (x, PART_HI + 0.015, zc), (0.07, 0.03, depth))
        for z in (STALL_FRONT + 0.1, STALL_BACK - 0.1):
            m.cylinder("Pipe_Steel", (x, PART_LO * 0.5, z), 0.025, PART_LO, "y", 8)
        m.box("Hull_Dark", (x, PART_LO * 0.5 + 0.02, STALL_FRONT + 0.1), (0.08, 0.03, 0.08))
    # fronts: a pilaster either side of each door, the headrail across the top
    for xs in STALLS:
        for sx in (-1, 1):
            a = xs + sx * DOOR_HALF
            b = xs + sx * (STALL_HALF - 0.025)
            m.box("Hull_Light", ((a + b) * 0.5, yc, STALL_FRONT), (abs(b - a), h, 0.05))
            m.box("Pipe_Steel", (a, yc, STALL_FRONT), (0.04, h, 0.07))        # door stop / hinge post
        # the little occupancy window over each door: green by day
        m.box("Light_Green", (xs, PART_HI + 0.07, STALL_FRONT - 0.03), (0.2, 0.06, 0.01))
    m.box("Pipe_Steel", (0, PART_HI + 0.02, STALL_FRONT), (right - left + 0.1, 0.05, 0.06))
    m.box("Pipe_Steel", (0, PART_HI + 0.02, STALL_FRONT - 0.07), (0.05, 0.05, 0.05))
    # the shut door on the -x stall, taped across
    xs = STALLS[0]
    m.box("Door_Panel", (xs, 1.2, STALL_FRONT), (DOOR_HALF * 2 - 0.02, 2.0, 0.035))
    for y in (0.75, 1.3, 1.75):
        m.box("Accent_Warn", (xs, y, STALL_FRONT - 0.022), (DOOR_HALF * 2 + 0.06, 0.07, 0.008))
    m.box("Hull_Dark", (xs + 0.3, 1.1, STALL_FRONT - 0.03), (0.04, 0.12, 0.03))   # the latch
    m.box("Accent_Red", (xs + 0.3, 1.19, STALL_FRONT - 0.03), (0.05, 0.04, 0.02))  # ENGAGED
    for xs in STALLS:
        toilet(m, xs)


def washroom(m):
    stall_row(m)
    # -x wall: a counter with two basins, a steel mirror (glass does not go in a station toilet)
    m.box("Hull_Dark", (-5.18, 0.42, 0.0), (0.36, 0.84, 3.4))
    m.box("Hull_Light", (-5.0, 0.87, 0.0), (0.74, 0.06, 3.5))
    m.box("Accent_Warn", (-4.63, 0.87, 0.0), (0.02, 0.06, 3.5))
    for z in (-0.85, 0.85):
        m.cylinder("Suit_White", (-5.0, 0.83, z), 0.13, 0.1, "y", 14, r_top=0.22)
        m.cylinder("Seal_Gasket", (-5.0, 0.785, z), 0.05, 0.01, "y", 8)
        # a tap, and the soap under a little lamp that says it is empty
        m.cylinder("Pipe_Steel", (-5.28, 1.0, z), 0.025, 0.26, "y", 8)
        m.cylinder("Pipe_Steel", (-5.17, 1.12, z), 0.02, 0.24, "x", 8)
        m.box("Suit_White", (-5.3, 1.05, z + 0.34), (0.1, 0.18, 0.1))
        m.box("Light_Data", (-5.245, 1.1, z + 0.34), (0.01, 0.02, 0.03))
        # everything floats off a counter here: a bungee across each basin
        m.box("Mat_Rubber", (-4.92, 0.95, z), (0.02, 0.02, 0.5))
    m.box("Hull_Dark", (-5.35, 1.75, 0.0), (0.06, 1.0, 3.3))
    m.box("Hull_Light", (-5.315, 1.75, 0.0), (0.02, 0.9, 3.2))
    # hand dryer and a towel dispenser either side of the counter
    m.box("Hull_Light", (-5.24, 1.25, 2.3), (0.26, 0.34, 0.3))
    m.box("Hull_Dark", (-5.1, 1.08, 2.3), (0.1, 0.03, 0.24))
    m.box("Light_Green", (-5.105, 1.34, 2.38), (0.01, 0.02, 0.02))
    m.box("Suit_White", (-5.28, 1.35, -2.3), (0.18, 0.44, 0.34))
    m.box("Hull_Dark", (-5.18, 1.14, -2.3), (0.04, 0.03, 0.26))

    # +x wall: the waste processor, the pump the stalls empty into, and its plumbing
    m.box("Hull_Dark", (5.05, 0.7, 2.6), (0.6, 1.4, 1.4))
    m.box("Hull_Panel", (4.74, 0.8, 2.6), (0.02, 1.1, 1.2))
    m.box("Accent_Warn", (4.735, 1.45, 2.6), (0.01, 0.06, 1.3))
    leds(m, 2.2, 3.0, 1.2, 1.32, 4.74, 6, 1, face=-1, axis="x", seed=71)
    m.box("Screen_Lit", (4.735, 1.05, 2.15), (0.01, 0.16, 0.3))
    for z in (2.2, 3.0):
        m.cylinder("Pipe_Copper", (5.1, 2.4, z), 0.05, 2.0, "y", 8)
    m.cylinder("Pipe_Copper", (3.1, 0.07, 5.1), 0.05, 4.1, "x", 8)             # the stalls' drain
    m.cylinder("Pipe_Copper", (5.1, 0.07, 4.0), 0.05, 2.2, "z", 8)
    # a locker of hygiene kits and a bin that seals
    m.box("Hull_Light", (5.2, 1.4, -1.2), (0.3, 1.2, 0.9))
    m.box("Door_Panel", (5.04, 1.4, -1.2), (0.02, 1.1, 0.8))
    m.box("Hull_Dark", (5.03, 1.4, -0.86), (0.02, 0.2, 0.04))
    m.cylinder("Hull_Dark", (5.15, 0.3, -2.4), 0.2, 0.6, "y", 12)
    m.cylinder("Mat_Rubber", (5.15, 0.61, -2.4), 0.2, 0.02, "y", 12)

    # a strip lamp over the stalls, on the ceiling: the partitions throw the room lamp's shadow
    m.box("Hull_Dark", (0, 3.55, 4.4), (3.4, 0.05, 0.3))
    m.box("Light_Strip", (0, 3.52, 4.4), (3.2, 0.01, 0.2))


ROOMS = {"room_comms": comms, "room_washroom": washroom}


def build(check=False):
    sh = shell()
    tri_count = sum(len(t) for t in sh.values())
    print("shell: %d triangles shared by %s" % (tri_count, ", ".join(SHELL_FROM)))
    for name, fit in ROOMS.items():
        m = Mesh()
        add_shell(m, sh)
        fit(m)
        lo, hi = m.bounds()
        assert lo[0] >= -6.001 and hi[0] <= 6.001 and lo[2] >= -6.001 and hi[2] <= 6.001, (name, lo, hi)
        assert lo[1] >= -0.301 and hi[1] <= 4.001, (name, lo, hi)
        path = os.path.join(KIT, name + ".glb")
        size = write_glb(m, path, name)
        print("%s: %d triangles, %d bytes" % (name, m.triangle_count(), size))
        if check:
            back = _triangles(path)
            n = sum(len(t) for t in back.values())
            assert n > tri_count, "%s: re-read only %d triangles" % (name, n)
            for mat, tris in sh.items():
                missing = len(set(tris) - back.get(mat, set()))
                assert missing == 0, "%s lost %d shell triangles of %s" % (name, missing, mat)
            print("  re-parsed ok: %d distinct triangles, shell intact" % n)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true", help="re-parse what was written")
    build(ap.parse_args().check)
