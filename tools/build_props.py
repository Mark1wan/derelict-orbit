#!/usr/bin/env python3
"""Builds the loose-prop kit: kit/prop_*.glb.

These are the small objects that drift through the station - the things you bump into,
grab to pull yourself along, and that get shoved around when the haunting escalates.
They use the same material names as the modular kit, so scripts/palette.gd remaps them
onto the game's textured materials with no extra work.

    python3 tools/build_props.py            # writes kit/prop_*.glb
    python3 tools/build_props.py --check    # re-parses every file it wrote

Each prop is modelled centred on X/Z with its base at y = 0 and is kept inside a 1 m box
so it fits a 3 m corridor at any tumble angle.
"""

import argparse
import hashlib
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from proplib import Mesh, write_glb, MATERIALS, X, Y, Z

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "kit")


def cargo_crate(m, s=0.52):
    """Ribbed supply crate: panelled faces, a corner cage, hazard corners and a latch."""
    h = s / 2.0
    m.box("Hull_Panel", (0, h, 0), (s * 0.94, s * 0.94, s * 0.94))
    m.frame("Hull_Dark", (0, h, 0), (s, s, s), s * 0.09)
    # recessed rib across two faces
    for zz in (-1, 1):
        m.box("Hull_Dark", (0, h, zz * s * 0.49), (s * 0.66, s * 0.16, s * 0.04))
    for xx in (-1, 1):
        m.box("Hull_Dark", (xx * s * 0.49, h, 0), (s * 0.04, s * 0.16, s * 0.66))
    # latch plate and handle on +Z
    m.box("Door_Panel", (0, h, s * 0.51), (s * 0.2, s * 0.12, s * 0.05))
    m.box("Accent_Warn", (0, s * 0.94, 0), (s * 0.5, s * 0.04, s * 0.5))
    # stencilled hazard stripe down one edge
    m.box("Accent_Warn", (s * 0.5, h, s * 0.5), (s * 0.1, s * 0.7, s * 0.1))


def cargo_crate_large(m):
    """Same family, a pallet-sized double-height box with a lid seam."""
    w, d, hgt = 0.78, 0.6, 0.56
    m.box("Hull_Panel", (0, hgt / 2, 0), (w * 0.95, hgt * 0.95, d * 0.95))
    m.frame("Hull_Dark", (0, hgt / 2, 0), (w, hgt, d), 0.055)
    m.box("Seal_Gasket", (0, hgt * 0.72, 0), (w * 1.01, 0.014, d * 1.01))
    for sx in (-1, 1):
        m.box("Door_Panel", (sx * w * 0.3, hgt * 0.72, d * 0.5), (0.1, 0.07, 0.035))
        m.box("Door_Panel", (sx * w * 0.3, hgt * 0.72, -d * 0.5), (0.1, 0.07, 0.035))
    m.box("Accent_Warn", (0, hgt * 0.3, d * 0.5), (w * 0.62, 0.07, 0.012))
    m.box("Hull_Dark", (0, 0.02, 0), (w * 0.8, 0.04, d * 0.8))     # skid


def gas_canister(m):
    """Pressure cylinder: domed ends, neck valve, protective collar, hazard band."""
    r, body = 0.13, 0.46
    y0 = r                      # the bottom dome rests on y = 0
    top = y0 + body
    m.cylinder("Pipe_Steel", (0, y0, 0), r, body, Y, 14)
    m.sphere("Pipe_Steel", (0, y0, 0), r, 14, 4, y_min=-1.0, y_max=0.0)
    m.sphere("Pipe_Steel", (0, top, 0), r, 14, 4, y_min=0.0, y_max=1.0)
    m.cylinder("Accent_Warn", (0, y0 + body * 0.35, 0), r * 1.02, 0.07, Y, 14, caps=False)
    neck = top + r * 0.6
    m.cylinder("Pipe_Copper", (0, neck, 0), 0.035, 0.09, Y, 8)
    m.cylinder("Door_Panel", (0, neck + 0.09, 0), 0.055, 0.03, Y, 8)          # valve wheel
    m.cylinder("Pipe_Copper", (-0.08, neck + 0.02, 0), 0.018, 0.08, X, 6)     # outlet
    for i in range(4):     # collar cage around the valve
        a = i * math.pi / 2 + math.pi / 4
        m.box("Hull_Dark", (math.cos(a) * r * 0.8, neck + 0.02, math.sin(a) * r * 0.8), (0.03, 0.16, 0.03))
    m.cylinder("Hull_Dark", (0, neck + 0.1, 0), r * 0.85, 0.03, Y, 14)


