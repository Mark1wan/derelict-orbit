extends Node3D
## Builds Sowbelly from cave/sowbelly.json: sweeps every passage, blows out every chamber,
## chunks the lot per material, and hangs a trimesh collider off the same vertices.
##
## The chunking is derelict-orbit's, at the same 20 m granularity (station.gd:117). It matters
## more here than it did there, because the only light in a cave reaches about fifteen metres
## and the fog eats everything past that - so frustum and distance culling are doing almost all
## the work, and chunks small enough to be culled individually are the whole performance story.
## A passage is one Bore; a Bore's faces are routed per chunk and per material by the callback
## it is handed, so nothing is ever built twice.
##
## Nothing in here is procedural yet. The plan is that a generator emits the same JSON a human
## would write, which is why the shape of that file is a list of centrelines and profiles
## rather than anything cleverer.

const CHUNK := 20.0
const CAVE_FILE := "res://cave/sowbelly.json"

var data := {}
var palette: CavePalette
var bores: Array[Bore] = []
var ropes: Array[Rope] = []
var start_point := Vector3(0, 0.4, 1.6)
var start_look := Vector3(0, -0.35, -1)

var _body: StaticBody3D
var _chunks := {}          ## "key|material" -> Geo, during the build only
var _tri_count := 0
var _mesh_count := 0
var _drips: Array[Vector3] = []
var _drip_timer := 0.0

func _ready() -> void:
	Cave.cave = self
	palette = CavePalette.new()
	build()

func build() -> void:
	var t0 := Time.get_ticks_msec()
	data = _load()
	if data.is_empty():
		push_error("cave: could not read %s" % CAVE_FILE)
		return

	var s: Array = data.get("start", [0, 0.4, 1.6])
	start_point = Vector3(s[0], s[1], s[2])
	var l: Array = data.get("start_look", [0, -0.35, -1])
	start_look = Vector3(l[0], l[1], l[2])

	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.name = "Rock"
	add_child(_body)

	for p: Dictionary in data.get("passages", []):
		var b := Bore.new(p)
		bores.append(b)
		b.build(func(mat: String) -> Geo: return _pick(b.points[b.points.size() / 2], mat))

	for c: Dictionary in data.get("chambers", []):
		_build_chamber(c)

	_commit()
	_build_lights()
	_build_ropes()
	_collect_drips()

	print("[cave] %s: %d passages, %d chambers, %d meshes, %d tris, %d ms" % [
		data.get("name", "?"), bores.size(), data.get("chambers", []).size(),
		_mesh_count, _tri_count, Time.get_ticks_msec() - t0])

func _load() -> Dictionary:
	if not FileAccess.file_exists(CAVE_FILE):
		return {}
	var f := FileAccess.open(CAVE_FILE, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

# ---------------------------------------------------------------- chunking

## Hand back the batch for this material in the chunk this point falls in, making it if it is
## the first face to land there. One Geo becomes one mesh becomes one draw call.
func _pick(at: Vector3, mat: String) -> Geo:
	var key := "%d_%d_%d|%s" % [floori(at.x / CHUNK), floori(at.y / CHUNK), floori(at.z / CHUNK), mat]
	if not _chunks.has(key):
		_chunks[key] = Geo.new()
	return _chunks[key]

func _commit() -> void:
	for key: String in _chunks:
		var g: Geo = _chunks[key]
		var mat: String = key.split("|")[1]
		var mi := g.commit(palette.get_mat(mat), self, _body, key.replace("|", "_"))
		if mi:
			_mesh_count += 1
			_tri_count += g.tris
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_chunks.clear()

# ---------------------------------------------------------------- chambers

## A chamber is a displaced sphere seen from the inside, with its floor routed to breakdown
## and holes cut wherever a passage arrives - otherwise there would be a membrane of rock
## stretched across every mouth.
func _build_chamber(c: Dictionary) -> void:
	var ctr: Array = c.get("centre", [0, 0, 0])
	var sz: Array = c.get("size", [10, 6, 10])
	var centre := Vector3(ctr[0], ctr[1], ctr[2])
	var size := Vector3(sz[0], sz[1], sz[2])

	var n := FastNoiseLite.new()
	n.seed = int(c.get("seed", 1))
	n.frequency = 0.8
	n.fractal_octaves = 3
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	var mouths: Array = []
	for m: Dictionary in data.get("mouths", []):
		if m.get("into", "") != c.get("id", ""):
			continue
		var a: Array = m["at"]
		mouths.append([Vector3(a[0], a[1], a[2]), float(m.get("r", 1.0))])

	var wall_key: String = c.get("wall", "rock_tri")
	var floor_key: String = c.get("floor", "rubble")
	var g := Geo.new()
	var cb := func(mid: Vector3, up: float) -> Geo:
		for m: Array in mouths:
			if mid.distance_to(m[0]) < m[1]:
				return null
		return _pick(mid, floor_key if up < -0.42 else wall_key)
	g.blob(centre, size, 40, 24, float(c.get("rough", 1.0)), n, cb)

	_build_speleothems(c, centre, size, n)

## Stalactites on the ceiling and stalagmites under them, placed by the same noise field that
## shaped the chamber so they land where the water would actually have run.
func _build_speleothems(c: Dictionary, centre: Vector3, size: Vector3, n: FastNoiseLite) -> void:
	var count := int(c.get("speleothems", 0))
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.get("seed", 1)) + 77
	var g: Geo = _pick(centre, "flow")
	for i in count:
		var th := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * 0.42
		var x := centre.x + cos(th) * size.x * rad
		var z := centre.z + sin(th) * size.z * rad
		var roof := centre.y + size.y * 0.42
		var floor_y := centre.y - size.y * 0.44
		var len_ := rng.randf_range(0.25, 1.5)
		g.spike(Vector3(x, roof, z), len_, rng.randf_range(0.05, 0.17), false, 6)
		if rng.randf() < 0.55:
			g.spike(Vector3(x + rng.randf_range(-0.2, 0.2), floor_y, z + rng.randf_range(-0.2, 0.2)),
				rng.randf_range(0.2, 0.9), rng.randf_range(0.07, 0.2), true, 6)

