extends Node3D
## Builds Sowbelly from cave/sowbelly.json: sweeps every passage, trims the junctions,
## chunks the lot per material, and hangs a trimesh collider off the same vertices.
##
## The chunking is derelict-orbit's, at the same 20 m granularity (station.gd:117). It matters
## more here than it did there, because the only light in a cave reaches about fifteen metres
## and the fog eats everything past that - so frustum and distance culling are doing almost all
## the work, and chunks small enough to be culled individually are the whole performance story.
## A passage is one Bore; a Bore's faces are routed per chunk and per material by the callback
## it is handed, so nothing is ever built twice.
##
## There is exactly ONE kind of thing in a cave: a passage. A room is a short passage with a big
## section, a shaft is a vertical one, a lead is one that pinches out. That is not a
## simplification, it is the fix for the worst bug this project has had - rooms used to be
## closed blob shells composited with swept tubes, the two were joined by cutting holes in each
## and hoping they lined up, and what was left over was rock you could not see and could not
## walk through, in the middle of the room you land in. One kind of object means one junction
## rule, and the rule can be exact.
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
var start_look := Vector3(0, -0.4, -1)
var start_on_rope := false   ## you begin clipped on, hanging, rather than stood somewhere

var _body: StaticBody3D
var decor: StaticBody3D    ## stalactites and the like - solid, but not part of the passage wall
var seams: StaticBody3D    ## junction lips - solid, double-sided, not part of the passage wall
var _chunks := {}          ## "key|material" -> Geo, during the build only
var _tri_count := 0
var _mesh_count := 0
var _drips: Array[Vector3] = []
var _drip_timer := 0.0
var _trimmed := 0          ## faces dropped for being inside another passage
var _seam_tris := 0        ## triangles kept but drawn both ways, at a junction (see Bore.SEAM)

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

	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.name = "Rock"
	add_child(_body)

	# Formations are solid rock you can bark a shin on, but they are not the passage wall, and
	# the clearance test has to be able to tell the difference: a stalactite half way across a
	# room is scenery, the same face belonging to a tunnel that runs through the room is a bug.
	decor = StaticBody3D.new()
	decor.collision_layer = 1
	decor.collision_mask = 0
	decor.name = "Formations"
	add_child(decor)

	# The lips at the junctions, on their own body for the same reason: they are rock, they are
	# meant to be in the way, and they are drawn from both sides so they are never the invisible
	# kind. The clearance test skips them and the leak test does not.
	seams = StaticBody3D.new()
	seams.collision_layer = 1
	seams.collision_mask = 0
	seams.name = "Seams"
	add_child(seams)

	# Every passage is constructed first and swept afterwards, because every face of every one
	# of them is trimmed against every other, and that needs all of them to exist.
	for p: Dictionary in data.get("passages", []):
		bores.append(Bore.new(p))
	for b in bores:
		b.build(
			func(mat: String) -> Geo: return _pick(b.points[b.points.size() / 2], mat),
			func(corners: PackedVector3Array, margin: float) -> int:
				return _inside_another(corners, b, margin))

	for b in bores:
		if b.kind == "room":
			_build_speleothems(b)
		_build_rubble(b)

	_resolve_start()
	_commit()
	_build_lights()
	_build_fill_lights()
	_build_ropes()
	_collect_drips()

	var rooms := 0
	var run := 0.0
	for b in bores:
		run += b.length()
		if b.kind == "room":
			rooms += 1
	print("[cave] %s: %d passages (%d rooms), %.0f m, %d meshes, %d tris (%d seam), %d cut, %d ms" % [
		data.get("name", "?"), bores.size(), rooms, run,
		_mesh_count, _tri_count, _seam_tris, _trimmed, Time.get_ticks_msec() - t0])

## Where the player begins. Taken from the geometry rather than written down: `start` names a
## rigged rope and how far down it you start, and the point comes out of the rope itself. A
## hand-written coordinate was wrong twice - once 1.6 m outside a 1.2 m shaft with no floor
## within forty metres - and there is no way to be sure by looking at it. This cannot be wrong
## unless the rope is.
func _resolve_start() -> void:
	var s = data.get("start", {})
	if s is Dictionary and s.has("on"):
		for r: Dictionary in data.get("rig", []):
			if r.get("id", "") != s["on"]:
				continue
			var top: Array = r["top"]
			var bottom: Array = r["bottom"]
			var a := Vector3(top[0], top[1], top[2])
			var b := Vector3(bottom[0], bottom[1], bottom[2])
			var down: float = float(s.get("down", 3.0))
			start_point = a + (b - a).normalized() * down
			start_on_rope = true
			break
	elif s is Array and s.size() == 3:
		start_point = Vector3(s[0], s[1], s[2])
	var l: Array = (s as Dictionary).get("look", [0, -0.4, -1]) if s is Dictionary else [0, -0.4, -1]
	start_look = Vector3(l[0], l[1], l[2])

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

