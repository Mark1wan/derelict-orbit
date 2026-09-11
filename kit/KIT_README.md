# Space Station Interior Kit

A modular, procedurally generated station interior in industrial "used future"
styling — nine corridor modules and eight fitted-out rooms — authored for Godot 4 and
supplied as glTF 2.0 plus a Blender rebuild script.

## Grid and dimensions

Every module occupies a **4.0 m × 4.0 m** footprint and is centred on the origin,
with the **floor surface at y = 0** and ceiling underside at y = 3.0 m. The interior
is 3.0 m wide; walls occupy the outer 0.5 m on each side. Pieces therefore snap
together on a 4 m grid with no offset fiddling — place them at multiples of 4 on X
and Z and the bulkhead frames line up.

Scale is 1 unit = 1 metre, matching Godot's default. Authored Y-up, so no rotation
correction is needed on import.

## The pieces

| File | Tris | Open sides | Notes |
|---|---|---|---|
| `corridor_straight.glb` | 1440 | −Z, +Z | |
| `corridor_door.glb` | 1632 | −Z, +Z | closed pressure door at centre |
| `corridor_corner.glb` | 1428 | −Z, +X | 90° turn |
| `corridor_tjunction.glb` | 1080 | −Z, +Z, +X | |
| `corridor_cross.glb` | 732 | all four | |
| `corridor_endcap.glb` | 1992 | −Z only | dead end with terminal console |
| `corridor_window.glb` | 1480 | −Z, +Z | viewport on the +X wall |
| `corridor_window_double.glb` | 1520 | −Z, +Z | viewports on both side walls |
| `corridor_observation.glb` | 1896 | −Z only | bay glazed on three sides |

Rotate corner, T-junction, end cap and the window pieces in 90° steps to face any
direction. The corridor set is roughly 13,200 triangles; with the eight rooms the whole
kit is about 54,000, so an entire deck costs very little.

## The rooms

Rooms are **12 × 12 m** — a 3 × 3 block of the same grid — so a room's centre still
lands on a cell centre and its doorway lines up exactly with the centre line of the
adjoining corridor cell. Interior is 11 × 11 m with the ceiling at **3.6 m**, taller
than the corridors; the doorway aperture stays 3.0 m so a corridor section butts
straight on with a header above it.

**Placement rule:** a room centred at (cx, cz) spans ±6 m, so the corridor cell that
connects to it sits **8 m** away on that axis. A room at (0, 0) meets a corridor cell
centred at (0, −8) through its −Z doorway. Each room has a single doorway on its −Z
wall; rotate in 90° steps to face it wherever you need.

| File | Tris | Contents |
|---|---|---|
| `room_control.glb` | 6096 | arc of five console bays with lit screens and chairs, main wall display, side equipment racks, gallery rail |
| `room_power.glb` | 4908 | three capacitor towers with glow bands and guard rails, breaker cabinets, cable trunking, overhead bus runs |
| `room_plant.glb` | 5288 | two pressure vessels on saddles, pump sets, valved pipe manifold, air-handling unit with fan and ceiling duct |
| `room_laboratory.glb` | 4656 | benches with under-counter cabinets, fume hood with glass sash, sealed glovebox, sample shelving, emergency shower |
| `room_observation.glb` | 3496 | glazed on three sides, tiered seating facing the main viewport, tables and chairs, planters |
| `room_exercise.glb` | 3580 | two treadmills with lit consoles, resistance machine with weight stack, exercise bike, mat area, free weights, lockers, mirror |
| `room_server.glb` | 8252 | two rack rows flanking a cold aisle, LED-lit rack fronts, overhead cable trays, cooling unit, operator station |
| `room_eva.glb` | 4652 | circular airlock hatch with locking wheel, six suit alcoves with suits, tool bench, charging docks, hoist rail, floor hazard marking |

Every room keeps the area in front of its doorway clear, so nothing blocks you walking
in from the corridor, and circulation rails are split rather than run wall to wall.

