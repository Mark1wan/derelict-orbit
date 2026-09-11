extends Node3D
## Schedules paranormal activity. Intensity = Game.intensity() (day number + penalties).
##
## Day events (escalating):
##   I>=1  shadows crossing doorways at the end of the corridor you're looking down, distant bangs
##   I>=2  light flicker
##   I>=3  whispers next to your ear, a watcher standing at the end of a corridor behind you
##   I>=4  loose objects get shoved
##   I>=5  brief full blackouts during the day
##   I>=6  shadows cross much closer
## Night: the Stalker (see stalker.gd), plus bangs/whispers.

var next_event := 6.0
var watcher: ShadowFigure = null
var ritual: Ritual = null
var stalker: Stalker = null
var _flickering := false

func _ready() -> void:
	Game.phase_changed.connect(_on_phase)
	Game.game_reset.connect(_reset)

func _reset() -> void:
	_clear_figures()
	if is_instance_valid(stalker):
		stalker.queue_free()
	stalker = null
	Sfx.set_heartbeat(false)
	next_event = 8.0

func _on_phase(p: int) -> void:
	match p:
		Game.Phase.NIGHT:
			_start_night()
		Game.Phase.DAY:
			_end_night()
			next_event = randf_range(8.0, 18.0)
		Game.Phase.SLEEP:
			_clear_figures()

func _process(delta: float) -> void:
	if Game.player == null or not Game.player.started:
		return
	if Game.phase == Game.Phase.DAY:
		_day_tick(delta)
	elif Game.phase == Game.Phase.NIGHT:
		_night_tick(delta)

# ---------------------------------------------------------------- day
func _day_tick(delta: float) -> void:
	next_event -= delta
	if next_event <= 0.0:
		var I := Game.intensity()
		var base := lerpf(28.0, 7.0, clampf((I - 1.0) / 7.0, 0.0, 1.0))
		next_event = randf_range(base * 0.6, base * 1.4)
		_fire_day_event(I)
	if is_instance_valid(watcher):
		_update_watcher(delta)
	else:
		watcher = null

func _fire_day_event(I: float) -> void:
	var options: Array = ["shadow", "shadow", "bang"]
	if I >= 2.0:
		options.append_array(["flicker", "flicker", "thrown", "thrown"])
	if I >= 3.0:
		options.append_array(["whisper", "watcher", "shadow", "ghoul", "chupacabra"])
	if I >= 4.0:
		options.append("drift")
	if I >= 5.0:
		options.append("blackout")
	if I >= 6.0:
		options.append_array(["shadow_close", "shadow_close"])
	var pick: String = options.pick_random()
	match pick:
		"shadow":
			if not _shadow_cross(7.0, 0.7):
				_bang()
		"shadow_close":
			if not _shadow_cross(3.0, 0.4):
				_flicker()
		"bang":
			_bang()
		"flicker":
			_flicker()
		"whisper":
			_whisper()
		"watcher":
			if not _spawn_watcher():
				_whisper()
		"ghoul":
			if not _ghoul():
				_whisper()
		"thrown":
			if not _fae():
				_bang()
		"chupacabra":
			if not _chupacabra():
				_bang()
		"drift":
			Game.station.shove_props(0.8)
			Sfx.play_at("bang", Game.player.camera.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), -10.0, 20.0, 1.4)
		"blackout":
			_blackout()

## A silhouette crosses a doorway the player is looking toward. Returns false if no spot fits.
func _shadow_cross(min_dist: float, min_dot: float) -> bool:
	var st: Station = Game.station
	var cam: Camera3D = Game.player.camera
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var candidates := []
	for spot: Array in st.crossing_spots():
		var p: Vector3 = spot[0]
		var to := p - eye
		if to.length() < min_dist or fwd.dot(to.normalized()) < min_dot:
			continue
		if not st.has_line_of_sight(eye, p):
			continue
		candidates.append(spot)
	if candidates.is_empty():
		return false
	var c: Array = candidates.pick_random()
	var f := ShadowFigure.new()
	add_child(f)
	var side := 1.0 if randf() < 0.5 else -1.0
	var p: Vector3 = c[0]
	var t: Vector3 = c[1]
	f.cross(p + t * 2.4 * side, p - t * 2.4 * side, randf_range(0.55, 1.1))
	Sfx.play_at("whisper", p, -14.0, 30.0, 0.8)
	return true

