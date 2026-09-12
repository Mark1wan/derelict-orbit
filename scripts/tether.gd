class_name Tether
extends Node3D
## The EVA suit's tether: a line fired from the waist that latches onto an anchor on the hull
## (Exterior.anchors), then reels you in.
##
## Aim at an anchor within RANGE - a ring marks the one you would hit - and fire. Keep holding to
## reel in; let go and the line stays clipped on as a leash of whatever length it has reached, so
## you can swing round the anchor, thrust, grab things. Fire at another anchor to switch; fire at
## nothing to unclip. The line is drawn as a ribbon that floats slack when it is not pulled tight.

const RANGE := 16.0
const REEL := 3.4              # m/s the winch pulls you in
const MIN_LEN := 1.1
const AIM := 0.975             # cos of how far off the aim an anchor may be (about 13 degrees)
const SHOOT_TIME := 0.22

var latched := false
var anchor := Vector3.ZERO
var length := 0.0
var reeling := false
var target := -1               # the anchor the aim is on this frame
var _shoot := 0.0
var _im := ImmediateMesh.new()
var _line: MeshInstance3D
var _marker: MeshInstance3D
var _t := 0.0

func _init() -> void:
	name = "Tether"
	_line = MeshInstance3D.new()
	_line.mesh = _im
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.layers = 1 | Orbit.EXTERIOR_LAYER
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.72, 0.2)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line.material_override = m
	add_child(_line)
	_marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.26
	tm.outer_radius = 0.32
	tm.rings = 24
	tm.ring_segments = 4
	_marker.mesh = tm
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.3, 0.9, 1.0)
	mm.no_depth_test = true
	mm.render_priority = 30
	_marker.material_override = mm
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)

func _anchors() -> Array[Vector3]:
	var st := Game.station as Station
	if st == null or st.exterior == null:
		return []
	return st.exterior.anchors

## The anchor nearest the aim from `from` along `dir`, in range and in sight, or -1.
func find_target(from: Vector3, dir: Vector3) -> int:
	var list := _anchors()
	var cands := []
	for i in list.size():
		var v := list[i] - from
		var d := v.length()
		if d > RANGE or d < 0.6:
			continue
		var dot := dir.dot(v / d)
		if dot > AIM:
			cands.append([dot, i])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for k in mini(4, cands.size()):
		var i: int = cands[k][1]
		if _clear(from, list[i]):
			return i
	return -1

func _clear(a: Vector3, b: Vector3) -> bool:
	var d := a.distance_to(b)
	var dir := (b - a) / d
	var q := PhysicsRayQueryParameters3D.create(a + dir * 0.2, b - dir * 0.4, 1)
	var world := get_world_3d()
	return world == null or world.direct_space_state.intersect_ray(q).is_empty()

## Fire along `dir` from `from` (the waist): latch onto the anchor there. False if there is none.
func fire(from: Vector3, dir: Vector3) -> bool:
	var i := find_target(from, dir)
	if i < 0:
		return false
	latched = true
	anchor = _anchors()[i]
	length = from.distance_to(anchor)
	_shoot = SHOOT_TIME
	Sfx.play("beep", -12.0, 1.8)
	Sfx.play_at("bang", anchor, -20.0, 20.0, 2.4)
	return true

func release() -> void:
	if latched:
		Sfx.play("beep", -18.0, 0.8)
	latched = false
	reeling = false

## Physics: the winch and the leash act on the player's velocity. `waist` is where the line leaves.
func apply(player: Player, waist: Vector3, delta: float) -> void:
	_shoot = maxf(0.0, _shoot - delta)
	if not latched:
		return
	var to := anchor - waist
	var d := to.length()
	if d < 0.001:
		return
	var n := to / d
	if reeling and _shoot <= 0.0:
		length = maxf(MIN_LEN, minf(length, d) - REEL * delta)
		if d > MIN_LEN + 0.25:
			var toward := player.velocity.dot(n)
			if toward < REEL:
				player.velocity += n * (REEL - toward) * clampf(6.0 * delta, 0.0, 1.0)
		else:
			player.velocity = player.velocity.lerp(Vector3.ZERO, clampf(8.0 * delta, 0.0, 1.0))
	if d > length + 0.02:
		var away := -player.velocity.dot(n)
		if away > 0.0:
			player.velocity += n * away
		player.velocity += n * clampf((d - length) * 4.0, 0.0, 3.0)

## Per frame: draw the line, and the ring on whatever anchor the aim is on (when `aim` is true).
func draw(waist: Vector3, eye: Vector3, aim_from: Vector3, aim_dir: Vector3, aim: bool) -> void:
	_t += get_process_delta_time()
	target = find_target(aim_from, aim_dir) if aim else -1
	_marker.visible = target >= 0
	if target >= 0:
		var p: Vector3 = _anchors()[target]
		var up := Vector3.UP if absf((eye - p).normalized().y) < 0.95 else Vector3.RIGHT
		_marker.global_transform = Transform3D(Basis.looking_at(eye - p, up) * Basis(Vector3.RIGHT, PI * 0.5), p)
	_im.clear_surfaces()
	if not latched:
		return
	var tip := waist.lerp(anchor, 1.0 - _shoot / SHOOT_TIME)
	var d := waist.distance_to(tip)
	var slack := clampf((length - waist.distance_to(anchor)) * 0.3, 0.0, 1.0) if _shoot <= 0.0 else 0.0
	var along := (tip - waist) / maxf(d, 0.001)
	var side := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var steps := 16
	for s in steps + 1:
		var t := float(s) / steps
		var p := waist.lerp(tip, t) + side * slack * sin(PI * t) * (1.0 + 0.2 * sin(_t * 1.3 + t * 5.0))
		var w := (p - eye).cross(along).normalized() * 0.012
		_im.surface_add_vertex(p - w)
		_im.surface_add_vertex(p + w)
	_im.surface_end()
