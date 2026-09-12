"""Minimal glTF 2.0 (.glb) generator for the Derelict Orbit asset kit.

Pure standard library - no numpy, no Blender. Build geometry from primitives into a
`Mesh`, then `write_glb()`. One glTF primitive is emitted per material, and material
names are the stable kit names that `scripts/palette.gd`'s KIT_MAP remaps onto the
station's real textured materials.

Conventions (same as kit/KIT_README.md):
  * 1 unit = 1 metre, Y up, counter-clockwise winding (glTF front faces).
  * Kit modules sit with their floor at y = 0. PROPS are different: they tumble in
    zero-G, so a prop is centred on its own origin and the origin is where it spins.
  * UVs are box-projected in world space at a constant texel density, so tiling
    textures can be dropped on without unwrapping (Godot uses triplanar anyway).
"""

import json
import math
import struct

TEXELS_PER_M = 0.5

# ---------------------------------------------------------------- materials

# name -> (base_color_rgba, metallic, roughness, emissive_rgb, emissive_strength, blend)
MATERIALS = {
    "Hull_Panel":  ((0.62, 0.65, 0.70, 1.0), 0.35, 0.62, None, 0.0, False),
    "Hull_Light":  ((0.66, 0.68, 0.72, 1.0), 0.60, 0.60, None, 0.0, False),
    "Hull_Dark":   ((0.40, 0.42, 0.46, 1.0), 0.40, 0.70, None, 0.0, False),
    "Floor_Grate": ((0.55, 0.56, 0.60, 1.0), 0.50, 0.75, None, 0.0, False),
    "Floor_Walk":  ((0.20, 0.21, 0.24, 1.0), 0.05, 0.90, None, 0.0, False),
    "Pipe_Steel":  ((0.55, 0.58, 0.60, 1.0), 0.50, 0.60, None, 0.0, False),
    "Pipe_Copper": ((0.50, 0.36, 0.26, 1.0), 0.90, 0.35, None, 0.0, False),
    "Accent_Warn": ((0.85, 0.62, 0.10, 1.0), 0.00, 0.80, None, 0.0, False),
    "Accent_Red":  ((0.70, 0.12, 0.08, 1.0), 0.10, 0.60, None, 0.0, False),
    "Door_Panel":  ((0.45, 0.47, 0.50, 1.0), 0.70, 0.50, None, 0.0, False),
    "Seal_Gasket": ((0.08, 0.08, 0.09, 1.0), 0.00, 0.95, None, 0.0, False),
    "Seat_Fabric": ((0.25, 0.30, 0.40, 1.0), 0.00, 0.95, None, 0.0, False),
    "Suit_Orange": ((0.90, 0.45, 0.10, 1.0), 0.00, 0.80, None, 0.0, False),
    "Suit_White":  ((0.85, 0.86, 0.88, 1.0), 0.00, 0.70, None, 0.0, False),
    "Foliage":     ((0.25, 0.55, 0.20, 1.0), 0.00, 0.90, None, 0.0, False),
    "Mat_Rubber":  ((0.10, 0.10, 0.11, 1.0), 0.00, 0.95, None, 0.0, False),
    "Light_Strip": ((0.24, 0.27, 0.30, 1.0), 0.00, 0.40, (0.80, 0.90, 1.00), 3.0, False),
    "Light_Warn":  ((0.30, 0.22, 0.06, 1.0), 0.00, 0.40, (1.00, 0.75, 0.20), 2.5, False),
    "Light_Data":  ((0.30, 0.21, 0.07, 1.0), 0.00, 0.40, (1.00, 0.70, 0.25), 2.5, False),
    "Light_Green": ((0.06, 0.30, 0.12, 1.0), 0.00, 0.40, (0.20, 1.00, 0.40), 2.5, False),
    "Screen_Lit":  ((0.10, 0.27, 0.30, 1.0), 0.00, 0.30, (0.35, 0.90, 1.00), 2.5, False),
    "Glass_Window": ((0.55, 0.70, 0.80, 0.14), 0.00, 0.05, None, 0.0, True),
    "Glass_Port":   ((0.55, 0.70, 0.80, 0.20), 0.00, 0.05, None, 0.0, True),
}


