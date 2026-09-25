# Getting it onto the headset

WebXR needs **HTTPS**. Localhost is exempt but a Quest is not localhost, so every route below is
really about getting `build/web/` onto an HTTPS address the headset can open.

The build is ~40 MB, almost all of it the wasm. First load on the Quest takes 10-20 s.

## The short way: let CI build it

`.github/workflows/webxr.yml` exports the Quest 3 preset on every push to `main` or a `claude/**`
branch, and on demand from the Actions tab.

**From the default branch** it deploys to GitHub Pages. Enable it once - *Settings → Pages →
Source: GitHub Actions* - and after that every push to `main` republishes the game at:

```
https://<owner>.github.io/<repo>/
```

Open that in the Quest browser, wait for the loader, tap **ENTER VR**.

**From any branch**, the run uploads the whole `build/web/` folder as a downloadable artifact
(*Actions → the run → Artifacts → `derelict-orbit-webxr-<sha>`*). Unzip it and serve it from
anywhere with HTTPS. That is the route for testing a branch without touching Pages.

The export is configured with **thread support off**, so it runs from any plain static host and
does not need the `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers that
GitHub Pages cannot set.

## Building it yourself

```
godot --headless --path . --import
godot --headless --path . --export-release "Web (WebXR, Quest 3)" build/web/index.html
```

Then serve it over HTTPS. Locally, the quickest tunnel:

```
cd build/web && python3 -m http.server 8080
# in another terminal
npx localtunnel --port 8080        # or ngrok http 8080, or cloudflared tunnel --url localhost:8080
```

Open the https URL the tunnel prints in the Quest browser.

## On the headset

| | |
|---|---|
| Grip (hold), empty hand near anything | grab it - move the controller to pull yourself, release to let go with momentum |
| Grip on an item (loose, or at your belt) | hold it - release over an empty holster to belt it, anywhere else and it floats off |
| Left stick | thruster, relative to where you look. About two seconds of burn, then it refills slowly |
| Right stick up/down | thruster up/down |
| Right stick left/right | snap turn 30° |
| A / X | flashlight on / off (in a hand, on the belt, or drifting) |
| Hold B + left stick | rotation thrusters: pitch (forward / back) and roll (left / right) |
| Hold B + right stick left / right | rotation thruster: yaw |
| Y (left hand) | crew terminal hologram on / off |
| Trigger | hold while pointing the hand's tool at a wall terminal - each names the tool it needs |
| Left wrist | task list, clock, night instructions |

**Every wall fitting is a handhold** - ladders, grab loops, foot restraints, valve wheels, locker
handles. In a station with no floor those are the route, not the scenery. The colliders carry a
6 cm margin, so you do not have to aim.

## What to look for in a test session

- **Day 1** is deliberately quiet: a couple of distant shapes, some bangs, and lamps that stutter
  with nothing behind them. If day 1 feels eventful, the intensity curve has drifted.
- **Lamps.** Three or four per deck are genuinely failing and stutter all run. Roughly one apparition
  in three also takes the nearest lamp with it. You are not supposed to be able to tell them apart -
  but listen for something *underneath* the buzz. It means something is there about eight times in
  ten (`docs/run_report.html` has the arithmetic).
- **From day 6**, look down side corridors at night for a doorway that is warm.
- **Grabbing.** You should be able to cross a corridor hand over hand without letting go. If you
  find a stretch where you cannot, that is a wall the fitting placer found no room on - worth
  knowing about.
- **Frame rate** in the rooms with the most fittings (power plant, server room) and looking down a
  long corridor through a doorway, which is the worst frame a deck has. **PS1 mode** is on by
  default in the headset - the title screen's first checkbox - and is what the frame budget is
  built around; if you turn it off in a headset, expect it to struggle. If it struggles *with* it
  on, docs/PERFORMANCE.md says what to try next and how to measure it.
- **PS1 mode, what to check**: text on the terminals and name plates still readable at arm's
  length; the amber glow on a loose tool still findable in the dark; hazard stripes still yellow
  and still on the floor edges; no bright seam lines where a wall's plating repeats. Everything
  you can grab, use or be caught by is unchanged - if something is missing rather than chunkier,
  that is a bug.

## Desktop, without a headset

`godot --path .` and play it flat: right mouse grabs a surface within reach, WASD/Space/C are the
thrusters, 1-4 swap the hand with a belt holster, Q lets go, E or left click picks up a loose item or
uses the held tool on a terminal, F the flashlight, `Ctrl+Shift+N` ends the shift.

```
DERELICT_SHOTS=/tmp/kestrel-shots godot --path .    # jump the camera through every room, save PNGs
DERELICT_AUTOTEST=1 godot --headless --path . --quit-after 6000    # the whole loop, no window
```

## Windows, without a headset or a web server

The repo also carries a **Windows Desktop (flat)** export preset. It produces a single
self-contained `DerelictOrbit.exe` (the pck is embedded), which runs by double-clicking - no
local server, no browser, no HTTPS. That is the quickest route to a flat playtest on Windows.

```
godot --headless --path . --export-release "Windows Desktop (flat)" build/windows/DerelictOrbit.exe
```

The build is unsigned, so SmartScreen shows an unknown-publisher warning: *More info → Run anyway*.

**It has no VR.** The headset path is WebXR (`scripts/main.gd` looks for the `WebXR` interface and
falls back to desktop when it is absent), so a native executable can only ever be the flat version.
For the headset, use the web build above.

Desktop controls are the flat ones in *Desktop, without a headset* above. Note that **Esc releases the
mouse rather than quitting** - click back into the window to recapture it.

## On a phone - what to check

Open https://games.biocrafted.xyz/derelict-orbit/ directly (not inside the hub window), turn the phone sideways
and tap **PLAY**. Controls are in the README. Please note the phone model and browser with anything you report.

- **Frame rate**: the fps number top right, in a corridor, in the power plant and server room, and at night with the
  flashlight on. Is it steady? Try the title screen's *Low graphics* off as well.
- **Loading**: how long from opening the link to the title screen, on Wi-Fi and on mobile data. Does the page
  reload itself or crash (older iPhones can run out of memory)?
- **Grab**: press and hold on a wall - does the ring fill and the phone buzz (Android only), and does dragging pull
  you the way you expect? Is 0.28 s too slow or too twitchy?
- **Look vs grab**: can you look around near walls without grabbing by accident?
- **Buttons**: big enough? Anything covered by your thumbs, or covering the crew terminal text?
- **Two-finger roll**: usable, or does it fight with looking?
- **Sound** starts after the first tap? Fullscreen on Android, and does it stay landscape?
- **Held upright** it should ask you to turn the phone.

`DERELICT_TOUCH=1 DERELICT_AUTOTEST=touch godot --headless --path .` tests the touch controls without a phone;
`DERELICT_TOUCH=1 DERELICT_SHOTS=/tmp/touch DERELICT_SHOTS_ONLY=touch godot --path .` saves screenshots of the phone UI.

## Spacewalk - what to check

Open the game with `?eva` on the end of the address to start straight on the spacewalk day.

- Suit up: is the visor rim too heavy in the headset? Too subtle on a phone? Is the breathing too loud?
- The airlock: does it read as a decompression chamber - shutters coming down, hiss, red light, the outer hatch
  opening onto the Earth? Is 6 s of cycling too long?
- The tether: can you find and hit anchors easily (VR trigger with a hand pointed, T, ROPE)? Is reeling at 3.4 m/s
  comfortable in VR, or does it need the vignette? Does the slack line look right?
- Getting lost: drift away unclipped with no fuel - is that scary in a good way, or just stuck?
- The route to the array: how long does it take, and how much O2 is left at the end?
- The repair at the junction box with the wrench and multitool, then back in: does 7 minutes feel right for the day?

`DERELICT_AUTOTEST=eva godot --headless --path .` runs the whole mission; `DERELICT_SHOTS=/tmp/eva
DERELICT_SHOTS_ONLY=eva godot --path .` saves screenshots of it.

## Tools and the belt - what to check in the headset

- Look down: four holster rings at the waist, following your heading but not your head tilt. Seated and standing.
- Grip an empty hand on a holstered tool to draw it; let go over an empty ring to stow it. Is 0.17 m of reach
  forgiving enough without grabbing the wrong holster?
- Let go of a tool mid-air with a flick: does it drift, bounce off a wall and glow amber so you find it again?
- A hand holding a tool must not grab rails. Does moving one-handed with a tool out feel right, or annoying?
- Wrong tool on a terminal: red blink, buzz, and a notice saying where the right tool is.
- Belt the flashlight at night: the beam should point where your body faces and still freeze the stalker.

## Rotation and the orbit - what to check in the headset

- Hold B and spin with the sticks. Does the spin carrying on after you let go feel like zero-G, or just nauseating?
  Is the vignette enough, too much? Try the VR comfort snaps from the title screen too.
- Upside down: grab, pull, use a terminal, draw from the belt. Does the belt stay at your waist?
- Look out of a window at the start of a shift: the sun should rise from behind the Earth's limb with an orange glow.
- Sunlit windows: a warm patch on the far wall and a faint shaft. Does a window go dark when another module is
  between it and the sun? Frame rate in a room with several lit windows?
- Night: no sunlight anywhere, city lights on the Earth's dark side.
- Press Y: does the crew terminal hologram read comfortably above the wrist at any wrist angle? Too big, too faint,
  in the way of the left hand grabbing? Closed, is the pulsing wrist emitter noticeable when tasks change?
