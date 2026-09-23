class_name Caver
extends CharacterBody3D
## You, in the cave. A CharacterBody3D under gravity that reads an Intent struct, asks
## CaverBody what shape it currently is, and moves only as far as the rock will let it.
##
## The interesting difference from an ordinary first-person controller is that movement is
## GATED rather than blocked. A normal controller pushes forward and lets the physics engine
## slide it along a wall; that is exactly the feeling a caving game must not have, because
## sliding is free and squeezing is not. Here the body measures the space around itself first
## (CaverBody.probe), decides what posture it can be, and then scales what you asked for by
## how much room there is. Contact pressure at 0.9 means you barely move whatever the stick
## says, and the scrape, the rumble and the closing vignette all come off the same number.
##
## Climbing is the one thing lifted almost unchanged from derelict-orbit: grip near rock and
## the hand is anchored to the world point it touched, then the body is driven so that hand
## returns to where it grabbed. In zero-G that was the whole locomotion system. Under gravity
## it is chimneying, stemming a rift and hauling yourself over breakdown, and it needed almost
## no changes to become those things.

const GRAVITY := 9.8
const TERMINAL := 14.0
const ACCEL := 9.0
const FRICTION := 13.0
const STEP_UP := 0.42          ## breakdown blocks you can just walk over
const SQUEEZE_CRAWL := 0.34    ## slowest the rock can make you: a shuffle, never a standstill
const CENTRING := 0.55         ## how hard the body feels for the middle of a tight gap
## The collision capsule is a centimetre and a half smaller than the body really is. CaverBody
## decides what fits - it measures the rock and picks the shape - and the capsule is only there
## for gross collision. Without the skin the two disagree at exactly the margin the whole cave
## is built around, and the physics wins an argument it should not be having.
const CAPSULE_SKIN := 0.015
## How long the capsule is when you are flat out. A metre is a torso and a bit; the old 1.30 m
## was a whole body, and the longer the capsule the more of a passage's curve it has to span at
## once.
const PRONE_LENGTH := 1.05
## Steeper than this and the surface is not a floor to lie on, it is a wall, and the capsule
## goes back to level rather than trying to stand on end.
const PRONE_UPRIGHT := 0.60   ## cos of about 53 degrees
const PRONE_SNAP := 0.10      ## how far a crawling body reaches down for the floor it left
const GRAB_REACH_XR := 0.20    ## sphere around the controller that counts as touching rock
const GRAB_REACH_FLAT := 1.9   ## how far in front of your eye the virtual hand can find rock
const GRAB_PULL := 3.2         ## how hard a hand can haul the body toward its anchor
const PULL_GAIN := 1.15        ## metres of virtual-hand travel per screen height dragged
const LOOK_SENS := 0.0022
const SNAP_ANGLE := 30.0
const HEAD_CLEAR := 0.16       ## closer than this to rock and the view starts to black out
const EYE_LERP := 7.0
const FALL_LIMIT := 12.0       ## seconds of freefall before the safety net decides you are lost

# What the hand marker says, unshaded so it reads the same in a lit chamber and in the dark.
const HAND_IDLE := Color(0.26, 0.25, 0.23)   ## nothing in reach
const HAND_NEAR := Color(0.30, 0.44, 0.55)   ## rock you could take hold of
const HAND_HELD := Color(0.42, 0.68, 0.38)   ## holding on
## Bottom LEFT on a flat screen: the survey slate has the right-hand corner.
const DESK_HAND_POS := Vector3(-0.235, -0.185, -0.52)

# VR comfort. Both are the derelict-orbit quads: unshaded, depth-test-disabled, glued to the
# camera, because a CanvasLayer is not visible in XR.
const FADE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
void fragment() { ALBEDO = tint.rgb; ALPHA = tint.a; }
"""

## The hand marker. Unshaded so a headlamp at point-blank range cannot blow it out, but with
## a fake key light baked in from the normal - without that every face is the same colour and
## a cube reads as a flat hexagon rather than an object.
const HAND_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 tint : source_color = vec3(0.26, 0.25, 0.23);
void fragment() {
	float key = 0.52 + 0.48 * clamp(dot(NORMAL, normalize(vec3(-0.35, 0.80, 0.48))), 0.0, 1.0);
	ALBEDO = tint * key;
}
"""

