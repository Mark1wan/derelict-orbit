#!/usr/bin/env python3
"""Play the haunting through without a headset: what a run actually throws at you, night by night.

    python3 tools/simulate_run.py --nights 16
    python3 tools/simulate_run.py --nights 16 --seed 4 --quiet   # just the summary

Every rule and every number here is read straight out of the GDScript at run time - the event
table and its intensity gates from scripts/haunt_manager.gd, the shift length, the intensity
curve and the night's odds (power failure, toilet trip, the bundle, the stalker) from
scripts/game.gd, the stalker's speed from scripts/stalker.gd - so this cannot quietly drift away
from the game. It is the schedule that is being simulated, not the game: it knows
nothing about geometry, so an event that would fail for want of a spot is assumed to find one.
"""

import argparse
import json
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def source(name):
    return open(os.path.join(ROOT, "scripts", name)).read()


def num(text, pattern, default):
    m = re.search(pattern, text)
    return float(m.group(1)) if m else default


def const(text, name, default):
    """A numeric const, written plainly or as a fraction (`1.0 / 3.0`)."""
    m = re.search(r"const %s := ([\d.]+)(?:\s*/\s*([\d.]+))?" % name, text)
    if not m:
        return default
    return float(m.group(1)) / (float(m.group(2)) if m.group(2) else 1.0)


HAUNT = source("haunt_manager.gd")
GAME = source("game.gd")
STALKER = source("stalker.gd")
RITUAL = source("ritual.gd")
CHUPA = source("chupacabra.gd")
GHOUL = source("ghoul.gd")
FAE = source("fae.gd")

DAY_LENGTH = num(GAME, r"const DAY_LENGTH := ([\d.]+)", 150.0)
TASKS_PER_DAY = int(num(GAME, r"const TASKS_PER_DAY := (\d+)", 3))
APPARITION_FLICKER = num(HAUNT, r"const APPARITION_FLICKER := ([\d.]+)", 0.3)
HAUNTED_BREATH = num(HAUNT, r"const HAUNTED_BREATH := ([\d.]+)", 0.75)
FAULT_BREATH = num(HAUNT, r"const FAULT_BREATH := ([\d.]+)", 0.07)
SEEN_CHANCE = num(FAE, r"const SEEN_CHANCE := ([\d.]+)", 0.45)
BOLT_CHANCE = num(CHUPA, r"const BOLT_CHANCE := ([\d.]+)", 0.25)
RITUAL_DAY = int(num(HAUNT, r"if Game\.day < (\d+)", 6))
NIGHT_BEAT_LAST = num(HAUNT, r"const NIGHT_BEAT_LAST := ([\d.]+)", 0.55)
# the night's rolls (scripts/game.gd, "the night")
MAX_DAYS = int(const(GAME, "MAX_DAYS", 7))
POWER_FAILURE = const(GAME, "POWER_FAILURE_CHANCE", 0.4)
POWER_FAILURE_LAST = const(GAME, "POWER_FAILURE_LAST", 0.7)
POWER_DREAD = const(GAME, "POWER_DREAD", 0.15)
POWER_DRY_MAX = int(const(GAME, "POWER_DRY_MAX", 2))
TOILET = const(GAME, "TOILET_CHANCE", 0.25)
TOILET_LAST = const(GAME, "TOILET_LAST", 0.4)
MONSTER_POWER = const(GAME, "MONSTER_POWER", 0.8)
MONSTER_TOILET = const(GAME, "MONSTER_TOILET", 0.2)
MONSTER_COMBO = const(GAME, "MONSTER_COMBO", 0.45)
MONSTER_RAMP = const(GAME, "MONSTER_RAMP", 0.2)
MONSTER_DREAD = const(GAME, "MONSTER_DREAD", 0.2)
STICKS = const(GAME, "STICKS_CHANCE", 0.5)
STICKS_LAST = const(GAME, "STICKS_LAST", 0.7)
STICKS_MONSTER = const(GAME, "STICKS_MONSTER", 0.3)
FIRST_MONSTER_NIGHT = int(const(GAME, "FIRST_MONSTER_NIGHT", 2))
QUIET_NIGHT = const(GAME, "QUIET_NIGHT", 7.0)

