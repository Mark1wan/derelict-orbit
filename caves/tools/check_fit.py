#!/usr/bin/env python3
"""Prove that Sowbelly can actually be caved.

A cave is data, and the data can lie. A profile keyframe edited by half a centimetre can pinch
a passage shut so that no posture fits through it, and nothing else in the build would notice -
the export succeeds, the cave renders, and the game is quietly unfinishable. So this runs first
in CI, before Godot is even downloaded, and it needs nothing but the standard library.

It re-implements two things from the game: the cross-section generator (scripts/geo.gd's
`section`, which turns w/h/shape/keel into a polygon) and the clearance scan (`clearance`,
which asks how tall a gap a body of a given width can find in that polygon). It reads the
posture table out of scripts/body.gd with a regex rather than keeping its own copy, the way
derelict-orbit's tools/simulate_run.py scrapes its constants out of the GDScript, so the two
cannot drift apart without this failing.

What it checks, per passage:

  - a through-passage is passable end to end in SOME posture at every station;
  - a passage marked `needs_exhale` really does reject a relaxed chest somewhere;
  - a passage marked `dead_end` really does pinch shut, and you can get far enough in to
    find that out;
  - the sections are sane: positive area, no profile keyframe out of order.

Usage:  python3 caves/tools/check_fit.py [cave/sowbelly.json]
Exit code 1 on any failure, and it says which station and by how much.
"""

import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Must match Geo.SHAPE_POWER in scripts/geo.gd.
SHAPE_POWER = {
    "tube": 2.0,
    "rift": 5.5,
    "letterbox": 4.2,
    "keyhole": 2.0,
    "breakdown": 1.6,
}

SIDES = 22          # Bore.SIDES
STATION_STEP = 0.35 # Bore.STATION_STEP

# Must match CaverBody.POSTURE_LABEL in scripts/body.gd.
POSTURE_TEXT = {
    "stand": "standing",
    "stoop": "stooping",
    "knees": "hands and knees",
    "belly": "flat out",
    "commit": "committed, sideways",
    "superman": "head first, arm ahead",
}


# ---------------------------------------------------------------- the GDScript, scraped

def source(name):
    with open(os.path.join(ROOT, "scripts", name), encoding="utf-8") as f:
        return f.read()


def postures():
    """The posture table out of body.gd, so there is exactly one copy of these numbers.

    Each row in the GDScript looks like:
        {"name": "belly", "h": 0.0, "w": 0.46, "chest": "h", "gear": 0.04, "speed": 0.35},
    where `chest` names the dimension that the chest depth supplies instead of a fixed number.
    """
    src = source("body.gd")
    block = re.search(r"const POSTURES\s*:=\s*\[(.*?)\n\]", src, re.S)
    if not block:
        raise SystemExit("check_fit: could not find `const POSTURES := [...]` in body.gd")
    rows = []
    for line in re.findall(r"\{[^{}]*\}", block.group(1)):
        row = {}
        for key, val in re.findall(r'"(\w+)"\s*:\s*("(?:[^"]*)"|[-\d.]+)', line):
            row[key] = val.strip('"') if val.startswith('"') else float(val)
        if "name" in row:
            rows.append(row)
    if not rows:
        raise SystemExit("check_fit: POSTURES in body.gd parsed as empty")
    return rows


def chest_depths():
    """(relaxed, exhaled) chest depth, also from body.gd."""
    src = source("body.gd")

    def num(pattern, fallback):
        m = re.search(pattern, src)
        return float(m.group(1)) if m else fallback

    relaxed = num(r"const CHEST_RELAXED\s*:=\s*([\d.]+)", 0.30)
    squeeze = num(r"const CHEST_SQUEEZE\s*:=\s*([\d.]+)", 0.035)
    return relaxed, relaxed - squeeze


def body_box(posture, chest, gear_default):
    """The (width, height) box this posture has to push through the rock."""
    gear = posture.get("gear", gear_default)
    w = posture.get("w", 0.46)
    h = posture.get("h", 1.75)
    axis = posture.get("chest", "none")
    if axis == "w":
        w = chest + gear
    elif axis == "h":
        h = chest + gear
    return w, h


# ---------------------------------------------------------------- geometry, mirrored from geo.gd

def section(shape, w, h, sides=SIDES, keel=0.0):
    a, b = w * 0.5, h * 0.5
    n = SHAPE_POWER.get(shape, 2.0)
    pts = []
    for i in range(sides):
        ang = 2.0 * math.pi * i / sides
        ca, sa = math.cos(ang), math.sin(ang)
        if shape == "keyhole":
            squeeze = 1.0 if sa >= 0.0 else 1.0 + (0.34 - 1.0) * min(-sa * 1.6, 1.0)
            x, y = ca * a * squeeze, sa * b
        else:
            d = (abs(ca) ** n + abs(sa) ** n) ** (-1.0 / n)
            x, y = ca * a * d, sa * b * d
        if keel > 0.0 and y < -b + keel:
            y = -b + keel
        pts.append((x, y))
    return pts


