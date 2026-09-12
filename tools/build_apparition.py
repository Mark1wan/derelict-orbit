#!/usr/bin/env python3
"""Writes kit/apparition_*.json for the whole apparition suite, and the reference renders in docs/.

    python3 tools/build_apparition.py              # rig + images
    python3 tools/build_apparition.py --no-render

scripts/apparition.gd reads the JSON; tools/render_apparition.py draws the same data with the
same smoke formula, so the images are a fair picture of what the game shows.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apparition_spec as spec

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-render", action="store_true")
    args = ap.parse_args()

    for name in sorted(spec.FIGURES):
        data = spec.FIGURES[name]().spec()
        path = os.path.join(ROOT, "kit", "apparition_%s.json" % name)
        with open(path, "w") as f:
            json.dump(data, f, indent=1)
        tints = {}
        morphing = 0
        for p in data["puffs"]:
            tints[p["tint"]] = tints.get(p["tint"], 0) + 1
            morphing += 1 if "pos2" in p else 0
        print("%s: %d puffs (%s%s), %d embers, %.0f kB"
              % (os.path.relpath(path, ROOT), len(data["puffs"]),
                 ", ".join("%s %d" % kv for kv in sorted(tints.items())),
                 ", %d morphing" % morphing if morphing else "",
                 len(data["embers"]), os.path.getsize(path) / 1024.0))

    if args.no_render:
        return
    import render_apparition
    sys.argv = [sys.argv[0]]
    render_apparition.main()


if __name__ == "__main__":
    main()
