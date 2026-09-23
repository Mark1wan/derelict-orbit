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
  - the sections are sane: positive area, no profile keyframe out of order;
  - consecutive passages on the route really overlap, and their floors meet at the join.

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
    "rift": 8.0,
    "letterbox": 4.2,
    "keyhole": 2.0,
    "breakdown": 1.6,
}

SIDES = 22          # Bore.SIDES
STATION_STEP = 0.35 # Bore.STATION_STEP
MAX_STEP = 0.40     # metres of floor mismatch a body can get over at a junction

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


def posture_clear():
    """CaverBody.POSTURE_CLEAR: room over your head before the game picks a posture at all."""
    m = re.search(r"const POSTURE_CLEAR\s*:=\s*([\d.]+)", source("body.gd"))
    return float(m.group(1)) if m else 0.10


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


# ---------------------------------------------------------------- junctions

def frames(pts):
    """One (x, y, z) frame per station, mirroring Geo.frames in scripts/geo.gd."""
    n = len(pts)
    if n < 2:
        return []
    tan = []
    for i in range(n):
        if i == 0:
            a, b = pts[0], pts[1]
        elif i == n - 1:
            a, b = pts[n - 2], pts[n - 1]
        else:
            a, b = pts[i - 1], pts[i + 1]
        tan.append(norm((b[0] - a[0], b[1] - a[1], b[2] - a[2])))
    out, prev_x = [], None
    for t in tan:
        if abs(t[1]) < 0.94:
            x = norm(cross((0.0, 1.0, 0.0), t))            # levelled
        elif prev_x is not None:
            d = dot(prev_x, t)
            x = norm(tuple(prev_x[k] - t[k] * d for k in range(3)))  # vertical: carry it through
        else:
            x = norm(cross((0.0, 0.0, -1.0), t))
        y = norm(cross(t, x))
        out.append((x, y, t))
        prev_x = x
    return out


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(v):
    m = math.sqrt(dot(v, v)) or 1.0
    return (v[0] / m, v[1] / m, v[2] / m)


def in_polygon(sec, px, py):
    """Point in a closed section polygon - the same even-odd test as Geo.contains."""
    inside = False
    j = len(sec) - 1
    for i in range(len(sec)):
        a, b = sec[i], sec[j]
        if (a[1] > py) != (b[1] > py):
            if px < (b[0] - a[0]) * (py - a[1]) / (b[1] - a[1]) + a[0]:
                inside = not inside
        j = i
    return inside


def swallows(passage, world, stations=None, frs=None):
    """Is this world point inside the passage's open space? Returns the station index or None.

    The same test Bore.contains_point does at runtime, which is what decides whether one
    passage's faces are trimmed out of another's lumen. If it says no for a join, the two
    tubes do not actually meet and there is a wall between them.
    """
    stations = stations or sections_along(passage)
    frs = frs or frames([st[1] for st in stations])
    for i, (_, pos, sec) in enumerate(stations):
        fx, fy, fz = frs[i]
        off = (world[0] - pos[0], world[1] - pos[1], world[2] - pos[2])
        if abs(dot(off, fz)) > STATION_STEP * 1.5:
            continue
        if in_polygon(sec, dot(off, fx), dot(off, fy)):
            return i
    return None


def floor_at(stations, i):
    """World height of the passage floor at station i."""
    _, pos, sec = stations[i]
    return pos[1] + min(q[1] for q in sec)


def check_standing(cave, problems, rows, chest, gear, clear):
    """No tunnel you can stand up in.

    A room is allowed to be a room and a shaft is a hole you go down a rope, but everything
    between them is supposed to be a bore. Left to prose this rots the first time somebody
    nudges a profile keyframe, so it is a gate: if the posture the game would pick at any
    station of any tunnel is `stand`, the cave is wrong and the build says so.
    """
    print()
    shoulders = body_box(rows[0], chest, gear)[0]
    for p in cave["passages"]:
        if p.get("kind") in ("room", "shaft"):
            continue
        tallest = None
        for dist, _, sec in sections_along(p):
            gap = clearance(sec, shoulders)
            if tallest is None or gap > tallest[1]:
                tallest = (dist, gap)
            fit = best_posture(sec, rows, chest, gear, clear)
            if fit and fit[0] == "stand":
                problems.append(f"{p['id']}: you can stand up at {dist:.1f} m in "
                                f"- that is a room, not a tunnel")
        if tallest is None:
            continue
        print("  tunnel %-20s tallest %.2f m at %.1f m in   %s"
              % (p["label"], tallest[1], tallest[0],
                 "STANDS UP" if tallest[1] >= 1.75 else "ok"))