## The loose props

`kit/prop_*.glb` — the small objects that drift through the deck: the things you bump into,
grab to pull yourself along, and that get shoved around when the haunting escalates. Each one
is centred on X/Z with its base at **y = 0**, fits inside a 1 m box (so it clears a 3 m corridor
at any tumble angle) and reuses the same material names as the modules, so a palette remap
applied to the kit covers the props too.

| File | Tris | Notes |
|---|---|---|
| `prop_crate.glb` | 240 | ribbed supply crate, corner cage, hazard edge |
| `prop_crate_large.glb` | 240 | pallet-sized box with a lid seam and catches |
| `prop_canister.glb` | 500 | pressure cylinder, valve under a collar cage |
| `prop_drum.glb` | 260 | fluid drum with rolling hoops and bung caps |
| `prop_toolbox.glb` | 96 | hinged case, carry handle, charge LED |
| `prop_medkit.glb` | 108 | first aid pack, red cross panel, status light |
| `prop_extinguisher.glb` | 344 | fire bottle, squeeze handle, hose |
| `prop_power_cell.glb` | 156 | finned battery pack with charge LEDs |
| `prop_helmet.glb` | 532 | EVA helmet, tinted visor, neck ring, lamp |
| `prop_slate.glb` | 72 | crew tablet with a lit screen |
| `prop_ration.glb` | 60 | sealed food pouch |
| `prop_debris.glb` | 120 | torn-off hull panel, bent ribs, cut cable |
| `prop_handhold.glb` | 132 | grab bar knocked off a wall |

About 2,900 triangles for the set. `scripts/station.gd` scatters them per room type (canisters and
drums in life support, power cells in the plant and the server room, helmets in the EVA airlock)
and gives each one a box collider, so a prop is also something you can grab and pull off.

They are built by `tools/build_props.py`, which is self-contained — pure Python, no Blender and no
third-party modules:

    python3 tools/build_props.py --check   # rewrites kit/prop_*.glb and re-parses each one

`tools/proplib.py` holds the glTF writer, the material palette and the primitives (box, cylinder,
sphere, corner frame). Adding a prop is a function plus one line in `PROPS`; the builder checks
every piece rests on y = 0 and stays under a metre before it writes anything.


## The window pieces

Each viewport is a genuine aperture cut through the hull — the slab is laid as four
pieces around the opening rather than punched out of one, since the generator is
additive and has no boolean operations. Each one carries a recessed reveal, a
perimeter gasket, mullions dividing the panes, an inner frame with bolt heads, a
blast-shutter housing with guide rails above, a hazard line under the sill and a
handrail across the glazing.

`corridor_window` glazes the +X wall only, so a run of them puts windows down one side
of a corridor; rotate 180° to face the other way. `corridor_window_double` glazes both
side walls. `corridor_observation` is a dead-end bay glazed on three sides with a
taller, wider aperture on the end wall (2.6 m × 1.72 m, single central mullion) — that
is the piece to point at a planet.

**The view is yours to supply.** The glazing is transparent geometry; what you see
through it is whatever your Godot `WorldEnvironment` sky shows. If you want Earth out
there, that is a panorama sky texture or a large textured sphere in your scene, not
part of this kit. The planet in the preview images is scenery generated by the preview
renderer purely so the apertures could be checked against something — it is deliberately
not exported.

Glazing uses the `Glass_Window` material with `alphaMode: BLEND` and base colour alpha
0.14, double-sided. Godot imports this as a transparent material. Two things worth
knowing: transparent surfaces do not write depth, so if you stack several window
modules in a line you may see sorting artefacts through them — setting the material's
Transparency to *Alpha Pre-Pass* (or Depth Draw Opaque) in Godot fixes it. And if you
want the windows to actually let light in, that is a light placed outside plus
`WorldEnvironment` ambient, not the glass material.

## Godot 4 import

Drop the `.glb` files into your project — the default import settings are correct.
A few things worth knowing:

