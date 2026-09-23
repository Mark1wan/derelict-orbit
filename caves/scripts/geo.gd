class_name Geo
extends RefCounted
## Batches many quads into ONE mesh (one draw call per material), and optionally a trimesh
## collider built from the same vertices. Ported from derelict-orbit's scripts/geo.gd, plus the
## three things a cave needs that a space station did not: a cross-section generator, a frame
## that can be carried down a bending centreline without twisting, and a sweep that puts them
## together.
##
## Winding: Godot front faces are clockwise. `quad` takes corners counter-clockwise as seen
## from the visible side (the way you'd sketch them) and emits clockwise triangles. Inside a
## cave you are always looking at the inside of things, so nearly everything here is inward.

var st := SurfaceTool.new()
var tris := 0

func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

## Corners a,b,c,d counter-clockwise seen from the front. uv_scale = texels per metre.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_scale := 0.5) -> void:
	var n := (b - a).cross(d - a).normalized()
	var u_axis := (b - a).normalized()
	var v_axis := n.cross(u_axis)
	for p: Vector3 in [a, c, b, a, d, c]:
		st.set_normal(n)
		st.set_uv(Vector2(p.dot(u_axis), p.dot(v_axis)) * uv_scale)
		st.add_vertex(p)
	tris += 2

## Same, but the caller supplies the UVs - used by `sweep`, which knows the real unwrap
## (distance around the passage, distance along it) and should not have it guessed per quad.
func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var n := (b - a).cross(d - a).normalized()
	var pts := [a, c, b, a, d, c]
	var uvs := [ua, uc, ub, ua, ud, uc]
	for i in 6:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	tris += 2

## Triangle with an explicit normal, for fans and caps.
func tri(a: Vector3, b: Vector3, c: Vector3, n := Vector3.ZERO, uv_scale := 0.35) -> void:
	var nn := n if n != Vector3.ZERO else (b - a).cross(c - a).normalized()
	for p: Vector3 in [a, b, c]:
		st.set_normal(nn)
		st.set_uv(Vector2(p.x + p.z, p.y) * uv_scale)
		st.add_vertex(p)
	tris += 1

## Axis-aligned box. inward=true builds the faces looking into the box.
func box(c: Vector3, s: Vector3, inward := false, uv_scale := 0.5) -> void:
	box_faces(c, s, [0, 1, 2, 3, 4, 5], inward, uv_scale)

## Only some faces of a box (indices: 0=+Z 1=-Z 2=+X 3=-X 4=+Y 5=-Y).
func box_faces(c: Vector3, s: Vector3, which: Array, inward := false, uv_scale := 0.5) -> void:
	var h := s * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	var faces := [[3, 2, 6, 7], [1, 0, 4, 5], [2, 1, 5, 6], [0, 3, 7, 4], [7, 6, 5, 4], [0, 1, 2, 3]]
	for i: int in which:
		var f: Array = faces[i]
		if inward:
			quad(p[f[3]], p[f[2]], p[f[1]], p[f[0]], uv_scale)
		else:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], uv_scale)

# ---------------------------------------------------------------- cross-sections
#
# A section is a closed polygon in the passage's own plane: x across, y up, both in metres,
# centred on (0, 0). `w` and `h` are the CLEAR dimensions - the opening a body has to fit
# through - and nothing this file does ever narrows them. Displacement only pushes rock away
# from the centreline, so the number written in sowbelly.json is the number the caver meets.

## Superellipse exponent per shape. 2 is an ellipse; higher is squarer; lower is more pointed.
const SHAPE_POWER := {
	"tube": 2.0,        # phreatic - dissolved full of water, so round
	"rift": 8.0,        # a joint pulled open: near-parallel walls, rounded ends
	"letterbox": 4.2,   # a bedding plane: wide, flat, square-ish corners
	"keyhole": 2.0,     # handled specially below
	"breakdown": 1.6,   # collapse: angular, pointed
}

