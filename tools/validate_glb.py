#!/usr/bin/env python3
"""Re-parse every .glb under kit/ and check it independently of the generator.

Verifies the container (magic, version, chunk lengths), that every accessor and buffer
view lies inside the buffer, that indices are in range, that normals are unit length,
that no triangle is degenerate, and that material names are ones scripts/palette.gd
knows how to remap.

    python3 tools/validate_glb.py [file.glb ...]
"""

import glob
import json
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# glTF material names that scripts/palette.gd's KIT_MAP remaps. Anything outside this
# set silently falls through to the default metal material in Godot.
KNOWN_MATERIALS = {
    "Hull_Panel", "Hull_Light", "Hull_Dark", "Floor_Grate", "Floor_Walk",
    "Pipe_Steel", "Pipe_Copper", "Accent_Warn", "Accent_Red",
    "Light_Strip", "Light_Warn", "Screen_Lit", "Light_Data", "Light_Green",
    "Glass_Window", "Glass_Port", "Door_Panel", "Seal_Gasket", "Seat_Fabric",
    "Suit_Orange", "Suit_White", "Foliage", "Mat_Rubber",
}

COMPONENT = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2), 5121: ("B", 1)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def parse_glb(path):
    with open(path, "rb") as fh:
        blob = fh.read()
    if len(blob) < 12:
        raise ValueError("file shorter than a glb header")
    magic, version, total = struct.unpack_from("<III", blob, 0)
    if magic != 0x46546C67:
        raise ValueError("bad magic 0x%08X (not a .glb)" % magic)
    if version != 2:
        raise ValueError("glTF version %d, expected 2" % version)
    if total != len(blob):
        raise ValueError("header length %d != file size %d" % (total, len(blob)))
    off, js, bin_chunk = 12, None, b""
    while off < len(blob):
        clen, ctype = struct.unpack_from("<II", blob, off)
        off += 8
        if off + clen > len(blob):
            raise ValueError("chunk at %d overruns the file" % off)
        data = blob[off:off + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(data.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_chunk = data
        off += clen
        if off % 4:
            raise ValueError("chunk at %d is not 4-byte aligned" % off)
    if js is None:
        raise ValueError("no JSON chunk")
    return js, bin_chunk


def read_accessor(js, bin_chunk, index):
    acc = js["accessors"][index]
    view = js["bufferViews"][acc["bufferView"]]
    fmt, size = COMPONENT[acc["componentType"]]
    n = NCOMP[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"] * n
    if start + count * size > len(bin_chunk):
        raise ValueError("accessor %d runs past the end of the buffer" % index)
    return struct.unpack_from("<%d%s" % (count, fmt), bin_chunk, start)


def check(path):
    problems = []
    js, bin_chunk = parse_glb(path)

    declared = js["buffers"][0]["byteLength"]
    if declared > len(bin_chunk):
        problems.append("buffer declares %d bytes, BIN chunk holds %d" % (declared, len(bin_chunk)))
    for i, view in enumerate(js.get("bufferViews", [])):
        if view.get("byteOffset", 0) + view["byteLength"] > len(bin_chunk):
            problems.append("bufferView %d runs past the end of the buffer" % i)

    mats = [m.get("name", "") for m in js.get("materials", [])]
    for name in mats:
        if name not in KNOWN_MATERIALS:
            problems.append("material %r is not in palette.gd's KIT_MAP" % name)

    tris = 0
    for mesh in js["meshes"]:
        for p, prim in enumerate(mesh["primitives"]):
            if prim.get("mode", 4) != 4:
                problems.append("primitive %d is not TRIANGLES" % p)
            pos = read_accessor(js, bin_chunk, prim["attributes"]["POSITION"])
            nrm = read_accessor(js, bin_chunk, prim["attributes"]["NORMAL"])
            idx = read_accessor(js, bin_chunk, prim["indices"])
            nverts = len(pos) // 3
            if len(nrm) != len(pos):
                problems.append("primitive %d: NORMAL/POSITION count mismatch" % p)
            if len(idx) % 3:
                problems.append("primitive %d: index count %d is not a multiple of 3"
                                % (p, len(idx)))
            if idx and max(idx) >= nverts:
                problems.append("primitive %d: index %d out of range (%d verts)"
                                % (p, max(idx), nverts))
                continue
            tris += len(idx) // 3
            for v in range(nverts):
                n = nrm[v * 3:v * 3 + 3]
                ln = math.sqrt(sum(c * c for c in n))
                if abs(ln - 1.0) > 1e-3:
                    problems.append("primitive %d vertex %d: normal length %.4f" % (p, v, ln))
                    break
            degenerate = 0
            for t in range(0, len(idx), 3):
                a, b, c = (pos[idx[t + k] * 3:idx[t + k] * 3 + 3] for k in range(3))
                ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
                vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
                cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                if math.sqrt(cx * cx + cy * cy + cz * cz) < 1e-10:
                    degenerate += 1
            if degenerate:
                problems.append("primitive %d: %d degenerate triangles" % (p, degenerate))

            acc = js["accessors"][prim["attributes"]["POSITION"]]
            if "min" not in acc or "max" not in acc:
                problems.append("primitive %d: POSITION accessor has no min/max" % p)

    for ext in js.get("extensionsUsed", []):
        if ext != "KHR_materials_emissive_strength":
            problems.append("unexpected extension %r" % ext)
    return tris, len(mats), problems


def main(argv):
    files = argv[1:] or sorted(glob.glob(os.path.join(ROOT, "kit", "**", "*.glb"),
                                         recursive=True))
    if not files:
        print("no .glb files found under kit/")
        return 1
    width = max(len(os.path.relpath(f, ROOT)) for f in files)
    bad = 0
    for f in files:
        rel = os.path.relpath(f, ROOT)
        try:
            tris, nmats, problems = check(f)
        except Exception as exc:                     # noqa: BLE001 - report, don't crash
            print("%-*s  FAIL  %s" % (width, rel, exc))
            bad += 1
            continue
        if problems:
            bad += 1
            print("%-*s  FAIL  %5d tris" % (width, rel, tris))
            for p in problems[:6]:
                print("%s    - %s" % (" " * width, p))
            if len(problems) > 6:
                print("%s    ... and %d more" % (" " * width, len(problems) - 6))
        else:
            print("%-*s  ok    %5d tris  %2d materials" % (width, rel, tris, nmats))
    print("\n%d file(s) checked, %d failed" % (len(files), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
