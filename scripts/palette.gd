class_name Palette
extends RefCounted
## The station's materials, keyed by short names. The kit's flat glTF materials are remapped
## onto these (textured plating, grating, hazard stripes from StationTex), and the emissive
## ones are toggled by main power: `emissive` go dark at night, `emergency` light up.

var mats := {}
var retro := false
var emissive: Array[StandardMaterial3D] = []
var emergency: Array[StandardMaterial3D] = []
var mat_warn: StandardMaterial3D        # floor marker lights: amber by day, red in the dark

## glTF material name -> [group, tint]. Surfaces of one group merge into ONE mesh per chunk;
## the tint rides along as a vertex colour so a dozen flat materials cost a single draw call.
##   panel  textured plating with a normal map (tinted)     vc    flat metals, pipes, fabric...
##   floor  grating                                          lit   self-lit screens and lamps (dark at night)
##   hazard yellow/black stripes    warn  floor markers (amber by day, red at night)    glass
const KIT_GROUPS := {
	"Hull_Panel": ["panel", Color(0.78, 0.8, 0.84)], "Hull_Dark": ["panel", Color(0.5, 0.52, 0.56)],
	"Door_Panel": ["panel", Color(0.45, 0.47, 0.5)],
	"Hull_Light": ["vc", Color(0.66, 0.68, 0.72)], "Floor_Walk": ["vc", Color(0.2, 0.21, 0.24)],
	"Pipe_Steel": ["vc", Color(0.55, 0.58, 0.6)], "Pipe_Copper": ["vc", Color(0.5, 0.36, 0.26)],
	"Seal_Gasket": ["vc", Color(0.08, 0.08, 0.09)], "Seat_Fabric": ["vc", Color(0.25, 0.3, 0.4)],
	"Suit_Orange": ["vc", Color(0.9, 0.45, 0.1)], "Suit_White": ["vc", Color(0.85, 0.86, 0.88)],
	"Foliage": ["vc", Color(0.25, 0.55, 0.2)], "Mat_Rubber": ["vc", Color(0.1, 0.1, 0.11)],
	"Accent_Red": ["vc", Color(0.7, 0.12, 0.08)],
	"Floor_Grate": ["floor", Color(1, 1, 1)],
	"Accent_Warn": ["hazard", Color(1, 1, 1)],
	"Light_Strip": ["lit", Color(0.85, 0.92, 1.0)], "Screen_Lit": ["lit", Color(0.35, 0.9, 1.0)],
	"Light_Data": ["lit", Color(1.0, 0.7, 0.25)], "Light_Green": ["lit", Color(0.2, 1.0, 0.4)],
	"Light_Warn": ["warn", Color(1, 1, 1)],
	"Glass_Window": ["glass", Color(1, 1, 1)], "Glass_Port": ["glass", Color(1, 1, 1)],
}
const TEXTURED_GROUPS := {"panel": true, "floor": true, "hazard": true}   # need tangents for normal maps / UVs
## PS1 mode draws the whole static hull from one texture page (StationTex.atlas): which quarter a
## group lives in, and how many times its texture repeats per metre of wall. Merged geometry carries
## the quarter in UV2 and the repeat baked into UV, so four groups become one draw call per chunk.
const ATLAS_PAGE := {
	"panel": Vector2(0.0, 0.0), "floor": Vector2(0.5, 0.0),
	"hazard": Vector2(0.0, 0.5), "vc": Vector2(0.5, 0.5),
}
const ATLAS_UV := {"panel": 0.5, "floor": 1.0, "hazard": 2.0, "vc": 1.0}
const ATLAS_GROUP := "atlas"
const DEFAULT_GROUP := ["vc", Color(0.24, 0.26, 0.3)]

## glTF material name -> palette key (single-material lookups, e.g. props)
const KIT_MAP := {
	"Hull_Panel": "hull", "Hull_Light": "light_metal", "Hull_Dark": "dark",
	"Floor_Grate": "floor", "Floor_Walk": "walk",
	"Pipe_Steel": "pipe2", "Pipe_Copper": "pipe",
	"Accent_Warn": "hazard", "Accent_Red": "red_paint",
	"Light_Strip": "strip", "Light_Warn": "warn",
	"Screen_Lit": "screen", "Light_Data": "data", "Light_Green": "green",
	"Glass_Window": "glass", "Glass_Port": "glass",
	"Door_Panel": "frame", "Seal_Gasket": "gasket", "Seat_Fabric": "fabric",
	"Suit_Orange": "orange", "Suit_White": "white", "Foliage": "leaf", "Mat_Rubber": "rubber",
}
const NO_COLLIDE := {"lit": true, "warn": true, "hazard": true, "strip": true, "screen": true, "data": true, "green": true, "red_paint": true, "leaf": true}

