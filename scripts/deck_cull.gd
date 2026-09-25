class_name DeckCull
extends Node3D
## Draws only the part of the deck you could see from where your head is.
##
## A deck is corridor cells and rooms on a 4 m grid, joined through openings: 3 m wide between two
## corridor cells, one doorway into each room. From above, every wall is a wall all the way up, so
## whether one module can be seen from another is a question about the plan alone: is there a
## straight line from the eye through the openings in between. That is answered each frame the head
## moves, by walking out from the module you are in through the openings, narrowing the wedge of
## directions each one lets through (a 2D portal walk - cheap, the deck is thirty-odd modules).
##
## Everything static on the deck lives in a bin under this node, and a bin is drawn only while a
## module it belongs to can be seen:
##
##   - a corridor chunk's merged hull: any of its cells can be seen
##   - a room's hull, panels, labels, dust, the comms console, the washroom: the room can be seen
##   - a lamp: any module inside its range can be seen, so a wall you can see never loses a light
##     that was falling on it - lamps shine through walls here (no shadows), and switching one off
##     just because its own corridor went out of view would change the light on the one you are in
##   - the outside of the hull, the truss and the spacewalk: some window can be seen
##
## What moves - loose props, and whatever the haunting has out on the deck (the stalker is a rig of
## forty-odd parts) - is shown or hidden by where it is now, give or take a metre.
##
## It is conservative everywhere it is not exact: openings are taken a little wider than they are,
## a junction is treated as a clear square, a room as an empty one. It can draw a module that is
## really out of sight; it must never hide one that is in sight. Outside the hull (the airlock, a
## spacewalk) nothing is hidden at all.

const HALF_OPEN := 1.75      # half the width of an opening: 1.5 m of corridor, plus a margin that
                             # covers both eyes, the near plane and a head that moved since
const NEAR_PORTAL := 0.35    # an eye this close to an opening is in both modules
const MOVE := 0.04           # metres the head moves before the walk is redone
const MAX_STEPS := 4000     # openings looked through per walk before giving up and drawing it all
const ROAM_REACH := 1.0      # how far something that moves may stick out of the module it is in

class Portal:
	var to: int
	var a: Vector2
	var b: Vector2
	var mid: Vector2
	var out: Vector2          # unit, across the opening from this module into `to`

## One per corridor cell and one per room.
var _portals: Array = []                # area -> Array[Portal]
var _windowed: Array[bool] = []         # area -> has glass to the outside
var _area_of := {}                      # Vector2i cell -> area (every cell of a room maps to it)
var _area_box: Array[Rect2] = []        # area -> its square on the plan
var _room_area := {}                    # room index -> area
var _panes: Array[Pane] = []

## A window in a wall, seen from above: the glass as a segment, and which way is out.
class Pane:
	var area: int
	var c: Vector2
	var n: Vector2            # unit, outwards
	var a: Vector2
	var b: Vector2

class Bin:
	var node: Node3D
	var areas: PackedInt32Array

var _bins: Array[Bin] = []
var _area_bin := {}                     # str(sorted areas) -> Bin
var _chunk_bin := {}                    # hull chunk key -> Bin
var outside: Node3D                     # everything that is only seen through glass

var station: Station
var enabled := true
var _seen := PackedByteArray()
var _eye := Vector3.INF
var _eye2 := Vector2.ZERO
var _steps := 0
var _all := true                        # nothing hidden (outside, or before the first walk)
var _saw_outside := true
var visible_areas := 0                  # modules drawn at the last walk, for the perf probe

func _init() -> void:
	name = "Cull"
	# after the player has moved and before the frame is drawn
	process_priority = 1000

