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

# ---------------------------------------------------------------- what is already on the wall
## Wall fittings only ever mount on a handful of known planes - the two sides of a corridor cell,
## the three walls of a room - so rather than voxelising a whole piece, each of those planes gets a
## flat profile: a grid across the wall holding how far the geometry standing on it reaches into
## the room. Ribs, pipe runs, light strips, window frames, door surrounds, consoles and racks all
## show up in it, and a patch of wall with nothing proud of it is a patch you can bolt to.
##
## Small (a few thousand cells per plane), built once per piece per plane, cached for the session.
const PROFILE_RES := 0.10    ## grid pitch across the wall
const PROFILE_DEPTH := 1.7   ## how far into the room we bother looking

## Surfaces nothing gets bolted over however flat they are: lamps, glazing, screens and doors. The
## kit sets its light strips flush into the wall, so depth alone would happily hang a locker on one.
const KEEP_OFF := {
	"Light_Strip": true, "Light_Warn": true, "Light_Data": true, "Light_Green": true,
	"Screen_Lit": true, "Glass_Window": true, "Glass_Port": true, "Door_Panel": true,
}

static var _profiles := {}

## `axis` 0 = an X wall, 2 = a Z wall. `coord` is the nominal plane in piece space (1.5 for a
## corridor side, 5.5 for a room wall). Keys are Vector2i cells across the plane; values are how
## far the geometry there stands proud of it, in metres - with the keep-off surfaces marked
## unmountable outright.
static func wall_profile(piece: String, axis: int, coord: float) -> Dictionary:
	var key := "%s|%d|%.2f" % [piece, axis, coord]
	if _profiles.has(key):
		return _profiles[key]
	var prof := {}
	var other := 2 if axis == 0 else 0
	var sign := signf(coord)
	var m := mesh(piece)
	var names := material_names(piece)
	for s in m.get_surface_count():
		var forbidden: bool = KEEP_OFF.has(names[s])
		var arrays := m.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := idx.size() if idx.size() > 0 else verts.size()
		var i := 0
		while i < count:
			var tri := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
			for k in 3:
				tri[k] = verts[idx[i + k]] if idx.size() > 0 else verts[i + k]
			i += 3
			# depth is how far inside the wall plane a vertex sits. Anything behind the wall or out
			# in the middle of the room is not this plane's business.
			var deepest := -1.0
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for v: Vector3 in tri:
				var d: float = (coord - v[axis]) * sign
				if d < -0.06 or d > PROFILE_DEPTH:
					continue
				deepest = maxf(deepest, 9.0 if forbidden else d)
				var p := Vector2(v[other], v.y)
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
			if deepest < 0.0:
				continue
			var c0 := Vector2i(floori(lo.x / PROFILE_RES), floori(lo.y / PROFILE_RES))
			var c1 := Vector2i(floori(hi.x / PROFILE_RES), floori(hi.y / PROFILE_RES))
			for a in range(c0.x, c1.x + 1):
				for b in range(c0.y, c1.y + 1):
					var cell := Vector2i(a, b)
					if deepest > float(prof.get(cell, -1.0)):
						prof[cell] = deepest
	_profiles[key] = prof
	return prof

## Is this rectangle of wall bare enough to bolt to? `face` is how far the finished wall surface
## itself stands proud of the nominal plane - the corridor pieces panel their walls 6 cm out, the
## rooms do not - and anything more than a few centimetres beyond that is a rib, a pipe, a console
## or a lamp, and is somebody else's spot.
static func wall_clear(piece: String, axis: int, coord: float, lo: Vector2, hi: Vector2,
		face := 0.0, tolerance := 0.03) -> bool:
	var prof := wall_profile(piece, axis, coord)
	var limit := face + tolerance
	var c0 := Vector2i(floori(lo.x / PROFILE_RES), floori(lo.y / PROFILE_RES))
	var c1 := Vector2i(floori(hi.x / PROFILE_RES), floori(hi.y / PROFILE_RES))
	for a in range(c0.x, c1.x + 1):
		for b in range(c0.y, c1.y + 1):
			if float(prof.get(Vector2i(a, b), -1.0)) > limit:
				return false
	return true

