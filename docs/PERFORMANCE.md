# Holding 72 Hz on a Quest 3

The headset is the tightest machine this game runs on and it is the one it is for: a browser, one
wasm thread, and every frame drawn twice, at 13.8 ms a frame. A phone at 1100 pixels across was
always smooth; the headset was not, and this is what was done about it.

The short version: **PS1 mode**. Not a filter over the top - the look *is* the optimisation, and
every trick in it is one a 1996 console used for the same reason (`scripts/ps1.gd`).

## Measuring it

```
DERELICT_PERF=1 xvfb-run -a godot --path . --quit-after 2400      # any machine, even a software renderer
DERELICT_SEED=4242 DERELICT_PS1=1 DERELICT_PERF=1 ...             # same deck twice, one mode each
```

`scripts/main.gd:_perf_probe` flies the camera through every room, doorway and corridor of a
generated deck, by day and then at night with the flashlight on, and prints per viewpoint:

- **draws** - draw calls in that frame. The number that decides whether a browser keeps up.
- **vertices**, **objects** - what was submitted.
- **in frustum** - the same count split into hull / loose / labels, so a bad row says *what* to fix.
- then a census of everything on the deck that costs a draw call, the texture and buffer memory,
  and what the frame costs with each subsystem switched off (`_perf_who`).

Draw calls, vertices and memory do not depend on the GPU doing the measuring, so these numbers are
comparable from a laptop, from CI, or from a software rasteriser in a container. Milliseconds are
not - read those only against each other, in the same run.

## Where it went

One deck (`DERELICT_SEED=4242`), 44 viewpoints - every room, doorway and corridor, by day and then
at night with the flashlight on:

| | worst frame | mean | texture memory | deck meshes |
|---|---|---|---|---|
| before | 563 draws | 242 | 51.8 MB | 156 |
| after, modern look | 401 draws | 167 | 52.8 MB | 106 |
| after, PS1 mode | 213 draws | 88 | 41.8 MB | 56 |

Draw calls are only half the story - they say nothing about the per-pixel work, which is what a
headset actually runs out of. PS1 mode also draws 36 % of the pixels per eye, lights per vertex
instead of per pixel, reads one texture per pixel instead of three or four, and carries no
tangents. On a software rasteriser - a crude stand-in for a fill-limited GPU - the same tour runs
at 84 ms a frame in PS1 mode against 185 ms in the modern look.

The worst frame is a night one and moves around a little between runs: the thing that walks at
night is a rig of forty-odd parts, and whether it is in shot changes the count.

The first structural win below lands in both modes; the texture page and everything after it is PS1 mode.

**Bolted fittings merge into the wall they are bolted to.** A deck hangs a hundred-odd
extinguishers, handholds, lockers and rails on its walls, and each was a node with two or three
surfaces - about two hundred draw calls of clutter. They are static, so they now go into the same
merged chunk mesh as the hull (`Kit.Merger.add(..., collide: false)`), which costs nothing extra to
draw. Each still gets its own forgiving grab box, because every fitting is a handhold and the box
is what makes a hand catch a rail instead of passing through it - the merged geometry is kept out
of the chunk collider so the two never fight.

**One texture page for the static hull** (PS1 mode). Plating, floor grating, hazard stripes and
flat painted metal live in the four quarters of one 256-pixel image (`StationTex.atlas`). Merged
geometry carries its quarter in UV2 and its repeat baked into UV, and the shader wraps inside the
quarter - so four material groups per chunk become one. A deck went from 106 hull meshes to 56.
This is what a console with 2 MB of texture memory did, for the same reason.

Then the per-pixel work, all of it PS1 mode:

