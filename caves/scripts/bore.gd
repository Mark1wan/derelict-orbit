class_name Bore
extends RefCounted
## One passage, from the data in cave/sowbelly.json to the rock you crawl through.
##
## A passage is a centreline and a handful of cross-section keyframes. The centreline's control
## points are resampled through a spline into a station every ~0.5 m; each station gets a
## section interpolated between the keyframes either side of it; and the whole lot is handed to
## Geo.sweep, which carries a levelled frame down the line so the floor stays underneath you
## through every bend.
##
## Two things this class owns besides geometry, both of which the rest of the game leans on:
## `clearance_at(i, body_width)`, which is the real passable gap at a station rather than the
## nominal numbers in the file, and `nearest(p)`, which turns a world position back into
## "you are 22 m into The Flatiron" for the survey slate and the posture look-ahead.

const STATION_STEP := 0.35  # metres between cross-sections; also the survey's resolution
const SIDES := 22           # points around a section - enough for rock, cheap enough for a Quest
const TUBE_MARGIN := 1.12   # a tube face must be this far inside a neighbour before it is cut
const CAP_MARGIN := 1.00    # an end face is cut wherever a neighbour is, exactly

## What a neighbouring passage says should happen to one of this passage's faces. See
## `swallows_face`, which is where the three of them are decided and explained.
enum { KEEP, CUT, SEAM }

var id := ""
var label := ""
var kind := "passage"
var wall_mat := "rock"
var floor_mat := "mud"
var rough := 0.0

var points := PackedVector3Array()    ## the centreline, one entry per station
var sections: Array = []              ## PackedVector2Array per station
var frames: Array = []                ## Basis per station: x across, y up, z along
var along := PackedFloat32Array()     ## distance from the passage mouth, per station

var bounds := AABB()                  ## everything this passage occupies, for coarse rejection
var radius := 0.0                     ## the biggest section radius anywhere along it

## The passage this one carries straight on from, and the one that carries on from it. Set by
## Cave when one passage starts exactly where another ends (see `continues_from`). Two such
## passages are one tube with a name change part way along: no end faces at the join, no
## trimming of either against the other, and the second is swept from the first one's last ring.
var continues: Bore = null
var continued_by: Bore = null

var _noise: FastNoiseLite
var _floor_face := PackedByteArray()  ## per face index: is this one floor rather than wall?
var _grid := {}                       ## Vector3i cell -> Array[int] of station indices
var _grid_size := 2.5                 ## metres per grid cell, never smaller than the passage

func _init(data: Dictionary) -> void:
	id = data.get("id", "")
	label = data.get("label", id)
	kind = data.get("kind", "passage")
	wall_mat = data.get("wall", "rock")
	# The floor is the same rock as the walls unless a cave says otherwise. Where it is, Cave
	# hands back the same batch for both and the split costs nothing; the capability stays for
	# a cave that wants mud underfoot.
	floor_mat = data.get("floor", wall_mat)
	rough = float(data.get("rough", 0.10))

	_noise = FastNoiseLite.new()
	_noise.seed = int(data.get("seed", 1))
	_noise.frequency = 0.9
	_noise.fractal_octaves = 3
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	var control := PackedVector3Array()
	for p: Array in data.get("path", []):
		control.append(Vector3(p[0], p[1], p[2]))
	points = Geo.spline(control, STATION_STEP)
	frames = Geo.frames(points)

	var keys: Array = data.get("profile", [])
	var run := 0.0
	for i in points.size():
		if i > 0:
			run += points[i].distance_to(points[i - 1])
		along.append(run)
	var total: float = maxf(along[along.size() - 1], 0.001)
	for i in points.size():
		sections.append(_section_at(keys, along[i] / total))

	_mark_floor_faces()
	_index()