**Collision.** No collision is baked in, deliberately. The quickest route is to
select the imported scene, then in the Import dock set the mesh's physics or, in the
instanced scene, use *Mesh → Create Trimesh Static Body*. If you would rather have it
generated automatically on import, open `blender_build_kit.py`'s output in Blender and
rename the mesh to `corridor_straight-col` — Godot's glTF importer reads the `-col`
suffix and builds a concave static body alongside the visible mesh.

**GridMap.** Because everything sits on a uniform 4 m cell with the floor at y = 0,
these pieces go straight into a MeshLibrary: create a scene containing the imported
meshes, add collision, then *Scene → Export As → MeshLibrary*. Set the GridMap cell
size to 4, 4, 4 with the Y offset left at 0.

**Emissive materials.** `Light_Strip` and `Light_Warn` carry emission via the
`KHR_materials_emissive_strength` extension, which Godot 4 honours. They will look
flat until you add a `WorldEnvironment` with Glow enabled — that is what makes the
ceiling lamps and floor markers read as light sources rather than white paint. The
emissive geometry does not illuminate anything on its own; add real lights, or bake
with LightmapGI, if you want the corridor lit by its own strips.

**Materials.** Fourteen flat PBR materials, no textures. UVs are box-projected in world
space at a consistent texel density, so tiling metal, grate and panel textures can be
dropped on without re-unwrapping. Material names (`Hull_Panel`, `Hull_Dark`,
`Floor_Grate`, `Pipe_Steel`, `Accent_Warn`, …) are stable across all six files, so a
material override applied once propagates across the whole kit.

## Rebuilding in Blender

`blender_build_kit.py` reconstructs the identical kit as editable Blender objects with
Principled BSDF materials — one collection per module, each joined into a single mesh.

    Blender → Scripting tab → Open → blender_build_kit.py → Run Script

`kit_ops.json` must sit in the same folder; it holds the primitive operations the kit
is built from. Or headless:

    blender --background --python blender_build_kit.py -- --save corridor_kit.blend

Pieces are spread along X for viewing, but that is an *object-level* offset only — the
mesh data is origin-centred, so Alt+G on any piece returns it to the origin ready for
export. Set `LAYOUT_SPACING = 0.0` at the top of the script to build them all at the
origin instead.

**Caveat worth stating plainly:** this script was written without a Blender available
to run it against, so while its syntax is checked and the geometry data it consumes is
verified, the Blender API calls themselves are untested. The `.glb` files are the
verified artefact — those were re-parsed and validated independently.

## Regenerating or modifying the geometry

The kit is parametric. `build_kit.py` holds the design: cell size, interior dimensions
and each module's construction, assembled from primitives in `kitlib.py`.

    python3 build_all.py       # writes out/*.glb and out/kit_ops.json
    python3 validate_glb.py    # re-parses every .glb and checks it
    python3 render.py          # preview + cutaway plan renders

`build_all.py` is the entry point and holds the registry of every module.
`build_kit.py` holds the corridor geometry, `build_rooms.py` the room shell and the
eight fit-outs, `kitlib.py` the primitives, material palette and glTF writer.

Useful levers near the top of `build_kit.py`: `CELL` (grid spacing), `HW` (interior
half-width), `H` (interior height). The `wall()` function controls all panelling, rib
spacing, pipe runs and the light strip; `floor()` and `ceiling()` take a layout mode so
straight runs get a directional walkway and lamp channel while junctions get a hub
treatment. Adding a module is a one-line entry in `MODULES` naming which sides are open.

`window_wall()` takes `ap_w`, `sill`, `head` and `mullions`, so aperture size, height
and pane count are all adjustable per module — see the `BAY` dict for how the
observation bay overrides them. A module gets glazing by naming the side in its
`windows` dict instead of letting it fall through to a plain wall.

`render.py` is a small software rasteriser written because the sandbox had no Blender
or OpenGL — it is a verification tool, not a renderer you should judge the assets by.
Real materials and lighting will look considerably better.
