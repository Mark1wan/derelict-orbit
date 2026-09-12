extends Node3D
class_name Stalker
## The thing that walks the station at night.
## It only advances when your flashlight is NOT on it. Light freezes it (until later nights,
## when it starts to push through the beam). It navigates the hub/corridor graph toward your head.

signal caught

var speed := 0.6
var lit_factor := 0.0        # speed multiplier while illuminated
var teleport_enabled := false
var body: Creature
var _unseen := 0.0
var _breath: AudioStreamPlayer3D
var _done := false
var _t := 0.0

func _ready() -> void:
	var I := Game.intensity()
	speed = 0.45 + 0.12 * I
	lit_factor = 0.0 if I < 5.0 else 0.3
	teleport_enabled = I >= 4.0

	body = Creature.new()
	body.name = "Body"
	# the rig's origin is under its feet; the stalker node itself sits at head height, where the
	# navigation and the catch test want it
	body.position = Vector3(0, -1.2, 0)
	body.glitch = 0.7 + 0.25 * I
	body.step_time = clampf(0.5 - 0.04 * I, 0.16, 0.5)
	add_child(body)

	_breath = AudioStreamPlayer3D.new()
	_breath.stream = Sfx.streams.get("breath")
	_breath.max_distance = 16.0
	_breath.volume_db = -4.0
	_breath.unit_size = 2.0
	add_child(_breath)
	_breath.play()

func is_lit(player: Player) -> bool:
	if not player.flashlight_on:
		return false
	var fl: SpotLight3D = player.flashlight
	var from := fl.global_position
	var to := global_position
	var v := to - from
	var dist := v.length()
	if dist > fl.spot_range or dist < 0.01:
		return dist < 0.01
	var fwd := -fl.global_transform.basis.z
	var ang := rad_to_deg(acos(clampf(fwd.dot(v / dist), -1.0, 1.0)))
	if ang > fl.spot_angle * 0.95:
		return false
	return Game.station.has_line_of_sight(from, to)

func _process(delta: float) -> void:
	if _done or Game.phase != Game.Phase.NIGHT or Game.player == null:
		return
	_t += delta
	var player: Player = Game.player
	var head: Vector3 = player.camera.global_position
	var to_head := head - global_position
	var dist := to_head.length()

	var lit := is_lit(player)
	var s := speed * (lit_factor if lit else 1.0)
	var target: Vector3 = Game.station.next_waypoint(global_position, head)
	var dir: Vector3 = target - global_position
	var walking := s > 0.02 and dir.length() > 0.05
	if walking:
		global_position += dir.normalized() * s * delta
	# in the beam it stops and stands up, which is worse than it moving
	body.moving = walking
	body.glitch = 0.15 if lit else 0.7 + 0.25 * Game.intensity()
	# always face the player; never look up/down
	var face := Vector3(head.x, global_position.y, head.z)
	if face.distance_to(global_position) > 0.05:
		look_at(face, Vector3.UP)
	global_position.y += sin(_t * 1.3) * 0.12 * delta   # slow bob, frame-rate independent

	# if you refuse to look for long enough, it closes distance without walking
	var cam_fwd := -player.camera.global_transform.basis.z
	var looking := cam_fwd.dot(to_head.normalized()) < -0.2
	if teleport_enabled and not looking and not lit and dist > 7.0:
		_unseen += delta
		if _unseen > 9.0:
			_unseen = 0.0
			var jump: Vector3 = Game.station.next_waypoint(global_position, head)
			global_position = global_position.move_toward(jump, 3.0)
			Sfx.play_at("bang", global_position, -6.0, 30.0, 0.7)
	else:
		_unseen = 0.0

	# heartbeat scales with proximity
	var rate := clampf(1.0 - (dist - 1.0) / 10.0, 0.0, 1.0)
	Sfx.set_heartbeat(dist < 11.0, rate)
	_breath.pitch_scale = 1.0 if not lit else 0.8

	if dist < 0.95:
		_done = true
		Sfx.set_heartbeat(false)
		caught.emit()

## Jumpscare pose: teleport right in front of the face.
func lunge(player: Player) -> void:
	var cam: Camera3D = player.camera
	var fwd := -cam.global_transform.basis.z
	global_position = cam.global_position + fwd * 0.55 + Vector3(0, -0.55, 0)
	look_at(cam.global_position, Vector3.UP)
	body.lunge_pose()
	body.set_eye_glow(4.0)
	_breath.stop()