def toolbox(m):
    """Hinged tool case: lid lip, two catches, a carry handle, a lit charge indicator."""
    w, d, hgt = 0.44, 0.26, 0.2
    m.box("Accent_Red", (0, hgt / 2, 0), (w, hgt, d))
    m.box("Hull_Dark", (0, hgt * 0.78, 0), (w * 1.02, 0.02, d * 1.02))
    m.box("Hull_Dark", (0, hgt + 0.045, 0), (w * 0.34, 0.02, d * 0.5))     # handle plate
    m.box("Hull_Dark", (-w * 0.16, hgt + 0.022, 0), (0.02, 0.045, d * 0.5))
    m.box("Hull_Dark", (w * 0.16, hgt + 0.022, 0), (0.02, 0.045, d * 0.5))
    for sx in (-1, 1):
        m.box("Door_Panel", (sx * w * 0.3, hgt * 0.7, d * 0.5), (0.07, 0.06, 0.02))
    m.box("Light_Green", (w * 0.42, hgt * 0.4, d * 0.5), (0.05, 0.016, 0.012))


def med_kit(m):
    """Wall-pack first aid case with a red cross panel and a status light."""
    w, d, hgt = 0.34, 0.16, 0.28
    m.box("Suit_White", (0, hgt / 2, 0), (w, hgt, d))
    m.box("Hull_Dark", (0, hgt / 2, 0), (w * 1.02, 0.018, d * 1.02))
    for sz in (-1, 1):
        m.box("Accent_Red", (0, hgt * 0.55, sz * d * 0.51), (w * 0.5, 0.05, 0.008))
        m.box("Accent_Red", (0, hgt * 0.55, sz * d * 0.51), (0.05, w * 0.5, 0.008))
    m.box("Door_Panel", (0, hgt * 0.2, d * 0.5), (0.09, 0.035, 0.018))
    m.box("Light_Green", (w * 0.38, hgt * 0.85, d * 0.5), (0.04, 0.014, 0.01))
    m.box("Hull_Dark", (0, hgt + 0.02, 0), (w * 0.3, 0.04, d * 0.35))


def extinguisher(m):
    """Fire bottle: body, domed top, squeeze handle, hose loop, mounting bracket."""
    r, body = 0.08, 0.3
    y0 = r
    top = y0 + body
    m.cylinder("Accent_Red", (0, y0, 0), r, body, Y, 12)
    m.sphere("Accent_Red", (0, top, 0), r, 12, 4, y_min=0.0, y_max=1.0)
    m.sphere("Accent_Red", (0, y0, 0), r, 12, 3, y_min=-1.0, y_max=0.0)
    m.cylinder("Pipe_Steel", (0, top + r * 0.55, 0), 0.022, 0.05, Y, 8)
    m.box("Door_Panel", (0, top + r * 0.55 + 0.05, 0), (0.13, 0.022, 0.035))
    m.box("Door_Panel", (0.055, top + r * 0.55 + 0.02, 0), (0.02, 0.06, 0.03))
    m.cylinder("Seal_Gasket", (0.06, y0 + body * 0.4, 0), 0.012, 0.22, Y, 6)          # hose
    m.cylinder("Door_Panel", (0.06, y0 + body * 0.4 - 0.06, 0), 0.02, 0.06, Y, 6, r_top=0.012)
    m.box("Suit_White", (0, y0 + body * 0.5, r * 0.99), (0.09, 0.11, 0.006))          # label
    m.box("Hull_Dark", (0, y0 + body * 0.25, -r * 0.9), (0.12, 0.03, 0.05))           # bracket


def power_cell(m):
    """Swappable battery pack: finned case, contact block, charge LEDs."""
    w, d, hgt = 0.3, 0.18, 0.24
    m.box("Hull_Dark", (0, hgt / 2, 0), (w, hgt, d))
    for i in range(5):
        m.box("Pipe_Steel", (-w * 0.36 + i * w * 0.18, hgt * 0.5, 0), (0.022, hgt * 0.92, d * 1.05))
    m.box("Pipe_Copper", (0, hgt + 0.02, 0), (w * 0.4, 0.04, d * 0.5))     # contacts
    for i in range(4):
        m.box("Light_Green", (-w * 0.3 + i * w * 0.2, hgt * 0.2, d * 0.51), (0.035, 0.016, 0.008))
    m.box("Accent_Warn", (0, hgt * 0.8, d * 0.51), (w * 0.7, 0.03, 0.008))
    m.box("Hull_Panel", (0, 0.015, 0), (w * 1.04, 0.03, d * 1.04))