def check_route(cave, problems):
    """Consecutive passages on the route must actually meet, and meet at the same floor.

    Two tubes that stop short of each other leave a wall between them; two that meet with
    their floors half a metre apart leave a step a crawling body cannot climb. Neither shows
    up in a per-passage fit check, and both were real: the Pitch used to end inside a chamber
    shell nothing ever cut a hole in.
    """
    by_id = {p["id"]: p for p in cave["passages"]}
    cache = {}

    def load(pid):
        if pid not in cache:
            st = sections_along(by_id[pid])
            cache[pid] = (st, frames([s[1] for s in st]))
        return cache[pid]

    route = cave.get("route", [])
    print()
    for a_id, b_id in zip(route, route[1:]):
        if a_id not in by_id or b_id not in by_id:
            problems.append(f"route names '{a_id if a_id not in by_id else b_id}', "
                            "which is not a passage")
            continue
        a_st, a_fr = load(a_id)
        b_st, b_fr = load(b_id)
        # The join is an overlap, not a butt weld: either the end of one is inside the other,
        # or the start of the other is inside the one. A shaft landing in a room satisfies the
        # first; a crawl leaving a room satisfies the second.
        i = swallows(by_id[b_id], a_st[-1][1], b_st, b_fr)
        j = swallows(by_id[a_id], b_st[0][1], a_st, a_fr)
        gap = math.dist(a_st[-1][1], b_st[0][1])
        if i is None and j is None:
            problems.append(f"{a_id} -> {b_id}: the passages do not overlap "
                            f"({gap:.2f} m between their ends) - there is rock in the way")
            continue
        # Floors, compared at the place they actually meet: the mouth of the arriving
        # passage against the floor of the one it arrives into, at that same station. A step
        # you cannot climb is as impassable as a wall.
        if i is not None:
            fa, fb, via = floor_at(a_st, len(a_st) - 1), floor_at(b_st, i), "end inside"
        else:
            fa, fb, via = floor_at(a_st, j), floor_at(b_st, 0), "start inside"
        step = abs(fa - fb)
        note = "ok"
        if step > MAX_STEP:
            # A pitch is allowed to arrive from above - that is what the rope is for.
            if by_id[a_id].get("kind") == "shaft":
                note = "drop"
            else:
                problems.append(f"{a_id} -> {b_id}: floors are {step:.2f} m apart at the join "
                                f"- that is a step, not a passage")
                note = "STEP"
        print(f"  join {a_id:>10} -> {b_id:<10} ends {gap:>5.2f} m apart ({via}), "
              f"floors {step:>4.2f} m apart  {note}")


# ---------------------------------------------------------------- the check

def best_posture(sec, rows, chest, gear, clear=0.0):
    """The posture the game would actually pick here - the fastest one that fits - or None.

    This mirrors CaverBody.choose_posture: nobody crawls where they could walk. It is the
    pass/fail test, because if this returns None then no shape you can make gets through.

    `clear` is CaverBody.POSTURE_CLEAR, and it is why a passage can be passable at a posture the
    game will not choose: a body fits under 1.26 m of roof at 1.25 m tall and will not walk
    there, because a shape with a centimetre to spare reads as full contact and wedges. The
    SLACK reported is still measured against the real body, not against the threshold - what the
    crux table is for is how close the rock came, not how the chooser felt about it.
    """
    width = max(p[0] for p in sec) - min(p[0] for p in sec)
    best = None
    for row in rows:
        bw, bh = body_box(row, chest, gear)
        gap = clearance(sec, bw)
        # Only where there is no chest in the box: flat out and committed are the bottom of the
        # table and breathing out gets you out of them, so they take the rock as they find it.
        if gap < bh + (clear if row.get("chest", "none") == "none" else 0.0):
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
    clear = posture_clear()
    gear = cave.get("body_gear", 0.04)
    problems = []

    print(f"{cave['name']} - posture table from scripts/body.gd, "
          f"chest {relaxed * 100:.1f} cm relaxed / {exhaled * 100:.1f} cm exhaled, "
          f"{clear * 100:.0f} cm of headroom before a posture is worth taking\n")
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
            fit = best_posture(sec, rows, exhaled, gear, clear)
            if fit and (crux is None or fit[1] < crux[2]):
                crux = (dist, fit[0], fit[1], fit[2])
            if best_posture(sec, rows, relaxed, gear, clear) is None:
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
    check_standing(cave, problems, rows, relaxed, gear, clear)
    check_route(cave, problems)
    print(f"\n{len(cave['passages'])} passages, {total_len:.0f} m of survey, "
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
