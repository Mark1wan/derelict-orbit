# Holding 72 Hz on a Quest 3

The headset is the tightest machine this game runs on and it is the one it is for: a browser, one
wasm thread, and every frame drawn twice, at 13.8 ms a frame. A phone at 1100 pixels across was
always smooth; the headset was not, and this is what was done about it.

## Measuring it

```
DERELICT_PERF=1 xvfb-run -a godot --path . --quit-after 2400      # any machine, even a software renderer
DERELICT_SEED=4242 DERELICT_PERF=1 ...                            # the same deck every run, to compare a change
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

None of this measures the headset itself. On a Quest, Meta's OVR Metrics Tool overlay shows the
frame rate and whether the GPU or the CPU is the one running out.

## Where it went

One deck (`DERELICT_SEED=4242`), 44 viewpoints - every room, doorway and corridor, by day and then
at night with the flashlight on:

| | worst frame | mean | texture memory | deck meshes |
|---|---|---|---|---|
| before | 563 draws | 242 | 51.8 MB | 156 |
| after | 401 draws | 167 | 52.8 MB | 106 |

The worst frame is a night one and moves around a little between runs: the thing that walks at
night is a rig of forty-odd parts, and whether it is in shot changes the count.

**Bolted fittings merge into the wall they are bolted to.** A deck hangs a hundred-odd
extinguishers, handholds, lockers and rails on its walls, and each was a node with two or three
surfaces - about two hundred draw calls of clutter. They are static, so they now go into the same
merged chunk mesh as the hull (`Kit.Merger.add(..., collide: false)`), which costs nothing extra to
draw. Each still gets its own forgiving grab box, because every fitting is a handhold and the box
is what makes a hand catch a rail instead of passing through it - the merged geometry is kept out
of the chunk collider so the two never fight.

**No flashlight shadow map in the headset** (or on low graphics). The beam's shadow map re-renders
everything in its cone every frame - the single most expensive thing in a frame.

**Three sunlit windows in the headset**, the nearest ones, out of six on a desktop.

## The eye buffers

Pixels are what a Quest runs out of first. Each eye renders at `XR_SCALE` (0.85) of the width the
browser recommends - about 72 % of the pixels - with fixed foveation at full (`XR_FOVEATION`),
so the edges of each eye, which the lens blurs anyway, are shaded coarser still.

Godot 4.7 has no setting for either. Its WebXR creates the projection layer itself
(`createProjectionLayer`, in `library_godot_webxr.js`) and passes neither a scale factor nor
foveation, and `WebXRInterface` has no `render_target_size_multiplier` (that belongs to
`OpenXRInterface`). An earlier version of `_enter_vr` set it anyway: a release export skips the
bad assignment without a word, so for a while the headset drew every eye at full size and nothing
noticed.

So `main.gd` wraps the browser's `XRWebGLBinding.prototype.createProjectionLayer` just before the
session starts (`XR_LAYER_JS`): the layer Godot asks for comes out at `XR_SCALE`, foveated. The
browser console prints `[xr] eye buffers at 0.85, foveation 1.00: ok` when it took. Anything other
than `ok` means the browser has no WebXR layers, and the layer is drawn at full size.

Two more things only a headset was paying for:

- **The fade and the comfort vignette** are quads glued to the camera across the whole view. Both
  stayed visible when clear, so every frame paid for two blended passes over every pixel of both
  eyes. They are hidden now while there is nothing on them.
- **72 Hz, asked for.** The physics ticks at 72. A browser presenting at 90 fits a frame with no
  physics step every few frames, and the body stutters along the corridor however fast each frame
  draws. `_on_session_started` asks the session for 72 Hz when the headset offers it.

## What was deliberately not done

- **No gameplay was cut.** Same deck size, same rooms, same props, same fittings to grab, same
  lights, same stalker, same nights.
- Occlusion culling: Godot's needs a bake, and the deck is generated at load.
- Chunks stayed at 20 m. Bigger chunks are fewer draw calls but worse culling; the measurement did
  not support the trade.
- Script time: the whole VR code path is about 0.35 ms of GDScript a frame on a desktop CPU, and the
  physics world is one moving body against static walls. The frame goes on drawing, not on logic.

## If it is still short on a headset

In this order, measure between each:

1. Check the browser console for `[xr] eye buffers ... ok`. If the layer wrapper did not take,
   nothing else on this list will be enough.
2. `XR_SCALE` at the top of `main.gd` - 0.7 is still sharp enough to read the terminals.
3. No MSAA in the headset: `_on_session_started` can set `msaa_3d` off. The resolve is pure cost
   on a tiler drawing everything twice.
4. Blended layers: the window light shafts (`window_sun.gd`, drawn both sides), the dust
   (`Station._dust`), and the name plates and terminal labels (`Label3D`), which draw twice each
   when they have an outline.
5. Corridor lights: `Station._place_lights` puts one every two cells. Every three is dimmer and
   cheaper.
6. Draw only the rooms you can see: the layout knows which cells neighbour the one you are in, and
   everything else on the deck could be hidden.
