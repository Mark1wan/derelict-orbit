class_name ToolBelt
extends Node3D
## Four holsters around the waist, so both hands can be free for the rails.
##
## The belt hangs a fixed drop below the head along the body's own up, and turns with the way the
## head faces around that axis - smoothed, so a glance over the shoulder does not swing it round. In
## zero-G there is no world up: upside down, the belt is still at your waist.
##
## Holsters count left to right: 1 left hip, 2 front left, 3 front right, 4 right hip. Tools hang
## through their holster pointing at the deck. The flashlight clips on pointing forward, so on the
## belt it still lights the way you are facing.

const SLOTS := 4
const DROP := 0.55            # head to waist
const RADIUS := 0.24
const ANGLES := [-110.0, -38.0, 38.0, 110.0]   # degrees from straight ahead, negative = left
const REACH := 0.17           # a hand this close to a holster can stow into it or draw from it
const FOLLOW := 4.0           # how quickly the belt turns after the head

var holsters: Array[Node3D] = []
var items: Array = []
var _ring_mats: Array[StandardMaterial3D] = []
var _numbers: Array[Label3D] = []
var _q := Quaternion.IDENTITY
var _placed := false

func _init() -> void:
	name = "ToolBelt"
	items.resize(SLOTS)
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color(0.12, 0.12, 0.13)
	strap.roughness = 0.9
	for i in SLOTS:
		var h := Node3D.new()
		h.name = "Holster%d" % (i + 1)
		var a := deg_to_rad(ANGLES[i])
		h.position = Vector3(sin(a) * RADIUS, 0.0, -cos(a) * RADIUS)
		add_child(h)
		holsters.append(h)
		var clip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.07, 0.018)
		clip.mesh = bm
		clip.material_override = strap
		clip.position = Vector3(0, -0.035, 0)
		clip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(clip)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.03
		tm.outer_radius = 0.04
		tm.rings = 16
		tm.ring_segments = 6
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.1, 0.25, 0.3)
		rm.emission_enabled = true
		rm.emission = Color(0.3, 0.85, 1.0)
		rm.emission_energy_multiplier = 0.2
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(ring)
		_ring_mats.append(rm)
		var lb := Label3D.new()
		lb.text = str(i + 1)
		lb.font_size = 32
		lb.pixel_size = 0.0012
		lb.outline_size = 8
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.position = Vector3(0, 0.06, 0)
		lb.visible = false
		h.add_child(lb)
		_numbers.append(lb)

## Keep the belt under `head` (the camera), in the body's own frame. `body_up` is the way the body
## is standing - in zero-G wherever your feet point, not the world's up - and the belt turns with
## the way the head faces around that axis, so it stays at the waist whichever way up you are.
func follow(head: Node3D, body_up: Vector3, delta: float) -> void:
	var up := body_up.normalized()
	var hb := head.global_transform.basis
	var fwd := -hb.z
	var flat := fwd - up * fwd.dot(up)
	if flat.length() < 0.25:
		# looking straight along the body: the top of the head points the way the body faces
		var hy := hb.y - up * hb.y.dot(up)
		flat = hy * -signf(fwd.dot(up))
	if flat.length() < 0.01:
		flat = up.cross(Vector3.RIGHT) if absf(up.dot(Vector3.RIGHT)) < 0.9 else up.cross(Vector3.FORWARD)
	var z := -flat.normalized()
	var x := up.cross(z).normalized()
	var target := Basis(x, up, z).get_rotation_quaternion()
	if _placed:
		_q = _q.slerp(target, clampf(FOLLOW * delta, 0.0, 1.0))
	else:
		_q = target
		_placed = true
	global_position = head.global_position - up * DROP
	global_basis = Basis(_q)

## Jump straight to the head next frame instead of turning towards it (after a teleport).
func snap() -> void:
	_placed = false

## Nearest holster to `p` within reach. `full` = one with an item in it, else an empty one. -1 if none.
func nearest(p: Vector3, full: bool) -> int:
	var best := -1
	var best_d := REACH
	for i in SLOTS:
		if (items[i] != null) != full:
			continue
		var d := holsters[i].global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best

func first_empty() -> int:
	for i in SLOTS:
		if items[i] == null:
			return i
	return -1

func slot_of(kind: String) -> int:
	for i in SLOTS:
		var it: Item = items[i]
		if it and it.kind == kind:
			return i
	return -1

func stow(item: Item, i: int, quiet := false) -> bool:
	if item == null or i < 0 or i >= SLOTS or items[i] != null:
		return false
	items[i] = item
	item.attach_to(holsters[i], _hang(item), Item.Where.BELT)
	if not quiet:
		Sfx.play("beep", -26.0, 1.6)
	return true

func take(i: int) -> Item:
	if i < 0 or i >= SLOTS:
		return null
	var it: Item = items[i]
	items[i] = null
	return it

## Which holsters to light up: the ones a hand is close enough to use.
func highlight(lit: Dictionary) -> void:
	for i in SLOTS:
		_ring_mats[i].emission_energy_multiplier = 2.2 if lit.has(i) else (0.45 if items[i] != null else 0.2)

func show_numbers(v: bool) -> void:
	for l in _numbers:
		l.visible = v

func clear() -> void:
	for i in SLOTS:
		var it: Item = items[i]
		if is_instance_valid(it):
			it.queue_free()
		items[i] = null

func _hang(item: Item) -> Transform3D:
	if item.kind == Item.FLASHLIGHT:
		# clipped on facing forward and a touch down, so the beam finds what is ahead of you
		return Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.02, -0.06))
	# tools hang through the loop, grip up, pointing at the deck
	return Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.05, 0))