| | why it is cheap | why it is period-correct |
|---|---|---|
| vertex lighting | a corridor lit by four lamps costs four sums per vertex, not four per pixel | Gouraud shading is the look |
| 0.6 render scale per eye | 36% of the pixels of a full-size eye buffer | the console drew about 320x240 |
| foveated eye buffers (both looks) | the edges of each eye, which the lens blurs anyway, are shaded coarser | - |
| no MSAA in the headset | no resolve, on a tiler drawing everything twice | there was no antialiasing |
| point-sampled 128 px textures | a quarter of the bandwidth and the memory | chunky texels are the point |
| no normal maps, no tangents | one texture read per pixel, four fewer floats per vertex | there were no normal maps |
| no triplanar sampling | three texture reads become none - those surfaces are flat painted metal now | flat metal |
| vertex snapping, affine UVs | free: it happens in the vertex shader | the wobble and the swim |
| cheap sky | drops the second detail octave, the ocean glint and one scattering term | - |
| no flashlight shadow map | the beam stops re-rendering everything in its cone every frame | the console had no shadow maps |
| dust at a third, culled at 12 m | blended quads are what a tiler charges most for | - |
| props culled at 26 m, two sunlit windows | fewer objects, fewer lights | draw distance |

## One trap, written down

The first cut of PS1 mode was half as bright as the modern look, and the reason was not the
lighting model - swapping vertex lighting for per-pixel changed nothing. Vertex colours reaching a
**custom** shader are already linear; converting them from sRGB again (a `pow(colour, 2.2)` that
looked obviously right) is what ate the light. The hull carries every piece's tint as a vertex
colour, so it darkened the whole station. If a future change to `Ps1.CODE` makes the deck gloomy,
look there first, and measure it - `tools/` has no brightness check, but rendering the same
viewpoint in both modes and comparing mean luminance settles it in a minute.

A flat diffuse surface does lose something real: the specular highlight a metal used to get. That
comes back as `gain` in the shader, in proportion to how metallic the material was, which is why
the station reads at about the brightness it did before.

## The one that never landed

Since the first performance pass the headset drew every eye at full size. `_enter_vr` set
`webxr.render_target_size_multiplier`, but Godot 4.7's `WebXRInterface` has no such property (it
belongs to `OpenXRInterface`). A release export skips the bad assignment without a word; a debug
export stops `_enter_vr` on it, before the session is even asked for. Either way the 0.6 scale in
the table above was never applied, and nothing here measures the headset, so nothing noticed.

Godot's WebXR creates its projection layer itself (`createProjectionLayer`, in
`library_godot_webxr.js`) and passes neither a scale factor nor foveation. So `main.gd` wraps the
browser's `XRWebGLBinding.prototype.createProjectionLayer` just before the session starts: the
layer Godot asks for comes out at `XR_SCALE` of the recommended size, with `fixedFoveation` set.
The browser console prints `[xr] eye buffers at 0.60, foveation 1.00: ok` when it took. Anything
other than `ok` means the browser has no WebXR layers, and the layer is drawn at full size.

Two more things only a headset was paying for:

- **The fade and the comfort vignette** are quads glued to the camera across the whole view. Both
  stayed visible when clear, so every frame paid for two blended passes over every pixel of both
  eyes. They are hidden now while there is nothing on them.
- **72 Hz, asked for.** The physics ticks at 72. A browser presenting at 90 fits a frame with no
  physics step every few frames, and the body stutters along the corridor however fast each frame
  draws. `_on_session_started` asks the session for 72 Hz when the headset offers it.

## What was deliberately not done

- **No gameplay was cut.** Same deck size, same rooms, same props, same fittings to grab, same
  lights, same stalker, same nights. Nothing in PS1 mode changes what you can do or see coming -
  the corridor that was lit is still lit, the fitting that was grabbable is still grabbable.
- **No tests skipped.** `DERELICT_AUTOTEST=1`, `=eva` and `=touch` all pass in both modes, and the
  probe is part of the same harness.
- Occlusion culling: Godot's needs a bake, and the deck is generated at load.
- Chunks stayed at 20 m. Bigger chunks are fewer draw calls but worse culling; the measurement did
  not support the trade.

## If it is still short on a headset

In this order, measure between each:

1. `XR_SCALE` at the top of `main.gd` - 0.6 is the PS1 default, 0.5 is still legible. Check the
   browser console for `[xr] eye buffers ... ok` first: if the layer wrapper did not take, nothing
   else on this list will be enough.
2. Corridor lights: `Station._place_lights` puts one every two cells. Every three is dimmer and
   cheaper.
3. `Ps1.SNAP_XR` - coarser snapping hides a lower render scale.
4. The name plates and terminal labels (`Label3D`) draw twice each when they have an outline.