def helmet(m):
    """EVA helmet: shell, tinted visor, neck ring, lamp bosses."""
    r = 0.17
    m.sphere("Suit_White", (0, 0.2, 0), r, 14, 7, y_min=-0.55, y_max=1.0)
    m.sphere("Glass_Port", (0, 0.2, 0.0), r * 0.99, 10, 4, y_min=-0.3, y_max=0.6, u_min=0.06, u_max=0.44)
    m.cylinder("Hull_Light", (0, 0.03, 0), r * 0.62, 0.05, Y, 14)           # neck ring
    m.cylinder("Seal_Gasket", (0, 0.0, 0), r * 0.6, 0.035, Y, 14)
    m.cylinder("Hull_Light", (0, 0.08, 0), r * 0.66, 0.03, Y, 14)
    for sx in (-1, 1):
        m.cylinder("Door_Panel", (sx * r * 0.72, 0.26, 0), 0.028, 0.04, X, 8)
    m.box("Light_Strip", (0, 0.33, r * 0.62), (0.07, 0.025, 0.012))          # helmet lamp
    m.box("Accent_Warn", (0, 0.12, 0), (r * 1.4, 0.02, r * 1.4))


def data_slate(m):
    """Crew tablet: bezel, lit screen, a grab lip along the back."""
    w, hgt, t = 0.24, 0.32, 0.022
    m.box("Hull_Dark", (0, hgt / 2, 0), (w, hgt, t))
    m.box("Screen_Lit", (0, hgt * 0.52, t * 0.52), (w * 0.84, hgt * 0.78, 0.004))
    m.box("Light_Data", (0, hgt * 0.06, t * 0.52), (w * 0.3, 0.01, 0.004))
    m.box("Hull_Panel", (0, hgt / 2, -t * 0.6), (w * 0.7, hgt * 0.5, 0.008))
    for sx in (-1, 1):
        m.box("Mat_Rubber", (sx * w * 0.5, hgt / 2, 0), (0.012, hgt * 0.9, t * 1.2))


def drum(m):
    """Fluid drum: rolling hoops, bung caps, a stencil band."""
    r, hgt = 0.19, 0.56
    m.cylinder("Pipe_Copper", (0, 0.01, 0), r, hgt, Y, 14)
    for a in (hgt * 0.28, hgt * 0.62):
        m.cylinder("Hull_Dark", (0, 0.01 + a, 0), r * 1.06, 0.04, Y, 14, caps=False)
    m.cylinder("Hull_Dark", (0, 0.0, 0), r * 1.04, 0.035, Y, 14, caps=False)
    m.cylinder("Hull_Dark", (0, 0.01 + hgt - 0.035, 0), r * 1.04, 0.035, Y, 14, caps=False)
    for sx in (-1, 1):
        m.cylinder("Pipe_Steel", (sx * r * 0.5, 0.01 + hgt, 0), 0.035, 0.02, Y, 8)
    m.cylinder("Accent_Warn", (0, 0.01 + hgt * 0.44, 0), r * 1.01, 0.06, Y, 14, caps=False)


def debris_panel(m):
    """A torn-off hull panel: buckled skin, bent ribs, exposed insulation and a cut cable."""
    t = 0.025
    m.box("Hull_Panel", (0, t / 2, 0), (0.62, t, 0.4))
    m.box("Hull_Panel", (0.36, t * 2.4, -0.06), (0.2, 0.02, 0.3))         # folded corner
    m.box("Hull_Dark", (-0.1, t * 1.6, 0.12), (0.44, 0.03, 0.05))         # rib
    m.box("Hull_Dark", (-0.1, t * 1.6, -0.12), (0.44, 0.03, 0.05))
    m.box("Seal_Gasket", (-0.05, t * 1.3, 0), (0.34, 0.02, 0.16))         # insulation batt
    m.cylinder("Pipe_Copper", (-0.3, t * 1.6, 0.05), 0.012, 0.26, X, 6)   # trailing cable
    m.cylinder("Pipe_Copper", (-0.32, t * 1.6, -0.1), 0.01, 0.16, Z, 6)
    m.box("Accent_Warn", (0.12, t * 1.1, 0.16), (0.24, 0.012, 0.04))


def handhold(m):
    """Loose grab bar knocked off a wall - two feet and a bent rail."""
    m.cylinder("Pipe_Steel", (-0.22, 0.1, 0), 0.022, 0.44, X, 8)
    for sx in (-1, 1):
        m.cylinder("Pipe_Steel", (sx * 0.22, 0.02, 0), 0.022, 0.08, Y, 8)
        m.box("Door_Panel", (sx * 0.22, 0.012, 0), (0.09, 0.024, 0.09))
    m.box("Accent_Warn", (0, 0.1, 0), (0.1, 0.05, 0.05))


def ration_pack(m):
    """Sealed food pouch, printed side, a bit of crumple in the seam."""
    w, d, hgt = 0.22, 0.1, 0.3
    m.box("Suit_White", (0, hgt / 2, 0), (w, hgt * 0.86, d))
    m.box("Hull_Dark", (0, hgt * 0.94, 0), (w * 1.03, 0.03, d * 0.5))    # crimped seam
    m.box("Hull_Dark", (0, 0.012, 0), (w * 1.03, 0.024, d * 0.5))
    m.box("Accent_Warn", (0, hgt * 0.6, d * 0.51), (w * 0.7, 0.05, 0.006))
    m.box("Hull_Dark", (0, hgt * 0.35, d * 0.51), (w * 0.5, 0.09, 0.005))