func _bang() -> void:
	var st: Station = Game.station
	var pos := st.random_point() + Vector3(randf_range(-3, 3), randf_range(-1, 1), randf_range(-3, 3))
	Sfx.play_at("bang", pos, -2.0, 60.0, randf_range(0.7, 1.2))

func _whisper() -> void:
	var head: Vector3 = Game.player.camera.global_position
	var off := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized() * 0.6
	Sfx.play_at("whisper", head + off, -6.0, 8.0, randf_range(0.85, 1.1))

func _flicker() -> void:
	if _flickering:
		return
	_flickering = true
	var l: Light3D = Game.station.random_light()
	Sfx.play_at("flicker", l.global_position, -8.0, 25.0)
	var n := 5 + randi() % 5
	for i in n:
		if not Game.power_on:
			break
		l.visible = not l.visible
		await get_tree().create_timer(randf_range(0.04, 0.16)).timeout
	l.visible = Game.power_on
	_flickering = false

func _blackout() -> void:
	if not Game.power_on:
		return
	var st: Station = Game.station
	Sfx.play("powerdown", -6.0, 1.3)
	for l in st.lights:
		l.visible = false
	for m in st.emissive_mats:
		m.emission_enabled = false
	_whisper()
	await get_tree().create_timer(randf_range(1.5, 3.0)).timeout
	if Game.power_on:
		st.set_power(true)
		Sfx.play("flicker", -6.0)

## A figure standing far down a corridor you're NOT looking at. Vanishes when stared at.
func _spawn_watcher() -> bool:
	if is_instance_valid(watcher):
		return false
	var st: Station = Game.station
	var cam: Camera3D = Game.player.camera
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var spots := []
	for p: Vector3 in st.watcher_spots():
		var to := p - eye
		if to.length() < 8.0 or fwd.dot(to.normalized()) > 0.35:
			continue
		if st.has_line_of_sight(eye, p):
			spots.append(p)
	if spots.is_empty():
		return false
	watcher = ShadowFigure.new()
	add_child(watcher)
	watcher.stand(spots.pick_random(), eye)
	return true

func _update_watcher(delta: float) -> void:
	var cam: Camera3D = Game.player.camera
	var eye := cam.global_position
	var to := watcher.global_position - eye
	var dist := to.length()
	var looking := (-cam.global_transform.basis.z).dot(to.normalized()) > 0.93
	if looking:
		watcher.looked += delta
	if watcher.looked > 0.7 or dist < 3.5:
		watcher.vanish()
		Sfx.play_at("whisper", watcher.global_position, -4.0, 30.0, 0.7)
		if dist < 6.0:
			Game.station.shove_props(0.4)
		watcher = null

func _clear_figures() -> void:
	for c in get_children():
		if c is ShadowFigure or c is Ghoul or c is Fae or c is Chupacabra:
			c.queue_free()
	watcher = null

## The Good Neighbours: they take hold of something loose and throw it. Wants a prop the player
## can actually see move - or, half the time, one they cannot see being carried at all, so all
## they get is a crate crossing the corridor at head height with nothing holding it.
func _fae() -> bool:
	for c in get_children():
		if c is Fae:
			return false
	var st: Station = Game.station
	var cam: Camera3D = Game.player.camera
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	# somewhere ahead of the player, and a loose prop near it
	var target := eye + fwd * randf_range(6.0, 12.0)
	var index := st.find_prop_near(target, 7.0, eye)
	if index < 0:
		index = st.find_prop_near(eye, 14.0, eye)
	if index < 0:
		return false
	var f := Fae.new()
	f.seen = randf() < Fae.SEEN_CHANCE
	add_child(f)
	# carried across the player's view, not along it: the point is that it crosses in front of you
	var across := fwd.cross(Vector3.UP).normalized()
	if not f.take(index, across, eye):
		f.queue_free()
		return false
	if f.seen:
		Sfx.play_at("beep", f.global_position, -18.0, 26.0, 1.9)
	return true