# ---------------------------------------------------------------- maths

def _mat_identity():
    return (1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0)


def _mat_mul(a, b):
    """Row-major 4x4 multiply: result applies b first, then a."""
    out = [0.0] * 16
    for r in range(4):
        for c in range(4):
            out[r * 4 + c] = sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4))
    return tuple(out)


def translate(x, y, z):
    return (1.0, 0.0, 0.0, x,
            0.0, 1.0, 0.0, y,
            0.0, 0.0, 1.0, z,
            0.0, 0.0, 0.0, 1.0)


def scale(x, y=None, z=None):
    if y is None:
        y = z = x
    return (x, 0.0, 0.0, 0.0,
            0.0, y, 0.0, 0.0,
            0.0, 0.0, z, 0.0,
            0.0, 0.0, 0.0, 1.0)


def rotate(axis, angle):
    """Rotation of `angle` radians about 'x', 'y' or 'z'."""
    c, s = math.cos(angle), math.sin(angle)
    if axis == "x":
        return (1.0, 0.0, 0.0, 0.0,
                0.0, c, -s, 0.0,
                0.0, s, c, 0.0,
                0.0, 0.0, 0.0, 1.0)
    if axis == "y":
        return (c, 0.0, s, 0.0,
                0.0, 1.0, 0.0, 0.0,
                -s, 0.0, c, 0.0,
                0.0, 0.0, 0.0, 1.0)
    if axis == "z":
        return (c, -s, 0.0, 0.0,
                s, c, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 0.0, 1.0)
    raise ValueError("axis must be x, y or z: %r" % (axis,))


def _xf_point(m, p):
    x, y, z = p
    return (m[0] * x + m[1] * y + m[2] * z + m[3],
            m[4] * x + m[5] * y + m[6] * z + m[7],
            m[8] * x + m[9] * y + m[10] * z + m[11])


def _xf_dir(m, v):
    x, y, z = v
    return (m[0] * x + m[1] * y + m[2] * z,
            m[4] * x + m[5] * y + m[6] * z,
            m[8] * x + m[9] * y + m[10] * z)


def _norm(v):
    n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if n < 1e-12:
        return (0.0, 1.0, 0.0)
    return (v[0] / n, v[1] / n, v[2] / n)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _box_uv(p, n):
    """Box projection: pick the plane the normal points most strongly along."""
    ax, ay, az = abs(n[0]), abs(n[1]), abs(n[2])
    if ay >= ax and ay >= az:
        u, v = p[0], p[2]
    elif ax >= az:
        u, v = p[2], p[1]
    else:
        u, v = p[0], p[1]
    return (u * TEXELS_PER_M, v * TEXELS_PER_M)


# ---------------------------------------------------------------- mesh

