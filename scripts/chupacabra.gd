extends Node3D
class_name Chupacabra
## The thing on board that drinks.
##
## The 1995 Puerto Rican one - the Canovanas sightings - not the mangy Texas coyote the name got
## attached to a decade later. Bipedal, waist height, grey-green and leathery, enormous black oval
## eyes with nothing in them, a row of spines down its back that stand up when it has decided
## about you, small clawed forelimbs held against the chest, no tail. It does not run. It hops,
## and the hops are far too long for the size of it.
##
## What that folklore is actually famous for is not the encounter, it is the evidence: stock found
## in the morning, not torn up and not eaten - drained, through two neat punctures, nothing
## spilled. On Kestrel-9 the things that hold pressure are the loose canisters, the coolant drums
## and the power cells, and you keep finding it crouched over one with its head down.
##
## In a station with no floor a hopper is worse than a walker. It kicks off a wall and crosses the
## corridor in one go, and it is gone before you have finished deciding what it was.

const RIG := "res://kit/chupacabra_rig.json"
const NOTICE_DIST := 5.0        # this close and it knows
const STARE_TIME := 1.4         # or you looked at it this long
const ALERT_HOLD := 0.7         # crest up, staring back, deciding
const COIL_HOLD := 0.22         # the spring loading
const LEAP_SPEED := 7.5
const LEAP_TIME := 1.8

signal bolted

enum State { FEEDING, ALERT, COIL, LEAP }

var body: Creature
var prop_index := -1
var _state: int = State.FEEDING
var _t := 0.0
var _looked := 0.0
var _life := 26.0
var _vel := Vector3.ZERO
var _prop: Node3D = null

func _ready() -> void:
	body = Creature.new()
	body.rig_path = RIG
	body.autopose = false          # this one does not twitch on a timer; it is doing something
	body.glitch = 0.0
	add_child(body)
	body.set_pose("feed", true)

## Crouch over station prop `index` and start feeding. Returns false if the prop is gone.
func feed_on(index: int, face: Vector3) -> bool:
	var st: Station = Game.station
	_prop = st.take_prop(index)
	if _prop == null:
		return false
	prop_index = index
	global_position = _prop.global_position + Vector3(0, -0.28, 0)
	var f := face
	f.y = global_position.y
	if f.distance_to(global_position) > 0.01:
		look_at(f, Vector3.UP)
	return true

func _process(delta: float) -> void:
	_t += delta
	if Game.player == null:
		return
	var cam: Camera3D = Game.player.camera
	var to := global_position - cam.global_position
	var dist := to.length()

	match _state:
		State.FEEDING:
			# head down in the thing, and it does not look up while it does this - which is the
			# only reason anyone has ever got close to one
			if is_instance_valid(_prop):
				_prop.global_position = global_position + Vector3(0, 0.28, 0)
				_prop.rotation += Vector3(0.1, 0.15, 0.05) * delta
			if (-cam.global_transform.basis.z).dot(to.normalized()) > 0.9:
				_looked += delta
			_life -= delta
			if dist < NOTICE_DIST or _looked > STARE_TIME:
				_alert()
			elif _life <= 0.0:
				_bolt()
		State.ALERT:
			# every spine up, staring straight back, working out which way to go
			if _t >= ALERT_HOLD:
				_state = State.COIL
				_t = 0.0
				body.set_pose("coil", true)
		State.COIL:
			if _t >= COIL_HOLD:
				_bolt()
		State.LEAP:
			global_position += _vel * delta
			_vel = _vel.lerp(Vector3.ZERO, 0.25 * delta)
			if _t >= LEAP_TIME:
				queue_free()

func _alert() -> void:
	if _state != State.FEEDING:
		return
	_state = State.ALERT
	_t = 0.0
	body.set_pose("alert", true)
	_drop_prop()
	Sfx.play_at("breath", global_position, -2.0, 22.0, 1.7)

## Off the wall. Away from whoever is watching, never through them: this is a scare, not the night.
func _bolt() -> void:
	if _state == State.LEAP:
		return
	_drop_prop()
	_state = State.LEAP
	_t = 0.0
	body.set_pose("leap", true)
	var away := global_position - Game.player.camera.global_position
	away.y = 0.0
	if away.length() < 0.1:
		away = -global_transform.basis.z
	away = away.normalized()
	# it kicks off along the corridor with a bit of up in it - it is aiming at a far wall
	_vel = (away + Vector3(0, randf_range(0.05, 0.35), 0)).normalized() * LEAP_SPEED
	look_at(global_position + away, Vector3.UP)
	Sfx.play_at("bang", global_position, -12.0, 24.0, 1.8)
	bolted.emit()

## Let go of whatever it had. It leaves the husk: that is the whole story about this animal.
func _drop_prop() -> void:
	if prop_index < 0:
		return
	Game.station.release_prop(prop_index, Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4)),
		Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)))
	prop_index = -1
	_prop = null
