class_name Airlock
extends Node3D
## The decompression chamber bolted onto the back of the EVA airlock room.
##
## The kit's EVA room has its hatch painted on a solid wall; Kit.part(..., hatch) cuts the hole and
## this builds what is behind it, in the room's own frame (so a rolled room rolls its airlock too):
## a short octagonal chamber from the room's back wall (z = 6) to an outer hatch at z = 10, with a
## shutter door at each end, handrails, a lamp, and the CYCLE AIRLOCK panel on its wall.
##
##   PRESSURIZED     inner shutter open to the room, outer sealed
##   DEPRESSURIZING  both sealed, the air hissing out - you need a suit on to start it
##   VACUUM          inner sealed, outer open to space
##   REPRESSURIZING  both sealed, the air coming back
##
## Hold USE / trigger on the panel from inside the chamber to cycle it. Reaching VACUUM and getting
## back to PRESSURIZED are steps of the spacewalk (Game.EVA_STEPS); the Game decides whether they
## count.

enum State { PRESSURIZED, DEPRESSURIZING, VACUUM, REPRESSURIZING }

const AXIS_Y := 1.75            # the chamber's axis runs out of the hatch at this height
const Z_FRAME := 5.37           # back of the hatch frame in the room wall
const Z_WALL := 6.0             # outer face of the room's back wall
const Z_OUT := 10.0             # the outer hatch
const APOTHEM := 2.05           # chamber interior
const SKIN := 2.2               # chamber exterior
const OPENING := 1.3            # outer hatch opening
const CYCLE_TIME := 6.0
const DOOR_SPEED := 0.9

var state: int = State.PRESSURIZED
var panel: Interactable
var readout: Label3D
var pressure := 1.0
var _pal: Palette
var _body: StaticBody3D
var _inner: Node3D
var _outer: Node3D
var _inner_shape: CollisionShape3D
var _outer_shape: CollisionShape3D
var _inner_open := 1.0
var _outer_open := 0.0
var _cycle := 0.0
var _hiss := 0.0
var _text_t := 0.0
var _lamp: OmniLight3D
var _alarm: OmniLight3D
var _lamp_mat: StandardMaterial3D
var _vent: CPUParticles3D

