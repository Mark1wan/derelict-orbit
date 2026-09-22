class_name Lamp
extends Node3D
## The headlamp, and the hand torch you keep as a spare.
##
## In derelict-orbit the flashlight is one more light in a corridor that already has a dozen.
## Here it is the only light in the world, and that changes everything about how it has to be
## built. The beam is not illumination, it is the interface: it is how you read the shape of a
## passage, how far away the wall is, whether that is mud or flowstone. So it gets a hot narrow
## centre for reading detail and a wide dim flood around it, because a single cone leaves you
## blind to everything just outside it and makes a cave unnavigable rather than dark.
##
## The shadow is the expensive part and the gate is derelict-orbit's, unchanged: desktop only,
## high graphics only. A Quest gets the same beam without the shadow map and it still reads,
## because in a cave almost everything the beam lands on is already facing away from something.

const MAIN_RANGE := 19.0
const MAIN_ANGLE := 15.0
const MAIN_ENERGY := 5.2
const FLOOD_RANGE := 9.0
const FLOOD_ANGLE := 48.0
const FLOOD_ENERGY := 0.85
const TORCH_RANGE := 13.0
const TORCH_ANGLE := 22.0
const WARM := Color(1.0, 0.94, 0.82)

var on := true
var backup_on := false

var main: SpotLight3D
var flood: SpotLight3D
var torch: SpotLight3D
var _dust: CPUParticles3D

func _ready() -> void:
	main = _spot(MAIN_ANGLE, MAIN_RANGE, MAIN_ENERGY, WARM)
	main.shadow_bias = 0.045
	main.shadow_normal_bias = 1.4
	add_child(main)

	flood = _spot(FLOOD_ANGLE, FLOOD_RANGE, FLOOD_ENERGY, Color(0.92, 0.94, 1.0))
	add_child(flood)

	torch = _spot(TORCH_ANGLE, TORCH_RANGE, 3.0, Color(0.96, 0.97, 1.0))
	torch.visible = false
	add_child(torch)

	_build_dust()

func _spot(angle: float, range_: float, energy: float, tint: Color) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.spot_angle = angle
	l.spot_range = range_
	l.spot_attenuation = 1.15
	l.light_energy = energy
	l.light_color = tint
	l.light_specular = 0.4
	l.shadow_enabled = false
	return l

## Motes in the beam. The single cheapest thing you can do to make a headlamp read as a beam
## rather than a brightness - lifted from derelict-orbit's station.gd:_dust(), with gravity
## switched back on so it drifts down instead of hanging.
func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.amount = 26
	_dust.lifetime = 9.0
	_dust.preprocess = 9.0          # already drifting on the first frame
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(1.6, 1.0, 2.2)
	_dust.direction = Vector3(0, -1, 0)
	_dust.spread = 30.0
	_dust.gravity = Vector3(0, -0.035, 0)
	_dust.initial_velocity_min = 0.01
	_dust.initial_velocity_max = 0.06
	var qm := QuadMesh.new()
	qm.size = Vector2(0.012, 0.012)
	_dust.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = Color(0.85, 0.82, 0.76, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_receive_shadows = true
	_dust.material_override = m
	_dust.position = Vector3(0, 0, -2.0)
	add_child(_dust)

func set_shadow_allowed(allowed: bool) -> void:
	main.shadow_enabled = allowed and on

func toggle_main() -> void:
	on = not on
	main.visible = on
	flood.visible = on
	_dust.emitting = on or backup_on
	Sfx.play("helmet", -26.0, 2.4)
	if not on:
		Cave.say("lamp off", 2.0)

func toggle_backup() -> void:
	backup_on = not backup_on
	torch.visible = backup_on
	_dust.emitting = on or backup_on

## Dim everything for a moment - used by the loading fade so the cave does not snap into
## existence at full brightness while the shaders are still warming up.
func set_scale_energy(f: float) -> void:
	main.light_energy = MAIN_ENERGY * f
	flood.light_energy = FLOOD_ENERGY * f
	torch.light_energy = 3.0 * f

## Is this point in the beam and unobstructed? Nothing in this build needs it yet, but it is
## the primitive every later system will want - a hazard that only triggers unlit, water you
## have to see before you step in it - and it is four tests in order of cost, the way
## derelict-orbit's stalker.gd:is_lit does it.
func lights(point: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	if not on:
		return false
	var from := main.global_position
	var v := point - from
	var dist := v.length()
	if dist > main.spot_range or dist < 0.01:
		return dist < 0.01
	var fwd := -main.global_transform.basis.z
	if rad_to_deg(acos(clampf(fwd.dot(v / dist), -1.0, 1.0))) > main.spot_angle * 0.95:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, point, 1)
	return space.intersect_ray(q).is_empty()