## The chupacabra: waiting round the edge of a side passage, with the wall taking most of it.
## Wants to be off to one side of where the player is looking rather than straight down it - the
## encounter is noticing something at the corner of a corridor you were walking past anyway.
func _chupacabra() -> bool:
	for c in get_children():
		if c is Chupacabra:
			return false
	var st: Station = Game.station
	var cam: Camera3D = Game.player.camera
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var spots := []
	for spot: Array in st.corner_spots():
		var p: Vector3 = spot[0]
		var to := p - eye
		var d := to.length()
		if d < 4.5 or d > 13.0:
			continue
		var dot := fwd.dot(to.normalized())
		if dot < 0.35 or dot > 0.93:     # off to one side of your path, not dead ahead
			continue
		if not st.has_line_of_sight(eye, p):
			continue
		spots.append(spot)
	if spots.is_empty():
		return false
	var c: Array = spots.pick_random()
	var beast := Chupacabra.new()
	add_child(beast)
	beast.lurk_at(c[0], c[1])
	return true

## The ghul: a crew member standing down a corridor you have no business in, with a lamp lit.
## Wants distance to work - the whole point of it is the walk toward it - so it only takes a spot
## well down the deck, and it only shows up once the station has started lying to you properly.
func _ghoul() -> bool:
	if Game.intensity() < 3.0:
		return false
	for c in get_children():
		if c is Ghoul:
			return false
	var st: Station = Game.station
	var cam: Camera3D = Game.player.camera
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var spots := []
	for spot: Array in st.crossing_spots():
		var p: Vector3 = spot[0]
		var to := p - eye
		if to.length() < 9.0 or fwd.dot(to.normalized()) < 0.55:
			continue
		if not st.has_line_of_sight(eye, p):
			continue
		spots.append(p)
	if spots.is_empty():
		return false
	var g := Ghoul.new()
	add_child(g)
	g.lure(spots.pick_random(), eye)
	return true

# ---------------------------------------------------------------- night
func _start_night() -> void:
	_clear_figures()
	if is_instance_valid(stalker):
		stalker.queue_free()
	stalker = Stalker.new()
	add_child(stalker)
	# the player wakes far from the power room; the stalker starts somewhere else again
	stalker.global_position = Game.station.stalker_spawn_point()
	stalker.caught.connect(_on_caught)
	next_event = randf_range(12.0, 25.0)
	Sfx.play("powerdown", -2.0)
	_place_ritual()

## Once a night, in a room you are not waking up in and the stalker is not starting in, somebody is
## sitting in a circle of candles. Nothing announces it: either you see warm light coming out of a
## doorway at some point tonight, or you do not.
func _place_ritual() -> void:
	if Game.intensity() < 2.0:
		return
	var st: Station = Game.station
	var count: int = st.layout.rooms.size()
	if count < 3:
		return
	var choices := []
	for i in count:
		if i == st.wake_room or i == st.stalker_room or i == 0:
			continue          # not where you wake, not where it starts, never the power plant
		choices.append(i)
	if choices.is_empty():
		return
	ritual = Ritual.new()
	add_child(ritual)
	# laid on that room's floor in the room's own frame, so a rolled room gets it on the wall
	ritual.global_transform = st.room_transform(choices.pick_random()).translated_local(Vector3(0, 0.02, 0))

func _night_tick(delta: float) -> void:
	next_event -= delta
	if next_event <= 0.0:
		next_event = randf_range(9.0, 22.0)
		if randf() < 0.5:
			_bang()
		else:
			_whisper()

func _end_night() -> void:
	if is_instance_valid(stalker):
		stalker.queue_free()
	stalker = null
	if is_instance_valid(ritual):
		ritual.queue_free()
	ritual = null
	Sfx.set_heartbeat(false)

func _on_caught() -> void:
	var player: Player = Game.player
	Game.player_caught()
	if is_instance_valid(stalker):
		stalker.lunge(player)
	player.flashlight.visible = true
	Sfx.play("scream", 0.0)
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(stalker):
		stalker.queue_free()
	stalker = null
