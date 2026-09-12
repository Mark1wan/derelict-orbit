class_name Palette
extends RefCounted
## The station's materials, keyed by short names. The kit's flat glTF materials are remapped
## onto these (textured plating, grating, hazard stripes from StationTex), and the emissive
## ones are toggled by main power: `emissive` go dark at night, `emergency` light up.

var mats := {}
var emissive: Array[StandardMaterial3D] = []
var emergency: Array[StandardMaterial3D] = []
var mat_warn: StandardMaterial3D        # floor marker lights: amber by day, red in the dark

## glTF material name -> palette key
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
const NO_COLLIDE := {"strip": true, "warn": true, "screen": true, "data": true, "green": true, "hazard": true, "red_paint": true, "leaf": true}

func _init() -> void:
	var panel := StationTex.panel(256, Color(0.62, 0.65, 0.70))
	var panel_dark := StationTex.panel(256, Color(0.40, 0.42, 0.46))
	var grate := StationTex.grate(128)
	mats["hull"] = textured(panel, Color(0.78, 0.8, 0.84), 0.5, 0.62, 0.35, 1.0)
	mats["dark"] = textured(panel_dark, Color(0.62, 0.64, 0.68), 0.5, 0.7, 0.4, 0.8)
	mats["light_metal"] = plain(Color(0.66, 0.68, 0.72), 0.5, 0.6)
	mats["floor"] = textured(grate, Color(0.9, 0.9, 0.9), 1.0, 0.75, 0.5, 1.4)
	mats["walk"] = plain(Color(0.2, 0.21, 0.24), 0.9, 0.05)
	mats["frame"] = textured(panel_dark, Color(0.45, 0.47, 0.5), 1.0, 0.5, 0.7, 0.6)
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
	mats["crate"] = textured(panel_dark, Color(0.6, 0.55, 0.4), 1.5, 0.85, 0.1, 0.8)
	mats["ext"] = textured(panel_dark, Color(0.35, 0.36, 0.4), 0.25, 0.8, 0.5, 0.5)
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
	hazard.uv1_triplanar = true
	hazard.uv1_world_triplanar = true
	hazard.uv1_scale = Vector3.ONE * 2.0
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

func get_mat(key: String) -> Material:
	return mats.get(key, mats["metal"])

static func plain(albedo: Color, rough := 0.7, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m

static func textured(tex: Dictionary, tint: Color, scale: float, rough: float, metal: float, normal_depth := 1.0) -> StandardMaterial3D:
	var m := plain(tint, rough, metal)
	m.albedo_texture = tex["albedo"]
	m.normal_enabled = true
	m.normal_texture = tex["normal"]
	m.normal_scale = normal_depth
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
	for m in emissive:
		m.emission_enabled = on
	for m in emergency:
		m.emission_enabled = not on
	mat_warn.emission = Color(1.0, 0.75, 0.2) if on else Color(1.0, 0.1, 0.05)
	mat_warn.emission_energy_multiplier = 0.8 if on else 3.0
	mat_warn.albedo_color = mat_warn.emission * 0.3
