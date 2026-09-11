extends Node3D
class_name Fae
## The ring. The oldest thing in the suite, and the only one that is pretty.
##
## Not the Victorian fairy with wings on a flower - the older kind, the ones nobody would name out
## loud. You called them the Good Neighbours, or Themselves, or the Fair Folk, because a name is a
## way of getting someone's attention. Two pieces of that folklore are in here.
##
## The **will-o'-the-wisp**: lights out over the bog that look like a lantern on the path, and are
## not, and that people followed into the water anyway, because a light in the dark is very hard
## to argue with. And the **ring**: the circle you do not step inside, because what is in there
## keeps its own time, and the people who came back out of one came back to a year they did not
## recognise.
##
## So: thirteen cold lights turning in a ring, hanging across the corridor at chest height, with a
## clear gap between it and the hull all the way round - the whole ship is cold iron, and they do
## not touch it. It is exactly the shape of a hoop you would swim through.
##
## Come near and the glamour comes off: the lights shrink to pinpricks and what was holding each
## one hangs there, small and long-armed, with its face turned toward you. Swim through it anyway
## and it takes what it takes, which is time. Your clock will disagree with you afterwards.

const RIG := "res://kit/apparition_fae.json"
const RING_RADIUS := 0.95
const RING_Y := 1.52
const GLAMOUR_DIST := 3.2     # this close and it stops bothering to look like lights
const TAKEN_TIME := 22.0      # seconds of shift it costs you to go through it
const LIFETIME := 34.0

signal taken

var body: Apparition
var spin := 0.22              # the dance: it turns, slowly, the whole time
var _life := LIFETIME
var _done := false

func _ready() -> void:
	body = Apparition.new()
	body.rig_path = RIG
	add_child(body)
	body.gather(1.6)          # they fade up out of nothing, unhurried

## Hang the ring across the corridor at `p`, square to `axis` (the direction of travel).
func hang(p: Vector3, axis: Vector3) -> void:
	global_position = p - Vector3(0, RING_Y, 0)
	var a := axis
	a.y = 0.0
	if a.length() > 0.01:
		look_at(global_position + a.normalized(), Vector3.UP)

func _process(delta: float) -> void:
	if _done or Game.player == null:
		return
	rotate_object_local(Vector3.FORWARD, spin * delta)
	_life -= delta

	var head: Vector3 = Game.player.camera.global_position
	var local := to_local(head)
	var dist := head.distance_to(global_position + Vector3(0, RING_Y, 0))

	# the glamour comes off on approach and does not go back on
	if dist < GLAMOUR_DIST and body.morph < 1.0:
		var tw := create_tween()
		tw.tween_property(body, "morph", 1.0, 0.9)
		body.morph = maxf(body.morph, 0.001)
		Sfx.play_at("whisper", global_position, -8.0, 24.0, 1.25)

	# through the hoop: inside the ring's plane and inside its radius
	var r := Vector2(local.x, local.y - RING_Y).length()
	if absf(local.z) < 0.45 and r < RING_RADIUS:
		_take()
	elif _life <= 0.0:
		_leave()

## What it takes is time. You were in there for a moment; the clock says otherwise.
func _take() -> void:
	if _done:
		return
	_done = true
	Game.day_time = minf(Game.DAY_LENGTH - 2.0, Game.day_time + TAKEN_TIME)
	Game.notice.emit("You are somewhere else in the corridor.\nThe clock has moved on without you.", 5.0)
	if Game.player is Player:
		Game.player.fuel = 0.0
	Sfx.play_at("scream", global_position, -8.0, 30.0, 1.6)
	taken.emit()
	body.disperse(0.35).tween_callback(queue_free)

func _leave() -> void:
	if _done:
		return
	_done = true
	body.disperse(1.4).tween_callback(queue_free)
