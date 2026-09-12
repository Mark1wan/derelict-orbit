#!/usr/bin/env python3
"""Software preview renders of the kit .glb files - a PNG contact sheet.

The sandbox this kit is authored in has no Blender and no OpenGL, so this is a small
z-buffered rasteriser using nothing but the standard library. It exists to check
silhouettes, proportions and material assignment. It is deliberately crude: two-light
Lambert with a rim term, no shadows, no reflections. Judge the assets in Godot, not here.

    python3 tools/render_props.py                     # kit/props -> out/props_sheet.png
    python3 tools/render_props.py kit/room_eva.glb    # any glb, any number
"""

import glob
import math
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from validate_glb import parse_glb, read_accessor  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE = 300
COLS = 4
BG = (0.07, 0.08, 0.10)

KEY = (-0.45, 0.75, 0.55)      # key light direction (towards the light)
FILL = (0.6, -0.2, -0.5)       # cool bounce from the other side


def _norm(v):
    n = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / n for c in v)


# ---------------------------------------------------------------- tiny 3x5 font

GLYPHS = {
    "A": "010101111101101", "B": "110101110101110", "C": "011100100100011",
    "D": "110101101101110", "E": "111100111100111", "F": "111100111100100",
    "G": "011100101101011", "H": "101101111101101", "I": "111010010010111",
    "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
    "M": "101111111101101", "N": "101111111111101", "O": "010101101101010",
    "P": "110101110100100", "Q": "010101101111011", "R": "110101110101101",
    "S": "011100010001110", "T": "111010010010010", "U": "101101101101011",
    "V": "101101101010010", "W": "101101111111101", "X": "101101010101101",
    "Y": "101101010010010", "Z": "111001010100111",
    "0": "011101101101110", "1": "010110010010111", "2": "110001010100111",
    "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
    "6": "011100110101010", "7": "111001010010010", "8": "010101010101010",
    "9": "010101011001110", "_": "000000000000111", "-": "000000111000000",
    ".": "000000000000010", " ": "000000000000000", "/": "001001010100100",
}


def draw_text(px, w, h, x0, y0, text, colour, scale=2):
    for ci, ch in enumerate(text.upper()):
        g = GLYPHS.get(ch, GLYPHS[" "])
        for row in range(5):
            for col in range(3):
                if g[row * 3 + col] != "1":
                    continue
                for dy in range(scale):
                    for dx in range(scale):
                        x = x0 + (ci * 4 + col) * scale + dx
                        y = y0 + row * scale + dy
                        if 0 <= x < w and 0 <= y < h:
                            px[y * w + x] = colour


# ---------------------------------------------------------------- png

def write_png(path, w, h, px):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b = px[y * w + x]
            raw += bytes((r, g, b))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    blob = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(blob)
    return len(blob)


# ---------------------------------------------------------------- rasteriser

def load(path):
    """-> (triangles, bounds). Each triangle is (p0, p1, p2, normal, colour, emissive)."""
    js, bin_chunk = parse_glb(path)
    tris = []
    lo = [1e30] * 3
    hi = [-1e30] * 3
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            mat = js["materials"][prim["material"]]
            pbr = mat.get("pbrMetallicRoughness", {})
            base = pbr.get("baseColorFactor", [0.8, 0.8, 0.8, 1.0])
            emis = mat.get("emissiveFactor")
            alpha = base[3]
            pos = read_accessor(js, bin_chunk, prim["attributes"]["POSITION"])
            nrm = read_accessor(js, bin_chunk, prim["attributes"]["NORMAL"])
            idx = read_accessor(js, bin_chunk, prim["indices"])
            for v in range(0, len(pos), 3):
                for k in range(3):
                    lo[k] = min(lo[k], pos[v + k])
                    hi[k] = max(hi[k], pos[v + k])
            for t in range(0, len(idx), 3):
                a, b, c = idx[t], idx[t + 1], idx[t + 2]
                p = [tuple(pos[i * 3:i * 3 + 3]) for i in (a, b, c)]
                n = _norm(tuple(sum(nrm[i * 3 + k] for i in (a, b, c)) for k in range(3)))
                tris.append((p[0], p[1], p[2], n, tuple(base[:3]), emis, alpha))
    return tris, (tuple(lo), tuple(hi))


