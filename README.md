# Derelict Orbit

Zero-G VR horror aboard orbital station **Kestrel-9**. Godot 4.7, exported to HTML5 / WebXR, tuned for Meta Quest 3.

**A different station every run.** The deck is generated from a modular kit when the game starts: a branching
corridor network on a 4 m grid with five or six rooms hung off it (control room, power plant, life support,
laboratory, observation deck, gym, server room, EVA airlock). Every piece is also rolled about the axis it attaches
along - the interior is a 3 m square, so a corridor's grating may be on your left, the next cell's on the ceiling, a
junction upside down, and a room turned on its side into a tall hall behind a normal door. There is no floor: every
surface is something to grab. Learn the layout by day; you will need it in the dark.

**You move by hand.** Hold **grip** with a hand next to any rail, wall or console and it is anchored there - pull
yourself along and let go with a flick to fly. The suit pack on the sticks is for corrections only: about two
seconds of burn, then it refills slowly.

Keep the station alive by day - three maintenance tasks per shift, done by pointing your right controller at a wall
terminal and holding **trigger**. Every night the main power fails and you wake in the dark in the room farthest
from the power plant. Find the plant and hold the MAIN POWER panel to bring the lights back. Something walks the
station at night. Your flashlight freezes it while the beam is on it; the moment you look away it moves. Survive 7 nights.

The haunting escalates with the day counter (and with every shift you leave unfinished):

| Intensity | What you get |
|---|---|
| 1 | shadows crossing doorways at the far end of the corridor you're looking down, distant bangs |
| 2 | light flicker; the night stalker's eyes glow |
| 3 | whispers by your ear, a watcher standing down a corridor behind you (vanishes when stared at) |
| 4 | loose crates get shoved; the stalker closes distance while you're not looking |
| 5 | brief daytime blackouts; the stalker pushes through the flashlight beam at 30 % speed |
| 6+ | shadows cross much closer, faster stalker |

## Controls

**Quest 3 (Touch controllers)**

| Input | Action |
|---|---|
| Grip (hold), hand touching something | grab it: move the controller to pull yourself, release to let go with momentum |
| Left stick | thruster burn relative to where you look (forward / strafe) - tiny tank, refills slowly |
| Right stick up / down | thruster up / down |
| Right stick left / right | snap turn 30 deg |
| A / X | flashlight on / off |
| Trigger (right) | hold while pointing at a terminal |
| Left wrist | task list, clock, night instructions |

**Desktop fallback (any browser / the Godot editor)**: **right mouse** on a surface within arm's reach grabs it, drag
to pull, release to let go. WASD / Space / C fire the thrusters, Shift holds on to whatever is in front of you, F flashlight,
E or left click to use a terminal, Esc releases the mouse. `Ctrl+Shift+N` ends the current shift immediately (dev shortcut).

## Project layout

```
project.godot          GL Compatibility renderer (required for web), XR shaders on, gravity 0
export_presets.cfg     Web preset: thread support OFF -> runs from any static HTTPS host, no COOP/COEP headers
scenes/main.tscn       minimal skeleton; everything else is built in code
scripts/game.gd        autoload: phases, day counter, tasks, intensity
scripts/sfx.gd         autoload: sound bank
scripts/main.gd        WebXR session, title UI, environment, autotest
scripts/player.gd      zero-G CharacterBody3D: grab-and-pull locomotion, thruster tank, flashlight, laser, wrist HUD
scripts/layout.gd      the deck plan: seeded corridor growth on the 4 m grid, rooms through their doorway, piece
                       + rotation per cell, BFS path / distances on the cell graph
scripts/kit.gd         loads kit/*.glb once, merges placed pieces per chunk and material, trimesh colliders
scripts/palette.gd     the materials the kit's glTF names are remapped to (textured plating, grating, hazard,
                       power-controlled emissives)
scripts/station.gd     builds a deck from the layout: hull, lights, terminals per room type, name plates, props,
                       the outside (planet, stars, truss, solar wings), navigation for the stalker
scripts/station_classic.gd  the original hand-laid hub-and-four-arms map, kept: swap it onto the Station node
kit/                   the modular station kit (glTF, 4 m cells, rooms 3x3) plus the loose props
                       (prop_*.glb: crates, canisters, helmets, debris) - see kit/KIT_README.md
scripts/geo.gd         SurfaceTool batcher: one mesh per material (+ trimesh collider); used by the classic map and small extras
scripts/tex.gd         procedural textures: riveted plating + normal maps, grating, hazard stripes,
                       vents, telemetry screens, LED rows, starfield, planet, solar cells
scripts/interactable.gd  wall terminal (hold-to-complete)
scripts/haunt_manager.gd daytime events + night stalker spawning
scripts/shadow_figure.gd / stalker.gd  the apparitions
tools/build_props.py   builds kit/prop_*.glb (pure Python glTF writer in tools/proplib.py, no Blender)
audio/*.wav            all synthesised by tools/gen_audio.py (numpy) - no third-party assets
build/web/             the exported WebXR build (index.html)
```

## Reviewing the map without a headset

```
DERELICT_SHOTS=/tmp/kestrel-shots godot --path .
```

Opens a window, starts desktop mode, jumps the camera through ~20 viewpoints (every room, the
corridors, the skylight, the windows, then the same with the power off) and saves a PNG of each.

## Running on the Quest 3

WebXR needs **HTTPS** (localhost is exempt, but the Quest isn't localhost). Two easy routes:

1. **GitHub Pages** - push `build/web/` to a repo, enable Pages. Because the export has thread support off it does
   not need the cross-origin-isolation headers Pages can't set. Open the URL in the Quest browser, tap **ENTER VR**.
2. **Local dev** - serve `build/web/` on your Mac and tunnel it:
   ```
   cd build/web && python3 -m http.server 8080
   # in another terminal (npm i -g localtunnel, or use ngrok / cloudflared)
   npx localtunnel --port 8080
   ```
   Open the https URL in the Quest browser.

Note: the wasm is ~38 MB; first load on the headset takes ~10-20 s.

## Re-exporting

In the Godot editor: Project > Export > "Web (WebXR, Quest 3)" > Export Project. Or headless:

```
godot --headless --path . --import
godot --headless --path . --export-release "Web (WebXR, Quest 3)" build/web/index.html
```

Smoke test the whole loop without a headset (day -> tasks -> night -> stalker -> power -> death -> restart):

```
DERELICT_AUTOTEST=1 godot --headless --path . --quit-after 6000
```

## Quest 3 performance notes

- Compatibility renderer, no glow/SSAO, light depth fog, MSAA 2x, 9 unshadowed omni lights + one shadowed spot
  (the flashlight). Hull geometry is batched per area and material (about 10 meshes per room) so draw calls stay
  in the low hundreds even with all the greebles. If you see frame drops, set `flashlight.shadow_enabled = false`
  in `player.gd` first, then drop `normal_enabled` on the hull materials in `station.gd`.
- Shadow atlas is 1024 on mobile (`project.godot`).
- Physics runs at 72 Hz to match the headset's default refresh.

## Ideas for next iterations

- Hand-tracked grab-and-pull along rails (the brake-on-grip is a stand-in for that).
- Audio logs on the terminals telling the previous crew's story.
- Doors that actually close (the bulkhead rings are open frames).
- Let the stalker leave marks: handprints on the portholes, a pod lid left open.
