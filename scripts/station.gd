extends Node3D
class_name Station
## Kestrel-9, generated fresh for every run from the modular kit (res://kit): StationLayout
## draws the deck plan on a 4 m grid, Kit merges the placed pieces into a few meshes per chunk,
## Palette swaps the kit's flat materials for the textured ones. This node also owns the
## lights, the wall terminals (tasks), the loose props, the outside (planet, stars, truss) and
## the navigation graph the stalker walks. The old hand-built map lives on in station_classic.gd.

const CELL := Kit.CELL
const NAV_Y := 1.4          # mid-height of a corridor: where floating things travel

const ROOM_LABEL := {
	"control": "CONTROL ROOM", "power": "POWER PLANT", "plant": "LIFE SUPPORT",
	"laboratory": "LABORATORY", "observation": "OBSERVATION DECK", "exercise": "GYM",
	"server": "SERVER ROOM", "eva": "EVA AIRLOCK",
}
## Per room type: [id, title, x on the door wall]. Bays at x = +-2.65 / +-4.2 are clear of
## furniture (checked against the kit's build ops); rooms with less wall space get fewer tasks.
const ROOM_TASKS := {
	"control": [["ctl_nav", "Sync nav computer", -2.65], ["ctl_alarm", "Acknowledge alarm log", 2.65]],
	"power": [["pwr_pump", "Reset coolant pump", -2.65]],
	"plant": [["ls_filter", "Swap O2 scrubber filter", -2.65], ["ls_vent", "Purge CO2 vent", 2.65]],
	"laboratory": [["lab_cultures", "Log sample cultures", -2.65], ["lab_glovebox", "Reseal the glovebox", 2.65]],
	"observation": [["obs_tracker", "Recalibrate star tracker", -2.65], ["obs_shutter", "Test blast shutters", 2.65]],
	"exercise": [["gym_harness", "Inspect treadmill harness", -2.65], ["gym_bike", "Reset bike telemetry", 2.65]],
	"server": [["srv_log", "Upload signal log", -4.2], ["srv_cooling", "Reseat rack cooling", 4.2]],
	"eva": [["eva_suits", "Charge suit batteries", 2.65]],
}
const POWER_PANEL_X := 2.65
const PANEL_Y := 1.5
const PANEL_Z := -5.37      # just proud of the door wall's panelling (wall slab inner face is -5.5)
const ROOM_TINT := {
	"control": Color(0.8, 0.88, 1.0), "power": Color(0.85, 0.95, 0.85), "plant": Color(0.8, 0.95, 0.9),
	"laboratory": Color(0.95, 0.95, 1.0), "observation": Color(0.75, 0.8, 1.0), "exercise": Color(1.0, 0.9, 0.8),
	"server": Color(0.8, 0.85, 1.0), "eva": Color(1.0, 0.92, 0.8),
}

var layout: StationLayout
var pal: Palette
var root: Node3D
var colliders: StaticBody3D
var lights: Array[Light3D] = []
var emergency_lights: Array[Light3D] = []
var interactables := {}
var props: Array[Node3D] = []
var prop_spin: Array[Vector3] = []
var prop_vel: Array[Vector3] = []
var power_led: OmniLight3D
var planet: MeshInstance3D
var clouds: MeshInstance3D
var wake_room := 0
var stalker_room := 0
var _t := 0.0
var _path_cache := {}

## Lists the haunt manager toggles directly during a blackout.
var emissive_mats: Array[StandardMaterial3D]:
	get:
		return pal.emissive

func _ready() -> void:
	pal = Palette.new()
	Game.station = self
	regenerate(Game.layout_seed)
	Game.power_changed.connect(set_power)
	Game.day_started.connect(_on_day_started)
	Game.game_reset.connect(func(): regenerate(Game.layout_seed); set_power(true))

