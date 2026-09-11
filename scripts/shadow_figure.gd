extends Node3D
class_name ShadowFigure
## Daytime apparition event: a smoke figure (see Apparition) that either slides across a doorway
## at the far end of a corridor, or stands down the corridor behind you and comes apart when you
## look straight at it.
##
## The figure itself has no feet and no walk - a vulto slides - so "crossing" here is the node
## moving while the smoke leans and trails behind it.

var mode := ""
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _dur := 1.0
var _t := 0.0
var looked := 0.0
var lifetime := 25.0
var _vanishing := false
var body: Apparition

func _ready() -> void:
	body = Apparition.new()
	add_child(body)
	body.gather(0.6)

## Slides from a to b across the mouth of a corridor, trailing as it goes.
func cross(a: Vector3, b: Vector3, dur: float) -> void:
	mode = "cross"
	_from = a
	_to = b
	_dur = dur
	body.agitation = 1.0
	global_position = a
	look_at(b, Vector3.UP)

## Stands at the far end and waits to be noticed.
func stand(p: Vector3, face: Vector3) -> void:
	mode = "stand"
	body.agitation = 0.0
	global_position = p
	var f := face
	f.y = p.y
	if f.distance_to(p) > 0.01:
		look_at(f, Vector3.UP)

## Comes apart rather than fading: the smoke opens up and the embers go out.
func vanish() -> void:
	if _vanishing:
		return
	_vanishing = true
	body.disperse(0.45).tween_callback(queue_free)

func _process(delta: float) -> void:
	if mode == "cross":
		_t += delta
		var k := _t / _dur
		global_position = _from.lerp(_to, k) + Vector3(0, sin(k * PI * 4.0) * 0.03, 0)
		# it leans into the slide, the way smoke lags behind whatever is carrying it
		rotation.z = lerp(rotation.z, -0.22, delta * 4.0)
		if _t >= _dur and not _vanishing:
			vanish()
	elif mode == "stand":
		lifetime -= delta
		if lifetime <= 0.0:
			vanish()
