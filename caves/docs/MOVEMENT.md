# The body

![The Sowbelly survey](survey.png)

*The cave the body model was built against. The orange mark is the Devil's Pinch: 29.3 cm of roof, head first.*

## The idea

Most first-person games model you as a capsule. A capsule has one radius, it either fits or it
does not, and when it does not the physics engine slides it along the wall at full speed. That
is a perfectly good model for a corridor and completely wrong for a cave, because sliding is
free and squeezing is not.

So you are not a capsule here. You are a **cross-section** - a height, a shoulder span and a
chest depth - and a posture is a decision about how to fold that section into the space
available. There are six ways to be a smaller shape and they are all in one table. Everything
else in this document is consequences of that.

The part that matters is the chest. A relaxed chest is 30.0 cm deep. At the bottom of a full
exhale it is 26.5 cm. Three and a half centimetres, held for about six seconds, is the entire
resource economy of the game, and every dimension in `cave/sowbelly.json` was chosen against
it.

## The postures

`CaverBody.POSTURES` in [`scripts/body.gd`](../scripts/body.gd). **Edit this.** Nothing else
decides how big you are, and `tools/check_fit.py` reads this table out of the file with a
regex and re-verifies the whole cave against it, so a number changed here is a cave checked in
CI rather than a cave quietly broken.

| Posture | Gap it needs | Across | Speed | Eye height |
|---|---|---|---|---|
| `stand` | 1.75 m | 0.46 m | 1.40 m/s | 1.62 m |
| `stoop` | 1.25 m | 0.46 m | 1.00 m/s | 1.12 m |
| `knees` | 0.75 m | 0.46 m | 0.75 m/s | 0.58 m |
| `belly` | **chest + 4 cm** | 0.46 m | 0.34 m/s | 0.19 m |
| `commit` | 1.02 m | **chest + 0.5 cm** | 0.13 m/s | 0.88 m |
| `superman` | **chest + 2 cm** | 0.32 m | 0.10 m/s | 0.17 m |

The two bold columns are where the exhale lands. `belly` is prone, so your chest is the
*vertical* dimension and emptying it lowers the ceiling you need. `commit` is upright and
turned sideways through a slot, so your chest is the *horizontal* dimension and emptying it
narrows the gap you need. `superman` is head-first with one arm pushed ahead, which takes your
shoulders from 46 cm to 32 cm and is the only way into a tube narrower than you are wide - and,
lying flat, the chest is its height, so it is also the shape the Devil's Pinch is passed in.

Head first, the collision capsule carries a quarter of the usual 1.5 cm skin, the same as
`commit`. At full skin it is three centimetres smaller than the body it stands for, which is
most of the exhale: a relaxed chest slid under the Pinch's roof, and the Drainpipe let a body to
the end of a lead the model says shuts.

The 4 cm on `belly` is the helmet, the oversuit and whatever is on your back. `commit` gets
only 5 mm because turned sideways in a slot there is nothing on you that is not squashed flat.

`commit` is **1.02 m tall, not 1.25**, and that number is load-bearing. Nobody goes through a
28 cm slot standing to attention - you are sideways, knees bent, head turned. It matters because
the section is drawn as a polygon: at 27 cm of width a rift gives back barely three quarters of
its drawn height, so a 1.25 m body needed a slot 1.7 m tall to fit, and a 1.7 m slot is a tunnel
you can see yourself standing up in. A playtester found that in about a minute.

**Posture is automatic.** Up-casts from your feet measure the ceiling, and you become the
fastest shape that fits under it. In a real cave nobody decides to crouch - the rock decides,
and taking that routine choice away leaves the interesting one, which is whether to go lower
than you have to. That is what LOW is for.

