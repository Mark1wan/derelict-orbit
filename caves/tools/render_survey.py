#!/usr/bin/env python3
"""Draw the Sowbelly survey - plan and extended elevation - from cave/sowbelly.json.

    python3 caves/tools/render_survey.py [out.png]

A cave survey is what cavers actually make: a plan view looking down, and an extended
elevation that unrolls the route along its own length so a passage that doubles back does not
draw over itself. Both are drawn here from the same file the game loads, so the picture cannot
disagree with the cave - which is the point, and the same reason derelict-orbit renders its
creature plates from the rig JSON rather than drawing them by hand.

Standard library only, like derelict-orbit's tools/render3d.py: the PNG is assembled from
zlib and struct, and the lettering is a 5x7 bitmap font defined at the bottom of this file.
No pillow, no matplotlib, no fonts on disk.
"""

import json
import math
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

W, H = 1500, 1000
BG = (14, 13, 12)
ROCK = (38, 35, 31)          # passage fill
EDGE = (120, 112, 98)        # passage outline
LINE = (74, 68, 59)          # centreline
MUD = (58, 46, 34)
WET = (44, 52, 58)
TEXT = (176, 168, 152)
DIM = (96, 90, 80)
HOT = (232, 176, 72)         # the crux, and anything that matters
GRID = (26, 25, 23)

PASSAGE_TINT = {
    "shaft": (44, 42, 38),
    "room": (52, 49, 44),
    "crawl": MUD,
    "rift": WET,
    "lead": (58, 40, 38),
}


# ---------------------------------------------------------------- canvas

class Canvas:
    def __init__(self, w, h, bg=BG):
        self.w, self.h = w, h
        self.px = [[bg[0], bg[1], bg[2]] * w for _ in range(h)]

    def set(self, x, y, c, a=1.0):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            row = self.px[y]
            i = x * 3
            if a >= 1.0:
                row[i], row[i + 1], row[i + 2] = c
            else:
                for k in range(3):
                    row[i + k] = int(row[i + k] * (1 - a) + c[k] * a)

    def line(self, x0, y0, x1, y1, c, width=1, a=1.0):
        dx, dy = x1 - x0, y1 - y0
        n = max(int(math.hypot(dx, dy)), 1)
        for s in range(n + 1):
            t = s / n
            x, y = x0 + dx * t, y0 + dy * t
            if width <= 1:
                self.set(x, y, c, a)
            else:
                r = width * 0.5
                for oy in range(int(-r) - 1, int(r) + 2):
                    for ox in range(int(-r) - 1, int(r) + 2):
                        if ox * ox + oy * oy <= r * r:
                            self.set(x + ox, y + oy, c, a)

    def poly(self, pts, c, a=1.0):
        """Filled polygon by scanline. Handles the concave outlines a passage produces."""
        if len(pts) < 3:
            return
        ys = [p[1] for p in pts]
        for y in range(max(int(min(ys)), 0), min(int(max(ys)) + 1, self.h)):
            xs = []
            for i in range(len(pts)):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % len(pts)]
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append(x0 + (x1 - x0) * (y - y0) / (y1 - y0))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(xs[i]), int(xs[i + 1]) + 1):
                    self.set(x, y, c, a)

    def rect(self, x, y, w, h, c, a=1.0):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                self.set(xx, yy, c, a)

    def text(self, x, y, s, c=TEXT, scale=1, spacing=1):
        """5x7 bitmap lettering. Returns the x it finished at."""
        cx = int(x)
        for ch in s.upper():
            glyph = FONT.get(ch)
            if glyph is None:
                cx += (5 + spacing) * scale
                continue
            for col, bits in enumerate(glyph):
                for row in range(7):
                    if bits & (1 << row):
                        if scale == 1:
                            self.set(cx + col, y + row, c)
                        else:
                            self.rect(cx + col * scale, y + row * scale, scale, scale, c)
            cx += (5 + spacing) * scale
        return cx

    def text_width(self, s, scale=1, spacing=1):
        return len(s) * (5 + spacing) * scale

    def save(self, path):
        raw = bytearray()
        for row in self.px:
            raw.append(0)
            raw.extend(row)
        def chunk(tag, data):
            out = struct.pack(">I", len(data)) + tag + data
            return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
               + chunk(b"IEND", b""))
        with open(path, "wb") as f:
            f.write(png)
        return len(png)


# ---------------------------------------------------------------- the survey

def spline_points(passage, step=0.5):
    """Same centreline the game builds, at survey resolution."""
    import check_fit
    return check_fit.spline([tuple(p) for p in passage["path"]], step)