class Mesh:
    """Accumulates triangles grouped by material name, under a transform stack."""

    def __init__(self):
        self.surfaces = {}          # material name -> {"pos", "nrm", "uv", "idx"}
        self._stack = [_mat_identity()]

    # -- transform stack ------------------------------------------------

    @property
    def xf(self):
        return self._stack[-1]

    def push(self, *mats):
        m = self._stack[-1]
        for x in mats:
            m = _mat_mul(m, x)
        self._stack.append(m)
        return self

    def pop(self):
        self._stack.pop()
        return self

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.pop()
        return False

    # -- raw triangle emission ------------------------------------------

    def _surface(self, mat):
        if mat not in MATERIALS:
            raise KeyError("unknown material %r (see kitlib.MATERIALS)" % (mat,))
        return self.surfaces.setdefault(mat, {"pos": [], "nrm": [], "uv": [], "idx": []})

    def tri(self, mat, a, b, c, normal=None):
        """One triangle, corners counter-clockwise seen from the visible side."""
        s = self._surface(mat)
        m = self.xf
        a, b, c = _xf_point(m, a), _xf_point(m, b), _xf_point(m, c)
        n = _norm(_xf_dir(m, normal)) if normal else _norm(_cross(_sub(b, a), _sub(c, a)))
        base = len(s["pos"]) // 3
        for p in (a, b, c):
            s["pos"].extend(p)
            s["nrm"].extend(n)
            s["uv"].extend(_box_uv(p, n))
        s["idx"].extend((base, base + 1, base + 2))

    def quad(self, mat, a, b, c, d, normal=None):
        """Corners counter-clockwise seen from the visible side."""
        self.tri(mat, a, b, c, normal)
        self.tri(mat, a, c, d, normal)

    def poly(self, mat, pts, normal=None):
        """Convex polygon as a fan, counter-clockwise seen from the visible side."""
        for i in range(1, len(pts) - 1):
            self.tri(mat, pts[0], pts[i], pts[i + 1], normal)

    # -- primitives ------------------------------------------------------

    #: face order for box(): +X -X +Y -Y +Z -Z
    FACES = ("+x", "-x", "+y", "-y", "+z", "-z")

    def box(self, mat, center=(0, 0, 0), size=(1, 1, 1), faces=None, inward=False):
        cx, cy, cz = center
        hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        x0, x1 = cx - hx, cx + hx
        y0, y1 = cy - hy, cy + hy
        z0, z1 = cz - hz, cz + hz
        f = {
            "+x": (((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)), (1, 0, 0)),
            "-x": (((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)), (-1, 0, 0)),
            "+y": (((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)), (0, 1, 0)),
            "-y": (((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)), (0, -1, 0)),
            "+z": (((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)), (0, 0, 1)),
            "-z": (((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)), (0, 0, -1)),
        }
        for key in (faces or self.FACES):
            pts, n = f[key]
            if inward:
                self.quad(mat, pts[3], pts[2], pts[1], pts[0], (-n[0], -n[1], -n[2]))
            else:
                self.quad(mat, *pts, normal=n)
        return self

    @staticmethod
    def _axis_frame(axis):
        """(along, u, v) unit vectors for a cylinder axis given as 'x', 'y' or 'z'."""
        return {
            "x": ((1, 0, 0), (0, 1, 0), (0, 0, 1)),
            "y": ((0, 1, 0), (0, 0, 1), (1, 0, 0)),
            "z": ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
        }[axis]

    def cylinder(self, mat, center=(0, 0, 0), radius=0.5, length=1.0, axis="y",
                 segments=12, caps=True, r_top=None, cap_mat=None):
        """Cylinder (or truncated cone if r_top differs) centred on `center`."""
        r_top = radius if r_top is None else r_top
        along, u, v = self._axis_frame(axis)
        h = length / 2.0

        def pt(r, t, s):
            a = 2.0 * math.pi * t / segments
            cs, sn = math.cos(a), math.sin(a)
            return tuple(center[i] + along[i] * s * h + (u[i] * cs + v[i] * sn) * r
                         for i in range(3))

        slope = (radius - r_top) / length if length > 1e-9 else 0.0
        for t in range(segments):
            b0, b1 = pt(radius, t, -1), pt(radius, t + 1, -1)
            t0, t1 = pt(r_top, t, 1), pt(r_top, t + 1, 1)
            na = 2.0 * math.pi * (t + 0.5) / segments
            radial = tuple(u[i] * math.cos(na) + v[i] * math.sin(na) for i in range(3))
            n = _norm(tuple(radial[i] + along[i] * slope for i in range(3)))
            self.quad(mat, b0, b1, t1, t0, normal=n)
        if caps:
            cm = cap_mat or mat
            if radius > 1e-6:
                ring = [pt(radius, t, -1) for t in range(segments)]
                self.poly(cm, list(reversed(ring)), normal=tuple(-a for a in along))
            if r_top > 1e-6:
                ring = [pt(r_top, t, 1) for t in range(segments)]
                self.poly(cm, ring, normal=along)
        return self

    def tube(self, mat, center=(0, 0, 0), radius=0.5, thickness=0.05, length=1.0,
             axis="y", segments=12, caps=True):
        """Open-ended pipe: outer wall, inner wall, and optional annular end caps."""
        inner = max(radius - thickness, 1e-4)
        self.cylinder(mat, center, radius, length, axis, segments, caps=False)
        along, u, v = self._axis_frame(axis)
        h = length / 2.0

        def pt(r, t, s):
            a = 2.0 * math.pi * t / segments
            cs, sn = math.cos(a), math.sin(a)
            return tuple(center[i] + along[i] * s * h + (u[i] * cs + v[i] * sn) * r
                         for i in range(3))

        for t in range(segments):  # inner wall, normals pointing in
            b0, b1 = pt(inner, t, -1), pt(inner, t + 1, -1)
            t0, t1 = pt(inner, t, 1), pt(inner, t + 1, 1)
            na = 2.0 * math.pi * (t + 0.5) / segments
            n = tuple(-(u[i] * math.cos(na) + v[i] * math.sin(na)) for i in range(3))
            self.quad(mat, b1, b0, t0, t1, normal=n)
        if caps:
            for s, n in ((1, along), (-1, tuple(-a for a in along))):
                for t in range(segments):
                    o0, o1 = pt(radius, t, s), pt(radius, t + 1, s)
                    i0, i1 = pt(inner, t, s), pt(inner, t + 1, s)
                    if s > 0:
                        self.quad(mat, i0, o0, o1, i1, normal=n)
                    else:
                        self.quad(mat, o0, i0, i1, o1, normal=n)
        return self

    def sphere(self, mat, center=(0, 0, 0), radius=0.5, segments=12, rings=6,
               y0=-1.0, y1=1.0, lon0=0.0, lon1=1.0):
        """UV sphere. y0/y1 clip it to a band (-1 = south pole, 1 = north) for domes;
        lon0/lon1 clip it in longitude (0..1 of a full turn) for a visor-style patch."""
        def pt(i, j):
            lat = math.asin(max(-1.0, min(1.0, y0 + (y1 - y0) * j / rings)))
            lon = 2.0 * math.pi * (lon0 + (lon1 - lon0) * i / segments)
            n = (math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon))
            return tuple(center[k] + n[k] * radius for k in range(3)), n

        def same(p, q):
            return all(abs(p[k] - q[k]) < 1e-9 for k in range(3))

        for j in range(rings):
            for i in range(segments):
                a, na = pt(i, j)
                b, nb = pt(i + 1, j)
                c, nc = pt(i + 1, j + 1)
                d, nd = pt(i, j + 1)
                # at a pole the whole row collapses to one point; emit the single
                # non-degenerate triangle of the pair instead of two zero-area ones
                if not same(a, b):
                    self.tri(mat, a, b, c,
                             normal=_norm(tuple(na[k] + nb[k] + nc[k] for k in range(3))))
                if not same(c, d):
                    self.tri(mat, a, c, d,
                             normal=_norm(tuple(na[k] + nc[k] + nd[k] for k in range(3))))
        return self

    def torus(self, mat, center=(0, 0, 0), radius=0.5, tube_radius=0.06, axis="y",
              segments=16, sides=8, arc=1.0):
        """Ring of circular cross section; `arc` < 1 sweeps only part of the circle."""
        along, u, v = self._axis_frame(axis)

        def pt(i, j):
            a = 2.0 * math.pi * arc * i / segments
            b = 2.0 * math.pi * j / sides
            radial = tuple(u[k] * math.cos(a) + v[k] * math.sin(a) for k in range(3))
            n = tuple(radial[k] * math.cos(b) + along[k] * math.sin(b) for k in range(3))
            ring = tuple(center[k] + radial[k] * radius for k in range(3))
            return tuple(ring[k] + n[k] * tube_radius for k in range(3)), n

        for i in range(segments):
            for j in range(sides):
                a, na = pt(i, j)
                b, nb = pt(i + 1, j)
                c, nc = pt(i + 1, j + 1)
                d, nd = pt(i, j + 1)
                self.tri(mat, a, b, c, normal=_norm(tuple(na[k] + nb[k] + nc[k] for k in range(3))))
                self.tri(mat, a, c, d, normal=_norm(tuple(na[k] + nc[k] + nd[k] for k in range(3))))
        return self

    def frame(self, mat, center=(0, 0, 0), size=(1, 1, 1), bar=0.04, axis="y"):
        """Four rails along `axis` at the corners of the cross section - a cage/handrail."""
        cx, cy, cz = center
        idx = {"x": 0, "y": 1, "z": 2}[axis]
        hs = [size[0] / 2.0, size[1] / 2.0, size[2] / 2.0]
        others = [i for i in range(3) if i != idx]
        for sa in (-1, 1):
            for sb in (-1, 1):
                off = [0.0, 0.0, 0.0]
                off[others[0]] = sa * (hs[others[0]] - bar / 2.0)
                off[others[1]] = sb * (hs[others[1]] - bar / 2.0)
                bs = [bar, bar, bar]
                bs[idx] = size[idx]
                self.box(mat, (cx + off[0], cy + off[1], cz + off[2]), tuple(bs))
        return self

    # -- stats -----------------------------------------------------------

    def triangle_count(self):
        return sum(len(s["idx"]) // 3 for s in self.surfaces.values())

    def bounds(self):
        lo = [1e30] * 3
        hi = [-1e30] * 3
        for s in self.surfaces.values():
            p = s["pos"]
            for i in range(0, len(p), 3):
                for k in range(3):
                    lo[k] = min(lo[k], p[i + k])
                    hi[k] = max(hi[k], p[i + k])
        return tuple(lo), tuple(hi)


# ---------------------------------------------------------------- glb writer

def _pad(b, fill=b"\x00"):
    n = (-len(b)) % 4
    return b + fill * n


def write_glb(mesh, path, name="mesh"):
    """Write `mesh` as a single-node .glb. One primitive per material."""
    if not mesh.surfaces:
        raise ValueError("mesh is empty")

    buf = bytearray()
    accessors = []
    buffer_views = []

    def add_view(data, target):
        while len(buf) % 4:
            buf.append(0)
        offset = len(buf)
        buf.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset,
                             "byteLength": len(data), "target": target})
        return len(buffer_views) - 1

    def add_accessor(values, comps, ctype, target, minmax=False):
        fmt = {"f": "<%df", "I": "<%dI"}[ctype] % len(values)
        view = add_view(struct.pack(fmt, *values), target)
        acc = {"bufferView": view, "componentType": 5126 if ctype == "f" else 5125,
               "count": len(values) // comps,
               "type": {1: "SCALAR", 2: "VEC2", 3: "VEC3"}[comps]}
        if minmax:
            lo = [min(values[k::comps]) for k in range(comps)]
            hi = [max(values[k::comps]) for k in range(comps)]
            acc["min"], acc["max"] = lo, hi
        accessors.append(acc)
        return len(accessors) - 1

    used = [m for m in MATERIALS if m in mesh.surfaces]
    materials = []
    for m in used:
        base, metal, rough, emis, strength, blend = MATERIALS[m]
        entry = {
            "name": m,
            "pbrMetallicRoughness": {"baseColorFactor": list(base),
                                     "metallicFactor": metal,
                                     "roughnessFactor": rough},
            "doubleSided": bool(blend),
        }
        if emis:
            entry["emissiveFactor"] = list(emis)
            if strength and strength != 1.0:
                entry["extensions"] = {
                    "KHR_materials_emissive_strength": {"emissiveStrength": strength}}
        if blend:
            entry["alphaMode"] = "BLEND"
        materials.append(entry)

    primitives = []
    for mi, m in enumerate(used):
        s = mesh.surfaces[m]
        primitives.append({
            "attributes": {
                "POSITION": add_accessor(s["pos"], 3, "f", 34962, minmax=True),
                "NORMAL": add_accessor(s["nrm"], 3, "f", 34962),
                "TEXCOORD_0": add_accessor(s["uv"], 2, "f", 34962),
            },
            "indices": add_accessor(s["idx"], 1, "I", 34963),
            "material": mi,
            "mode": 4,
        })

    gltf = {
        "asset": {"version": "2.0", "generator": "derelict-orbit kitlib"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(buf)}],
    }
    if any("KHR_materials_emissive_strength" in m.get("extensions", {}) for m in materials):
        gltf["extensionsUsed"] = ["KHR_materials_emissive_strength"]

    js = _pad(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
    bn = _pad(bytes(buf))
    blob = (struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bn))
            + struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(bn), 0x004E4942) + bn)
    with open(path, "wb") as fh:
        fh.write(blob)
    return len(blob)
