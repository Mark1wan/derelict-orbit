class_name CavePalette
extends RefCounted
## The materials Sowbelly is built from, keyed by the names sowbelly.json and cave.gd use.
## Ported from derelict-orbit's scripts/palette.gd: the same `plain` / `textured` / `triplanar`
## helpers, built once at start-up and shared, so a whole cave is a handful of materials and
## a handful of draw calls.
##
## Everything is swept along a centreline and comes out with a real cylindrical unwrap, so it
## all uses ordinary UVs - cheaper than triplanar, which costs three texture fetches per map and
## is a poor trade on a Quest. `triplanar` is kept below for geometry that has no unwrap.

var mats := {}

## Roughly how many texture tiles per metre each surface wants. Rock has no natural scale, so
## these were picked to keep a headlamp beam from finding a repeat at conversational distance.
const SCALE := {
	"rock": 0.42,
}

func _init() -> void:
	# One rock. Sowbelly is wet limestone from the shaft head to the far end of the Drainpipe -
	# walls, roof and floor - because that is what a cave water is still working on looks like,
	# and because a floor that announces itself with a different texture reads as a corridor.
	var wet := CaveTex.limestone(256, Color(0.34, 0.34, 0.35))
	var dry := CaveTex.limestone()

	# The wall of the whole cave. Darker than instinct says it should be, and cooler: this cave
	# is lit end to end by fill lights standing in for strung lamps, and rock that looks right
	# under one headlamp goes chalky under eleven of them. The shine is not here - it is in the
	# roughness map, low in the hollows and high on the ribs - so the multiplier is 1.0 and the
	# texture decides. A single roughness for the whole wall is what makes wet rock look like
	# wet plastic.
	mats["rock_wet"] = textured(wet, Color(0.40, 0.40, 0.42), SCALE["rock"], 1.0, 0.0, 1.0)

	# Dry bedded limestone. Nothing in Sowbelly asks for it; it is the fallback `get_mat`
	# returns for an unknown key, and the next cave may want somewhere that is not wet. The
	# roughness multiplier drags the same map up into the dry half of its range.
	mats["rock"] = textured(dry, Color(0.52, 0.50, 0.46), SCALE["rock"], 1.45, 0.0, 1.0)

	# Formations. The same rock as everything else - a stalactite is not a different substance
	# and white ones would put back exactly the bright lines this cave just lost - but it keeps
	# its own KEY on purpose: Cave._commit routes "flow" onto the decor body, and the clearance
	# test skips that body. Fold these into the wall material and every stalactite starts
	# failing the test as rock standing in the passage.
	mats["flow"] = textured(wet, Color(0.43, 0.43, 0.44), SCALE["rock"], 0.85, 0.0, 1.0)

	# Seams: the lip of rock where one passage's tube crosses another's end face. Those faces
	# have to stay - cutting them opens a hole to the void - but they belong to the tunnel and
	# so they face into it, which from the passage next door means looking at their backs.
	# Every other face in the cave is single-sided and that is correct; these are the handful
	# that would otherwise be solid and invisible, which is the one thing this cave is not
	# allowed to have. Drawn from both sides, a seam is a lip at the mouth, which is what it is.
	var seam := textured(wet, Color(0.40, 0.40, 0.42), SCALE["rock"], 1.0, 0.0, 1.0)
	seam.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["seam"] = seam

	# Rigging: rope, hangers, the survey station tags. Not rock, and meant to read instantly
	# as the only man-made thing in the beam.
	mats["rope"] = plain(Color(0.78, 0.66, 0.24), 0.85, 0.0)
	mats["steel"] = plain(Color(0.60, 0.62, 0.66), 0.42, 0.85)
	mats["tape"] = plain(Color(0.92, 0.30, 0.18), 0.80, 0.0)

## Unknown keys fall back to dry rock rather than crashing, but they say so: a cave asking for
## a material that no longer exists should be a line in the log, not a passage that quietly
## comes out the wrong colour.
func get_mat(key: String) -> Material:
	if not mats.has(key):
		push_warning("cave: no material '%s', falling back to rock" % key)
		return mats["rock"]
	return mats[key]

static func plain(albedo: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m

## World-space triplanar, for geometry with no authored UVs.
static func triplanar(m: StandardMaterial3D) -> StandardMaterial3D:
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * m.uv1_scale.x
	return m

## `rough` is a MULTIPLIER when the texture brings a roughness map of its own, and the flat
## roughness of the whole surface when it does not. Wet rock brings one: the shine belongs in
## the hollows where the water is, and a single number for the whole wall is the difference
## between limestone and wet plastic.
static func textured(tex: Dictionary, tint: Color, scale: float, rough: float, metal: float, normal_depth := 1.0) -> StandardMaterial3D:
	var m := plain(tint, rough, metal)
	m.albedo_texture = tex["albedo"]
	if normal_depth > 0.0:
		m.normal_enabled = true
		m.normal_texture = tex["normal"]
		m.normal_scale = normal_depth
	if tex.has("rough"):
		m.roughness_texture = tex["rough"]
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_scale = Vector3(scale, scale, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m