# ---------------------------------------------------------------- fittings

## The only light that is not on your head: daylight down the entrance shaft. It reaches maybe
## twenty metres and then it is gone, and watching it go is the point of it.
func _build_lights() -> void:
	for l: Dictionary in data.get("lights", []):
		var a: Array = l.get("at", [0, 0, 0])
		var aim: Array = l.get("aim", [0, -1, 0])
		var col: Array = l.get("colour", [1, 1, 1])
		var s := SpotLight3D.new()
		s.position = Vector3(a[0], a[1], a[2])
		s.look_at_from_position(Vector3(a[0], a[1], a[2]),
			Vector3(a[0] + aim[0], a[1] + aim[1], a[2] + aim[2]), Vector3.BACK)
		s.light_color = Color(col[0], col[1], col[2])
		s.light_energy = float(l.get("energy", 2.0))
		s.spot_range = float(l.get("range", 20.0))
		s.spot_angle = float(l.get("angle", 30.0))
		s.spot_attenuation = 1.6
		s.shadow_enabled = false
		s.name = l.get("id", "light")
		add_child(s)

func _build_ropes() -> void:
	for r: Dictionary in data.get("rig", []):
		var rope := Rope.new()
		add_child(rope)
		rope.setup(r, palette.get_mat("rope") as StandardMaterial3D)
		ropes.append(rope)

## Places water is falling. Chosen where a wet passage runs level enough to pool, so the drips
## line up with the flowstone rather than being scattered at random.
func _collect_drips() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for b in bores:
		if b.wall_mat != "rock_wet" and b.floor_mat != "mud":
			continue
		var step: int = maxi(b.points.size() / 6, 1)
		for i in range(0, b.points.size(), step):
			if rng.randf() < 0.6:
				_drips.append(b.points[i] + Vector3(0, 0.1, 0))
	for c: Dictionary in data.get("chambers", []):
		var ctr: Array = c.get("centre", [0, 0, 0])
		var sz: Array = c.get("size", [10, 6, 10])
		for i in 6:
			_drips.append(Vector3(
				ctr[0] + rng.randf_range(-1, 1) * sz[0] * 0.35,
				ctr[1] - sz[1] * 0.40,
				ctr[2] + rng.randf_range(-1, 1) * sz[2] * 0.35))

func _process(delta: float) -> void:
	if _drips.is_empty() or Cave.caver == null:
		return
	_drip_timer -= delta
	if _drip_timer > 0.0:
		return
	_drip_timer = randf_range(0.7, 3.4)
	# Only the drips you could actually hear. A cave that plays every drip everywhere is a
	# rainstorm; one that plays the near ones tells you where the water is.
	var eye: Vector3 = Cave.caver.global_position
	var near: Array[Vector3] = []
	for p in _drips:
		if p.distance_squared_to(eye) < 18.0 * 18.0:
			near.append(p)
	if near.is_empty():
		return
	Sfx.play_at("drip", near[randi() % near.size()], -12.0, 16.0, randf_range(0.8, 1.35))

# ---------------------------------------------------------------- queries

## Which passage is this point in, for the survey slate. Linear over every station of every
## passage, which is 230-odd distance checks; at the 0.25 s the slate refreshes on, that is
## free, and it saves keeping a spatial index in sync with nothing.
func passage_at(p: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for b in bores:
		var n := b.nearest(p)
		if n["dist"] < best_d:
			best_d = n["dist"]
			best = {"id": b.id, "label": b.label, "along": n["along"], "t": n["t"], "dist": n["dist"]}
	for c: Dictionary in data.get("chambers", []):
		var ctr: Array = c.get("centre", [0, 0, 0])
		var sz: Array = c.get("size", [10, 6, 10])
		var centre := Vector3(ctr[0], ctr[1], ctr[2])
		var half := Vector3(sz[0], sz[1], sz[2]) * 0.5
		var local := (p - centre) / half
		if local.length() < 1.0:
			return {"id": c.get("id", ""), "label": c.get("label", ""), "along": 0.0, "t": 0.0, "dist": 0.0}
	if best_d > 6.0:
		return {}
	return best

func bore(id: String) -> Bore:
	for b in bores:
		if b.id == id:
			return b
	return null

## Somewhere sensible to put the caver for a test or a warm-up tour: the given fraction along
## the named passage, lifted to sit on the floor of the section there.
func point_in(id: String, t: float) -> Vector3:
	var b := bore(id)
	if b == null:
		return start_point
	var i: int = clampi(int(round(t * float(b.points.size() - 1))), 0, b.points.size() - 1)
	var sec: PackedVector2Array = b.sections[i]
	var lo := INF
	for q: Vector2 in sec:
		lo = minf(lo, q.y)
	return b.points[i] + b.frames[i].y * (lo + 0.05)

## The direction the passage runs at that point, so a test or a warm-up tour can face the way
## it is going. Geo.frames puts the tangent in basis.z, so this is +z and not the -z a camera
## would use - they are not the same convention and mixing them walks you out backwards.
func heading_in(id: String, t: float) -> Vector3:
	var b := bore(id)
	if b == null:
		return start_look
	var i: int = clampi(int(round(t * float(b.points.size() - 1))), 0, b.points.size() - 1)
	var f: Basis = b.frames[i]
	return f.z