## How much of a section's roughness a vertex gets, by how far down the section it faces.
##
## Walls keep all of it. The floor keeps almost none, because displacement is radial and only
## ever pushes rock away from the centreline - so on a floor it digs rather than piles, and a
## room with half a metre of it has ditches in it with fifty-degree sides. A standing body
## walks into one and cannot climb out, which is exactly what happened: the route walker
## stopped dead 93 % of the way across the Cellar with no rock anywhere near its chest.
##
## It is also what a cave looks like. Water leaves walls rough and fills floors flat - silt,
## sand and cobbles settle - so the rough number in the file is a wall number.
const FLOOR_EASE := 0.18

## Rings in an end face. A mouth is cut out of one by dropping faces, so the edge of the mouth
## is only ever as accurate as the faces are small - and SPLIT levels of quartering are applied
## to the ones that land on the edge, which is where being coarse actually costs.
const CAP_RINGS := 10

## How many times a face that lands on a junction is quartered before it is built. One face of
## a room wall is most of a metre across, and a mouth two of them wide would be either walled
## off or full of holes; two levels takes that to a few centimetres, and only at the junctions.
const SPLIT := 3

static func _floor_ease(p: Vector2) -> float:
	var len_sq := p.length_squared()
	if len_sq < 1e-6:
		return 1.0
	var down: float = clampf(-p.y / sqrt(len_sq), 0.0, 1.0)
	return lerpf(1.0, FLOOR_EASE, sqrt(down))

## A closed cross-section polygon, `sides` points counter-clockwise starting at +x.
## `keel` (0..1) flattens the bottom into a floor - mud, sand, cobbles - without eating into
## the clear height, because the flat is added below the section rather than cut out of it.
static func section(shape: String, w: float, h: float, sides: int, keel := 0.0) -> PackedVector2Array:
	var a := w * 0.5
	var b := h * 0.5
	var n: float = SHAPE_POWER.get(shape, 2.0)
	var pts := PackedVector2Array()
	for i in sides:
		var ang := TAU * float(i) / float(sides)
		var ca := cos(ang)
		var sa := sin(ang)
		var p: Vector2
		if shape == "keyhole":
			# A round tube over a narrow slot: the canonical vadose-over-phreatic profile.
			# The upper half keeps the full width, the lower half pinches to a third of it.
			var squeeze: float = 1.0 if sa >= 0.0 else lerpf(1.0, 0.34, minf(-sa * 1.6, 1.0))
			p = Vector2(ca * a * squeeze, sa * b)
		else:
			# Superellipse in polar form: r = 1 / (|cos|^n + |sin|^n)^(1/n), scaled per axis.
			var d := pow(pow(absf(ca), n) + pow(absf(sa), n), -1.0 / n)
			p = Vector2(ca * a * d, sa * b * d)
		if keel > 0.0 and p.y < -b + keel:
			p.y = -b + keel   # the floor is flat; the rock below it is filled with sediment
		pts.append(p)
	return pts

## The tallest gap a body of width `bw` can find in this section - the number that decides
## whether you get through. Scans candidate horizontal positions and reports the best vertical
## clearance over the whole body width, plus where it was found (x offset, floor height).
## Returns {"h": float, "x": float, "y": float}. h <= 0 means nothing of that width fits.
static func clearance(sec: PackedVector2Array, bw: float, samples := 41) -> Dictionary:
	var lo := INF
	var hi := -INF
	for p: Vector2 in sec:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	var best := {"h": -1.0, "x": 0.0, "y": 0.0}
	if hi - lo < bw:
		return best
	for s in samples:
		var cx: float = lerpf(lo + bw * 0.5, hi - bw * 0.5, float(s) / float(maxi(samples - 1, 1)))
		# The gap over the body's whole width is the worst gap under it.
		var top := INF
		var bot := -INF
		var ok := true
		for k in 5:
			var x: float = cx + lerpf(-bw * 0.5, bw * 0.5, float(k) / 4.0)
			var span := _span_at(sec, x)
			if span.y <= span.x:
				ok = false
				break
			bot = maxf(bot, span.x)
			top = minf(top, span.y)
		if ok and top - bot > best["h"]:
			best = {"h": top - bot, "x": cx, "y": bot}
	return best

