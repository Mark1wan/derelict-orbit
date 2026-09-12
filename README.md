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
| Grip (hold), empty hand touching something | grab it: move the controller to pull yourself, release to let go with momentum |
| Grip on an item (loose, or holstered at your waist) | hold it while you grip; let go over an empty holster to belt it, anywhere else and it floats off |
| Left stick | thruster burn relative to where you look (forward / strafe) - tiny tank, refills slowly |
| Right stick up / down | thruster up / down |
| Right stick left / right | snap turn 30 deg |
| Hold B + left stick | rotation thrusters: forward / back pitches, left / right rolls - the spin keeps going, a grab stops it |
| Hold B + right stick left / right | rotation thruster: yaw |
| A / X | flashlight on / off, wherever it is (hand, belt or drifting) |
| Trigger | hold while pointing that hand at a terminal - holding the repair tool the terminal names |
| Y (left hand) | crew terminal hologram on / off: tasks with the tool each needs, clock, thruster fuel, belt, where the tools are |

**Desktop fallback (any browser / the Godot editor)**: **right mouse** on a surface within arm's reach grabs it, drag
to pull, release to let go. WASD / Space / C fire the thrusters, Shift holds on to whatever is in front of you, **R + mouse** rolls and pitches the whole body, **Tab** shows or hides the crew terminal. **1-4** swap
your hand with that belt holster, **Q** lets go of what you hold, **E or left click** picks up a loose item in reach or uses the
held tool on a terminal, F flashlight, Esc releases the mouse. `Ctrl+Shift+N` ends the current shift immediately (dev shortcut).

## Tools and the belt

A hand that holds something cannot grab a rail, so what you are not using goes on the **tool belt**: four holsters
around your waist (1 left hip, 2 front left, 3 front right, 4 right hip) that turn with the way your body faces.
Tools hang pointing at the deck; the flashlight clips on pointing forward, so on the belt it still lights your way
(and still freezes the stalker). Let go of an item anywhere else and it drifts off in zero-G with your hand's
motion - it bounces off walls and glows amber until you catch it.

Every task terminal names the repair tool it needs, and only that tool, pointed at it with trigger held, works:

| Tool | Tasks |
|---|---|
| Wrench | coolant pump, O2 scrubber filter, CO2 vent, treadmill harness |
| Multitool | glovebox seal, blast shutters, bike telemetry, rack cooling, suit batteries |
| Scanner | nav computer, alarm log, sample cultures, star tracker, signal log |

You start with the flashlight and the wrench. The multitool and the scanner are floating just inside the door of
two other rooms (seeded per deck). The wrist lists what is in your hands, on the belt, and where the rest was
last seen. The MAIN POWER panel at night needs no tool.

## Rotation

There is no up on Kestrel-9. Hold **B** and the sticks turn into rotation thrusters: the left stick pitches
(forward / back) and rolls (left / right), the right stick yaws. It is real zero-G spin - it builds up while you
burn, keeps going when you let go, costs the same small tank as the linear thrusters, and only stops when a hand
takes hold of the station. The tool belt follows your body, so it is still at your waist upside down. A vignette
closes in while you spin; players who get sick from smooth rotation can tick **VR comfort** on the title screen to
rotate in 30 degree snaps instead. Waking up at night and restarting stand you upright again.

## The orbit: Earth, sun and sunlight

The sky is a shader (`sky/orbit_sky.gdshader`), so the Earth can fill most of the lower half of the view the way it
does from low orbit without ever intersecting the station: a lit day side with ocean glint, a night side of city
lights, and a blue atmosphere along the limb that turns orange where the sun rises or sets through it. Its textures
are baked once by `tools/bake_sky.gd` into `sky/`. From low orbit the ground straight below is magnified far past any
single texture, so the shader tiles a small detail texture over the surface at two scales - terrain grain, cloud
wisps, and the city lights, which are town specks cut out of a smooth population map so they stay points of light.

`scripts/orbit.gd` moves the sun along the orbit with the game: each shift opens with the sun rising from behind
the Earth, it crosses overhead through the shift, sets as the shift ends, and the night is the station passing
through the Earth's shadow - that is the dark the power failure leaves you in. Restoring power brings the next sunrise.

Sunlight never shines through the hull. The sun's DirectionalLight3D only touches the exterior truss, solar wings
and radiators (render layer 3). Inside, `scripts/window_sun.gd` gives every outside window the sun can actually
reach a light of its own - a patch thrown on the far wall and a faint shaft from the glass - and a window with
another module between it and the sun stays dark, so the station shades itself as the sun moves. The windows are
read from the kit's glass geometry. Real shadow maps for a whole deck are left out on purpose: too heavy for a
Quest 3 until measured on one.

## Project layout

