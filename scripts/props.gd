class_name StationProps
extends RefCounted
## Loose set dressing: the things drifting loose in the corridors and rooms (res://kit/props).
##
## These are the same glTF pipeline as the corridor kit, so Kit's loader and cache handle them
## unchanged - a prop is just a piece whose name is "props/<name>". The difference is the
## origin: kit modules sit with their floor at y = 0, but a prop is centred on its own origin
## because in zero-G that origin is what it tumbles about.
##
## Props are NOT merged into the hull batches - each one is its own MeshInstance3D so it can
## spin and be shoved (see Station.shove_props). That costs one draw call per material per
## prop, which is why a deck places about a dozen of them, not a hundred.

## Corridor clutter: bigger, cargo-ish, the stuff that breaks loose from a stack.
const CORRIDOR := [
	"prop_crate", "prop_crate_long", "prop_canister",
	"prop_stowage_bag", "prop_cable_coil", "prop_debris_panel",
]
## Things the crew left in a room and never came back for.
const ROOM := [
	"prop_toolbox", "prop_datapad", "prop_helmet",
	"prop_extinguisher", "prop_oxygen_pack", "prop_crate",
]

## Build one prop, with the kit's flat glTF materials swapped for the station's real ones.
static func make(name: String, pal: Palette) -> MeshInstance3D:
	var piece := "props/" + name
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.mesh(piece)
	mi.name = name
	var names := Kit.material_names(piece)
	for s in names.size():
		mi.set_surface_override_material(s, pal.get_mat(Palette.KIT_MAP.get(names[s], "metal")))
	return mi