## The vertical extent (bottom, top) of the section at a given x. Assumes a section that is
## vertically convex, which every shape here is.
static func _span_at(sec: PackedVector2Array, x: float) -> Vector2:
	var bot := INF
	var top := -INF
	var n := sec.size()
	for i in n:
		var p := sec[i]
		var q := sec[(i + 1) % n]
		if (p.x <= x and q.x >= x) or (q.x <= x and p.x >= x):
			var y: float = p.y
			if absf(q.x - p.x) > 1e-9:
				y = lerpf(p.y, q.y, (x - p.x) / (q.x - p.x))
			bot = minf(bot, y)
			top = maxf(top, y)
	if bot == INF:
		return Vector2(0.0, 0.0)
	return Vector2(bot, top)

## Is this point inside the section polygon? Crossing count, which is exact for the convex
## shapes here and does not care that they are not circles - a rift is thirty centimetres one
## way and two metres the other, and treating it as a circle of its longest radius throws away
## most of the passage.
static func contains(sec: PackedVector2Array, p: Vector2) -> bool:
	var inside := false
	var n := sec.size()
	var j := n - 1
	for i in n:
		var a := sec[i]
		var b := sec[j]
		if (a.y > p.y) != (b.y > p.y):
			if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
		j = i
	return inside

# ---------------------------------------------------------------- frames along a centreline

## One orthonormal frame per path point: basis.x across the passage, basis.y up it, basis.z
## along it. Where the passage is anything but vertical the frame is levelled against world up,
## so "height" in a profile means height and a crawl's floor stays underneath you. Through a
## near-vertical stretch - a pitch, a chimney - there is no such thing as levelling, so the
## previous frame is carried forward by parallel transport instead and the passage does not
## spin around its own axis on the way down.
static func frames(path: PackedVector3Array) -> Array:
	var n := path.size()
	var out: Array = []
	if n < 2:
		return out
	var tan := PackedVector3Array()
	for i in n:
		if i == 0:
			tan.append((path[1] - path[0]).normalized())
		elif i == n - 1:
			tan.append((path[n - 1] - path[n - 2]).normalized())
		else:
			tan.append((path[i + 1] - path[i - 1]).normalized())
	var prev_x := Vector3.ZERO
	for i in n:
		var t := tan[i]
		var x: Vector3
		if absf(t.dot(Vector3.UP)) < 0.94:
			x = Vector3.UP.cross(t).normalized()          # levelled: y ends up as near up as it can be
		elif prev_x != Vector3.ZERO:
			x = (prev_x - t * prev_x.dot(t)).normalized() # vertical: carry the last frame through
		else:
			x = Vector3.BACK.cross(t).normalized()
		if x.length_squared() < 0.5:
			x = Vector3.BACK.cross(t).normalized()
		var y := t.cross(x).normalized()
		out.append(Basis(x, y, t))
		prev_x = x
	return out

## Resample a coarse list of control points into a smooth centreline, one point per `step`
## metres, through a centripetal Catmull-Rom spline. Control points in sowbelly.json are
## corners of the passage's shape; this is what turns them into something you can walk.
static func spline(control: PackedVector3Array, step := 0.6) -> PackedVector3Array:
	var n := control.size()
	if n < 3:
		return control
	var out := PackedVector3Array()
	for i in range(n - 1):
		var p0: Vector3 = control[maxi(i - 1, 0)]
		var p1: Vector3 = control[i]
		var p2: Vector3 = control[i + 1]
		var p3: Vector3 = control[mini(i + 2, n - 1)]
		var segs := maxi(int(ceil(p1.distance_to(p2) / step)), 1)
		for s in segs:
			out.append(_catmull(p0, p1, p2, p3, float(s) / float(segs)))
	out.append(control[n - 1])
	return out