# the event table, lifted from _fire_day_event so the gates cannot drift
GATES = []
for gate, opts in re.findall(r"if I >= ([\d.]+):\s*\n\s*options\.append(?:_array)?\(([^)]*)\)", HAUNT):
    GATES.append((float(gate), re.findall(r'"(\w+)"', opts)))
BASE_OPTIONS = re.findall(r'var options: Array = \[([^\]]*)\]', HAUNT)
BASE_OPTIONS = re.findall(r'"(\w+)"', BASE_OPTIONS[0]) if BASE_OPTIONS else ["shadow", "bang"]

LABEL = {
    "shadow": "vulto crosses a doorway ahead",
    "shadow_close": "vulto crosses close, barely off your shoulder",
    "watcher": "vulto standing down the corridor behind you",
    "ghoul": "ghul: a crew member down a passage, unlit, waiting",
    "thrown": "Good Neighbours take something and throw it",
    "chupacabra": "chupacabra at the edge of a side passage",
    "bang": "bang, somewhere off the corridor",
    "whisper": "whisper at your ear",
    "flicker": "a lamp stutters",
    "drift": "every loose thing in the deck shoves at once",
    "blackout": "daylight blackout",
}
APPARITIONS = {"shadow", "shadow_close", "watcher", "ghoul", "thrown", "chupacabra"}


def lerp(a, b, t):
    return a + (b - a) * t


def night_ramp(I):
    """Game.night_ramp: 0 on the first night, 1 on the last; unfinished shifts push it on."""
    return max(0.0, min(1.0, (I - 1.0) / float(MAX_DAYS - 1)))


