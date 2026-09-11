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

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0, 0, 0, 1)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	build_body(_mat, self)

## Shared humanoid silhouette: body capsule, head, two arms. ~1.9 m tall, origin at chest.
static func build_body(mat: Material, parent: Node3D) -> void:
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.22
	cm.height = 1.3
	cm.radial_segments = 10
	cm.rings = 4
	body.mesh = cm
	body.material_override = mat
	body.position = Vector3(0, -0.1, 0)
	parent.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 10
	sm.rings = 6
	head.mesh = sm
	head.material_override = mat
	head.position = Vector3(0, 0.72, 0)
	parent.add_child(head)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var am := CapsuleMesh.new()
		am.radius = 0.06
		am.height = 0.9
		am.radial_segments = 6
		am.rings = 2
		arm.mesh = am
		arm.material_override = mat
		arm.position = Vector3(side * 0.3, -0.05, 0)
		arm.rotation.z = side * 0.12
		parent.add_child(arm)
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.09
		lm.height = 1.0
		lm.radial_segments = 6
		lm.rings = 2
		leg.mesh = lm
		leg.material_override = mat
		leg.position = Vector3(side * 0.12, -1.05, 0)
		parent.add_child(leg)

func cross(a: Vector3, b: Vector3, dur: float) -> void:
	mode = "cross"
	_from = a
	_to = b
	_dur = dur
	global_position = a
	look_at(b, Vector3.UP)

func stand(p: Vector3, face: Vector3) -> void:
	mode = "stand"
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
