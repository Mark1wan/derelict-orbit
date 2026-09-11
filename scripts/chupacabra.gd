extends Node3D
class_name Chupacabra
## The thing on board that watches from corners.
##
## The 1995 Puerto Rican one - the Canovanas sightings - not the mangy Texas coyote the name got
## attached to a decade later. Bipedal, waist height, grey-green and leathery, enormous black oval
## eyes with nothing in them, a row of spines down the back that stand up when it has decided
## about you, small clawed forelimbs held against the chest, no tail. It does not run. It hops,
## and the hops are far too long for the size of it.
##
## What you get, almost every time, is not a creature. It is a corner with something at the bottom
## of it: the body is round the edge and stays there, and what is out in the corridor with you is
## a head craned back over a shoulder, and the eyes. You look at it. It looks at you. And then it
## is not there, and the corner is a corner.
##
## Roughly one time in four it does not do you the courtesy of leaving quietly: it comes off the
## wall across the mouth of the passage at seven metres a second and is gone before you have
## finished deciding what it was. In a station with no floor, a hopper does not need a run-up.
##
## It never comes toward you. The day is not when this station kills you.

const RIG := "res://kit/chupacabra_rig.json"
const NOTICE_DIST := 4.5       # this close and it does not wait to be looked at
const STARE_TIME := 0.35       # or this long with your eyes actually on it
const LURK_LIFE := 22.0        # if you never notice, it goes anyway
const BOLT_CHANCE := 0.25      # the rest of the time it just withdraws
const WITHDRAW_SPEED := 2.6
const WITHDRAW_TIME := 0.55
const COIL_HOLD := 0.18
const LEAP_SPEED := 7.0
const LEAP_TIME := 0.9

signal gone(bolted: bool)

enum State { LURKING, COIL, WITHDRAW, LEAP }

var body: Creature
var _state: int = State.LURKING
var _t := 0.0
var _looked := 0.0
var _life := LURK_LIFE
var _hide := Vector3.FORWARD    # further into the passage, which is where it goes
var _vel := Vector3.ZERO

func _ready() -> void:
	body = Creature.new()
	body.rig_path = RIG
	body.autopose = false        # it is not idling, it is holding still, which is different
	body.glitch = 0.0
	add_child(body)
	body.set_pose("peek", true)

## Wait at `pos`, with `hide` pointing further into the passage. The body faces that way - the
## pose is what cranes the head back round the corner at you.
func lurk_at(pos: Vector3, hide: Vector3) -> void:
	global_position = pos
	_hide = hide.normalized()
	look_at(global_position + _hide, Vector3.UP)

func _process(delta: float) -> void:
	_t += delta
	if Game.player == null:
		return
	var cam: Camera3D = Game.player.camera
	var to := global_position - cam.global_position
	var dist := to.length()

	match _state:
		State.LURKING:
			_life -= delta
			if (-cam.global_transform.basis.z).dot(to.normalized()) > 0.93:
				_looked += delta
			else:
				_looked = maxf(0.0, _looked - delta * 0.5)
			if dist < NOTICE_DIST or _looked > STARE_TIME:
				_leave()
			elif _life <= 0.0:
				_withdraw()      # never noticed: it just is not there any more
		State.COIL:
			if _t >= COIL_HOLD:
				_launch()
		State.WITHDRAW:
			global_position += _hide * WITHDRAW_SPEED * delta
			if _t >= WITHDRAW_TIME:
				queue_free()
		State.LEAP:
			global_position += _vel * delta
			if _t >= LEAP_TIME:
				queue_free()

## Noticed. Most of the time it backs off round the corner; sometimes it goes the loud way.
func _leave() -> void:
	if _state != State.LURKING:
		return
	if randf() < BOLT_CHANCE:
		_state = State.COIL
		_t = 0.0
		body.set_pose("coil", true)
		Sfx.play_at("breath", global_position, -6.0, 18.0, 1.8)
	else:
		_withdraw()

func _withdraw() -> void:
	if _state == State.WITHDRAW or _state == State.LEAP:
		return
	_state = State.WITHDRAW
	_t = 0.0
	body.set_pose("withdraw", true)
	Sfx.play_at("static", global_position, -20.0, 14.0, 1.7)
	gone.emit(false)

## Off the wall, across the mouth of the passage, away from you - a shape crossing a gap.
func _launch() -> void:
	_state = State.LEAP
	_t = 0.0
	body.set_pose("leap", true)
	# across the opening rather than down it: the point is that it passes through your view
	var across := _hide.cross(Vector3.UP).normalized()
	if randf() < 0.5:
		across = -across
	var away := (global_position - Game.player.camera.global_position).normalized()
	away.y = 0.0
	_vel = (across * 0.85 + away.normalized() * 0.35 + Vector3(0, randf_range(0.0, 0.25), 0)).normalized() * LEAP_SPEED
	look_at(global_position + _vel, Vector3.UP)
	Sfx.play_at("bang", global_position, -14.0, 20.0, 1.9)
	gone.emit(true)
