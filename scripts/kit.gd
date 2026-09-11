class_name Kit
extends RefCounted
## The modular station kit (res://kit/*.glb, see kit/KIT_README.md): 4 m grid cells, floor at
## y = 0, rooms are 3x3 cells with their doorway on -Z. This loads each piece once, remembers
## the glTF material name of every surface, and merges placed pieces into a few big meshes
## (one per chunk per material) so a whole deck is ~100 draw calls with proper culling.

const CELL := 4.0

## Open sides of each corridor piece in its authored orientation. N = -Z, S = +Z, E = +X, W = -X.
const OPENS := {
	"corridor_straight": ["N", "S"],
	"corridor_door": ["N", "S"],
	"corridor_window": ["N", "S"],
	"corridor_window_double": ["N", "S"],
	"corridor_corner": ["N", "E"],
	"corridor_tjunction": ["N", "S", "E"],
	"corridor_cross": ["N", "S", "E", "W"],
	"corridor_endcap": ["N"],
	"corridor_observation": ["N"],
}
const DIR_OF := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}

static var _meshes := {}
static var _names := {}

static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null

static func _load(piece: String) -> void:
	if _meshes.has(piece):
		return
	var ps: PackedScene = load("res://kit/%s.glb" % piece)
	var inst := ps.instantiate()
	var mi := _find_mesh(inst)
	var m: ArrayMesh = mi.mesh
	# bake any node transform the importer left on the mesh instance
	var xf := mi.transform
	var p := mi.get_parent()
	while p and p != inst:
		xf = p.transform * xf
		p = p.get_parent()
	if not xf.is_equal_approx(Transform3D.IDENTITY):
		var st := SurfaceTool.new()
		var baked := ArrayMesh.new()
		for s in m.get_surface_count():
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(m, s, xf)
			st.commit(baked)
			baked.surface_set_material(baked.get_surface_count() - 1, m.surface_get_material(s))
		m = baked
	var names: Array[String] = []
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		names.append(mat.resource_name if mat else "")
	_meshes[piece] = m
	_names[piece] = names
	inst.free()

static func mesh(piece: String) -> ArrayMesh:
	_load(piece)
	return _meshes[piece]

static func material_names(piece: String) -> Array[String]:
	_load(piece)
	return _names[piece]

## Pieces that only open along their own axis (-Z / +Z) can be rolled by any quarter turn about
## that axis and still line up, because the interior is a 3 m square. Junctions can only be
## flipped upside down (roll 2), which mirrors their side opening.
static func can_roll_freely(piece: String) -> bool:
	for side: String in OPENS[piece]:
		if side == "E" or side == "W":
			return false
	return true

## Open sides of a piece after rolling it `roll` quarter turns about its local Z axis.
static func opens_after_roll(piece: String, roll: int) -> Array:
	var out := []
	for side: String in OPENS[piece]:
		if roll == 2 and side == "E":
			out.append("W")
		elif roll == 2 and side == "W":
			out.append("E")
		else:
			out.append(side)
	return out

## Rotation index k (0..3, k * 90 degrees about +Y) that maps the piece's open sides (after the
## given roll) onto `needed` (an Array of Vector2i grid directions). -1 if none fits.
static func rotation_for(piece: String, needed: Array, rng: RandomNumberGenerator = null, roll := 0) -> int:
	var want := {}
	for d: Vector2i in needed:
		want[d] = true
	var fits := []
	for k in 4:
		var got := {}
		for side: String in opens_after_roll(piece, roll):
			got[rotate_dir(DIR_OF[side], k)] = true
		if got.size() == want.size() and got.keys().all(func(d): return want.has(d)):
			fits.append(k)
	if fits.is_empty():
		return -1
	if rng:
		return fits[rng.randi() % fits.size()]
	return fits[0]

## Rotate a grid direction by k * 90 degrees about +Y (same convention as Basis(Vector3.UP, k*PI/2)).
static func rotate_dir(d: Vector2i, k: int) -> Vector2i:
	var v := Vector3(d.x, 0, d.y)
	var r := Basis(Vector3.UP, k * PI * 0.5) * v
	return Vector2i(roundi(r.x), roundi(r.z))

## World transform of a piece in `cell`, turned k quarter turns about +Y and rolled `roll`
## quarter turns about its own attachment axis (local Z, through the centre of the 3 m square
## opening at y = 1.5). The roll is what sells zero-G: floors end up on walls and ceilings.
static func cell_transform(cell: Vector2i, k: int, roll := 0) -> Transform3D:
	var rz := Basis(Vector3(0, 0, 1), roll * PI * 0.5)
	var pivot := Vector3(0, 1.5, 0)
	var local := Transform3D(rz, pivot - rz * pivot)
	return Transform3D(Basis(Vector3.UP, k * PI * 0.5), Vector3(cell.x * CELL, 0, cell.y * CELL)) * local

## Surfaces dropped per piece: the corridor door module ships with a closed pressure door, and a
## closed door in a random corridor would cut the deck in two - keep its bulkhead frame only.
const SKIP := {"corridor_door": {"Door_Panel": true, "Glass_Port": true}}

## Accumulates surfaces from many placed pieces, grouped by a material key.
class Merger:
	var tools := {}
	var counts := {}
	func add(piece: String, xf: Transform3D, keymap: Callable) -> void:
		var m := Kit.mesh(piece)
		var names := Kit.material_names(piece)
		var skip: Dictionary = Kit.SKIP.get(piece, {})
		for s in m.get_surface_count():
			if skip.has(names[s]):
				continue
			var key: String = keymap.call(names[s])
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
				counts[key] = 0
			tools[key].append_from(m, s, xf)
			counts[key] += 1
	## materials.call(key) -> Material. Every opaque key gets a trimesh collider on `body`.
	func commit(parent: Node, body: StaticBody3D, materials: Callable, no_collide: Dictionary, prefix: String) -> Array[MeshInstance3D]:
		var out: Array[MeshInstance3D] = []
		for key: String in tools:
			var st: SurfaceTool = tools[key]
			var mesh := st.commit()
			if mesh.get_surface_count() == 0:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = materials.call(key)
			mi.name = "%s_%s" % [prefix, key]
			parent.add_child(mi)
			if body and not no_collide.has(key):
				var cs := CollisionShape3D.new()
				cs.shape = mesh.create_trimesh_shape()
				body.add_child(cs)
			out.append(mi)
		return out
