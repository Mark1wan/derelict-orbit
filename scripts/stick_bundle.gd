class_name StickBundle
extends RefCounted
## What is hanging outside the stall door (scripts/washroom.gd): a bundle of sticks, the kind that
## gets left on doorsteps. A dozen-odd twigs of different lengths, crooked, bound tight in three
## places with twine and once with red thread, a strip of pale cloth knotted round the middle, a
## few longer twigs splayed out of the top like fingers, and a loop of cord at the top as though it
## had been hung from something. There is nothing for it to hang from.
##
## Built in code like the terminals: a handful of Geo prisms, four flat materials, about half a
## metre long. Its axis is its local Y.

const WOOD := Color(0.22, 0.15, 0.09)
const BARK := Color(0.32, 0.25, 0.17)
const TWINE := Color(0.46, 0.39, 0.27)
const THREAD := Color(0.5, 0.04, 0.03)
const CLOTH := Color(0.64, 0.6, 0.52)

static func make(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "StickBundle"
	var wood := Geo.new()
	var bark := Geo.new()
	var twine := Geo.new()
	var thread := Geo.new()
	var cloth := Geo.new()

	# the sticks: packed round the axis, pinched at the bindings, flaring a little either end
	var n := 15
	for i in n:
		var a := TAU * float(i) / n + rng.randf_range(-0.25, 0.25)
		var r := rng.randf_range(0.012, 0.042)
		var out := Vector3(cos(a), 0.0, sin(a))
		var lo := out * (r + rng.randf_range(0.0, 0.02)) + Vector3(0, -rng.randf_range(0.22, 0.3), 0)
		var hi := out * (r + rng.randf_range(0.01, 0.05)) + Vector3(0, rng.randf_range(0.18, 0.3), 0)
		var mid := out * r * 0.8 + Vector3(0, rng.randf_range(-0.03, 0.03), 0)
		var g := wood if i % 3 != 0 else bark
		var thick := rng.randf_range(0.006, 0.012)
		g.pipe(lo, mid, thick, 5)
		g.pipe(mid, hi, thick * 0.85, 5)
		if rng.randf() < 0.35:
			# a crook: the twig forks off near its end
			var fork := hi + (out * rng.randf_range(0.03, 0.07) + Vector3(0, rng.randf_range(0.02, 0.06), 0))
			g.pipe(hi.lerp(mid, 0.25), fork, thick * 0.6, 4)

	# the crown: four long twigs splayed out of the top, bent, reaching
	for i in 4:
		var a := TAU * (float(i) + rng.randf_range(0.0, 0.5)) / 4.0
		var out := Vector3(cos(a), 0.0, sin(a))
		var base := out * 0.02 + Vector3(0, 0.12, 0)
		var elbow := out * rng.randf_range(0.07, 0.1) + Vector3(0, rng.randf_range(0.3, 0.36), 0)
		var tip := elbow + out * rng.randf_range(0.05, 0.1) + Vector3(0, rng.randf_range(0.03, 0.09), 0)
		wood.pipe(base, elbow, 0.007, 5)
		wood.pipe(elbow, tip, 0.005, 4)
		wood.pipe(tip, tip + out * 0.03 + Vector3(rng.randf_range(-0.02, 0.02), 0.02, 0), 0.003, 4)

	# the bindings: three of twine, wound thick, and one of red thread between two of them
	for y: float in [-0.17, 0.0, 0.14]:
		twine.prism(Vector3(0, y - 0.02, 0), Vector3(0, y + 0.02, 0), 0.056, 9)
		twine.prism(Vector3(0, y - 0.006, 0), Vector3(0, y + 0.006, 0), 0.061, 9)
	thread.prism(Vector3(0, -0.085, 0), Vector3(0, -0.07, 0), 0.058, 9)
	# its loose end, trailing
	thread.pipe(Vector3(0.055, -0.078, 0.0), Vector3(0.07, -0.2, 0.025), 0.003, 4)
	thread.pipe(Vector3(0.07, -0.2, 0.025), Vector3(0.065, -0.29, 0.05), 0.003, 4)

	# the cloth: a strip knotted round the middle, the two ends hanging
	cloth.prism(Vector3(0, 0.05, 0), Vector3(0, 0.085, 0), 0.058, 9)
	cloth.box(Vector3(0.0, -0.02, 0.062), Vector3(0.035, 0.16, 0.004))
	cloth.box(Vector3(0.028, -0.05, 0.058), Vector3(0.03, 0.2, 0.004))
	cloth.box(Vector3(0.0, 0.07, 0.066), Vector3(0.05, 0.035, 0.02))

	# the loop of cord at the top, as if it had been hung up, and nothing above it
	var loop_pts: Array[Vector3] = []
	for k in 9:
		var t := PI * float(k) / 8.0
		loop_pts.append(Vector3(cos(t) * 0.035, 0.34 + sin(t) * 0.06, 0.0))
	twine.pipe(Vector3(0, 0.16, 0), loop_pts[0], 0.004, 4)
	twine.pipe(Vector3(0, 0.16, 0), loop_pts[8], 0.004, 4)
	for k in 8:
		twine.pipe(loop_pts[k], loop_pts[k + 1], 0.004, 4)

	wood.commit(_mat(WOOD, 0.95), root, null, "sticks")
	bark.commit(_mat(BARK, 0.9), root, null, "bark")
	twine.commit(_mat(TWINE, 1.0), root, null, "twine")
	thread.commit(_mat(THREAD, 0.8), root, null, "thread")
	cloth.commit(_mat(CLOTH, 1.0), root, null, "cloth")
	return root

static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.0
	return m