def render(path, size=TILE):
    tris, (lo, hi) = load(path)
    centre = tuple((lo[k] + hi[k]) / 2.0 for k in range(3))
    radius = max(math.sqrt(sum((hi[k] - lo[k]) ** 2 for k in range(3))) / 2.0, 1e-3)

    # 3/4 orbit camera looking at the centre
    yaw, pitch, dist = math.radians(34), math.radians(22), radius * 3.1
    eye = (centre[0] + dist * math.cos(pitch) * math.sin(yaw),
           centre[1] + dist * math.sin(pitch),
           centre[2] + dist * math.cos(pitch) * math.cos(yaw))
    fwd = _norm(tuple(centre[k] - eye[k] for k in range(3)))
    right = _norm((-fwd[2], 0.0, fwd[0]))
    up = (right[1] * fwd[2] - right[2] * fwd[1],
          right[2] * fwd[0] - right[0] * fwd[2],
          right[0] * fwd[1] - right[1] * fwd[0])
    focal = size / (2.0 * math.tan(math.radians(26)))

    px = [BG] * (size * size)
    zbuf = [1e30] * (size * size)
    key, fill = _norm(KEY), _norm(FILL)

    def project(p):
        d = tuple(p[k] - eye[k] for k in range(3))
        z = sum(d[k] * fwd[k] for k in range(3))
        if z <= 1e-4:
            return None
        x = sum(d[k] * right[k] for k in range(3))
        y = sum(d[k] * up[k] for k in range(3))
        return (size / 2.0 + x * focal / z, size / 2.0 - y * focal / z, z)

    for p0, p1, p2, n, base, emis, alpha in tris:
        s = [project(p) for p in (p0, p1, p2)]
        if any(v is None for v in s):
            continue
        # backface cull (screen-space winding)
        area = ((s[1][0] - s[0][0]) * (s[2][1] - s[0][1])
                - (s[2][0] - s[0][0]) * (s[1][1] - s[0][1]))
        if area >= -1e-9:
            continue

        view = _norm(tuple(eye[k] - (p0[k] + p1[k] + p2[k]) / 3.0 for k in range(3)))
        lam = max(0.0, sum(n[k] * key[k] for k in range(3)))
        amb = 0.16 + 0.24 * max(0.0, sum(n[k] * fill[k] for k in range(3)))
        rim = 0.35 * (1.0 - max(0.0, sum(n[k] * view[k] for k in range(3)))) ** 2.5
        shade = amb + 0.95 * lam
        col = [min(1.0, base[k] * shade + rim * 0.5) for k in range(3)]
        if emis:
            col = [min(1.0, col[k] * 0.35 + emis[k] * 0.9) for k in range(3)]

        x0 = max(0, int(min(v[0] for v in s)))
        x1 = min(size - 1, int(max(v[0] for v in s)) + 1)
        y0 = max(0, int(min(v[1] for v in s)))
        y1 = min(size - 1, int(max(v[1] for v in s)) + 1)
        inv = 1.0 / area
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                pxc, pyc = x + 0.5, y + 0.5
                w0 = ((s[1][0] - s[0][0]) * (pyc - s[0][1])
                      - (pxc - s[0][0]) * (s[1][1] - s[0][1])) * inv
                w1 = ((s[2][0] - s[1][0]) * (pyc - s[1][1])
                      - (pxc - s[1][0]) * (s[2][1] - s[1][1])) * inv
                w2 = 1.0 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                z = w1 * s[0][2] + w2 * s[1][2] + w0 * s[2][2]
                i = y * size + x
                if z >= zbuf[i]:
                    continue
                if alpha < 0.95:
                    # Glazing: tint without writing depth. Previews exaggerate the
                    # opacity - at the authored 0.14-0.20 a visor is invisible here,
                    # though it reads correctly against Godot's real transparency.
                    a = max(alpha, 0.5)
                    old = px[i]
                    px[i] = tuple(old[k] * (1 - a) + col[k] * a for k in range(3))
                    continue
                zbuf[i] = z
                px[i] = tuple(col)
    return px


def main(argv):
    files = argv[1:] or sorted(glob.glob(os.path.join(ROOT, "kit", "props", "*.glb")))
    if not files:
        print("no .glb files given or found in kit/props/")
        return 1
    cols = min(COLS, len(files))
    rows = (len(files) + cols - 1) // cols
    label_h = 22
    W, H = cols * TILE, rows * (TILE + label_h)
    sheet = [(0, 0, 0)] * (W * H)

    for i, f in enumerate(files):
        print("rendering %s" % os.path.relpath(f, ROOT))
        tile = render(f)
        cx, cy = (i % cols) * TILE, (i // cols) * (TILE + label_h)
        for y in range(TILE):
            for x in range(TILE):
                r, g, b = tile[y * TILE + x]
                sheet[(cy + y) * W + cx + x] = (int(r * 255), int(g * 255), int(b * 255))
        name = os.path.splitext(os.path.basename(f))[0]
        draw_text(sheet, W, H, cx + 8, cy + TILE + 7, name, (190, 205, 220), 2)

    out_dir = os.path.join(ROOT, "out")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "props_sheet.png")
    n = write_png(out, W, H, sheet)
    print("\n%d tiles -> %s (%dx%d, %.0f kB)" % (len(files), out, W, H, n / 1024.0))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
