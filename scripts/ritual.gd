extends Node3D
class_name Ritual
## The candlelit room.
##
## Night only, and only with the station's main power dead - which is every night. One room on the
## deck has light in it: warm, low, moving, coming out of a doorway a long way down a corridor
## where nothing has been warm for hours. That is the whole hook. You do not have to go and look.
##
## Inside: a circle marked on the deck with glyphs round its rim, nine candles standing on it, and
## somebody sitting in the middle of it with their legs folded, their back straight, their head
## bowed and both arms up. They are not a person - they are the same smoke everything else in this
## suite is made of - and they do not react to you at all.
##
## Cross the doorway and it stops. Not gutters, not fades: **stops**, all of it at once, the
## candles and the marks and whoever was sitting there, and the room is a dark room with nothing
## in it. There is no evidence afterwards and there is nothing to interact with. It is the only
## apparition here that never once acknowledges that you exist.

const RIG := "res://kit/apparition_ritual.json"
const RADIUS := 1.15            # the circle, and where the candles stand
const TRIGGER := 3.4            # how close you get before it stops
const SNUFF := 0.22             # how long "at once" actually takes

signal snuffed

var body: Apparition
var _glyphs: MeshInstance3D
var _candles: MeshInstance3D
var _light: OmniLight3D
var _glyph_mat: StandardMaterial3D
var _wax_mat: StandardMaterial3D
var _t := 0.0
var _done := false

func _ready() -> void:
	_build_circle()
	body = Apparition.new()
	body.rig_path = RIG
	add_child(body)
	body.gather(2.2)            # it was already going before you got here

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.28)
	_light.light_energy = 1.5
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.35, 0)
	add_child(_light)

## The circle: a ring cut into the deck plating, glyphs round its rim, and nine candle stubs.
## Built here rather than in the rig because these are marks on a surface, not smoke.
func _build_circle() -> void:
	_glyph_mat = StandardMaterial3D.new()
	_glyph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glyph_mat.albedo_color = Color(0.85, 0.42, 0.14)
	_glyph_mat.emission_enabled = true
	_glyph_mat.emission = Color(1.0, 0.45, 0.12)
	_glyph_mat.emission_energy_multiplier = 1.6

	_wax_mat = StandardMaterial3D.new()
	_wax_mat.albedo_color = Color(0.34, 0.31, 0.26)
	_wax_mat.roughness = 0.9

	var g := Geo.new()
	var segments := 72
	for i in segments:
		# the ring itself, drawn as short arcs so it reads as scored rather than printed
		if i % 3 == 2:
			continue
		var a := i * TAU / segments
		var p := Vector3(cos(a) * RADIUS, 0.005, sin(a) * RADIUS)
		g.box(p, Vector3(0.075, 0.004, 0.075))
	# glyphs: twelve marks round the rim, each a stroke with bars across it, none of them repeated
	var rng := RandomNumberGenerator.new()
	rng.seed = 990417
	for i in 12:
		var a := i * TAU / 12.0
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var base := out * (RADIUS + 0.30)
		g.box(base + Vector3(0, 0.005, 0), out * 0.26 + Vector3(0, 0.004, 0) + side * 0.022)
		for k in rng.randi_range(2, 3):
			var t := -0.09 + k * 0.075
			g.box(base + out * t + Vector3(0, 0.005, 0),
				out * 0.020 + Vector3(0, 0.004, 0) + side * rng.randf_range(0.09, 0.17))
	_glyphs = g.commit(_glyph_mat, self, null, "glyphs")

	var wax := Geo.new()
	for i in 9:
		var a := i * TAU / 9.0
		var p := Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)
		wax.box(p + Vector3(0, 0.06, 0), Vector3(0.055, 0.12, 0.055))
	_candles = wax.commit(_wax_mat, self, null, "candles")

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	# candle light is never steady: two rates, so it never settles into a pulse
	_light.light_energy = 1.35 + 0.30 * sin(_t * 5.7) * sin(_t * 1.9) + 0.08 * sin(_t * 11.3)
	_glyph_mat.emission_energy_multiplier = 1.45 + 0.35 * sin(_t * 3.1 + 1.0)
	if Game.player == null:
		return
	if Game.player.camera.global_position.distance_to(global_position) < TRIGGER:
		snuff()

## All of it at once. No gutter, no fade, no smoke afterwards - and nothing left to find.
func snuff() -> void:
	if _done:
		return
	_done = true
	snuffed.emit()
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 0.0, SNUFF)
	tw.parallel().tween_property(_glyph_mat, "emission_energy_multiplier", 0.0, SNUFF * 0.7)
	tw.parallel().tween_property(_glyph_mat, "albedo_color", Color(0, 0, 0, 1), SNUFF * 0.7)
	tw.parallel().tween_property(body, "form", 0.0, SNUFF)
	tw.parallel().tween_property(body, "ember_energy", 0.0, SNUFF * 0.5)
	tw.tween_callback(queue_free)
	Sfx.play_at("powerdown", global_position, -14.0, 22.0, 2.2)
