# Derelict Orbit

Zero-G VR horror aboard orbital station **Kestrel-9**. Godot 4.7, exported to HTML5 / WebXR, tuned for Meta Quest 3.

**A different station every run.** The deck is generated from a modular kit when the game starts: a branching
corridor network on a 4 m grid with six or seven rooms hung off it: the power plant, the EVA airlock, the comms
room and the washroom on every deck, and two or three of the control room, life support, laboratory, observation
deck, gym and server room. Every piece is also rolled about the axis it attaches
along - the interior is a 3 m square, so a corridor's grating may be on your left, the next cell's on the ceiling, a
junction upside down, and a room turned on its side into a tall hall behind a normal door. There is no floor: every
surface is something to grab. Learn the layout by day; you will need it in the dark.

**You move by hand.** Hold **grip** with a hand next to any rail, wall or console and it is anchored there - pull
yourself along and let go with a flick to fly. The suit pack on the sticks is for corrections only: about two
seconds of burn, then it refills slowly.

Keep the station alive by day - three maintenance tasks per shift, done by pointing your right controller at a wall
terminal and holding **trigger**. The nights are never the same twice: some nights the main power fails and you wake
in the dark in the room farthest from the power plant, some nights you wake up needing the toilet, some nights both,
some nights nothing at all. Something walks the station on some of them. Your flashlight freezes it while the beam is
on it; the moment you look away it moves. Survive 7 nights. See [The nights](#the-nights).

**Earth is on the radio.** Once a shift the comms console keys up and Gateway Control reads you a
message - about the lights that come on at 03:00, about life support scrubbing for two - and then
waits on your report. That uplink is where the story is told; see [The uplink](#the-uplink-messages-from-earth).

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
| Trigger | hold while pointing that hand at a terminal - holding the repair tool the terminal names, or at the comms console to send your shift report, or at the washroom stall door to swing it (no tool needed) |
| Y (left hand) | crew terminal hologram on / off: tasks with the tool each needs, clock, thruster fuel, belt, where the tools are |

**Desktop fallback (any browser / the Godot editor)**: **right mouse** on a surface within arm's reach grabs it, drag
to pull, release to let go. WASD / Space / C fire the thrusters, Shift holds on to whatever is in front of you, **R + mouse** rolls and pitches the whole body, **Tab** shows or hides the crew terminal. **1-4** swap
your hand with that belt holster, **Q** lets go of what you hold, **E or left click** picks up a loose item in reach, uses the
held tool on a terminal, or sends your shift report on the comms console, or swings the stall door, F flashlight, Esc releases the mouse. `Ctrl+Shift+N` ends the current shift immediately (dev shortcut).

**Phones and tablets (held sideways)**: the title screen shows **PLAY** when the page is opened on a touch device
(`scripts/touch_controls.gd`). Android Chrome goes fullscreen and locks to landscape; an iPhone keeps its browser bars.

| Touch | Action |
|---|---|
| Left thumb, anywhere lower left | thruster stick - it centres where your thumb lands |
| UP / DN (bottom left edge) | thruster up / down |
| Drag on the right side | look |
| Press and hold on a surface within reach | grab it (ring fills, phone buzzes) - then drag to pull yourself, lift to let go with momentum |
| Two fingers: twist / slide up or down | roll / pitch the whole body |
| Quick tap | pick up the loose item nearest the middle of the view |
| USE (hold) | use the tool in your hand on the terminal in the middle of the view - or send your shift report on the comms console, or swing the stall door; hold it to restart after dying |
| BRACE (hold) | hold on to whatever is in front of you |
| DROP, LIGHT, TASKS | let go of what you hold, flashlight, crew terminal |
| Belt buttons 1-4 | swap your hand with that holster |

**Low graphics** is on by default on touch devices (title screen toggle): the 3D view renders at about 1100 px across,
no MSAA, a 1024 shadow map, and at most 2 sunlit windows. There is a small fps readout top right for testing.

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

## The nights

Every night rolls its own events, independently, so they can land together:

| Event | Chance | What you do |
|---|---|---|
| **Power failure** | 1 in 3 | you wake in the dark; reach the MAIN POWER panel in the POWER PLANT and hold it |
| **Toilet trip** | 1 in 4 | you wake needing the toilet: get into the working stall in the WASHROOM and shut the door (hold **trigger** / **USE** on it), look at the toilet - the screen goes black - then turn round and open the door. With the power on, that is half the night: go back to bed (the room you woke in) |
| **Both** | 1 in 12 | the toilet comes first: the power panel will not take a hold until you have been |
| **Neither** | 1 in 2 | a quiet night. The screen stays black and the next shift starts |

On a night the power stays on, the deck runs its night cycle: every lamp at 30 %, dark enough for the flashlight to
matter and light enough to see what is standing in a doorway.

**The bundle.** On half the toilet trips, when you open the stall door, there is a bundle of sticks hanging in the
air right outside it, at the height of your eyes - a dozen twigs bound with twine and a red thread, a strip of cloth
knotted round it, a loop of cord at the top as though it had been hung from something. It is put there while the
screen is black, so you never see it arrive, only find it on the way out.

**The thing that walks** (the stalker) is never out on the first night. After that:

| Tonight | Chance it is out |
|---|---|
| power failure | 80 % - it is out from the moment the lights die |
| toilet trip, lights on | 20 % |
| toilet trip and power failure | 45 % |
| ...and the bundle was outside the door | +30 % on either (50 % / 75 %) |

On a toilet night it is decided in the stall, in the black, and let go the moment you open the door - from the room
farthest from you that is not the one you are heading for. All of these numbers are constants at the top of "the
night" in `scripts/game.gd`. For playtesting, `?night=power,toilet,sticks` in the page URL (or
`DERELICT_NIGHT=power,toilet,sticks,monster`, or `quiet`) pins every night of the run to exactly that.

## The uplink: messages from Earth

The story is told over the radio. Twenty seconds into every shift the comms console keys up and
**GATEWAY CONTROL, HOUSTON** reads you a message - an attention tone, the squelch opening, and a
voice, while the console prints what it is saying line by line at the pace it is spoken. Then it is
your turn: point at the console, hold **TRIGGER** (**USE** on a phone) for a couple of seconds, and
your own shift report goes back. No tool needed; you are pressing a key, not fixing anything.

Answer it and the week is a conversation. Day 2 is flight asking why the deck lights drew current
at 03:00 with you asleep. Day 3 is life support scrubbing carbon dioxide for two people. Day 4
answers a report you have not sent yet. By day 6 the station is filing its own crew manifest, and
it says two. Skip a report and Gateway opens the next shift asking why you went quiet, before it
says anything else. On nights 4 and 6, if anything wakes you, the console keys up by itself - it runs
off its own cell, so a power failure does not stop it - and something is on the mic that is not
Gateway and is not you.

The voice is synthesised like everything else here, by `tools/gen_voice.py`, with nothing but the
standard library: three formant resonators walking between one letter's targets and the next over a
glottal pulse train, pitch falling across each sentence, then band-limited to 300-3000 Hz at an
8 kHz sample rate, clipped, hissed, dropped out and wrapped in squelch. You do not make out the
words - the console prints those - you make out that a person is reading a report at you, and on
the last two nights that the person is wrong. The script is `comms/log.json`: edit it, re-run the
tool, and the story changes without a line of code. See [docs/COMMS.md](docs/COMMS.md).

## Rotation

There is no up on Kestrel-9. Hold **B** and the sticks turn into rotation thrusters: the left stick pitches
(forward / back) and rolls (left / right), the right stick yaws. It is real zero-G spin - it builds up while you
burn, keeps going when you let go, costs the same small tank as the linear thrusters, and only stops when a hand
takes hold of the station. The tool belt follows your body, so it is still at your waist upside down. A vignette
closes in while you spin; players who get sick from smooth rotation can tick **VR comfort** on the title screen to
rotate in 30 degree snaps instead. Waking up at night and restarting stand you upright again.

## Spacewalk (day 3)

Some days are one long job instead of three small ones (`Game.MISSION_DAYS`). On day 3 the solar array on the far
wing is failing and the shift is 7 minutes long. The crew terminal lists the steps and marks the next one `>>>`:

1. **Suit up** - hold trigger / USE on the SUIT UP panel beside the hatch in the EVA AIRLOCK. The view goes behind a
   helmet visor, you can hear yourself breathing, and the terminal shows suit O2.
2. **Depressurize** - float through the hatch into the decompression chamber (`scripts/airlock.gd`) and hold the
   CYCLE AIRLOCK panel. The inner shutter comes down, the air hisses out under a red light, the outer hatch opens.
   It will not cycle without a suit, or with you outside the chamber.
3. **Tether out to the array** - the suit's tether (`scripts/tether.gd`) latches onto the amber-blinking anchors on
   the hull, the pylons, the truss and the boom (`scripts/exterior.gd`). Aim at one within 16 m - a cyan ring marks
   it - and fire: **trigger** with a hand pointed at it (VR), **T** (desktop) or **ROPE** (phone). Keep holding to reel
   in; let go and it stays clipped on as a leash; fire at nothing to unclip. Hands still grab anything outside.
4. **Unbolt the damaged panel** (wrench) and 5. **splice the power coupling** (multitool) at the junction box on the
   boom. Bring both: the multitool is somewhere on the deck.
6. **Get back in and repressurize** - into the chamber, cycle it again. That ends the shift.

About 5 minutes of air outside; it refills inside. Run out, or end up in vacuum without a suit, and the shift ends
unfinished. Outside, the haunting has no corridors: it comes through the suit radio and knocks in the hull.
Every deck is generated with the EVA room's back wall clear and a rope route checked from the airlock to the array
(`DERELICT_AUTOTEST=routes` surveys 16 decks). Playtest shortcut: open the page with `?eva`, or run with
`DERELICT_EVA=1`, to start on day 3.

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
scripts/game.gd        autoload: phases, day counter, tasks, intensity, the night's rolls
scripts/sfx.gd         autoload: sound bank
scripts/main.gd        WebXR session, title UI, environment, autotest
scripts/player.gd      zero-G CharacterBody3D: grab-and-pull locomotion, thruster tank, flashlight, laser, wrist HUD
scripts/item.gd        the flashlight and the repair tools (built in code): hand / belt / loose, zero-G drift
scripts/tool_belt.gd   four holsters at the waist that follow the body's heading
scripts/holo_panel.gd  the crew terminal: tasks and stats as a hologram from the left wrist (Y / TAB)
scripts/comms.gd       autoload: the uplink - when Earth calls, what is due back, the night carriers
scripts/comms_station.gd  the comms console: prints the message as it is spoken, hold to transmit
scripts/washroom.gd    the washroom's working stall: its door, and the night's toilet trip (black, the bundle)
scripts/stick_bundle.gd  the bundle of sticks that hangs outside the stall door, built in code
comms/log.json         the whole story: seven messages from Earth, seven replies, two night carriers
audio/voice/*.wav      one rendered transmission per entry (tools/gen_voice.py)
tools/gen_voice.py     the radio voice: formant speech + the radio channel, standard library only
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
kit/                   the modular station kit (glTF, 4 m cells, rooms 3x3: ten rooms) plus 22 props
                       (prop_*.glb), classed wall attachment / floating / room equipment. Every
                       wall fitting is a handhold - see kit/KIT_README.md
scripts/geo.gd         SurfaceTool batcher: one mesh per material (+ trimesh collider); used by the classic map and small extras
scripts/tex.gd         procedural textures: riveted plating + normal maps, grating, hazard stripes,
                       vents, telemetry screens, LED rows, starfield, planet, solar cells
scripts/interactable.gd  wall terminal (hold-to-complete)
scripts/haunt_manager.gd daytime events + letting the night stalker go when the night says so
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
tools/build_extra_rooms.py builds kit/room_comms.glb and kit/room_washroom.glb on the shell the other rooms share
tools/build_creature.py builds kit/creature_rig.json and kit/chupacabra_rig.json + their renders
tools/riglib.py        shared rig machinery: bones, parts, fur, poses, the floor solver
tools/build_apparition.py builds kit/apparition_corridor.json + its renders in docs/
docs/APPARITIONS.md    the apparitions: the jinn/vulto basis, the corridor one, what comes next
docs/PERFORMANCE.md    the frame budget: how it is measured, where it went, what to try next
docs/COMMS.md          the uplink: the shift loop, the seven days, and how the voice is built
docs/CREATURE.md       the night stalker: anatomy, poses, how to change it
audio/*.wav            all synthesised by tools/gen_audio.py (numpy), tools/gen_flicker_audio.py and
                       tools/gen_voice.py (standard library only) - no third-party assets
build/web/             the exported WebXR build (index.html)
```

## Reviewing the map without a headset

```
DERELICT_SHOTS=/tmp/kestrel-shots godot --path .
```

Opens a window, starts desktop mode, jumps the camera through ~20 viewpoints (every room, the
corridors, the skylight, the windows, then the same with the power off) and saves a PNG of each.
`DERELICT_SHOTS_ONLY=washroom` shoots just the comms room and the washroom: the console, the stall
from inside, the door shut, and the door opened on the bundle by the night cycle and in a power
failure. `DERELICT_AUTOTEST=layouts` (headless) lists decks where both rooms are the right way up.

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

Smoke test the whole loop without a headset (day -> tasks -> a first night with no stalker -> power -> a power
failure and a toilet trip at once, with the bundle and the stalker -> toilet, then power -> caught -> restart):

```
DERELICT_AUTOTEST=1 godot --headless --path . --quit-after 6000
DERELICT_AUTOTEST=nights godot --headless --path .    # the odds, a quiet night, a toilet trip back to bed
DERELICT_AUTOTEST=layouts godot --headless --path .   # 300 deck plans: every one has the rooms it needs
```

## Holding 72 Hz on a Quest 3

The headset is the tightest machine this runs on: a browser, one wasm thread, every frame drawn twice, 13.8 ms
each. What keeps it inside that:

- **Smaller, foveated eye buffers.** Each eye renders at 0.85 of the recommended width with fixed foveation at
  full, so the edges of each eye (which the lens blurs anyway) are shaded coarser still. Godot 4.7's WebXR has no
  setting for either, so `main.gd` wraps the browser's WebXR layer factory before the session starts
  (`XR_LAYER_JS`); the browser console prints `[xr] eye buffers at 0.85, foveation 1.00: ok` when it took.
- **Bolted wall fittings merge into the chunk mesh of the wall they hang on** (about two hundred draw calls of
  extinguishers, handholds and lockers, now free - and they keep their own forgiving grab boxes, so a hand still
  catches a rail the way it did).
- **No flashlight shadow map in the headset**, and at most three sunlit windows.
- **Nothing blended over the whole view unless it is showing**: the fade and the spin vignette are hidden while clear.

Measured on one deck (`DERELICT_SEED=4242`), 44 viewpoints by day and night:

| | worst frame | mean | texture memory |
|---|---|---|---|
| before | 563 draws | 242 | 51.8 MB |
| now | 401 draws | 167 | 52.8 MB |

Run the probe on any machine - draw calls and memory do not depend on the GPU measuring them:

```
DERELICT_SEED=4242 DERELICT_PERF=1 xvfb-run -a godot --path . --quit-after 2400
```

See [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for what it prints, where the time went, and what to try next if a
headset is still short.

- The loading stage after "ENTER VR" / "Play" walks the camera through every room behind the black fade so all
  shaders compile before you can see anything.
- Shadow atlas is 1024 on mobile (`project.godot`). Physics runs at 72 Hz, and the session asks the headset for
  72 Hz to match (`main.gd:_on_session_started`).

## Ideas for next iterations

- Hand-tracked grab-and-pull along rails (the brake-on-grip is a stand-in for that).
- Audio logs on the maintenance terminals: the crew that rotated home, in their own words, now that
  the uplink has a voice to read them (`tools/gen_voice.py`).
- Doors that actually close (the bulkhead rings are open frames).
- Let the stalker leave marks: handprints on the portholes, a pod lid left open.