## Bucket the stations into a coarse grid and work out what this passage occupies, so a caller
## asking "is this point inside you" can answer without walking the whole centreline.
func _index() -> void:
	for i in points.size():
		var sec: PackedVector2Array = sections[i]
		for q: Vector2 in sec:
			radius = maxf(radius, q.length())
	radius += rough
	# The cell has to be at least as big as the passage is wide. A station is registered in its
	# own cell and its 26 neighbours, and a lookup reads one cell - which is only correct while
	# nothing inside the passage is further from a station than one cell. At a fixed 2.5 m the
	# Cellar, which is six metres across, could hide a face from its own index.
	_grid_size = maxf(2.5, radius)
	bounds = AABB(points[0], Vector3.ZERO)
	for p: Vector3 in points:
		bounds = bounds.expand(p)
	bounds = bounds.grow(radius)
	for i in points.size():
		var c := _cell(points[i])
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var k := c + Vector3i(dx, dy, dz)
					if not _grid.has(k):
						_grid[k] = PackedInt32Array()
					_grid[k].append(i)

func _cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / _grid_size), floori(p.y / _grid_size), floori(p.z / _grid_size))

## Stations near this point, or an empty list if the point is nowhere near this passage.
func stations_near(p: Vector3) -> PackedInt32Array:
	if not bounds.has_point(p):
		return PackedInt32Array()
	return _grid.get(_cell(p), PackedInt32Array())

## Is this point inside this passage's open space? Exact against the real section polygon at the
## nearest station - a rift is 30 cm one way and two metres the other, and a circle of its
## longest radius would swallow most of the cave.
func contains_point(p: Vector3, scale := 1.0) -> bool:
	if beyond_end(p):
		return false
	for i in stations_near(p):
		var f: Basis = frames[i]
		var off: Vector3 = p - points[i]
		if absf(off.dot(f.z)) > STATION_STEP * 1.5:
			continue
		if Geo.contains(sections[i], Vector2(off.dot(f.x), off.dot(f.y)) * scale):
			return true
	return false

## Does this passage start where `other` ends? Within a centimetre, and with the same number of
## points around the section, because the join is made by reusing the other one's last ring.
##
## This is the tube-to-tube join, and it exists because the overlap join does not work for two
## tubes the same size. Overlap is right where a crawl opens into a room: the crawl's end sits
## well inside something much bigger, and all of it is cut away. Butt two tubes end to end
## instead and each end face lies across the other's mouth - half inside, half out - so the
## junction keeps it, draws it both ways as a lip, and it is a slab of stretched rock across
## the passage. That is what stood between the Flatiron and the Devil's Pinch.
func continues_from(other: Bore) -> bool:
	if other == self or other.points.is_empty() or points.is_empty():
		return false
	if points[0].distance_to(other.points[other.points.size() - 1]) > 0.01:
		return false
	return (sections[0] as PackedVector2Array).size() \
		== (other.sections[other.sections.size() - 1] as PackedVector2Array).size()

## The ring at station i, exactly as the sweep builds it.
func ring(i: int) -> PackedVector3Array:
	return Geo.ring(points[i], frames[i], sections[i], rough, _noise)

## Is this point past one of the passage's two end faces?
##
## A passage is a solid bounded by those faces, and the test has to say so. A station will claim
## any point within half a station-step along its own tangent, which for the last station means
## half a metre past the end of the passage - so without this, a neighbour's wall is trimmed
## away in a slab the passage does not enclose and nothing else covers. The Gullet lost its
## walls for the first half metre past the Cellar's end face exactly that way, which is a hole
## you can see through and fall out of.
func beyond_end(p: Vector3) -> bool:
	var last: int = points.size() - 1
	if (p - points[0]).dot((frames[0] as Basis).z) < 0.0:
		return true
	return (p - points[last]).dot((frames[last] as Basis).z) > 0.0