static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

# ---------------------------------------------------------------- the sweep

## Sweep a passage: one closed section per path point, walls facing inward, unwrapped
## cylindrically so the rock texture runs along the passage instead of being guessed per quad.
##
## `rough` displaces every wall vertex outward along its own radial by up to that many metres,
## sampled from `noise` at the vertex's world position - so the displacement is continuous
## along the passage and around the ring without any seam bookkeeping. It only ever pushes
## rock away, never in, which is what lets sowbelly.json's numbers be a promise.
##
## `pick(k) -> Geo` gives the builder for the face between section points k and k+1, so a crawl
## routes its floor into the mud batch and its walls into the limestone one in a single pass.
## Kept from derelict-orbit's Geo.tube.
##
## `verdict(corners) -> int` says what the junction makes of each face: 0 build it, 1 drop it,
## 2 it lands on the edge of a mouth, so quarter it and ask again (see `_patch`). That is how
## one passage opens into another without leaving a membrane of rock across the join.
func sweep(path: PackedVector3Array, sections: Array, rough := 0.0,
		noise: FastNoiseLite = null, pick: Callable = Callable(),
		verdict: Callable = Callable(), seam: Geo = null, uv_scale := 0.7) -> void:
	var n := path.size()
	if n < 2 or sections.size() != n:
		return
	var fr := frames(path)
	var rings: Array = []
	var along := PackedFloat32Array()
	var run := 0.0
	for i in n:
		var sec: PackedVector2Array = sections[i]
		var ring := PackedVector3Array()
		for p: Vector2 in sec:
			var world: Vector3 = path[i] + fr[i].x * p.x + fr[i].y * p.y
			if rough > 0.0 and noise:
				var radial := (world - path[i]).normalized()
				# 0..1, never negative: rock is displaced outward only.
				var d: float = (noise.get_noise_3dv(world * 1.6) * 0.5 + 0.5)
				world += radial * d * rough * _floor_ease(p)
			ring.append(world)
		rings.append(ring)
		if i > 0:
			run += path[i].distance_to(path[i - 1])
		along.append(run)

	var sides: int = (sections[0] as PackedVector2Array).size()
	# Arc length around the first ring, reused for every ring, so the texture does not swim
	# where the passage widens.
	var around := PackedFloat32Array()
	var acc := 0.0
	var first: PackedVector3Array = rings[0]
	around.append(0.0)
	for i in range(1, sides + 1):
		acc += first[i % sides].distance_to(first[i - 1])
		around.append(acc)

	for i in range(n - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		for k in sides:
			var j := (k + 1) % sides
			var g: Geo = pick.call(k) if pick.is_valid() else self
			if g == null:
				continue
			var u0 := around[k] * uv_scale
			var u1 := around[k + 1] * uv_scale
			var v0 := along[i] * uv_scale
			var v1 := along[i + 1] * uv_scale
			_patch(r0[j], r0[k], r1[k], r1[j],
				Vector2(u1, v0), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1),
				g, verdict, seam, 0)

