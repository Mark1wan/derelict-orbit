extends CharacterBody3D
class_name Player
## Zero-G player. Two ways to get around, in VR (Quest 3) and on the desktop fallback:
##
##  GRAB   Hold GRIP with a hand next to any surface (rail, wall, console, crate) and that hand is
##         anchored to it. Move the controller and your body follows - pull yourself along, then
##         let go with a flick and you keep the momentum. This is the main way to move.
##  THRUST The sticks fire a suit pack with a tiny tank: about two seconds of burn, refills slowly.
##         Enough to correct a drift or reach the next rail, not to cruise.
##
## VR:      left stick = thrust relative to where you look, right stick = up/down + snap turn,
##          grip = grab (either hand), A / X = flashlight, right trigger = hold on a terminal.
## Desktop: RIGHT MOUSE on a surface within reach grabs it - drag the mouse to pull (release to
##          let go), WASD / Space / C = thrusters, Shift = hold on to what's in front of you,
##          F flashlight, E or LEFT click = use a terminal, Esc releases the mouse.

const THRUST := 2.4            # m/s^2 at full stick
const FUEL_DRAIN := 0.55       # tank per second at full burn (~1.8 s of burn)
const FUEL_REGEN := 0.06       # tank per second while not burning (~17 s to refill)
const MAX_SPEED := 3.5
const GRAB_PULL_SPEED := 6.0   # how fast a grabbed hand snaps back to its anchor
const DRIFT_DAMP := 0.12       # zero-G: you mostly keep drifting
const GRAB_REACH := 0.18       # metres from the hand to a surface that counts as touching it
const DESK_REACH := 2.2        # desktop arm's length, from the eye
const SNAP_ANGLE := 30.0
const DEAD_ZONE := 0.18

@onready var origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left: XRController3D = $XROrigin3D/LeftHand
@onready var right: XRController3D = $XROrigin3D/RightHand
@onready var body_shape: CollisionShape3D = $BodyShape

var flashlight: SpotLight3D
var ray: RayCast3D
var laser: MeshInstance3D
var wrist: Label3D
var hud_label: Label3D
var fade_mat: StandardMaterial3D
var fade_target := 1.0
var fade_speed := 1.5

var xr_active := false
var started := false
var flashlight_on := true
var snap_ready := true
var focused: Interactable = null
var yaw := 0.0
var pitch := 0.0
var mouse_captured := false
var _toggle_prev := false
var _notice_timer := 0.0
var _wrist_tick := 0.0
var _restart_hold := 0.0

# locomotion state
var fuel := 1.0
var thrusting := false
var grab_hand: XRController3D = null
var grab_anchor := Vector3.ZERO
var hand_mats := {}
var _reach_shape := SphereShape3D.new()
var d_grabbing := false
var d_anchor := Vector3.ZERO
var d_hand_local := Vector3.ZERO
var _empty_warned := false
var _debug_hold := false

const HAND_IDLE := Color(0.15, 0.16, 0.18)
const HAND_NEAR := Color(0.25, 0.55, 0.7)
const HAND_HELD := Color(0.3, 0.85, 0.45)

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_to_group("player")
	Game.player = self
	camera.current = true
	_reach_shape.radius = GRAB_REACH
	_build_attachments()
	Game.notice.connect(_on_notice)
	Game.tasks_changed.connect(_refresh_wrist)
	Game.phase_changed.connect(_on_phase)
	Game.game_reset.connect(_on_reset)
	_refresh_wrist()