## Is this FACE inside some OTHER passage's open space? Where two passages meet, their tubes
## cross at an angle and each one's wall hangs through the other's lumen - invisible rock, right
## at the junction, which is the worst possible place for it. A face inside its neighbour is not
## a wall at all, so it goes; one across the edge of a mouth is quartered and asked again.
## Bore.swallows_face decides all three answers; Bore.build says what each one costs.
func _inside_another(corners: PackedVector3Array, self_bore: Bore, margin: float) -> int:
	var worst: int = Bore.KEEP
	for b in bores:
		if b == self_bore:
			continue
		var say: int = b.swallows_face(corners, margin)
		# CUT wins over SEAM: if any neighbour encloses the face outright it is not a wall,
		# whatever another one thinks of it.
		if say == Bore.CUT:
			_trimmed += 1
			return Bore.CUT
		if say == Bore.SEAM:
			worst = Bore.SEAM
	return worst

## Is this point inside ANY passage's open space? `CAVE_AUTOTEST=clear` walks a leaking ray with
## it to say where the ray left the cave, which beats reporting where it started: a hole a few
## centimetres across at a junction is not findable from the other end of a passage.
func inside_any(at: Vector3, margin := 1.0) -> bool:
	for b in bores:
		if b.contains_point(at, margin):
			return true
	return false

func _commit() -> void:
	for key: String in _chunks:
		var g: Geo = _chunks[key]
		var mat: String = key.split("|")[1]
		var onto: StaticBody3D = _body
		if mat == "flow":
			onto = decor
		elif mat == "seam":
			onto = seams
			_seam_tris += g.tris
		var mi := g.commit(palette.get_mat(mat), self, onto, key.replace("|", "_"))
		if mi:
			_mesh_count += 1
			_tri_count += g.tris
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_chunks.clear()

# ---------------------------------------------------------------- rooms

## Stalactites on the ceiling of a room and stalagmites under them. Rooms are passages, so the
## placement rides the passage's own frames - hang them off the roof of each section rather than
## off a box, and they land where the section actually is however it bends.
func _build_speleothems(b: Bore) -> void:
	var count := _count(b.id, "speleothems")
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = b.points.size() * 17 + count
	var g: Geo = _pick(b.points[b.points.size() / 2], "flow")
	for i in count:
		var at: int = rng.randi_range(1, maxi(b.points.size() - 2, 1))
		if _borrowed(b, at):
			continue
		var sec: PackedVector2Array = b.sections[at]
		var lo := INF
		var hi := -INF
		var half := 0.0
		for q: Vector2 in sec:
			lo = minf(lo, q.y)
			hi = maxf(hi, q.y)
			half = maxf(half, absf(q.x))
		var f: Basis = b.frames[at]
		# Out towards the walls rather than down the middle of the room: the line you walk is
		# the line you look along, and a stalagmite in it reads as a bug even when it is not.
		var side: float = half * rng.randf_range(0.35, 0.86) * (1.0 if rng.randf() < 0.5 else -1.0)
		var drop: float = rng.randf_range(0.25, 0.95)
		var thick: float = rng.randf_range(0.05, 0.17)
		var roof: Vector3 = b.points[at] + f.y * (hi - 0.04) + f.x * side
		if _decor_debug:
			print("[decor] %s spike side %+.2f half %.2f drop %.2f at %s"
				% [b.id, side, half, drop, roof])
		g.spike(roof, drop, thick, false, 7)
		# One in six is a column: the stalactite met the stalagmite growing under it and the two
		# joined, which takes long enough that a cave with a few of them reads as an old one.
		var gap: float = (hi - lo) - drop
		if rng.randf() < 0.17 and gap > 0.1:
			g.spike(b.points[at] + f.y * (lo + 0.02) + f.x * side, gap, thick * 0.85, true, 7)
		elif rng.randf() < 0.62:
			g.spike(b.points[at] + f.y * (lo + 0.02) + f.x * side,
				rng.randf_range(0.18, 0.62), thick * rng.randf_range(0.9, 1.6), true, 7)

