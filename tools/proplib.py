"""Minimal glTF 2.0 (.glb) writer and the solid primitives the prop kit is built from.

No third-party modules: the geometry is accumulated as flat-shaded triangles grouped by
material, then written as one mesh with one primitive per material. Material names match
the ones the station kit already uses (see kit/KIT_README.md and scripts/palette.gd's
KIT_MAP), so props are remapped onto the game's textured materials for free.

Convention, same as the station kit: 1 unit = 1 m, Y up, the piece centred on the origin
with its resting face at y = 0 (props float, but a sane pivot keeps placement predictable).
UVs are box-projected in world space at 1 m per tile; Godot re-projects them triplanar
anyway, they are only there so the glTF is usable elsewhere.
"""

import json
import math
import struct

# name -> (base colour RGBA, metallic, roughness, emissive strength)
MATERIALS = {
    "Hull_Panel":  ((0.62, 0.65, 0.70, 1.0), 0.35, 0.62, 0.0),
    "Hull_Dark":   ((0.40, 0.42, 0.46, 1.0), 0.40, 0.70, 0.0),
    "Hull_Light":  ((0.66, 0.68, 0.72, 1.0), 0.60, 0.45, 0.0),
    "Floor_Grate": ((0.45, 0.46, 0.50, 1.0), 0.50, 0.75, 0.0),
    "Pipe_Steel":  ((0.55, 0.58, 0.60, 1.0), 0.50, 0.50, 0.0),
    "Pipe_Copper": ((0.50, 0.36, 0.26, 1.0), 0.90, 0.35, 0.0),
    "Accent_Warn": ((0.85, 0.62, 0.10, 1.0), 0.10, 0.60, 0.0),
    "Accent_Red":  ((0.70, 0.12, 0.08, 1.0), 0.10, 0.60, 0.0),
    "Door_Panel":  ((0.45, 0.47, 0.50, 1.0), 0.70, 0.50, 0.0),
    "Seal_Gasket": ((0.08, 0.08, 0.09, 1.0), 0.00, 0.95, 0.0),
    "Mat_Rubber":  ((0.10, 0.10, 0.11, 1.0), 0.00, 0.95, 0.0),
    "Suit_White":  ((0.85, 0.86, 0.88, 1.0), 0.00, 0.70, 0.0),
    "Suit_Orange": ((0.90, 0.45, 0.10, 1.0), 0.00, 0.80, 0.0),
    "Light_Strip": ((0.80, 0.90, 1.00, 1.0), 0.00, 0.40, 3.0),
    "Light_Warn":  ((1.00, 0.75, 0.20, 1.0), 0.00, 0.40, 3.0),
    "Light_Green": ((0.20, 1.00, 0.40, 1.0), 0.00, 0.40, 3.0),
    "Light_Data":  ((1.00, 0.70, 0.25, 1.0), 0.00, 0.40, 3.0),
    "Screen_Lit":  ((0.35, 0.90, 1.00, 1.0), 0.00, 0.40, 2.0),
    "Glass_Port":  ((0.18, 0.28, 0.38, 0.14), 0.10, 0.15, 0.0),
}

X, Y, Z = 0, 1, 2


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


