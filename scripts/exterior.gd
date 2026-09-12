class_name Exterior
extends Node3D
## The outside of Kestrel-9 as a place you can go: tether anchors on the hull, pylons up to the
## truss, and the damaged solar array the spacewalk is for.
##
## ANCHORS are the "outside units" a suit's tether latches onto (tether.gd): eye bolts with an amber
## beacon on corridor and room roofs, on the airlock chamber, under the truss, along the boom and at
## the array. Each is solid, so a hand can grab it too. After the deck is built, finish_route()
## checks that a chain of anchors no more than a rope's length apart leads from the airlock to the
## array, and strings guide cables with anchors on them across any gap - so every deck can be done.
##
## THE SITE is on the wing across the deck from the airlock: a junction box on the boom with two panels
## (eva_unbolt, wrench; eva_splice, multitool), a scorched tile hanging off the wing and sparks.

const HOP := 12.0              # the longest gap the route may ask a rope to cover (Tether.RANGE is 16)
const RELAY := 9.0             # spacing of anchors along a guide cable
const TRUSS_Y := 9.5

var anchors: Array[Vector3] = []
var route: Array[int] = []     # anchor indices from the airlock to the site (tests, hints)
var route_ok := false
var site := Vector3.ZERO       # the junction box
var wing_side := 1.0           # +1: the wing past the deck's +X end
var unbolt: Interactable
var splice: Interactable
var _pal: Palette
var _body: StaticBody3D
var _clamps := Geo.new()
var _beacons := Geo.new()
var _cables := Geo.new()
var _struts := Geo.new()
var _beacon_mat: StandardMaterial3D
var _tile: MeshInstance3D
var _sparks: CPUParticles3D
var _start := Vector3.ZERO
var _t := 0.0
var _tile_drift := false

func build(station: Station) -> void:
	name = "Exterior"
	_pal = station.pal
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(0.3, 0.2, 0.05)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.6, 0.15)
	_beacon_mat.emission_energy_multiplier = 2.0

	var layout := station.layout
	var b := layout.bounds()
	var cz := (b.position.y + b.end.y - 1) * 0.5 * Kit.CELL
	var x0 := (b.position.x - 1) * Kit.CELL
	var x1 := b.end.x * Kit.CELL

	# roofs: every other corridor cell, and each room's middle and corners
	for c: Vector2i in station._module_boxes:
		if (c.x + c.y) % 2 == 0:
			var box: AABB = station._module_boxes[c]
			_anchor(Vector3(box.get_center().x, box.end.y + 0.15, box.get_center().z))
	for i: int in station._room_boxes:
		var box: AABB = station._room_boxes[i]
		var mid := box.get_center()
		_anchor(Vector3(mid.x, box.end.y + 0.15, mid.z))
		for s: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_anchor(Vector3(mid.x + s.x * box.size.x * 0.36, box.end.y + 0.15, mid.z + s.y * box.size.z * 0.36))
	if station.airlock:
		_start = station.airlock.exit_point()
		for p: Vector3 in station.airlock.anchor_points():
			_anchor(p)

	# pylons from the roofs up to the truss, with anchors part way up, and anchors under the truss
	var pylons := Geo.new()
	var k := x0
	while k <= x1 + 0.1:
		_anchor(Vector3(k, TRUSS_Y - 0.4, cz))
		var roof := _roof_under(station, Vector3(k, 0, cz))
		if roof > -INF and int(roundi(k / Kit.CELL)) % 3 == 0:
			pylons.box(Vector3(k, (roof + TRUSS_Y) * 0.5, cz), Vector3(0.22, TRUSS_Y - roof, 0.22))
			_anchor(Vector3(k + 0.4, (roof + TRUSS_Y) * 0.5, cz))
		k += Kit.CELL
	_commit(pylons, "truss")

	# the boom out to the wing on the far side from the airlock - the walk is the job - and its corners
	var eva_x := station.airlock.centre().x if station.airlock else x1
	wing_side = -1.0 if eva_x > (x0 + x1) * 0.5 else 1.0
	var edge := x1 if wing_side > 0.0 else x0
	var wx := edge + wing_side * 11.0
	var x := edge
	while absf(x - wx) > 2.0:
		_anchor(Vector3(x, TRUSS_Y + 0.05, cz))
		x += wing_side * 4.0
	for s: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_anchor(Vector3(wx + s.x * 2.2, TRUSS_Y + 0.6, cz + s.y * 7.4))
	_build_site(Vector3(wx - wing_side * 1.8, TRUSS_Y + 0.4, cz), Vector3(wx, TRUSS_Y + 0.46, cz + 3.2))
	var lane := _guideline(station, cz)
	_anchor(site + Vector3(0, 0.75, -signf(lane - cz) * 1.6))
	_commit(_struts, "truss")