## What should be done with this FACE, which belongs to some other passage? One question, asked
## of the four corners, and the answer is simply whether they agree.
##
##   CUT  - every corner is inside this passage. The face is not a wall, it is a pipe hanging
##          through the middle of somewhere you walk. Drop it.
##   KEEP - no corner is inside. It is rock.
##   SEAM - the corners disagree, so the face lies across the edge of a mouth or across one of
##          this passage's two end faces. Dropping it whole opens a hole to the void beside the
##          mouth; keeping it whole puts a bar across a passage somebody has to get through.
##          Neither, so `Geo` quarters it and asks again, down to `Geo.SPLIT` levels. What is
##          still ambiguous at the limit is a few centimetres across; it is kept, and drawn
##          from both sides, because a kept face belongs to the OTHER passage and therefore
##          faces away from anyone standing in this one - solid and invisible, which is the one
##          thing this cave is not allowed to have. Drawn both ways it is a lip at the mouth,
##          which is what it is.
func swallows_face(corners: PackedVector3Array, scale := 1.0) -> int:
	var inside := 0
	for c: Vector3 in corners:
		if contains_point(c, scale):
			inside += 1
	if inside == 0:
		return KEEP
	if inside == corners.size():
		return CUT
	return SEAM

## Interpolate the profile keyframes at fraction t and build the section polygon.
##
## Shapes do not interpolate as names, so where two keyframes disagree - a round tube opening
## out into a letterbox - both polygons are built at the blended size and the POINTS are
## lerped. Every shape here passes through (+-w/2, 0) and (0, +-h/2), and lerping preserves
## those, so the width and height written in the file survive the blend intact.
func _section_at(keys: Array, t: float) -> PackedVector2Array:
	if keys.is_empty():
		return Geo.section("tube", 1.0, 1.0, SIDES)
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[keys.size() - 1]
	for i in range(keys.size() - 1):
		if t >= float(keys[i].get("t", 0.0)) and t <= float(keys[i + 1].get("t", 1.0)):
			a = keys[i]
			b = keys[i + 1]
			break
	var ta := float(a.get("t", 0.0))
	var tb := float(b.get("t", 1.0))
	var f: float = 0.0 if tb - ta < 1e-6 else clampf((t - ta) / (tb - ta), 0.0, 1.0)
	f = smoothstep(0.0, 1.0, f)   # ease the ends so a pinch closes gradually, not in one step

	var w: float = lerpf(float(a.get("w", 1.0)), float(b.get("w", 1.0)), f)
	var h: float = lerpf(float(a.get("h", 1.0)), float(b.get("h", 1.0)), f)
	var keel: float = lerpf(float(a.get("keel", 0.0)), float(b.get("keel", 0.0)), f)
	var sa := Geo.section(a.get("shape", "tube"), w, h, SIDES, keel)
	var sb := Geo.section(b.get("shape", "tube"), w, h, SIDES, keel)
	if a.get("shape", "tube") == b.get("shape", "tube"):
		return sa
	var out := PackedVector2Array()
	for i in SIDES:
		out.append(sa[i].lerp(sb[i], f))
	return out

## Which faces around the section are floor. Sections are symmetric about both axes and
## parameterised by angle, so this is the same set at every station: the faces low enough down
## that a body would be lying on them. They get mud; everything else gets rock.
func _mark_floor_faces() -> void:
	_floor_face.resize(SIDES)
	var mid: PackedVector2Array = sections[sections.size() / 2]
	var lo := INF
	var hi := -INF
	for p: Vector2 in mid:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var cut: float = lo + (hi - lo) * 0.26
	for k in SIDES:
		var y: float = (mid[k].y + mid[(k + 1) % SIDES].y) * 0.5
		_floor_face[k] = 1 if y <= cut else 0