**Everything that looks a pace ahead walks the floor to get there.** Headroom, the second
contact ring and the width probe all step forward along the *flattened* heading - they have to,
or the body's frame twists every time the passage tips. So on an eighteen-degree climb a point
projected 85 cm ahead lands a third of a metre nearer the floor than it started, which in a
fifty-centimetre crawl is underneath it; casting sideways from inside rock reports no width at
all, and the body folds down to its smallest shape and wedges in a passage it fits comfortably.
`_along_floor` finds the floor under the projected point and restores the height it had. That is
what a gradient does to a look-ahead that does not know about gradients, and this cave is full of
gradients on purpose.

**Casts, plural, and that matters.** Headroom is read at the centreline *and half a shoulder
span either side of it*, and the tightest of the three wins. One ray up the middle reads the
apex of the arch, which in a round passage is nowhere near what a body 46 cm across can get
under - the roof has already started coming down by the time it reaches your shoulder. That was
honest while the cave's crawls were flat-roofed bedding planes, and became a lie the moment they
became tubes. The offset is capped by the room actually available, because in a squeeze the
walls can be 14 cm away and a probe fired from 23 cm out would report no headroom at all.

**A fit is not a choice.** Standing, stooping and hands-and-knees each need **10 cm of clear
headroom over the shape itself** (`POSTURE_CLEAR`) before the body will take them. The gap a
posture *needs* is in the table above; the gap it *waits for* is 10 cm more than that.

This is the rule that took longest to find, and it was found the hard way. The body walked into
the Gullet with 1.26 m of headroom, at 1.25 m of stoop, and stopped dead 3.6 m in. Every ray
fired forward from the eye reported two clear metres of tunnel - and they were right. What had
happened was that its head had caught the lintel of the mouth, the rock that comes down over a
tunnel where it leaves a room. A body that catches an overhang is worse off than one that is
blocked, because the only way to slide along a surface facing downwards is to slide *down* it,
and the floor is already there. Forward went nowhere and backward went nowhere, which is exactly
what an invisible wall is.

Nobody walks fifteen metres stooped with their helmet grinding on the roof. They drop onto their
knees a pace before the low bit, because they can see it coming - and the body reading headroom
four times along the pace ahead (`POSTURE_STEPS`) is that pace, read properly.

The 10 cm is **height only, and only for the three postures with no chest in their box**. Width
never gets a margin anywhere, and neither does the chest: the Devil's Pinch gives a body lying
head first 29.3 cm, an empty chest needs 28.5 and a full one 32, and that is the game. `belly` and `superman` do not get it either - lying flat is not a
choice with room in it, it is the last shape you have.

Standing back up requires **9 cm of clear extra headroom on top of that** (`POSTURE_HYSTERESIS`).
Dropping is instant, because the ceiling is right there; getting up waits. Without that, a
passage hovering around 75 cm has you bobbing onto your knees and back twice a second, and
nobody caves like that.

## Breath

Held, not toggled. Shift on a keyboard, either trigger in VR, the biggest button on the screen
on a phone.

| | |
|---|---|
| `CHEST_RELAXED` | 0.30 m |
| `CHEST_SQUEEZE` | 0.035 m — what a full exhale gives back |
| `EXHALE_IN` | 1.25 /s — about 0.8 s to empty |
| `EXHALE_OUT` | 2.40 /s — it comes back faster than it goes |
| `AIR_DRAIN` | 0.165 /s — a full exhale lasts about six seconds |
| `AIR_REGAIN` | 0.30 /s — and about three and a half to get it back |
| `AIR_REARM` | 0.22 — below this you cannot start another one |

Run out and your body takes the decision back: the chest opens, `air_locked` goes true, and you
cannot exhale again until you have recovered a fifth of it. That is not a punishment and
nothing is lost by it. It means the squeeze has to be solved again, and the next attempt
starts from further back.

The slate counts the seconds down while you are holding. The breathing loop slows and drops
away as the chest empties, and there is a gasp on the way back if you ran it to nothing - which
is the only feedback most players will need, because they will not be looking at the slate at
the time.