## The modules and their openings, from the plan. Called before anything is built so the hull can
## be committed straight into its bins.
func setup(st: Station, lay: StationLayout) -> void:
	station = st
	enabled = not OS.has_environment("DERELICT_NOCULL")
	for c: Vector2i in lay.corridor:
		_area_of[c] = _new_area(Rect2(Vector2(c) * Kit.CELL - Vector2.ONE * Kit.CELL * 0.5, Vector2.ONE * Kit.CELL))
	for r: Dictionary in lay.rooms:
		var centre: Vector2i = r["center"]
		var i := _new_area(Rect2(Vector2(centre) * Kit.CELL - Vector2.ONE * Kit.CELL * 1.5, Vector2.ONE * Kit.CELL * 3.0))
		_room_area[r["index"]] = i
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				_area_of[centre + Vector2i(dx, dz)] = i
		var t: String = r["type"]
		_add_panes(i, "room_" + t, Kit.cell_transform(centre, r["rot"], r["roll"]))
		# the airlock's outer hatch opens onto space, which is a window as far as this is concerned
		_windowed[i] = _windowed[i] or t == "eva"
	for c: Vector2i in lay.corridor:
		var cell: Dictionary = lay.corridor[c]
		var from: int = _area_of[c]
		_add_panes(from, cell["piece"], Kit.cell_transform(c, cell["rot"], cell["roll"]))
		for d: Vector2i in cell["open"]:
			var beyond := c + d if lay.corridor.has(c + d) else c + d * 2
			if not _area_of.has(beyond):
				continue
			var to: int = _area_of[beyond]
			var mid := Vector2(c) * Kit.CELL + Vector2(d) * Kit.CELL * 0.5
			_link(from, to, mid, Vector2(d))
			if not lay.corridor.has(c + d):
				_link(to, from, mid, -Vector2(d))     # the way back out of the room
	_seen.resize(_portals.size())
	outside = Node3D.new()
	outside.name = "Outside"
	add_child(outside)

func _new_area(box: Rect2) -> int:
	_portals.append([])
	_windowed.append(false)
	_area_box.append(box)
	return _portals.size() - 1

func _link(from: int, to: int, mid: Vector2, out: Vector2) -> void:
	var p := Portal.new()
	p.to = to
	p.mid = mid
	p.out = out
	p.a = mid - Vector2(-out.y, out.x) * HALF_OPEN
	p.b = mid + Vector2(-out.y, out.x) * HALF_OPEN
	_portals[from].append(p)

## The module's glass. A pane in a wall looks out sideways, across the deck, at the other modules;
## one in a ceiling or a floor (a rolled module) looks up or down at nothing but the sky and the
## truss, because every module on a deck sits at the same height.
func _add_panes(area: int, piece: String, xf: Transform3D) -> void:
	for ap: Dictionary in Kit.window_apertures(piece):
		_windowed[area] = true
		var n := xf.basis * (ap["normal"] as Vector3)
		if absf(n.y) > 0.5:
			continue
		var n2 := Vector2(n.x, n.z).normalized()
		var t3 := Vector3(-n2.y, 0.0, n2.x)
		var half := absf((xf.basis * (ap["u"] as Vector3)).dot(t3)) + absf((xf.basis * (ap["v"] as Vector3)).dot(t3)) + 0.25
		var c3 := xf * (ap["center"] as Vector3)
		var p := Pane.new()
		p.area = area
		p.c = Vector2(c3.x, c3.z)
		p.n = n2
		p.a = p.c - Vector2(t3.x, t3.z) * half
		p.b = p.c + Vector2(t3.x, t3.z) * half
		_panes.append(p)

func area_at(p: Vector3) -> int:
	return _area_of.get(StationLayout.cell_at(p), -1)

func room_area(room_index: int) -> int:
	return _room_area.get(room_index, -1)

# ---------------------------------------------------------------- bins
func _bin(areas: PackedInt32Array, label: String) -> Bin:
	var b := Bin.new()
	b.areas = areas
	b.node = Node3D.new()
	b.node.name = label
	add_child(b.node)
	_bins.append(b)
	return b

## Where a hull chunk's merged meshes go: `cells` are the plan cells it was merged from.
func chunk_node(key: String, cells: Array) -> Node3D:
	if not _chunk_bin.has(key):
		var areas := PackedInt32Array()
		for c: Vector2i in cells:
			var a: int = _area_of.get(c, -1)
			if a >= 0 and not areas.has(a):
				areas.append(a)
		_chunk_bin[key] = _bin(areas, "Chunk_" + key)
	return (_chunk_bin[key] as Bin).node

## The bin for things seen whenever any of `areas` is: one per distinct set, shared.
func _areas_node(areas: PackedInt32Array) -> Node3D:
	areas.sort()
	var key := str(areas)
	if not _area_bin.has(key):
		_area_bin[key] = _bin(areas, "Seen_%d" % _area_bin.size())
	return (_area_bin[key] as Bin).node