func build(station: Station, xf: Transform3D) -> void:
	name = "Airlock"
	_pal = station.pal
	transform = xf
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	var axis := Vector3(0, 0, 1)
	var c0 := Vector3(0, AXIS_Y, Z_WALL)
	var c1 := Vector3(0, AXIS_Y, Z_OUT - 0.12)

	# the passage through the room wall, behind the kit's hatch frame
	var lo := Kit.HATCH_LO
	var hi := Kit.HATCH_HI
	var tunnel := Geo.new()
	tunnel.box_faces(Vector3(0, (lo.y + hi.y) * 0.5, (Z_FRAME + Z_WALL) * 0.5), Vector3(hi.x - lo.x, hi.y - lo.y, Z_WALL - Z_FRAME), [2, 3, 4, 5], true)
	_commit(tunnel, "dark")
	var inside := Geo.new()
	inside.tube(c0, c1, APOTHEM, 8, true)
	_commit(inside, "light_metal")
	var skin := Geo.new()
	skin.tube(c0, c1 + axis * 0.12, SKIN, 8, false)
	skin.ring(Vector3(0, AXIS_Y, Z_OUT), axis, OPENING, SKIN + 0.08, 0.24, 8)
	_commit(skin, "ext", true, true)
	var ribs := Geo.new()
	for z: float in [7.4, 8.7]:
		ribs.ring(Vector3(0, AXIS_Y, z), axis, APOTHEM - 0.14, APOTHEM, 0.12, 8)
	_commit(ribs, "hazard", false)
	var rails := Geo.new()
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var off := Vector3(cos(a), sin(a), 0) * (APOTHEM - 0.3)
		rails.pipe(c0 + off + axis * 0.4, c1 + off - axis * 0.3, 0.03)
	_commit(rails, "pipe2")

	# the shutters: each hangs from its top edge and rolls up into it
	_inner = _shutter(Vector3(0, hi.y + 0.07, Z_WALL + 0.08), Vector2(2.8, 2.8))
	_inner_shape = _inner.get_meta("shape")
	_outer = _shutter(Vector3(0, AXIS_Y + 1.45, Z_OUT - 0.22), Vector2(2.84, 2.9))
	_outer_shape = _outer.get_meta("shape")

	# light: a lamp in the roof, a red alarm for the cycle, a floodlight outside the hatch
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(0.9, 0.95, 1.0)
	_lamp_mat.emission_energy_multiplier = 2.0
	var lamp_geo := Geo.new()
	lamp_geo.box(Vector3(0, AXIS_Y + APOTHEM - 0.04, 8.05), Vector3(0.5, 0.05, 1.6))
	lamp_geo.box(Vector3(0, AXIS_Y + SKIN + 0.12, Z_OUT - 0.4), Vector3(0.18, 0.18, 0.18))
	lamp_geo.commit(_lamp_mat, self)
	_lamp = _omni(Vector3(0, AXIS_Y + 1.4, 8.0), Color(0.85, 0.92, 1.0), 0.9, 6.0)
	_alarm = _omni(Vector3(0, AXIS_Y + 1.2, 7.2), Color(1.0, 0.12, 0.05), 0.0, 6.5)
	var flood := _omni(Vector3(0, AXIS_Y + 2.9, Z_OUT + 1.2), Color(1.0, 0.95, 0.85), 1.4, 11.0)
	flood.light_cull_mask = Orbit.EXTERIOR_LAYER

	_vent = CPUParticles3D.new()
	_vent.emitting = false
	_vent.amount = 60
	_vent.lifetime = 1.4
	_vent.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_vent.emission_box_extents = Vector3(1.4, 1.4, 1.6)
	_vent.direction = Vector3(0, 0, 1)
	_vent.spread = 40.0
	_vent.initial_velocity_min = 0.6
	_vent.initial_velocity_max = 1.8
	_vent.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var mist := StandardMaterial3D.new()
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.albedo_color = Color(0.9, 0.95, 1.0, 0.35)
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mist
	_vent.mesh = q
	_vent.position = Vector3(0, AXIS_Y, 8.0)
	add_child(_vent)

	# the panel, on the chamber wall, facing in
	panel = Interactable.new()
	add_child(panel)
	panel.setup("airlock", "CYCLE AIRLOCK", "AIRLOCK", false, "")
	panel.hold_time = 1.2
	var wall := Vector3(APOTHEM - 0.08, AXIS_Y, 8.0)
	panel.global_position = to_global(wall)
	var facing := global_basis * Vector3(-1, 0, 0)
	panel.look_at(panel.global_position - facing, global_basis * Vector3.UP)
	panel.completed.connect(func(_id: String) -> void: _on_panel())
	panel.set_active(true)
	readout = Label3D.new()
	readout.font_size = 32
	readout.pixel_size = 0.0022
	readout.outline_size = 8
	readout.modulate = Color(0.6, 0.95, 1.0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(readout)
	readout.position = Vector3(0, -0.62, 0.08)
	_update_text()

func _commit(g: Geo, key: String, collide := true, ext := false) -> void:
	var mi := g.commit(_pal.get_mat(key), self, _body if collide else null, key)
	if mi and ext:
		mi.layers = 1 | Orbit.EXTERIOR_LAYER

func _omni(p: Vector3, col: Color, energy: float, range_: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = col
	l.light_energy = energy
	l.omni_range = range_
	l.shadow_enabled = false
	add_child(l)
	return l

## A door plate hanging from `top` (its top edge centre). Its StaticBody shape is kept on meta.
func _shutter(top: Vector3, size: Vector2) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = top
	add_child(pivot)
	var g := Geo.new()
	g.box(Vector3(0, -size.y * 0.5, 0), Vector3(size.x, size.y, 0.1))
	_commit_to(g, "frame", pivot)
	var stripe := Geo.new()
	for k in 3:
		stripe.box(Vector3(0, -size.y * (0.25 + 0.25 * k), 0), Vector3(size.x * 0.96, 0.1, 0.12))
	_commit_to(stripe, "hazard", pivot)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.14)
	cs.shape = box
	cs.position = Vector3(0, -size.y * 0.5, 0)
	body.add_child(cs)
	pivot.add_child(body)
	pivot.set_meta("shape", cs)
	return pivot

func _commit_to(g: Geo, key: String, parent: Node3D) -> void:
	var mi := g.commit(_pal.get_mat(key), parent)
	if mi:
		mi.layers = 1 | Orbit.EXTERIOR_LAYER

# ---------------------------------------------------------------- where things are
## Inside the chamber (a point in the world).
func contains(p: Vector3) -> bool:
	var l := to_local(p)
	return l.z > Z_WALL - 0.4 and l.z < Z_OUT - 0.1 and Vector2(l.x, l.y - AXIS_Y).length() < APOTHEM
func is_vacuum() -> bool:
	return state == State.VACUUM
func centre() -> Vector3:
	return to_global(Vector3(0, AXIS_Y, 8.0))
## Just outside the outer hatch, and the way out.
func exit_point() -> Vector3:
	return to_global(Vector3(0, AXIS_Y, Z_OUT + 1.2))
func outward() -> Vector3:
	return (global_basis * Vector3(0, 0, 1)).normalized()
## Just inside the room, in front of the inner hatch.
func room_point() -> Vector3:
	return to_global(Vector3(0, AXIS_Y, 3.6))
## Anchor points on the chamber's hull: above the outer hatch and on its roof.
func anchor_points() -> Array[Vector3]:
	return [to_global(Vector3(0, AXIS_Y + SKIN + 0.35, Z_OUT - 0.5)), to_global(Vector3(0, AXIS_Y + SKIN + 0.35, 7.0))]

func reset() -> void:
	state = State.PRESSURIZED
	pressure = 1.0
	_cycle = 0.0
	_inner_open = 1.0
	_outer_open = 0.0
	_vent.emitting = false
	_alarm.light_energy = 0.0
	panel.set_active(true)
	_apply_doors()
	_update_text()

# ---------------------------------------------------------------- cycling
func _on_panel() -> void:
	var player: Player = Game.player
	panel.set_active(true)
	if state == State.DEPRESSURIZING or state == State.REPRESSURIZING:
		return
	if player == null or not contains(player.camera.global_position):
		Game.notice.emit("AIRLOCK\nGet inside the chamber to cycle it.", 3.0)
		return
	if state == State.PRESSURIZED:
		if not player.suit_on:
			Game.notice.emit("AIRLOCK LOCKED\nNo suit detected. Put on an EVA suit first.", 3.5)
			Sfx.play_at("powerdown", panel.global_position, -14.0, 10.0, 2.0)
			return
		state = State.DEPRESSURIZING
	else:
		state = State.REPRESSURIZING
	_cycle = 0.0
	Sfx.play_at("beep", panel.global_position, -8.0, 12.0, 0.6)

## Test hook: cycle as if the panel had been held.
func debug_cycle() -> void:
	_on_panel()

func _process(delta: float) -> void:
	var inner_target := 1.0 if state == State.PRESSURIZED else 0.0
	var outer_target := 1.0 if state == State.VACUUM else 0.0
	_inner_open = move_toward(_inner_open, inner_target, DOOR_SPEED * delta)
	_outer_open = move_toward(_outer_open, outer_target, DOOR_SPEED * delta)
	_apply_doors()
	var cycling := state == State.DEPRESSURIZING or state == State.REPRESSURIZING
	# the air only moves once both shutters are down
	if cycling and _inner_open < 0.01 and _outer_open < 0.01:
		_cycle += delta
		var k := clampf(_cycle / CYCLE_TIME, 0.0, 1.0)
		pressure = 1.0 - k if state == State.DEPRESSURIZING else k
		_vent.emitting = state == State.DEPRESSURIZING and k < 0.8
		_hiss -= delta
		if _hiss <= 0.0:
			_hiss = 0.45
			Sfx.play_at("static", centre(), -12.0, 14.0, 0.35 if state == State.DEPRESSURIZING else 0.5)
		if k >= 1.0:
			_finish()
	_alarm.light_energy = (1.6 if fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4 else 0.2) if cycling else 0.0
	_lamp_mat.emission = Color(1.0, 0.15, 0.05) if cycling else (Color(0.3, 1.0, 0.45) if state == State.VACUUM else Color(0.9, 0.95, 1.0))
	_text_t -= delta
	if _text_t <= 0.0:
		_text_t = 0.2
		_update_text()

func _finish() -> void:
	_vent.emitting = false
	if state == State.DEPRESSURIZING:
		state = State.VACUUM
		pressure = 0.0
		Sfx.play_at("powerdown", centre(), -6.0, 20.0, 0.8)
		if Game.player and contains(Game.player.camera.global_position):
			Game.on_task_completed("eva_cycle_out")
	else:
		state = State.PRESSURIZED
		pressure = 1.0
		Sfx.play_at("powerup", centre(), -6.0, 20.0, 1.1)
		if Game.player and contains(Game.player.camera.global_position):
			Game.on_task_completed("eva_return")
	panel.set_active(true)

func _apply_doors() -> void:
	_inner.scale = Vector3(1.0, lerpf(1.0, 0.03, _inner_open), 1.0)
	_outer.scale = Vector3(1.0, lerpf(1.0, 0.03, _outer_open), 1.0)
	_inner_shape.set_deferred("disabled", _inner_open > 0.5)
	_outer_shape.set_deferred("disabled", _outer_open > 0.5)

func _update_text() -> void:
	var s: String = ["PRESSURIZED", "DEPRESSURIZING", "VACUUM - OUTER HATCH OPEN", "REPRESSURIZING"][state]
	readout.text = "%s\n%d kPa" % [s, roundi(101.0 * pressure)]