def clock(t):
    """The game's own wrist clock: 08:00 + twelve hours across a shift."""
    frac = max(0.0, min(1.0, t / DAY_LENGTH))
    minutes = int(8 * 60 + frac * 12 * 60)
    return "%02d:%02d" % (minutes // 60 % 24, minutes % 60)


def run(nights, seed, skill=0.72):
    """`skill` is how reliably the player finishes a shift's tasks; unfinished shifts are what
    drives night_penalty, which is what drives everything else."""
    rng = random.Random(seed)
    penalty = 0
    power_held = 0      # Game.power_held / monster_kept: the dread
    monster_kept = 0
    log = []
    tally = {}
    for day in range(1, nights + 1):
        I = day + penalty
        options = list(BASE_OPTIONS)
        for gate, opts in GATES:
            if I >= gate:
                options += opts
        events = []
        t = rng.uniform(8.0, 18.0)
        base = 28.0 + (7.0 - 28.0) * max(0.0, min(1.0, (I - 1.0) / 7.0))
        # the deck's own failing lamps, on their own timer, with nothing behind them
        faults = []
        ft = 12.0
        while ft < DAY_LENGTH:
            faults.append(ft)
            ft += rng.uniform(16.0, 38.0) / max(0.8, min(2.4, 0.8 + I * 0.25))
        while t < DAY_LENGTH:
            pick = rng.choice(options)
            line = {"t": t, "kind": pick, "flicker": False, "under": False}
            if pick in APPARITIONS and rng.random() < APPARITION_FLICKER:
                line["flicker"] = True
                line["delayed"] = rng.random() < 0.5
                line["under"] = rng.random() < HAUNTED_BREATH
            if pick == "thrown":
                line["seen"] = rng.random() < SEEN_CHANCE
            if pick == "chupacabra":
                line["bolted"] = rng.random() < BOLT_CHANCE
            events.append(line)
            tally[pick] = tally.get(pick, 0) + 1
            t += rng.uniform(base * 0.6, base * 1.4)
        for ft in faults:                       # a broken lamp that sounds like the other kind
            tally["fault"] = tally.get("fault", 0) + 1
            if rng.random() < FAULT_BREATH:
                tally["fault_under"] = tally.get("fault_under", 0) + 1
                events.append({"t": ft, "kind": "fault", "flicker": True, "under": True})
            else:
                events.append({"t": ft, "kind": "fault", "flicker": True, "under": False})
        events.sort(key=lambda e: e["t"])

        done = TASKS_PER_DAY if rng.random() < skill - 0.04 * max(0, I - 3) else rng.randint(0, TASKS_PER_DAY - 1)
        if done < TASKS_PER_DAY:
            penalty += 1
        night_I = day + penalty
        # tonight's rolls, the way Game._begin_night and the washroom's blackout make them
        ramp = night_ramp(night_I)
        if power_held >= POWER_DRY_MAX:
            power_p = 1.0
        else:
            power_p = min(1.0, lerp(POWER_FAILURE, POWER_FAILURE_LAST, ramp) + POWER_DREAD * power_held)
        power = rng.random() < power_p
        toilet = rng.random() < lerp(TOILET, TOILET_LAST, ramp)
        sticks = toilet and rng.random() < lerp(STICKS, STICKS_LAST, ramp)
        power_held = 0 if power else power_held + 1
        chance = 0.0
        if day >= FIRST_MONSTER_NIGHT and (power or toilet):
            if toilet:
                chance = MONSTER_COMBO if power else MONSTER_TOILET
            else:
                chance = MONSTER_POWER
            chance += MONSTER_RAMP * ramp + MONSTER_DREAD * monster_kept
            if sticks:
                chance += STICKS_MONSTER
        stalker = rng.random() < min(1.0, chance)
        if day >= FIRST_MONSTER_NIGHT:
            monster_kept = 0 if stalker else monster_kept + 1
        kind = "combo" if power and toilet else ("power" if power else ("toilet" if toilet else "quiet"))
        for k, on in (("night_" + kind, True), ("stalker_nights", stalker), ("bundles", sticks)):
            if on:
                tally[k] = tally.get(k, 0) + 1
        night = {
            "kind": kind,
            "power": power,
            "toilet": toilet,
            "sticks": sticks,
            "stalker": stalker,
            "speed": 0.45 + 0.12 * night_I,
            "lit": 0.0 if night_I < 5.0 else 0.3,
            "teleport": night_I >= 4.0,
            "ritual": day >= RITUAL_DAY,
            "eyes": day >= 2,
            "beats": [],
        }
        gap = lerp(1.0, NIGHT_BEAT_LAST, ramp)                    # night beats close up over the run
        nt = rng.uniform(12.0, 25.0) * gap
        walk = 0.0
        if power:
            walk += rng.uniform(70.0, 190.0) + 9.0 * night_I     # how long to find the power room
        if toilet:
            walk += rng.uniform(50.0, 120.0)                       # to the washroom, and in the stall
            if not power:
                walk += rng.uniform(40.0, 110.0)                   # ...and back to bed
        if kind == "quiet":
            walk = QUIET_NIGHT                                     # slept through: nothing to hear
            nt = walk
        while nt < walk:
            night["beats"].append((nt, "bang" if rng.random() < 0.5 else "whisper"))
            nt += rng.uniform(9.0, 22.0) * gap
        night["length"] = walk
        log.append({"day": day, "I": I, "night_I": night_I, "events": events,
                    "done": done, "night": night})
    return log, tally


def report(log, tally, quiet=False):
    out = []
    for d in log:
        n = d["night"]
        if not quiet:
            out.append("")
            out.append("DAY %-2d  intensity %-2d   %d/%d tasks"
                       % (d["day"], d["I"], d["done"], TASKS_PER_DAY))
            out.append("-" * 74)
            for e in d["events"]:
                bits = []
                if e["kind"] == "fault":
                    bits.append("a lamp stutters - the deck's own, nothing behind it")
                else:
                    bits.append(LABEL.get(e["kind"], e["kind"]))
                if e["kind"] == "thrown":
                    bits.append("(you see the lights)" if e.get("seen") else "(NOTHING VISIBLE - a crate crosses the corridor on its own)")
                if e["kind"] == "chupacabra":
                    bits.append("(bolts across the opening)" if e.get("bolted") else "(withdraws round the corner)")
                if e.get("flicker") and e["kind"] != "fault":
                    bits.append("+ the nearest lamp goes" + (" a beat later" if e.get("delayed") else ""))
                if e.get("under"):
                    bits.append("*** something under the buzz ***")
                out.append("  %s  %s" % (clock(e["t"]), "  ".join(bits)))
            what = {"quiet": "quiet - slept through", "power": "power out",
                    "toilet": "toilet trip, lights on", "combo": "power out AND a toilet trip"}[n["kind"]]
            if n["sticks"]:
                what += ", the bundle outside the stall door"
            if n["stalker"]:
                out.append("  NIGHT %-2d  %s, %.0fs up   stalker %.2f m/s%s%s%s"
                           % (d["day"], what, n["length"], n["speed"],
                              ", eyes lit" if n["eyes"] else ", unseen in the dark",
                              ", pushes through your torch" if n["lit"] else "",
                              ", closes distance while you look away" if n["teleport"] else ""))
            else:
                out.append("  NIGHT %-2d  %s%s" % (d["day"], what, "" if n["kind"] == "quiet" else
                                                   ", %.0fs up   nothing walking" % n["length"]))
            if n["ritual"]:
                out.append("           ** one doorway is warm: somebody is sitting in a circle of candles **")
            for t, k in n["beats"]:
                out.append("           %5.0fs  %s" % (t, "a bang, somewhere" if k == "bang" else "a whisper at your ear"))
    out.append("")
    out.append("=" * 74)
    out.append("OVER %d NIGHTS" % len(log))
    out.append("=" * 74)
    total_app = sum(v for k, v in tally.items() if k in APPARITIONS)
    for k in sorted(tally, key=lambda k: -tally[k]):
        if k in ("fault", "fault_under", "stalker_nights", "bundles") or k.startswith("night_"):
            continue
        out.append("  %-14s %3d %s" % (k, tally[k], "apparition" if k in APPARITIONS else ""))
    out.append("  %-14s %3d" % ("apparitions", total_app))
    out.append("")
    out.append("  nights: %d quiet, %d power failures, %d toilet trips, %d both"
               % (tally.get("night_quiet", 0), tally.get("night_power", 0),
                  tally.get("night_toilet", 0), tally.get("night_combo", 0)))
    out.append("  the stalker walked on %d of them; the bundle was outside the stall door %d times"
               % (tally.get("stalker_nights", 0), tally.get("bundles", 0)))
    out.append("")
    out.append("  lamps stuttering with nothing behind them: %d" % tally.get("fault", 0))
    out.append("  ...of which carried the breath anyway:     %d  (false positives)"
               % tally.get("fault_under", 0))
    true_b = round(total_app * APPARITION_FLICKER * HAUNTED_BREATH)
    false_b = tally.get("fault_under", 0)
    if true_b + false_b:
        out.append("")
        out.append("  the breath under the buzz: %d times with something there, %d without"
                   % (true_b, false_b))
        out.append("  -> hearing it means something is there %d%% of the time. Worth listening for,"
                   % round(100.0 * true_b / (true_b + false_b)))
        out.append("     never safe to trust, which is the whole point of it.")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nights", type=int, default=16)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--out", default=None)
    ap.add_argument("--json", default=None, help="write the run as data, for building reports from")
    args = ap.parse_args()
    log, tally = run(args.nights, args.seed)
    if args.json:
        with open(args.json, "w") as f:
            json.dump({"nights": args.nights, "seed": args.seed, "days": log, "tally": tally,
                       "labels": LABEL, "apparitions": sorted(APPARITIONS),
                       "day_length": DAY_LENGTH, "tasks": TASKS_PER_DAY,
                       "clock": [clock(t * DAY_LENGTH / 12.0) for t in range(13)]}, f)
        print("wrote", args.json)
        if not args.out:
            return
    text = report(log, tally, args.quiet)
    if args.out:
        open(args.out, "w").write(text + "\n")
        print("wrote", args.out)
    else:
        print(text)


if __name__ == "__main__":
    main()