func _build_attachments() -> void:
	for c in [left, right]:
		var hand_mat := StandardMaterial3D.new()
		hand_mat.albedo_color = HAND_IDLE
		hand_mat.metallic = 0.4
		hand_mats[c] = hand_mat
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.04, 0.13)
		mi.mesh = bm
		mi.material_override = hand_mat
		mi.position = Vector3(0, 0, 0.03)
		c.add_child(mi)
		# a finger loop: the grab point
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.02
		tm.outer_radius = 0.032
		tm.rings = 10
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = hand_mat
		ring.position = Vector3(0, -0.02, -0.02)
		c.add_child(ring)

	# flashlight body + lens on the right controller
	var hand_mat_r: StandardMaterial3D = hand_mats[right]
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.02
	cm.height = 0.14
	cm.radial_segments = 10
	body.mesh = cm
	body.material_override = hand_mat_r
	body.rotation.x = PI * 0.5
	body.position = Vector3(0, 0.02, -0.07)
	right.add_child(body)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.022
	lm.bottom_radius = 0.022
	lm.height = 0.01
	lm.radial_segments = 10
	lens.mesh = lm
	var lens_mat := StandardMaterial3D.new()
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1, 0.95, 0.8)
	lens_mat.emission_energy_multiplier = 3.0
	lens.material_override = lens_mat
	lens.rotation.x = PI * 0.5
	lens.position = Vector3(0, 0.02, -0.145)
	lens.name = "Lens"
	right.add_child(lens)

	flashlight = SpotLight3D.new()
	flashlight.name = "Flashlight"
	flashlight.position = Vector3(0, 0.02, -0.15)
	flashlight.light_color = Color(1.0, 0.94, 0.82)
	flashlight.light_energy = 3.2
	flashlight.spot_range = 20.0
	flashlight.spot_angle = 23.0
	flashlight.spot_attenuation = 1.1
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.06
	right.add_child(flashlight)

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -5)
	ray.collision_mask = 2
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	ray.enabled = true
	right.add_child(ray)

	laser = MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.003, 0.003, 1.0)
	laser.mesh = lb
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(1.0, 0.3, 0.2, 0.35)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser.material_override = lmat
	laser.position = Vector3(0, 0, -0.5)
	right.add_child(laser)

	wrist = Label3D.new()
	wrist.font_size = 40
	wrist.pixel_size = 0.0006
	wrist.outline_size = 10
	wrist.position = Vector3(0, 0.07, 0.0)
	wrist.rotation_degrees = Vector3(-35, 0, 0)
	wrist.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wrist.modulate = Color(0.7, 1.0, 0.8)
	wrist.no_depth_test = true
	wrist.render_priority = 50
	left.add_child(wrist)

	hud_label = Label3D.new()
	hud_label.font_size = 44
	hud_label.pixel_size = 0.0014
	hud_label.outline_size = 12
	hud_label.position = Vector3(0, -0.12, -1.6)
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label.modulate = Color(0.9, 0.95, 1.0)
	hud_label.no_depth_test = true
	hud_label.render_priority = 120
	camera.add_child(hud_label)

	# fade quad glued to the camera (CanvasLayer UI is not visible in XR)
	var fade := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(4, 4)
	fade.mesh = qm
	fade_mat = StandardMaterial3D.new()
	fade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_mat.albedo_color = Color(0, 0, 0, 1)
	fade_mat.no_depth_test = true
	fade_mat.render_priority = 100
	fade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fade.material_override = fade_mat
	fade.position = Vector3(0, 0, -0.25)
	camera.add_child(fade)

## Called once the session mode is known.
func begin(xr: bool) -> void:
	xr_active = xr
	started = true
	if not xr:
		camera.position = Vector3(0, 1.6, 0)
		flashlight.reparent(camera, false)
		flashlight.position = Vector3(0.18, -0.15, 0)
		flashlight.rotation = Vector3.ZERO
		ray.reparent(camera, false)
		ray.position = Vector3.ZERO
		ray.rotation = Vector3.ZERO
		laser.visible = false
		wrist.reparent(camera, false)
		wrist.position = Vector3(-1.15, -0.3, -1.5)
		wrist.rotation = Vector3.ZERO
		wrist.pixel_size = 0.0011
		left.visible = false
		right.visible = false
	fade_target = 0.0

func teleport_head_to(p: Vector3) -> void:
	var off := camera.global_position - global_position
	global_position = p - off
	velocity = Vector3.ZERO
	grab_hand = null
	d_grabbing = false

# ---------------------------------------------------------------- input helpers
func _stick(c: XRController3D) -> Vector2:
	for n in ["thumbstick", "primary", "touchpad"]:
		var v: Vector2 = c.get_vector2(n)
		if v.length() > DEAD_ZONE:
			return v
	return Vector2.ZERO

func _pressed(c: XRController3D, names: Array) -> bool:
	for n in names:
		if c.is_button_pressed(n):
			return true
	return false

func _trigger(c: XRController3D) -> bool:
	return _pressed(c, ["trigger_click"]) or c.get_float("trigger") > 0.55

func _grip(c: XRController3D) -> bool:
	return _pressed(c, ["grip_click"]) or c.get_float("grip") > 0.55

## Is there solid station (layer 1) within grabbing distance of this point?
func _near_surface(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _reach_shape
	q.transform = Transform3D(Basis(), p)
	q.collision_mask = 1
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Desktop: the surface straight ahead within arm's length, or an empty Dictionary.
func _reach_hit() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * DESK_REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)

func _start_grab(c: XRController3D) -> void:
	grab_hand = c
	grab_anchor = c.global_position
	Sfx.play("beep", -28.0, 0.5)
	if c.has_method("trigger_haptic_pulse"):
		c.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.05, 0.0)

func _end_grab() -> void:
	grab_hand = null
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED

func _tint_hand(c: XRController3D, near: bool, held: bool) -> void:
	var m: StandardMaterial3D = hand_mats[c]
	m.albedo_color = HAND_HELD if held else (HAND_NEAR if near else HAND_IDLE)