## Contact pressure

One number, and almost everything you feel comes off it.

Each frame the body casts **two rings of twelve rays** in the plane across the passage: one at
the chest, one 30 cm further up the passage. Each ray is compared against the body's own
half-extent in that same direction, and what comes back is the fraction of the available room
along that line that is *you*. The worst four of the twelve are averaged, and that is
occupancy; pressure is occupancy mapped through `CONTACT_FLOOR` (0.42) and `CONTACT_SPAN`
(0.50).

Two things about that are not obvious and both were bugs first.

**Averaging raw distances is wrong.** Picture a bedding crawl: three metres wide and thirty-eight
centimetres tall. Average how far away the rock is and it reads as open space, because the two
horizontal rays fly off into the dark - but nothing about that passage is open. What is
pressing on you is the ceiling. Comparing each ray against your own extent along it fixes this:
the wide directions cannot vote, because you are not filling them.

**One ring is not enough.** A caver stopped dead by a pinch 30 cm in front of them has a
perfectly roomy chest, and the ring at the chest says so. The second ring, cast up the passage,
measures the cross-section you are about to be in - which is the one that decides whether you
get through, and the moment the number most needs to be right.

What pressure drives, in order of how much it matters:

- **The scrape loop.** `Sfx.set_scrape` runs a broadband grind whose gain and pitch track
  pressure, and only while you are moving - rock you are resting against makes no sound. This
  is what sells a squeeze, and it is doing more work than anything on screen.
- **Speed.** `1 - smoothstep(0.35, 0.94, pressure)`, floored at 0.34. The floor matters as much
  as the curve: a squeeze you fit through is slow, not still - four centimetres a second with
  rock on both shoulders, twenty-odd seconds to cross the Devil's Pinch. Floor it lower and a
  passage you genuinely fit becomes indistinguishable from one you do not, which is exactly
  the distinction the game is about.
- **Haptics.** Controller rumble in VR, `Input.vibrate_handheld` on a phone, both only while
  moving.
- **The vignette.** The rock closing in at the edge of the view, on the camera-glued quad
  Derelict Orbit uses for its comfort vignette.

## Wedged

Pressure at 0.90 or above, asking to go forward, and less than **2 cm of ground made in
0.7 seconds**. Measured over a window rather than per frame, because a real squeeze is not
stationary - it is slow, and a per-frame threshold would call four centimetres a second
"stuck".

Being wedged stops forward movement dead. Backwards still works. Changing shape still works.
There is no timer, nothing is counting down, and nothing is lost - the slate says
`WEDGED - empty your chest and back off`, because a first-time player should not have to guess.

Three ways out, and the first is the one that matters:

1. **Get smaller.** You were held at a particular shape; become 1.2 cm smaller than that shape
   on either axis and the rock lets go, whether or not you have managed to move yet. Without
   this the only escapes are pressure dropping - which it will not, you are still in the same
   slot - or moving, which you cannot. Emptying your chest has to be an answer here, or the
   mechanic the whole cave is built around does nothing at the one moment it is supposed to
   matter.
2. Pressure falling below 0.80, which usually means you backed off.
3. Moving 6 cm from where you were held.

**You can only be wedged in a posture the chest is part of** - `belly`, `commit`, `superman`.
Standing against a wall you cannot walk through is not being wedged, it is being somewhere you
should not be, and calling it wedged would be a trap: the way out of a wedge is to empty your
chest, and a standing body's size does not depend on its chest at all.

## Climbing

Lifted almost unchanged from Derelict Orbit, where it was the entire locomotion system in
zero-G. Grip near rock and the hand is pinned to the world point it found; the body is then
driven so that hand returns to where it grabbed.

Under gravity the same three lines become climbing, chimneying a rift and hauling yourself over
breakdown - and a hand on the rock also stops you falling, which is what a hand on the rock is
for. Desktop and touch use the same model with a virtual hand: a ray from the eye finds the
rock, and dragging the mouse or a finger moves the hand in the camera's frame.