# ---------------------------------------------------------------- build
func regenerate(seed_: int) -> void:
	if root:
		remove_child(root)
		root.free()
	lights.clear()
	emergency_lights.clear()
	interactables.clear()
	props.clear()
	prop_spin.clear()
	prop_vel.clear()
	_path_cache.clear()
	power_led = null
	layout = StationLayout.new()
	if not layout.generate(seed_):
		layout.generate(1)
	root = Node3D.new()
	root.name = "Deck"
	add_child(root)
	colliders = StaticBody3D.new()
	colliders.name = "Colliders"
	colliders.collision_layer = 1
	colliders.collision_mask = 0
	root.add_child(colliders)

	# hull: every placed piece merged per 3x3-cell chunk and material
	var mergers := {}
	var keymap := func(n: String) -> String: return Palette.KIT_MAP.get(n, "metal")
	for c: Vector2i in layout.corridor:
		var cell: Dictionary = layout.corridor[c]
		var key := "c%d_%d" % [floori(c.x / 3.0), floori(c.y / 3.0)]
		if not mergers.has(key):
			mergers[key] = Kit.Merger.new()
		mergers[key].add(cell["piece"], Kit.cell_transform(c, cell["rot"], cell["roll"]), keymap)
	for r: Dictionary in layout.rooms:
		var key := "room%d" % r["index"]
		mergers[key] = Kit.Merger.new()
		mergers[key].add("room_" + r["type"], Kit.cell_transform(r["center"], r["rot"], r["roll"]), keymap)
	for key: String in mergers:
		mergers[key].commit(root, colliders, pal.get_mat, Palette.NO_COLLIDE, key)

	_place_lights()
	_place_rooms()
	_place_props()
	_build_outside()
	_pick_special_rooms()
	Game.task_pool = task_pool()

func _place_lights() -> void:
	for c: Vector2i in layout.corridor:
		var cell: Dictionary = layout.corridor[c]
		var junction: bool = cell["open"].size() != 2
		if junction or (c.x + c.y) % 2 == 0:
			_light(StationLayout.world(c, 1.5), 0.75, 6.5, Color(0.8, 0.88, 1.0))
		if junction:
			_emergency_light(StationLayout.world(c, 1.5), 0.18, 5.0)
		if cell["open"].size() == 2 and (c.x * 7 + c.y * 3) % 4 == 0:
			_dust(StationLayout.world(c, 1.5), Vector3(1.3, 1.2, 1.3), 14)
	for r: Dictionary in layout.rooms:
		var t: String = r["type"]
		_light(StationLayout.world(r["center"], 1.8), 1.0, 11.0, ROOM_TINT.get(t, Color(0.85, 0.9, 1.0)))
		_emergency_light(StationLayout.world(r["door_cell"], 1.5), 0.25, 5.0)
		_dust(StationLayout.world(r["center"], 1.8), Vector3(5.0, 1.6, 5.0), 40)

func _place_rooms() -> void:
	for r: Dictionary in layout.rooms:
		var t: String = r["type"]
		var xf := Kit.cell_transform(r["center"], r["rot"], r["roll"])
		var facing := xf.basis * Vector3(0, 0, 1)
		for task: Array in ROOM_TASKS[t]:
			var pos := xf * Vector3(task[2], PANEL_Y, PANEL_Z)
			_panel(task[0], task[1], ROOM_LABEL[t], pos, facing)
		if t == "power":
			var pos := xf * Vector3(POWER_PANEL_X, PANEL_Y, PANEL_Z)
			_panel("power", "MAIN POWER", ROOM_LABEL[t], pos, facing, true)
			power_led = OmniLight3D.new()
			power_led.position = pos + facing * 0.6
			power_led.light_color = Color(1, 0.15, 0.05)
			power_led.light_energy = 0.0
			power_led.omni_range = 6.0
			root.add_child(power_led)
		# name plate hanging in the corridor cell outside the door, readable from both sides
		var dir: Vector2i = r["dir"]
		var toward_room := -Vector3(dir.x, 0, dir.y)
		var plate := StationLayout.world(r["door_cell"], 2.5) + toward_room * 1.2
		var g := Geo.new()
		var across := Vector3(absf(toward_room.z), 0, absf(toward_room.x))
		g.box(plate, across * 1.1 + Vector3(0, 0.26, 0) + toward_room.abs() * 0.05)
		g.box(plate + Vector3(0, 0.38, 0), Vector3(0.04, 0.5, 0.04))
		g.commit(pal.get_mat("frame"), root, null, "plate")
		_sign(ROOM_LABEL[t], plate + toward_room * 0.035, toward_room, 40, Color(0.95, 0.97, 1.0), 0.0038)
		_sign(ROOM_LABEL[t], plate - toward_room * 0.035, -toward_room, 40, Color(0.95, 0.97, 1.0), 0.0038)