func _init() -> void:
	# PS1 mode: half-size art, no normal maps (nothing reads one), and at the end of this every
	# surface that never changes is swapped for the Ps1 shader - see _retro_convert
	retro = Game.retro
	var size := 128 if retro else 256
	var panel := StationTex.panel(size, Color(0.62, 0.65, 0.70), not retro)
	var panel_dark := StationTex.panel(size, Color(0.40, 0.42, 0.46), not retro)
	var grate := StationTex.grate(64 if retro else 128, not retro)
	# merged groups (see KIT_GROUPS)
	var pm := textured(panel, Color(1, 1, 1), 0.5, 0.62, 0.35, 1.0)
	pm.vertex_color_use_as_albedo = true
	pm.vertex_color_is_srgb = true
	mats["panel"] = pm
	var vc := plain(Color(1, 1, 1), 0.55, 0.4)
	vc.vertex_color_use_as_albedo = true
	vc.vertex_color_is_srgb = true
	mats["vc"] = vc
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.vertex_color_use_as_albedo = true
	lit.vertex_color_is_srgb = true
	lit.albedo_color = Color(1, 1, 1)
	mats["lit"] = lit
	mats["hull"] = textured(panel, Color(0.78, 0.8, 0.84), 0.5, 0.62, 0.35, 1.0)
	mats["dark"] = textured(panel_dark, Color(0.62, 0.64, 0.68), 0.5, 0.7, 0.4, 0.8)
	mats["light_metal"] = plain(Color(0.66, 0.68, 0.72), 0.5, 0.6)
	mats["floor"] = textured(grate, Color(0.9, 0.9, 0.9), 1.0, 0.75, 0.5, 1.4)
	mats["walk"] = plain(Color(0.2, 0.21, 0.24), 0.9, 0.05)
	mats["frame"] = triplanar(textured(panel_dark, Color(0.45, 0.47, 0.5), 1.0, 0.5, 0.7, 0.0))
	mats["metal"] = plain(Color(0.24, 0.26, 0.3), 0.45, 0.8)
	mats["pipe"] = plain(Color(0.5, 0.36, 0.26), 0.35, 0.9)
	mats["pipe2"] = plain(Color(0.55, 0.58, 0.6), 0.6, 0.5)
	mats["gasket"] = plain(Color(0.08, 0.08, 0.09), 0.95, 0.0)
	mats["fabric"] = plain(Color(0.25, 0.3, 0.4), 0.95, 0.0)
	mats["orange"] = plain(Color(0.9, 0.45, 0.1), 0.8, 0.0)
	mats["white"] = plain(Color(0.85, 0.86, 0.88), 0.7, 0.0)
	mats["leaf"] = plain(Color(0.25, 0.55, 0.2), 0.9, 0.0)
	mats["rubber"] = plain(Color(0.1, 0.1, 0.11), 0.95, 0.0)
	mats["red_paint"] = plain(Color(0.7, 0.12, 0.08), 0.6, 0.1)
	mats["crate"] = triplanar(textured(panel_dark, Color(0.6, 0.55, 0.4), 1.5, 0.85, 0.1, 0.0))
	mats["ext"] = triplanar(textured(panel_dark, Color(0.35, 0.36, 0.4), 0.25, 0.8, 0.5, 0.0))
	mats["ext"].disable_fog = true
	mats["ext"].emission_enabled = true
	mats["ext"].emission = Color(0.16, 0.18, 0.22)
	mats["ext"].emission_energy_multiplier = 0.3
	var truss := plain(Color(0.5, 0.52, 0.56), 0.6, 0.6)
	truss.disable_fog = true
	truss.emission_enabled = true
	truss.emission = Color(0.22, 0.23, 0.26)
	truss.emission_energy_multiplier = 0.3
	mats["truss"] = truss
	var hazard := plain(Color(1, 1, 1), 0.8, 0.0)
	hazard.albedo_texture = StationTex.hazard()
	hazard.uv1_scale = Vector3(2.0, 2.0, 1.0)
	mats["hazard"] = hazard
	var solar := plain(Color(1, 1, 1), 0.3, 0.6)
	solar.albedo_texture = StationTex.solar()
	solar.uv1_triplanar = true
	solar.uv1_world_triplanar = true
	solar.uv1_scale = Vector3.ONE * 0.5
	solar.disable_fog = true
	solar.emission_enabled = true
	solar.emission_texture = StationTex.solar()
	solar.emission = Color(0.6, 0.65, 0.8)
	solar.emission_energy_multiplier = 0.2
	mats["solar"] = solar
	var glass := plain(Color(0.18, 0.28, 0.38, 0.1), 0.15, 0.1)
	glass.metallic_specular = 0.35
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["glass"] = glass
	mats["strip"] = emissive_mat(Color(0.8, 0.9, 1.0), 1.0)
	mats["screen"] = emissive_mat(Color(0.35, 0.9, 1.0), 0.9)
	mats["data"] = emissive_mat(Color(1.0, 0.7, 0.25), 0.9)
	mats["green"] = emissive_mat(Color(0.2, 1.0, 0.4), 0.9)
	mats["red"] = emissive_mat(Color(1.0, 0.12, 0.05), 3.5, true)
	mat_warn = emissive_mat(Color(1.0, 0.75, 0.2), 0.8)
	emissive.erase(mat_warn)          # handled by set_power: amber by day, red guide light at night
	mats["warn"] = mat_warn
	if retro:
		_retro_convert()
		# one material for every static surface of the hull: plating, grating, stripes, painted
		# metal. Kit.Merger routes those groups into ATLAS_GROUP and tags each vertex with its
		# quarter of the page.
		mats[ATLAS_GROUP] = Ps1.mat(Color(1, 1, 1), StationTex.atlas(128), 1.0, true,
			Color(0, 0, 0), 0.0, false, true, 1.2)

