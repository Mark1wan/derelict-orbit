# The apparitions

![the corridor apparition](apparition_corridor.png)

The daytime hauntings used to be a black capsule-and-sticks figure that floated. This is the
replacement, and the basis for the rest of the suite.

## The idea

Two traditions, deliberately mixed.

**Jinn.** In Islamic belief the jinn are made of smokeless fire - not the ghost of a dead person
but a creature of another order, living alongside you in the same rooms, with its own will. So
the apparition is *smoke*, and somewhere inside it there is fire: two embers where a face would
be. They are the only bright thing about it, and they are not eyes so much as coals.

**Vulto.** The Brazilian shadow person: a flat, man-shaped darkness standing in a doorway or at
the end of a hall, seen at the edge of vision, gone the instant you look straight at it. So the
smoke holds a human outline - shoulders, a head, the suggestion of a hood - it has **no feet**,
it does not walk, it *slides*, and when you look at it, it does not fade: it **comes apart**.

What that gets you that a silhouette did not: it has no anatomy to get wrong, it reads at corridor
distance as a hole in the light, and the way it leaves is the scariest thing it does.

## The corridor apparition

47 soft camera-facing puffs, two embers.

- **Core** (41 puffs) - near black, `0.010, 0.009, 0.014`. Stacked, they make the middle of the
  figure darker than the unlit corridor behind it.
- **Haze** (6 puffs) - big, almost transparent, faintly violet. This is the part that matters:
  against an unlit bulkhead a pure black figure is *nothing at all*. The haze is what you catch
  out of the corner of your eye.
- **Embers** (2) - additive, flickering, and they dim before the smoke does when it leaves.

Every puff has an anchor on the figure, a drift orbit (so the mass boils and never holds a shape)
and a dissolve direction. One parameter, `form`, slides every puff from its anchor out along that
direction and fades it: `form` 1 is a figure, 0 is nothing.

| | |
|---|---|
| ![close](apparition_close.png) | ![crossing](apparition_cross.png) |
| Close, in the doorway light | Crossing: it leans into the slide and trails |

**Arriving** is `gather()` - the dissolve run backwards, so it condenses out of the corridor air.
**Leaving** is `disperse()`:

![dissolving](apparition_dissolve.png)

*Four frames of a stare: gathered, opening, the embers going out, gone.*

It is used two ways today, both through `ShadowFigure`: sliding across the mouth of a corridor
(agitated, leaning, trailing) and standing at the far end waiting to be noticed - the watcher,
which disperses once you have looked at it for 0.7 s or got within 3.5 m.

## Cost

Two draw calls for the whole thing: one `MultiMesh` of billboarded quads for the smoke, one for
the embers, with per-instance colour carrying the alpha. The sprite texture is generated once from
a hash-based value noise and shared. No particle system, no shader.

## The files

| | |
|---|---|
| `tools/apparition_spec.py` | the figure: puff layout, embers, the smoke formula. **Edit this.** |
| `tools/build_apparition.py` | writes `kit/apparition_corridor.json` and the images here |
| `tools/render_apparition.py` | the reference renders (corridor, close, crossing, dissolve) |
| `kit/apparition_corridor.json` | 47 puffs, 2 embers - what the game loads |
| `scripts/apparition.gd` | builds and animates it |
| `scripts/shadow_figure.gd` | the two events that use it |

    python3 tools/build_apparition.py

The smoke sprite is the same formula in both languages, on the same integer hash, so the images
match what the game draws rather than illustrating it.

## The rest of the suite

The parts that generalise are the puff cloud, `form`, and the gather/disperse pair. A new
apparition is a new layout function in `tools/apparition_spec.py` plus its own JSON. Candidates,
none built yet:

- **The one in the vent** - smoke pouring *out* of a wall grille and pooling along the ceiling,
  no figure at all until it has finished pouring.
- **The one in the machine** - a jinn inhabiting a console: embers behind the screen, smoke
  bleeding from the seams, the terminal working normally the whole time.
- **The one behind you** - gathers only in the space you are not looking at, and is never there
  when you turn; the only evidence is the ember light on the wall in front of you.
- **The crowd** - several vultos at the far end of a long corridor, standing in a line, all of
  them dispersing at once when the lights come back.