## Blocks on the floor. A dissolved tube is a smooth shell and nothing that has had a few
## thousand years of roof falling into it stays one, so passages get loose rock in them - which
## is also the difference between crawling along a pipe and crawling over something.
##
## They ride the section the same way the formations do, are kept off the centreline, and are
## capped at a fraction of the passage's own height, because rubble you cannot get over in a
## 45 cm crawl is a wall.
func _build_rubble(b: Bore) -> void:
	var count := _count(b.id, "rubble")
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = b.points.size() * 31 + count * 7
	var g: Geo = _pick(b.points[b.points.size() / 2], "flow")
	for i in count:
		var at: int = rng.randi_range(1, maxi(b.points.size() - 2, 1))
		if _borrowed(b, at):
			continue
		var sec: PackedVector2Array = b.sections[at]
		var lo := INF
		var hi := -INF
		var half := 0.0
		for q: Vector2 in sec:
			lo = minf(lo, q.y)
			hi = maxf(hi, q.y)
			half = maxf(half, absf(q.x))
		var f: Basis = b.frames[at]
		var wide: float = clampf(half * rng.randf_range(0.16, 0.42), 0.06, 0.55)
		var tall: float = clampf((hi - lo) * rng.randf_range(0.10, 0.26), 0.05, 0.42)

		# How far out it has to sit to leave the route alone. A chunk is jittered outward by up
		# to a third of its own size, so its real reach is wider than it was asked for, and the
		# body still has to get past on the centreline. Everything here is measured from the
		# block's INNER face for that reason.
		var reach: float = wide * 0.5 * (1.0 + Geo.CHUNK_JITTER)
		var room: float = half - reach
		var side: float = room * rng.randf_range(0.55, 0.98)
		if absf(side) - reach < RUBBLE_KEEP:
			# No room beside the route. Lay it down instead: a slab you crawl OVER is rubble
			# too, and it is the only kind a fifty-centimetre crawl can have. One that stands up
			# in there is a wall, and a wall in a tunnel is the bug this cave keeps being told
			# about.
			tall = minf(tall, RUBBLE_SLAB)
			side = room * rng.randf_range(-0.9, 0.9)
		var at_p: Vector3 = b.points[at] + f.y * (lo + tall * 0.40) + f.x * side
		if _decor_debug:
			print("[decor] %s rubble side %+.2f reach %.2f half %.2f tall %.2f at %s"
				% [b.id, side, reach, half, tall, at_p])
		g.chunk(at_p, Vector3(wide, tall, wide * rng.randf_range(0.6, 1.5)), rng.randi())

## Is this station somewhere another passage already is?
##
## Passages join by overlapping - the last stations of one sit inside the next - so the last
## couple of metres of a crawl are geometrically inside a room, and the crawl's own walls there
## have been cut away. Decorate those stations and the blocks come out sized for a 90 cm tube
## and standing loose in the middle of a chamber, on the line a player walks. That is how the
## Gullet put a boulder in the Bone Box, and it is the same shape of mistake as the tube walls
## that used to hang invisibly inside the rooms: geometry placed by one passage in a place
## another passage owns.
func _borrowed(b: Bore, at: int) -> bool:
	var one := PackedVector3Array([b.points[at]])
	return _inside_another(one, b, 1.0) != Bore.KEEP

func _count(id: String, key: String) -> int:
	for p: Dictionary in data.get("passages", []):
		if p.get("id", "") == id:
			return int(p.get(key, 0))
	return 0

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
## How much of the centreline rubble has to leave alone, and how tall a block may be when it
## cannot. Half a pair of shoulders is 23 cm; this is that plus a hand's width of margin.
var _decor_debug := OS.has_environment("CAVE_DECOR")

const RUBBLE_KEEP := 0.30
const RUBBLE_SLAB := 0.07

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
		# A room needs more than a passage: one lamp in the middle of a nine-metre chamber is a
		# bulb with a dark room around it, and that is what the Cellar looked like.
		var reach: float = spacing * (0.5 if b.kind == "room" else 1.0)
		var step: int = maxi(int(round(reach / Bore.STATION_STEP)), 1)
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
			var size: float = maxf(hi - lo, wide * 2.0)
			# Energy scales with the passage, not just range. A lamp bright enough to reach the
			# far wall of a nine-metre room is thirty centimetres from the wall of a one-metre
			# tube, and burns it white - which is how a crawl in wet limestone ended up looking
			# like a lit porcelain pipe. Small passage, small lamp: the wall is closer anyway.
			_fill_light(at, clampf(size * 2.6 + 3.0, 4.0, 16.0),
				FILL_ENERGY * clampf(size / 2.6, 0.30, 1.0))
			made += 1
			i += step

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
			best = {"id": b.id, "label": b.label, "along": n["along"], "t": n["t"],
				"dist": n["dist"], "lead": _is_lead(b.id)}
	if best_d > 6.0:
		return {}
	return best

## A lead is a passage that pinches out. The player has to be told, once, on the way in: a
## passage that stops being big enough for a human is indistinguishable from a bug unless the
## cave says it meant it, and "I hit an impassable dead end" is what that looks like reported.
func _is_lead(id: String) -> bool:
	for p: Dictionary in data.get("passages", []):
		if p.get("id", "") == id:
			return bool(p.get("dead_end", false))
	return false

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
