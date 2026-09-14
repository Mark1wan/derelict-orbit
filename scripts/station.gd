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
## Per room type: [id, title, x on the door wall, repair tool it needs (an Item kind)]. Bays at x = +-2.65 / +-4.2 are clear of
## furniture (checked against the kit's build ops); rooms with less wall space get fewer tasks.
const ROOM_TASKS := {
	"control": [["ctl_nav", "Sync nav computer", -2.65, "scanner"], ["ctl_alarm", "Acknowledge alarm log", 2.65, "scanner"]],
	"power": [["pwr_pump", "Reset coolant pump", -2.65, "wrench"]],
	"plant": [["ls_filter", "Swap O2 scrubber filter", -2.65, "wrench"], ["ls_vent", "Purge CO2 vent", 2.65, "wrench"]],
	"laboratory": [["lab_cultures", "Log sample cultures", -2.65, "scanner"], ["lab_glovebox", "Reseal the glovebox", 2.65, "multitool"]],
	"observation": [["obs_tracker", "Recalibrate star tracker", -2.65, "scanner"], ["obs_shutter", "Test blast shutters", 2.65, "multitool"]],
	"exercise": [["gym_harness", "Inspect treadmill harness", -2.65, "wrench"], ["gym_bike", "Reset bike telemetry", 2.65, "multitool"]],
	"server": [["srv_log", "Upload signal log", -4.2, "scanner"], ["srv_cooling", "Reseat rack cooling", 4.2, "multitool"]],
	"eva": [["eva_suits", "Charge suit batteries", 2.65, "multitool"]],
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
## Lamps that are genuinely failing - bad ballast, nothing supernatural. Picked with the deck seed,
## so they are the same ones all run, and they stutter on their own schedule for ever. Their only
## job is to make sure a stuttering light is never by itself evidence of anything.
var faulty_lights: Array[Light3D] = []
var emergency_lights: Array[Light3D] = []
var interactables := {}
var props: Array[Node3D] = []
var carried := {}                       # prop index -> an apparition has hold of it
var prop_spin: Array[Vector3] = []
var prop_vel: Array[Vector3] = []
var power_led: OmniLight3D
var planet: MeshInstance3D
var clouds: MeshInstance3D
var window_sun: WindowSun
var wake_room := 0
var stalker_room := 0
var _t := 0.0
var _path_cache := {}
var _module_boxes := {}                 # corridor cell -> its world AABB (what counts as inside)
var _room_boxes := {}                   # room index -> its world AABB
var airlock: Airlock
var exterior: Exterior

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
	Game.tasks_changed.connect(_refresh_active)
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
	carried.clear()
	_path_cache.clear()
	_module_boxes.clear()
	_room_boxes.clear()
	airlock = null
	exterior = null
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

	# hull: every placed piece merged per 3x3-cell chunk and material - the inside, and separately
	# the outside faces, which go on the exterior render layer where the sun can light them
	var mergers := {}
	var outers := {}
	var keymap := func(n: String) -> String: return Palette.KIT_MAP.get(n, "metal")
	for c: Vector2i in layout.corridor:
		var cell: Dictionary = layout.corridor[c]
		var key := "c%d_%d" % [floori(c.x / 5.0), floori(c.y / 5.0)]   # 20 m chunks: fewer draw calls, still culls
		if not mergers.has(key):
			mergers[key] = Kit.Merger.new()
			outers[key] = Kit.Merger.new()
		var xf := Kit.cell_transform(c, cell["rot"], cell["roll"])
		mergers[key].add(Kit.part(cell["piece"], "in"), xf, keymap)
		outers[key].add(Kit.part(cell["piece"], "out"), xf, keymap)
		_module_boxes[c] = xf * Kit.mesh(cell["piece"]).get_aabb()
	for r: Dictionary in layout.rooms:
		var key := "room%d" % r["index"]
		mergers[key] = Kit.Merger.new()
		outers[key] = Kit.Merger.new()
		var xf := Kit.cell_transform(r["center"], r["rot"], r["roll"])
		var piece: String = "room_" + String(r["type"])
		var hatch: bool = r["type"] == "eva"
		mergers[key].add(Kit.part(piece, "in", hatch), xf, keymap)
		outers[key].add(Kit.part(piece, "out", hatch), xf, keymap)
		_room_boxes[r["index"]] = xf * Kit.mesh(piece).get_aabb()
	for key: String in mergers:
		mergers[key].commit(root, colliders, pal.get_mat, Palette.NO_COLLIDE, key)
		for mi: MeshInstance3D in outers[key].commit(root, colliders, pal.get_mat, Palette.NO_COLLIDE, key + "_out"):
			_exterior(mi)

	_place_lights()
	_pick_faulty_lights()
	_place_rooms()
	_place_props()
	_build_outside()
	_place_window_sun()
	_build_eva()
	_pick_special_rooms()
	_place_tools()
	Game.task_pool = task_pool()

func _place_lights() -> void:
	for c: Vector2i in layout.corridor:
		var cell: Dictionary = layout.corridor[c]
		var junction: bool = cell["open"].size() != 2
		# one light per two cells: the Compatibility renderer pays per light per pixel
		if posmod(c.x + c.y, 2) == 0:
			_light(StationLayout.world(c, 1.5), 0.9, 6.0, Color(0.8, 0.88, 1.0))
		if junction:
			_emergency_light(StationLayout.world(c, 1.5), 0.18, 5.0)
	for r: Dictionary in layout.rooms:
		var t: String = r["type"]
		_light(StationLayout.world(r["center"], 1.8), 1.0, 11.0, ROOM_TINT.get(t, Color(0.85, 0.9, 1.0)))
		_emergency_light(StationLayout.world(r["door_cell"], 1.5), 0.25, 5.0)
		_dust(StationLayout.world(r["center"], 1.8), Vector3(5.0, 1.6, 5.0), 28)

func _place_rooms() -> void:
	for r: Dictionary in layout.rooms:
		var t: String = r["type"]
		var xf := Kit.cell_transform(r["center"], r["rot"], r["roll"])
		var facing := xf.basis * Vector3(0, 0, 1)
		for task: Array in ROOM_TASKS[t]:
			var pos := xf * Vector3(task[2], PANEL_Y, PANEL_Z)
			_panel(task[0], task[1], ROOM_LABEL[t], pos, facing, false, task[3])
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
		var plate_mi := g.commit(pal.get_mat("frame"), root, null, "plate")
		plate_mi.visibility_range_end = 20.0
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
	"prop_ladder": "wall",
	"prop_grab_loop": "wall",
	"prop_foot_restraint": "wall",
	"prop_valve": "wall",
	"prop_locker": "wall",
	"prop_control_box": "wall",
	"prop_cable_reel": "wall",
	"prop_tool_rack": "wall",
	"prop_hose_reel": "wall",
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

## Wall attachments, split by where they belong. Every one of these is a handhold before it is
## anything else: in a station with no floor, a wall with nothing on it is a wall you cannot cross,
## so the fittings are the furniture and the route at the same time.
const WALL_CORRIDOR := ["prop_ladder", "prop_ladder", "prop_grab_loop", "prop_grab_loop",
	"prop_handhold", "prop_handhold", "prop_foot_restraint", "prop_control_box",
	"prop_extinguisher", "prop_medkit", "prop_cable_reel"]
const WALL_ROOM := ["prop_locker", "prop_control_box", "prop_grab_loop", "prop_handhold",
	"prop_extinguisher", "prop_medkit", "prop_tool_rack", "prop_foot_restraint"]

## Fittings that belong to particular work: the valve where there is something to shut off, the
## tool rack where something is maintained, the hose where something can burn.
const WALL_BY_ROOM := {
	"power": ["prop_valve", "prop_tool_rack", "prop_hose_reel", "prop_control_box"],
	"plant": ["prop_valve", "prop_valve", "prop_hose_reel", "prop_cable_reel"],
	"control": ["prop_control_box", "prop_locker", "prop_tool_rack"],
	"laboratory": ["prop_hose_reel", "prop_locker", "prop_control_box", "prop_valve"],
	"observation": ["prop_grab_loop", "prop_handhold", "prop_locker"],
	"exercise": ["prop_foot_restraint", "prop_foot_restraint", "prop_grab_loop", "prop_handhold"],
	"server": ["prop_tool_rack", "prop_control_box", "prop_cable_reel", "prop_hose_reel"],
	"eva": ["prop_locker", "prop_tool_rack", "prop_valve", "prop_cable_reel", "prop_ladder"],
}

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

const GRAB_MARGIN := 0.06   # how much fatter than the mesh a wall fitting's collider is
const CORRIDOR_HW := 1.5    # nominal interior half-width of a corridor cell
const CORRIDOR_FACE := 0.06 # ...and how far its panelling stands proud of that, which is where a
                            #    fitting's backplate actually has to sit
const ROOM_HW := 5.5        # inner face of a room wall
const ROOM_FACE := 0.10     # ...rooms panel theirs 10 cm out

## Try to hang `piece` on a wall of `kit_piece`, re-rolling the spot until one of them is on bare
## wall. `local_for` suggests a candidate in the kit piece's own space, and Kit.wall_clear() throws
## it out if that patch already has a rib, a pipe run, a light strip, a window frame, a door
## surround or a console standing on it - which on a kit this greebled is most of the wall.
##
## Nothing is nudged and nothing is squeezed in: if none of the tries land, that wall stays bare.
## A fitting that is not there is invisible; a fitting through a pipe is the first thing anyone
## sees, and it makes the whole deck look generated.
const MOUNT_CLEARANCE := 0.03   # air left around a fitting, on top of its own size

## Fittings that run up the wall rather than along it. The kit's bare panels are about 0.6 m wide
## and 2 m tall, so a ladder laid sideways never fits anywhere and a ladder stood upright fits
## almost everywhere - which is also the way anyone would actually bolt one on.
const UPRIGHT := {"prop_ladder": true, "prop_cable_reel": true}

## Hang `piece` on one of `kit_piece`'s walls, in a spot found rather than guessed: Kit searches
## that wall's profile for somewhere the whole footprint is bare - no rib, no pipe run, no light
## strip, no window frame, no console - and the fitting goes there, or nowhere.
func _mount_on_wall(piece: String, kit_piece: String, xf: Transform3D, axis: int, coord: float,
		face: float, normal: Vector3, tangent: Vector3, lo: Vector2, hi: Vector2,
		rng: RandomNumberGenerator, taken: Dictionary) -> bool:
	var size := Kit.mesh(piece).get_aabb().size
	# _mount() lands the mesh with its Z along the tangent and its X across it, so turning a
	# fitting upright is just handing it the wall's own up direction as the tangent
	var upright: bool = UPRIGHT.has(piece)
	if upright:
		tangent = Vector3(0, 1, 0)
	var w := (size.x if upright else size.z) + MOUNT_CLEARANCE * 2.0
	var h := (size.z if upright else size.x) + MOUNT_CLEARANCE * 2.0
	var spot := Kit.find_clear_spot(kit_piece, axis, coord, face, w, h, lo, hi, rng, taken)
	if spot == Vector2.INF:
		return false
	var local := Vector3.ZERO
	local.y = spot.y
	local[axis] = coord - signf(coord) * face          # sit on the finished wall, not behind it
	local[2 if axis == 0 else 0] = spot.x
	_mount(piece, xf, local, normal, tangent)
	return true

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

	# wall: bolted to a corridor side wall (only where the piece still has both side walls). Two
	# thirds of cells get something, and a third of those get a fitting on each side - a corridor
	# you can cross hand over hand without letting go is the difference between a route and a gap
	for c: Vector2i in straight:
		var cell: Dictionary = layout.corridor[c]
		if not PLAIN_CORRIDOR.has(cell["piece"]) or rng.randf() > 0.62:
			continue
		var xf := Kit.cell_transform(c, cell["rot"], cell["roll"])
		var sides := [1.0 if rng.randf() < 0.5 else -1.0]
		if rng.randf() < 0.33:
			sides.append(-sides[0])
		for side: float in sides:
			_mount_on_wall(String(WALL_CORRIDOR[rng.randi() % WALL_CORRIDOR.size()]),
				cell["piece"], xf, 0, side * CORRIDOR_HW, CORRIDOR_FACE,
				Vector3(-side, 0, 0), Vector3(0, 0, 1),
				Vector2(-1.5, 0.35), Vector2(1.5, 2.5), rng, {})

	for r: Dictionary in layout.rooms:
		var t: String = r["type"]
		var xf := Kit.cell_transform(r["center"], r["rot"], r["roll"])

		# equipment: floating inside one work area of the room, not scattered across it
		var pool: Array = EQUIPMENT.get(t, FLOATING)
		# kept above the fit-out: benches, racks, capacitor towers and seating all live under about
		# 1.6 m, and a drifting canister through a console reads worse than no canister at all
		var anchor := Vector3(rng.randf_range(-1.0, 1.0) * 3.2, 2.05, (1.0 if rng.randf() < 0.5 else -1.0) * 3.2)
		for i in pool.size():
			var p: Vector3 = anchor + Vector3(rng.randf_range(-1.1, 1.1), rng.randf_range(-0.45, 0.75), rng.randf_range(-1.1, 1.1))
			_prop(String(pool[i]), xf * p, rng)

		# wall: two or three fittings on each side wall, plus a couple on the back wall. Half of
		# them are drawn from what this room is actually for.
		var trade: Array = WALL_BY_ROOM.get(t, WALL_ROOM)
		var room_piece := "room_" + t
		# one tally per wall: fittings on the same wall have to find their own patch
		for side: float in [-1.0, 1.0]:
			var taken := {}
			for i in 2 + (1 if rng.randf() < 0.5 else 0):
				var wall_pool: Array = trade if rng.randf() < 0.5 else WALL_ROOM
				_mount_on_wall(String(wall_pool[rng.randi() % wall_pool.size()]), room_piece, xf,
					0, side * ROOM_HW, ROOM_FACE, Vector3(-side, 0, 0), Vector3(0, 0, 1),
					Vector2(-4.6, 0.45), Vector2(4.6, 3.0), rng, taken)
		var back := {}
		for i in 2:
			var wall_pool: Array = trade if rng.randf() < 0.6 else WALL_ROOM
			_mount_on_wall(String(wall_pool[rng.randi() % wall_pool.size()]), room_piece, xf,
				2, ROOM_HW, ROOM_FACE, Vector3(0, 0, -1), Vector3(1, 0, 0),
				Vector2(-4.6, 0.45), Vector2(4.6, 3.0), rng, back)

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
	# the sky, the Earth and the sun are drawn by the sky shader now (Orbit); what is left out here
	# is structure, lit by the real sunlight on its own render layer
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
	_exterior(ext.commit(pal.get_mat("truss"), root, colliders, "truss"))
	var sol := Geo.new()
	for sx: float in [-1.0, 1.0]:
		var wx := (x1 + 11.0) if sx > 0 else (x0 - 11.0)
		sol.box(Vector3(wx, y + 0.4, centre.z), Vector3(5.0, 0.08, 16.0))
	_exterior(sol.commit(pal.get_mat("solar"), root, colliders, "solar"))
	var rad := Geo.new()
	rad.box(Vector3(centre.x, -6.0, (b.position.y - 2) * CELL), Vector3(10.0, 3.0, 0.1))
	rad.box(Vector3(centre.x, -6.0, (b.end.y + 1) * CELL), Vector3(10.0, 3.0, 0.1))
	_exterior(rad.commit(pal.get_mat("ext"), root, null, "radiators"))

## The spacewalk: the airlock chamber behind the EVA room, the suit rack panel on its back wall, and
## the anchors, pylons and damaged array outside (Exterior).
func _build_eva() -> void:
	var i := layout.eva_room()
	if i < 0:
		return
	var r: Dictionary = layout.rooms[i]
	var xf := Kit.cell_transform(r["center"], r["rot"], r["roll"])
	airlock = Airlock.new()
	root.add_child(airlock)
	airlock.build(self, xf)
	_panel("eva_suit", "SUIT UP", ROOM_LABEL["eva"], xf * Vector3(-2.65, PANEL_Y, PANEL_Z * -1.0), xf.basis * Vector3(0, 0, -1))
	exterior = Exterior.new()
	root.add_child(exterior)
	exterior.build(self)
	exterior.finish()
	interactables["eva_unbolt"] = exterior.unbolt
	interactables["eva_splice"] = exterior.splice

## Inside a module's hull: a corridor cell or a room (the airlock chamber is not counted).
func inside_hull(p: Vector3) -> bool:
	var c := StationLayout.cell_at(p)
	for dc: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var k := c + dc
		if _module_boxes.has(k) and (_module_boxes[k] as AABB).grow(0.05).has_point(p):
			return true
		if layout.occupied.has(k) and (_room_boxes[layout.occupied[k]] as AABB).grow(0.05).has_point(p):
			return true
	return false

## Out in space: neither in a module nor in the airlock chamber.
func is_outside(p: Vector3) -> bool:
	return not inside_hull(p) and not (airlock != null and airlock.contains(p))

## No air here: outside, or in the chamber while it is open to space.
func in_vacuum(p: Vector3) -> bool:
	if inside_hull(p):
		return false
	if airlock != null and airlock.contains(p):
		return airlock.is_vacuum()
	return true

## Mission days light up one step's panel at a time; ordinary days all of today's.
func _refresh_active() -> void:
	if Game.mission == "":
		return
	var nxt := Game.next_step_id()
	if interactables.has(nxt):
		var it: Interactable = interactables[nxt]
		if not it.active and not it.done:
			it.set_active(true)

## Outside structure: on the exterior render layer too, so the sun lights it.
func _exterior(mi: MeshInstance3D) -> void:
	if mi:
		mi.layers = 1 | Orbit.EXTERIOR_LAYER

## Every outside window on the deck, for WindowSun: corridor window pieces, observation bays and
## the rooms that have glazing, read off the kit's own glass.
func _place_window_sun() -> void:
	window_sun = WindowSun.new()
	root.add_child(window_sun)
	for c: Vector2i in layout.corridor:
		var cell: Dictionary = layout.corridor[c]
		for ap: Dictionary in Kit.window_apertures(cell["piece"]):
			window_sun.add_window(Kit.cell_transform(c, cell["rot"], cell["roll"]), ap, 3.5)
	for r: Dictionary in layout.rooms:
		for ap: Dictionary in Kit.window_apertures("room_" + r["type"]):
			window_sun.add_window(Kit.cell_transform(r["center"], r["rot"], r["roll"]), ap, 11.5)

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
	l.light_specular = 0.25
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
	l.visibility_range_end = 18.0
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

	# Every wall fitting is grabbable, and deliberately forgiving about it: the collider is the
	# piece's box plus a 6 cm margin, so a hand that comes near a rail or a strap catches it rather
	# than passing through the gap in the middle of it. The player's grab is a 0.18 m sphere against
	# layer 1 (see player.gd), which is the same layer the hull is on - so grabbing a fitting and
	# grabbing the wall behind it feel identical, which is the point.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = aabb.size + Vector3.ONE * GRAB_MARGIN
	cs.shape = shape
	cs.position = aabb.get_center()
	body.add_child(cs)
	mi.add_child(body)

func _panel(id: String, title: String, room: String, pos: Vector3, facing: Vector3, power := false, tool := "") -> void:
	var it := Interactable.new()
	root.add_child(it)
	it.setup(id, title, room, power, tool)
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
		if carried.has(i):
			continue          # something else is moving this one
		var p := props[i]
		p.rotation += prop_spin[i] * delta
		p.position += prop_vel[i] * delta
		prop_vel[i] = prop_vel[i].lerp(Vector3.ZERO, 0.4 * delta)
		p.position.y += sin(_t * 0.5 + float(i)) * 0.03 * delta
	if power_led and not Game.power_on:
		power_led.light_energy = 1.2 if fmod(_t, 1.2) < 0.15 else 0.05

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
	if Game.mission != "":
		ids = [Game.next_step_id()]
	for id in interactables:
		var it: Interactable = interactables[id]
		if it.is_power:
			continue
		it.set_active(id in ids)
	if airlock:
		airlock.reset()
	if exterior:
		exterior.reset()

func _on_task_completed(id: String) -> void:
	Game.on_task_completed(id)

## Nudge every prop (paranormal "something moved").
# ---------------------------------------------------------------- props on loan
## Nearest loose prop to `point` that nothing else has hold of, or -1. `visible_from` (when given)
## also requires line of sight from there, for events that want to be watched.
func find_prop_near(point: Vector3, max_dist := 9.0, visible_from := Vector3.INF) -> int:
	var best := -1
	var best_d := max_dist
	for i in props.size():
		if carried.has(i):
			continue
		var d := props[i].global_position.distance_to(point)
		if d >= best_d:
			continue
		if visible_from != Vector3.INF and not has_line_of_sight(visible_from, props[i].global_position):
			continue
		best = i
		best_d = d
	return best

## Take a prop out of the drift: whoever asked is moving it now.
func take_prop(i: int) -> Node3D:
	if i < 0 or i >= props.size():
		return null
	carried[i] = true
	prop_vel[i] = Vector3.ZERO
	return props[i]

## Give it back, with a shove. This is what an object flying across a corridor is.
func release_prop(i: int, velocity: Vector3, spin := Vector3.ZERO) -> void:
	if i < 0 or i >= props.size():
		return
	carried.erase(i)
	prop_vel[i] = velocity
	prop_spin[i] = spin

func shove_props(strength := 0.6) -> void:
	for i in props.size():
		prop_vel[i] += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * strength
		prop_spin[i] += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.8

## Three or four lamps on the deck are on their way out. Seeded, so this run's bad lights are this
## run's bad lights, and the player can learn which ones they are - which is the point: a lamp you
## know is broken is the best possible place for something to be standing.
func _pick_faulty_lights() -> void:
	faulty_lights.clear()
	if lights.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed_ + 404
	var pool := lights.duplicate()
	for i in mini(4, pool.size()):
		faulty_lights.append(pool.pop_at(rng.randi() % pool.size()))

## The light nearest a point, so an event can make the bit of deck it is happening on misbehave.
func nearest_light(p: Vector3) -> Light3D:
	var best: Light3D = null
	var best_d := INF
	for l in lights:
		var d := l.global_position.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = l
	return best

func random_light() -> Light3D:
	return lights.pick_random()

# ---------------------------------------------------------------- repair tools
## The tools the player does not start with (Item.STARTING) are waiting on the deck: each just inside
## the door of a different room, never the room you wake in, so part of the first shift is finding
## your kit. Seeded, so a deck number always hides them in the same places.
func _place_tools() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed_ + 505
	var candidates: Array[int] = []
	for r: Dictionary in layout.rooms:
		if r["index"] != wake_room:
			candidates.append(r["index"])
	if candidates.is_empty():
		candidates.append(wake_room)
	var k := 0
	for kind: String in Item.TOOLS:
		if Item.STARTING.has(kind):
			continue
		var pick: int = candidates[0]
		if candidates.size() > 1:
			pick = candidates.pop_at(rng.randi() % candidates.size())
		var r: Dictionary = layout.rooms[pick]
		var dir: Vector2i = r["dir"]
		var across := Vector3(-dir.y, 0, dir.x)
		var p := room_entry(pick, 1.3) + across * (0.7 if k % 2 == 0 else -0.7) + Vector3(0, rng.randf_range(-0.15, 0.25), 0)
		var it := Item.make(kind)
		it.release_into(root, Vector3.ZERO)
		it.global_position = p
		it.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		it.spin = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
		k += 1

## What the player would call the place a point is in: a room's name, or "CORRIDOR".
func place_name(p: Vector3) -> String:
	var c := StationLayout.cell_at(p)
	if layout.occupied.has(c):
		var r: Dictionary = layout.rooms[layout.occupied[c]]
		return ROOM_LABEL[r["type"]]
	return "CORRIDOR"

# ---------------------------------------------------------------- game-facing API
func task_pool() -> Array:
	var out := []
	for r: Dictionary in layout.rooms:
		for task: Array in ROOM_TASKS[r["type"]]:
			out.append({"id": task[0], "title": task[1], "room": ROOM_LABEL[r["type"]], "tool": task[3]})
	return out

func layout_label() -> String:
	return "%04d" % layout.seed_

## The room's own frame - its floor, its walls, whichever way the deck plan rolled it. A ritual
## circle laid in here lands on that room's floor even when the roll has turned the floor into a
## wall, which is the right answer in a station with no gravity.
func room_transform(i: int) -> Transform3D:
	var r: Dictionary = layout.rooms[i % layout.rooms.size()]
	return Kit.cell_transform(r["center"], r["rot"], r["roll"])

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

## Corners something can wait round: a point tucked into a side passage, close enough to its mouth
## to be seen from the corridor and far enough to one side that the wall has most of it. Returns
## [position, hide direction] - the hide direction is further into the passage, where it goes.
func corner_spots() -> Array:
	var out := []
	for c: Vector2i in layout.corridor:
		var cell: Dictionary = layout.corridor[c]
		if cell["open"].size() < 2:
			continue
		for d: Vector2i in cell["open"]:
			var into := Vector3(d.x, 0, d.y)
			var lateral := Vector3(d.y, 0, -d.x)
			for side: float in [-1.0, 1.0]:
				out.append([StationLayout.world(c, 1.05) + into * 1.15 + lateral * side * 0.95, into])
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
	if window_sun:
		var n_win := 0
		for pane: WindowSun.Pane in window_sun.windows:
			if n_win < 2 and window_sun.clear_to_sun(pane, pane.normal):
				out.append(["window_%d" % n_win, pane.center - pane.normal * 1.4, pane.center + pane.normal * 10.0])
				n_win += 1
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
