"""Shared machinery for posable creature rigs: bones, the parts hung off them, poses, and a
floor solver.

A rig is plain data - materials, a bone tree, primitive parts attached to bones, and poses that
are joint angles on top of the rest skeleton. `scripts/creature.gd` builds any of them in Godot
and `tools/render_creature.py` draws the same data, so the reference images cannot drift from
what the game shows.

Conventions: 1 unit = 1 m, Y up, the creature faces -Z (Godot's forward), origin on the floor
under it. Limb bones run down their own local -Y, so a rotation of 0 is a straight limb and the
angles in a pose are honest joint angles rather than fudged offsets.

(The night stalker's rig in creature_spec.py predates this module and still carries its own copy
of these helpers; anything new should be built on `Rig`.)
"""

import math
import random

from render3d import euler, mat_mul, translate, xform


def tip_of(base, rot, length):
    """Where a `cone` part of this length, at this rotation, ends - so the next segment of a horn
    or a claw can start exactly there instead of floating near it."""
    d = xform(euler(rot), (0.0, length, 0.0))
    return (base[0] + d[0], base[1] + d[1], base[2] + d[2])


class Rig:
    """One creature: materials, bones, parts, poses."""

    def __init__(self, name, materials):
        self.name = name
        self.materials = materials
        self.bones = []          # (name, parent, offset)
        self.parts = []
        self.poses = {}
        self.airborne = set()    # poses that are not supposed to rest on the floor

    # ------------------------------------------------------------------ skeleton
    def bone(self, name, parent, offset):
        self.bones.append((name, parent, list(offset)))

    def mirror_bones(self, spec_fn):
        """Add a left/right pair of chains. `spec_fn(side, sx)` calls self.bone()."""
        for side, sx in (("L", 1.0), ("R", -1.0)):
            spec_fn(side, sx)

    # ------------------------------------------------------------------ parts
    def part(self, bone, shape, mat, pos=(0, 0, 0), rot=(0, 0, 0), size=(0.1, 0.1, 0.1),
             r=0.0, h=0.0, r2=None):
        self.parts.append({"bone": bone, "shape": shape, "mat": mat, "pos": list(pos),
                           "rot": list(rot), "size": list(size), "r": r, "h": h,
                           "r2": r if r2 is None else r2})

    def limb(self, bone, mat, length, r_top, r_bot):
        """A tapered segment running down the bone's local -Y."""
        self.part(bone, "cone", mat, pos=(0, -length, 0), h=length, r=r_bot, r2=r_top)

    def spines(self, bone, mat, along, count, length, lean, seed, thick=0.012, jitter=14):
        """A row of stiff spines down a line on a bone - a dorsal crest, a ruff of quills."""
        rng = random.Random(seed)
        (x0, y0, z0), (x1, y1, z1) = along
        for i in range(count):
            t = (i + 0.5) / count
            pos = (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t)
            rot = (lean[0] + rng.uniform(-jitter, jitter),
                   lean[1] + rng.uniform(-jitter, jitter),
                   lean[2] + rng.uniform(-jitter, jitter))
            self.part(bone, "cone", mat, pos=pos, rot=rot,
                      h=length * rng.uniform(0.72, 1.25), r=thick, r2=0.0)

    def scatter(self, bone, mat, centre, radii, count, size, seed, flatten=1.0):
        """Mottling, warts, growths - small blisters over part of a body."""
        rng = random.Random(seed)
        for _ in range(count):
            v = [rng.gauss(0, 1) for _ in range(3)]
            n = math.sqrt(sum(x * x for x in v)) or 1.0
            p = [centre[i] + v[i] / n * radii[i] for i in range(3)]
            s = size * rng.uniform(0.6, 1.4)
            self.part(bone, "sph", mat, pos=p, size=(s, s * flatten, s))


    # ------------------------------------------------------------------ fur
    @staticmethod
    def _dir_to_rot(d, jitter, rng):
        """Euler (XYZ degrees, applied Y*X*Z like Godot) that points a strand's +Y along `d`."""
        l = math.sqrt(sum(v * v for v in d)) or 1.0
        d = [v / l for v in d]
        rx = math.degrees(math.acos(max(-1.0, min(1.0, d[1]))))
        ry = math.degrees(math.atan2(d[0], d[2]))
        return [rx + rng.uniform(-jitter, jitter), ry + rng.uniform(-jitter, jitter), 0.0]

    @staticmethod
    def _clear_of(pos, avoid):
        for a_pos, a_r in avoid:
            if sum((pos[i] - a_pos[i]) ** 2 for i in range(3)) < a_r * a_r:
                return False
        return True

    def fur_blob(self, bone, center, radii, count, sweep, length, seed, avoid=(), thick=0.016,
                 out=0.55, clump=4, keep=None):
        """A pelt over a rounded body part. Strands are grown off the surface of an ellipsoid,
        angled between the surface normal and `sweep` (which is the way the coat lies), in small
        clumps - fur scattered evenly reads as a hairbrush; fur that clumps reads as an animal.
        Raising `out` bristles it, lowering it lays it flat."""
        rng = random.Random(seed)
        made = 0
        guard = 0
        while made < count and guard < count * 40:
            guard += 1
            v = [rng.gauss(0, 1) for _ in range(3)]
            n = math.sqrt(sum(x * x for x in v)) or 1.0
            v = [x / n for x in v]
            base = [center[i] + v[i] * radii[i] * 0.97 for i in range(3)]
            if keep and not keep(base):
                continue
            if not self._clear_of(base, avoid):
                continue
            normal = [v[i] / radii[i] for i in range(3)]
            nl = math.sqrt(sum(x * x for x in normal)) or 1.0
            normal = [x / nl for x in normal]
            d = [normal[i] * out + sweep[i] for i in range(3)]
            ln = length * rng.uniform(0.7, 1.25)
            for _ in range(rng.randint(1, clump)):
                root = [base[i] + rng.uniform(-0.012, 0.012) for i in range(3)]
                self.part(bone, "strand", "hair", pos=root, rot=self._dir_to_rot(d, 11, rng),
                          h=ln * rng.uniform(0.8, 1.15), r=thick, r2=0.0)
                made += 1
                if made >= count:
                    break

    def fur_limb(self, bone, y0, y1, radius, count, sweep, length, seed, avoid=(), thick=0.014,
                 clump=4, out=0.5):
        """The same, wrapped around a limb segment running down the bone's -Y."""
        rng = random.Random(seed)
        made = 0
        guard = 0
        while made < count and guard < count * 40:
            guard += 1
            t = rng.uniform(0.0, 1.0)
            a = rng.uniform(0, math.tau)
            base = [math.cos(a) * radius * 0.95, y0 + (y1 - y0) * t, math.sin(a) * radius * 0.95]
            if not self._clear_of(base, avoid):
                continue
            d = [math.cos(a) * out + sweep[0], sweep[1], math.sin(a) * out + sweep[2]]
            ln = length * rng.uniform(0.7, 1.2)
            for _ in range(rng.randint(1, clump)):
                root = [base[i] + rng.uniform(-0.010, 0.010) for i in range(3)]
                self.part(bone, "strand", "hair", pos=root, rot=self._dir_to_rot(d, 10, rng),
                          h=ln * rng.uniform(0.8, 1.15), r=thick, r2=0.0)
                made += 1
                if made >= count:
                    break

    # ------------------------------------------------------------------ poses
    def pose(self, name, root_pos, root_rot, builder, airborne=False):
        d = {"root": list(root_rot)}
        builder(d)
        self.poses[name] = {"root_pos": list(root_pos), "bones": d}
        if airborne:
            self.airborne.add(name)

    @staticmethod
    def both(d, bone, rot, mirror=True):
        """Set a left/right pair. Mirroring negates the Y and Z angles, as a real mirror does."""
        d["%s_L" % bone] = list(rot)
        d["%s_R" % bone] = [rot[0], -rot[1], -rot[2]] if mirror else list(rot)

    # ------------------------------------------------------------------ the floor
    def _pose_min_y(self, pose, ignore_mats=()):
        """Lowest point of the posed model, walking the same forward kinematics the game does."""
        bones = {n: (p, o) for n, p, o in self.bones}
        xf = {}
        lo = 1e9
        for name, parent, offset in self.bones:
            local = mat_mul(translate(offset), euler(pose["bones"].get(name, [0, 0, 0])))
            if not parent:
                local = mat_mul(translate(pose["root_pos"]), local)
            xf[name] = local if not parent else mat_mul(xf[parent], local)
        for p in self.parts:
            if p["mat"] in ignore_mats:
                continue
            m = mat_mul(xf[p["bone"]], mat_mul(translate(p["pos"]), euler(p["rot"])))
            if p["shape"] in ("box", "sph"):
                ext = [v / 2 for v in p["size"]]
                corners = [(x * ext[0], y * ext[1], z * ext[2])
                           for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
            else:
                r = max(p["r"], p["r2"])
                corners = [(x * r, y, z * r) for x in (-1, 1) for y in (0.0, p["h"]) for z in (-1, 1)]
            for c in corners:
                lo = min(lo, xform(m, c)[1])
        return lo

    def settle(self, clearance=0.0, ignore_mats=()):
        """Drop or lift each pose so it rests on the floor, leaving the airborne ones alone."""
        for name, p in self.poses.items():
            if name in self.airborne:
                continue
            p["root_pos"][1] -= self._pose_min_y(p, ignore_mats) - clearance

    # ------------------------------------------------------------------ output
    def spec(self):
        return {
            "name": self.name,
            "materials": self.materials,
            "bones": [{"name": n, "parent": p, "offset": o} for n, p, o in self.bones],
            "parts": self.parts,
            "poses": self.poses,
        }