```
project.godot          GL Compatibility renderer (required for web), XR shaders on, gravity 0
export_presets.cfg     Web preset: thread support OFF -> runs from any static HTTPS host, no COOP/COEP headers
scenes/main.tscn       minimal skeleton; everything else is built in code
scripts/game.gd        autoload: phases, day counter, tasks, intensity
scripts/sfx.gd         autoload: sound bank
scripts/main.gd        WebXR session, title UI, environment, autotest
scripts/player.gd      zero-G CharacterBody3D: grab-and-pull locomotion, thruster tank, flashlight, laser, wrist HUD
scripts/item.gd        the flashlight and the repair tools (built in code): hand / belt / loose, zero-G drift
scripts/tool_belt.gd   four holsters at the waist that follow the body's heading
scripts/holo_panel.gd  the crew terminal: tasks and stats as a hologram from the left wrist (Y / TAB)
scripts/orbit.gd       where the sun is: orbit clock tied to day and night, eclipse, sky shader uniforms, exterior sunlight
scripts/window_sun.gd  sunlight through outside windows: per-window light patch and shaft, shaded by other modules
sky/                   orbit_sky.gdshader and the baked textures: Earth day, night population, stars, tiling detail
tools/bake_sky.gd      bakes sky/*.png: godot --headless --path . --script tools/bake_sky.gd
scripts/layout.gd      the deck plan: seeded corridor growth on the 4 m grid, rooms through their doorway, piece
                       + rotation per cell, BFS path / distances on the cell graph
scripts/kit.gd         loads kit/*.glb once, merges placed pieces per chunk and material, trimesh colliders
scripts/palette.gd     the materials the kit's glTF names are remapped to (textured plating, grating, hazard,
                       power-controlled emissives)
scripts/station.gd     builds a deck from the layout: hull, lights, terminals per room type, name plates, props,
                       the outside (planet, stars, truss, solar wings), navigation for the stalker
scripts/station_classic.gd  the original hand-laid hub-and-four-arms map, kept: swap it onto the Station node
kit/                   the modular station kit (glTF, 4 m cells, rooms 3x3) plus 22 props
                       (prop_*.glb), classed wall attachment / floating / room equipment. Every
                       wall fitting is a handhold - see kit/KIT_README.md
scripts/geo.gd         SurfaceTool batcher: one mesh per material (+ trimesh collider); used by the classic map and small extras
scripts/tex.gd         procedural textures: riveted plating + normal maps, grating, hazard stripes,
                       vents, telemetry screens, LED rows, starfield, planet, solar cells
scripts/interactable.gd  wall terminal (hold-to-complete)
scripts/haunt_manager.gd daytime events + night stalker spawning
scripts/shadow_figure.gd  the two daytime apparition events (crossing, watching)
scripts/apparition.gd  the apparitions: smoke figures built from kit/apparition_*.json - the
                       corridor vulto (jinn crossed with the Brazilian shadow person) and the ghul
scripts/ghoul.gd       the ghul: wears a crew member down a corridor to draw you off your shift,
                       unlit until it stops pretending (docs/APPARITIONS.md)
scripts/fae.gd         the Good Neighbours: thirteen wisps envelop a loose prop, carry it, and
                       throw it across the corridor - and half the time you never see the lights
scripts/ritual.gd      night only: one room lit by nine candles, a circle of glyphs, and somebody
                       seated in it - and it all stops the moment you walk in
scripts/stalker.gd     the night stalker
scripts/creature.gd    posable creature rigs from kit/*_rig.json: the night stalker's belly-up
                       crawl and contortions (docs/CREATURE.md), and the chupacabra
scripts/chupacabra.gd  the 1995 Puerto Rican one: waits round the edge of a side passage with the
                       wall over most of it, withdraws when noticed, sometimes bolts across the
                       opening at 7 m/s instead (docs/CHUPACABRA.md)
tools/build_props.py   builds kit/prop_*.glb (pure Python glTF writer in tools/proplib.py, no Blender)
tools/build_creature.py builds kit/creature_rig.json and kit/chupacabra_rig.json + their renders
tools/riglib.py        shared rig machinery: bones, parts, fur, poses, the floor solver
tools/build_apparition.py builds kit/apparition_corridor.json + its renders in docs/
docs/APPARITIONS.md    the apparitions: the jinn/vulto basis, the corridor one, what comes next
docs/CREATURE.md       the night stalker: anatomy, poses, how to change it
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

**Short version: `.github/workflows/webxr.yml` exports the build on every push** - as a
downloadable artifact from any branch, and to GitHub Pages from the default branch. See
[docs/PLAYTEST.md](docs/PLAYTEST.md) for the whole route onto the headset and what to look for in a
test session.

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
