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

var id := ""
var label := ""
var kind := "passage"
var wall_mat := "rock"
var floor_mat := "mud"
var rough := 0.0
var open_start := false     # true: the first ring is a mouth into a chamber, not a rock face
var open_end := false

var points := PackedVector3Array()    ## the centreline, one entry per station
var sections: Array = []              ## PackedVector2Array per station
var frames: Array = []                ## Basis per station: x across, y up, z along
var along := PackedFloat32Array()     ## distance from the passage mouth, per station

var _noise: FastNoiseLite
var _floor_face := PackedByteArray()  ## per face index: is this one floor rather than wall?

func _init(data: Dictionary) -> void:
	id = data.get("id", "")
	label = data.get("label", id)
	kind = data.get("kind", "passage")
	wall_mat = data.get("wall", "rock")
	floor_mat = data.get("floor", "mud")
	rough = float(data.get("rough", 0.10))
	open_start = bool(data.get("open_start", false))
	open_end = bool(data.get("open_end", false))

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
func build(pick: Callable) -> void:
	var walls: Geo = pick.call(wall_mat)
	var floors: Geo = pick.call(floor_mat)
	var cb := func(k: int, _i: int) -> Geo:
		return floors if _floor_face[k] == 1 else walls
	walls.sweep(points, sections, rough, _noise, cb)
	# A passage that runs into rock is capped; one that opens into a chamber is left open, or
	# there would be a membrane stretched across the mouth.
	if not open_start:
		walls.cap(points, sections, false, rough, _noise)
	if not open_end:
		walls.cap(points, sections, true, rough, _noise)

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