## Every prop in kit/prop_*.glb belongs to one of three classes:
##
##   "wall"       bolted flush to a wall surface - upright on its mount, does not tumble and the
##                haunting cannot shove it. Extinguishers, medkits and spare grab bars.
##   "floating"   loose in the corridors: tumbling, drifting, shoveable. Crates, debris, rations.
##   "equipment"  floating too, but kept in the work area of the room it belongs to (EQUIPMENT).
##
## A prop is placed by its class, so adding one is a single line here.
const PROP_CLASS := {
	"prop_extinguisher": "wall",
	"prop_medkit": "wall",
	"prop_handhold": "wall",
	"prop_crate": "floating",
	"prop_crate_large": "floating",
	"prop_debris": "floating",
	"prop_ration": "floating",
	"prop_canister": "equipment",
	"prop_drum": "equipment",
	"prop_toolbox": "equipment",
	"prop_power_cell": "equipment",
	"prop_helmet": "equipment",
	"prop_slate": "equipment",
}

## Wall attachments, split by where they belong. Grab bars are a corridor fitting; safety gear
## hangs in both, next to the way out.
const WALL_CORRIDOR := ["prop_handhold", "prop_extinguisher", "prop_medkit"]
const WALL_ROOM := ["prop_extinguisher", "prop_medkit"]

## The loose stuff that has drifted out of somebody's hands and never been collected.
const FLOATING := ["prop_crate", "prop_crate_large", "prop_debris", "prop_ration"]

## Equipment by room type: what that workstation actually works with.
const EQUIPMENT := {
	"control": ["prop_slate", "prop_toolbox"],
	"power": ["prop_power_cell", "prop_toolbox"],
	"plant": ["prop_canister", "prop_drum"],
	"laboratory": ["prop_canister", "prop_slate"],
	"observation": ["prop_slate", "prop_helmet"],
	"exercise": ["prop_toolbox", "prop_slate"],
	"server": ["prop_power_cell", "prop_slate"],
	"eva": ["prop_helmet", "prop_canister"],
}

## Corridor pieces with both side walls intact - the ones a wall fitting can hang on.
const PLAIN_CORRIDOR := {"corridor_straight": true, "corridor_door": true}

const CORRIDOR_HW := 1.5    # interior half-width of a corridor cell
const ROOM_HW := 5.5        # inner face of a room wall

func _place_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed_ + 77

	var straight: Array[Vector2i] = []
	for c: Vector2i in layout.corridor:
		if layout.corridor[c]["open"].size() == 2:
			straight.append(c)
	if straight.is_empty():
		return

	# floating: loose in the corridors, tumbling
	for i in mini(7, straight.size()):
		var c: Vector2i = straight[rng.randi() % straight.size()]
		var p := StationLayout.world(c, 1.5) + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.8, 0.8))
		_prop(String(FLOATING[rng.randi() % FLOATING.size()]), p, rng)

	# wall: bolted to a corridor side wall (only where the piece still has both side walls)
	for c: Vector2i in straight:
		var cell: Dictionary = layout.corridor[c]
		if not PLAIN_CORRIDOR.has(cell["piece"]) or rng.randf() > 0.35:
			continue
		var xf := Kit.cell_transform(c, cell["rot"], cell["roll"])
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		# clear of the bulkhead frame at the middle of the cell
		var along := rng.randf_range(0.7, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0)
		var local := Vector3(side * CORRIDOR_HW, rng.randf_range(0.9, 2.1), along)
		_mount(String(WALL_CORRIDOR[rng.randi() % WALL_CORRIDOR.size()]), xf, local, Vector3(-side, 0, 0), Vector3(0, 0, 1))

	for r: Dictionary in layout.rooms:
		var t: String = r["type"]
		var xf := Kit.cell_transform(r["center"], r["rot"], r["roll"])

		# equipment: floating inside one work area of the room, not scattered across it
		var pool: Array = EQUIPMENT.get(t, FLOATING)
		var anchor := Vector3(rng.randf_range(-1.0, 1.0) * 3.2, 1.6, (1.0 if rng.randf() < 0.5 else -1.0) * 3.2)
		for i in pool.size():
			var p: Vector3 = anchor + Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(-0.8, 1.0), rng.randf_range(-1.1, 1.1))
			_prop(String(pool[i]), xf * p, rng)

		# wall: safety gear on the two side walls, flanking the door wall
		for side: float in [-1.0, 1.0]:
			var local := Vector3(side * ROOM_HW, rng.randf_range(1.1, 2.3), rng.randf_range(-3.0, 3.0))
			_mount(String(WALL_ROOM[rng.randi() % WALL_ROOM.size()]), xf, local, Vector3(-side, 0, 0), Vector3(0, 0, 1))

