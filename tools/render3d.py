"""A small z-buffered software renderer, so the assets in kit/ can be looked at without Godot.

Flat shading, one key light, one fill, ambient, plus an emission term so the runes and the eyes
read the way they will in the game. Writes PNG directly (zlib only). This is a check tool, not
something to judge the assets by - real materials and lighting look considerably better.
"""

import math
import struct
import zlib


def norm(v):
    l = math.sqrt(sum(c * c for c in v)) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


class Camera:
    """Look-at perspective camera."""

    def __init__(self, eye, target, up=(0, 1, 0), fov=38.0):
        self.eye = eye
        f = norm(sub(target, eye))
        r = norm(cross(f, up))
        u = cross(r, f)
        self.right, self.up, self.fwd = r, u, f
        self.scale = 1.0 / math.tan(math.radians(fov) * 0.5)

    def project(self, p, w, h):
        d = sub(p, self.eye)
        z = dot(d, self.fwd)
        if z < 0.01:
            return None
        x = dot(d, self.right) / z * self.scale
        y = dot(d, self.up) / z * self.scale
        return (w * 0.5 + x * h * 0.5, h * 0.5 - y * h * 0.5, z)


class Renderer:
    def __init__(self, w, h, bg=(9, 9, 11)):
        self.w, self.h = w, h
        self.color = [[bg] * w for _ in range(h)]
        self.depth = [[1e30] * w for _ in range(h)]
        self.key = norm((-0.45, 0.75, -0.6))
        self.fill = norm((0.8, 0.15, 0.5))
        self.ambient = 0.10
        self.key_energy = 0.95
        self.fill_energy = 0.22

    def shade(self, n, color, emission):
        lit = self.ambient + self.key_energy * max(0.0, dot(n, self.key)) \
            + self.fill_energy * max(0.0, dot(n, self.fill))
        out = []
        for i in range(3):
            v = color[i] * lit + emission[i]
            out.append(int(max(0, min(255, round(255 * (v ** (1 / 2.2)))))))
        return tuple(out)

    def triangle(self, cam, p0, p1, p2, color, emission=(0, 0, 0)):
        n = norm(cross(sub(p1, p0), sub(p2, p0)))
        if dot(n, sub(p0, cam.eye)) > 0:      # back face: flip so both sides shade sanely
            n = (-n[0], -n[1], -n[2])
        pr = [cam.project(p, self.w, self.h) for p in (p0, p1, p2)]
        if any(v is None for v in pr):
            return
        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = pr
        det = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(det) < 1e-9:
            return
        rgb = self.shade(n, color, emission)
        lo_x = max(0, int(min(x0, x1, x2)))
        hi_x = min(self.w - 1, int(max(x0, x1, x2)) + 1)
        lo_y = max(0, int(min(y0, y1, y2)))
        hi_y = min(self.h - 1, int(max(y0, y1, y2)) + 1)
        for py in range(lo_y, hi_y + 1):
            row_c = self.color[py]
            row_d = self.depth[py]
            for px in range(lo_x, hi_x + 1):
                a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / det
                if a < 0:
                    continue
                b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / det
                if b < 0 or a + b > 1:
                    continue
                z = a * z0 + b * z1 + (1 - a - b) * z2
                if z < row_d[px]:
                    row_d[px] = z
                    row_c[px] = rgb

    def save(self, path):
        raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in self.color)

        def chunk(tag, data):
            c = struct.pack(">I", len(data)) + tag + data
            return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(raw, 6))
               + chunk(b"IEND", b""))
        with open(path, "wb") as f:
            f.write(png)
        return len(png)


# ------------------------------------------------------------------ 4x4 transforms
def ident():
    return (1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)


def mat_mul(a, b):
    out = []
    for r in range(4):
        for c in range(4):
            out.append(sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4)))
    return tuple(out)


def translate(v):
    return (1, 0, 0, v[0], 0, 1, 0, v[1], 0, 0, 1, v[2], 0, 0, 0, 1)


def scale(v):
    return (v[0], 0, 0, 0, 0, v[1], 0, 0, 0, 0, v[2], 0, 0, 0, 0, 1)


def euler(deg):
    """XYZ euler in degrees, matching Godot's Node3D.rotation order (YXZ applied as X then Y then Z
    is close enough for a preview; the rig only ever uses one or two axes per joint)."""
    x, y, z = (math.radians(d) for d in deg)
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = (1, 0, 0, 0, 0, cx, -sx, 0, 0, sx, cx, 0, 0, 0, 0, 1)
    ry = (cy, 0, sy, 0, 0, 1, 0, 0, -sy, 0, cy, 0, 0, 0, 0, 1)
    rz = (cz, -sz, 0, 0, sz, cz, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    return mat_mul(ry, mat_mul(rx, rz))


def xform(m, p):
    return (m[0] * p[0] + m[1] * p[1] + m[2] * p[2] + m[3],
            m[4] * p[0] + m[5] * p[1] + m[6] * p[2] + m[7],
            m[8] * p[0] + m[9] * p[1] + m[10] * p[2] + m[11])