## Find somewhere on this wall a `w` x `h` fitting actually fits, searched rather than guessed:
## every position on the grid inside [lo, hi] whose whole footprint is bare, picked from at random.
## Returns Vector2.INF when the wall has no room for it, which is a perfectly good answer - a lot
## of this kit's wall is rib, pipe, console and lamp, and a fitting that is not there is invisible
## while a fitting through a pipe is the first thing anyone sees.
## `taken` is the wall's own running tally of what previous fittings have used - pass the same
## dictionary for every fitting on one wall and they stop landing on top of each other. The cells
## the chosen spot covers are marked in it before this returns.
static func find_clear_spot(piece: String, axis: int, coord: float, face: float, w: float,
		h: float, lo: Vector2, hi: Vector2, rng: RandomNumberGenerator,
		taken: Dictionary = {}) -> Vector2:
	var prof := wall_profile(piece, axis, coord)
	var limit := face + 0.03
	# rounded, not ceilinged: the kit's bare panels are only six cells wide and rounding up a
	# fitting's half-width by a whole cell was enough to reject every one of them
	var hw := maxi(1, roundi(w * 0.5 / PROFILE_RES))
	var hh := maxi(1, roundi(h * 0.5 / PROFILE_RES))
	var c0 := Vector2i(floori(lo.x / PROFILE_RES), floori(lo.y / PROFILE_RES))
	var c1 := Vector2i(floori(hi.x / PROFILE_RES), floori(hi.y / PROFILE_RES))
	var spots: Array[Vector2i] = []
	var a := c0.x
	while a <= c1.x:
		var b := c0.y
		while b <= c1.y:
			var ok := true
			for u in range(a - hw, a + hw + 1):
				for v in range(b - hh, b + hh + 1):
					var cell := Vector2i(u, v)
					if taken.has(cell) or float(prof.get(cell, -1.0)) > limit:
						ok = false
						break
				if not ok:
					break
			if ok:
				spots.append(Vector2i(a, b))
			b += 2
		a += 2
	if spots.is_empty():
		return Vector2.INF
	var pick: Vector2i = spots[rng.randi() % spots.size()]
	for u in range(pick.x - hw, pick.x + hw + 1):        # this patch is spoken for now
		for v in range(pick.y - hh, pick.y + hh + 1):
			taken[Vector2i(u, v)] = true
	return Vector2((pick.x + 0.5) * PROFILE_RES, (pick.y + 0.5) * PROFILE_RES)

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

# ---------------------------------------------------------------- windows
static var _apertures := {}

## The glazed openings in a piece's outer walls, in the piece's own frame: one per glazed wall side,
## [{center, normal (outward), u, v (half extents across the glass)}]. Read from the Glass_Window
## surfaces, so a window added to the kit is picked up without code. Glass well inside a module
## (a fume hood sash) is not an outside window and is skipped, as is anything facing up or down.
static func window_apertures(piece: String) -> Array:
	if _apertures.has(piece):
		return _apertures[piece]
	var out := []
	var m := mesh(piece)
	var names := material_names(piece)
	var half := 6.0 if piece.begins_with("room_") else CELL * 0.5
	var groups := {}
	for s in m.get_surface_count():
		if names[s] != "Glass_Window":
			continue
		var arrays := m.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := idx.size() if idx.size() > 0 else verts.size()
		var i := 0
		while i < count:
			var a: Vector3 = verts[idx[i]] if idx.size() > 0 else verts[i]
			var b: Vector3 = verts[idx[i + 1]] if idx.size() > 0 else verts[i + 1]
			var c: Vector3 = verts[idx[i + 2]] if idx.size() > 0 else verts[i + 2]
			i += 3
			var cr := (b - a).cross(c - a)
			var area := cr.length() * 0.5
			if area < 1e-5:
				continue
			var nrm := cr.normalized()
			var axis := 0
			if absf(nrm.y) > absf(nrm[axis]):
				axis = 1
			if absf(nrm.z) > absf(nrm[axis]):
				axis = 2
			if axis == 1:
				continue
			var coord := (a[axis] + b[axis] + c[axis]) / 3.0
			if absf(coord) < half - 0.8:
				continue
			var key := "%d|%d" % [axis, int(signf(coord))]
			if not groups.has(key):
				groups[key] = {"axis": axis, "sign": signf(coord), "area": 0.0,
					"lo": Vector3(INF, INF, INF), "hi": Vector3(-INF, -INF, -INF)}
			var g: Dictionary = groups[key]
			g["area"] = float(g["area"]) + area
			for v: Vector3 in [a, b, c]:
				g["lo"] = (g["lo"] as Vector3).min(v)
				g["hi"] = (g["hi"] as Vector3).max(v)
	for key in groups:
		var g: Dictionary = groups[key]
		if float(g["area"]) < 0.25:
			continue
		var lo: Vector3 = g["lo"]
		var hi: Vector3 = g["hi"]
		var axis: int = g["axis"]
		var ext := (hi - lo) * 0.5
		var normal := Vector3.ZERO
		normal[axis] = float(g["sign"])
		var other := 2 if axis == 0 else 0
		var u := Vector3.ZERO
		u[other] = ext[other]
		out.append({"center": (lo + hi) * 0.5, "normal": normal, "u": u, "v": Vector3(0, ext.y, 0)})
	_apertures[piece] = out
	return out