## One quad of a passage wall, split where it lands on a junction. Same reasoning as
## `_cap_patch`: a face that is part inside a neighbour and part outside is a hole on one side
## and rock on the other whichever way it goes whole, and a wall face here is 35 cm along the
## passage by most of a metre around it - which is the difference between a mouth you can crawl
## through and a mouth with a bar across it. Splitting is only ever asked for at a junction, so
## the rest of the cave carries none of the cost.
func _patch(q0: Vector3, q1: Vector3, q2: Vector3, q3: Vector3,
		t0: Vector2, t1: Vector2, t2: Vector2, t3: Vector2,
		g: Geo, verdict: Callable, seam: Geo, depth: int) -> void:
	if verdict.is_valid():
		var say: int = verdict.call(PackedVector3Array([q0, q1, q2, q3]))
		if say == 1:
			return
		if say == 2:
			if depth < SPLIT:
				var a := (q0 + q1) * 0.5
				var bb := (q1 + q2) * 0.5
				var c := (q2 + q3) * 0.5
				var d := (q3 + q0) * 0.5
				var m := (q0 + q1 + q2 + q3) * 0.25
				var ta := (t0 + t1) * 0.5
				var tb := (t1 + t2) * 0.5
				var tc := (t2 + t3) * 0.5
				var td := (t3 + t0) * 0.5
				var tm := (t0 + t1 + t2 + t3) * 0.25
				_patch(q0, a, m, d, t0, ta, tm, td, g, verdict, seam, depth + 1)
				_patch(a, q1, bb, m, ta, t1, tb, tm, g, verdict, seam, depth + 1)
				_patch(m, bb, q2, c, tm, tb, t2, tc, g, verdict, seam, depth + 1)
				_patch(d, m, c, q3, td, tm, tc, t3, g, verdict, seam, depth + 1)
				return
			if seam != null:
				g = seam
	g.quad_uv(q0, q1, q2, q3, t0, t1, t2, t3)

## Cap an end of a swept passage - a blind pinch, a dead end, the rock a passage runs into when
## it stops, or the wall a tunnel arrives through. `at_end` picks which of the two ends.
##
## `face(corners) -> int` says what to do with each patch of it: 0 build it, 1 drop it,
## 2 it lands on the rim of a mouth, so split it and ask again. Every end is capped and a mouth
## is a hole dropped out of one, so this is where a junction is actually cut. See `_cap_patch`.
func cap(path: PackedVector3Array, sections: Array, at_end: bool, rough := 0.0,
		noise: FastNoiseLite = null, face: Callable = Callable()) -> void:
	var n := path.size()
	if n < 2:
		return
	var i := n - 1 if at_end else 0
	var fr := frames(path)
	var sec: PackedVector2Array = sections[i]
	var centre: Vector3 = path[i]
	var norm: Vector3 = -fr[i].z if at_end else fr[i].z
	var sides := sec.size()

	# Concentric rings from the centre out, rather than one fan of long thin triangles, so the
	# face can have a hole cut in it. Every end of every passage is capped; the ones that are
	# mouths get opened by `face` calling for the faces inside the passage they run into to be
	# dropped. A fan cannot do that - its triangles reach from the rim to the centre, so
	# dropping one takes a whole wedge of the wall with it.
	var rings: Array = []
	for r in CAP_RINGS + 1:
		var f := float(r) / float(CAP_RINGS)
		var ring := PackedVector3Array()
		for p: Vector2 in sec:
			var q: Vector2 = p * f
			var world: Vector3 = centre + fr[i].x * q.x + fr[i].y * q.y
			# Only the rim is displaced, and by the same amount the sweep displaces it, so the
			# cap meets the tube it closes without a seam.
			if r == CAP_RINGS and rough > 0.0 and noise:
				world += ((world - centre).normalized()
					* (noise.get_noise_3dv(world * 1.6) * 0.5 + 0.5) * rough * _floor_ease(p))
			ring.append(world)
		rings.append(ring)

	for r in CAP_RINGS:
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		for k in sides:
			var j := (k + 1) % sides
			_cap_patch(a[k], a[j], b[j], b[k], centre if r == 0 else Vector3.INF,
				norm, at_end, face, 0)

