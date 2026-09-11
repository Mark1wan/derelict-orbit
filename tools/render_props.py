#!/usr/bin/env python3
"""Contact sheet of the prop kit - or just the wall fittings, which are the ones worth checking,
since they are seen from below at odd angles in a station with no floor.

    python3 tools/render_props.py           # docs/props_wall.png
    python3 tools/render_props.py --all
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_props
import proplib
from render3d import Camera, Renderer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# the wall class, in the order scripts/station.gd files them
WALL = ["prop_ladder", "prop_grab_loop", "prop_foot_restraint", "prop_handhold", "prop_valve",
        "prop_locker", "prop_control_box", "prop_cable_reel", "prop_hose_reel", "prop_tool_rack",
        "prop_extinguisher", "prop_medkit"]


def draw(rend, cam, mesh, mats):
    for mat_name, tris in mesh.tris.items():
        mat = mats[mat_name]
        col = [c ** 1.0 for c in mat["baseColorFactor"][:3]]
        em = mat.get("emissiveFactor", [0, 0, 0])
        strength = mat.get("extensions", {}).get("KHR_materials_emissive_strength", {}).get("emissiveStrength", 0.0)
        emission = [e * strength * 0.25 for e in em]
        for a, b, c in tris:
            rend.triangle(cam, a, b, c, col, emission)


def wall_plane(rend, cam, half=0.75, step=0.15):
    """The surface it is bolted to - these all mount with +Y out of the wall."""
    n = int(half * 2 / step)
    for i in range(n):
        for j in range(n):
            x0, z0 = -half + i * step, -half + j * step
            shade = 0.045 if (i + j) % 2 else 0.062
            a = (x0, 0, z0)
            b = (x0 + step, 0, z0)
            c = (x0 + step, 0, z0 + step)
            d = (x0, 0, z0 + step)
            rend.triangle(cam, a, b, c, [shade] * 3)
            rend.triangle(cam, a, c, d, [shade] * 3)


def sheet(names, path, w=360, h=330, cols=4):
    mats = {}
    for k, v in proplib.MATERIALS.items():
        color, metal, rough, emissive = v
        entry = {"baseColorFactor": list(color)}
        if emissive > 0:
            entry["emissiveFactor"] = list(color[:3])
            entry["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": emissive}}
        mats[k] = entry
    rows = (len(names) + cols - 1) // cols
    rend = Renderer(w * cols, h * rows, (10, 10, 12))
    for i, name in enumerate(names):
        mesh = proplib.Mesh()
        build_props.PROPS[name](mesh)
        mesh.settle()
        sub = Renderer(w, h, (10, 10, 12))
        cam = Camera((0.62, 0.46, 0.70), (0, 0.10, 0), fov=38)
        wall_plane(sub, cam)
        draw(sub, cam, mesh, mats)
        col, row = i % cols, i // cols
        for y in range(h):
            rend.color[row * h + y][col * w:(col + 1) * w] = sub.color[y]
            rend.color[row * h + y][col * w] = (34, 34, 40)
        for x in range(w):
            rend.color[row * h][col * w + x] = (34, 34, 40)
    rend.save(path)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    if args.all:
        print(sheet(sorted(build_props.PROPS), os.path.join(docs, "props_all.png")))
    else:
        print(sheet(WALL, os.path.join(docs, "props_wall.png")))


if __name__ == "__main__":
    main()