## Wake room = farthest room from the power plant (the night walk). Stalker starts in the
## room farthest from where you wake, never the one you wake in.
func _pick_special_rooms() -> void:
	var power_node: Vector2i = layout.rooms[0]["center"]
	var d := layout.distances_from(power_node)
	wake_room = 0
	var best := -1
	for r: Dictionary in layout.rooms:
		var dist: int = d.get(r["center"], -1)
		if dist > best:
			best = dist
			wake_room = r["index"]
	var d2 := layout.distances_from(layout.rooms[wake_room]["center"])
	stalker_room = -1
	best = -1
	for r: Dictionary in layout.rooms:
		if r["index"] == wake_room:
			continue
		var dist: int = d2.get(r["center"], -1)
		if r["index"] == 0:
			dist -= 2   # prefer not to start it in the power plant
		if dist > best:
			best = dist
			stalker_room = r["index"]
	if stalker_room < 0:
		stalker_room = 0

# ---------------------------------------------------------------- outside
func _build_outside() -> void:
	var b := layout.bounds()
	var centre := Vector3((b.position.x + b.end.x - 1) * 0.5 * CELL, 1.5, (b.position.y + b.end.y - 1) * 0.5 * CELL)
	var sky := SphereMesh.new()
	sky.radius = 170.0
	sky.height = 340.0
	sky.radial_segments = 24
	sky.rings = 12
	var sky_mat := StandardMaterial3D.new()
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	sky_mat.albedo_texture = StationTex.stars()
	sky_mat.disable_fog = true
	_mesh(sky, centre, sky_mat)
	var pm := SphereMesh.new()
	pm.radius = 26.0
	pm.height = 52.0
	pm.radial_segments = 48
	pm.rings = 24
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_texture = StationTex.planet()
	pmat.disable_fog = true
	planet = _mesh(pm, centre + Vector3(18, 44, -22), pmat)
	planet.rotation = Vector3(0.3, 0, 0.2)
	var am := SphereMesh.new()
	am.radius = 26.9
	am.height = 53.8
	am.radial_segments = 32
	am.rings = 16
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.albedo_color = Color(0.45, 0.7, 1.0, 0.18)
	amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amat.disable_fog = true
	clouds = _mesh(am, planet.position, amat)
	var sun := SphereMesh.new()
	sun.radius = 5.0
	sun.height = 10.0
	sun.radial_segments = 16
	sun.rings = 8
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.97, 0.9)
	smat.disable_fog = true
	_mesh(sun, centre + Vector3(-120, 40, 90), smat)
	# truss spine over the deck, solar wings past its ends, radiators
	var ext := Geo.new()
	var x0 := (b.position.x - 1) * CELL
	var x1 := (b.end.x) * CELL
	var y := 9.5
	ext.box(Vector3((x0 + x1) * 0.5, y, centre.z), Vector3(x1 - x0 + 4.0, 0.45, 0.45))
	ext.box(Vector3((x0 + x1) * 0.5, y + 1.5, centre.z), Vector3(x1 - x0 + 4.0, 0.3, 0.3))
	var k := x0
	while k <= x1:
		ext.box(Vector3(k, y + 0.75, centre.z), Vector3(0.16, 1.5, 0.16))
		k += 4.0
	for sx: float in [-1.0, 1.0]:
		var wx := (x1 + 11.0) if sx > 0 else (x0 - 11.0)
		ext.box(Vector3(wx, y + 0.4, centre.z), Vector3(0.3, 0.3, 0.3))
		ext.box(Vector3((wx + (x1 if sx > 0 else x0)) * 0.5, y + 0.4, centre.z), Vector3(absf(wx - (x1 if sx > 0 else x0)), 0.25, 0.25))
	ext.commit(pal.get_mat("truss"), root, null, "truss")
	var sol := Geo.new()
	for sx: float in [-1.0, 1.0]:
		var wx := (x1 + 11.0) if sx > 0 else (x0 - 11.0)
		sol.box(Vector3(wx, y + 0.4, centre.z), Vector3(5.0, 0.08, 16.0))
	sol.commit(pal.get_mat("solar"), root, null, "solar")
	var rad := Geo.new()
	rad.box(Vector3(centre.x, -6.0, (b.position.y - 2) * CELL), Vector3(10.0, 3.0, 0.1))
	rad.box(Vector3(centre.x, -6.0, (b.end.y + 1) * CELL), Vector3(10.0, 3.0, 0.1))
	rad.commit(pal.get_mat("ext"), root, null, "radiators")

