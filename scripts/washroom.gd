extends Node3D
class_name Washroom
## The washroom's working stall, and the night you need it.
##
## The room itself - the stalls, the basins, the toilets - is kit geometry (kit/room_washroom.glb,
## tools/build_extra_rooms.py). What lives here is what moves: the door of the one stall that works,
## and the toilet trip (Game.night_toilet), which plays like this:
##
##   get into the stall, shut the door (hold TRIGGER / USE on it), look at the toilet -
##   the screen goes black - it comes back, you turn round and open the door.
##
## Half the time (Game.STICKS_CHANCE) there is something hanging in the air right outside that door
## when you open it: a bundle of sticks, bound up with twine and a red thread, at the height of your
## eyes, as if someone had left it there for you. It is put there while the screen is black, so it
## is never seen arriving - only found, on the way out. Finding it makes the thing that walks more
## likely to be out tonight (Game.monster_chance), and if it is, it is let go the moment the door
## opens (Game.toilet_done).
##
## Everything is in the room's own frame, so a washroom the deck plan rolled onto its side has its
## stalls on the wall and all of this still lines up.

## The stall row, in the room's frame - the same numbers tools/build_extra_rooms.py builds it from.
const STALL_X := 0.8             ## the working stall's centre
const OTHER_X := -0.8            ## the one taped shut
const STALL_FRONT := 3.35
const STALL_BACK := 5.32
const STALL_HALF := 0.8
const DOOR_HALF := 0.4
const PART_HI := 2.3
const TOILET := Vector3(0.8, 0.45, 4.93)

const DOOR_OPEN_DEG := -100.0    ## it swings out into the room, so it never shuts you in against it
const DOOR_SPEED := 2.2          ## full swings per second
const GAZE := 0.9                ## seconds of looking at the toilet with the door shut
const BUNDLE_OUT := 0.9          ## how far outside the door the sticks hang
const BLACK_TIME := 3.6          ## seconds the screen stays black

enum Trip { NONE, WAITING, SHUT_IN, BLACK, AFTER }

var door: StallDoor
var door_pivot: Node3D
var door_open := true
var trip: int = Trip.NONE
var bundle: Node3D = null
var _door_shape: CollisionShape3D
var _sign: Label3D
var _open_amount := 1.0
var _gaze := 0.0
var _shut_t := 0.0
var _hinted := false
var _looked_hint := false
var _bundle_t := 0.0

func build(station: Station, xf: Transform3D) -> void:
	global_transform = xf
	var pal: Palette = station.pal
	# the door hangs on the post at the stall's +x side and swings out
	door_pivot = Node3D.new()
	door_pivot.name = "StallDoor"
	door_pivot.position = Vector3(STALL_X + DOOR_HALF - 0.02, 0.0, STALL_FRONT)
	add_child(door_pivot)
	var w := DOOR_HALF * 2.0 - 0.04
	var slab := Geo.new()
	slab.box(Vector3(-w * 0.5, 1.2, 0.0), Vector3(w, 2.0, 0.035))
	slab.commit(pal.get_mat("light_metal"), door_pivot, null, "door")
	var fittings := Geo.new()
	for side: float in [-1.0, 1.0]:
		fittings.box(Vector3(-w + 0.1, 1.05, side * 0.04), Vector3(0.04, 0.16, 0.04))    # the handle
		fittings.box(Vector3(-w + 0.1, 1.25, side * 0.022), Vector3(0.1, 0.07, 0.01))     # the latch plate
	for y: float in [0.45, 1.95]:
		fittings.box(Vector3(-0.02, y, 0.0), Vector3(0.05, 0.14, 0.06))                    # hinges
	fittings.commit(pal.get_mat("pipe2"), door_pivot, null, "door_fittings")

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_door_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, 2.0, 0.06)
	_door_shape.shape = box
	_door_shape.position = Vector3(-w * 0.5, 1.2, 0.0)
	body.add_child(_door_shape)
	door_pivot.add_child(body)

	door = StallDoor.new()
	door_pivot.add_child(door)
	door.setup_door(self, Vector3(w, 2.0, 0.14))
	door.position = Vector3(-w * 0.5, 1.2, 0.0)

	# VACANT / ENGAGED over the latch, the way every public stall tells you
	_sign = _label("", Vector3(-w + 0.1, 1.36, -0.03), Vector3(0, 0, -1), 0.0014)
	door_pivot.add_child(_sign)
	var shut := _label("OUT OF ORDER", Vector3(OTHER_X, 1.5, STALL_FRONT - 0.035), Vector3(0, 0, -1), 0.0022)
	shut.modulate = Color(1.0, 0.55, 0.15)
	add_child(shut)
	_apply_door()
	door_pivot.rotation.y = deg_to_rad(DOOR_OPEN_DEG) * _open_amount

	Game.phase_changed.connect(_on_phase)

