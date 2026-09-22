class_name CavePalette
extends RefCounted
## The materials Sowbelly is built from, keyed by the names sowbelly.json and cave.gd use.
## Ported from derelict-orbit's scripts/palette.gd: the same `plain` / `textured` / `triplanar`
## helpers, built once at start-up and shared, so a whole cave is a handful of materials and
## a handful of draw calls.
##
## Two mapping strategies. Passages are swept along a centreline and come out with a real
## cylindrical unwrap, so they use ordinary UVs - cheaper than triplanar, which costs three
## texture fetches per map and is a poor trade on a Quest. Loose rock has no sensible unwrap,
## so that gets world triplanar.

var mats := {}

## Roughly how many texture tiles per metre each surface wants. Rock has no natural scale, so
## these were picked to keep a headlamp beam from finding a repeat at conversational distance.
const SCALE := {
	"rock": 0.55,
	"mud": 0.75,
	"flow": 0.85,
	"rubble": 0.45,
}

func _init() -> void:
	var lime := CaveTex.limestone()
	var wet_lime := CaveTex.limestone(256, Color(0.40, 0.40, 0.39))
	var clay := CaveTex.mud()
	var flow := CaveTex.flowstone()
	var rubble := CaveTex.breakdown()

	# Dry limestone wall. Rough, unreflective, and darker than instinct says it should be:
	# a beam on pale rock at 2 m is already bright, and anything lighter blows out.
	mats["rock"] = textured(lime, Color(0.58, 0.56, 0.52), SCALE["rock"], 0.92, 0.0, 1.5)

	# The same rock where water runs over it. Darker, glossier, and it catches the beam.
	mats["rock_wet"] = textured(wet_lime, Color(0.44, 0.44, 0.45), SCALE["rock"], 0.46, 0.0, 1.6)

	# Clay floor. Nearly flat under light, which is exactly what it looks like.
	mats["mud"] = textured(clay, Color(0.62, 0.56, 0.48), SCALE["mud"], 0.88, 0.0, 0.9)

	# Flowstone carries its own roughness map so only the drip lines look wet.
	var f := textured(flow, Color(0.95, 0.92, 0.86), SCALE["flow"], 0.55, 0.0, 1.2)
	f.roughness_texture = flow["rough"]
	f.roughness = 1.0
	mats["flow"] = f

	# Breakdown: the floor of a room whose ceiling has been coming down for a while.
	mats["rubble"] = triplanar(textured(rubble, Color(0.52, 0.50, 0.47), SCALE["rubble"], 0.95, 0.0, 1.6))

	# Loose rock and anything else with no sensible unwrap.
	mats["rock_tri"] = triplanar(textured(lime, Color(0.58, 0.56, 0.52), SCALE["rock"], 0.92, 0.0, 1.5))

	# Seams: the lip of rock where one passage's tube crosses another's end face. Those faces
	# have to stay - cutting them opens a hole to the void - but they belong to the tunnel and
	# so they face into it, which from the room next door means looking at their backs. Every
	# other face in the cave is single-sided and that is correct; these are the handful that
	# would otherwise be solid and invisible, which is the one thing this cave is not allowed
	# to have. Drawn from both sides, a seam is just a lip at the mouth, which is what it is.
	var seam := textured(lime, Color(0.55, 0.53, 0.49), SCALE["rock"], 0.93, 0.0, 1.5)
	seam.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["seam"] = seam

	# Rigging: rope, hangers, the survey station tags. Not rock, and meant to read instantly
	# as the only man-made thing in the beam.
	mats["rope"] = plain(Color(0.78, 0.66, 0.24), 0.85, 0.0)
	mats["steel"] = plain(Color(0.60, 0.62, 0.66), 0.42, 0.85)
	mats["tape"] = plain(Color(0.92, 0.30, 0.18), 0.80, 0.0)

func get_mat(key: String) -> Material:
	return mats.get(key, mats["rock"])

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

static func textured(tex: Dictionary, tint: Color, scale: float, rough: float, metal: float, normal_depth := 1.0) -> StandardMaterial3D:
	var m := plain(tint, rough, metal)
	m.albedo_texture = tex["albedo"]
	if normal_depth > 0.0:
		m.normal_enabled = true
		m.normal_texture = tex["normal"]
		m.normal_scale = normal_depth
	m.uv1_scale = Vector3(scale, scale, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m
