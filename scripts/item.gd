class_name Item
extends Node3D
## Something a hand can carry: the flashlight and the three repair tools.
##
## An item is always in exactly one place - a hand, a belt holster, or loose in the station - and
## that place is its parent node. Loose items drift: zero-G keeps whatever velocity a hand let go
## with, a wall bounces them off, and a small amber locator glow keeps a tool findable in the dark.
##
## Every mesh is built here in code and gripped at the origin, pointing down -Z the way a
## controller does, so an item parented to a hand needs no offset.

enum Where { WORLD, HAND, BELT }

const FLASHLIGHT := "flashlight"
const WRENCH := "wrench"
const MULTITOOL := "multitool"
const SCANNER := "scanner"
## The repair tools, in the order the wrist lists them. Every task needs exactly one of these.
const TOOLS := [WRENCH, MULTITOOL, SCANNER]
## What the player carries from the start. The rest are waiting somewhere on the deck.
const STARTING := [FLASHLIGHT, WRENCH]
const LABEL := {FLASHLIGHT: "FLASHLIGHT", WRENCH: "WRENCH", MULTITOOL: "MULTITOOL", SCANNER: "SCANNER"}
const SHORT := {FLASHLIGHT: "LIGHT", WRENCH: "WRENCH", MULTITOOL: "MULTI", SCANNER: "SCAN"}
const GROUP := "loose_items"
const GRAB_REACH := 0.22       # a hand this close to a loose item can take it
const DRIFT_DAMP := 0.12       # zero-G: a let-go item keeps going for a long while
const MAX_THROW := 4.0

var kind := ""
var where: int = Where.WORLD
var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var light: SpotLight3D          # flashlight only
var _lens_mat: StandardMaterial3D
var _led_mat: StandardMaterial3D
var _led_idle := 1.4
var _beacon: OmniLight3D
var _t := 0.0

static func make(p_kind: String) -> Item:
	var it := Item.new()
	it.kind = p_kind
	it.name = p_kind.capitalize()
	match p_kind:
		FLASHLIGHT:
			it._build_flashlight()
		WRENCH:
			it._build_wrench()
		MULTITOOL:
			it._build_multitool()
		SCANNER:
			it._build_scanner()
	it._beacon = OmniLight3D.new()
	it._beacon.light_color = Color(1.0, 0.65, 0.2)
	it._beacon.light_energy = 0.35
	it._beacon.omni_range = 1.6
	it._beacon.shadow_enabled = false
	it._beacon.position = Vector3(0, 0.08, -0.05)
	it._beacon.visible = false
	it.add_child(it._beacon)
	return it

# ---------------------------------------------------------------- where it is
func set_where(w: int) -> void:
	where = w
	if w == Where.WORLD:
		add_to_group(GROUP)
	else:
		if is_in_group(GROUP):
			remove_from_group(GROUP)
		velocity = Vector3.ZERO
		spin = Vector3.ZERO
	if _beacon:
		_beacon.visible = w == Where.WORLD and kind != FLASHLIGHT

## Carried: into a hand or a belt holster, at a local transform there.
func attach_to(parent: Node3D, local: Transform3D, w: int) -> void:
	if get_parent():
		reparent(parent, false)
	else:
		parent.add_child(self)
	transform = local
	set_where(w)

## Let go into the station: it floats off at `vel`, turning slowly, until a hand catches it.
func release_into(parent: Node, vel: Vector3) -> void:
	if get_parent():
		reparent(parent, true)
	else:
		parent.add_child(self)
	set_where(Where.WORLD)
	velocity = vel.limit_length(MAX_THROW)
	spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.7

func grab_point() -> Vector3:
	return global_position

func set_light(on: bool) -> void:
	if light:
		light.visible = on
	if _lens_mat:
		_lens_mat.emission_enabled = on

## A tool is being used on something this frame: its indicator comes alive.
func working(delta: float) -> void:
	_t += delta
	if _led_mat:
		_led_mat.emission_energy_multiplier = 1.0 + 2.5 * absf(sin(_t * 22.0))