def profile_at(passage, t):
    """(width, height) of the passage at fraction t, interpolated as Bore does."""
    keys = passage["profile"]
    a, b = keys[0], keys[-1]
    for i in range(len(keys) - 1):
        if keys[i].get("t", 0.0) <= t <= keys[i + 1].get("t", 1.0):
            a, b = keys[i], keys[i + 1]
            break
    ta, tb = a.get("t", 0.0), b.get("t", 1.0)
    f = 0.0 if tb - ta < 1e-6 else (t - ta) / (tb - ta)
    f = max(0.0, min(1.0, f))
    f = f * f * (3.0 - 2.0 * f)
    return (a.get("w", 1.0) + (b.get("w", 1.0) - a.get("w", 1.0)) * f,
            a.get("h", 1.0) + (b.get("h", 1.0) - a.get("h", 1.0)) * f)


def draw_plan(c, cave, box):
    """Looking straight down. Passage outlines at their true width.

    Sowbelly runs about 43 m along Z and 29 m across X, so the plan is turned a quarter turn to
    put its long axis across the page - which is what a caver drawing this by hand would do, and
    why the north arrow below points along +Z rather than up.
    """
    x0, y0, x1, y1 = box
    pts_all = []
    for p in cave["passages"]:
        pts_all += [(q[0], q[2]) for q in p["path"]]
    lo_x = min(q[0] for q in pts_all) - 4
    hi_x = max(q[0] for q in pts_all) + 4
    lo_z = min(q[1] for q in pts_all) - 4
    hi_z = max(q[1] for q in pts_all) + 4
    # Turned: world Z runs across the page, world X runs down it.
    scale = min((x1 - x0) / (hi_z - lo_z), (y1 - y0) / (hi_x - lo_x))
    # Centred in whichever axis it does not fill, so a compact cave sits in the middle of the
    # plate rather than pinned to one corner of it.
    pad_x = ((x1 - x0) - (hi_z - lo_z) * scale) / 2
    pad_y = ((y1 - y0) - (hi_x - lo_x) * scale) / 2

    def to_px(wx, wz):
        return (x0 + pad_x + (wz - lo_z) * scale, y0 + pad_y + (wx - lo_x) * scale)

    # 10 m grid, so the reader has a sense of size before reading any number.
    g = 10.0
    gx = math.ceil(lo_x / g) * g
    while gx < hi_x:
        a, b = to_px(gx, lo_z), to_px(gx, hi_z)
        c.line(a[0], a[1], b[0], b[1], GRID)
        gx += g
    gz = math.ceil(lo_z / g) * g
    while gz < hi_z:
        a, b = to_px(lo_x, gz), to_px(hi_x, gz)
        c.line(a[0], a[1], b[0], b[1], GRID)
        gz += g

    pending = []

    def label(px, py, s, col=TEXT):
        pending.append((px, py, s, col))

    def place(px, py, s, col=TEXT):
        """Keep labels off each other by nudging aside until the slot is free."""
        w = c.text_width(s)
        for step in range(14):
            y = py + step * 11 * (1 if step % 2 == 0 else -1)
            key = (int(px) // 8, int(y) // 11)
            if key not in _taken:
                _taken.add(key)
                for k in range(w // 8 + 1):
                    _taken.add((int(px) // 8 + k, int(y) // 11))
                c.text(px, y, s, col)
                return
        c.text(px, py, s, col)

    _taken = set()

    for p in cave["passages"]:
        pts = spline_points(p)
        total = sum(math.dist(pts[i], pts[i - 1]) for i in range(1, len(pts)))
        run = 0.0
        left, right = [], []
        for i, q in enumerate(pts):
            if i:
                run += math.dist(q, pts[i - 1])
            t = run / max(total, 0.001)
            w, _ = profile_at(p, t)
            if i == 0:
                d = (pts[1][0] - pts[0][0], pts[1][2] - pts[0][2])
            elif i == len(pts) - 1:
                d = (pts[-1][0] - pts[-2][0], pts[-1][2] - pts[-2][2])
            else:
                d = (pts[i + 1][0] - pts[i - 1][0], pts[i + 1][2] - pts[i - 1][2])
            n = math.hypot(*d) or 1.0
            nx, nz = -d[1] / n, d[0] / n
            left.append(to_px(q[0] + nx * w / 2, q[2] + nz * w / 2))
            right.append(to_px(q[0] - nx * w / 2, q[2] - nz * w / 2))
        c.poly(left + right[::-1], PASSAGE_TINT.get(p.get("kind"), ROCK))
        for side in (left, right):
            for i in range(len(side) - 1):
                c.line(side[i][0], side[i][1], side[i + 1][0], side[i + 1][1], EDGE)
        if p.get("kind") == "shaft":
            continue   # a vertical pitch is a dot from above; the elevation names it
        mid = pts[len(pts) // 2]
        mx, my = to_px(mid[0], mid[2])
        label(mx + 8, my - 3, p["label"])

    # Scale bar and a north arrow, because a survey without them is a drawing.
    for px, py, txt, col in pending:
        place(px, py, txt, col)

    bar = 20.0
    bx, by = x0 + 14, y1 - 22
    c.line(bx, by, bx + bar * scale, by, TEXT, 2)
    c.line(bx, by - 4, bx, by + 4, TEXT)
    c.line(bx + bar * scale, by - 4, bx + bar * scale, by + 4, TEXT)
    c.text(bx, by + 8, "20 M", DIM)
    nx, ny = x1 - 46, y0 + 20
    c.line(nx, ny, nx + 22, ny, TEXT, 2)
    c.line(nx + 22, ny, nx + 15, ny - 4, TEXT)
    c.line(nx + 22, ny, nx + 15, ny + 4, TEXT)
    c.text(nx + 26, ny - 3, "N", TEXT)


def draw_elevation(c, cave, box, crux):
    """Depth against distance along the route - the descent, unrolled."""
    x0, y0, x1, y1 = box
    order = [p for pid in cave["route"] for p in cave["passages"] if p["id"] == pid]
    total = 0.0
    segs = []
    for p in order:
        pts = spline_points(p)
        length = sum(math.dist(pts[i], pts[i - 1]) for i in range(1, len(pts)))
        segs.append((p, pts, total, length))
        total += length
    depths = [-q[1] for _, pts, _, _ in segs for q in pts]
    lo_d, hi_d = min(depths) - 3, max(depths) + 3
    sx = (x1 - x0) / max(total, 1.0)
    sy = (y1 - y0) / max(hi_d - lo_d, 1.0)

    for d in range(0, int(hi_d) + 10, 10):
        if d < lo_d:
            continue
        y = y0 + (d - lo_d) * sy
        c.line(x0, y, x1, y, GRID)
        c.text(x0 - 30, y - 3, "%d M" % d, DIM)

    for p, pts, base, length in segs:
        run = 0.0
        top, bot = [], []
        for i, q in enumerate(pts):
            if i:
                run += math.dist(q, pts[i - 1])
            t = run / max(length, 0.001)
            _, h = profile_at(p, t)
            px = x0 + (base + run) * sx
            d = -q[1]
            top.append((px, y0 + (d - h / 2 - lo_d) * sy))
            bot.append((px, y0 + (d + h / 2 - lo_d) * sy))
        c.poly(top + bot[::-1], PASSAGE_TINT.get(p.get("kind"), ROCK))
        for side in (top, bot):
            for i in range(len(side) - 1):
                c.line(side[i][0], side[i][1], side[i + 1][0], side[i + 1][1], EDGE)
        lx = x0 + (base + length / 2) * sx
        ly = top[len(top) // 2][1]
        c.text(lx - c.text_width(p["label"]) / 2, ly - 14, p["label"], TEXT)

        if p["id"] == "pinch" and crux:
            cx = x0 + (base + crux["along"]) * sx
            cy = top[min(int(crux["along"] / max(length, 0.001) * len(top)), len(top) - 1)][1]
            c.line(cx, cy - 34, cx, cy - 6, HOT, 2)
            label = "%.1f CM" % (crux["width"] * 100.0)
            c.text(cx - c.text_width(label) / 2, cy - 46, label, HOT)

    return sy / sx if sx > 0 else 1.0


def main(out_path):
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import check_fit

    with open(os.path.join(ROOT, "cave", "sowbelly.json"), encoding="utf-8") as f:
        cave = json.load(f)
    rows = check_fit.postures()
    relaxed, exhaled = check_fit.chest_depths()

    # The crux, measured rather than quoted, so the plate and the checker cannot disagree.
    crux = None
    pinch = next((p for p in cave["passages"] if p["id"] == "pinch"), None)
    if pinch:
        for dist, _, sec in check_fit.sections_along(pinch):
            w = max(q[0] for q in sec) - min(q[0] for q in sec)
            if crux is None or w < crux["width"]:
                crux = {"along": dist, "width": w}

    c = Canvas(W, H)
    c.text(40, 34, "SOWBELLY CAVE", TEXT, scale=3)
    c.text(40, 74, "PLAN AND EXTENDED ELEVATION - DRAWN FROM CAVE/SOWBELLY.JSON", DIM)

    deepest = max(-q[1] for p in cave["passages"] for q in p["path"])
    length = 0.0
    for p in cave["passages"]:
        pts = spline_points(p)
        length += sum(math.dist(pts[i], pts[i - 1]) for i in range(1, len(pts)))
    stats = "%d PASSAGES   %.0f M SURVEYED   %.1f M DEEP" % (len(cave["passages"]), length, deepest)
    c.text(W - 40 - c.text_width(stats), 74, stats, DIM)

    c.text(40, 108, "PLAN", TEXT, scale=2)
    draw_plan(c, cave, (60, 130, W - 60, 560))

    c.text(40, 592, "EXTENDED ELEVATION", TEXT, scale=2)
    exag = draw_elevation(c, cave, (110, 630, W - 60, 900), crux)
    note = "DISTANCE ALONG THE ROUTE, UNROLLED.  VERTICAL EXAGGERATION %.1fX" % exag
    c.text(W - 40 - c.text_width(note), 600, note, DIM)

    if crux:
        note = ("THE DEVIL'S PINCH IS %.1f CM AT ITS WORST.  A RELAXED CHEST IS %.1f CM.  "
                "FULLY EXHALED IT IS %.1f CM." % (crux["width"] * 100, relaxed * 100, exhaled * 100))
        c.text(40, 940, note, HOT)
    c.text(40, 962, "FICTIONAL CAVE.  REAL CAVING DIMENSIONS.  "
                    "REGENERATE WITH: PYTHON3 CAVES/TOOLS/RENDER_SURVEY.PY", DIM)

    size = c.save(out_path)
    print("%s  %dx%d  %.0f kB" % (out_path, W, H, size / 1024))
    print("%d passages, %.0f m surveyed, %.1f m deep" % (len(cave["passages"]), length, deepest))
    if crux:
        print("crux %.1f cm at %.1f m into the Devil's Pinch" % (crux["width"] * 100, crux["along"]))
    return 0


# ---------------------------------------------------------------- 5x7 font
# Each glyph is five columns; bit n of a column is row n from the top.

def _g(*rows):
    """Build column bitmaps from seven strings of five characters."""
    cols = [0] * 5
    for r, s in enumerate(rows):
        for col, ch in enumerate(s):
            if ch != " ":
                cols[col] |= 1 << r
    return cols


FONT = {
    "A": _g(" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"),
    "B": _g("#### ", "#   #", "#### ", "#   #", "#   #", "#   #", "#### "),
    "C": _g(" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "),
    "D": _g("#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "),
    "E": _g("#####", "#    ", "#### ", "#    ", "#    ", "#    ", "#####"),
    "F": _g("#####", "#    ", "#### ", "#    ", "#    ", "#    ", "#    "),
    "G": _g(" ### ", "#   #", "#    ", "#  ##", "#   #", "#   #", " ### "),
    "H": _g("#   #", "#   #", "#####", "#   #", "#   #", "#   #", "#   #"),
    "I": _g(" ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "),
    "J": _g("   ##", "    #", "    #", "    #", "#   #", "#   #", " ### "),
    "K": _g("#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"),
    "L": _g("#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"),
    "M": _g("#   #", "## ##", "# # #", "#   #", "#   #", "#   #", "#   #"),
    "N": _g("#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"),
    "O": _g(" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "),
    "P": _g("#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "),
    "Q": _g(" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"),
    "R": _g("#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"),
    "S": _g(" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "),
    "T": _g("#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "),
    "U": _g("#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "),
    "V": _g("#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "),
    "W": _g("#   #", "#   #", "#   #", "#   #", "# # #", "## ##", "#   #"),
    "X": _g("#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"),
    "Y": _g("#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "),
    "Z": _g("#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"),
    "0": _g(" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "),
    "1": _g("  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "),
    "2": _g(" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"),
    "3": _g("#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "),
    "4": _g("   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "),
    "5": _g("#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "),
    "6": _g("  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "),
    "7": _g("#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "),
    "8": _g(" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "),
    "9": _g(" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "),
    ".": _g("     ", "     ", "     ", "     ", "     ", " ##  ", " ##  "),
    ",": _g("     ", "     ", "     ", "     ", " ##  ", " ##  ", " #   "),
    "-": _g("     ", "     ", "     ", "#####", "     ", "     ", "     "),
    ":": _g("     ", " ##  ", " ##  ", "     ", " ##  ", " ##  ", "     "),
    "'": _g("  #  ", "  #  ", "     ", "     ", "     ", "     ", "     "),
    "/": _g("    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    "),
    "(": _g("   # ", "  #  ", " #   ", " #   ", " #   ", "  #  ", "   # "),
    ")": _g(" #   ", "  #  ", "   # ", "   # ", "   # ", "  #  ", " #   "),
    "+": _g("     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "),
    " ": [0, 0, 0, 0, 0],
}


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "survey.png")
    sys.exit(main(target))
