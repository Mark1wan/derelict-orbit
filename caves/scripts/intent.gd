class_name Intent
extends RefCounted
## What the player is asking for this frame, in one struct, produced three ways and consumed
## once.
##
## derelict-orbit does not have this, and it is the one thing about it that does not scale.
## Its player.gd branches on `xr_active` in the middle of _physics_process and runs two
## parallel movement implementations; touch then smuggles itself into the desktop branch by
## forging key presses with Input.action_press and calling six touch_*() methods directly.
## It works, but every new verb has to be threaded through three places and there is nowhere
## to stand if you want to know what the player actually asked for.
##
## A caving game has more verbs than a zero-G one - a posture, a held breath, two hands on the
## rock, a rope - and they interact. So: three producers fill this struct, caver.gd reads it
## and nothing else, and the autotests write it directly, which is how a headless run can crawl
## the whole cave without a keyboard.

enum Source { DESKTOP, TOUCH, XR }

var source := Source.DESKTOP

var move := Vector2.ZERO      ## x strafe, y forward. Already dead-zoned and clamped.
var look := Vector2.ZERO      ## yaw, pitch delta in radians, this frame
var snap := 0                 ## -1 / +1 for one snap turn, VR and touch comfort mode

var exhale := 0.0             ## 0..1 held. The one input the whole cave is built around.
var lower := false            ## edge: fold down one posture past what the ceiling demands
var raise := false            ## edge: stand back up if there is room

var lamp := false             ## edge: headlamp on / off
var backup := false           ## edge: hand torch on / off
var slate := false            ## edge: survey slate
var rope := false             ## edge: clip on / off the rope
var brake := 0.0              ## 0..1 held: the rappel brake, and a general "hold still"

## One per hand. In VR both are real and tracked; flat and touch have a single virtual hand in
## slot 0 whose pose is derived from the camera. `grab` is held, not an edge.
class Hand:
	var active := false
	var pose := Transform3D.IDENTITY
	var grab := false
	var trigger := 0.0
	var pull := Vector2.ZERO   ## flat and touch only: drag that moves the virtual hand

var hands: Array[Hand] = [Hand.new(), Hand.new()]

## Clear the per-frame edges. Held values (move, exhale, grab) are rewritten by the producer
## every frame, so only the ones that fire once need this.
func clear_edges() -> void:
	lower = false
	raise = false
	lamp = false
	backup = false
	slate = false
	rope = false
	snap = 0
	look = Vector2.ZERO
	for h in hands:
		h.pull = Vector2.ZERO

func any_grab() -> bool:
	return hands[0].grab or hands[1].grab

# ---------------------------------------------------------------- desktop

const DEAD_ZONE := 0.12

## Keyboard and mouse. The InputMap actions are built in code by CaveGame._setup_input(), the
## way derelict-orbit's game.gd:236-263 does, so there is nothing to lose in project.godot.
func read_desktop(cam: Camera3D, reach: float) -> void:
	source = Source.DESKTOP
	move = Vector2(
		Input.get_axis("c_left", "c_right"),
		Input.get_axis("c_back", "c_forward")).limit_length(1.0)
	exhale = 1.0 if Input.is_action_pressed("c_exhale") else 0.0
	brake = 1.0 if Input.is_action_pressed("c_brake") else 0.0
	lower = lower or Input.is_action_just_pressed("c_lower")
	raise = raise or Input.is_action_just_pressed("c_raise")
	lamp = lamp or Input.is_action_just_pressed("c_lamp")
	backup = backup or Input.is_action_just_pressed("c_backup")
	slate = slate or Input.is_action_just_pressed("c_slate")
	rope = rope or Input.is_action_just_pressed("c_rope")

	var h := hands[0]
	h.active = true
	h.grab = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	h.trigger = 1.0 if Input.is_action_pressed("c_use") else 0.0
	if cam:
		h.pose = Transform3D(cam.global_transform.basis,
			cam.global_position + cam.global_transform.basis * Vector3(0.18, -0.16, -reach * 0.45))
	hands[1].active = false
	hands[1].grab = false

# ---------------------------------------------------------------- VR

const XR_DEAD_ZONE := 0.18

## Poll the controllers. XRController3D exposes signals but derelict-orbit polls instead, and
## so do we: a struct filled once per frame has no ordering problem, and edges are diffed here
## rather than scattered through the consumer.
func read_xr(left: XRController3D, right: XRController3D, prev: Dictionary) -> void:
	source = Source.XR
	move = _stick(left)
	var turn := _stick(right)
	if absf(turn.x) > 0.7 and not prev.get("turn", false):
		snap = -signi(int(signf(turn.x)))
		prev["turn"] = true
	elif absf(turn.x) < 0.3:
		prev["turn"] = false

	# Exhale is on the trigger, either hand. Squeezing your hand while your chest empties is
	# the closest a controller gets to the real thing, and it leaves the grips free for rock.
	exhale = maxf(_trigger(left), _trigger(right))
	brake = _trigger(right)

	lower = _edge(prev, "lower", _stick_click(left) or _pressed(left, ["by_button"]))
	raise = _edge(prev, "raise", _stick_click(right))
	lamp = _edge(prev, "lamp", _pressed(left, ["ax_button"]) or _pressed(right, ["ax_button"]))
	slate = _edge(prev, "slate", _pressed(right, ["by_button"]))
	rope = _edge(prev, "rope", false)

	for i in 2:
		var c: XRController3D = left if i == 0 else right
		var h := hands[i]
		h.active = c != null
		if c:
			h.pose = c.global_transform
			h.grab = _grip(c)
			h.trigger = _trigger(c)

static func _stick(c: XRController3D) -> Vector2:
	if c == null:
		return Vector2.ZERO
	for n in ["thumbstick", "primary", "touchpad"]:
		var v: Vector2 = c.get_vector2(n)
		if v.length() > XR_DEAD_ZONE:
			return v.limit_length(1.0)
	return Vector2.ZERO

static func _stick_click(c: XRController3D) -> bool:
	return _pressed(c, ["primary_click", "thumbstick_click"])

static func _pressed(c: XRController3D, names: Array) -> bool:
	if c == null:
		return false
	for n: String in names:
		if c.is_button_pressed(n):
			return true
	return false

static func _trigger(c: XRController3D) -> float:
	if c == null:
		return 0.0
	return clampf(c.get_float("trigger"), 0.0, 1.0)

static func _grip(c: XRController3D) -> bool:
	if c == null:
		return false
	return c.is_button_pressed("grip_click") or c.get_float("grip") > 0.55

static func _edge(prev: Dictionary, key: String, down: bool) -> bool:
	var was: bool = prev.get(key, false)
	prev[key] = down
	return down and not was