## The rigged route: a guide cable from the outer hatch up clear of the roofs, across to one side of the
## truss, up over it and along it to the array, with an anchor every 8 m and struts tying it to the
## structure. It keeps to lanes nothing on any deck reaches (roofs top out under 8 m, the truss spans
## 9.3 - 11.2 m at its centreline), so every deck gets a walk the rope can always do. Returns the z
## of the lane beside the truss.
func _guideline(station: Station, cz: float) -> float:
	var al := station.airlock
	if al == null:
		return cz + 1.6
	var p0 := al.exit_point()
	var lane := cz + (1.6 if p0.z >= cz else -1.6)
	var low := TRUSS_Y - 1.0
	var high := TRUSS_Y + 2.7
	var pts: Array[Vector3] = [p0, Vector3(p0.x, low, p0.z), Vector3(p0.x, low, lane), Vector3(p0.x, high, lane),
		Vector3(site.x, high, lane), Vector3(site.x, site.y + 0.75, lane)]
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var span := a.distance_to(b)
		if span < 0.05:
			continue
		_cables.pipe(a, b, 0.02)
		var n := maxi(1, int(ceil(span / 8.0)))
		for s in range(1, n + 1):
			var p := a.lerp(b, float(s) / n)
			_anchor(p)
			if absf(p.y - low) < 0.01:
				var roof := _roof_under(station, p)
				if roof > -INF:
					_struts.pipe(p - Vector3(0, 0.22, 0), Vector3(p.x, roof, p.z), 0.03)
			elif p.y > TRUSS_Y + 1.8:
				_struts.pipe(p - Vector3(0, 0.22, 0), Vector3(p.x, TRUSS_Y + 1.5, cz), 0.03)
	return lane

## Build the anchors' meshes and colliders, then (a couple of physics frames later, once the hull's
## colliders are in the space) make sure a rope can get from the airlock to the site.
func finish() -> void:
	_flush_anchor_meshes()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_connect_route()
	# the cables are for the eye; the anchors on them are what is solid
	var cmi := _cables.commit(_pal.get_mat("pipe2"), self)
	if cmi:
		cmi.layers = 1 | Orbit.EXTERIOR_LAYER
	_flush_anchor_meshes()        # any relay anchors

func _flush_anchor_meshes() -> void:
	_commit(_clamps, "pipe2")
	var mi := _beacons.commit(_beacon_mat, self)
	if mi:
		mi.layers = 1 | Orbit.EXTERIOR_LAYER
	_clamps = Geo.new()
	_beacons = Geo.new()

func _anchor(p: Vector3) -> int:
	anchors.append(p)
	_clamps.ring(p, Vector3.UP, 0.1, 0.16, 0.06, 8)
	_clamps.pipe(p - Vector3(0, 0.22, 0), p - Vector3(0, 0.03, 0), 0.035)
	_beacons.box(p + Vector3(0, 0.07, 0), Vector3(0.06, 0.06, 0.06))
	return anchors.size() - 1

func _commit(g: Geo, key: String) -> void:
	var mi := g.commit(_pal.get_mat(key), self, _body, key)
	if mi:
		mi.layers = 1 | Orbit.EXTERIOR_LAYER

## Top of whatever module is under (x, z), or -INF.
func _roof_under(station: Station, p: Vector3) -> float:
	var top := -INF
	for box: AABB in station._module_boxes.values() + station._room_boxes.values():
		if p.x >= box.position.x and p.x <= box.end.x and p.z >= box.position.z and p.z <= box.end.z:
			top = maxf(top, box.end.y)
	return top

func _build_site(box_at: Vector3, tile_at: Vector3) -> void:
	site = box_at + Vector3(0, 0.425, 0)
	var g := Geo.new()
	g.box(site, Vector3(1.0, 0.6, 2.3))
	_commit(g, "dark")
	var stripe := Geo.new()
	stripe.box(site + Vector3(0, 0.31, 0), Vector3(1.02, 0.03, 2.32))
	_commit(stripe, "hazard")
	var top := site + Vector3(0, 0.3, 0)
	unbolt = _site_panel("eva_unbolt", "UNBOLT DAMAGED PANEL", Item.WRENCH, top + Vector3(0, 0.07, -0.58))
	splice = _site_panel("eva_splice", "SPLICE POWER COUPLING", Item.MULTITOOL, top + Vector3(0, 0.07, 0.58))
	# the damaged tile, lifted off the wing, and a scorch where it was
	_tile = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.05, 1.8)
	_tile.mesh = bm
	_tile.material_override = _pal.get_mat("solar")
	_tile.position = tile_at + Vector3(0, 0.35, 0)
	_tile.rotation = Vector3(0.45, 0.3, 0.2)
	_tile.layers = 1 | Orbit.EXTERIOR_LAYER
	add_child(_tile)
	var scorch := Geo.new()
	scorch.box(tile_at, Vector3(2.0, 0.02, 2.0))
	var black := Palette.plain(Color(0.03, 0.03, 0.03), 0.95, 0.0)
	var smi := scorch.commit(black, self)
	smi.layers = 1 | Orbit.EXTERIOR_LAYER
	_sparks = CPUParticles3D.new()
	_sparks.amount = 24
	_sparks.lifetime = 0.5
	_sparks.explosiveness = 0.6
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.0
	_sparks.initial_velocity_max = 3.0
	_sparks.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.7, 0.25)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = sm
	_sparks.mesh = q
	_sparks.position = tile_at + Vector3(0, 0.05, 0)
	add_child(_sparks)
	var work := OmniLight3D.new()
	work.light_color = Color(1.0, 0.85, 0.6)
	work.light_energy = 1.2
	work.omni_range = 7.0
	work.light_cull_mask = Orbit.EXTERIOR_LAYER
	work.position = site + Vector3(0, 2.2, 0)
	add_child(work)

