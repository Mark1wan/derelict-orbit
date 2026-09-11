#!/usr/bin/env python3
"""Writes the creature rigs - kit/creature_rig.json (the night stalker) and
kit/chupacabra_rig.json - and the reference renders in docs/.

    python3 tools/build_creature.py            # both rigs + their pose sheets
    python3 tools/build_creature.py --rig chupacabra
    python3 tools/build_creature.py --no-render

scripts/creature.gd reads the JSON at runtime, so the model in the game and the reference images
come from the same data. The rigs themselves are tools/creature_spec.py (the stalker, which
predates tools/riglib.py and carries its own helpers) and tools/chupacabra_spec.py.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chupacabra_spec
import creature_spec
import render_creature

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# name -> (spec module, json file, pose order, sheet camera, hip height for the print-out)
RIGS = {
    "creature": (creature_spec, "creature_rig.json",
                 ["upright", "crawl_a", "crawl_b", "dislocate", "contort", "freeze", "lunge", "coil"],
                 {"eye": (2.4, 1.25, -3.0), "target": (0, 0.85, 0), "fov": 34.0},
                 creature_spec.HIP_Y),
    "chupacabra": (chupacabra_spec, "chupacabra_rig.json", chupacabra_spec.POSE_ORDER,
                   {"eye": (1.15, 0.60, -1.45), "target": (0, 0.30, 0), "fov": 36.0},
                   chupacabra_spec.HIP_Y),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rig", choices=sorted(RIGS) + ["all"], default="all")
    ap.add_argument("--no-render", action="store_true")
    args = ap.parse_args()

    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    names = sorted(RIGS) if args.rig == "all" else [args.rig]
    for name in names:
        module, filename, order, cam, hip = RIGS[name]
        data = module.spec()
        path = os.path.join(ROOT, "kit", filename)
        with open(path, "w") as f:
            json.dump(data, f, indent=1, sort_keys=False)
        counts = {}
        for p in data["parts"]:
            counts[p["mat"]] = counts.get(p["mat"], 0) + 1
        print("%s: %d bones, %d parts, %d poses, %.0f kB"
              % (os.path.relpath(path, ROOT), len(data["bones"]), len(data["parts"]),
                 len(data["poses"]), os.path.getsize(path) / 1024.0))
        print("  parts by material: " + ", ".join("%s %d" % kv for kv in sorted(counts.items())))
        for pose in order:
            print("  pose %-10s root %.2f m" % (pose, data["poses"][pose]["root_pos"][1] + hip))
        if args.no_render:
            continue
        sheet = "creature_poses.png" if name == "creature" else "%s_poses.png" % name
        print(render_creature.sheet(order, os.path.join(docs, sheet), rig=data, **cam))


if __name__ == "__main__":
    main()
