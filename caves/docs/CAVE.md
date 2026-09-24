# Sowbelly Cave

![The Sowbelly survey](survey.png)

*Plan and extended elevation. Both are drawn by `tools/render_survey.py` straight from
`cave/sowbelly.json` - the same file the game loads - so the picture cannot disagree with the
cave. 7 passages, 87 m surveyed, 27.6 m below the entrance.*

## What it is

Sowbelly is invented. The geology is not: it is a limestone system of the kind that forms in
bedded, jointed rock where water has had a long time and several ways down. The passage types
are the real ones cavers name - a pitch, a phreatic tube, a rift, a lead - and the dimensions
are the real ones too, down to a squeeze that is narrower than a relaxed human
chest.

It is a **tight** cave, and that is the design. There are two places in it where a person can
stand up, neither of them larger than a garage, and 60 of its 87 metres are passage you cross
on your hands, your knees or your chest.

It is not a model of any real cave, and the head-down lead at the bottom does not restage
anything that happened in one. Where caving has famous passage names attached to a particular
place, they are not used here.

## The passages

Every number below is printed by `python3 caves/tools/check_fit.py`, which measures the cave
rather than repeating what was written about it.

| Passage | Length | Crux | Posture there | Spare | With a full chest |
|---|---|---|---|---|---|
| The Pitch | 16.8 m | 1.86 m high | standing | 10.8 cm | goes |
| The Cellar | 9.5 m | 2.40 m high | standing | 65.0 cm | goes |
| The Gullet | 15.9 m | 0.41 m high | flat out | 10.7 cm | goes |
| The Bone Box | 6.5 m | 2.12 m high | standing | 37.0 cm | goes |
| The Flatiron | 24.8 m | 0.40 m high | flat out | 9.3 cm | goes |
| The Devil's Pinch | 9.3 m | 0.31 m high | flat out | 0.0 cm | **shut at 4.4 m** |
| The Drainpipe | 5.0 m | 0.32 m high | flat out | 1.1 cm | shut at 2.0 m |

