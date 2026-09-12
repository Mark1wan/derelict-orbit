#!/usr/bin/env python3
"""Renders the stalker rig (tools/creature_spec.py) to PNG reference sheets.

    python3 tools/render_creature.py                 # docs/creature_poses.png + detail sheets
    python3 tools/render_creature.py --pose crawl_a --out /tmp/x.png

Forward kinematics here is the same maths scripts/creature.gd does with Node3D transforms, so
what you see is what the game builds.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import creature_spec
from render3d import Camera, Renderer, mat_mul, translate, euler, xform

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def bone_transforms(rig, pose):
    """World transform of every bone for a pose. `rig` is a spec dict (see tools/riglib.py)."""
    bones = {b["name"]: (b["parent"], b["offset"]) for b in rig["bones"]}
    order = [b["name"] for b in rig["bones"]]
    rot = pose["bones"] if pose else {}
    root_pos = pose["root_pos"] if pose else [0, 0, 0]
    out = {}
    for name in order:
        parent, offset = bones[name]
        local = mat_mul(translate(offset), euler(rot.get(name, [0, 0, 0])))
        if not parent:
            local = mat_mul(translate(root_pos), local)
        out[name] = local if not parent else mat_mul(out[parent], local)
    return out


def part_triangles(part, m):
    """Triangles for one part, already in world space. Shapes mirror what creature.gd builds."""
    local = mat_mul(translate(part["pos"]), euler(part["rot"]))
    m = mat_mul(m, local)
    tris = []
    shape = part["shape"]
    if shape == "box":
        sx, sy, sz = (v / 2.0 for v in part["size"])
        c = [(x * sx, y * sy, z * sz) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        # indices into c: bit2=x bit1=y bit0=z
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        for a, b, cc, d in faces:
            tris.append((c[a], c[b], c[cc]))
            tris.append((c[a], c[cc], c[d]))
    elif shape == "sph":
        rx, ry, rz = (v / 2.0 for v in part["size"])   # "size" is the full extent, like a box
        seg, rings = 10, 6
        for j in range(rings):
            v0 = 1.0 - 2.0 * j / rings
            v1 = 1.0 - 2.0 * (j + 1) / rings
            for i in range(seg):
                u0 = i * math.tau / seg
                u1 = (i + 1) * math.tau / seg

                def at(u, v):
                    phi = math.acos(max(-1.0, min(1.0, v)))
                    return (rx * math.sin(phi) * math.cos(u), ry * math.cos(phi), rz * math.sin(phi) * math.sin(u))
                a, b, cc, d = at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)
                tris.append((a, b, cc))
                tris.append((a, cc, d))
    else:   # "cone"/"strand": tapered cylinder from r at y=0 to r2 at y=h. A strand is the cheap
            # 3-sided version with no caps - that is what the fur is made of, by the thousand.
        r0, r1, h = part["r"], part["r2"], part["h"]
        seg = 3 if shape == "strand" else 8
        for i in range(seg):
            u0 = i * math.tau / seg
            u1 = (i + 1) * math.tau / seg
            a = (math.cos(u0) * r0, 0, math.sin(u0) * r0)
            b = (math.cos(u1) * r0, 0, math.sin(u1) * r0)
            cc = (math.cos(u1) * r1, h, math.sin(u1) * r1)
            d = (math.cos(u0) * r1, h, math.sin(u0) * r1)
            tris.append((a, b, cc))
            tris.append((a, cc, d))
            if shape != "strand":
                tris.append(((0, 0, 0), b, a))
                if r1 > 0.0001:
                    tris.append(((0, h, 0), d, cc))
    return [tuple(xform(m, p) for p in t) for t in tris]


def wall(rend, cam, x=0.45, half=1.6, step=0.4):
    """A vertical surface, for the poses that are not standing on anything."""
    n = int(half * 2 / step)
    for i in range(n):
        for j in range(n):
            y0, z0 = i * step, -half + j * step
            y1, z1 = y0 + step, z0 + step
            shade = 0.034 if (i + j) % 2 else 0.050
            a, b, c, d = (x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)
            rend.triangle(cam, a, b, c, [shade] * 3)
            rend.triangle(cam, a, c, d, [shade] * 3)


def corner(rend, cam, x=0.30, z_from=-2.4, z_to=0.0, height=2.2, step=0.4):
    """A wall that stops - i.e. a corner, with an edge to look round. The whole point of the
    chupacabra is what this hides."""
    n_y = int(height / step)
    n_z = int((z_to - z_from) / step)
    for i in range(n_y):
        for j in range(n_z):
            y0, z0 = i * step, z_from + j * step
            y1, z1 = y0 + step, z0 + step
            shade = 0.038 if (i + j) % 2 else 0.055
            a, b, c, d = (x, y0, z0), (x, y1, z0), (x, y1, z1), (x, y0, z1)
            rend.triangle(cam, a, b, c, [shade] * 3)
            rend.triangle(cam, a, c, d, [shade] * 3)
    # the return face at the end, so the wall reads as a corner rather than as a hole
    for i in range(n_y):
        y0, y1 = i * step, (i + 1) * step
        a, b, c, d = (x, y0, z_to), (x, y1, z_to), (x + 0.35, y1, z_to), (x + 0.35, y0, z_to)
        rend.triangle(cam, a, b, c, [0.028] * 3)
        rend.triangle(cam, a, c, d, [0.028] * 3)


def ground(rend, cam, half=3.0, step=0.5):
    """A dim checker floor - without a contact shadow you cannot tell a crouch from a hover."""
    n = int(half * 2 / step)
    for i in range(n):
        for j in range(n):
            x0, z0 = -half + i * step, -half + j * step
            x1, z1 = x0 + step, z0 + step
            shade = 0.030 if (i + j) % 2 else 0.045
            a, b, c, d = (x0, 0, z0), (x1, 0, z0), (x1, 0, z1), (x0, 0, z1)
            rend.triangle(cam, a, b, c, [shade] * 3)
            rend.triangle(cam, a, c, d, [shade] * 3)


def draw(rend, cam, pose_name, rig=None, root_rot=None, root_pos=(0, 0, 0)):
    """`root_rot` turns the whole model - for showing a wall-clinger on a wall rather than
    standing on the floor pretending."""
    rig = rig or creature_spec.spec()
    pose = rig["poses"][pose_name]
    xf = bone_transforms(rig, pose)
    if root_rot or root_pos != (0, 0, 0):
        world = mat_mul(translate(root_pos), euler(root_rot or [0, 0, 0]))
        xf = {k: mat_mul(world, v) for k, v in xf.items()}
    for part in rig["parts"]:
        mat = rig["materials"][part["mat"]]
        for tri in part_triangles(part, xf[part["bone"]]):
            rend.triangle(cam, tri[0], tri[1], tri[2], mat["albedo"], mat["emission"])


def prop_box(rend, cam, pos, size=(0.26, 0.26, 0.26), color=(0.135, 0.125, 0.100)):
    """A stand-in for whatever it has got its face in - one of the kit's canisters or crates."""
    hx, hy, hz = (v / 2 for v in size)
    c = [(pos[0] + x * hx, pos[1] + y * hy, pos[2] + z * hz)
         for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    for a, b, cc, d in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]:
        rend.triangle(cam, c[a], c[b], c[cc], list(color))
        rend.triangle(cam, c[a], c[cc], c[d], list(color))