## Every module a lamp at `p` reaches: the ones whose square its range touches.
func _lit_areas(p: Vector3, reach: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var q := Vector2(p.x, p.z)
	for a in _area_box.size():
		var box := _area_box[a]
		var nearest := Vector2(clampf(q.x, box.position.x, box.end.x), clampf(q.y, box.position.y, box.end.y))
		if nearest.distance_to(q) <= reach:
			out.append(a)
	return out

## Sort what the deck builder left on `root` into bins. What moves (props, tools), what has no
## picture (colliders) and what looks after its own lights (WindowSun) stays where it is.
##
## A thing that is in one module is seen with that module - and, if it carries a lamp (the comms
## console's, the airlock's), wherever that lamp reaches too, like any other lamp.
func adopt(root: Node3D, keep: Array) -> void:
	for n: Node in root.get_children():
		if n == self or n in keep or not n is Node3D or n is Item or n is StaticBody3D or n is WindowSun:
			continue
		var n3 := n as Node3D
		if n3 is Exterior or (n3 is VisualInstance3D and ((n3 as VisualInstance3D).layers & Orbit.EXTERIOR_LAYER) != 0):
			n3.reparent(outside)
			continue
		var areas := PackedInt32Array()
		if n3 is Airlock:
			# behind the EVA room's back wall, seen through its inner hatch
			areas.append(room_area(station.layout.eva_room()))
		elif not n3 is Light3D:
			areas.append(area_at(_where(n3)))
		if areas.has(-1):
			continue
		for l: Node in [n3] + n3.find_children("*", "Light3D", true, false):
			if l is OmniLight3D or l is SpotLight3D:
				var lamp := l as Light3D
				var reach: float = (lamp as OmniLight3D).omni_range if lamp is OmniLight3D else (lamp as SpotLight3D).spot_range
				for a in _lit_areas(lamp.global_position, reach):
					if not areas.has(a):
						areas.append(a)
		if not areas.is_empty():
			n3.reparent(_areas_node(areas))

## Where a node's picture is. A mesh the Geo helper built sits at the origin with its vertices in
## deck coordinates, so for those it is the middle of the mesh, not the node.
func _where(n: Node3D) -> Vector3:
	if n is GeometryInstance3D:
		return ((n as GeometryInstance3D).global_transform * (n as GeometryInstance3D).get_aabb()).get_center()
	return n.global_position

# ---------------------------------------------------------------- the walk
func _process(_delta: float) -> void:
	var player := Game.player as Player
	if station == null or player == null or player.camera == null:
		return
	var eye := player.camera.global_position
	if eye.distance_squared_to(_eye) > MOVE * MOVE:
		_eye = eye
		_walk_from(eye)
	_show_props()

## Redo the walk now (after a teleport, say), rather than when the next frame is processed.
func refresh() -> void:
	_eye = Vector3.INF
	_process(0.0)

func _walk_from(eye: Vector3) -> void:
	var start := area_at(eye)
	if not enabled or start < 0 or not station.inside_hull(eye):
		_show_all()
		return
	_eye2 = Vector2(eye.x, eye.z)
	_seen.fill(0)
	_steps = 0
	_seen[start] = 1
	for p: Portal in _portals[start]:
		if Geometry2D.get_closest_point_to_segment(_eye2, p.a, p.b).distance_to(_eye2) < NEAR_PORTAL:
			# astride an opening: the module on the other side is one the eye is in, too
			_seen[p.to] = 1
			_step(p.to, 0.0, TAU, start)
	_step(start, 0.0, TAU, -1)
	if _steps > MAX_STEPS:
		_show_all()
		return
	var windows := false
	for a in _seen.size():
		if _seen[a] and _windowed[a]:
			windows = true
			break
	if windows:
		_look_out()
	_all = false
	_saw_outside = windows
	_apply()

## Everything seen past `area`, looking through the wedge of directions starting at angle `lo` and
## `width` radians wide (TAU: every direction), having come in from `came`.
##
## A line of sight crosses each opening going away from the eye, never back towards it: an opening
## the eye is already past is not one it can see through. That also keeps the walk from going round
## a loop of corridors.
func _step(area: int, lo: float, width: float, came: int) -> void:
	for p: Portal in _portals[area]:
		if p.to == came or (_eye2 - p.mid).dot(p.out) > 0.01:
			continue
		_steps += 1
		if _steps > MAX_STEPS:
			return
		var w := _wedge(p.a, p.b)
		if width < TAU:
			# the part of this opening that is inside the wedge we are looking through
			w = _overlap(lo, width, w.x, w.y)
		if w.y < 1e-4:
			continue
		_seen[p.to] = 1
		_step(p.to, w.x, w.y, area)

## Glass is nearly clear: through a window, past the station's outside, you can see into another
## module through its window, if that one faces you and is inside the view out of yours.
func _look_out() -> void:
	var into := PackedInt32Array()
	for p: Pane in _panes:
		if not _seen[p.area] or (_eye2 - p.c).dot(p.n) > 0.0:
			continue
		var view := _wedge(p.a, p.b)
		for q: Pane in _panes:
			if _seen[q.area] or (_eye2 - q.c).dot(q.n) <= 0.0 or (q.c - p.c).dot(p.n) <= 0.0:
				continue
			var w := _wedge(q.a, q.b)
			if _overlap(view.x, view.y, w.x, w.y).y > 0.0:
				into.append(q.area)
	for a in into:
		_seen[a] = 1

## The directions from the eye that pass through the segment a-b: (first angle, width), width < PI.
func _wedge(a: Vector2, b: Vector2) -> Vector2:
	var lo := (a - _eye2).angle()
	var span := wrapf((b - _eye2).angle() - lo, 0.0, TAU)
	if span > PI:
		lo += span
		span = TAU - span
	return Vector2(wrapf(lo, 0.0, TAU), span)

## The directions in both wedges (width 0 when there are none).
func _overlap(lo: float, width: float, lo2: float, width2: float) -> Vector2:
	var d := wrapf(lo2 - lo, 0.0, TAU)
	var s := d
	var e := minf(width, d + width2)
	if e <= s:
		# the second wedge may wrap round past the first one's start
		s = 0.0
		e = minf(width, d - TAU + width2)
		if e <= s:
			return Vector2(lo, 0.0)
	return Vector2(lo + s, e - s)

func _apply() -> void:
	var n := 0
	for a in _seen.size():
		n += _seen[a]
	visible_areas = n
	for b: Bin in _bins:
		var on := _all
		if not on:
			for a in b.areas:
				if _seen[a]:
					on = true
					break
		if b.node.visible != on:
			b.node.visible = on
	var out := _all or _saw_outside
	if outside.visible != out:
		outside.visible = out

func _show_all() -> void:
	if _all:
		_show_props()
		return
	_all = true
	_seen.fill(1)
	visible_areas = _seen.size()
	_apply()

func _show_props() -> void:
	for p: Node3D in station.props:
		_show_roamer(p)
	var haunt := get_tree().get_first_node_in_group("haunt")
	if haunt:
		for n: Node in haunt.get_children():
			if not n is Node3D:
				continue
			# one that carries a lamp (the ritual's candles) is a lamp: the glow out of its doorway
			# is the point of it, and that falls on walls well outside the room it is in
			var reach := 0.0
			for c: Node in n.get_children():
				if c is OmniLight3D:
					reach = maxf(reach, (c as OmniLight3D).omni_range)
			if reach > 0.0:
				var on := _all or area_at((n as Node3D).global_position) < 0
				if not on:
					for a in _lit_areas((n as Node3D).global_position, reach):
						if _seen[a]:
							on = true
							break
				if (n as Node3D).visible != on:
					(n as Node3D).visible = on
			else:
				_show_roamer(n as Node3D)

func _show_roamer(n: Node3D) -> void:
	var on := _all
	if not on:
		var p := n.global_position
		for off: Vector3 in [Vector3.ZERO, Vector3(ROAM_REACH, 0, 0), Vector3(-ROAM_REACH, 0, 0), Vector3(0, 0, ROAM_REACH), Vector3(0, 0, -ROAM_REACH)]:
			var a := area_at(p + off)
			if a < 0 or _seen[a] == 1:
				on = true
				break
	if n.visible != on:
		n.visible = on