## PS1 mode. Every surface that never changes becomes one Ps1 shader material - vertex lighting,
## snapped vertices, affine textures - and the handful that do change (the emissive screens the
## power cuts, the amber floor markers, the glass) stay StandardMaterial3D so set_power below goes
## on driving them, just shaded per vertex instead of per pixel.
##
## Triplanar materials lose their texture rather than their mapping: they are triplanar because
## that geometry has no useful UVs, and three texture reads a pixel is exactly what this mode is
## for getting rid of. Flat painted metal is the period-correct answer anyway.
func _retro_convert() -> void:
	var live := {}                    # materials set_power drives: they stay standard
	for m in emissive:
		live[m] = true
	for m in emergency:
		live[m] = true
	live[mat_warn] = true
	live[mats["lit"]] = true          # set_power writes its albedo
	live[mats["glass"]] = true        # transparent: its own sorting and blending
	for key: String in mats:
		var m: Variant = mats[key]
		if m is StandardMaterial3D and not live.has(m):
			mats[key] = _to_retro(m)
		elif m is StandardMaterial3D:
			Ps1.cheapen(m)

func _to_retro(m: StandardMaterial3D) -> ShaderMaterial:
	var tex: Texture2D = null if m.uv1_triplanar else m.albedo_texture
	var energy := m.emission_energy_multiplier if m.emission_enabled else 0.0
	# a PS1 surface is flat diffuse and nothing else, so a metal loses the specular highlight that
	# was half of how bright it read. Hand it back as albedo, in proportion to how metallic it was.
	var gain := 1.0 + m.metallic * 0.5
	return Ps1.mat(m.albedo_color, tex, m.uv1_scale.x, m.vertex_color_use_as_albedo,
		m.emission, energy, m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, false, gain)

func get_mat(key: String) -> Material:
	return mats.get(key, mats["metal"])

static func plain(albedo: Color, rough := 0.7, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m

## World-space triplanar variant for geometry without authored UVs (props, exterior extras).
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

func emissive_mat(col: Color, energy := 2.0, is_emergency := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col * 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	if is_emergency:
		emergency.append(m)
		m.emission_enabled = false
	else:
		emissive.append(m)
	return m

func set_power(on: bool) -> void:
	mats["lit"].albedo_color = Color(1, 1, 1) if on else Color(0.05, 0.05, 0.06)
	for m in emissive:
		m.emission_enabled = on
	for m in emergency:
		m.emission_enabled = not on
	mat_warn.emission = Color(1.0, 0.75, 0.2) if on else Color(1.0, 0.1, 0.05)
	mat_warn.emission_energy_multiplier = 0.8 if on else 3.0
	mat_warn.albedo_color = mat_warn.emission * 0.3