**Crux** here means the station with the least room to spare in the best posture available
*there* - not the narrowest section. The Pinch's row is where flat out stops fitting even
empty, half a metre before the worst of it; past that point you are head first, and the
narrowest roof is 29.3 cm (see [the Pinch](#6-the-devils-pinch)).

Every posture in the tunnel rows is `flat out`. That is the rule and not a coincidence - see
below.

It also gates three rules that are easy to state, easy to lose, and were all lost at least once:

```
  tunnel The Gullet           tallest 1.09 m, narrowest 0.48 m at 13.2 m in, 3 pinches   ok
  tunnel The Flatiron         tallest 0.76 m, narrowest 0.46 m at 21.5 m in, 3 pinches   ok
  tunnel The Devil's Pinch    tallest 0.55 m, narrowest 0.30 m at  4.8 m in, 1 pinch   ok
  tunnel The Drainpipe        tallest 0.50 m, narrowest 0.20 m at  5.0 m in, 0 pinches   ok
```

**Nothing you can stand up in**, and the number that is checked is the DRAWN height of the
section - 1.35 m is the ceiling - rather than the clearance a pair of shoulders can find in it.
That distinction is the whole reason this gate was rewritten. The old one asked whether the game
would pick `stand`, and the Devil's Pinch passed it comfortably while standing 1.72 m tall,
because at shoulder width a 28 cm slot has no gap at all. The rule was satisfied and a
playtester still reported a tunnel they could stand up in - because they could see one. What you
can see is the rule.

**Pinches**, at least two per through-crawl: places where the bore closes to under two thirds of
the passage either side of it and opens again. A tunnel that is merely small the whole way along
is a pipe; what makes it a cave is having to work through something.

**It keeps closing.** Each tunnel's narrowest gap is narrower than the one before it on the
route - 48 cm, then 46, then 30, then 20. Measured on the tightest single dimension rather than
on area, because a flattened bore trades height for width: the Pinch's crux is a metre across
and 30 cm high, so by area it reads as roomier than it is while being the hardest thing in the
cave.

`check_fit.py` also prints the joins, because a cave whose passages are each passable can still
be impassable where two of them meet. `end inside` means the first passage's last station falls
inside the second's open space, which is what a join is here - an overlap, not a butt weld -
and `drop` marks the one join you are not expected to walk across, which is what the rope is
for:

```
  join      pitch -> cellar     ends  2.49 m apart (end inside), floors 1.06 m apart  drop
  join     cellar -> gullet     ends  1.24 m apart (start inside), floors 0.06 m apart  ok
  join     gullet -> bonebox    ends  1.77 m apart (end inside), floors 0.07 m apart  ok
  join    bonebox -> flatiron   ends  0.87 m apart (start inside), floors 0.00 m apart  ok
  join   flatiron -> pinch      ends  0.00 m apart (end inside), floors 0.00 m apart  ok
  join      pinch -> drainpipe  ends  0.25 m apart (end inside), floors 0.03 m apart  ok
```

### 1. The Pitch

A 17 m shaft, 2.3 m across at the head and narrowing the whole way to 1.7 m where it drops
through the roof of the Cellar. Nothing in this cave opens back up once it has closed, and the
first thing you are in sets that expectation. One rope, rigged from two bolts and a loop of tape at the top, hanging free the
whole way. There is daylight at the head of it and none at the bottom, and watching it go is
the point of it.

**You start on the rope**, three metres down, already clipped on. There is no surface, no
approach and no walk-in: the first frame of the game is rock within arm's reach on every side
and a hole underneath you. The spawn point is not written down anywhere - `cave.gd` derives it
from the rigged rope itself, because a hand-typed coordinate was wrong twice, once by putting
the player 1.6 m outside a 1.2 m shaft with no floor within forty metres.

The rope is the only thing in the cave that is not rock, and it reads that way: gold against
grey, and the only colour in the beam. Clip on or off with **R**, hold the brake to slow down,
push forward to climb. Let the brake off entirely and you go down at 4.2 m/s, which is fast
enough to be a decision.

### 2. The Cellar

9 × 5 m and 3 m to the roof, sixteen formations hanging off it and fourteen blocks of roof on
the floor under them. The rope lands you here. It is one of two places in Sowbelly where you can
stand up, and it exists to give you a scale that everything afterwards takes away - you get
about eight metres of walking, and then the Gullet.

### 3. The Gullet

A phreatic tube - dissolved when this part of the system was full of water, which is why it is
round and why it bends the way it does. 1.30 × 1.15 m at the mouth, closing to 0.88 × 0.66 m
over sixteen metres, with three pinches on the way where it shuts to about half that and opens
again.

It puts you on your belly in the first three metres and keeps you there. Eighteen degrees of drop straight out of the Cellar, easing to nine, then it climbs back over a
rib before dropping twenty into the Bone Box - so you are never on the flat for long, and you
have gained and lost height with your face fifty centimetres from the rock.

The gradients are as steep as they are, and the BREAKS between them are gentler than they were,
because the break is what a long collider cannot ride. A capsule pitched to the floor it is on
has its nose out over the floor ahead; at a twenty-nine degree change of slope that nose ends up
inside the rock, and the body moves forward at a third of a metre a second while being shoved
back exactly as far. Sixteen degrees of change is what it can take, and the cave is authored to
it. That is a limit of the collider rather than of the cave, and it is written down here so the
next person to flatten a rib knows which of the two they are fighting.

The verticality is not decoration. It is the reason the collision capsule now lies along the
floor rather than along the horizon, and the reason a prone body is allowed a steeper floor
angle than an upright one: both of those were bugs this passage exposed the day it stopped being
a ramp. See [MOVEMENT.md](MOVEMENT.md).

### 4. The Bone Box

7 × 4.5 m, roof at 2.8, eleven formations and ten blocks. The last place in the cave you stand
up, and you can see the Flatiron from it: a hole in the far wall about knee high and no wider
than your shoulders. It is a small room and it is meant to feel like one after the Cellar,
because the cave is closing down the whole way.

### 5. The Flatiron

Twenty-five metres of the same bore, squashed. It keeps the Gullet's shape and loses its height:
1.02 × 0.80 m at the mouth and 0.80 × 0.49 m at its worst, with three pinches of its own.

Those worst heights came up three to five centimetres from where they were first drawn, and the
reason is pace rather than fit. Five centimetres lower and the body picks `superman` - head
first, one arm pushed ahead - which moves at ten centimetres a second. Twenty-five metres of that
is four minutes in which nothing the player does makes any difference. Flat out is 34 cm a
second and still slow enough to be work. The pinches kept their bite; the passage stopped being
a corridor you wait in.

It used to be a bedding plane - 3.2 m wide and 41 cm high, the parting between two beds of
limestone. That is a real passage type and it was the wrong one for this cave: a slab that wide
reads as a low room, not as something you are committed inside. The height it had was right, so
the height is what stayed.

The change is not free. A bedding plane passes a body on its belly *because* it is wide - your
shoulders are somewhere the roof has not come down yet. In a bore the roof curves down before
your shoulders clear it, so the same 41 cm would be impassable and the tightest heights here had
to come up a little as the widths collapsed. Flat out, one arm ahead, helmet scraping, and the
scrape loop never stops.

It is not flat either. It drops fifteen degrees out of the Bone Box, runs level, climbs fourteen
back up, and drops seventeen into the Pinch - which over twenty-five metres of belly crawl is
most of what stops it being a corridor.

### 6. The Devil's Pinch

The same tube as the Flatiron, carried straight on and pressed nearly flat: a metre wide and
33 cm high at the worst of it, which is **29.3 cm** of roof across the 32 cm a body lying head
first takes up.

It used to be a rift - a joint pulled open into a slot 1.30 m tall and 28.8 cm wide, passed
turned sideways. It was the one passage in the cave that was not round, and it read as a
different cave: a tall corridor at the bottom of a crawl, with a slab of junction rock across the
way in. Both went. The passage is a bore like every other tunnel, and it carries straight on from
the Flatiron as one tube (see [joining two passages](#joining-two-passages-and-the-bug-that-made-it-the-only-rule)).

You go through it head first, one arm ahead, and you do not go through it at all with a full
chest. Head first, the chest is your height: 30 cm relaxed plus 2 cm of helmet and oversuit is
32.0 cm, and 4.4 m in the passage stops being tall enough for that. Emptied, it is 28.5 cm,
which leaves 8 mm. The stretch where only an empty chest goes is about half a metre, so it is
two or three breaths rather than a minute of holding one.

Push into it with a full chest and you get held: pressure goes to 1.00, forward does nothing,
and **the screen tells you what to do about it**. That last part is new and it is the whole
reason this passage was being reported as a bug - the advice was on the survey slate, which is
an object on your wrist you have to decide to look at. Empty your chest and the rock lets go.
That is the whole cave in one sentence, and everything else in Sowbelly exists to get you to it
prepared.

### 7. The Drainpipe

A lead, not a route. It leaves the bottom of the Pinch heading down at nearly thirty degrees,
60 cm at the mouth - it carries on from where the Pinch left off, as one tube -
and narrowing all the way, and 2.7 m in, 54 % of its length, it stops admitting anything human
in any posture with any amount of air in your chest. It carries on getting smaller for another
two metres and then it is rock.

The point of it is the committing. You can get far enough in to be sure, head down, before you
find out - and then you have to reverse out of it, because there is nowhere to turn round.
`check_fit.py` enforces both halves: a passage marked `dead_end` must close, *and* must not
close in the first 45 % of its length, because a dead end you cannot enter is just a wall and
teaches nothing.

**And the cave now says so on the way in.** A passage that quietly stops being big enough for a
person is indistinguishable from a broken game, and that is exactly how it was reported: "hit an
impassable dead end in a tunnel". Entering a `dead_end` passage for the first time puts *a lead
- it closes, and you reverse out* on the screen under its name. Everything the cave asks of you
it has to tell you it is asking.

## Authoring another one

`cave/sowbelly.json` is data, read by the game (`scripts/cave.gd`) and by both Python tools.

**There is exactly one kind of object in a cave: a passage.** A room is a short passage with a
big cross-section, a shaft is a vertical one, a lead is one that pinches out. That is not
laziness, it is the fix for the worst bug this project has had, and the reason is at the bottom
of this page.

A passage is a centreline and a few cross-section keyframes:

```jsonc
{
  "id": "flatiron",
  "label": "The Flatiron",
  "kind": "crawl",              // shaft | room | crawl | squeeze | lead - the survey's colours,
                                //   and `room` is the one that gets formations
  "seed": 5512,                 // the noise that roughens the walls
  "rough": 0.05,                // metres of outward displacement; walls only ever move OUT
  "wall": "rock", "floor": "mud",
  "path": [[24.5, -20.6, 8.2], [27, -21.0, 14], ...],   // control points, metres, Y up
  "profile": [
    {"t": 0.00, "w": 1.30, "h": 1.10, "shape": "keyhole",   "keel": 0.10},
    {"t": 0.45, "w": 3.20, "h": 0.44, "shape": "letterbox", "keel": 0.04},
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

| `shape` | What it is | Reads as | Used by |
|---|---|---|---|
| `tube` | phreatic - dissolved full of water | round | every tunnel in the cave |
| `rift` | a joint pulled open | tall, near-parallel walls | nothing, currently |
| `letterbox` | a bedding plane | wide, flat, square-ish corners | the two rooms |
| `keyhole` | a tube that later cut down into a slot | round over a narrow bottom | nothing, currently |
| `breakdown` | collapse | angular, pointed | nothing, currently |

**Tunnels are `tube`.** A wide flat section reads as a low room rather than as a passage you
are inside, so `letterbox` is for rooms and the tunnels between them are bores - including the
Pinch, which used to be the one `rift` and read as a corridor from another cave because of it.
A squeeze in this cave is a bore pressed flat, never a slot.

`rift`'s exponent is 8, not the 4-ish a "rounded rectangle" suggests: a slot is passed by a body
turned sideways, which needs its gap *at its own width* rather than at the centreline, and a
rounder rift throws that gap away until the slot has to be made taller than a person to
compensate. That is how the Pinch ended up as a standing-height corridor before it was a tube.

`w` and `h` are the clear width and height. Nothing in the pipeline ever narrows them:
displacement only pushes rock *away* from the centreline, which is what lets the numbers in
this file be a promise rather than an aspiration. `keel` flattens the bottom into a sediment
floor by adding a flat below the section rather than cutting into it.

Beware of reading `h` as headroom. The section is a 22-gon and a body is not a point: what has
to fit is a gap of the body's height across the body's *width*, and towards the edge of any
section the roof has already started coming down. At the crux that costs about a quarter of the
nominal height. `check_fit.py` measures the polygon rather than the ideal curve, which is why
it is the thing to tune against and arithmetic on `w` and `h` is not.

**`rough` is a wall number.** Because displacement is radial and outward-only, on a floor it
digs rather than piles, and a vertex facing straight down keeps only 9 % of it
(`Geo.FLOOR_EASE`). That is both what a cave looks like - water leaves walls rough and fills
floors flat, with silt and sand and cobbles settling - and what makes a passage crawlable. At
full strength, 45 cm of roughness on the Cellar's floor cut ditches in it with fifty-degree
sides, and the route walker stopped dead 93 % of the way across with no rock anywhere near its
chest.

It came down from 18 % to 9 % when the crawls got rugged. A crawling body has no step-up: it
climbs what `floor_max_angle` lets it slide up and snags on anything steeper, and 11 cm of
displacement keeping a fifth of itself makes faces well past that. The ruggedness you see is on
the walls and the roof - where it can be as steep as it likes - and in the texture. Not
underneath you.
Sowbelly has one rock everywhere now - wet limestone, walls, roof and floor alike - so `keel`
is doing the work a mud texture used to: it is what tells you which way is down.

Where two keyframes name different shapes, both polygons are built at the blended size and the
points are lerped - every shape passes through (±w/2, 0) and (0, ±h/2), so the width and height
survive the blend intact.

### Joining two passages, and the bug that made it the only rule

Passages join by **overlapping**: you author the next one so its first control points sit
inside the previous one's open space. There is nothing to declare and nothing to line up.

**Except tube to tube, which carries straight on.** Overlap is right where a crawl meets a room:
the crawl's end sits well inside something much bigger, and all of it is cut away. Two tubes the
same size cannot overlap that way - neither is inside the other - and butting them end to end
left each end face lying half across the other's mouth, which the rules below keep as a seam: a
slab of stretched, double-sided rock across the passage, which is what stood between the
Flatiron and the Pinch. So a passage whose first control point is **exactly** the last control
point of another (within a centimetre) continues it instead (`Bore.continues_from`): it is
swept from the other one's last ring, vertex for vertex, neither end is capped, and the two are
not trimmed against each other. Give the two the same section at the join - same shape, size and
keel - or the first 35 cm of the second will do the blending. The Flatiron, the Pinch and the
Drainpipe are one tube with two name changes along it.

**Both ends of every passage are capped.** There used to be an `open_end` flag that left an end
uncapped where a tunnel arrived, and there is no correct way to write that down: the Cellar is
six metres across and the tunnel leaving it is two, so leaving its end open left thirteen square
metres of room wall open to the void. Every passage in the cave leaked that way, and
`CAVE_AUTOTEST=clear` found all seven at once. So the cap is always built and the junction cuts
the mouth out of it - which is then a hole the exact shape of the passage that arrives, rather
than a hole somebody typed in. An end face is ten concentric rings rather than a fan of long
triangles, because a hole can only be as accurate as the faces are small.

**The junction is one question, asked of every face.** When `cave.gd` builds a passage it asks
each of the others, of each face - tube and end face alike - what should happen to it. The
question is only whether the face's four corners agree, and `Bore.swallows_face` answers CUT,
KEEP or SEAM. The test underneath is exact: a corner is transformed into the other passage's
frame at the nearest station and tested against the real section polygon, not a bounding sphere;
a rift is 30 cm one way and two metres the other, and a circle of its longest radius would
swallow half the cave. A station grid keeps it affordable.

- **CUT** - every corner is inside the other passage. The face is not a wall, it is a pipe
  hanging through the middle of somewhere you walk.
- **KEEP** - no corner is inside. It is rock.
- **SEAM** - the corners disagree, so the face lies across the edge of a mouth. `Geo` quarters
  it and asks again, three levels deep, which takes a face that is 35 cm by most of a metre
  down to a few centimetres - and only at a junction, so the rest of the cave carries none of
  the cost. See below for what survives that.

The two kinds of face differ only in margin, because the cost of cutting too much differs. A
tube face has to be *well* inside its neighbour before it goes (`Bore.TUBE_MARGIN`, 1.12):
over-cut a tube wall and there is a hole in the cave. An end face goes wherever the neighbour
is, exactly (`CAP_MARGIN`, 1.00): under-cut one and there is rock across the mouth.

A passage is also **bounded by its own two end faces**, and the containment test says so
explicitly. A station will claim any point within half a station-step along its own tangent,
which for the last station means half a metre past the end of the passage - so without that
bound, a neighbour's wall is trimmed away in a slab the passage does not enclose and nothing
else covers. The Gullet lost its walls for the first half metre past the Cellar's end face
exactly that way, which is a hole you can see through and fall out of.

**A join's floors have to meet within 10 cm** (`check_fit.MAX_STEP`), and that number used to be
40. Forty centimetres is the height of a breakdown block you step onto, and a `CharacterBody3D`
cannot step onto anything: `floor_snap_length` only ever snaps DOWN. What a body can climb is
whatever is shallower than `floor_max_angle`, and the lip at a junction - the double-sided seam
face below - is exactly as steep as the mismatch makes it. Twelve centimetres at the Gullet's
mouth came out at 59 degrees, one degree over the limit, and stopped a standing body dead in a
room 2.4 metres tall with nothing else near it. Tightening the gate immediately found a second
one, a 20 cm step into the Flatiron, which would have been the next thing a player hit.

### Seams

Quartering three times gets a mouth's edge down to a few centimetres, but it cannot get it to
nothing: there is always a last ring of patches the edge runs through. Those cannot be cut - the
part outside the neighbour would have nothing on either side of it, which is the hole above -
and they cannot simply be kept either, because a kept face belongs to the *other* passage and
therefore faces into it. Standing in the room, you would be looking at its back: single-sided,
so invisible; `backface_collision`, so solid. That is the exact bug this whole round is about,
reintroduced a few centimetres at a time at every junction in the cave.

So they are kept and routed to their own material, which is the same limestone with
`cull_mode = CULL_DISABLED`. Drawn from both sides, a seam is a lip of rock at the mouth, which
is what it is - you can see it, you can climb over it, and caves have them. Sowbelly carries
about 2,100 seam triangles out of 19,600, all at the room junctions, on their own `StaticBody3D` so the tests can name them
when one of them is in the way. Everything else in the cave stays single-sided, which is both
correct and cheaper.

### Rubble and formations

A dissolved tube is a smooth shell and nothing with a few thousand years of roof falling into it
stays one. So rooms carry `rubble` and `speleothems`, both built in `cave.gd` riding the
passage's own frames so they land where the section actually is however it bends.

**The tunnels carry none.** Even laid flat, a block in a crawl is something to catch on in a
passage you are already filling, and players read them as obstacles put there to stop them -
which is not what anything in this cave is for. `rubble` still works on any passage; nothing
between the rooms asks for it.

Blocks are `Geo.chunk`: six faces with all eight corners pushed about, so no two edges are
parallel. `Geo.box` was the obvious thing to reach for and it reads as a crate the moment there
is more than one of them on a floor.

**In anything you crawl through, a block is always a slab.** Rubble goes on the `decor` body,
which `CAVE_AUTOTEST=clear` skips - it has to, or every stalactite fails the clearance test as
rock in the passage - so nothing in the geometry check can see a boulder in a crawl. The
placement rule is the only guard, and it took three goes.

The first two were both "keep it further from the centreline": a block is pushed out until its
inner face (its nominal half-width plus the third of it that `chunk` may jitter outward) clears
the line by 45 cm. That is right for a room and useless for a tunnel, because **a crawling body
does not travel down the centreline.** It wanders a good half metre either side of it, which in
a ninety-centimetre passage is most of the passage, and there is no further out to go. So below
1.6 m of clear height - anything you are not walking in - `tall` is capped at 5 cm and the block
is laid flat across the floor wherever it likes. Rubble you crawl over is rubble; rubble you
cannot get past is a wall, and a wall in a tunnel is the bug this cave keeps being told about.

All three were caught by the route walker and none of them by anything else.

One formation in six is a column - the stalactite met the stalagmite growing under it and the
two joined, which takes long enough that a cave with a few of them reads as an old one.

### And the thing all of this replaced

Rooms used to be a second kind of object - a displaced sphere seen from the inside, with a
`mouths` list naming where passages arrived so
the sphere's faces could be cut away around them. The cutting went one way only: the chamber's
shell was opened around a passage, but nothing ever removed the **passage's** shell from inside
the chamber. So the Pitch came down through the Cellar's roof and left four metres of tube
hanging in the middle of the room, and the Gullet ran four metres in from the other side and
left another. Both were invisible, because a swept tube's faces are single-sided and you were
looking at their backs. Both were solid, because the trimesh collider is built with
`backface_collision = true`. You came off the rope into a wall that was not there.

Two kinds of shell composited by cutting holes in each and hoping they line up is the bug. One
kind of object means one junction rule, and the rule can be exact.

`CAVE_AUTOTEST=clear` is the test that keeps all of this honest, and it asks both halves of the
question from every station of every passage. *Rock where there should be none:* a ray along
each of the 22 section directions, and since displacement only ever pushes rock outward,
anything that comes back early is in the lumen. *None where there should be rock:* 32 rays over
a sphere, and since a cave is a closed shell, any that reaches eighty metres has left the
world. It covers the whole cave rather than one line through it, and it fails the build.

**It is made of rays, and there is a thing rays cannot see.** A ray is a line; what stops a
player is a capsule 43 cm across, and a capsule catches rock a line misses. The route walker
stalled 3.6 m into the Gullet with four forward probes all reporting two clear metres, because
the body's head was against the lintel over the mouth - a face pointing down and backwards,
horizontally clear, impossible to slide along without descending into the floor. Nothing about
the geometry was wrong; the body had chosen a posture with a centimetre to spare and walked it
under an overhang. So when the route walker gives up it now asks the *collider* what it is
touching rather than asking the passage what is there - see
[MOVEMENT.md](MOVEMENT.md#when-it-stops-and-you-cannot-see-why). Reach for that first.

### Then check it

```
python3 caves/tools/check_fit.py
python3 caves/tools/render_survey.py
CAVE_AUTOTEST=clear godot --headless --path caves --quit-after 20000
```

`check_fit.py` reads the posture table out of `scripts/body.gd` with a regex rather than
keeping its own copy, reconstructs every section, and scans each one for the tallest gap a
body of each width can find. It fails if a through-passage is impassable in every posture, if
a passage marked `needs_exhale` turns out to admit a relaxed chest, or if a `dead_end` goes
right through. It then walks the `route` and checks that each pair of passages really does
overlap and that their floors meet within 40 cm where they do - a cave whose passages are each
passable can still be impassable at a junction, and a 50 cm lip between two crawls is a wall
to a body on its belly. It needs nothing but the standard library and it runs before Godot is even
downloaded in CI, because a cave that cannot be caved should not get as far as being exported.

## The files

| | |
|---|---|
| `cave/sowbelly.json` | the cave. **Edit this.** |
| `scripts/bore.gd` | one passage: spline, sections, sweep, and the clearance queries |
| `scripts/geo.gd` | cross-sections, levelled frames, the sweep, colliders |
| `scripts/cave.gd` | reads the JSON, trims the junctions, chunks the result at 20 m, rigs the rope and the drips |
| `tools/check_fit.py` | proves it is passable |
| `tools/render_survey.py` | draws `docs/survey.png` |