## Sweep this passage into the caller's batches. `pick(material_key) -> Geo` hands back the
## builder for a material, so the caller decides the chunking and we just ask for somewhere to
## put each face.
##
## `trim(corners, margin) -> int` is asked of EVERY face - tube and end face alike -
## what to do with it, via each other passage's `swallows_face`: KEEP, CUT or SEAM. That one
## question is the whole junction rule, and it answers both halves of it:
##
##   - A TUBE face inside its neighbour is not a wall. It is a pipe hanging through the middle
##     of somewhere you walk, invisible because a swept tube's faces are single-sided and solid
##     because its collider is not. The Pitch came down through the Cellar's roof and left four
##     metres of exactly that. Dropped.
##   - An END face is a membrane across a mouth. Both ends of every passage are capped - bar
##     the ends where one passage `continues` another, which are not mouths at all - there
##     is no "open end" flag any more, because there was no way to write one down correctly:
##     leaving an end uncapped left a room's whole cross-section open to the void around a
##     tunnel a fifth of its size, and every passage in the cave leaked that way. So the cap is
##     always built and the trim cuts the mouth out of it, which is a hole the exact shape of
##     the passage that arrives rather than a hole someone typed in.
##
## The two differ only in margin, because the cost of cutting too much differs. A tube face has
## to be well inside its neighbour before it goes (TUBE_MARGIN, 1.12): over-cut a tube wall and
## there is a hole in the cave. An end face goes wherever the neighbour is, exactly (CAP_MARGIN,
## 1.00): under-cut one and there is rock across the mouth.
##
## A SEAM face is routed to its own material, which is the same rock drawn from both sides. See
## `swallows_face` for why those faces cannot be cut and why they must not be single-sided.
func build(pick: Callable, trim: Callable = Callable()) -> void:
	var walls: Geo = pick.call(wall_mat)
	var floors: Geo = pick.call(floor_mat)
	var seams: Geo = pick.call("seam")
	# Which builder a wall face belongs to, and separately what the junction says about it. Geo
	# wants them apart because a face the junction calls a SEAM is quartered and asked again.
	var by_material := func(k: int) -> Geo:
		return floors if _floor_face[k] == 1 else walls
	var tube := func(corners: PackedVector3Array) -> int:
		return trim.call(corners, TUBE_MARGIN) if trim.is_valid() else KEEP
	# Carrying on from another passage: start from its last ring, and the texture from where it
	# left off, so there is nothing at the join to see or to catch on.
	var first := PackedVector3Array()
	var run_from := 0.0
	if continues:
		first = continues.ring(continues.points.size() - 1)
		run_from = continues.length()
	walls.sweep(points, sections, rough, _noise, by_material, tube, seams, 0.7, first, run_from)
	var end_face := func(corners: PackedVector3Array) -> int:
		return trim.call(corners, CAP_MARGIN) if trim.is_valid() else KEEP
	if continues == null:
		walls.cap(points, sections, false, rough, _noise, end_face)
	if continued_by == null:
		walls.cap(points, sections, true, rough, _noise, end_face)

# ---------------------------------------------------------------- queries

## The tallest gap a body `body_width` wide can find at station i, and where in the section it
## is. This - not the w and h in the file - is the number that decides whether you get through.
func clearance_at(i: int, body_width: float) -> Dictionary:
	if i < 0 or i >= sections.size():
		return {"h": -1.0, "x": 0.0, "y": 0.0}
	return Geo.clearance(sections[i], body_width)

## The tightest station in the passage for a body of this width: {"i", "h", "along"}.
func tightest(body_width: float) -> Dictionary:
	var best := {"i": 0, "h": INF, "along": 0.0}
	for i in sections.size():
		var c := clearance_at(i, body_width)
		if c["h"] < best["h"]:
			best = {"i": i, "h": c["h"], "along": along[i]}
	return best

## Nearest station to a world point: {"i", "dist", "along", "t"}. Used by the survey slate and
## by the body's look-ahead, which wants to know what is coming before it gets there.
func nearest(p: Vector3) -> Dictionary:
	var best := 0
	var best_d := INF
	for i in points.size():
		var d: float = points[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	var total: float = maxf(along[along.size() - 1], 0.001)
	return {"i": best, "dist": sqrt(best_d), "along": along[best], "t": along[best] / total}

func length() -> float:
	return along[along.size() - 1] if along.size() > 0 else 0.0

## Where the passage starts and ends in the world, for stitching the cave graph together.
func mouth(at_end: bool) -> Vector3:
	return points[points.size() - 1] if at_end else points[0]
