#!/usr/bin/env python3
"""What the wall placer sees: the profile of a kit piece's wall, and where fittings land in it.

    python3 tools/render_wall_map.py     # docs/wall_placement.png

Mirrors Kit.wall_profile / Kit.find_clear_spot from scripts/kit.gd against the real .glb, so this
is a picture of the actual decision the game makes, not an illustration of it. Dark = bare wall a
fitting can be bolted to; grey = something already standing there (rib, pipe run, console, rack);
red = a surface nothing gets bolted over whatever its depth (lamp, screen, glazing, door).
"""

import json
import math
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_props
import proplib
from render3d import Renderer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES, DEPTH = 0.10, 1.7
KEEP_OFF = {"Light_Strip", "Light_Warn", "Light_Data", "Light_Green", "Screen_Lit",
            "Glass_Window", "Glass_Port", "Door_Panel"}
UPRIGHT = {"prop_ladder", "prop_cable_reel"}
CLEARANCE = 0.03


def read_glb(path):
    d = open(path, "rb").read()
    jlen = struct.unpack_from("<I", d, 12)[0]
    g = json.loads(d[20:20 + jlen])
    blob = d[20 + jlen + 8:]

    def acc(i):
        a = g["accessors"][i]
        bv = g["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        n, t, ct = a["count"], a["type"], a["componentType"]
        size = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}[t]
        fmt = {5126: "f", 5125: "I", 5123: "H"}[ct]
        vals = struct.unpack_from("<%d%s" % (n * size, fmt), blob, off)
        return [vals[i * size:(i + 1) * size] for i in range(n)] if size > 1 else list(vals)

    out = []
    for prim in g["meshes"][0]["primitives"]:
        pos, idx = acc(prim["attributes"]["POSITION"]), acc(prim["indices"])
        name = g["materials"][prim["material"]]["name"]
        for i in range(0, len(idx), 3):
            out.append((name, [pos[idx[i]], pos[idx[i + 1]], pos[idx[i + 2]]]))
    return out


def profile(piece, axis, coord):
    tris = read_glb(os.path.join(ROOT, "kit", "%s.glb" % piece))
    other = 2 if axis == 0 else 0
    sign = 1.0 if coord > 0 else -1.0
    prof = {}
    for name, tri in tris:
        forbidden = name in KEEP_OFF
        deepest, lo, hi = -1.0, [1e9, 1e9], [-1e9, -1e9]
        for v in tri:
            d = (coord - v[axis]) * sign
            if d < -0.06 or d > DEPTH:
                continue
            deepest = max(deepest, 9.0 if forbidden else d)
            lo = [min(lo[0], v[other]), min(lo[1], v[1])]
            hi = [max(hi[0], v[other]), max(hi[1], v[1])]
        if deepest < 0:
            continue
        for a in range(math.floor(lo[0] / RES), math.floor(hi[0] / RES) + 1):
            for b in range(math.floor(lo[1] / RES), math.floor(hi[1] / RES) + 1):
                prof[(a, b)] = max(prof.get((a, b), -1.0), deepest)
    return prof


def footprints():
    out = {}
    for name, fn in build_props.PROPS.items():
        m = proplib.Mesh()
        fn(m)
        m.settle()
        pts = [p for t in m.tris.values() for tr in t for p in tr]
        out[name] = (max(p[0] for p in pts) - min(p[0] for p in pts),
                     max(p[1] for p in pts) - min(p[1] for p in pts),
                     max(p[2] for p in pts) - min(p[2] for p in pts))
    return out


def find_spots(prof, face, w, h, lo, hi, taken=None):
    limit = face + 0.03
    hw = max(1, round(w * 0.5 / RES))
    hh = max(1, round(h * 0.5 / RES))
    spots = []
    for a in range(math.floor(lo[0] / RES), math.floor(hi[0] / RES) + 1, 2):
        for b in range(math.floor(lo[1] / RES), math.floor(hi[1] / RES) + 1, 2):
            ok = True
            for u in range(a - hw, a + hw + 1):
                for v in range(b - hh, b + hh + 1):
                    if (taken and (u, v) in taken) or prof.get((u, v), -1.0) > limit:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                spots.append((a, b, hw, hh))
    return spots


def panel(rend, ox, oy, piece, axis, coord, face, lo, hi, px, fits, rng):
    prof = profile(piece, axis, coord)
    a0, b0 = math.floor(lo[0] / RES), math.floor(lo[1] / RES)
    a1, b1 = math.floor(hi[0] / RES), math.floor(hi[1] / RES)
    for a in range(a0, a1 + 1):
        for b in range(b0, b1 + 1):
            d = prof.get((a, b), -1.0)
            if d > 8.0:
                col = (92, 30, 34)
            elif d > face + 0.03:
                col = (58, 58, 64)
            else:
                col = (22, 30, 26)
            x0 = ox + (a - a0) * px
            y0 = oy + (b1 - b) * px
            for y in range(y0, min(y0 + px, rend.h)):
                for x in range(x0, min(x0 + px, rend.w)):
                    rend.color[y][x] = col
    # where fittings actually land
    foot = footprints()
    taken = set()
    for name in fits:
        sx, sy, sz = foot[name]
        w = (sx if name in UPRIGHT else sz) + CLEARANCE * 2
        h = (sz if name in UPRIGHT else sx) + CLEARANCE * 2
        spots = find_spots(prof, face, w, h, lo, hi, taken)
        if not spots:
            continue
        a, b, hw, hh = spots[rng.randrange(len(spots))]
        for u in range(a - hw, a + hw + 1):
            for v in range(b - hh, b + hh + 1):
                taken.add((u, v))
        col = (120, 200, 150) if name not in UPRIGHT else (200, 170, 110)
        for u in range(a - hw, a + hw + 1):
            for v in range(b - hh, b + hh + 1):
                if not (a0 <= u <= a1 and b0 <= v <= b1):
                    continue
                edge = u in (a - hw, a + hw) or v in (b - hh, b + hh)
                x0 = ox + (u - a0) * px
                y0 = oy + (b1 - v) * px
                for y in range(y0, min(y0 + px, rend.h)):
                    for x in range(x0, min(x0 + px, rend.w)):
                        rend.color[y][x] = col if edge else tuple(int(c * 0.45) for c in col)


def main():
    rng = random.Random(9)
    rend = Renderer(1180, 560, (12, 12, 14))
    panel(rend, 20, 30, "corridor_straight", 0, 1.5, 0.06, (-1.5, 0.35), (1.5, 2.5), 12,
          ["prop_ladder", "prop_medkit", "prop_handhold", "prop_control_box"], rng)
    panel(rend, 420, 30, "room_power", 0, 5.5, 0.10, (-4.6, 0.45), (4.6, 3.0), 7,
          ["prop_ladder", "prop_locker", "prop_valve", "prop_hose_reel", "prop_tool_rack"], rng)
    out = os.path.join(ROOT, "docs", "wall_placement.png")
    rend.save(out)
    print(out)


if __name__ == "__main__":
    main()
