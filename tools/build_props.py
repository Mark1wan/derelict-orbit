#!/usr/bin/env python3
"""Loose props and set dressing for Kestrel-9 - written to kit/props/*.glb.

Unlike the corridor and room modules (floor at y = 0, 4 m grid), a prop is
**centred on its own origin**: in zero-G every one of these tumbles, and the origin is
the point it spins about. Keep each one roughly symmetric about the origin, or it will
look like it is orbiting an invisible pivot.

Material names come from kitlib.MATERIALS and are the same stable set the corridor kit
uses, so scripts/palette.gd's KIT_MAP remaps them onto the station's real textured
materials with no extra wiring.

    python3 tools/build_props.py        # writes kit/props/*.glb
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from kitlib import Mesh, rotate, translate, write_glb  # noqa: E402

TAU = 2.0 * math.pi
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "kit", "props")

PROPS = {}


def prop(name, description):
    def deco(fn):
        PROPS[name] = (fn, description)
        return fn
    return deco


# ---------------------------------------------------------------- shared details

def bolts(m, mat, center, radius, count, axis="y", head=0.018, depth=0.012):
    """Ring of bolt heads - the cheapest thing that makes a flat panel read as hardware."""
    idx = {"x": 0, "y": 1, "z": 2}[axis]
    others = [i for i in range(3) if i != idx]
    for i in range(count):
        a = TAU * i / count
        p = list(center)
        p[others[0]] += math.cos(a) * radius
        p[others[1]] += math.sin(a) * radius
        m.cylinder(mat, tuple(p), head, depth, axis, segments=6)


def latch(m, center, size=(0.09, 0.05, 0.03)):
    """Toggle catch: a body plus a lighter lever."""
    m.box("Hull_Dark", center, size)
    m.box("Hull_Light", (center[0], center[1] + size[1] * 0.35, center[2] + size[2] * 0.55),
          (size[0] * 0.65, size[1] * 0.5, size[2] * 0.6))


def hazard_band(m, center, size, mat="Accent_Warn"):
    m.box(mat, center, size)


# ---------------------------------------------------------------- the props

@prop("prop_crate", "0.6 m ribbed cargo crate: corner posts, lid seam, latches, hazard stripe")
def crate(m):
    s = 0.60
    h = s / 2.0
    m.box("Hull_Panel", (0, 0, 0), (s, s, s))
    # corner posts down all four vertical edges
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box("Hull_Dark", (sx * (h - 0.03), 0, sz * (h - 0.03)), (0.07, s + 0.012, 0.07))
    # ribs across two faces
    for z in (-1, 1):
        for y in (-0.14, 0.14):
            m.box("Hull_Dark", (0, y, z * (h + 0.012)), (s - 0.12, 0.05, 0.03))
    # lid seam and latches
    m.box("Hull_Dark", (0, h - 0.05, 0), (s + 0.014, 0.02, s + 0.014))
    for z in (-1, 1):
        latch(m, (0, h - 0.05, z * (h + 0.025)), (0.10, 0.06, 0.035))
    # hazard stripe low on the ±X faces, and a lit status pip
    for sx in (-1, 1):
        hazard_band(m, (sx * (h + 0.008), -h + 0.09, 0), (0.012, 0.055, s - 0.10))
    m.cylinder("Light_Green", (0.12, h - 0.05, h + 0.02), 0.016, 0.016, "z", segments=8)


@prop("prop_crate_long", "1.1 m transport case: banded shell, recessed handles, stencil plate")
def crate_long(m):
    L, W, H = 1.10, 0.46, 0.40
    m.box("Hull_Panel", (0, 0, 0), (L, H, W))
    for x in (-0.34, 0.0, 0.34):  # strapping bands
        m.box("Hull_Dark", (x, 0, 0), (0.07, H + 0.014, W + 0.014))
    m.box("Hull_Dark", (0, H / 2 - 0.04, 0), (L + 0.012, 0.018, W + 0.012))  # lid seam
    for sx in (-1, 1):  # end handles
        m.box("Hull_Dark", (sx * (L / 2 + 0.012), 0, 0), (0.024, 0.20, W - 0.10))
        m.box("Hull_Light", (sx * (L / 2 + 0.05), 0, 0), (0.05, 0.035, W - 0.16))
    for sx in (-1, 1):  # latches on the long faces
        for sz in (-1, 1):
            latch(m, (sx * 0.17, H / 2 - 0.04, sz * (W / 2 + 0.022)), (0.09, 0.05, 0.032))
    m.box("Screen_Lit", (0.34, 0.03, W / 2 + 0.009), (0.13, 0.08, 0.004))  # manifest label


@prop("prop_canister", "0.9 m gas canister: domed ends, neck valve, guard collar, hazard band")
def canister(m):
    r, body = 0.14, 0.56
    m.cylinder("Pipe_Steel", (0, 0, 0), r, body, "y", segments=14, caps=False)
    m.sphere("Pipe_Steel", (0, body / 2, 0), r, segments=14, rings=3, y0=0.0, y1=1.0)
    m.sphere("Pipe_Steel", (0, -body / 2, 0), r, segments=14, rings=3, y0=-1.0, y1=0.0)
    hazard_band(m, (0, 0.10, 0), (r * 2 + 0.008, 0.07, r * 2 + 0.008))
    m.cylinder("Accent_Warn", (0, 0.10, 0), r + 0.004, 0.07, "y", segments=14, caps=False)
    # neck, valve body and handwheel
    m.cylinder("Hull_Dark", (0, body / 2 + r - 0.01, 0), 0.045, 0.09, "y", segments=10)
    m.box("Pipe_Copper", (0, body / 2 + r + 0.07, 0), (0.09, 0.07, 0.07))
    m.torus("Pipe_Copper", (0, body / 2 + r + 0.13, 0), 0.055, 0.012, "y", segments=12, sides=6)
    m.cylinder("Pipe_Copper", (0.075, body / 2 + r + 0.07, 0), 0.02, 0.05, "x", segments=8)
    # guard collar over the valve
    m.tube("Hull_Dark", (0, body / 2 + r + 0.10, 0), 0.10, 0.014, 0.12, "y", segments=12)
    # foot ring
    m.tube("Hull_Dark", (0, -body / 2 - r + 0.03, 0), r - 0.005, 0.012, 0.07, "y", segments=14)


@prop("prop_toolbox", "0.5 m tool chest: two drawers with pulls, lid handle, side clips")
def toolbox(m):
    W, H, D = 0.48, 0.30, 0.26
    m.box("Accent_Red", (0, -0.02, 0), (W, H * 0.72, D))
    m.box("Hull_Dark", (0, H * 0.36 - 0.02, 0), (W + 0.01, 0.02, D + 0.01))
    m.box("Accent_Red", (0, H * 0.36 + 0.05, 0), (W, 0.10, D))  # lid
    for y in (-0.10, 0.02):  # drawer fronts
        m.box("Hull_Dark", (0, y, D / 2 + 0.006), (W - 0.05, 0.085, 0.012))
        m.box("Hull_Light", (0, y, D / 2 + 0.022), (0.16, 0.022, 0.022))
    # carry handle over the lid
    m.box("Hull_Dark", (0, H * 0.36 + 0.12, 0), (0.20, 0.022, 0.03))
    for sx in (-1, 1):
        m.box("Hull_Dark", (sx * 0.09, H * 0.36 + 0.10, 0), (0.022, 0.05, 0.03))
        latch(m, (sx * 0.15, H * 0.36 - 0.02, D / 2 + 0.018), (0.07, 0.05, 0.03))
    m.box("Screen_Lit", (-0.15, 0.02, D / 2 + 0.014), (0.07, 0.045, 0.004))


@prop("prop_helmet", "EVA helmet: shell, tinted visor, neck ring, lamp pods and comms boom")
def helmet(m):
    r = 0.17
    m.sphere("Suit_White", (0, 0.02, 0), r, segments=16, rings=6, y0=-0.55, y1=1.0)
    # visor: a patch of the shell, not a band all the way round (+Z is "front")
    m.sphere("Glass_Port", (0, 0.03, 0.0), r + 0.010, segments=12, rings=5,
             y0=-0.38, y1=0.52, lon0=0.05, lon1=0.45)
    for lon in (0.05, 0.45):   # visor surround, up each side and across the brow
        m.sphere("Hull_Dark", (0, 0.03, 0.0), r + 0.012, segments=1, rings=5,
                 y0=-0.40, y1=0.54, lon0=lon - 0.02, lon1=lon + 0.02)
    m.sphere("Hull_Dark", (0, 0.03, 0.0), r + 0.012, segments=10, rings=1,
             y0=0.50, y1=0.60, lon0=0.03, lon1=0.47)
    # neck ring
    m.tube("Hull_Light", (0, -0.115, 0), 0.105, 0.016, 0.05, "y", segments=16)
    m.torus("Seal_Gasket", (0, -0.142, 0), 0.100, 0.013, "y", segments=16, sides=6)
    bolts(m, "Hull_Dark", (0, -0.092, 0), 0.098, 8, axis="y", head=0.011, depth=0.01)
    # lamp pods either side of the visor
    for sx in (-1, 1):
        m.cylinder("Hull_Dark", (sx * 0.135, 0.06, 0.06), 0.028, 0.05, "x", segments=8)
        m.cylinder("Light_Strip", (sx * 0.162, 0.06, 0.06), 0.021, 0.012, "x", segments=8)
    # comms boom and orange cap stripe
    m.cylinder("Hull_Dark", (0.10, -0.02, 0.10), 0.008, 0.12, "z", segments=6)
    m.box("Suit_Orange", (0, 0.17, -0.02), (0.10, 0.02, 0.13))


@prop("prop_extinguisher", "0.55 m extinguisher: bottle, squeeze handle, gauge, horn and hose")
def extinguisher(m):
    r, body = 0.085, 0.34
    m.cylinder("Accent_Red", (0, 0, 0), r, body, "y", segments=14, caps=False)
    m.sphere("Accent_Red", (0, body / 2, 0), r, segments=14, rings=3, y0=0.0, y1=1.0)
    m.sphere("Accent_Red", (0, -body / 2, 0), r, segments=14, rings=3, y0=-1.0, y1=0.0)
    m.box("Suit_White", (0, -0.02, r + 0.004), (0.10, 0.13, 0.006))  # instruction label
    # valve head, trigger, gauge
    m.cylinder("Hull_Dark", (0, body / 2 + r - 0.01, 0), 0.035, 0.08, "y", segments=10)
    m.box("Hull_Dark", (0, body / 2 + r + 0.06, 0), (0.05, 0.045, 0.11))
    m.box("Hull_Light", (0, body / 2 + r + 0.095, 0.01), (0.045, 0.022, 0.13))
    m.cylinder("Hull_Dark", (0.055, body / 2 + r + 0.06, 0), 0.028, 0.02, "x", segments=10)
    m.cylinder("Light_Green", (0.068, body / 2 + r + 0.06, 0), 0.021, 0.004, "x", segments=10)
    # hose arcing down the side into a horn
    m.torus("Mat_Rubber", (0.075, body / 2 + r - 0.02, -0.04), 0.10, 0.012, "z",
            segments=10, sides=6, arc=0.42)
    m.cylinder("Hull_Dark", (0.13, 0.04, -0.04), 0.022, 0.07, "y", segments=8,
               r_top=0.05, caps=True)
    # wall bracket band
    m.tube("Hull_Dark", (0, -0.06, 0), r + 0.012, 0.012, 0.045, "y", segments=14)


@prop("prop_datapad", "0.27 m data pad: lit screen, bezel, grip strap and hard case corners")
def datapad(m):
    W, H, T = 0.19, 0.27, 0.018
    m.box("Hull_Dark", (0, 0, 0), (W, H, T))
    m.box("Screen_Lit", (0, 0.012, T / 2 + 0.002), (W - 0.032, H - 0.055, 0.004))
    for sy in (-1, 1):  # rubber bumper corners
        for sx in (-1, 1):
            m.box("Mat_Rubber", (sx * (W / 2 - 0.018), sy * (H / 2 - 0.018), 0),
                  (0.042, 0.042, T + 0.01))
    m.box("Hull_Light", (0, -H / 2 + 0.022, T / 2 + 0.003), (0.05, 0.012, 0.004))  # home bar
    m.cylinder("Light_Green", (W / 2 - 0.028, H / 2 - 0.016, T / 2 + 0.003), 0.006, 0.004,
               "z", segments=6)
    # strap across the back
    m.box("Seat_Fabric", (0, 0, -T / 2 - 0.012), (0.05, H - 0.09, 0.022))


@prop("prop_cable_coil", "0.5 m coiled umbilical: three loops, tie wraps, capped end fittings")
def cable_coil(m):
    for i, r in enumerate((0.22, 0.195, 0.17)):
        m.push(translate(0, (i - 1) * 0.035, 0))
        m.torus("Mat_Rubber", (0, 0, 0), r, 0.026, "y", segments=18, sides=7)
        m.pop()
    for a in (0.0, TAU / 3, 2 * TAU / 3):  # tie wraps holding the bundle
        m.push(rotate("y", a), translate(0.195, 0, 0))
        m.box("Accent_Warn", (0, 0, 0), (0.05, 0.14, 0.014))
        m.pop()
    # both ends: a hose end with a coupling collar, hooked over the coil
    for sx, sz in ((1, 1), (-1, -1)):
        m.push(translate(sx * 0.20, 0.085, sz * 0.10), rotate("x", 0.4 * sz))
        m.cylinder("Mat_Rubber", (0, 0, 0), 0.026, 0.10, "y", segments=8)
        m.cylinder("Pipe_Copper", (0, 0.07, 0), 0.034, 0.05, "y", segments=10)
        m.torus("Hull_Dark", (0, 0.095, 0), 0.036, 0.009, "y", segments=10, sides=6)
        m.pop()


@prop("prop_oxygen_pack", "0.7 m life-support pack: twin tanks, frame, regulator, status LEDs")
def oxygen_pack(m):
    m.box("Hull_Dark", (0, 0, -0.07), (0.44, 0.50, 0.08))          # back plate
    m.frame("Hull_Light", (0, 0, -0.07), (0.46, 0.52, 0.10), bar=0.022, axis="y")
    for sx in (-1, 1):                                              # the two bottles
        m.cylinder("Suit_White", (sx * 0.12, 0, 0.03), 0.085, 0.36, "y", segments=12, caps=False)
        m.sphere("Suit_White", (sx * 0.12, 0.18, 0.03), 0.085, segments=12, rings=3, y0=0.0, y1=1.0)
        m.sphere("Suit_White", (sx * 0.12, -0.18, 0.03), 0.085, segments=12, rings=3, y0=-1.0, y1=0.0)
        m.cylinder("Accent_Warn", (sx * 0.12, 0.08, 0.03), 0.089, 0.05, "y", segments=12, caps=False)
        m.cylinder("Pipe_Copper", (sx * 0.12, 0.27, 0.03), 0.024, 0.06, "y", segments=8)
    # regulator block bridging the bottles, plus the LED row
    m.box("Hull_Dark", (0, 0.29, 0.03), (0.30, 0.06, 0.09))
    m.torus("Pipe_Copper", (0, 0.29, 0.03), 0.115, 0.011, "z", segments=12, sides=6, arc=0.5)
    for i, mat in enumerate(("Light_Green", "Light_Data", "Light_Warn")):
        m.cylinder(mat, (-0.05 + i * 0.05, 0.29, 0.082), 0.011, 0.006, "z", segments=6)
    # shoulder straps
    for sx in (-1, 1):
        m.box("Seat_Fabric", (sx * 0.15, 0.10, -0.115), (0.06, 0.28, 0.014))


@prop("prop_debris_panel", "0.9 m torn hull plate: bent lip, sheared ribs, exposed insulation")
def debris_panel(m):
    W, H, T = 0.90, 0.55, 0.022
    m.box("Hull_Panel", (0, 0, 0), (W, H, T))
    m.box("Seal_Gasket", (0, 0, -T / 2 - 0.008), (W - 0.06, H - 0.06, 0.016))   # insulation
    for x in (-0.26, 0.0, 0.26):                                                # stiffener ribs
        m.box("Hull_Dark", (x, 0, -T / 2 - 0.03), (0.05, H - 0.02, 0.05))
    for sx in (-1, 1):                                                          # bolt rows
        for i in range(4):
            m.cylinder("Hull_Dark", (sx * (W / 2 - 0.035), -0.18 + i * 0.12, T / 2),
                       0.014, 0.012, "z", segments=6)
    # the torn end: a bent-back lip and three ragged teeth
    m.push(translate(W / 2, 0, 0), rotate("y", -0.9))
    m.box("Hull_Panel", (0.055, 0, 0), (0.11, H - 0.05, T))
    m.pop()
    for i, (y, w) in enumerate(((0.16, 0.09), (-0.02, 0.13), (-0.19, 0.07))):
        m.push(translate(-W / 2, y, 0), rotate("z", 0.3 - 0.25 * i))
        m.tri("Hull_Panel", (0, w / 2, T / 2), (-0.10, 0, T / 2), (0, -w / 2, T / 2))
        m.tri("Hull_Panel", (0, -w / 2, -T / 2), (-0.10, 0, -T / 2), (0, w / 2, -T / 2))
        m.pop()
    # scorch-dark edge strip along the tear
    m.box("Floor_Walk", (-W / 2 + 0.03, 0, 0), (0.06, H + 0.004, T + 0.006))


@prop("prop_stowage_bag", "0.55 m fabric stowage bag: quilted panels, webbing, tag and clips")
def stowage_bag(m):
    W, H, D = 0.52, 0.34, 0.30
    m.box("Seat_Fabric", (0, 0, 0), (W, H, D))
    for sx in (-1, 1):   # soft corners: chamfer posts
        for sz in (-1, 1):
            m.box("Seat_Fabric", (sx * (W / 2 - 0.02), 0, sz * (D / 2 - 0.02)),
                  (0.05, H + 0.012, 0.05))
    for x in (-0.13, 0.13):   # webbing straps around the girth
        m.box("Hull_Dark", (x, 0, 0), (0.045, H + 0.014, D + 0.014))
        m.box("Hull_Light", (x, H / 2 + 0.012, 0), (0.05, 0.016, 0.06))
    m.box("Hull_Dark", (0, H / 2 - 0.03, 0), (W + 0.01, 0.016, D + 0.01))   # zip line
    for sx in (-1, 1):   # grab loops
        m.torus("Hull_Dark", (sx * (W / 2 + 0.005), 0.02, 0), 0.055, 0.012, "x",
                segments=12, sides=6, arc=0.5)
    m.box("Screen_Lit", (0.14, -0.06, D / 2 + 0.006), (0.11, 0.07, 0.004))  # inventory tag
    m.box("Accent_Warn", (-0.16, -0.10, D / 2 + 0.006), (0.09, 0.03, 0.005))


# ---------------------------------------------------------------- entry point

def build(names=None):
    os.makedirs(OUT_DIR, exist_ok=True)
    rows = []
    for name in sorted(PROPS):
        if names and name not in names:
            continue
        fn, desc = PROPS[name]
        m = Mesh()
        fn(m)
        path = os.path.join(OUT_DIR, name + ".glb")
        size = write_glb(m, path, name)
        lo, hi = m.bounds()
        dims = tuple(round(hi[i] - lo[i], 3) for i in range(3))
        rows.append((name, m.triangle_count(), len(m.surfaces), dims, size, desc))
    width = max(len(r[0]) for r in rows)
    for name, tris, surfs, dims, size, desc in rows:
        print("%-*s  %5d tris  %2d mats  %-22s %6.1f kB  %s"
              % (width, name, tris, surfs,
                 "%.2f x %.2f x %.2f m" % dims, size / 1024.0, desc))
    print("\n%d props, %d triangles total -> %s"
          % (len(rows), sum(r[1] for r in rows), OUT_DIR))
    return rows


if __name__ == "__main__":
    build(set(sys.argv[1:]) or None)