## VR in a 28 cm slot

The genuinely hard part, and worth saying plainly what it costs.

**You cannot crawl in your living room.** Your headset's real height maps onto the posture
band, so physically crouching crouches you in the cave. A stick click takes you lower than the
room allows. The floor comes up to meet the posture you are in - the body height is applied to
the `XROrigin3D` and the camera is never written to, so the headset stays authoritative and
the view never lurches.

**Your head will go through rock, because nothing can stop it.** So it goes black instead: the
camera-glued fade quad rises as head clearance drops under 16 cm. That is Derelict Orbit's
loading fade doing a second job, and it is a better answer than showing you the inside of the
world.

**Rock is solid from both sides.** Godot's trimesh shapes ignore backfaces by default, so a ray
cast from inside rock hits nothing and reports open space - and a body that ends up briefly
embedded in a wall reads the cave as a cathedral and tries to stand up in a slot. Every
collider here sets `backface_collision`, which makes the body model self-recovering: embedded
means zero clearance, which folds you down immediately.

**A prone body lies along the floor, not along the horizon.** Flat out, the collision capsule
is a metre of capsule pointing where you are going. Leave it level in a passage dropping at
thirty degrees and its nose sits a third of a metre higher than the roof in front of it, so it
jams - on nothing, in a tunnel with room to spare, which from inside is indistinguishable from
an invisible wall. It now takes its long axis from `get_floor_normal()`, clamped to about 46
degrees, and it is a metre rather than 1.3 m, because the longer the capsule the more of a
passage's curve it has to span at once. Passages with real climbs and drops in them are worth
nothing if the collider refuses to tilt with them.

**And the floor it reaches down for is short when you are flat out.** `floor_snap_length` keeps
a body glued to a slope it would otherwise leave for an instant, and 42 cm of it is right for
stepping over breakdown in a room. In a 60 cm crawl it is most of the passage, and this cave is
a shell one triangle thick with nothing behind it - so a body that came off a thirty-degree
floor snapped straight through it, ended up 13 cm inside the rock, read four centimetres of
headroom and folded itself down to `superman`. Prone gets 10 cm, which is all it needs.

One floor angle for every posture, and a generous one: **58 degrees**. Prone used to get 40 and
upright 58, which is backwards - flat out you have four points of contact and your weight spread
along the rock. Splitting the difference at 52 was worse than either, because it turns the
57-degree lip at the Gullet's mouth from something you walk over into a wall.

**The body says what is wrong where you are looking.** `Caver._advise` puts `CaverBody.advice()`
on the HUD and repeats it every 2.5 s while it holds. It used to be on the survey slate and
nowhere else - and the slate is an object on your wrist you have to decide to look at. So a
player met the Devil's Pinch with a full chest, got held by 15 mm of rock, saw the view close in
and nothing else, and reported an impassable dead end. The cave's central mechanic was invisible
at the one moment it mattered.

**A body arrives the right shape.** `teleport` probes and folds before the first physics step,
in two passes, because where the chest sits depends on the posture and the posture depends on
what the chest can see. Without it a caver dropped into a crawl lands standing, a capsule twice
the width of the passage, and gets ejected through the wall - which a warm-up tour and a
respawn will do as readily as a test.

Comfort snap turning is on the title screen for players who need it.

## The shell guard

The cave is a shell one triangle thick with nothing behind it, and a `CharacterBody3D` has two
ways through a wall like that, neither of them by moving. The capsule is **resized or turned into
rock in one step** - a posture change in a slot, a prone capsule swung across a tube by the
mouse - and the engine's depenetration shoves it out whichever side is nearer. Or a snap, a haul
or the rope pulls it a few centimetres into the shell, and the next step's recovery finishes the
job. Once the centre is on the far side of a face there is no rock to slide along, and you are
outside the world without having seen it happen. It was easy to do, and it happened most in
exactly the places the game is about.