# ---------------------------------------------------------------- small helpers
func _mesh(m: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
	return mi

func _light(pos: Vector3, energy: float, range_: float, col := Color(0.8, 0.9, 1.0)) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_energy = energy
	l.omni_range = range_
	l.light_color = col
	l.shadow_enabled = false
	root.add_child(l)
	lights.append(l)
	return l

func _emergency_light(pos: Vector3, energy := 0.25, range_ := 6.0) -> void:
	var e := OmniLight3D.new()
	e.position = pos
	e.light_color = Color(1, 0.1, 0.05)
	e.light_energy = energy
	e.omni_range = range_
	e.visible = false
	root.add_child(e)
	emergency_lights.append(e)

func _sign(text: String, pos: Vector3, facing: Vector3, size := 48, col := Color(0.85, 0.92, 1.0), pixel := 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.outline_size = 6
	l.shaded = true
	l.modulate = col
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(l)
	l.position = pos
	l.look_at(pos - facing, Vector3.UP)
	return l

## One prop from the kit, tumbling at a random attitude. Its surfaces keep the kit material
## names, so the same palette remap the hull uses applies here. The glb rests on y = 0, so the
## mesh is offset inside a pivot node and the pivot is what spins.
func _prop(piece: String, pos: Vector3, rng: RandomNumberGenerator) -> void:
	assert(PROP_CLASS.get(piece, "") != "wall", "%s is a wall attachment - use _mount()" % piece)
	var mesh := Kit.mesh(piece)
	var names := Kit.material_names(piece)
	var pivot := Node3D.new()
	pivot.name = piece
	pivot.position = pos
	pivot.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	root.add_child(pivot)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var aabb := mesh.get_aabb()
	mi.position = -aabb.get_center()
	for s in mesh.get_surface_count():
		var key: String = Palette.KIT_MAP.get(names[s], "metal")
		mi.set_surface_override_material(s, pal.get_mat(key))
	pivot.add_child(mi)

	# one box collider, so a prop is something you can grab and pull off
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)

	props.append(pivot)
	prop_spin.append(Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)))
	prop_vel.append(Vector3.ZERO)

