extends Node3D
class_name ShadowFigure
## Daytime apparition: an unlit black silhouette that crosses a doorway,
## or stands at the end of a corridor and vanishes when you look straight at it.

var mode := ""
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _dur := 1.0
var _t := 0.0
var _mat: StandardMaterial3D
var looked := 0.0
var lifetime := 25.0
var _vanishing := false

var body: Creature

func _ready() -> void:
	body = Creature.new()
	body.position = Vector3(0, -1.2, 0)
	body.glitch = 0.35
	add_child(body)
	_mat = body.make_silhouette()

func cross(a: Vector3, b: Vector3, dur: float) -> void:
	mode = "cross"
	body.moving = true      # it crosses the doorway on all fours
	_from = a
	_to = b
	_dur = dur
	global_position = a
	look_at(b, Vector3.UP)

func stand(p: Vector3, face: Vector3) -> void:
	mode = "stand"
	body.moving = false     # the watcher is upright, and does not move at all
	global_position = p
	var f := face
	f.y = p.y
	if f.distance_to(p) > 0.01:
		look_at(f, Vector3.UP)

func vanish() -> void:
	if _vanishing:
		return
	_vanishing = true
	var tw := create_tween()
	tw.tween_property(_mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(queue_free)

func _process(delta: float) -> void:
	if mode == "cross":
		_t += delta
		var k := _t / _dur
		global_position = _from.lerp(_to, k) + Vector3(0, sin(k * PI * 4.0) * 0.03, 0)
		if _t >= _dur:
			queue_free()
	elif mode == "stand":
		lifetime -= delta
		if lifetime <= 0.0:
			vanish()
