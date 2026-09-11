class_name Geo
extends RefCounted
## Batches many quads into ONE mesh (one draw call per material). Used for the station hull:
## rooms, corridor tubes, bulkhead rings, beams. Optionally adds a trimesh collider.
##
## Winding: Godot front faces are clockwise. `quad` takes corners counter-clockwise as seen
## from the visible side (the way you'd sketch them) and emits clockwise triangles.

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

## Axis-aligned box. inward=true builds the faces looking into the box (a room interior).
func box(c: Vector3, s: Vector3, inward := false, uv_scale := 0.5) -> void:
	var h := s * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	var faces := [
		[3, 2, 6, 7], # +Z
		[1, 0, 4, 5], # -Z
		[2, 1, 5, 6], # +X
		[0, 3, 7, 4], # -X
		[7, 6, 5, 4], # +Y
		[0, 1, 2, 3]] # -Y
	for f: Array in faces:
		if inward:
			quad(p[f[3]], p[f[2]], p[f[1]], p[f[0]], uv_scale)
		else:
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], uv_scale)

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

## Points of a regular polygon (apothem = distance centre->flat side) in the plane
## perpendicular to `axis`, rotated so one flat side faces `down` (-Y for corridors).
static func poly_ring(center: Vector3, axis: Vector3, apothem: float, sides: int) -> Array:
	var r := apothem / cos(PI / sides)
	var up := Vector3.UP
	if absf(axis.dot(up)) > 0.9:
		up = Vector3.FORWARD
	var u := up.cross(axis).normalized()
	var v := axis.cross(u).normalized()
	var pts := []
	for i in sides:
		var a := TAU * (float(i) + 0.5) / sides   # +0.5 so a flat face is at the bottom
		pts.append(center + (u * cos(a) + v * sin(a)) * r)
	return pts

## Polygonal tube from p0 to p1. inward=true: faces look into the tube (a corridor).
## face_cb(i) -> Geo chooses the builder per face (lets the floor use a different material).
func tube(p0: Vector3, p1: Vector3, apothem: float, sides: int, inward := true, face_cb: Callable = Callable(), uv_scale := 0.5) -> void:
	var axis := (p1 - p0).normalized()
	var r0 := poly_ring(p0, axis, apothem, sides)
	var r1 := poly_ring(p1, axis, apothem, sides)
	for i in sides:
		var j := (i + 1) % sides
		var g: Geo = self
		if face_cb.is_valid():
			g = face_cb.call(i)
		if inward:
			g.quad(r0[j], r0[i], r1[i], r1[j], uv_scale)
		else:
			g.quad(r0[i], r0[j], r1[j], r1[i], uv_scale)

## Which tube face index is the floor (lowest centre) for a horizontal tube.
static func floor_face(axis: Vector3, apothem: float, sides: int) -> int:
	var r := poly_ring(Vector3.ZERO, axis, apothem, sides)
	var best := 0
	var best_y := INF
	for i in sides:
		var y: float = (r[i].y + r[(i + 1) % sides].y) * 0.5
		if y < best_y:
			best_y = y
			best = i
	return best

## Tube face whose centre points most toward `toward` (e.g. -t for the left wall).
static func face_toward(axis: Vector3, apothem: float, sides: int, toward: Vector3) -> int:
	var r := poly_ring(Vector3.ZERO, axis, apothem, sides)
	var best := 0
	var best_d := -INF
	for i in sides:
		var c: Vector3 = (r[i] + r[(i + 1) % sides]) * 0.5
		var d := c.normalized().dot(toward)
		if d > best_d:
			best_d = d
			best = i
	return best

## Polygonal annulus extruded along `axis` (a bulkhead frame / rib). Faces: inner, outer, both ends.
func ring(center: Vector3, axis: Vector3, apothem_in: float, apothem_out: float, depth: float, sides: int, uv_scale := 0.5) -> void:
	var a0 := center - axis * depth * 0.5
	var a1 := center + axis * depth * 0.5
	var i0 := poly_ring(a0, axis, apothem_in, sides)
	var i1 := poly_ring(a1, axis, apothem_in, sides)
	var o0 := poly_ring(a0, axis, apothem_out, sides)
	var o1 := poly_ring(a1, axis, apothem_out, sides)
	for i in sides:
		var j := (i + 1) % sides
		quad(i0[j], i0[i], i1[i], i1[j], uv_scale)      # inner (faces the axis)
		quad(o0[i], o0[j], o1[j], o1[i], uv_scale)      # outer
		quad(o0[j], o0[i], i0[i], i0[j], uv_scale)      # back end cap (-axis)
		quad(i1[j], i1[i], o1[i], o1[j], uv_scale)      # front end cap (+axis)

## Closed polygonal prism (a solid cylinder-ish shape), outward faces.
func prism(p0: Vector3, p1: Vector3, apothem: float, sides: int, uv_scale := 0.5) -> void:
	var axis := (p1 - p0).normalized()
	tube(p0, p1, apothem, sides, false, Callable(), uv_scale)
	var r0 := poly_ring(p0, axis, apothem, sides)
	var r1 := poly_ring(p1, axis, apothem, sides)
	for i in range(1, sides - 1):
		# end caps as fans
		var n0 := -axis
		st.set_normal(n0); st.set_uv(Vector2.ZERO); st.add_vertex(r0[0])
		st.set_normal(n0); st.set_uv(Vector2.ZERO); st.add_vertex(r0[i])
		st.set_normal(n0); st.set_uv(Vector2.ZERO); st.add_vertex(r0[i + 1])
		st.set_normal(axis); st.set_uv(Vector2.ZERO); st.add_vertex(r1[0])
		st.set_normal(axis); st.set_uv(Vector2.ZERO); st.add_vertex(r1[i + 1])
		st.set_normal(axis); st.set_uv(Vector2.ZERO); st.add_vertex(r1[i])
		tris += 2

## Thin cylinder (pipe / rail) between two points as an 8-sided prism.
func pipe(p0: Vector3, p1: Vector3, radius: float, sides := 8) -> void:
	prism(p0, p1, radius, sides, 1.0)

## Build the MeshInstance3D. body != null -> also a trimesh collider on that StaticBody3D.
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
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)
	return mi