def span_at(sec, x):
    bot, top = math.inf, -math.inf
    n = len(sec)
    for i in range(n):
        px, py = sec[i]
        qx, qy = sec[(i + 1) % n]
        if (px <= x <= qx) or (qx <= x <= px):
            y = py if abs(qx - px) < 1e-9 else py + (qy - py) * (x - px) / (qx - px)
            bot, top = min(bot, y), max(top, y)
    return (0.0, 0.0) if bot is math.inf else (bot, top)


def clearance(sec, bw, samples=41):
    lo = min(p[0] for p in sec)
    hi = max(p[0] for p in sec)
    if hi - lo < bw:
        return -1.0
    best = -1.0
    for s in range(samples):
        f = s / max(samples - 1, 1)
        cx = (lo + bw * 0.5) + ((hi - bw * 0.5) - (lo + bw * 0.5)) * f
        top, bot, ok = math.inf, -math.inf, True
        for k in range(5):
            x = cx + (-bw * 0.5) + bw * (k / 4.0)
            sbot, stop = span_at(sec, x)
            if stop <= sbot:
                ok = False
                break
            bot, top = max(bot, sbot), min(top, stop)
        if ok and top - bot > best:
            best = top - bot
    return best


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(
        0.5 * ((2.0 * p1[k]) + (-p0[k] + p2[k]) * t
               + (2.0 * p0[k] - 5.0 * p1[k] + 4.0 * p2[k] - p3[k]) * t2
               + (-p0[k] + 3.0 * p1[k] - 3.0 * p2[k] + p3[k]) * t3)
        for k in range(3))


def spline(control, step=STATION_STEP):
    n = len(control)
    if n < 3:
        return list(control)
    out = []
    for i in range(n - 1):
        p0 = control[max(i - 1, 0)]
        p1, p2 = control[i], control[i + 1]
        p3 = control[min(i + 2, n - 1)]
        dist = math.dist(p1, p2)
        segs = max(int(math.ceil(dist / step)), 1)
        for s in range(segs):
            out.append(catmull(p0, p1, p2, p3, s / segs))
    out.append(tuple(control[-1]))
    return out


def sections_along(passage):
    """Every station's (distance along, section), exactly as Bore builds them."""
    pts = spline([tuple(p) for p in passage["path"]])
    along, run = [], 0.0
    for i, p in enumerate(pts):
        if i:
            run += math.dist(p, pts[i - 1])
        along.append(run)
    total = max(along[-1], 0.001)
    keys = passage["profile"]
    out = []
    for i, p in enumerate(pts):
        out.append((along[i], p, section_at(keys, along[i] / total)))
    return out


def section_at(keys, t):
    a, b = keys[0], keys[-1]
    for i in range(len(keys) - 1):
        if keys[i].get("t", 0.0) <= t <= keys[i + 1].get("t", 1.0):
            a, b = keys[i], keys[i + 1]
            break
    ta, tb = a.get("t", 0.0), b.get("t", 1.0)
    f = 0.0 if tb - ta < 1e-6 else smoothstep((t - ta) / (tb - ta))
    w = a.get("w", 1.0) + (b.get("w", 1.0) - a.get("w", 1.0)) * f
    h = a.get("h", 1.0) + (b.get("h", 1.0) - a.get("h", 1.0)) * f
    keel = a.get("keel", 0.0) + (b.get("keel", 0.0) - a.get("keel", 0.0)) * f
    sa = section(a.get("shape", "tube"), w, h, SIDES, keel)
    if a.get("shape", "tube") == b.get("shape", "tube"):
        return sa
    sb = section(b.get("shape", "tube"), w, h, SIDES, keel)
    return [(sa[i][0] + (sb[i][0] - sa[i][0]) * f,
             sa[i][1] + (sb[i][1] - sa[i][1]) * f) for i in range(SIDES)]


# ---------------------------------------------------------------- the check

def best_posture(sec, rows, chest, gear):
    """The posture the game would actually pick here - the fastest one that fits - or None.

    This mirrors CaverBody.choose_posture: nobody crawls where they could walk. It is the
    pass/fail test, because if this returns None then no shape you can make gets through.
    """
    width = max(p[0] for p in sec) - min(p[0] for p in sec)
    best = None
    for row in rows:
        bw, bh = body_box(row, chest, gear)
        gap = clearance(sec, bw)
        if gap < bh:
            continue
        # Slack is the SMALLER of the two margins, across the shoulders and through the
        # chest. A passage you clear vertically by half a metre and horizontally by nothing
        # is a squeeze, and reporting the half metre would be a lie.
        across = width - bw
        through = gap - bh
        if best is None or row["speed"] > best[3]:
            best = (row["name"], min(across, through),
                    ("%.2f m wide" % width) if across < through else ("%.2f m high" % gap),
                    row["speed"])
    return best[:3] if best else None


