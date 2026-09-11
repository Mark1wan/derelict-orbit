class_name StationLayout
extends RefCounted
## Procedural deck plan on the kit's 4 m grid. Deterministic for a seed.
##
## A corridor network is grown by random branching walks from the origin (no 2x2 blobs, so
## every cell is a recognisable straight / corner / junction). Rooms (3x3 cells) are then hung
## off corridor cells through their single doorway. Each corridor cell finally gets the piece
## and rotation that matches its open sides.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const LIMIT := 7            # cells from the origin the plan may reach
const ROOM_TYPES := ["control", "plant", "laboratory", "observation", "exercise", "server", "eva"]

var rng := RandomNumberGenerator.new()
var seed_ := 0
## Vector2i -> {"doors": Array[Vector2i], "open": Array[Vector2i], "piece": String, "rot": int}
var corridor := {}
## [{ "type": String, "center": Vector2i, "dir": Vector2i (centre -> door cell), "door_cell": Vector2i, "rot": int, "index": int }]
var rooms := []
var occupied := {}          # Vector2i -> room index (all 9 cells of each room)

func generate(p_seed: int, room_count := 6) -> bool:
	seed_ = p_seed
	rng.seed = p_seed
	for attempt in 40:
		corridor.clear()
		rooms.clear()
		occupied.clear()
		if _grow(room_count):
			_assign_pieces()
			return true
		rng.seed = p_seed + 1000 * (attempt + 1)
	return false

func _free(c: Vector2i) -> bool:
	return absi(c.x) <= LIMIT and absi(c.y) <= LIMIT and not corridor.has(c) and not occupied.has(c)

## Adding `c` must not complete a 2x2 block of corridor cells.
func _makes_blob(c: Vector2i) -> bool:
	for dx in [-1, 1]:
		for dz in [-1, 1]:
			if corridor.has(c + Vector2i(dx, 0)) and corridor.has(c + Vector2i(0, dz)) and corridor.has(c + Vector2i(dx, dz)):
				return true
	return false

func _add_cell(c: Vector2i) -> void:
	corridor[c] = {"doors": [], "open": [], "piece": "", "rot": 0}

func _grow(room_count: int) -> bool:
	_add_cell(Vector2i.ZERO)
	var target := rng.randi_range(18, 26)
	var guard := 0
	while corridor.size() < target and guard < 600:
		guard += 1
		var from: Vector2i = corridor.keys()[rng.randi() % corridor.size()]
		var d: Vector2i = DIRS[rng.randi() % 4]
		var run := rng.randi_range(1, 4)
		for k in run:
			var n := from + d * (k + 1)
			if not _free(n) or _makes_blob(n):
				break
			_add_cell(n)
	if corridor.size() < 12:
		return false
	# rooms: power first (the game needs it), then a shuffled selection of the others
	var types := ROOM_TYPES.duplicate()
	_shuffle(types)
	types.insert(0, "power")
	var placed := 0
	for t: String in types:
		if placed >= room_count:
			break
		if _place_room(t):
			placed += 1
	if placed < 4:
		return false
	if rooms.is_empty() or rooms[0]["type"] != "power":
		return false
	return true

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp

func _place_room(type: String) -> bool:
	var cells: Array = corridor.keys()
	for attempt in 80:
		var c: Vector2i = cells[rng.randi() % cells.size()]
		var d: Vector2i = DIRS[rng.randi() % 4]
		if corridor.has(c + d) or not corridor[c]["doors"].is_empty():
			continue
		var centre := c + d * 2
		var ok := true
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if not _free(centre + Vector2i(dx, dz)):
					ok = false
		if not ok:
			continue
		# keep a one-cell breathing space between rooms so hulls don't merge
		for r in rooms:
			var other: Vector2i = r["center"]
			if absi(other.x - centre.x) < 4 and absi(other.y - centre.y) < 4:
				ok = false
		if not ok:
			continue
		var rot := _room_rotation(-d)
		var idx := rooms.size()
		# rooms roll about their doorway too: upside down, or on their side as a tall hall
		var rr := rng.randf()
		var roll := 0 if rr < 0.4 else (2 if rr < 0.65 else (1 if rr < 0.825 else 3))
		rooms.append({"type": type, "center": centre, "dir": -d, "door_cell": c, "rot": rot, "roll": roll, "index": idx})
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				occupied[centre + Vector2i(dx, dz)] = idx
		corridor[c]["doors"].append(d)
		return true
	return false

