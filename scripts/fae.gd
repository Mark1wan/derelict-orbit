extends Node3D
class_name Fae
## The Good Neighbours: the apparition that picks things up.
##
## Not the Victorian fairy with wings on a flower - the older kind, the ones nobody would name out
## loud. You called them the Good Neighbours, or Themselves, or the Fair Folk, because a name is a
## way of getting someone's attention.
##
## What they were actually blamed for, before anyone drew them, was small and constant and
## infuriating: things moved. Tools not where you left them. Something thrown across a barn with
## nobody in it. Lights in the yard at night, and in the morning the gate is off its hinges and
## lying out in the field.
##
## So this one does not stand anywhere and does not look at you. It takes hold of a loose crate or
## a helmet or a drum, wraps itself round it as a shell of thirteen cold lights, carries it a few
## metres - unhurried, wandering, the way you carry something you are not in a rush with - and
## then throws it.
##
## Half the time you never see the lights at all. You see a crate come out of a side passage at
## head height doing four metres a second, and hit the far wall, and nothing is there.

const RIG := "res://kit/apparition_fae.json"
const GLAMOUR_DIST := 3.4      # this close and it stops bothering to look like lights
const SEEN_CHANCE := 0.45      # how often the lights are visible at all

enum State { TAKING, CARRYING, THROWN }

signal thrown(prop: Node3D, velocity: Vector3)

var seen := true               # false: the object moves and there is nothing to see doing it
var carry_time := 3.4          # seconds it holds on before it lets go
var throw_speed := 4.2
var spin := 0.5                # the swarm turns around whatever it has hold of

var _state: int = State.TAKING
var _prop: Node3D = null
var _prop_index := -1
var _body: Apparition
var _t := 0.0
var _drift := Vector3.ZERO
var _wander := Vector3.ZERO
var _throw_dir := Vector3.FORWARD

func _ready() -> void:
	_body = Apparition.new()
	_body.rig_path = RIG
	add_child(_body)
	if seen:
		_body.gather(0.9)      # they come up out of nothing around it
	else:
		_body.form = 0.0
		_body.ember_energy = 0.0

## Take hold of station prop `index` and carry it `along` (a direction, usually across the
## player's view), then throw it that way. Returns false if the prop is not there any more.
func take(index: int, along: Vector3, away_from: Vector3) -> bool:
	var st: Station = Game.station
	_prop = st.take_prop(index)
	if _prop == null:
		return false
	_prop_index = index
	global_position = _prop.global_position
	var dir := along
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	# carry it across, and throw it on past - never back down the throat of whoever is watching
	var to_watcher := (away_from - global_position)
	to_watcher.y = 0.0
	if to_watcher.length() > 0.01 and dir.dot(to_watcher.normalized()) > 0.35:
		dir = -dir
	_drift = dir * randf_range(0.55, 0.95) + Vector3(0, randf_range(-0.15, 0.15), 0)
	_throw_dir = dir
	_wander = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	carry_time = randf_range(2.6, 5.0)
	return true

func _process(delta: float) -> void:
	if _state == State.THROWN or not is_instance_valid(_prop):
		return
	_t += delta
	rotate_object_local(Vector3.UP, spin * delta)

	# carried: it wanders while it goes, because nothing is in a hurry about this
	var wobble := Vector3(
		sin(_t * 1.7 + _wander.x * 6.0),
		sin(_t * 1.3 + _wander.y * 6.0),
		sin(_t * 2.1 + _wander.z * 6.0)) * 0.22
	global_position += (_drift + wobble * delta * 4.0) * delta
	_prop.global_position = global_position
	_prop.rotation += Vector3(0.4, 0.7, 0.3) * delta

	if seen and Game.player:
		var head: Vector3 = Game.player.camera.global_position
		# up close the glamour comes off: the lights shrink and what is holding it is still there
		if head.distance_to(global_position) < GLAMOUR_DIST and _body.morph < 1.0:
			_body.morph = maxf(_body.morph, 0.001)
			create_tween().tween_property(_body, "morph", 1.0, 0.8)

	if _t >= carry_time:
		_throw()

## Let go, hard. This is the bit anyone actually sees: something crosses a corridor at speed.
func _throw() -> void:
	if _state == State.THROWN:
		return
	_state = State.THROWN
	var vel := (_throw_dir + Vector3(randf_range(-0.2, 0.2), randf_range(-0.25, 0.25), randf_range(-0.2, 0.2))).normalized() * throw_speed
	var st: Station = Game.station
	st.release_prop(_prop_index, vel, Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4)))
	Sfx.play_at("bang", global_position, -8.0, 30.0, 1.3)
	thrown.emit(_prop, vel)
	if seen:
		# the lights let go with it and go out a moment later
		_body.disperse(0.5).tween_callback(queue_free)
	else:
		queue_free()