def render(pose_name, w, h, eye, target, fov, path, bg=(9, 9, 11), rig=None, root_rot=None,
           root_pos=(0, 0, 0), surface="floor", prop=None):
    rend = Renderer(w, h, bg)
    cam = Camera(eye, target, fov=fov)
    if surface == "wall":
        wall(rend, cam)
    elif surface == "corner":
        ground(rend, cam)
        corner(rend, cam)
    else:
        ground(rend, cam)
    if prop is not None:
        prop_box(rend, cam, prop)
    draw(rend, cam, pose_name, rig, root_rot, root_pos)
    rend.save(path)
    return path


def sheet(names, path, w=440, h=520, cols=4, eye=(2.4, 1.25, -3.0), target=(0, 0.85, 0), fov=34.0,
          rig=None):
    """Contact sheet: every pose from the same camera, so they can be compared."""
    rend = Renderer(w * cols, h * ((len(names) + cols - 1) // cols))
    for i, name in enumerate(names):
        col, row = i % cols, i // cols
        sub = Renderer(w, h)
        cam = Camera(eye, target, fov=fov)
        ground(sub, cam)
        draw(sub, cam, name, rig)
        for y in range(h):
            rend.color[row * h + y][col * w:(col + 1) * w] = sub.color[y]
        for y in range(h):      # divider
            rend.color[row * h + y][col * w] = (40, 40, 46)
        for x in range(w):
            rend.color[row * h][col * w + x] = (40, 40, 46)
    rend.save(path)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pose", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--size", type=int, nargs=2, default=[520, 620])
    ap.add_argument("--eye", type=float, nargs=3, default=[2.4, 1.25, -3.0])
    ap.add_argument("--target", type=float, nargs=3, default=[0, 0.85, 0])
    ap.add_argument("--fov", type=float, default=34.0)
    ap.add_argument("--rig", default="creature", help="creature (the stalker) or chupacabra")
    args = ap.parse_args()

    rig = creature_spec.spec()
    order = ["upright", "crawl_a", "crawl_b", "dislocate", "contort", "freeze", "lunge", "coil"]
    sheet_cam = {"eye": (2.4, 1.25, -3.0), "target": (0, 0.85, 0), "fov": 34.0}
    if args.rig == "chupacabra":
        import chupacabra_spec
        rig = chupacabra_spec.spec()
        order = chupacabra_spec.POSE_ORDER
        sheet_cam = {"eye": (1.15, 0.60, -1.45), "target": (0, 0.30, 0), "fov": 36.0}

    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    if args.pose:
        out = args.out or os.path.join(docs, "%s_%s.png" % (args.rig, args.pose))
        print(render(args.pose, args.size[0], args.size[1], tuple(args.eye), tuple(args.target),
                     args.fov, out, rig=rig))
        return
    name = "creature_poses.png" if args.rig == "creature" else "%s_poses.png" % args.rig
    print(sheet(order, os.path.join(docs, name), rig=rig, **sheet_cam))


if __name__ == "__main__":
    main()