# ---------------------------------------------------------------- movement
func _physics_process(delta: float) -> void:
	if not started:
		return
	var frozen := Game.phase == Game.Phase.DEAD or Game.phase == Game.Phase.TITLE or Game.phase == Game.Phase.SLEEP
	var b := camera.global_transform.basis
	var wish := Vector3.ZERO
	var turn := 0.0
	var holding := false

	if xr_active:
		var ls := _stick(left)
		var rs := _stick(right)
		turn = rs.x
		var vert := rs.y if absf(rs.y) > DEAD_ZONE else 0.0
		if not frozen:
			wish = -b.z * ls.y + b.x * ls.x + Vector3.UP * vert
		var tog := _pressed(right, ["ax_button"]) or _pressed(left, ["ax_button"])
		if tog and not _toggle_prev:
			_toggle_flashlight()
		_toggle_prev = tog
		for c in [left, right]:
			var near := _near_surface(c.global_position)
			var g := _grip(c) and not frozen
			if g and grab_hand == null and near:
				_start_grab(c)
			elif not g and grab_hand == c:
				_end_grab()
			_tint_hand(c, near, grab_hand == c)
		if grab_hand:
			holding = true
			velocity = ((grab_anchor - grab_hand.global_position) / delta).limit_length(GRAB_PULL_SPEED)
	else:
		var move_in := Vector2(Input.get_axis("d_left", "d_right"), Input.get_axis("d_back", "d_forward"))
		var vert := Input.get_axis("d_down", "d_up")
		if not frozen:
			wish = -b.z * move_in.y + b.x * move_in.x + Vector3.UP * vert
		if Input.is_action_just_pressed("d_flash"):
			_toggle_flashlight()
		var rmb := (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and mouse_captured and not frozen) or _debug_hold
		if rmb and not d_grabbing:
			var hit := _reach_hit()
			if not hit.is_empty():
				d_grabbing = true
				d_anchor = hit["position"]
				d_hand_local = camera.global_transform.affine_inverse() * d_anchor
				Sfx.play("beep", -28.0, 0.5)
		elif not rmb and d_grabbing:
			d_grabbing = false
			if velocity.length() > MAX_SPEED:
				velocity = velocity.normalized() * MAX_SPEED
		if d_grabbing:
			holding = true
			var hand := camera.global_transform * d_hand_local
			velocity = ((d_anchor - hand) / delta).limit_length(GRAB_PULL_SPEED)
		elif Input.is_action_pressed("d_brake") and not _reach_hit().is_empty():
			holding = true
			velocity = velocity.lerp(Vector3.ZERO, clampf(6.0 * delta, 0.0, 1.0))

	# thrusters: a small tank, empties fast, refills slowly
	thrusting = false
	if not holding and wish.length() > 0.01:
		var w := wish.limit_length(1.0)
		if fuel > 0.0:
			velocity += w * THRUST * delta
			fuel = maxf(0.0, fuel - FUEL_DRAIN * delta * w.length())
			thrusting = true
			_empty_warned = false
		elif not _empty_warned:
			_empty_warned = true
			Game.notice.emit("THRUSTERS EMPTY\nGrab a rail and pull.", 2.5)
	if not thrusting and fuel < 1.0:
		fuel = minf(1.0, fuel + FUEL_REGEN * delta)
	if not holding:
		velocity = velocity.lerp(Vector3.ZERO, clampf(DRIFT_DAMP * delta, 0.0, 1.0))
		if velocity.length() > MAX_SPEED:
			velocity = velocity.normalized() * MAX_SPEED
	# the collider follows the head, so physically you *are* your head
	body_shape.global_position = camera.global_position
	move_and_slide()

	if xr_active:
		if absf(turn) > 0.7 and snap_ready:
			_snap(-signf(turn) * SNAP_ANGLE)
			snap_ready = false
		elif absf(turn) < 0.3:
			snap_ready = true
	_update_interaction(delta)

func _snap(deg: float) -> void:
	var cam_pos := camera.global_position
	origin.rotate_y(deg_to_rad(deg))
	origin.global_position += cam_pos - camera.global_position
	if grab_hand:
		grab_anchor = grab_hand.global_position   # keep the grip where the hand now is

func _toggle_flashlight() -> void:
	flashlight_on = not flashlight_on
	flashlight.visible = flashlight_on
	var lens := right.get_node_or_null("Lens")
	if lens:
		lens.visible = flashlight_on
	Sfx.play("beep", -20.0, 0.5)