func _site_panel(id: String, title: String, tool: String, pos: Vector3) -> Interactable:
	var it := Interactable.new()
	add_child(it)
	it.setup(id, title, "SOLAR ARRAY", false, tool)
	it.global_position = pos
	it.look_at(pos - Vector3.UP, Vector3(wing_side, 0, 0))
	it.completed.connect(func(done_id: String) -> void: _on_site(done_id))
	return it

func _on_site(id: String) -> void:
	Game.on_task_completed(id)
	if id == "eva_unbolt":
		_tile_drift = true
	elif id == "eva_splice":
		_sparks.emitting = false

func reset() -> void:
	_tile_drift = false
	if _sparks:
		_sparks.emitting = true

# ---------------------------------------------------------------- route
func _connect_route() -> void:
	for guard in 12:
		var reach := _reachable()
		var goal := _nearest_anchor(site)
		if reach.has(goal):
			route = _path(goal)
			route_ok = true
			return
		# the closest unconnected pair that a cable can be strung between
		var best := [-1, -1]
		var best_d := INF
		for i: int in reach:
			for j in anchors.size():
				if reach.has(j):
					continue
				var d := _pos(i).distance_to(anchors[j]) + anchors[j].distance_to(site) * 0.35
				if d < best_d and _clear(_pos(i), anchors[j]):
					best_d = d
					best = [i, j]
		if best[0] == -1:
			break
		var a := _pos(best[0])
		var z: Vector3 = anchors[best[1]]
		_cables.pipe(a, z, 0.02)
		var n := int(ceil(a.distance_to(z) / RELAY))
		for s in range(1, n):
			var p := a.lerp(z, float(s) / n)
			anchors.append(p)
			_clamps.ring(p, (z - a).normalized(), 0.1, 0.16, 0.06, 8)
			_beacons.box(p + Vector3(0, 0.12, 0), Vector3(0.06, 0.06, 0.06))
	route_ok = false

## -1 stands for the start: just outside the outer hatch.
func _pos(i: int) -> Vector3:
	return _start if i == -1 else anchors[i]

func _nearest_anchor(p: Vector3) -> int:
	var best := 0
	for i in anchors.size():
		if anchors[i].distance_to(p) < anchors[best].distance_to(p):
			best = i
	return best

func _reachable() -> Dictionary:
	var prev := {-1: -1}
	var queue := [-1]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j in anchors.size():
			if prev.has(j) or _pos(i).distance_to(anchors[j]) > HOP:
				continue
			if not _clear(_pos(i), anchors[j]):
				continue
			prev[j] = i
			queue.append(j)
	_prev = prev
	return prev

var _prev := {}

func _path(goal: int) -> Array[int]:
	var out: Array[int] = []
	var i := goal
	while i != -1:
		out.push_front(i)
		i = _prev[i]
	return out

## Nothing solid between two anchor points (their own clamps aside).
func _clear(a: Vector3, b: Vector3) -> bool:
	var d := a.distance_to(b)
	if d < 0.8:
		return true
	var dir := (b - a) / d
	var q := PhysicsRayQueryParameters3D.create(a + dir * 0.35, b - dir * 0.35, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _process(delta: float) -> void:
	_t += delta
	_beacon_mat.emission_energy_multiplier = 3.0 if fmod(_t, 1.6) < 0.2 else 0.6
	if _tile_drift and _tile:
		_tile.position += Vector3(wing_side * 0.15, 0.35, 0.1) * delta
		_tile.rotation += Vector3(0.3, 0.5, 0.2) * delta
	var player: Player = Game.player
	if player and Game.next_step_id() == "eva_reach" and player.camera.global_position.distance_to(site) < 4.5:
		Game.on_task_completed("eva_reach")
