extends CharacterBody3D
class_name Player
## Zero-G player: two hands, a tool belt, and two ways to get around - in VR (Quest 3) and on the
## desktop fallback.
##
##  GRAB   Grip with an EMPTY hand next to any surface (rail, wall, console, crate) and that hand is
##         anchored there. Move the controller and your body follows; let go with a flick and you
##         keep the momentum. This is the main way to move.
##  THRUST The sticks fire a suit pack with a tiny tank: about two seconds of burn, refills slowly.
##  ROTATE Hold B (right hand) and the sticks become rotation thrusters: left stick pitches and
##         rolls, right stick yaws. Spin keeps going after you let go and burns the same fuel; a
##         hand on the station stops it. A vignette closes in while you spin. Comfort mode (title
##         screen) snaps 30 degrees per flick instead. Desktop: hold R and move the mouse.
##  ITEMS  Grip on a loose item, or on a holstered one at the belt, to hold it - keep gripping to
##         keep holding. Let go over an empty holster and it goes on the belt; let go anywhere
##         else and it floats off with your hand's motion. A hand holding something cannot grab
##         rails, so belt what you are not using. Tasks need the right repair tool: point it at
##         the terminal and hold trigger. See Item and ToolBelt.
##
## VR:      left stick = thrust relative to where you look, right stick = up/down + snap turn,
##          grip = grab / hold, A / X = flashlight on-off wherever it is, trigger = use what that
##          hand holds on the terminal it points at.
## Desktop: RIGHT MOUSE on a surface within reach grabs it, drag to pull. WASD / Space / C
##          thrusters, Shift hold on. 1-4 swap your hand with that belt holster, Q let go of what
##          you hold, E / LEFT click pick up a loose item in reach or use the held tool on a
##          terminal, F flashlight, Esc releases the mouse.

const THRUST := 2.4            # m/s^2 at full stick
const FUEL_DRAIN := 0.55       # tank per second at full burn (~1.8 s of burn)
const FUEL_REGEN := 0.06       # tank per second while not burning (~17 s to refill)
const MAX_SPEED := 3.5
const GRAB_PULL_SPEED := 6.0   # how fast a grabbed hand snaps back to its anchor
const DRIFT_DAMP := 0.12       # zero-G: you mostly keep drifting
const GRAB_REACH := 0.18       # metres from the hand to a surface that counts as touching it
const DESK_REACH := 2.2        # desktop arm's length, from the eye
const DESK_PICK_REACH := 1.8   # desktop: how far away a loose item can be picked up
const DESK_HAND := Vector3(0.2, -0.2, -0.42)
const SNAP_ANGLE := 30.0
const DEAD_ZONE := 0.18
const ROT_ACCEL := 1.4         # rad/s^2 of spin from a full stick with B held
const ROT_MAX := 1.6           # rad/s
const ROT_DAMP := 0.05         # zero-G: a spin mostly keeps going
const ROT_FUEL := 0.35         # tank per second at full rotation burn
const SNAP_ROT := 30.0         # comfort mode: degrees per flick
const DESK_ROT := 0.004        # desktop R + mouse: radians per pixel

