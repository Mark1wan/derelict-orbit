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
| Grip (hold), hand near anything | grab it - move the controller to pull yourself, release to let go with momentum |
| Left stick | thruster, relative to where you look. About two seconds of burn, then it refills slowly |
| Right stick up/down | thruster up/down |
| Right stick left/right | snap turn 30° |
| A / X | flashlight |
| Trigger (right) | hold while pointing at a wall terminal |
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
- **Frame rate** in the rooms with the most fittings (power plant, server room). If it drops, the
  first things to try are in the README's performance notes.

## Desktop, without a headset

`godot --path .` and play it flat: right mouse grabs a surface within reach, WASD/Space/C are the
thrusters, F the flashlight, E or left click uses a terminal, `Ctrl+Shift+N` ends the shift.

```
DERELICT_SHOTS=/tmp/kestrel-shots godot --path .    # jump the camera through every room, save PNGs
DERELICT_AUTOTEST=1 godot --headless --path . --quit-after 6000    # the whole loop, no window
```
