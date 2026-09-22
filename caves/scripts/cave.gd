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

	# Every passage is built first, then swept, because a passage's open ends have to be
	# trimmed against the passages they run into and that needs all of them to exist.
	for p: Dictionary in data.get("passages", []):
		bores.append(Bore.new(p))
	for b in bores:
		b.build(
			func(mat: String) -> Geo: return _pick(b.points[b.points.size() / 2], mat),
			func(at: Vector3) -> bool: return _inside_another(at, b))

	for c: Dictionary in data.get("chambers", []):
		_build_chamber(c)

	_commit()
	_build_lights()
	_build_fill_lights()
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

## Is this point inside some OTHER passage's open space? Where two passages meet, their tubes
## cross at an angle and each one's wall hangs through the other's lumen - invisible rock,
## right at the junction, which is the worst possible place for it. A face that is inside its
## neighbour is not a wall at all, so it is dropped.
func _inside_another(at: Vector3, self_bore: Bore) -> bool:
	for b in bores:
		if b == self_bore:
			continue
		var n := b.nearest(at)
		var i: int = n["i"]
		var f: Basis = b.frames[i]
		var off: Vector3 = at - b.points[i]
		# Only the part of the offset in the other passage's cross-section plane matters; how
		# far along it the point sits is already accounted for by picking the nearest station.
		if absf(off.dot(f.z)) > Bore.STATION_STEP * 1.5:
			continue
		var local := Vector2(off.dot(f.x), off.dot(f.y)) * 1.12
		# Scaled OUT before the test, so a face has to be well inside the neighbour before it
		# is dropped. Cutting generously here punches holes in the floor at a junction, and
		# falling through the world is a worse bug than a little rock where two tubes cross.
		if Geo.contains(b.sections[i], local):
			return true
	return false

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

	# Where the chamber's shell has to be opened. A hand-written radius per mouth is a number
	# that is wrong the moment a passage moves, and when it is too small the leftover shell
	# hangs across the passage as rock you cannot see and cannot get past - which is exactly
	# what it did, leaving 31 cm of headroom three metres into a 1.5 m tube.
	#
	# So the cuts are derived instead: any station of any passage that falls inside this
	# chamber opens a hole the size of the passage there. Explicit mouths stay as a way to open
	# something bigger by hand, but nothing depends on them being right.
	var mouths: Array = []
	for m: Dictionary in data.get("mouths", []):
		if m.get("into", "") != c.get("id", ""):
			continue
		var a: Array = m["at"]
		mouths.append([Vector3(a[0], a[1], a[2]), float(m.get("r", 1.0))])

	var reach: Vector3 = size * 0.5 + Vector3(2.5, 2.5, 2.5)
	for b in bores:
		for i in b.points.size():
			var p: Vector3 = b.points[i]
			if ((p - centre) / reach).length_squared() > 1.0:
				continue
			var sec: PackedVector2Array = b.sections[i]
			var r := 0.0
			for q: Vector2 in sec:
				r = maxf(r, q.length())
			mouths.append([p, r * 1.3 + 0.4])

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

## Light the cave itself, so the headlamp is not the only thing you can see by. Off when
## CaveGame.lit is false, which restores the dark version the atmosphere was designed around.
##
## One omni every FILL_SPACING metres down each passage, sat a little above the centreline, with
## a range derived from how big the passage is there - a shaft gets a lamp that fills it, a
## bedding crawl gets one that does not spill forty metres up the passage. Chambers get a ring
## plus one high, because a single light in the middle of a thirty-metre room reads as a bulb
## rather than as a room.
##
## All unshadowed. The Compatibility renderer pays per light per pixel and shadow maps are the
## most expensive thing in either of these two games, so the fill is light and the one shadow
## budget stays on the headlamp.
const FILL_SPACING := 7.5
const FILL_SPACING_LOW := 12.0
const FILL_ENERGY := 1.5
const FILL_TINT := Color(1.0, 0.95, 0.88)
const FILL_MAX := 48

func _build_fill_lights() -> void:
	if not Cave.lit:
		return
	var spacing: float = FILL_SPACING_LOW if Cave.low_quality else FILL_SPACING
	var made := 0

	for b in bores:
		var step: int = maxi(int(round(spacing / Bore.STATION_STEP)), 1)
		var i: int = step / 2
		while i < b.points.size() and made < FILL_MAX:
			var sec: PackedVector2Array = b.sections[i]
			var lo := INF
			var hi := -INF
			var wide := 0.0
			for q: Vector2 in sec:
				lo = minf(lo, q.y)
				hi = maxf(hi, q.y)
				wide = maxf(wide, absf(q.x))
			# Just under the ceiling, the way anything you actually hang in a cave ends up.
			var at: Vector3 = b.points[i] + b.frames[i].y * (hi * 0.55)
			_fill_light(at, clampf(maxf(hi - lo, wide * 2.0) * 2.6 + 3.0, 4.0, 16.0))
			made += 1
			i += step

	for c: Dictionary in data.get("chambers", []):
		var ctr: Array = c.get("centre", [0, 0, 0])
		var sz: Array = c.get("size", [10, 6, 10])
		var centre := Vector3(ctr[0], ctr[1], ctr[2])
		var size := Vector3(sz[0], sz[1], sz[2])
		var reach: float = maxf(size.x, size.z) * 0.75
		for k in 4:
			if made >= FILL_MAX:
				break
			var a := TAU * (float(k) + 0.5) / 4.0
			_fill_light(centre + Vector3(cos(a) * size.x * 0.26, size.y * 0.16, sin(a) * size.z * 0.26),
				reach, 1.25)
			made += 1
		if made < FILL_MAX:
			_fill_light(centre + Vector3(0, size.y * 0.34, 0), reach * 1.2, 1.1)
			made += 1

	print("[cave] lit: %d fill lights at %.1f m spacing" % [made, spacing])

func _fill_light(at: Vector3, reach: float, energy := FILL_ENERGY) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.omni_range = reach
	l.light_energy = energy
	l.light_color = FILL_TINT
	l.light_specular = 0.12
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 34.0
	l.distance_fade_length = 10.0
	add_child(l)

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

## Below this there is no cave, only the void outside the shell. The caver's safety net uses it
## to notice it has fallen out of the world.
func floor_limit() -> float:
	if data.has("floor_limit"):
		return float(data["floor_limit"])
	var lowest := 0.0
	for b in bores:
		for p: Vector3 in b.points:
			lowest = minf(lowest, p.y)
	return lowest - 8.0

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