## One quad of an end face, or the triangle at its centre. A patch that is only partly inside
## the passage arriving through it is the RIM OF A MOUTH - keeping it whole walls off the
## passage, dropping it whole opens a pinhole to the void beside it - so it is split in four and
## each quarter asked again, down to SPLIT levels. That gets the rim accurate to a few
## centimetres without carrying the triangles everywhere else: at the base resolution a mouth in
## a room's end wall is one patch across, and one patch is 30 cm. What is left at the limit is
## built as ordinary rock, because a few centimetres of lip at a mouth is a few centimetres.
func _cap_patch(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, apex: Vector3,
		norm: Vector3, at_end: bool, face: Callable, depth: int) -> void:
	var g: Geo = self
	if face.is_valid():
		var say: int = face.call(PackedVector3Array([p0, p1, p2, p3]))
		if say == 1:
			return
		if say == 2 and depth < SPLIT and apex == Vector3.INF:
			var m01 := (p0 + p1) * 0.5
			var m12 := (p1 + p2) * 0.5
			var m23 := (p2 + p3) * 0.5
			var m30 := (p3 + p0) * 0.5
			var mid := (p0 + p1 + p2 + p3) * 0.25
			_cap_patch(p0, m01, mid, m30, apex, norm, at_end, face, depth + 1)
			_cap_patch(m01, p1, m12, mid, apex, norm, at_end, face, depth + 1)
			_cap_patch(mid, m12, p2, m23, apex, norm, at_end, face, depth + 1)
			_cap_patch(m30, mid, m23, p3, apex, norm, at_end, face, depth + 1)
			return
	if apex != Vector3.INF:
		# The innermost band collapses to a point at the centre: one triangle, not two.
		if at_end:
			g.tri(apex, p3, p2, norm)
		else:
			g.tri(apex, p2, p3, norm)
	elif at_end:
		g.tri(p0, p3, p2, norm)
		g.tri(p0, p2, p1, norm)
	else:
		g.tri(p0, p2, p3, norm)
		g.tri(p0, p1, p2, norm)

## Thin closed prism between two points - a rope anchor, a stalactite, a rail.
func pipe(p0: Vector3, p1: Vector3, radius: float, sides := 6) -> void:
	var axis := (p1 - p0).normalized()
	if axis.length_squared() < 0.5:
		return
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.BACK
	var u := up.cross(axis).normalized()
	var v := axis.cross(u).normalized()
	var r0 := PackedVector3Array()
	var r1 := PackedVector3Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var off := (u * cos(a) + v * sin(a)) * radius
		r0.append(p0 + off)
		r1.append(p1 + off)
	for i in sides:
		var j := (i + 1) % sides
		quad(r0[i], r0[j], r1[j], r1[i], 1.0)
	for i in range(1, sides - 1):
		tri(r0[0], r0[i + 1], r0[i], -axis)
		tri(r1[0], r1[i], r1[i + 1], axis)

## A tapered spike - stalactites hanging, stalagmites standing. `up` flips which end is wide.
func spike(base: Vector3, height: float, radius: float, up := true, sides := 6) -> void:
	var tip := base + Vector3.UP * (height if up else -height)
	var ring := PackedVector3Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		ring.append(base + Vector3(cos(a), 0.0, sin(a)) * radius)
	for i in sides:
		var j := (i + 1) % sides
		if up:
			tri(ring[i], ring[j], tip)
		else:
			tri(ring[j], ring[i], tip)

## Build the MeshInstance3D. body != null -> also a trimesh collider on that StaticBody3D,
## from the same vertices, so what you see is exactly what you bump into.
func commit(mat: Material, parent: Node, body: StaticBody3D = null, name_ := "") -> MeshInstance3D:
	if tris == 0:
		return null
	st.generate_tangents()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if name_ != "":
		mi.name = name_
	parent.add_child(mi)
	if body:
		var cs := CollisionShape3D.new()
		var shape := mesh.create_trimesh_shape()
		# Rock is solid from both sides. Godot's trimesh shapes ignore backfaces by default,
		# which means a ray cast from INSIDE the rock hits nothing and reports open space - so
		# a body that ends up briefly embedded in a wall reads the cave as a cathedral and
		# stands up in a slot it cannot fit through. Turning this on makes the body model
		# self-recovering: embedded means zero clearance, which folds you down immediately.
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
	return mi