func _label(text: String, pos: Vector3, facing: Vector3, pixel: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = pixel
	l.outline_size = 6
	l.modulate = Color(0.85, 0.92, 1.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.visibility_range_end = 12.0
	l.position = pos
	# a Label3D reads from its +Z side; point that along `facing`
	l.basis = Basis.looking_at(-facing, Vector3.UP)
	return l

# ---------------------------------------------------------------- the door
## Swing it. Refused while the screen is black - nobody is opening anything then.
func toggle_door() -> void:
	if trip == Trip.BLACK:
		return
	door_open = not door_open
	Sfx.play_at("bang", door.global_position, -18.0, 10.0, 2.6 if door_open else 2.1)
	_apply_door()

func door_usable() -> bool:
	return trip != Trip.BLACK

func _apply_door() -> void:
	_sign.text = "VACANT" if door_open else "ENGAGED"
	_sign.modulate = Color(0.3, 1.0, 0.45) if door_open else Color(1.0, 0.25, 0.15)

# ---------------------------------------------------------------- where you are
## Inside the working stall (a point in the world).
func in_stall(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x - STALL_X) < STALL_HALF - 0.05 and l.z > STALL_FRONT + 0.02 and l.z < STALL_BACK \
		and l.y > 0.0 and l.y < PART_HI + 0.1

func toilet_point() -> Vector3:
	return to_global(TOILET)

## Just outside the stall door: where you stand to go in, and where the sticks hang.
func outside_door(height := 1.5) -> Vector3:
	return to_global(Vector3(STALL_X, height, STALL_FRONT - BUNDLE_OUT))

## Looking at the toilet: roughly at it, and close enough to be using it.
func looking_at_toilet(cam: Camera3D) -> bool:
	var to := toilet_point() - cam.global_position
	return to.length() < 2.6 and (-cam.global_transform.basis.z).dot(to.normalized()) > 0.8

# ---------------------------------------------------------------- the trip
func _on_phase(p: int) -> void:
	match p:
		Game.Phase.NIGHT:
			trip = Trip.WAITING if Game.night_toilet else Trip.NONE
			_hinted = false
			_looked_hint = false
		Game.Phase.DAY, Game.Phase.TITLE, Game.Phase.SLEEP:
			trip = Trip.NONE
			_clear_bundle()

func _process(delta: float) -> void:
	var target := 1.0 if door_open else 0.0
	if _open_amount != target:
		_open_amount = move_toward(_open_amount, target, DOOR_SPEED * delta)
		door_pivot.rotation.y = deg_to_rad(DOOR_OPEN_DEG) * _open_amount
		# no collider while it swings: a moving slab of static geometry is a trap, not a door
		_door_shape.disabled = _open_amount > 0.02 and _open_amount < 0.98
	if bundle != null:
		_bundle_t += delta
		bundle.rotate_object_local(Vector3.UP, 0.12 * delta)
		bundle.position.y += sin(_bundle_t * 0.9) * 0.012 * delta
	var player: Player = Game.player
	if player == null or Game.phase != Game.Phase.NIGHT or not Game.toilet_pending:
		return
	var cam: Camera3D = player.camera
	var inside := in_stall(cam.global_position)
	var shut := not door_open and _open_amount < 0.02
	match trip:
		Trip.WAITING:
			if inside and door_open and not _hinted:
				_hinted = true
				Game.notice.emit("Shut the door.\nHold %s on it." % Game.use_word(), 3.5)
			if inside and shut:
				trip = Trip.SHUT_IN
				_gaze = 0.0
				_shut_t = 0.0
		Trip.SHUT_IN:
			if not inside or not shut:
				trip = Trip.WAITING
				return
			_shut_t += delta
			if looking_at_toilet(cam):
				_gaze += delta
			else:
				_gaze = maxf(0.0, _gaze - delta * 0.5)
			if _gaze >= GAZE:
				_blackout()
			elif _shut_t > 8.0 and not _looked_hint:
				_looked_hint = true
				Game.notice.emit("Use the toilet.\nLook at it.", 3.0)
		Trip.AFTER:
			# out: the door opened, or you went over the top of the partition
			if _open_amount > 0.35 or not inside:
				_finish()

## The screen goes black. While it is, the bundle is decided and, if it is coming, hung outside the
## door - in the dark, so it is never seen arriving.
func _blackout() -> void:
	trip = Trip.BLACK
	var player: Player = Game.player
	player.velocity = Vector3.ZERO
	player.fade_speed = 2.5
	player.fade_target = 1.0
	Sfx.play_at("static", toilet_point(), -12.0, 8.0, 0.32)       # the suction fan spinning up
	await get_tree().create_timer(0.55).timeout
	if trip != Trip.BLACK or Game.phase != Game.Phase.NIGHT:
		return
	if Game.toilet_blackout():
		var eye_y := clampf(to_local(player.camera.global_position).y, 0.9, 2.0)
		_hang_bundle(eye_y)
		# not nothing, in the dark: something light touching the other side of the door
		Sfx.play_at("whisper", outside_door(eye_y), -20.0, 5.0, 0.6)
	await get_tree().create_timer(BLACK_TIME * 0.5).timeout
	Sfx.play_at("powerdown", toilet_point(), -14.0, 8.0, 1.8)    # the pump, the flush
	await get_tree().create_timer(BLACK_TIME * 0.5).timeout
	if trip != Trip.BLACK or Game.phase != Game.Phase.NIGHT:
		return
	trip = Trip.AFTER
	player.fade_speed = 0.8
	player.fade_target = 0.0

func _finish() -> void:
	trip = Trip.NONE
	Game.toilet_done()
	if bundle != null:
		# it has been there the whole time. The only sound is what it makes turning on its thread
		Sfx.play_at("underbreath", bundle.global_position, -12.0, 6.0, 0.85)

## Test hook: straight through the trip, as if it had been played - door shut, black, door open.
func debug_trip() -> void:
	door_open = false
	_open_amount = 0.0
	_apply_door()
	trip = Trip.SHUT_IN
	_blackout()

# ---------------------------------------------------------------- the bundle
func _hang_bundle(height: float) -> void:
	_clear_bundle()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	bundle = StickBundle.make(rng)
	add_child(bundle)
	bundle.position = Vector3(STALL_X + rng.randf_range(-0.06, 0.06), height, STALL_FRONT - BUNDLE_OUT)
	# hanging as if from a thread, a little off true, turned any old way
	bundle.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
	_bundle_t = 0.0
	Ps1.cheapen_tree(bundle)

func _clear_bundle() -> void:
	if bundle != null and is_instance_valid(bundle):
		bundle.queue_free()
	bundle = null


## The stall door as something the player points at and holds on: the ordinary point-and-hold of a
## terminal (the player code needs nothing new), without the terminal. A short hold swings it; it
## will not swing again until the trigger is let go.
class StallDoor extends Interactable:
	var washroom: Washroom
	var _latched := false

	func setup_door(w: Washroom, size: Vector3) -> void:
		washroom = w
		id = "stall_door"
		title = "STALL DOOR"
		room = "WASHROOM"
		hold_time = 0.35
		active = true
		collision_layer = 2
		collision_mask = 0
		monitoring = false
		monitorable = true
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		add_child(shape)

	func hold(delta: float, _with := "") -> bool:
		if _latched or not washroom.door_usable():
			return false
		progress += delta / hold_time
		if progress >= 1.0:
			progress = 0.0
			_latched = true
			washroom.toggle_door()
		return true

	func release() -> void:
		progress = 0.0
		_latched = false

	func set_active(on: bool) -> void:
		active = on

	func set_focused(f: bool) -> void:
		focused = f

	func set_label_visible(_v: bool) -> void:
		pass

	func _refresh() -> void:
		pass

	func _process(_delta: float) -> void:
		pass
