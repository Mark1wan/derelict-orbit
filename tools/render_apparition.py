#!/usr/bin/env python3
"""Renders the corridor apparition to PNG, the way Godot will draw it: camera-facing soft puffs
composited back to front over a corridor.

    python3 tools/render_apparition.py                    # docs/apparition_*.png

The puffs use the same layout and the same smoke texture formula the game does
(tools/apparition_spec.py -> kit/apparition_corridor.json -> scripts/apparition.gd), so this is a
fair picture of it rather than an illustration.
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apparition_spec as spec
from render3d import Camera, Renderer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_TEX = {}


def texture(size=96, plateau=0.0):
    """The puff sprite, one per (size, plateau)."""
    key = (size, round(plateau, 3))
    if key not in _TEX:
        _TEX[key] = [[spec.smoke_alpha((x + 0.5) / size, (y + 0.5) / size, plateau)
                      for x in range(size)] for y in range(size)]
    return _TEX[key]


def corridor(rend, cam, length=16.0, half=1.5, height=3.0, lit_end=True, doorway=True):
    """A plain 3 m corridor running down -Z, shaded darker with distance, with ceiling strips.
    Context only - the real thing is scripts/station.gd's kit geometry."""
    seg = 0.8
    n = int(length / seg)
    for i in range(n):
        z0, z1 = -i * seg, -(i + 1) * seg
        f = 1.0 - min(1.0, (i * seg) / (length * 1.15))          # fog toward the far end
        base = 0.055 * f + 0.012
        for quad, shade in (
            ([(-half, 0, z0), (half, 0, z0), (half, 0, z1), (-half, 0, z1)], base * 0.8),
            ([(-half, height, z0), (-half, height, z1), (half, height, z1), (half, height, z0)], base * 0.7),
            ([(-half, 0, z0), (-half, 0, z1), (-half, height, z1), (-half, height, z0)], base),
            ([(half, 0, z0), (half, height, z0), (half, height, z1), (half, 0, z1)], base),
        ):
            a, b, c, d = quad
            rend.triangle(cam, a, b, c, [shade] * 3)
            rend.triangle(cam, a, c, d, [shade] * 3)
        if i % 2 == 0 and lit_end:      # ceiling light strip
            e = 0.30 * f + 0.02
            a = (-0.35, height - 0.02, z0)
            b = (0.35, height - 0.02, z0)
            c = (0.35, height - 0.02, z1)
            d = (-0.35, height - 0.02, z1)
            rend.triangle(cam, a, b, c, [0, 0, 0], [e, e * 1.05, e * 1.2])
            rend.triangle(cam, a, c, d, [0, 0, 0], [e, e * 1.05, e * 1.2])
    if doorway:
        # a lit bulkhead at the far end: the apparition is a shape you notice because it is
        # blocking light, which is how anyone ever sees one
        z = -length
        rend.triangle(cam, (-half, 0, z), (half, 0, z), (half, height, z), [0.30, 0.31, 0.34])
        rend.triangle(cam, (-half, 0, z), (half, height, z), (-half, height, z), [0.30, 0.31, 0.34])
        for sx in (-1, 1):     # frame
            rend.triangle(cam, (sx * half, 0, z + 0.02), (sx * half, height, z + 0.02),
                          (sx * (half - 0.22), height, z + 0.02), [0.10, 0.10, 0.12])
            rend.triangle(cam, (sx * half, 0, z + 0.02), (sx * (half - 0.22), height, z + 0.02),
                          (sx * (half - 0.22), 0, z + 0.02), [0.10, 0.10, 0.12])


