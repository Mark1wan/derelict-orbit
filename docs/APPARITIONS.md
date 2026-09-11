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

## The ghul

![the lure](ghoul_lure.png)

*What is standing at the end of the corridor. A crew member, facing away. Nothing about it is
lit - a shape against the light at the far end is all you ever really see down a corridor.*

The ghul of pre-Islamic Arabia is not a ghost either. It is a desert demon that waits off the road
in desolate country, takes the shape of a person to bring a traveller in off their route, and eats
what it catches. It lives on the dead. And in every
version of the story, whatever else it can change, **it cannot change its hooves**.

That is the whole design. This one does not jump out at you; it stands a long way off, looking
like a person, and waits for you to walk to it. While you are walking to it you are not doing your
shift. It is the only apparition in the suite that costs you something.

### Two layouts in one figure

Every puff carries a second anchor, and `morph` slides the whole figure between them.

![the turn](ghoul_turn.png)

*Five frames of it deciding to stop pretending. Two eyes open - the first light it has shown -
the shoulders rise into a hunch above the head, the neck runs forward, the arms lengthen until the
hands are on the deck. The feet never move.*

| | |
|---|---|
| ![true](ghoul_true.png) | ![hooves](ghoul_hooves.png) |
| Settled over its meal | The tell, there from the first frame |

**The hooves are in both layouts, in the same place, at the same size** - the one thing about it
that never changes. They are also the only part of the figure that is not smoke: they use a third
tint, horn-coloured, so they take the light when nothing else about it does. Two hard little
objects where a pair of boots should be, and a split at the toe. Nobody is meant to notice them
until they do.

The rest of it is tuned to pass, not to haunt: a higher `plateau` on the sprite (0.55 against the
vulto's 0) so the puffs merge into something solid instead of reading as smoke, browner and
heavier core colour - carrion rather than the vulto's cold black - fewer loose wisps, and legs,
which the vulto never has.

### The event

`scripts/ghoul.gd`. It appears from intensity 3 onward, at a spot at least 9 m away that you are
roughly facing, and stands there. It stops pretending when you get within 6.5 m **or** have looked
straight at it for 2.6 s - whichever you do first - takes 1.1 s to turn, holds the true shape for
a couple of seconds while you decide what to do about it, and then takes itself away down the
corridor and disperses.

It never touches you. The day is not when this station kills you.


## Cost

Two draw calls for the whole thing: one `MultiMesh` of billboarded quads for the smoke, one for
the embers, with per-instance colour carrying the alpha. The sprite texture is generated once from
a hash-based value noise and shared. No particle system, no shader.

## The files

| | |
|---|---|
| `tools/apparition_spec.py` | every figure in the suite: puff layouts, embers, the smoke formula. **Edit this.** |
| `tools/build_apparition.py` | writes `kit/apparition_*.json` and the images here |
| `tools/render_apparition.py` | the reference renders |
| `kit/apparition_corridor.json` | the vulto: 47 puffs, 2 embers |
| `kit/apparition_ghoul.json` | the ghul: 62 puffs (8 of them hooves), 2 embers, all of it morphing |
| `scripts/apparition.gd` | builds and animates any of them - one class, one JSON per figure |
| `scripts/shadow_figure.gd` | the two vulto events (crossing, watching) |
| `scripts/ghoul.gd` | the lure |

    python3 tools/build_apparition.py

The smoke sprite is the same formula in both languages, on the same integer hash, so the images
match what the game draws rather than illustrating it.

## The rest of the suite

The parts that generalise are the puff cloud, `form`, `morph`, and the gather/disperse pair. A new
apparition is a new layout function in `tools/apparition_spec.py` plus its own JSON - `Apparition`
itself does not care which figure it is building. Candidates, none built yet:

- **The one in the vent** - smoke pouring *out* of a wall grille and pooling along the ceiling,
  no figure at all until it has finished pouring.
- **The one in the machine** - a jinn inhabiting a console: embers behind the screen, smoke
  bleeding from the seams, the terminal working normally the whole time.
- **The one behind you** - gathers only in the space you are not looking at, and is never there
  when you turn; the only evidence is the ember light on the wall in front of you.
- **The crowd** - several vultos at the far end of a long corridor, standing in a line, all of
  them dispersing at once when the lights come back.