const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.04, 0.03, 0.02);
void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;
	ALBEDO = tint;
	ALPHA = smoothstep(0.22, 0.95, d) * strength;
}
"""

@onready var origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand
@onready var body_shape: CollisionShape3D = $BodyShape

var body := CaverBody.new()
var intent := Intent.new()
var started := false
var xr_active := false
## The fourth producer. When the autotest is writing the Intent struct itself, the desktop and
## XR producers have to keep their hands off it - which is only possible because there is a
## struct to write in the first place.
var scripted := false

var lamp: Lamp = null
var slate: Slate = null
var rope: Rope = null

var yaw := 0.0
var pitch := 0.0
var eye := 1.62                ## current, eased, height of the head above the feet
var fade_target := 1.0
var _fade := 1.0
var _vignette := 0.0

# Per-hand grab state. In VR both hands are real; flat and touch use slot 0 as a virtual hand
# that lives a fixed distance in front of the eye and is dragged around by the mouse/finger.
var _anchor := [Vector3.ZERO, Vector3.ZERO]
var _held := [false, false]
var _hand_local := [Vector3.ZERO, Vector3.ZERO]
var _hand_vel := [Vector3.ZERO, Vector3.ZERO]
var _hand_prev := [Vector3.ZERO, Vector3.ZERO]
var _xr_prev := {}

var _capsule := CapsuleShape3D.new()
var _fade_mat: ShaderMaterial
var _vig_mat: ShaderMaterial
var _hand_mesh := [null, null]
var _hand_mat := [null, null]
var _scrape: AudioStreamPlayer
var _last_pos := Vector3.ZERO
var _ground := Vector3.ZERO    ## the last place you were stood on something
var _falling := 0.0
var _floor_limit := -1e9       ## below this you are out of the cave; set from the cave data
var _said := ""                ## the advice currently on the HUD, and when to repeat it
var _say_again := 0.0
var rescues := 0               ## times the safety net has had to put you back. Asserted zero
                               ## by the route test: trimming too much punches a hole to the
                               ## void, and this is how that gets noticed.
var _probe_frame := 0

func _ready() -> void:
	Cave.caver = self
	motion_mode = MOTION_MODE_GROUNDED
	floor_max_angle = deg_to_rad(58.0)
	floor_snap_length = 0.35
	floor_stop_on_slope = true
	up_direction = Vector3.UP
	body_shape.shape = _capsule
	_build_view()
	_build_hands()
	Cave.phase_changed.connect(_on_phase)

# ---------------------------------------------------------------- setup

func _build_view() -> void:
	# Fade quad: the VR answer to putting your head through a wall. It is also the loading
	# fade and the respawn fade, exactly as in derelict-orbit.
	var fade := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(4, 4)
	fade.mesh = qm
	_fade_mat = ShaderMaterial.new()
	_fade_mat.shader = Shader.new()
	_fade_mat.shader.code = FADE_SHADER
	_fade_mat.set_shader_parameter("tint", Color(0, 0, 0, 1))
	fade.material_override = _fade_mat
	fade.position = Vector3(0, 0, -0.2)
	fade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fade.sorting_offset = 100.0
	camera.add_child(fade)

	var vig := MeshInstance3D.new()
	var vq := QuadMesh.new()
	vq.size = Vector2(0.9, 0.9)
	vig.mesh = vq
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = Shader.new()
	_vig_mat.shader.code = VIGNETTE_SHADER
	vig.material_override = _vig_mat
	vig.position = Vector3(0, 0, -0.21)
	vig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vig.sorting_offset = 99.0
	camera.add_child(vig)

	_scrape = AudioStreamPlayer.new()
	_scrape.bus = "Master"
	add_child(_scrape)

func _build_hands() -> void:
	# A gloved fist, near enough. The mesh only exists so you can see where your hand is and
	# whether it has found something to hold, so it is retinted every frame rather than
	# animated - and it is unshaded, because it lives 50 cm from a headlamp putting out 5.2
	# and anything lit at that range comes back as a white block. Unshaded means the tint IS
	# the reading: dark for nothing, blue for rock in reach, green for holding on.
	for i in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.055, 0.048, 0.095)
		mi.mesh = bm
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = HAND_SHADER
		m.set_shader_parameter("tint", HAND_IDLE)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hand_mat[i] = m
		_hand_mesh[i] = mi
		if i == 0:
			left_hand.add_child(mi)
		else:
			right_hand.add_child(mi)

func begin(xr: bool) -> void:
	xr_active = xr
	started = true
	if Cave.cave:
		_floor_limit = Cave.cave.floor_limit()
	if not xr:
		# Flat play has no local-floor reference space, so the head is placed by hand and the
		# hand meshes belong to the camera rather than to controllers that do not exist.
		camera.position = Vector3(0, eye, 0)
		for i in 2:
			var mi: MeshInstance3D = _hand_mesh[i]
			mi.get_parent().remove_child(mi)
			camera.add_child(mi)
			mi.visible = i == 0
			mi.position = DESK_HAND_POS
	if lamp:
		lamp.set_shadow_allowed(shadow_allowed())

## The headlamp shadow is the whole look of the game and also, by a distance, the most
## expensive thing in it - a shadow map re-rendered every frame for everything in the cone.
## Same gate as derelict-orbit's flashlight: desktop, high graphics, flat only.
func shadow_allowed() -> bool:
	return started and not xr_active and not Cave.low_quality

func teleport(p: Vector3, look_dir := Vector3.ZERO) -> void:
	global_position = p
	velocity = Vector3.ZERO
	_last_pos = p
	for i in 2:
		_held[i] = false
	if look_dir != Vector3.ZERO:
		yaw = atan2(-look_dir.x, -look_dir.z)
		pitch = clampf(asin(clampf(look_dir.normalized().y, -1.0, 1.0)), -1.45, 1.45)
		origin.rotation.y = yaw
		if not xr_active:
			camera.rotation.x = pitch
	if is_inside_tree():
		_fit_here()

## Measure and fold before the first physics step, so a body dropped into a crawl arrives
## already the right shape. Without this it lands standing, a capsule twice the width of the
## passage, and move_and_slide ejects it through the wall - which it will do for a warm-up
## tour and a respawn as readily as for a test. Two passes, because where the chest sits
## depends on the posture and the posture depends on what the chest can see.
func _fit_here() -> void:
	var space := get_world_3d().direct_space_state
	for pass_ in 2:
		body.probe(space, chest_point(), _body_frame(), global_position)
		body.choose_posture(false, false, 1.0)
	eye = body.eye_height()
	_shape_body()

func _on_phase(p: int) -> void:
	if p == Cave.Phase.CAVING:
		fade_target = 0.0

# ---------------------------------------------------------------- the frame

func _physics_process(delta: float) -> void:
	if not started:
		return
	_read_input(delta)

	var frame := _body_frame()
	var chest_pt := chest_point()
	# The ring is twelve raycasts; at 72 Hz that is 864 a second, which is nothing, but the
	# headroom and width casts on top of it are not worth doing twice in a frame either.
	body.probe(get_world_3d().direct_space_state, chest_pt, frame, global_position)
	body.breathe(intent.exhale, delta)
	body.choose_posture(intent.lower, intent.raise, delta)
	body.update_wedge(intent.move.y > 0.25, global_position, delta)

	_shape_body()
	_move(delta, frame)
	_climb(delta)
	move_and_slide()

	_track_progress()
	_advise(delta)
	_safety_net(delta)
	if rope:
		rope.caver_moved(self, intent, delta)
	intent.clear_edges()

## Nobody should ever fall out of the world. A cave is a hollow shell with nothing outside it,
## so a body that gets through the rock - or is put somewhere it should not be - falls until
## the floating point runs out, and there is no way back.
##
## This catches both shapes of that: falling below the cave entirely, and falling for longer
## than any drop in it lasts. Either way you go back to the last place you were stood on
## something, which is always somewhere you can get out of.
func _safety_net(delta: float) -> void:
	if is_on_floor() or (rope and rope.clipped):
		if not body.wedged:
			_ground = global_position
		_falling = 0.0
		return
	_falling += delta
	var below: bool = global_position.y < _floor_limit
	if not below and _falling < FALL_LIMIT:
		return
	var back: Vector3 = _ground
	if back == Vector3.ZERO and Cave.cave:
		back = Cave.cave.start_point
	teleport(back + Vector3(0, 0.25, 0))
	rescues += 1
	_falling = 0.0
	Cave.say("you came off - back on your feet" if not below else "out of the cave - back you go", 3.0)

## Put the body's advice where the player is looking.
##
## It was on the survey slate and nowhere else, and the slate is an object on your wrist that
## you have to decide to look at. So a player met the Devil's Pinch with a full chest, got held
## by 1.5 cm of rock, saw the view close in and nothing else, and reported an impassable dead
## end in a tunnel - which from inside the game is exactly what it was. The cave's whole central
## mechanic was invisible at the one moment it mattered.
##
## Repeated rather than fired once, because being stuck is a state and not an event: the HUD
## clears itself after a few seconds and the rock does not.
const ADVICE_REPEAT := 2.5
const ADVICE_CRAWL := 0.03   ## moving slower than this counts as being stopped

func _advise(delta: float) -> void:
	var say := body.advice()
	# "Tight - try breathing out" is true for most of the Flatiron and saying so for twenty-five
	# metres is nagging, not advice. On the HUD it waits until the rock has actually stopped you;
	# the slate keeps showing it the whole time, which is what a slate is for.
	if say != "" and not body.wedged and not body.air_locked \
			and Vector3(velocity.x, 0.0, velocity.z).length() > ADVICE_CRAWL:
		say = ""
	_say_again -= delta
	if say == _said and (say == "" or _say_again > 0.0):
		return
	_said = say
	_say_again = ADVICE_REPEAT
	if say != "":
		Cave.say(say, ADVICE_REPEAT + 0.6)

func _read_input(delta: float) -> void:
	if scripted:
		pass   # the autotest is the producer this frame; do not overwrite what it wrote
	elif xr_active:
		intent.read_xr(left_hand, right_hand, _xr_prev)
		if intent.snap != 0:
			_snap_turn(float(intent.snap) * SNAP_ANGLE)
	elif Cave.touch:
		pass   # TouchControls writes straight into `intent` in its own _process
	else:
		intent.read_desktop(camera, GRAB_REACH_FLAT)

	if intent.lamp and lamp:
		lamp.toggle_main()
	if intent.backup and lamp:
		lamp.toggle_backup()
	if intent.slate and slate:
		slate.toggle()

## The body's own frame: x across the passage, y up it, z back the way you came. The ring is
## cast in the x/y plane, so it measures the cross-section you have to fit through rather than
## an arbitrary horizontal slice - which matters the moment a passage tilts.
func _body_frame() -> Basis:
	var fwd := -origin.global_transform.basis.z
	if xr_active:
		var head := -camera.global_transform.basis.z
		fwd = Vector3(head.x, 0.0, head.z)
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var across := Vector3.UP.cross(fwd).normalized()
	return Basis(across, fwd.cross(across).normalized(), -fwd)

func chest_point() -> Vector3:
	# Where the widest part of you is: roughly at the eye when upright, and just off the floor
	# when you are flat out. It is the point the ring is cast from, so it decides what "tight"
	# means, and it has to be the chest rather than the head.
	var h: float = body.eye_height()
	return global_position + Vector3.UP * (h * 0.78 + 0.06)

## Resize the capsule to whatever shape we currently are. Prone postures lie it down along the
## direction of travel, because a standing capsule in a 34 cm bedding crawl is a sphere that
## cannot get anywhere.
##
## And prone postures lie it down along the FLOOR, not along the horizon. A body flat out is a
## metre of capsule pointing where you are going; leave it level in a passage that is dropping
## at thirty degrees and its nose is a third of a metre higher than the roof in front of it, so
## it jams - on nothing, in a tunnel with plenty of room, exactly like an invisible wall. The
## whole reason for a passage with real climbs and drops in it is that you feel the ground
## tilt, and that is worth nothing if the collider refuses to tilt with it.
func _shape_body() -> void:
	var b := body.box()
	var prone: bool = body.posture >= CaverBody.BELLY and body.name_of() != "commit"
	if prone:
		_capsule.radius = clampf(b.y * 0.5 - CAPSULE_SKIN, 0.07, 0.30)
		_capsule.height = maxf(PRONE_LENGTH, _capsule.radius * 2.0 + 0.02)
		var up := _floor_up()
		body_shape.basis = _prone_basis(up)
		# Offset along the FLOOR NORMAL, not along world up. The capsule turns about its own
		# centre, so a body lying at thirty degrees with its centre a radius above the origin
		# has its back end a quarter of a metre underneath the floor - and a trimesh with
		# backface collision on is perfectly happy to keep it there, reading four centimetres of
		# headroom in a passage 60 cm tall and folding the body down to superman inside the
		# rock. Along the normal, the capsule sits on the slope however steep the slope is.
		body_shape.position = up * (_capsule.radius + 0.01)
	else:
		# In `commit` the width IS the mechanic, so the skin has to get out of its way. A
		# centimetre and a half either side is three centimetres of slack, and the whole exhale
		# is worth three and a half: at full skin a relaxed chest slides through the crux the
		# body model says is shut, which is the one thing the Devil's Pinch must never do.
		var skin: float = CAPSULE_SKIN * (0.25 if body.name_of() == "commit" else 1.0)
		_capsule.radius = clampf(minf(b.x, 0.46) * 0.5 - skin, 0.09, 0.28)
		_capsule.height = maxf(b.y, _capsule.radius * 2.0 + 0.02)
		body_shape.basis = Basis.IDENTITY
		body_shape.position = Vector3(0, _capsule.height * 0.5, 0)

## The surface under the body, as an up vector, clamped to a tilt a body would actually lie at.
## Only trusted while there IS a floor: in the air you lie level, which is both correct and what
## this did before it could tilt at all.
func _floor_up() -> Vector3:
	var up := get_floor_normal() if is_on_floor() else Vector3.UP
	if up.length_squared() < 0.001 or up.y < PRONE_UPRIGHT:
		return Vector3.UP
	return up.normalized()

## The frame a lying-down capsule takes: long axis along the floor, pointing where you are going.
func _prone_basis(up: Vector3) -> Basis:
	var fwd := -origin.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	if absf(up.dot(fwd)) > 0.98:
		return Basis(Vector3.UP.cross(fwd).normalized(), fwd, Vector3.UP)
	# The capsule's long axis is its LOCAL Y.
	var along := (fwd - up * fwd.dot(up)).normalized()
	var side := up.cross(along).normalized()
	return Basis(side, along, side.cross(along).normalized())

# ---------------------------------------------------------------- moving

func _move(delta: float, frame: Basis) -> void:
	var on_rope: bool = rope != null and rope.clipped
	if not is_on_floor() and not intent.any_grab() and not on_rope:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -TERMINAL)
	elif is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0

	var fwd := -frame.z
	var side := frame.x
	var wish := (fwd * intent.move.y + side * intent.move.x).limit_length(1.0)

	# What the rock allows. Pressure alone would let you crawl into a pinch at full speed and
	# stop dead; easing it out means the passage slows you down before it stops you, which is
	# the only warning a real one gives.
	#
	# The floor matters as much as the curve. A squeeze you fit through is slow, not still -
	# four centimetres a second with rock on both shoulders, twenty-odd seconds to cross the
	# Devil's Pinch. Floor it any lower and a passage you genuinely fit is indistinguishable
	# from one you do not, which is exactly the distinction the game is about.
	var room: float = 1.0 - smoothstep(0.35, 0.94, body.pressure)
	var target_speed: float = body.speed() * maxf(room, SQUEEZE_CRAWL)
	if body.wedged:
		# Forward does nothing. Backwards, and changing shape, still work - that is the way out.
		if intent.move.y > 0.0:
			wish -= fwd * intent.move.y
		target_speed = minf(target_speed, 0.20)
	if intent.brake > 0.5:
		target_speed *= 0.25

	# Line yourself up in the gap. Only bites when it is actually tight, and it is what turns
	# "the numbers say I fit but I am stuck" into a squeeze you can work through.
	var centre_pull: float = body.centring() * body.pressure * CENTRING
	if absf(centre_pull) > 0.001:
		wish += frame.x * centre_pull

	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if wish.length_squared() > 0.0001:
		flat = flat.move_toward(wish * target_speed, ACCEL * delta)
	else:
		flat = flat.move_toward(Vector3.ZERO, FRICTION * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	# Breakdown is a floor of loose blocks; without a step-up you catch on every one of them.
	#
	# One floor angle for every posture, and a steep one.
	#
	# Prone used to get 40 degrees and upright 58, which is backwards - flat out you have four
	# points of contact and your weight spread along the rock - and the moment the passages had
	# real gradients in them the crawls started coming off the floor on a thirty-degree ramp:
	# airborne, the capsule stops tilting with the slope, gravity takes over, and the body
	# slithers instead of crawling. Splitting the difference was worse than either, because 52
	# turns the 57-degree lip at the Gullet's mouth from something you walk over into a wall.
	#
	# Snap is unconditional for the same reason the angle is generous. The usual reason to drop
	# it while airborne is so a jump reads as a jump, and there is no jumping in a cave - there
	# is rock you are on and rock you have briefly bounced off, and the second should end fast.
	#
	# But it is SHORT when you are flat out. 42 cm is the height of a breakdown block you step
	# over in a room; in a 60 cm crawl it is most of the passage, and the cave is a shell one
	# triangle thick with nothing behind it - so a body that leaves a thirty-degree floor for an
	# instant snaps straight through it and ends up thirteen centimetres inside the rock,
	# reporting four centimetres of headroom and folding itself down to superman. Enough to stay
	# glued to a slope is all it needs.
	floor_max_angle = deg_to_rad(58.0)
	floor_snap_length = STEP_UP if body.posture <= CaverBody.KNEES else PRONE_SNAP

## Grip near rock and the hand is pinned to the world point it found; the body is then driven
## so that hand goes back to where it grabbed. Straight out of derelict-orbit's player.gd,
## where it was the entire locomotion system in zero-G. Under gravity the same three lines are
## climbing, chimneying and hauling over breakdown, and a hand on the rock also stops you
## falling, which is what a hand on the rock is for.
func _climb(delta: float) -> void:
	var pulling := false
	for i in 2:
		var h: Intent.Hand = intent.hands[i]
		if not h.active:
			_held[i] = false
			continue
		var hand_pos := _hand_world(i, h)
		_hand_vel[i] = _hand_vel[i].lerp((hand_pos - _hand_prev[i]) / maxf(delta, 0.0001), 0.5)
		_hand_prev[i] = hand_pos

		if h.grab and not _held[i]:
			var found := _rock_near(i, h, hand_pos)
			if found != Vector3.INF:
				_held[i] = true
				_anchor[i] = found
				if not xr_active:
					_hand_local[i] = camera.global_transform.affine_inverse() * found
				Sfx.play("grab", -14.0, randf_range(0.9, 1.1))
		elif not h.grab and _held[i]:
			_held[i] = false
			# Let go with whatever the hand was doing, the way you push off a wall.
			if xr_active:
				velocity += _hand_vel[i].limit_length(2.4) * 0.4

		if _held[i]:
			if not xr_active and h.pull != Vector2.ZERO:
				var b := camera.global_transform.basis
				_hand_local[i] += (b.x * h.pull.x + b.y * h.pull.y).normalized() * h.pull.length() * PULL_GAIN
				_hand_local[i] = camera.global_transform.affine_inverse() * (camera.global_transform * _hand_local[i])
			var now := _hand_world(i, h)
			var anchor: Vector3 = _anchor[i]
			var pull := (anchor - now) / maxf(delta, 0.0001)
			velocity = velocity.lerp(pull.limit_length(GRAB_PULL), 0.55)
			pulling = true

	for i in 2:
		var mat: ShaderMaterial = _hand_mat[i]
		if mat:
			var c := HAND_IDLE
			if _held[i]:
				c = HAND_HELD
			elif intent.hands[i].active and _rock_near(i, intent.hands[i], _hand_world(i, intent.hands[i])) != Vector3.INF:
				c = HAND_NEAR
			var now: Color = mat.get_shader_parameter("tint")
			mat.set_shader_parameter("tint", now.lerp(c, 0.25))
	if pulling:
		velocity.y = maxf(velocity.y, -1.2)

func _hand_world(i: int, h: Intent.Hand) -> Vector3:
	if xr_active:
		return h.pose.origin
	if _held[i]:
		return camera.global_transform * _hand_local[i]
	return h.pose.origin

## Is there rock within reach of this hand? In VR it is a sphere around the controller, the
## way derelict-orbit does it; flat and touch cast a ray from the eye, because a virtual hand
## floating in front of you has no business feeling for walls it cannot see.
func _rock_near(i: int, h: Intent.Hand, hand_pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if xr_active:
		var q := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = GRAB_REACH_XR
		q.shape = sphere
		q.transform = Transform3D(Basis.IDENTITY, hand_pos)
		q.collision_mask = 1
		var hits := space.intersect_shape(q, 1)
		return hand_pos if not hits.is_empty() else Vector3.INF
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	if i == 0 and h.pose != Transform3D.IDENTITY:
		dir = (h.pose.origin - from).normalized() if h.pose.origin.distance_to(from) > 0.05 else dir
	var ray := PhysicsRayQueryParameters3D.create(from, from + dir * GRAB_REACH_FLAT, 1)
	var hit := space.intersect_ray(ray)
	return hit["position"] if not hit.is_empty() else Vector3.INF

# ---------------------------------------------------------------- head, view, feedback

func _process(delta: float) -> void:
	if not started:
		return
	_ease_head(delta)
	_feedback(delta)

func _ease_head(delta: float) -> void:
	eye = lerpf(eye, body.eye_height(), clampf(delta * EYE_LERP, 0.0, 1.0))
	if not xr_active:
		camera.position = Vector3(0, eye, 0)
		return
	# In VR the headset owns the pose, so the body height is applied to the ORIGIN and the
	# camera is left alone. Physically crouching therefore crouches you in the cave, and the
	# posture the rock forces on you moves the floor under your feet to meet it.
	var real: float = maxf(camera.position.y, 0.1)
	origin.position.y = clampf(eye - real, -1.4, 0.4)

## Everything the rock does to you that is not movement. Pressure drives all of it, because
## pressure is the one number that knows how close the cave is.
func _feedback(delta: float) -> void:
	var p: float = body.pressure

	var want_vig: float = clampf((p - 0.30) / 0.60, 0.0, 1.0) * 0.85
	if body.wedged:
		want_vig = maxf(want_vig, 0.95)
	_vignette = lerpf(_vignette, want_vig, clampf(delta * 4.0, 0.0, 1.0))
	_vig_mat.set_shader_parameter("strength", _vignette)

	# Head clearance is its own thing, separate from pressure: in VR you can lean your head
	# into rock the body model knows nothing about, and the honest answer is to go black
	# rather than show you the inside of the world.
	var head_gap := _head_clearance()
	var want_fade: float = fade_target
	if head_gap < HEAD_CLEAR:
		want_fade = maxf(want_fade, 1.0 - clampf(head_gap / HEAD_CLEAR, 0.0, 1.0))
	_fade = move_toward(_fade, want_fade, delta * (2.6 if want_fade > _fade else 1.6))
	_fade_mat.set_shader_parameter("tint", Color(0, 0, 0, _fade))

	Sfx.set_scrape(_scrape, p, velocity.length())
	Sfx.set_breath(body.exhale, body.air, p)
	if xr_active and p > 0.55:
		var amp: float = clampf((p - 0.55) / 0.45, 0.0, 1.0) * 0.35
		if velocity.length() > 0.05:
			for c in [left_hand, right_hand]:
				c.trigger_haptic_pulse("haptic", 0.0, amp, 0.06, 0.0)
	elif Cave.touch and p > 0.85 and velocity.length() > 0.05:
		if randf() < 0.05:
			Input.vibrate_handheld(18)

func _head_clearance() -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.22
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	q.collision_mask = 1
	var rest := space.get_rest_info(q)
	if rest.is_empty():
		return 1.0
	return maxf(camera.global_position.distance_to(rest["point"]), 0.0)

func _snap_turn(deg: float) -> void:
	var before := camera.global_position
	origin.rotation.y += deg_to_rad(deg)
	origin.global_position += before - camera.global_position
	_vignette = maxf(_vignette, 0.7)

func _track_progress() -> void:
	var moved := global_position.distance_to(_last_pos)
	if moved > 0.002 and moved < 2.0:
		Cave.travelled += moved
	_last_pos = global_position
	Cave.note_depth(global_position.y)
	if Cave.cave and Cave.cave.has_method("passage_at"):
		var p: Dictionary = Cave.cave.passage_at(global_position)
		if not p.is_empty():
			Cave.enter_passage(p["id"], p["label"], bool(p.get("lead", false)))

# ---------------------------------------------------------------- flat look

func _unhandled_input(e: InputEvent) -> void:
	if not started or xr_active:
		return
	if e is InputEventMouse and (Cave.touch or e.device == InputEvent.DEVICE_ID_EMULATION):
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := e as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _held[0]:
			# Right mouse held with a grip on the rock drags the hand, not the view: that is
			# how you haul yourself up something on a flat screen.
			intent.hands[0].pull += Vector2(m.relative.x, -m.relative.y) / 600.0
			return
		yaw -= m.relative.x * LOOK_SENS
		var dy: float = m.relative.y * LOOK_SENS * (-1.0 if Cave.invert_look else 1.0)
		pitch = clampf(pitch - dy, -1.45, 1.45)
		origin.rotation.y = yaw
		camera.rotation.x = pitch
	elif e is InputEventMouseButton and e.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ---------------------------------------------------------------- touch hooks

func touch_look(rel: Vector2) -> void:
	yaw -= rel.x * LOOK_SENS * 1.35
	pitch = clampf(pitch - rel.y * LOOK_SENS * 1.35 * (-1.0 if Cave.invert_look else 1.0), -1.45, 1.45)
	origin.rotation.y = yaw
	camera.rotation.x = pitch

func touch_grab_begin(screen: Vector2) -> bool:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * GRAB_REACH_FLAT, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	intent.hands[0].active = true
	intent.hands[0].grab = true
	_held[0] = true
	_anchor[0] = hit["position"]
	_hand_local[0] = camera.global_transform.affine_inverse() * _anchor[0]
	Sfx.play("grab", -14.0, randf_range(0.9, 1.1))
	return true

func touch_grab_end() -> void:
	intent.hands[0].grab = false
	_held[0] = false

func touch_pull(rel: Vector2) -> void:
	intent.hands[0].pull += rel

# ---------------------------------------------------------------- test hooks
#
# Used by CAVE_AUTOTEST. They live on the production class on purpose, the way
# derelict-orbit's player.gd:1002-1030 does: a test that drives the real code through the
# real entry points is worth more than one that pokes at a copy of it.

func debug_move(dir: Vector2) -> void:
	scripted = true
	intent.move = dir.limit_length(1.0)

func debug_exhale(v: float) -> void:
	scripted = true
	intent.exhale = clampf(v, 0.0, 1.0)

func debug_brake(v: float) -> void:
	scripted = true
	intent.brake = clampf(v, 0.0, 1.0)

func debug_face(dir: Vector3) -> void:
	teleport(global_position, dir)

func debug_state() -> Dictionary:
	return {
		"posture": body.name_of(),
		"chest": body.chest,
		"pressure": body.pressure,
		"headroom": body.headroom,
		"width": body.width,
		"wedged": body.wedged,
		"air": body.air,
		"depth": -global_position.y,
	}

## What the body is actually touching, and how far the actual capsule could actually go.
##
## Rays fired from a point say what is in front of your nose. They cannot see the thing that
## stops a CharacterBody3D, which is the capsule catching on rock a ray missed by a few
## centimetres - and every diagnosis made from rays alone in this cave has been wrong. So this
## reports the collider, not a model of it: the shape, where the last move_and_slide hit rock
## and which way that rock faced, whether the capsule is already overlapping something, and how
## far a swept cast of that same capsule gets before it jams.
func debug_contacts(heading: Vector3) -> Array[String]:
	var out: Array[String] = []
	out.append("  asked %s, facing %s, velocity %s, centring %+.2f, tightest %s, held %s/%s"
		% [intent.move, _short(-origin.global_transform.basis.z), _short(velocity),
			body.centring() * body.pressure * CENTRING, _short(body.tightest_dir),
			_held[0], _held[1]])
	out.append("capsule r %.3f h %.3f at %+.2f m, %s, on floor %s%s, vel %.3f m/s (y %+.2f)"
		% [_capsule.radius, _capsule.height, body_shape.position.y,
			"lying down" if absf(body_shape.rotation.x) > 0.1 else "upright",
			is_on_floor(), ", floor at %.0f deg" % rad_to_deg(get_floor_angle())
				if is_on_floor() else "",
			Vector3(velocity.x, 0.0, velocity.z).length(), velocity.y])

	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		# A normal pointing up is floor; one pointing along the passage is a wall across it.
		var facing: String = "floor" if n.y > 0.7 else ("roof" if n.y < -0.7 else "wall")
		out.append("  touching %s (%s) at %s, normal %s, %.0f deg off level, pushes %s"
			% [c.get_collider().name if c.get_collider() else "?", facing,
				_short(c.get_position()), _short(n), rad_to_deg(acos(clampf(n.y, -1.0, 1.0))),
				"you on" if n.dot(heading) > 0.2 else
					("you back" if n.dot(heading) < -0.2 else "sideways")])
	if get_slide_collision_count() == 0:
		out.append("  touching nothing at all")

	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _capsule
	q.transform = body_shape.global_transform
	q.collision_mask = 1
	q.exclude = [get_rid()]
	q.margin = 0.0

	# Already inside the rock? Then nothing about the passage ahead matters. collide_shape hands
	# back pairs of points - one on the capsule, one on the rock - and the gap between a pair is
	# how deep it is in.
	var rest := space.get_rest_info(q)
	if rest.is_empty():
		out.append("  capsule is clear of the rock where it stands")
	else:
		var deepest := 0.0
		var pairs := space.collide_shape(q, 8)
		for i in range(0, pairs.size() - 1, 2):
			deepest = maxf(deepest, pairs[i].distance_to(pairs[i + 1]))
		out.append("  capsule is INSIDE rock at %s, %.3f m deep, normal %s"
			% [_short(rest["point"]), deepest, _short(rest["normal"])])

	# And how far it can actually be swept, which is the number the rays were standing in for.
	var dir := Vector3(heading.x, 0.0, heading.z).normalized()
	for motion: Vector3 in [dir * 2.0, (dir + Vector3.DOWN * 0.3).normalized() * 2.0,
			Vector3.DOWN * 0.6]:
		q.motion = motion
		var span := space.cast_motion(q)
		out.append("  sweep %s: %.2f m of %.2f" % [_short(motion.normalized()),
			span[0] * motion.length(), motion.length()])
	return out

func _short(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