class Mesh:
    """Triangle soup grouped by material name."""

    def __init__(self):
        self.tris = {}   # material -> list of (p0, p1, p2)

    def tri(self, mat, p0, p1, p2):
        # A quad with a corner on a sphere pole or a cone tip collapses two of its points into one.
        # That half is a zero-area triangle with no normal, so drop it instead of writing it.
        n = _cross(_sub(p1, p0), _sub(p2, p0))
        if n[0] * n[0] + n[1] * n[1] + n[2] * n[2] < 1e-18:
            return
        self.tris.setdefault(mat, []).append((p0, p1, p2))

    def quad(self, mat, p0, p1, p2, p3):
        """Counter-clockwise seen from the front face."""
        self.tri(mat, p0, p1, p2)
        self.tri(mat, p0, p2, p3)

    def box(self, mat, center, size):
        """Axis-aligned box, `center` at its middle."""
        cx, cy, cz = center
        hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        x0, x1 = cx - hx, cx + hx
        y0, y1 = cy - hy, cy + hy
        z0, z1 = cz - hz, cz + hz
        p = lambda x, y, z: (x, y, z)
        self.quad(mat, p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1))   # +Z
        self.quad(mat, p(x1, y0, z0), p(x0, y0, z0), p(x0, y1, z0), p(x1, y1, z0))   # -Z
        self.quad(mat, p(x1, y0, z1), p(x1, y0, z0), p(x1, y1, z0), p(x1, y1, z1))   # +X
        self.quad(mat, p(x0, y0, z0), p(x0, y0, z1), p(x0, y1, z1), p(x0, y1, z0))   # -X
        self.quad(mat, p(x0, y1, z1), p(x1, y1, z1), p(x1, y1, z0), p(x0, y1, z0))   # +Y
        self.quad(mat, p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1), p(x0, y0, z1))   # -Y

    def box_on(self, mat, center, size):
        """Box whose base sits at `center`'s y."""
        self.box(mat, (center[0], center[1] + size[1] / 2.0, center[2]), size)

    def cylinder(self, mat, base, radius, height, axis=Y, seg=12, caps=True, r_top=None):
        """Cylinder (or truncated cone when `r_top` differs) rising from `base` along `axis`."""
        r_top = radius if r_top is None else r_top

        def at(a, r, t):
            c, s = math.cos(t) * r, math.sin(t) * r
            if axis == Y:
                return (base[0] + c, base[1] + a, base[2] + s)
            if axis == X:
                return (base[0] + a, base[1] + c, base[2] + s)
            return (base[0] + c, base[1] + s, base[2] + a)

        top = (base[0], base[1], base[2])
        top = (top[0] + (height if axis == X else 0),
               top[1] + (height if axis == Y else 0),
               top[2] + (height if axis == Z else 0))
        for i in range(seg):
            t0 = i * 2 * math.pi / seg
            t1 = (i + 1) * 2 * math.pi / seg
            a0, b0 = at(0.0, radius, t0), at(0.0, radius, t1)
            a1, b1 = at(height, r_top, t0), at(height, r_top, t1)
            self.quad(mat, a0, b0, b1, a1)
            if caps:
                self.tri(mat, base, b0, a0)
                self.tri(mat, top, a1, b1)

    def sphere(self, mat, center, radius, seg=12, rings=6, y_min=-1.0, y_max=1.0,
               u_min=0.0, u_max=1.0):
        """UV sphere, optionally cut to a band of its height (y_min/y_max as fractions of the
        radius) and to an arc around Y (u_min/u_max as fractions of a turn) - a visor, a dome."""
        def at(u, v):
            phi = math.acos(max(-1.0, min(1.0, v)))
            return (center[0] + radius * math.sin(phi) * math.cos(u),
                    center[1] + radius * math.cos(phi),
                    center[2] + radius * math.sin(phi) * math.sin(u))
        for j in range(rings):
            v0 = y_max + (y_min - y_max) * j / rings
            v1 = y_max + (y_min - y_max) * (j + 1) / rings
            for i in range(seg):
                u0 = (u_min + (u_max - u_min) * i / seg) * 2 * math.pi
                u1 = (u_min + (u_max - u_min) * (i + 1) / seg) * 2 * math.pi
                a, b, c, d = at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)
                self.quad(mat, a, b, c, d)

    def frame(self, mat, center, size, bar):
        """Twelve edge bars of a box - a crate's corner cage."""
        cx, cy, cz = center
        hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        for sy in (-1, 1):
            for sz in (-1, 1):
                self.box(mat, (cx, cy + sy * hy, cz + sz * hz), (size[0], bar, bar))
            for sx in (-1, 1):
                self.box(mat, (cx + sx * hx, cy + sy * hy, cz), (bar, bar, size[2]))
        for sx in (-1, 1):
            for sz in (-1, 1):
                self.box(mat, (cx + sx * hx, cy, cz + sz * hz), (bar, size[1], bar))

    def settle(self):
        """Translate so the lowest vertex sits at y = 0 - a predictable pivot for placement."""
        pts = [p for tris in self.tris.values() for t in tris for p in t]
        dy = min(p[1] for p in pts)
        if abs(dy) < 1e-9:
            return
        for mat, tris in self.tris.items():
            self.tris[mat] = [tuple((p[0], p[1] - dy, p[2]) for p in t) for t in tris]

    def triangle_count(self):
        return sum(len(t) for t in self.tris.values())