## Rotation k so the room's authored -Z doorway faces grid direction `face`.
func _room_rotation(face: Vector2i) -> int:
	for k in 4:
		if Kit.rotate_dir(Vector2i(0, -1), k) == face:
			return k
	return 0

func _assign_pieces() -> void:
	for c: Vector2i in corridor:
		var cell: Dictionary = corridor[c]
		var open: Array = []
		for d: Vector2i in DIRS:
			if corridor.has(c + d) or cell["doors"].has(d):
				open.append(d)
		cell["open"] = open
		var piece := ""
		match open.size():
			1:
				piece = "corridor_observation" if rng.randf() < 0.3 else "corridor_endcap"
			2:
				var opposite: bool = open[0] == -open[1]
				if opposite:
					var r := rng.randf()
					if r < 0.22:
						piece = "corridor_window"
					elif r < 0.32:
						piece = "corridor_window_double"
					elif r < 0.45:
						piece = "corridor_door"
					else:
						piece = "corridor_straight"
				else:
					piece = "corridor_corner"
			3:
				piece = "corridor_tjunction"
			_:
				piece = "corridor_cross"
		# roll about the attachment axis: straights any quarter turn, junctions only upside down.
		# Half the time copy a neighbour's roll so runs keep an orientation for a few cells.
		var roll := 0
		var inherited := false
		for d: Vector2i in open:
			var n := c + d
			if corridor.has(n) and corridor[n].has("roll") and rng.randf() < 0.5:
				roll = corridor[n]["roll"]
				inherited = true
				break
		if not inherited:
			roll = rng.randi() % 4
		if not Kit.can_roll_freely(piece) and roll % 2 == 1:
			roll = 0 if rng.randf() < 0.5 else 2
		var rot := Kit.rotation_for(piece, open, rng, roll)
		if rot < 0:
			piece = "corridor_cross"
			roll = 0
			rot = 0
		cell["piece"] = piece
		cell["rot"] = rot
		cell["roll"] = roll

# ---------------------------------------------------------------- queries
static func world(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3(c.x * Kit.CELL, y, c.y * Kit.CELL)

static func cell_at(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / Kit.CELL), roundi(p.z / Kit.CELL))

func bounds() -> Rect2i:
	var r := Rect2i(Vector2i.ZERO, Vector2i.ZERO)
	var first := true
	for c: Vector2i in corridor.keys() + occupied.keys():
		if first:
			r = Rect2i(c, Vector2i.ONE)
			first = false
		else:
			r = r.expand(c)
	return r

## Graph node for a world position: a corridor cell, or a room's centre cell.
func node_of(p: Vector3) -> Vector2i:
	var c := cell_at(p)
	if occupied.has(c):
		return rooms[occupied[c]]["center"]
	if corridor.has(c):
		return c
	# outside anything: nearest corridor cell
	var best := Vector2i.ZERO
	var best_d := INF
	for k: Vector2i in corridor:
		var d := (world(k) - p).length_squared()
		if d < best_d:
			best_d = d
			best = k
	return best

func neighbours(n: Vector2i) -> Array:
	var out := []
	if occupied.has(n) and not corridor.has(n):
		out.append(rooms[occupied[n]]["door_cell"])
		return out
	if corridor.has(n):
		var cell: Dictionary = corridor[n]
		for d: Vector2i in cell["open"]:
			if corridor.has(n + d):
				out.append(n + d)
			elif cell["doors"].has(d):
				out.append(n + d * 2)   # the room's centre cell
	return out

## Breadth-first path of graph nodes from a to b (inclusive). Empty if unreachable.
func path(a: Vector2i, b: Vector2i) -> Array:
	if a == b:
		return [a]
	var prev := {a: a}
	var queue := [a]
	while not queue.is_empty():
		var n: Vector2i = queue.pop_front()
		for m: Vector2i in neighbours(n):
			if prev.has(m):
				continue
			prev[m] = n
			if m == b:
				var out := [b]
				var k := b
				while k != a:
					k = prev[k]
					out.push_front(k)
				return out
			queue.append(m)
	return []

func distances_from(a: Vector2i) -> Dictionary:
	var dist := {a: 0}
	var queue := [a]
	while not queue.is_empty():
		var n: Vector2i = queue.pop_front()
		for m: Vector2i in neighbours(n):
			if not dist.has(m):
				dist[m] = dist[n] + 1
				queue.append(m)
	return dist