## A wall attachment: the prop's base sits flat on the wall surface, `normal` pointing off it
## into the room and `tangent` giving the direction its front faces. `xf` is the piece transform,
## `local` a point on the wall in that piece's own frame - so a rolled cell mounts it on what is
## now the ceiling, which is the whole point of a station with no floor.
func _mount(piece: String, xf: Transform3D, local: Vector3, normal: Vector3, tangent: Vector3) -> void:
	assert(PROP_CLASS.get(piece, "") == "wall", "%s is not a wall attachment - use _prop()" % piece)
	var mesh := Kit.mesh(piece)
	var names := Kit.material_names(piece)
	var aabb := mesh.get_aabb()
	var up := (xf.basis * normal).normalized()
	var fwd := (xf.basis * tangent).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = piece
	for s in mesh.get_surface_count():
		var key: String = Palette.KIT_MAP.get(names[s], "metal")
		mi.set_surface_override_material(s, pal.get_mat(key))
	root.add_child(mi)
	mi.transform = Transform3D(Basis(up.cross(fwd), up, fwd), xf * local)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	cs.shape = shape
	cs.position = aabb.get_center()
	body.add_child(cs)
	mi.add_child(body)

func _panel(id: String, title: String, room: String, pos: Vector3, facing: Vector3, power := false) -> void:
	var it := Interactable.new()
	root.add_child(it)
	it.setup(id, title, room, power)
	it.global_position = pos
	it.look_at(pos - facing, Vector3.UP)
	it.completed.connect(_on_task_completed)
	interactables[id] = it

func _dust(center: Vector3, extents: Vector3, amount := 36) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.07
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.014)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.9, 1.0, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	p.mesh = q
	p.position = center
	root.add_child(p)

# ---------------------------------------------------------------- runtime
func _process(delta: float) -> void:
	_t += delta
	for i in props.size():
		var p := props[i]
		p.rotation += prop_spin[i] * delta
		p.position += prop_vel[i] * delta
		prop_vel[i] = prop_vel[i].lerp(Vector3.ZERO, 0.4 * delta)
		p.position.y += sin(_t * 0.5 + float(i)) * 0.03 * delta
	if power_led and not Game.power_on:
		power_led.light_energy = 1.2 if fmod(_t, 1.2) < 0.15 else 0.05
	if planet:
		planet.rotate_y(delta * 0.006)
		clouds.rotate_y(delta * 0.009)

func set_power(on: bool) -> void:
	for l in lights:
		l.visible = on
	pal.set_power(on)
	for e in emergency_lights:
		e.visible = not on
	if power_led:
		power_led.light_energy = 0.0
	for id in interactables:
		var it: Interactable = interactables[id]
		it.set_label_visible(on)
		if it.is_power:
			it.set_active(not on)
		else:
			it._refresh()

func _on_day_started(_day: int) -> void:
	var ids := []
	for t in Game.tasks:
		ids.append(t["id"])
	for id in interactables:
		var it: Interactable = interactables[id]
		if it.is_power:
			continue
		it.set_active(id in ids)

func _on_task_completed(id: String) -> void:
	Game.on_task_completed(id)

## Nudge every prop (paranormal "something moved").
func shove_props(strength := 0.6) -> void:
	for i in props.size():
		prop_vel[i] += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * strength
		prop_spin[i] += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.8

func random_light() -> Light3D:
	return lights.pick_random()

# ---------------------------------------------------------------- game-facing API
func task_pool() -> Array:
	var out := []
	for r: Dictionary in layout.rooms:
		for task: Array in ROOM_TASKS[r["type"]]:
			out.append({"id": task[0], "title": task[1], "room": ROOM_LABEL[r["type"]]})
	return out

func layout_label() -> String:
	return "%04d" % layout.seed_

func room_center(i: int) -> Vector3:
	return StationLayout.world(layout.rooms[i % layout.rooms.size()]["center"], NAV_Y)

## The kit keeps the area just inside each doorway clear of furniture: safe to appear in.
func room_entry(i: int, y := NAV_Y) -> Vector3:
	var r: Dictionary = layout.rooms[i % layout.rooms.size()]
	var dir: Vector2i = r["dir"]
	return StationLayout.world(r["center"], y) + Vector3(dir.x, 0, dir.y) * 3.2

func start_point() -> Vector3:
	return wake_point()

func wake_point() -> Vector3:
	return room_entry(wake_room)

