#!/usr/bin/env python3
"""Writes kit/creature_rig.json (the night stalker's skeleton, parts and poses) and the
reference renders in docs/.

    python3 tools/build_creature.py            # rig + docs/creature_poses.png
    python3 tools/build_creature.py --no-render

scripts/creature.gd reads the JSON at runtime, so the model in the game and the reference
images come from the same data - see tools/creature_spec.py for the rig itself.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import creature_spec as spec
import render_creature

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POSE_ORDER = ["upright", "crawl_a", "crawl_b", "dislocate", "contort", "freeze", "lunge", "coil"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-render", action="store_true")
    args = ap.parse_args()

    data = spec.spec()
    path = os.path.join(ROOT, "kit", "creature_rig.json")
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=False)
    counts = {}
    for p in data["parts"]:
        counts[p["mat"]] = counts.get(p["mat"], 0) + 1
    print("%s: %d bones, %d parts, %d poses, %.0f kB"
          % (os.path.relpath(path, ROOT), len(data["bones"]), len(data["parts"]),
             len(data["poses"]), os.path.getsize(path) / 1024.0))
    print("  parts by material: " + ", ".join("%s %d" % kv for kv in sorted(counts.items())))
    for name in POSE_ORDER:
        print("  pose %-10s root %.2f m" % (name, data["poses"][name]["root_pos"][1] + spec.HIP_Y))

    if args.no_render:
        return
    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    print(render_creature.sheet(POSE_ORDER, os.path.join(docs, "creature_poses.png")))


if __name__ == "__main__":
    main()