func _process(delta: float) -> void:
	if _led_mat and _led_mat.emission_energy_multiplier != _led_idle:
		_led_mat.emission_energy_multiplier = move_toward(_led_mat.emission_energy_multiplier, _led_idle, delta * 6.0)
	if where != Where.WORLD:
		return
	_t += delta
	var step := velocity * delta
	if step.length_squared() > 1e-8:
		var from := global_position
		var q := PhysicsRayQueryParameters3D.create(from, from + step + step.normalized() * 0.06, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit["normal"]
			velocity = velocity.bounce(n) * 0.35
			spin *= 0.5
			step = Vector3.ZERO
	global_position += step
	velocity = velocity.lerp(Vector3.ZERO, clampf(DRIFT_DAMP * delta, 0.0, 1.0))
	rotation += spin * delta
	spin = spin.lerp(Vector3.ZERO, clampf(0.2 * delta, 0.0, 1.0))
	global_position.y += sin(_t * 0.7) * 0.015 * delta
	if _beacon and _beacon.visible:
		_beacon.light_energy = 0.12 + 0.3 * (0.5 + 0.5 * sin(_t * 2.4))

# ---------------------------------------------------------------- models
func _build_flashlight() -> void:
	var body := _mat(Color(0.2, 0.21, 0.24), 0.45, 0.7)
	_cyl(0.021, 0.15, Vector3(0, 0, -0.03), body)
	_cyl(0.024, 0.05, Vector3(0, 0, 0.035), _mat(Color(0.07, 0.07, 0.08), 0.9, 0.0))    # rubber grip
	_cyl(0.03, 0.045, Vector3(0, 0, -0.125), body)                                      # head
	_box(Vector3(0.012, 0.012, 0.02), Vector3(0, 0.024, -0.02), _mat(Color(0.95, 0.75, 0.12), 0.6, 0.1))
	_lens_mat = _glow(Color(1, 0.95, 0.8), 3.0)
	_cyl(0.026, 0.006, Vector3(0, 0, -0.149), _lens_mat)
	light = SpotLight3D.new()
	light.name = "Beam"
	light.position = Vector3(0, 0, -0.16)
	light.light_color = Color(1.0, 0.94, 0.82)
	light.light_energy = 3.2
	light.spot_range = 16.0
	light.spot_angle = 23.0
	light.spot_attenuation = 1.1
	light.shadow_enabled = true
	light.shadow_bias = 0.06
	add_child(light)

## Open-ended spanner: steel shank, rubber grip, orange band so it reads in the dark.
func _build_wrench() -> void:
	var steel := _mat(Color(0.64, 0.67, 0.72), 0.35, 0.85)
	_box(Vector3(0.026, 0.012, 0.21), Vector3(0, 0, -0.04), steel)
	_box(Vector3(0.032, 0.02, 0.085), Vector3(0, 0, 0.03), _mat(Color(0.07, 0.07, 0.08), 0.9, 0.0))
	_box(Vector3(0.034, 0.022, 0.012), Vector3(0, 0, -0.02), _mat(Color(0.95, 0.45, 0.08), 0.6, 0.1))
	_box(Vector3(0.08, 0.014, 0.026), Vector3(0, 0, -0.155), steel)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.02, 0.014, 0.05), Vector3(sx * 0.03, 0, -0.19), steel)

## Circuit multitool: orange body, a readout, two probe tips.
func _build_multitool() -> void:
	var orange := _mat(Color(0.95, 0.45, 0.08), 0.55, 0.15)
	_cyl(0.019, 0.11, Vector3(0, 0, 0.02), _mat(Color(0.07, 0.07, 0.08), 0.9, 0.0))
	_box(Vector3(0.05, 0.042, 0.07), Vector3(0, 0, -0.07), orange)
	_box(Vector3(0.036, 0.004, 0.03), Vector3(0, 0.022, -0.075), _mat(Color(0.05, 0.05, 0.06), 0.3, 0.2))
	_led_mat = _glow(Color(0.2, 1.0, 0.4), 1.4)
	_box(Vector3(0.028, 0.003, 0.018), Vector3(0, 0.0245, -0.075), _led_mat)
	var steel := _mat(Color(0.7, 0.72, 0.75), 0.3, 0.9)
	for sx: float in [-1.0, 1.0]:
		_cyl(0.0035, 0.06, Vector3(sx * 0.013, 0, -0.135), steel)
	_box(Vector3(0.008, 0.008, 0.008), Vector3(0.013, 0, -0.166), _mat(Color(0.8, 0.1, 0.08), 0.5, 0.2))
	_box(Vector3(0.008, 0.008, 0.008), Vector3(-0.013, 0, -0.166), _mat(Color(0.1, 0.1, 0.1), 0.5, 0.2))

## Diagnostic scanner: a slate with a lit screen on a short handle.
func _build_scanner() -> void:
	_box(Vector3(0.03, 0.022, 0.07), Vector3(0, -0.004, 0.02), _mat(Color(0.07, 0.07, 0.08), 0.9, 0.0))
	_box(Vector3(0.085, 0.022, 0.12), Vector3(0, 0.006, -0.07), _mat(Color(0.82, 0.83, 0.85), 0.6, 0.1))
	_box(Vector3(0.089, 0.012, 0.124), Vector3(0, 0.0, -0.07), _mat(Color(0.2, 0.21, 0.24), 0.5, 0.5))
	_led_mat = _glow(Color(0.35, 0.9, 1.0), 1.4)
	_box(Vector3(0.066, 0.003, 0.085), Vector3(0, 0.018, -0.075), _led_mat)
	_cyl(0.004, 0.05, Vector3(0.03, 0.01, -0.15), _mat(Color(0.2, 0.21, 0.24), 0.5, 0.5))

static func _mat(c: Color, rough := 0.5, metal := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_led_idle = energy
	return m

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(bm, pos, Vector3.ZERO, mat)

## Cylinder lying along Z, the item's length axis.
func _cyl(r: float, length: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 12
	cm.rings = 1
	return _add(cm, pos, Vector3(PI * 0.5, 0, 0), mat)

func _add(mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