def main(path):
    with open(path, encoding="utf-8") as f:
        cave = json.load(f)
    rows = postures()
    relaxed, exhaled = chest_depths()
    gear = cave.get("body_gear", 0.04)
    problems = []

    print(f"{cave['name']} - posture table from scripts/body.gd, "
          f"chest {relaxed * 100:.1f} cm relaxed / {exhaled * 100:.1f} cm exhaled\n")
    print(f"{'passage':<19}{'len':>7}{'at':>7}  {'crux':<14}{'posture there':<24}"
          f"{'slack':>8}  {'relaxed':<20}")
    print("-" * 100)

    deepest = 0.0
    total_len = 0.0
    for p in cave["passages"]:
        stations = sections_along(p)
        total_len += stations[-1][0]
        deepest = min(deepest, min(s[1][1] for s in stations))

        # The crux is the station with the least room to spare for the best posture available
        # there - not the narrowest section, which for a bedding crawl is a wide flat slot you
        # walk through sideways and not the bit that stops you at all.
        crux = None
        blocked_relaxed = []
        blocked_exhaled = []
        for dist, pos, sec in stations:
            area = abs(sum(sec[i][0] * sec[(i + 1) % SIDES][1] - sec[(i + 1) % SIDES][0] * sec[i][1]
                           for i in range(SIDES))) * 0.5
            if area <= 1e-6:
                problems.append(f"{p['id']}: degenerate section at {dist:.1f} m")
            fit = best_posture(sec, rows, exhaled, gear)
            if fit and (crux is None or fit[1] < crux[2]):
                crux = (dist, fit[0], fit[1], fit[2])
            if best_posture(sec, rows, relaxed, gear) is None:
                blocked_relaxed.append(dist)
            if fit is None:
                blocked_exhaled.append(dist)

        if crux is None:
            crux = (0.0, "-", 0.0, "-")
        if blocked_relaxed:
            pct = blocked_relaxed[0] / max(stations[-1][0], 0.01) * 100
            rel = f"shut at {blocked_relaxed[0]:.1f} m ({pct:.0f}%)"
        else:
            rel = "goes"
        print(f"{p['label']:<19}{stations[-1][0]:>6.1f}m{crux[0]:>6.1f}m  {crux[3]:<14}"
              f"{POSTURE_TEXT.get(crux[1], crux[1]):<24}{crux[2] * 100:>6.1f}cm  {rel:<20}")

        if p.get("dead_end"):
            # A lead that pinches out is the point of a lead. Check it really does close, and
            # that you can get deep enough in to find out - a dead end you cannot enter is
            # just a wall, and does not teach anything.
            if not blocked_exhaled:
                problems.append(f"{p['id']}: marked dead_end but goes right through")
            elif blocked_exhaled[0] < stations[-1][0] * 0.45:
                problems.append(
                    f"{p['id']}: pinches shut at {blocked_exhaled[0]:.1f} m, only "
                    f"{blocked_exhaled[0] / stations[-1][0] * 100:.0f}% in - too soon to commit to")
            else:
                print(f"{'':32}  lead closes at {blocked_exhaled[0]:.1f} m "
                      f"({blocked_exhaled[0] / stations[-1][0] * 100:.0f}% in) - back out from there")
        else:
            if blocked_exhaled:
                problems.append(
                    f"{p['id']}: impassable at {blocked_exhaled[0]:.1f} m even fully exhaled "
                    f"(crux {crux[3]} at {crux[0]:.1f} m)")
            if p.get("needs_exhale") and not blocked_relaxed:
                problems.append(f"{p['id']}: marked needs_exhale but a relaxed chest walks it")

        for i in range(len(p["profile"]) - 1):
            if p["profile"][i].get("t", 0.0) > p["profile"][i + 1].get("t", 1.0):
                problems.append(f"{p['id']}: profile keyframes out of order at index {i}")

    print("-" * 100)
    print(f"{len(cave['passages'])} passages, {total_len:.0f} m of survey, "
          f"deepest point {-deepest:.1f} m below the entrance")

    # The squeeze the whole cave is built around: name it, and say by how much.
    pinch = next((p for p in cave["passages"] if p["id"] == "pinch"), None)
    if pinch:
        narrow = min(max(q[0] for q in s[2]) - min(q[0] for q in s[2])
                     for s in sections_along(pinch))
        print(f"\n{pinch['label']}: {narrow * 100:.1f} cm at its worst. "
              f"Chest {relaxed * 100:.1f} cm relaxed - no. "
              f"{exhaled * 100:.1f} cm exhaled - {(narrow - exhaled) * 1000:+.0f} mm.")
        if narrow >= relaxed:
            problems.append("pinch: a relaxed chest fits - the cave's one hard squeeze is free")
        if narrow < exhaled:
            problems.append(f"pinch: {narrow * 100:.1f} cm is narrower than an exhaled chest - nobody gets through")

    if problems:
        print("\nFAIL")
        for p in problems:
            print("  - " + p)
        return 1
    print("\nok - every through-passage goes, every lead closes")
    return 0


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "cave", "sowbelly.json")
    sys.exit(main(arg))