Two checks in `caver.gd`, both cheap, and together they make the shell a wall from the inside:

- **A shape is checked before it is applied** (`_shape_clear`). Every step the body computes the
  capsule it wants - radius, length, tilt, offset - and asks the physics server how deep that
  capsule would sit in the rock *here*. Under `SHELL_SKIN` (3 cm) it is resting on rock, and it
  goes on. Deeper than that, it is refused and the body keeps the last shape that was clear,
  until the rock gives it room. A shape that is *smaller* than the current one is always
  allowed, because shrinking is the way out of everything. A prone capsule therefore no longer
  turns in a tube it cannot turn in: the view turns, the collider waits.
- **The centre is traced after every step** (`_guard_shell`). Two rays, from where the capsule's
  centre and the chest were at the end of the last step to where they are now. Every collider has
  `backface_collision` on, so a ray crosses a face from either side, and a centre that crossed
  one is a body that went through a wall - whichever of the ways through it took. It is put back
  where it was, still, with the shape it had: that position was inside the cave a step ago and the
  shape was clear of the rock there. At walking pace the trace is two centimetres long, so it
  cannot clip a corner the capsule itself went round.

`Caver.unclips` counts the second one and the route test asserts it is zero: the guard is the
last line, not the first, and a route that needs it is a route where the capsule went through a
wall for a reason that wants finding rather than hiding. `Caver.refits` counts the first, and it
is allowed to be large - a body pushing into the closed end of the Drainpipe is refused a shape
every step, which is the lead doing what a lead does. `CAVE_DEBUG_REFIT=1` prints every 24th
refusal with the shape it wanted, the shape it kept, and how deep each would be.

## When it stops and you cannot see why

`Caver.debug_contacts` exists because **rays lie about this cave, and every diagnosis made from
them alone has been wrong.** A ray is a line fired from one point; what stops a CharacterBody3D
is a capsule 43 cm across catching rock the line missed by a few centimetres. So when
`CAVE_AUTOTEST=route` gives up it stops asking the passage what is there and asks the body:

    capsule r 0.215 h 1.250 at +0.62 m, upright, on floor true, floor at 18 deg, vel 0.000 m/s
      touching Rock (roof) at (7.06, -16.60, 1.24), normal (-0.65, -0.74, -0.16), pushes you back
      capsule is INSIDE rock at (7.06, -16.60, 1.24), 0.000 m deep
      sweep (0.98, 0.00, 0.18): 2.00 m of 2.00
      sweep (0.94, -0.29, 0.17): 0.00 m of 2.00

That is the shape, every contact `move_and_slide` made and which way it faced, whether the
capsule is already overlapping anything, and how far a swept cast of that same capsule gets.
The four lines above name a blockage four rays had just called two clear metres of tunnel: a
face pointing down and backwards at head height, horizontally clear but impossible to slide
along without descending into the floor. Reach for it first, not last.

## The files

| | |
|---|---|
| `scripts/body.gd` | the shape, the breath, the rings, the wedge. **Edit this.** |
| `scripts/caver.gd` | gravity, gated movement, climbing, the head, the fade |
| `scripts/intent.gd` | what the player asked for, from any of four sources |
| `tools/check_fit.py` | reads the posture table out of `body.gd` and re-checks the cave |
| `cave/sowbelly.json` | the dimensions those numbers are measured against |

After changing any number in `POSTURES`, `CHEST_RELAXED` or `CHEST_SQUEEZE`:

    python3 caves/tools/check_fit.py
    CAVE_AUTOTEST=1 godot --headless --path caves --quit-after 9000

The first tells you whether the cave is still passable. The second tells you whether the
Devil's Pinch still refuses a full chest and still opens for an empty one, which is the only
assertion in the project that is really about the design rather than the code.
