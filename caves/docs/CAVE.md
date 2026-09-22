# Sowbelly Cave

![The Sowbelly survey](survey.png)

*Plan and extended elevation. Both are drawn by `tools/render_survey.py` straight from
`cave/sowbelly.json` - the same file the game loads - so the picture cannot disagree with the
cave. 5 passages, 114 m surveyed, 61.2 m below the entrance.*

## What it is

Sowbelly is invented. The geology is not: it is a limestone system of the kind that forms in
bedded, jointed rock where water has had a long time and several ways down. The passage types
are the real ones cavers name - a pitch, a breakdown chamber, a phreatic tube, a bedding
plane, a rift, a lead - and the dimensions are the real ones too, down to a squeeze that is
narrower than a relaxed human chest.

It is not a model of any real cave, and the head-down lead at the bottom does not restage
anything that happened in one. Where caving has famous passage names attached to a particular
place, they are not used here.

## The passages

Every number below is printed by `python3 caves/tools/check_fit.py`, which measures the cave
rather than repeating what was written about it.

| Passage | Length | Crux | Posture there | Spare | With a full chest |
|---|---|---|---|---|---|
| The Pitch | 48.0 m | 2.34 m high | standing | 59.1 cm | goes |
| The Gullet | 16.3 m | 0.75 m high | hands and knees | 0.3 cm | goes |
| The Flatiron | 36.3 m | 0.76 m high | hands and knees | 1.5 cm | goes |
| The Devil's Pinch | 9.1 m | **0.285 m wide** | committed, sideways | 0.7 cm | **shut at 4.6 m** |
| The Drainpipe | 4.7 m | 0.33 m high | head first, arm ahead | 4.8 cm | shut at 2.9 m |

### 1. The Pitch

A 48 m shaft, 2.4 m across at the head and belling out to 8 m where it breaks through the roof
of the Rubble Hall. One rope, rigged from two bolts and a loop of tape at the top, hanging free
the whole way. There is daylight for the first twenty metres or so and then there is not, and
watching it go is the point of it.

The rope is the only thing in the cave that is not rock, and it reads that way: gold against
grey, and the only colour in the beam. Clip on with **R**, hold the brake to slow down, push
forward to climb. Let the brake off entirely and you go down at 4.2 m/s, which is fast enough
to be a decision.

### 2. The Rubble Hall

32 × 20 m, 12 m to the roof, with a floor of collapsed blocks and eighteen stalactites hanging
out of a ceiling your headlamp cannot reach. This is the only place in Sowbelly where you can
stand up and walk, and it exists to establish the scale that everything afterwards takes away.

### 3. The Gullet

A phreatic tube - dissolved when this part of the system was full of water, which is why it is
round and why it bends the way it does. 2.1 m at the mouth, closing to 1.1 m over sixteen
metres as it descends. A mud floor, the first in the cave.

It is the passage that puts you on your hands and knees without asking, and it does it
gradually: the ceiling comes down over ten metres rather than at a step, so you are already
crawling by the time you notice you stopped walking.

### 4. The Flatiron

Thirty-six metres of bedding plane: the parting between two beds of limestone, opened by water
running along it. Wide - up to 3.4 m - and at its worst 41 cm from floor to ceiling, which
after the mud keel is 38 cm of clear space.

Flat out, one arm ahead, helmet scraping. Contact pressure sits at about 0.74 the whole way,
which is high enough that the scrape loop never stops and low enough that you keep moving.
This is the passage that teaches you what the game's one number feels like, well before it
matters.

### 5. The Devil's Pinch

A joint pulled open: two near-parallel faces of rock, nearly two metres tall and, at the worst
of it, **28.5 cm apart**. Wet, because water is still using it.

You go through it upright and turned sideways, and you do not go through it at all with a full
chest. A relaxed chest plus the 5 mm of oversuit is 30.5 cm, and 4.6 m in - halfway - the
passage stops being wide enough for that. Emptied it is 27.0 cm, which leaves 1.5 cm of rock
either side of you.

Push into it with a full chest and you get held: pressure goes to 1.00, forward does nothing,
and the slate tells you what to do about it. Empty your chest and the rock lets go. That is the
whole cave in one sentence, and everything else in Sowbelly exists to get you to it prepared.

### 6. The Drainpipe