def _uv(p, n):
    """Box projection: pick the plane most perpendicular to the face normal, 1 m per tile."""
    ax, ay, az = abs(n[0]), abs(n[1]), abs(n[2])
    if ay >= ax and ay >= az:
        return (p[0], p[2])
    if ax >= az:
        return (p[2], p[1])
    return (p[0], p[1])


def write_glb(mesh, path, name="prop"):
    """Write `mesh` as a single-node, single-mesh binary glTF."""
    bin_parts = []
    offset = 0
    accessors = []
    buffer_views = []
    primitives = []
    materials = []
    mat_index = {}

    def add_view(data, target):
        nonlocal offset
        pad = (-len(data)) % 4
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        bin_parts.append(data + b"\x00" * pad)
        offset += len(data) + pad
        return len(buffer_views) - 1

    for mat_name in sorted(mesh.tris):
        tris = mesh.tris[mat_name]
        if not tris:
            continue
        pos, nor, uvs, idx = [], [], [], []
        for p0, p1, p2 in tris:
            n = _norm(_cross(_sub(p1, p0), _sub(p2, p0)))
            base = len(pos) // 3
            for p in (p0, p1, p2):
                pos.extend(p)
                nor.extend(n)
                uvs.extend(_uv(p, n))
            idx.extend((base, base + 1, base + 2))

        lo = [min(pos[i::3]) for i in range(3)]
        hi = [max(pos[i::3]) for i in range(3)]
        v_pos = add_view(struct.pack("<%df" % len(pos), *pos), 34962)
        v_nor = add_view(struct.pack("<%df" % len(nor), *nor), 34962)
        v_uv = add_view(struct.pack("<%df" % len(uvs), *uvs), 34962)
        v_idx = add_view(struct.pack("<%dI" % len(idx), *idx), 34963)
        count = len(pos) // 3
        a = len(accessors)
        accessors.append({"bufferView": v_pos, "componentType": 5126, "count": count, "type": "VEC3", "min": lo, "max": hi})
        accessors.append({"bufferView": v_nor, "componentType": 5126, "count": count, "type": "VEC3"})
        accessors.append({"bufferView": v_uv, "componentType": 5126, "count": count, "type": "VEC2"})
        accessors.append({"bufferView": v_idx, "componentType": 5125, "count": len(idx), "type": "SCALAR"})

        if mat_name not in mat_index:
            color, metal, rough, emissive = MATERIALS[mat_name]
            m = {
                "name": mat_name,
                "pbrMetallicRoughness": {
                    "baseColorFactor": list(color),
                    "metallicFactor": metal,
                    "roughnessFactor": rough,
                },
                "doubleSided": False,
            }
            if emissive > 0.0:
                m["emissiveFactor"] = list(color[:3])
                m["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": emissive}}
            if color[3] < 1.0:
                m["alphaMode"] = "BLEND"
                m["doubleSided"] = True
            mat_index[mat_name] = len(materials)
            materials.append(m)

        primitives.append({
            "attributes": {"POSITION": a, "NORMAL": a + 1, "TEXCOORD_0": a + 2},
            "indices": a + 3,
            "material": mat_index[mat_name],
        })

    blob = b"".join(bin_parts)
    gltf = {
        "asset": {"version": "2.0", "generator": "derelict-orbit tools/build_props.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(blob)}],
    }
    if any("extensions" in m for m in materials):
        gltf["extensionsUsed"] = ["KHR_materials_emissive_strength"]

    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(blob), 0x004E4942) + blob
    with open(path, "wb") as f:
        f.write(out)
    return len(out)