PROPS = {
    "prop_crate": cargo_crate,
    "prop_crate_large": cargo_crate_large,
    "prop_canister": gas_canister,
    "prop_toolbox": toolbox,
    "prop_medkit": med_kit,
    "prop_extinguisher": extinguisher,
    "prop_power_cell": power_cell,
    "prop_helmet": helmet,
    "prop_slate": data_slate,
    "prop_drum": drum,
    "prop_debris": debris_panel,
    "prop_handhold": handhold,
    "prop_ration": ration_pack,
}


IMPORT_TEMPLATE = """[remap]

importer="scene"
importer_version=1
type="PackedScene"
uid="uid://{uid}"
path="res://.godot/imported/{name}.glb-{hash}.scn"

[deps]

source_file="res://kit/{name}.glb"
dest_files=["res://.godot/imported/{name}.glb-{hash}.scn"]

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{}}
gltf/naming_version=2
gltf/embedded_image_handling=1
gltf/texture_map_mode=1
"""


def write_import(name, out_dir):
    """Godot's .import sidecar, so the editor picks the prop up without a manual reimport.

    The resource uid is derived from the file name (Godot rewrites it if it ever clashes) and
    the cache file name is the md5 of the res:// path, which is how the importer names it.
    """
    path = os.path.join(out_dir, name + ".glb.import")
    if os.path.exists(path):
        return False
    digest = hashlib.md5(("res://kit/%s.glb" % name).encode()).hexdigest()
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
    n = int(hashlib.md5(("uid:" + name).encode()).hexdigest(), 16)
    uid = ""
    for _ in range(13):
        uid, n = uid + alphabet[n % len(alphabet)], n // len(alphabet)
    with open(path, "w") as f:
        f.write(IMPORT_TEMPLATE.format(uid=uid, name=name, hash=digest))
    return True


def bounds(mesh):
    pts = [p for tris in mesh.tris.values() for t in tris for p in t]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    return lo, hi


def check(path):
    """Re-parse a .glb: header, chunk sizes, and that every accessor fits its buffer view."""
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2, path
    assert length == len(data), "%s: header length %d != %d" % (path, length, len(data))
    jlen, jtype = struct.unpack_from("<II", data, 12)
    assert jtype == 0x4E4F534A
    gltf = json.loads(data[20:20 + jlen])
    blen, btype = struct.unpack_from("<II", data, 20 + jlen)
    assert btype == 0x004E4942
    assert 20 + jlen + 8 + blen == len(data)
    assert gltf["buffers"][0]["byteLength"] == blen
    size = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}
    comp = {5126: 4, 5125: 4}
    for acc in gltf["accessors"]:
        bv = gltf["bufferViews"][acc["bufferView"]]
        need = acc["count"] * size[acc["type"]] * comp[acc["componentType"]]
        assert need <= bv["byteLength"], "%s: accessor overruns its view" % path
        assert bv["byteOffset"] + bv["byteLength"] <= blen
    for prim in gltf["meshes"][0]["primitives"]:
        idx = gltf["accessors"][prim["indices"]]
        verts = gltf["accessors"][prim["attributes"]["POSITION"]]["count"]
        off = gltf["bufferViews"][idx["bufferView"]]["byteOffset"]
        raw = struct.unpack_from("<%dI" % idx["count"], data, 20 + jlen + 8 + off)
        assert max(raw) < verts, "%s: index out of range" % path
    for mat in gltf["materials"]:
        assert mat["name"] in MATERIALS
    return gltf


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=OUT_DIR, help="output directory (default: kit/)")
    ap.add_argument("--check", action="store_true", help="re-parse each file after writing")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    total = 0
    for name, build in sorted(PROPS.items()):
        mesh = Mesh()
        build(mesh)
        mesh.settle()
        lo, hi = bounds(mesh)
        span = max(hi[i] - lo[i] for i in range(3))
        assert span <= 1.0, "%s is %.2f m across - too big for a 3 m corridor" % (name, span)
        assert abs(lo[1]) < 1e-6, "%s does not rest on y = 0 (min y %.3f)" % (name, lo[1])
        path = os.path.join(args.out, name + ".glb")
        nbytes = write_glb(mesh, path, name)
        tris = mesh.triangle_count()
        total += tris
        mats = len(mesh.tris)
        write_import(name, args.out)
        if args.check:
            check(path)
        print("%-22s %5d tris  %2d mats  %6.2f x %.2f x %.2f m  %6d B"
              % (name, tris, mats, hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], nbytes))
    print("%d props, %d triangles total" % (len(PROPS), total))


if __name__ == "__main__":
    main()