A lead, not a route. It leaves the bottom of the Pinch heading down, 1.2 m at the mouth and
narrowing all the way, and 2.9 m in - 63 % of its length - it stops admitting anything human,
in any posture, with any amount of air in your chest. It carries on getting smaller for another
two metres and then it is rock.

The point of it is the committing. You can get far enough in to be sure, head down, before you
find out - and then you have to reverse out of it, because there is nowhere to turn round.
`check_fit.py` enforces both halves: a passage marked `dead_end` must close, *and* must not
close in the first 45 % of its length, because a dead end you cannot enter is just a wall and
teaches nothing.

## Authoring another one

`cave/sowbelly.json` is data, read by the game (`scripts/cave.gd`) and by both Python tools.
A passage is a centreline and a few cross-section keyframes:

```jsonc
{
  "id": "flatiron",
  "label": "The Flatiron",
  "kind": "crawl",              // shaft | crawl | rift | lead - drives the survey's colours
  "seed": 5512,                 // the noise that roughens the walls
  "rough": 0.05,                // metres of outward displacement; walls only ever move OUT
  "wall": "rock", "floor": "mud",
  "open_start": true,           // this end is a mouth into a chamber, not a rock face
  "open_end": true,
  "path": [[26.5, -57.1, 8.8], [28, -57.3, 15], ...],   // control points, metres, Y up
  "profile": [
    {"t": 0.00, "w": 1.22, "h": 1.00, "shape": "keyhole",   "keel": 0.10},
    {"t": 0.42, "w": 3.40, "h": 0.46, "shape": "letterbox", "keel": 0.04},
    {"t": 1.00, "w": 1.60, "h": 1.50, "shape": "rift"}
  ]
}
```

The control points go through a centripetal Catmull-Rom spline and come out as a station every
35 cm. Each station gets a section interpolated between the keyframes either side of it, and
`Geo.sweep` carries a **levelled** frame down the line - levelled against world up wherever
the passage is not vertical, so "height" in a profile means height and a crawl's floor stays
underneath you through every bend. Through a near-vertical stretch there is no such thing as
levelling, so the previous frame is carried forward by parallel transport and the passage does
not spin around its own axis on the way down.

### Cross-sections

`shape` picks a superellipse exponent, except `keyhole`, which is built specially.

| `shape` | What it is | Reads as |
|---|---|---|
| `tube` | phreatic - dissolved full of water | round |
| `rift` | a joint pulled open | tall, near-parallel walls |
| `letterbox` | a bedding plane | wide, flat, square-ish corners |
| `keyhole` | a tube that later cut down into a slot | round over a narrow bottom |
| `breakdown` | collapse | angular, pointed |

`w` and `h` are the clear width and height. Nothing in the pipeline ever narrows them:
displacement only pushes rock *away* from the centreline, which is what lets the numbers in
this file be a promise rather than an aspiration. `keel` flattens the bottom into a sediment
floor by adding a flat below the section rather than cutting into it.

Where two keyframes name different shapes, both polygons are built at the blended size and the
points are lerped - every shape passes through (±w/2, 0) and (0, ±h/2), so the width and height
survive the blend intact.

### Chambers

A chamber is a displaced sphere seen from the inside. `mouths` lists where passages arrive, and
faces within that radius are dropped - otherwise there would be a membrane of rock stretched
across every opening.

### Then check it

```
python3 caves/tools/check_fit.py
python3 caves/tools/render_survey.py
```

`check_fit.py` reads the posture table out of `scripts/body.gd` with a regex rather than
keeping its own copy, reconstructs every section, and scans each one for the tallest gap a
body of each width can find. It fails if a through-passage is impassable in every posture, if
a passage marked `needs_exhale` turns out to admit a relaxed chest, or if a `dead_end` goes
right through. It needs nothing but the standard library and it runs before Godot is even
downloaded in CI, because a cave that cannot be caved should not get as far as being exported.

## The files

| | |
|---|---|
| `cave/sowbelly.json` | the cave. **Edit this.** |
| `scripts/bore.gd` | one passage: spline, sections, sweep, and the clearance queries |
| `scripts/geo.gd` | cross-sections, levelled frames, the sweep, chambers, colliders |
| `scripts/cave.gd` | reads the JSON, chunks the result at 20 m, rigs the rope and the drips |
| `tools/check_fit.py` | proves it is passable |
| `tools/render_survey.py` | draws `docs/survey.png` |