func _unhandled_input(e: InputEvent) -> void:
	if xr_active or not started:
		return
	if e is InputEventMouseButton and e.pressed and not mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false
	elif e is InputEventMouseMotion and mouse_captured:
		if d_grabbing:
			# the mouse is your arm while you hold on: drag left to pull yourself right
			d_hand_local += Vector3(e.relative.x, -e.relative.y, 0) * 0.003
		else:
			yaw -= e.relative.x * 0.0022
			pitch = clampf(pitch - e.relative.y * 0.0022, -1.45, 1.45)
			origin.rotation.y = yaw
			camera.rotation.x = pitch

# ---------------------------------------------------------------- interaction
func _update_interaction(delta: float) -> void:
	var hit: Interactable = null
	if ray.is_colliding():
		var c := ray.get_collider()
		if c is Interactable:
			hit = c
	if hit != focused:
		if is_instance_valid(focused):
			focused.set_focused(false)
		focused = hit
		if focused:
			focused.set_focused(true)
	var pressing := _trigger(right) if xr_active else Input.is_action_pressed("d_interact")
	if Game.phase == Game.Phase.DEAD or Game.phase == Game.Phase.WON:
		if pressing:
			_restart_hold += delta
			if _restart_hold > 1.5:
				_restart_hold = -99.0
				Game.restart.call_deferred()
		else:
			_restart_hold = 0.0
		return
	if focused:
		if pressing:
			focused.hold(delta)
		else:
			focused.release()
	if laser.visible:
		var d := 5.0
		if ray.is_colliding():
			d = ray.global_position.distance_to(ray.get_collision_point())
		laser.scale.z = d
		laser.position.z = -d * 0.5

# ---------------------------------------------------------------- per-frame UI
func _process(delta: float) -> void:
	var c := fade_mat.albedo_color
	c.a = move_toward(c.a, fade_target, delta * fade_speed)
	fade_mat.albedo_color = c
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			hud_label.text = ""
	_wrist_tick += delta
	if _wrist_tick > 0.25:
		_wrist_tick = 0.0
		_refresh_wrist()

func _on_notice(text: String, seconds: float) -> void:
	hud_label.text = text
	_notice_timer = seconds

func _on_phase(p: int) -> void:
	match p:
		Game.Phase.SLEEP:
			fade_speed = 0.6
			fade_target = 1.0
		Game.Phase.NIGHT:
			# wake up in the dark, as far from the power plant as the deck allows
			teleport_head_to(Game.station.wake_point())
			fuel = 1.0
			await get_tree().create_timer(1.5).timeout
			fade_speed = 0.5
			fade_target = 0.0
		Game.Phase.DAY:
			fade_speed = 1.5
			fade_target = 0.0
		Game.Phase.DEAD:
			fade_speed = 2.5
			fade_target = 1.0
		Game.Phase.WON:
			fade_speed = 0.3
			fade_target = 1.0
	_refresh_wrist()

func _on_reset() -> void:
	teleport_head_to(Game.station.start_point())
	_restart_hold = 0.0
	fade_speed = 1.5
	fade_target = 0.0
	flashlight_on = true
	flashlight.visible = true
	fuel = 1.0
	hud_label.text = ""

## Test hooks (autotest): fake a desktop grab on a point 1 m ahead with the hand offset by `offset`,
## so the body should travel by -offset.
func debug_grab_pull(offset: Vector3) -> void:
	_debug_hold = true
	d_grabbing = true
	d_anchor = camera.global_position - camera.global_transform.basis.z * 1.0
	d_hand_local = camera.global_transform.affine_inverse() * d_anchor + offset

func debug_release() -> void:
	_debug_hold = false

func _fuel_bar() -> String:
	var n := int(round(fuel * 6.0))
	return "THRUST [" + "#".repeat(n) + "-".repeat(6 - n) + "]"

func _refresh_wrist() -> void:
	var s := ""
	match Game.phase:
		Game.Phase.TITLE:
			s = "KESTREL-9  maintenance terminal\nstandby"
		Game.Phase.DAY:
			s = "DAY %d    %s    %s\n" % [Game.day, Game.clock_string(), _fuel_bar()]
			for t in Game.tasks:
				s += "%s %s  -  %s\n" % ["[x]" if t["done"] else "[ ]", t["title"], t["room"]]
			if Game.day == 1 and Game.day_time < 40.0:
				s += "\n" + ("grip = grab a rail, pull, let go" if xr_active else "right mouse = grab, drag to pull")
		Game.Phase.SLEEP:
			s = "Shift over.\nGo to sleep."
		Game.Phase.NIGHT:
			s = "NIGHT %d    %s\nPOWER: OFFLINE\n> restore main power (POWER PLANT)\n> light freezes it. dark does not." % [Game.day, _fuel_bar()]
		Game.Phase.DEAD:
			s = "SIGNAL LOST"
		Game.Phase.WON:
			s = "RESCUED"
	wrist.text = s