def crate(rend, cam, pos, size=0.52, tumble=0.5):
    """A stand-in for whatever the swarm has got hold of - one of the kit's loose crates."""
    h = size / 2.0
    c, s_ = math.cos(tumble), math.sin(tumble)

    def p(x, y, z):
        return (pos[0] + x * c - z * s_, pos[1] + y, pos[2] + x * s_ + z * c)

    corners = [p(x * h, y * h, z * h) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for a, b, cc, d in faces:
        rend.triangle(cam, corners[a], corners[b], corners[cc], [0.30, 0.27, 0.20])
        rend.triangle(cam, corners[a], corners[cc], corners[d], [0.30, 0.27, 0.20])


def splat(rend, cam, center, radius, alpha, color, tex, additive=False):
    """One camera-facing puff, alpha-composited. Godot does this with a billboarded quad."""
    pr = cam.project(center, rend.w, rend.h)
    if pr is None:
        return
    sx, sy, z = pr
    px_r = radius / z * rend.scale * rend.h * 0.5
    if px_r < 0.5:
        return
    size = len(tex)
    x0, x1 = max(0, int(sx - px_r)), min(rend.w - 1, int(sx + px_r))
    y0, y1 = max(0, int(sy - px_r)), min(rend.h - 1, int(sy + px_r))
    for py in range(y0, y1 + 1):
        v = (py - (sy - px_r)) / (2 * px_r)
        ty = min(size - 1, max(0, int(v * size)))
        row = rend.color[py]
        depth = rend.depth[py]
        trow = tex[ty]
        for px in range(x0, x1 + 1):
            if z > depth[px]:
                continue                       # behind the corridor wall
            u = (px - (sx - px_r)) / (2 * px_r)
            a = trow[min(size - 1, max(0, int(u * size)))] * alpha
            if a <= 0.002:
                continue
            old = row[px]
            if additive:
                row[px] = tuple(min(255, int(old[i] + 255 * color[i] * a)) for i in range(3))
            else:
                row[px] = tuple(int(old[i] * (1 - a) + 255 * color[i] * a) for i in range(3))


def draw(rend, cam, fig, origin=(0, 0, 0), form=1.0, t=0.0, ember=1.0, yaw=0.0, lean=0.0,
         morph=0.0):
    """`fig` at `origin`. `form` 1 is gathered, 0 is fully dispersed - staring at one drives that
    toward 0. `morph` 0 -> 1 takes a two-layout figure from what it is pretending to be to what it
    is. `t` advances the drift so successive frames boil."""
    tex_spec = fig.spec()["texture"]
    tex = texture(tex_spec["size"], tex_spec["plateau"])
    cols = {k: v for k, v in fig.colors.items()}
    puffs = fig.puffs
    cy, sy_ = math.cos(yaw), math.sin(yaw)
    items = []
    for p in puffs:
        ph, rate = p["phase"], p["rate"]
        d = p["drift"]
        home = p["pos"]
        base_size = p["size"]
        base_alpha = p["alpha"]
        if morph > 0.0 and "pos2" in p:
            home = [home[i] + (p["pos2"][i] - home[i]) * morph for i in range(3)]
            base_size = base_size + (p["size2"] - base_size) * morph
            base_alpha = base_alpha + (p.get("alpha2", base_alpha) - base_alpha) * morph
        anchor = [
            home[0] + math.sin(t * rate[0] + ph[0]) * d,
            home[1] + math.sin(t * rate[1] + ph[1]) * d * 0.7 + p["rise"] * t * 0.35,
            home[2] + math.sin(t * rate[2] + ph[2]) * d,
        ]
        spread = (1.0 - form) * 1.6
        pos = [anchor[i] + p["out"][i] * spread for i in range(3)]
        lx = pos[0] * math.cos(lean) - pos[1] * math.sin(lean)
        ly = pos[0] * math.sin(lean) + pos[1] * math.cos(lean)
        x = lx * cy + pos[2] * sy_
        z = -lx * sy_ + pos[2] * cy
        world = (origin[0] + x, origin[1] + ly, origin[2] + z)
        size = base_size * (1.0 + 0.12 * math.sin(t * rate[0] * 1.7 + ph[1])) * (1.0 + (1.0 - form) * 1.2)
        alpha = base_alpha * (0.75 + 0.25 * math.sin(t * rate[2] + ph[2])) * (form ** 0.6)
        items.append((cam.project(world, rend.w, rend.h), world, size, alpha, p["tint"]))
    for pr, world, size, alpha, tint in sorted(items, key=lambda it: -(it[0][2] if it[0] else 0)):
        splat(rend, cam, world, size, alpha, cols[tint], tex)
    for e in fig.embers:
        pos = e["pos"]
        size = e["size"]
        energy = e["energy"]
        if morph > 0.0 and "pos2" in e:
            pos = [pos[i] + (e["pos2"][i] - pos[i]) * morph for i in range(3)]
            size = size + (e["size2"] - size) * morph
            energy = energy + (e["energy2"] - energy) * morph
        lx = pos[0] * math.cos(lean) - pos[1] * math.sin(lean)
        ly = pos[0] * math.sin(lean) + pos[1] * math.cos(lean)
        x = lx * cy + pos[2] * sy_
        z = -lx * sy_ + pos[2] * cy
        world = (origin[0] + x, origin[1] + ly, origin[2] + z)
        splat(rend, cam, world, size * (0.7 + 0.5 * form), energy * ember * form,
              cols[e["key"]], tex, additive=True)


def scene(path, w, h, eye, target, fov, origin, form=1.0, t=0.0, ember=1.0, yaw=0.0, corr=True,
          lean=0.0, fig=None, morph=0.0, carrying=None):
    fig = fig or spec.corridor_figure()
    rend = Renderer(w, h, (6, 6, 8))
    cam = Camera(eye, target, fov=fov)
    rend.scale = cam.scale
    if corr:
        corridor(rend, cam)
    if carrying is not None:
        crate(rend, cam, carrying)
    draw(rend, cam, fig, origin, form, t, ember, yaw, lean, morph)
    rend.save(path)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "docs"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    o = args.out
    print(scene(os.path.join(o, "apparition_corridor.png"), 900, 620, (0.3, 1.55, -1.4), (0, 1.2, -9),
                40, (0.12, 0, -8.6), form=1.0, t=2.0))
    print(scene(os.path.join(o, "apparition_close.png"), 700, 800, (1.0, 1.6, -9.6), (0, 1.05, -12.6),
                36, (0, 0, -12.7), form=1.0, t=5.0, yaw=0.4))
    # crossing the mouth of the corridor: it leans into the slide and trails behind itself
    print(scene(os.path.join(o, "apparition_cross.png"), 900, 620, (0.2, 1.55, -1.4), (0, 1.2, -9),
                40, (-0.55, 0, -8.9), form=0.94, t=9.0, yaw=1.2, lean=-0.22))

    # the dissolve, four frames of a stare
    rend = Renderer(1000, 620, (6, 6, 8))
    for i, form in enumerate([1.0, 0.72, 0.42, 0.12]):
        sub = Renderer(250, 620, (6, 6, 8))
        cam = Camera((0, 1.45, -3.6), (0, 1.15, -8.6), fov=32)
        sub.scale = cam.scale
        corridor(sub, cam)
        draw(sub, cam, spec.corridor_figure(), (0, 0, -8.5), form=form, t=3.0 + i * 1.3,
             ember=1.0 - i * 0.22)
        for y in range(620):
            rend.color[y][i * 250:(i + 1) * 250] = sub.color[y]
            rend.color[y][i * 250] = (30, 30, 34)
    rend.save(os.path.join(o, "apparition_dissolve.png"))
    print(os.path.join(o, "apparition_dissolve.png"))

    ghoul = spec.ghoul_figure()
    print(scene(os.path.join(o, "ghoul_lure.png"), 900, 620, (0.3, 1.55, -1.4), (0, 1.2, -9),
                40, (0.10, 0, -8.8), t=2.0, fig=ghoul, morph=0.0))
    print(scene(os.path.join(o, "ghoul_true.png"), 820, 620, (1.15, 1.30, -9.0), (0, 0.80, -12.9),
                32, (0, 0, -12.9), t=6.0, yaw=0.75, fig=ghoul, morph=1.0))
    print(scene(os.path.join(o, "ghoul_hooves.png"), 700, 560, (0.95, 0.80, -11.3), (0, 0.42, -12.9),
                24, (0, 0, -12.9), t=2.5, yaw=0.3, fig=ghoul, morph=0.0))
    # the turn: five frames of it stopping pretending
    rend = Renderer(1150, 660, (6, 6, 8))
    for i, m in enumerate([0.0, 0.25, 0.5, 0.75, 1.0]):
        sub = Renderer(230, 660, (6, 6, 8))
        cam = Camera((0, 1.5, -2.2), (0, 1.05, -10.6), fov=32)
        sub.scale = cam.scale
        corridor(sub, cam)
        draw(sub, cam, ghoul, (0, 0, -10.6), t=4.0 + i * 0.9, morph=m)
        for y in range(660):
            rend.color[y][i * 230:(i + 1) * 230] = sub.color[y]
            rend.color[y][i * 230] = (30, 30, 34)
    rend.save(os.path.join(o, "ghoul_turn.png"))
    print(os.path.join(o, "ghoul_turn.png"))

    fae = spec.fae_figure()
    held = (0, 1.45, -7.6)
    print(scene(os.path.join(o, "fae_carry.png"), 900, 640, (0.3, 1.55, -2.0), (0, 1.45, -7.6),
                38, held, t=3.0, fig=fae, morph=0.0, carrying=held))
    print(scene(os.path.join(o, "fae_glamour_off.png"), 900, 640, (0.3, 1.55, -2.0), (0, 1.45, -7.6),
                38, held, t=3.0, fig=fae, morph=1.0, carrying=held))
    print(scene(os.path.join(o, "fae_close.png"), 820, 700, (0.85, 1.75, -5.9), (0, 1.42, -7.6),
                20, held, t=3.0, fig=fae, morph=1.0, carrying=held))
    # gather, carry, throw: the crate crosses the corridor and the lights let go of it
    rend = Renderer(1240, 560, (6, 6, 8))
    frames = [(-1.10, 0.25, 0.5), (-0.45, 1.0, 1.0), (0.35, 1.0, 1.0), (1.05, 0.0, 0.0)]
    for i, (x, form, ember_e) in enumerate(frames):
        sub = Renderer(310, 560, (6, 6, 8))
        cam = Camera((0.1, 1.55, -3.4), (0, 1.42, -8.0), fov=40)
        sub.scale = cam.scale
        corridor(sub, cam)
        pos = (x, 1.45 + 0.05 * i, -7.9)
        crate(sub, cam, pos, tumble=0.4 + i * 0.5)
        if form > 0.0:
            draw(sub, cam, fae, pos, form=form, t=3.0 + i * 0.7, ember=ember_e, morph=0.0)
        for y in range(560):
            rend.color[y][i * 310:(i + 1) * 310] = sub.color[y]
            rend.color[y][i * 310] = (30, 30, 34)
    rend.save(os.path.join(o, "fae_throw.png"))
    print(os.path.join(o, "fae_throw.png"))


if __name__ == "__main__":
    main()