const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = smoothstep(0.3, 0.85, d) * strength;
}
"""

@onready var origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left: XRController3D = $XROrigin3D/LeftHand
@onready var right: XRController3D = $XROrigin3D/RightHand
@onready var body_shape: CollisionShape3D = $BodyShape

var flashlight: SpotLight3D       # the beam of the flashlight item, wherever that item is
var flash_item: Item
var belt: ToolBelt
var held := {}                    # hand node -> Item
var rays := {}                    # hand node -> RayCast3D (terminals, layer 2)
var lasers := {}                  # hand node -> MeshInstance3D
var desk_hand: Node3D             # desktop: the one virtual hand, bottom right of the view
var wrist: HoloPanel              # the crew terminal hologram: tasks, clock, fuel, kit
var _menu_prev := false
var hud_label: Label3D
var fade_mat: StandardMaterial3D
var fade_target := 1.0
var fade_speed := 1.5

var xr_active := false
var started := false
var flashlight_on := true
var snap_ready := true
var focused := {}                 # Interactable -> true: what some hand points at this frame
var _using := {}                  # Interactable -> true: what a trigger is held on this frame
var yaw := 0.0
var pitch := 0.0
var mouse_captured := false
var _toggle_prev := false
var _notice_timer := 0.0
var _wrist_tick := 0.0
var _restart_hold := 0.0
var _wrong_cd := 0.0

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
var _grip_prev := {}
var _hand_prev := {}
var _hand_vel := {}
var ang_vel := Vector3.ZERO         # world-space spin, rad/s
var _rot_burn := false
var _rot_snap_ready := true
var _vignette := 0.0
var vignette_mat: ShaderMaterial

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
	belt = ToolBelt.new()
	add_child(belt)
	_give_starting_kit()
	Game.notice.connect(_on_notice)
	Game.tasks_changed.connect(_refresh_wrist)
	Game.tasks_changed.connect(wrist.notify)
	Game.day_started.connect(func(_d: int) -> void: wrist.notify())
	Game.phase_changed.connect(_on_phase)
	Game.game_reset.connect(_on_reset)
	_refresh_wrist()

func _build_attachments() -> void:
	for c: XRController3D in [left, right]:
		var hand_mat := StandardMaterial3D.new()
		hand_mat.albedo_color = HAND_IDLE
		hand_mat.metallic = 0.4
		hand_mats[c] = hand_mat
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.04, 0.13)
		mi.mesh = bm
		mi.material_override = hand_mat
		mi.position = Vector3(0, -0.03, 0.06)
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
		var r := _make_ray()
		c.add_child(r)
		rays[c] = r
		var lz := _make_laser()
		c.add_child(lz)
		lasers[c] = lz

	wrist = HoloPanel.new()
	wrist.attach_wrist(left, camera)

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

	# comfort vignette: the edges of the view close in while the body spins
	var vig := MeshInstance3D.new()
	var vq := QuadMesh.new()
	vq.size = Vector2(0.8, 0.8)
	vig.mesh = vq
	vignette_mat = ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = VIGNETTE_SHADER
	vignette_mat.shader = vs
	vignette_mat.render_priority = 99
	vig.material_override = vignette_mat
	vig.position = Vector3(0, 0, -0.26)
	vig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(vig)

func _make_ray() -> RayCast3D:
	var r := RayCast3D.new()
	r.target_position = Vector3(0, 0, -5)
	r.collision_mask = 2
	r.collide_with_areas = true
	r.collide_with_bodies = false
	r.enabled = true
	return r

func _make_laser() -> MeshInstance3D:
	var laser := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.003, 0.003, 1.0)
	laser.mesh = lb
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(1.0, 0.3, 0.2, 0.35)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser.material_override = lmat
	laser.position = Vector3(0, 0, -0.5)
	laser.visible = false
	return laser

## The flashlight and the wrench, both on the belt. Everything else is somewhere on the deck.
func _give_starting_kit() -> void:
	flash_item = Item.make(Item.FLASHLIGHT)
	flashlight = flash_item.light
	belt.stow(flash_item, 1, true)
	belt.stow(Item.make(Item.WRENCH), 2, true)
	flashlight_on = true
	flash_item.set_light(true)

## Called once the session mode is known.
func begin(xr: bool) -> void:
	xr_active = xr
	started = true
	belt.snap()
	if not xr:
		camera.position = Vector3(0, 1.6, 0)
		for c: XRController3D in [left, right]:
			(rays[c] as RayCast3D).enabled = false
		desk_hand = Node3D.new()
		desk_hand.name = "DeskHand"
		desk_hand.position = DESK_HAND
		camera.add_child(desk_hand)
		var r := _make_ray()
		camera.add_child(r)
		rays = {desk_hand: r}
		lasers = {}
		wrist.attach_view(camera)
		left.visible = false
		right.visible = false
		belt.show_numbers(true)
		# on a flat screen the flashlight is most use in the hand: it aims where you look
		_put_in_hand(desk_hand, belt.take(belt.slot_of(Item.FLASHLIGHT)))
	fade_target = 0.0

func teleport_head_to(p: Vector3) -> void:
	var off := camera.global_position - global_position
	global_position = p - off
	velocity = Vector3.ZERO
	grab_hand = null
	d_grabbing = false
	belt.snap()

func look_at_point(p: Vector3) -> void:
	var v := p - camera.global_position
	yaw = atan2(-v.x, -v.z)
	pitch = clampf(atan2(v.y, Vector2(v.x, v.z).length()), -1.45, 1.45)
	var cam := camera.global_position
	origin.global_basis = Basis(Vector3.UP, yaw)
	camera.rotation.x = pitch
	origin.global_position += cam - camera.global_position
	ang_vel = Vector3.ZERO

## Stand the body upright again, keeping the heading (waking up, restarting).
func reset_orientation() -> void:
	var f := -camera.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = Vector3.FORWARD
	yaw = atan2(-f.x, -f.z)
	var cam := camera.global_position
	origin.global_basis = Basis(Vector3.UP, yaw)
	origin.global_position += cam - camera.global_position
	ang_vel = Vector3.ZERO
	belt.snap()

## Turn the whole body about `axis` by `angle`, pivoting on the head so the view does not swing.
func _rotate_body(axis: Vector3, angle: float) -> void:
	if absf(angle) < 1e-6 or axis.length_squared() < 1e-8:
		return
	var cam := camera.global_position
	origin.global_basis = (Basis(axis.normalized(), angle) * origin.global_basis).orthonormalized()
	origin.global_position += cam - camera.global_position
	if grab_hand:
		grab_anchor = grab_hand.global_position

## Rotation thrusters. `input` is (pitch, yaw, roll) in -1..1 about the head's own axes: pitch > 0
## tips the nose down, yaw > 0 turns right, roll > 0 rolls right. The spin keeps going once the
## input stops - zero-G - and costs fuel. Comfort mode snaps in steps instead.
func apply_rotation_input(input: Vector3, delta: float) -> void:
	if Game.comfort_snap:
		_snap_rotation(input)
		return
	var w := input.limit_length(1.0)
	if w.length() < 0.01:
		return
	if fuel <= 0.0:
		if not _empty_warned:
			_empty_warned = true
			Game.notice.emit("THRUSTERS EMPTY\nGrab a rail to stop the spin.", 2.5)
		return
	var b := camera.global_transform.basis
	ang_vel += (b.x * -w.x + b.y * -w.y + -b.z * w.z) * ROT_ACCEL * delta
	fuel = maxf(0.0, fuel - ROT_FUEL * delta * w.length())
	_rot_burn = true

func _snap_rotation(input: Vector3) -> void:
	var m := maxf(absf(input.x), maxf(absf(input.y), absf(input.z)))
	if m < 0.3:
		_rot_snap_ready = true
		return
	if m < 0.7 or not _rot_snap_ready:
		return
	_rot_snap_ready = false
	var b := camera.global_transform.basis
	var a := deg_to_rad(SNAP_ROT)
	if absf(input.x) == m:
		_rotate_body(b.x, -a * signf(input.x))
	elif absf(input.z) == m:
		_rotate_body(-b.z, a * signf(input.z))
	else:
		_rotate_body(b.y, -a * signf(input.y))
	ang_vel = Vector3.ZERO
	_vignette = 0.7

# ---------------------------------------------------------------- input helpers
func _hands() -> Array:
	if xr_active:
		return [left, right]
	return [desk_hand] if desk_hand else []

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

func _buzz(hand: Node3D, amp: float) -> void:
	if hand is XRController3D and hand.has_method("trigger_haptic_pulse"):
		(hand as XRController3D).trigger_haptic_pulse("haptic", 0.0, amp, 0.05, 0.0)

func _start_grab(c: XRController3D) -> void:
	grab_hand = c
	grab_anchor = c.global_position
	Sfx.play("beep", -28.0, 0.5)
	_buzz(c, 0.5)

func _end_grab() -> void:
	grab_hand = null
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED

func _tint_hand(c: XRController3D, near: bool, holding: bool) -> void:
	var m: StandardMaterial3D = hand_mats[c]
	m.albedo_color = HAND_HELD if holding else (HAND_NEAR if near else HAND_IDLE)

# ---------------------------------------------------------------- items and the belt
func held_item(hand: Node3D = null) -> Item:
	if hand == null:
		hand = right if xr_active else desk_hand
	return held.get(hand)

func held_kind(hand: Node3D = null) -> String:
	var it := held_item(hand)
	return it.kind if it else ""

func _put_in_hand(hand: Node3D, item: Item) -> void:
	if item == null or hand == null:
		return
	held[hand] = item
	item.attach_to(hand, Transform3D.IDENTITY, Item.Where.HAND)
	_buzz(hand, 0.3)

func _take_from_hand(hand: Node3D) -> Item:
	var it: Item = held.get(hand)
	held.erase(hand)
	return it

func _stow_from_hand(hand: Node3D, slot: int) -> bool:
	var it: Item = held.get(hand)
	if it == null or not belt.stow(it, slot):
		return false
	held.erase(hand)
	_buzz(hand, 0.2)
	return true

## Open the hand: the item floats off into the station with `vel`.
func _let_go(hand: Node3D, vel: Vector3) -> void:
	var it := _take_from_hand(hand)
	if it == null:
		return
	var parent: Node = Game.station
	var r = Game.station.get("root")
	if r is Node:
		parent = r
	it.release_into(parent, vel)
	Sfx.play("beep", -30.0, 0.7)

func _nearest_loose(p: Vector3, reach: float) -> Item:
	var best: Item = null
	var best_d := reach
	for n in get_tree().get_nodes_in_group(Item.GROUP):
		var it := n as Item
		if it == null:
			continue
		var d := it.grab_point().distance_to(p)
		if d < best_d:
			best_d = d
			best = it
	return best

func _carried(kind: String) -> bool:
	for hand in held:
		var it: Item = held[hand]
		if it and it.kind == kind:
			return true
	return belt.slot_of(kind) >= 0

## Where an item is, in words for the wrist and for "wrong tool" notices.
func _where_is(kind: String) -> String:
	for hand in held:
		var it: Item = held[hand]
		if it and it.kind == kind:
			return "in your hand"
	var s := belt.slot_of(kind)
	if s >= 0:
		return "on your belt" if xr_active else "on your belt (%d)" % (s + 1)
	for n in get_tree().get_nodes_in_group(Item.GROUP):
		var it := n as Item
		if it and it.kind == kind:
			if Game.station.has_method("place_name"):
				return "last seen: " + String(Game.station.call("place_name", it.global_position))
			return "somewhere on the deck"
	return "lost"

## Desktop: swap whatever is in the hand with holster `i` (0-based). Keys 1-4.
func desk_slot(i: int) -> void:
	if desk_hand == null or i < 0 or i >= ToolBelt.SLOTS:
		return
	var in_hand := _take_from_hand(desk_hand)
	var in_slot := belt.take(i)
	if in_hand:
		belt.stow(in_hand, i)
	if in_slot:
		_put_in_hand(desk_hand, in_slot)

## Desktop: the loose item nearest the middle of the view within reach, into the empty hand.
func pick_up_nearest(reach := DESK_PICK_REACH) -> bool:
	if desk_hand == null or held.get(desk_hand) != null:
		return false
	var eye := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var best: Item = null
	var best_off := INF
	for n in get_tree().get_nodes_in_group(Item.GROUP):
		var it := n as Item
		if it == null:
			continue
		var v := it.grab_point() - eye
		var d := v.length()
		if d > reach:
			continue
		var off := (v - fwd * v.dot(fwd)).length()     # distance from the line of sight
		if d > 0.7 and (v.dot(fwd) <= 0.0 or off > 0.4):
			continue
		if off < best_off:
			best_off = off
			best = it
	if best == null:
		return false
	_put_in_hand(desk_hand, best)
	Sfx.play("beep", -24.0, 1.2)
	return true

func _wrong_tool(it: Interactable) -> void:
	if _wrong_cd > 0.0 or it.tool == "":
		return
	_wrong_cd = 2.5
	Game.notice.emit("NEEDS THE %s\n%s" % [Item.LABEL.get(it.tool, it.tool.to_upper()), _where_is(it.tool)], 2.5)

# ---------------------------------------------------------------- movement
func _physics_process(delta: float) -> void:
	if not started:
		return
	var frozen := Game.phase == Game.Phase.DEAD or Game.phase == Game.Phase.TITLE or Game.phase == Game.Phase.SLEEP
	belt.follow(camera, origin.global_basis.y, delta)
	_wrong_cd = maxf(0.0, _wrong_cd - delta)
	_rot_burn = false
	var b := camera.global_transform.basis
	var wish := Vector3.ZERO
	var turn := 0.0
	var holding := false

	if xr_active:
		var ls := _stick(left)
		var rs := _stick(right)
		if _pressed(right, ["by_button"]):
			# B held: the sticks are rotation thrusters - left pitches and rolls, right yaws
			if not frozen:
				apply_rotation_input(Vector3(ls.y, rs.x, ls.x), delta)
		else:
			_rot_snap_ready = true
			turn = rs.x
			var vert := rs.y if absf(rs.y) > DEAD_ZONE else 0.0
			if not frozen:
				wish = -b.z * ls.y + b.x * ls.x + origin.global_basis.y * vert
		var menu := _pressed(left, ["by_button"])
		if menu and not _menu_prev:
			toggle_panel()
		_menu_prev = menu
		var tog := _pressed(right, ["ax_button"]) or _pressed(left, ["ax_button"])
		if tog and not _toggle_prev:
			_toggle_flashlight()
		_toggle_prev = tog
		var lit := {}
		for c: XRController3D in [left, right]:
			var p := c.global_position
			var prev: Vector3 = _hand_prev.get(c, p)
			var hv: Vector3 = _hand_vel.get(c, Vector3.ZERO)
			_hand_vel[c] = hv.lerp((p - prev) / delta, 0.5)
			_hand_prev[c] = p
			var g := _grip(c)                 # items follow the raw grip, so a fade never drops them
			var was: bool = _grip_prev.get(c, false)
			_grip_prev[c] = g
			var item: Item = held.get(c)
			# an empty hand looks for a full holster to draw from, a full hand for an empty one
			var slot := belt.nearest(p, item == null)
			var loose: Item = null
			if item == null and slot < 0 and grab_hand != c:
				loose = _nearest_loose(p, Item.GRAB_REACH)
			var near := _near_surface(p)
			if slot >= 0:
				lit[slot] = true
			if g and not was:
				if item == null and slot >= 0:
					_put_in_hand(c, belt.take(slot))
				elif item == null and loose:
					_put_in_hand(c, loose)
			elif not g and was and item != null:
				if slot >= 0:
					_stow_from_hand(c, slot)
				else:
					_let_go(c, _hand_vel[c])
			if g and not frozen and held.get(c) == null and grab_hand == null and near:
				_start_grab(c)
			elif (not g or frozen) and grab_hand == c:
				_end_grab()
			_tint_hand(c, near or loose != null or (item == null and slot >= 0), grab_hand == c or held.get(c) != null)
		belt.highlight(lit)
		if grab_hand:
			holding = true
			velocity = ((grab_anchor - grab_hand.global_position) / delta).limit_length(GRAB_PULL_SPEED)
	else:
		var move_in := Vector2(Input.get_axis("d_left", "d_right"), Input.get_axis("d_back", "d_forward"))
		var vert := Input.get_axis("d_down", "d_up")
		if not frozen:
			wish = -b.z * move_in.y + b.x * move_in.x + origin.global_basis.y * vert
		if Input.is_action_just_pressed("d_flash"):
			_toggle_flashlight()
		if Input.is_action_just_pressed("d_menu"):
			toggle_panel()
		if Input.is_action_just_pressed("d_drop") and not frozen:
			_let_go(desk_hand, -b.z * 0.5 + velocity)
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
	if not thrusting and not _rot_burn and fuel < 1.0:
		fuel = minf(1.0, fuel + FUEL_REGEN * delta)
	if not holding:
		velocity = velocity.lerp(Vector3.ZERO, clampf(DRIFT_DAMP * delta, 0.0, 1.0))
		if velocity.length() > MAX_SPEED:
			velocity = velocity.normalized() * MAX_SPEED
	# spin: what the rotation thrusters built up keeps turning you - until a hand takes hold
	if grab_hand or d_grabbing:
		ang_vel = Vector3.ZERO
	elif ang_vel.length_squared() > 1e-6:
		ang_vel = ang_vel.limit_length(ROT_MAX)
		_rotate_body(ang_vel.normalized(), ang_vel.length() * delta)
		ang_vel = ang_vel.lerp(Vector3.ZERO, clampf(ROT_DAMP * delta, 0.0, 1.0))
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

## Snap turn about the body's own up (right stick, B not held).
func _snap(deg: float) -> void:
	_rotate_body(origin.global_basis.y, deg_to_rad(deg))

func _toggle_flashlight() -> void:
	flashlight_on = not flashlight_on
	if is_instance_valid(flash_item):
		flash_item.set_light(flashlight_on)
	Sfx.play("beep", -20.0, 0.5)

func _unhandled_input(e: InputEvent) -> void:
	if xr_active or not started:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = (e as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			desk_slot(k - KEY_1)
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
		elif Input.is_physical_key_pressed(KEY_R):
			# R held: the mouse rolls and pitches the whole body - there is no up in here
			var cb := camera.global_transform.basis
			_rotate_body(-cb.z, e.relative.x * DESK_ROT)
			_rotate_body(cb.x, -e.relative.y * DESK_ROT)
		else:
			yaw -= e.relative.x * 0.0022
			_rotate_body(origin.global_basis.y, -e.relative.x * 0.0022)
			pitch = clampf(pitch - e.relative.y * 0.0022, -1.45, 1.45)
			camera.rotation.x = pitch

# ---------------------------------------------------------------- interaction
func _update_interaction(delta: float) -> void:
	var dead := Game.phase == Game.Phase.DEAD or Game.phase == Game.Phase.WON
	var now_focused := {}
	var now_using := {}
	var any_press := false
	for hand: Node3D in _hands():
		var r: RayCast3D = rays.get(hand)
		if r == null:
			continue
		var hit: Interactable = null
		if r.is_colliding():
			hit = r.get_collider() as Interactable
		var pressing := _trigger(hand as XRController3D) if xr_active else Input.is_action_pressed("d_interact")
		any_press = any_press or pressing
		var item: Item = held.get(hand)
		if lasers.has(hand):
			var lz: MeshInstance3D = lasers[hand]
			lz.visible = hit != null or (item != null and item.kind != Item.FLASHLIGHT)
			var d := 5.0
			if r.is_colliding():
				d = r.global_position.distance_to(r.get_collision_point())
			lz.scale.z = d
			lz.position.z = -d * 0.5
		if hit == null:
			continue
		now_focused[hit] = true
		if dead or not pressing:
			continue
		now_using[hit] = true
		if hit.hold(delta, item.kind if item else ""):
			if item:
				item.working(delta)
		elif hit.active and not hit.done:
			_wrong_tool(hit)
	# desktop: pressing use with an empty hand and no terminal in sight picks up a loose item
	if not xr_active and not dead and now_focused.is_empty() and Input.is_action_just_pressed("d_interact"):
		pick_up_nearest()
	for it in focused.keys():
		if not now_focused.has(it) and is_instance_valid(it):
			(it as Interactable).set_focused(false)
	for it in now_focused.keys():
		if not focused.has(it):
			(it as Interactable).set_focused(true)
	focused = now_focused
	for it in _using.keys():
		if not now_using.has(it) and is_instance_valid(it):
			(it as Interactable).release()
	_using = now_using
	if dead:
		if any_press:
			_restart_hold += delta
			if _restart_hold > 1.5:
				_restart_hold = -99.0
				Game.restart.call_deferred()
		else:
			_restart_hold = 0.0

# ---------------------------------------------------------------- per-frame UI
func _process(delta: float) -> void:
	if started:
		belt.follow(camera, origin.global_basis.y, delta)
	var c := fade_mat.albedo_color
	c.a = move_toward(c.a, fade_target, delta * fade_speed)
	fade_mat.albedo_color = c
	if xr_active and not Game.comfort_snap:
		_vignette = maxf(_vignette - delta * 1.5, clampf(ang_vel.length() / 0.9, 0.0, 1.0) * 0.8)
	else:
		_vignette = maxf(_vignette - delta * 3.0, 0.0)
	vignette_mat.set_shader_parameter("strength", _vignette)
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
			# wake up in the dark, as far from the power plant as the deck allows - with your belt
			teleport_head_to(Game.station.wake_point())
			reset_orientation()
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
	for hand in held.keys():
		var it: Item = held[hand]
		if is_instance_valid(it):
			it.queue_free()
	held.clear()
	belt.clear()
	_give_starting_kit()
	if not xr_active and desk_hand:
		_put_in_hand(desk_hand, belt.take(belt.slot_of(Item.FLASHLIGHT)))
	teleport_head_to(Game.station.start_point())
	reset_orientation()
	_restart_hold = 0.0
	fade_speed = 1.5
	fade_target = 0.0
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

func debug_let_go() -> void:
	_let_go(desk_hand, -camera.global_transform.basis.z * 0.5)

## Test hook (autotest): get `kind` into the desktop hand the way a player would - from the belt,
## or by going to wherever it floats and picking it up. False if it cannot be had.
func debug_equip(kind: String) -> bool:
	if held_kind(desk_hand) == kind:
		return true
	var s := belt.slot_of(kind)
	if s >= 0:
		desk_slot(s)
		return held_kind(desk_hand) == kind
	for n in get_tree().get_nodes_in_group(Item.GROUP):
		var it := n as Item
		if it == null or it.kind != kind:
			continue
		if held.get(desk_hand) != null:
			var spare := belt.first_empty()
			if spare < 0:
				return false
			_stow_from_hand(desk_hand, spare)
		teleport_head_to(it.grab_point() + Vector3(0, 0, 0.6))
		look_at_point(it.grab_point())
		return pick_up_nearest() and held_kind(desk_hand) == kind
	return false

## Show or hide the crew terminal (Y on the left hand, TAB on the desktop).
func toggle_panel() -> void:
	wrist.toggle()

## Review hook (photo mode): pose the left hand in front of the desktop camera and project the
## terminal from it the way it looks in VR, or put it back.
func debug_preview_wrist(on: bool) -> void:
	if on:
		left.visible = true
		left.position = Vector3(-0.14, 1.26, -0.4)
		left.rotation_degrees = Vector3(25.0, 30.0, 0.0)
		wrist.attach_wrist(left, camera)
	else:
		left.visible = false
		wrist.attach_view(camera)

func _fuel_bar() -> String:
	var n := int(round(fuel * 6.0))
	return "THRUST [" + "#".repeat(n) + "-".repeat(6 - n) + "]"

## Hands, belt, and where the tools you are not carrying were last seen.
func _kit_line() -> String:
	var hands := PackedStringArray()
	for hand in _hands():
		var it: Item = held.get(hand)
		hands.append(Item.SHORT[it.kind] if it else "-")
	var s := "HAND %s    BELT" % " / ".join(hands)
	for i in ToolBelt.SLOTS:
		var it: Item = belt.items[i]
		s += " %d:%s" % [i + 1, Item.SHORT[it.kind] if it else "-"]
	var away := PackedStringArray()
	for kind: String in Item.TOOLS + [Item.FLASHLIGHT]:
		if not _carried(kind):
			away.append("%s @ %s" % [Item.SHORT[kind], _where_is(kind).trim_prefix("last seen: ")])
	if not away.is_empty():
		s += "\n" + "   ".join(away)
	return s + "\n"

func _refresh_wrist() -> void:
	var s := ""
	match Game.phase:
		Game.Phase.TITLE:
			s = "KESTREL-9  maintenance terminal\nstandby"
		Game.Phase.DAY:
			s = "DAY %d    %s    %s\n" % [Game.day, Game.clock_string(), _fuel_bar()]
			for t in Game.tasks:
				var tk: String = t.get("tool", "")
				var need := "  [%s]" % Item.SHORT.get(tk, tk.to_upper()) if tk != "" else ""
				s += "%s %s  -  %s%s\n" % ["[x]" if t["done"] else "[ ]", t["title"], t["room"], need]
			s += _kit_line()
			if Game.day == 1 and Game.day_time < 45.0:
				if xr_active:
					s += "\ngrip empty hand = grab rail   grip item = hold it\nlet go over a holster = belt it   trigger = use tool\nhold B + sticks = rotate (spin keeps going)\nY (left hand) = hide this terminal"
				else:
					s += "\nright mouse = grab   1-4 = belt   Q = let go\nE / click = pick up or use tool   R + mouse = roll / pitch\nTAB = hide this terminal"
		Game.Phase.SLEEP:
			s = "Shift over.\nGo to sleep."
		Game.Phase.NIGHT:
			s = "NIGHT %d    %s\nPOWER: OFFLINE\n> restore main power (POWER PLANT)\n> light freezes it. dark does not.\n" % [Game.day, _fuel_bar()]
			s += _kit_line()
		Game.Phase.DEAD:
			s = "SIGNAL LOST"
		Game.Phase.WON:
			s = "RESCUED"
	wrist.set_text(s)