func stalker_spawn_point() -> Vector3:
	return room_entry(stalker_room, 1.2)

func random_point() -> Vector3:
	if randf() < 0.5:
		return room_center(randi() % layout.rooms.size())
	var c: Vector2i = layout.corridor.keys()[randi() % layout.corridor.size()]
	return StationLayout.world(c, NAV_Y)

## [point, direction] pairs: a silhouette can cross a junction cell along any of its open sides.
func crossing_spots() -> Array:
	var out := []
	for c: Vector2i in layout.corridor:
		var cell: Dictionary = layout.corridor[c]
		if cell["open"].size() < 2:
			continue
		for d: Vector2i in cell["open"]:
			out.append([StationLayout.world(c, 1.5), Vector3(d.x, 0, d.y)])
	return out

func watcher_spots() -> Array:
	var out := []
	for c: Vector2i in layout.corridor:
		out.append(StationLayout.world(c, 1.3))
	return out

## Review viewpoints for main.gd's photo mode: [name, eye, target].
func viewpoints() -> Array:
	var out := []
	for r: Dictionary in layout.rooms:
		var dir: Vector2i = r["dir"]
		var toward_room := -Vector3(dir.x, 0, dir.y)
		var eye := StationLayout.world(r["door_cell"], 1.5) + toward_room * 1.0
		out.append(["room_" + r["type"], eye, StationLayout.world(r["center"], 1.0)])
		# and looking back at the door wall from inside, where the terminals hang
		out.append(["door_" + r["type"], StationLayout.world(r["center"], 1.5) + toward_room * 1.0, StationLayout.world(r["center"], 1.4) - toward_room * 5.5])
		out.append(["approach_" + r["type"], StationLayout.world(r["door_cell"], 1.5) - toward_room * 1.8, StationLayout.world(r["door_cell"], 1.6) + toward_room * 2.0])
	var n := 0
	for c: Vector2i in layout.corridor:
		var cell: Dictionary = layout.corridor[c]
		if cell["open"].size() == 2 and n < 3:
			var d: Vector2i = cell["open"][0]
			var dv := Vector3(d.x, 0, d.y)
			out.append(["corridor_%d" % n, StationLayout.world(c, 1.5) - dv * 1.0, StationLayout.world(c, 1.3) + dv * 10.0])
			n += 1
		elif cell["open"].size() == 1 and cell["piece"] == "corridor_observation":
			var d: Vector2i = cell["open"][0]
			var dv := Vector3(d.x, 0, d.y)
			out.append(["observation_bay", StationLayout.world(c, 1.5) + dv * 1.5, StationLayout.world(c, 1.3) - dv * 4.0])
	var b := layout.bounds()
	var centre := Vector3((b.position.x + b.end.x - 1) * 0.5 * CELL, 0, (b.position.y + b.end.y - 1) * 0.5 * CELL)
	out.append(["deck_overview", centre + Vector3(-30, 42, 34), centre])
	return out

# ---------------------------------------------------------------- navigation
## Next point to travel toward along the cell graph. Leaving a room aims for its doorway first.
func next_waypoint(from: Vector3, to: Vector3) -> Vector3:
	var a := layout.node_of(from)
	var b := layout.node_of(to)
	if a == b:
		return to
	var key := "%s>%s" % [a, b]
	if not _path_cache.has(key):
		_path_cache[key] = layout.path(a, b)
	var p: Array = _path_cache[key]
	if p.size() < 2:
		return to
	var nxt: Vector2i = p[1]
	if layout.occupied.has(a) and not layout.corridor.has(a):
		var r: Dictionary = layout.rooms[layout.occupied[a]]
		var dir: Vector2i = r["dir"]
		var doorway := StationLayout.world(r["center"], NAV_Y) + Vector3(dir.x, 0, dir.y) * 5.6
		if (Vector2(from.x, from.z) - Vector2(doorway.x, doorway.z)).length() > 1.2:
			return doorway
	return StationLayout.world(nxt, NAV_Y)

## True when nothing solid (walls, layer 1) is between two points.
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()
