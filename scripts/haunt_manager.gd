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
## Night: bangs and whispers, and on some nights the Stalker (see stalker.gd) - only when
## Game.monster_released says so, which is never the first night and not every night after.

## Daytime apparitions take the lighting with them about a third of the time: whatever lamp is
## nearest the thing stutters while it is there. The flicker itself still means nothing - the
## deck's own failing lamps stutter four times as often - but it is what carries the sound layer,
## and that layer has to reach the player often enough to be worth doubting.
##
## These three numbers are one decision and were tuned together against tools/simulate_run.py: at
## 20% / 60% / 14% a run produced 18 breaths with something behind them and 25 with nothing, so
## hearing one meant it was MORE likely to be nothing - a tell that actively misinforms is not
## doubt, it is noise. At these values it lands near 7 in 10, which is the useful shape: worth
## listening for, never safe to trust. Night has its own darkness and does not need any of it.
const APPARITION_FLICKER := 0.30
const HAUNTED_BREATH := 0.75    ## chance a haunted stutter carries the sound underneath it
const FAULT_BREATH := 0.07      ## ...and the chance a genuinely broken lamp does too

var next_event := 6.0
var watcher: ShadowFigure = null
var ritual: Ritual = null
var stalker: Stalker = null
var _flickering := false
var _fault_timer := 12.0

func _ready() -> void:
	Game.phase_changed.connect(_on_phase)
	Game.game_reset.connect(_reset)
	Game.monster_released.connect(_release_stalker)

func _reset() -> void:
	_clear_figures()
	if is_instance_valid(stalker):
		stalker.queue_free()
	stalker = null
	Sfx.set_heartbeat(false)
	next_event = 8.0
	_fault_timer = 12.0

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
	# the deck's own bad lamps, on their own schedule, with nothing behind them. These are most of
	# the flickering the player sees all run - which is exactly what makes the other ones deniable
	_fault_timer -= delta
	if _fault_timer <= 0.0:
		_fault_timer = randf_range(16.0, 38.0) / clampf(0.8 + Game.intensity() * 0.25, 0.8, 2.4)
		var st: Station = Game.station
		if not st.faulty_lights.is_empty():
			_stutter(st.faulty_lights.pick_random())
	next_event -= delta
	if next_event <= 0.0:
		var I := Game.intensity()
		var base := lerpf(28.0, 7.0, clampf((I - 1.0) / 7.0, 0.0, 1.0))
		next_event = randf_range(base * 0.6, base * 1.4)
		if Game.player.outside:
			_outside_event()
		else:
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

## Out on the hull there is no corridor for anything to cross. What reaches you comes through the
## suit: a breath under the static on the radio, or a knock in the metal you are holding on to.
func _outside_event() -> void:
	if randf() < 0.5:
		Sfx.play("static", -16.0, randf_range(0.5, 0.8))
		Sfx.play("underbreath", -14.0, randf_range(0.8, 1.0))
	else:
		Sfx.play("bang", -9.0, randf_range(0.35, 0.55))

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
	var c: Array = _pick_spot(candidates, func(s): return s[0])
	var f := ShadowFigure.new()
	add_child(f)
	var side := 1.0 if randf() < 0.5 else -1.0
	var p: Vector3 = c[0]
	var t: Vector3 = c[1]
	f.cross(p + t * 2.4 * side, p - t * 2.4 * side, randf_range(0.55, 1.1))
	Sfx.play_at("whisper", p, -14.0, 30.0, 0.8)
	_flicker_near(p)
	return true

func _bang() -> void:
	var st: Station = Game.station
	var pos := st.random_point() + Vector3(randf_range(-3, 3), randf_range(-1, 1), randf_range(-3, 3))
	Sfx.play_at("bang", pos, -2.0, 60.0, randf_range(0.7, 1.2))

func _whisper() -> void:
	var head: Vector3 = Game.player.camera.global_position
	var off := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized() * 0.6
	Sfx.play_at("whisper", head + off, -6.0, 8.0, randf_range(0.85, 1.1))

## ---------------------------------------------------------------- the lights
##
## There are two reasons a lamp on this deck stutters. One is that it is a fifty year old fitting
## on a station nobody has maintained since the crew stopped filing reports. The other is that
## something is standing under it.
##
## The whole design here is that **you cannot tell which**. Both causes go through the same
## routine, draw their character from the same pool, and sound identical, because the moment the
## haunted ones have a signature the player stops doubting and starts reading. What they get
## instead is a deck that misbehaves constantly, and about one time in five that misbehaviour has
## company.

## Ways a failing lamp goes. Cause never picks from this - the roll does.
enum Stutter { BLINK, STAMMER, DYING, BANK }

## Where an apparition turns up. A third of the time it takes the spot nearest a lamp that is
## already failing - so the light you have learned not to trust is also the one with something
## under it, and the two explanations stop being separable at all. `point_of` pulls the position
## out of whatever shape of spot the caller has.
func _pick_spot(spots: Array, point_of: Callable) -> Variant:
	if Game.station.faulty_lights.is_empty() or randf() > 0.34:
		return spots.pick_random()
	var best: Variant = spots[0]
	var best_d := INF
	for s in spots:
		var p: Vector3 = point_of.call(s)
		for f: Light3D in Game.station.faulty_lights:
			var d := f.global_position.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = s
	return best

func _flicker() -> void:
	# the ambient one. Mostly a lamp that is actually broken; otherwise a lamp somewhere an
	# apparition would have picked, so "it flickered at the junction ahead" means nothing either
	var st: Station = Game.station
	var l: Light3D = null
	if not st.faulty_lights.is_empty() and randf() < 0.65:
		l = st.faulty_lights.pick_random()
	else:
		var spots: Array = st.crossing_spots()
		l = st.nearest_light(spots.pick_random()[0]) if not spots.is_empty() else st.random_light()
	_stutter(l)

## An apparition just turned up. One time in five the nearest lamp goes - sometimes as it arrives,
## sometimes a beat or two later, once it is already standing there.
func _flicker_near(pos: Vector3) -> void:
	if randf() >= APPARITION_FLICKER:
		return
	var l: Light3D = Game.station.nearest_light(pos)
	if randf() < 0.5:
		await get_tree().create_timer(randf_range(0.6, 1.6)).timeout
	_stutter(l, true)

## One routine, one pool of behaviours, no tell in the light itself. Every caller lands here.
##
## The sound is where it gets interesting. Every stutter gets the same two layers: the switching
## noise, and `ballast` - what a failing fitting actually sounds like, mains buzz gated into
## bursts with the odd contact tick. Under about three in five of the haunted ones there is a
## third layer, `underbreath`, mixed at -26 dB with a seven metre falloff: something breathing,
## close, pitched down and rolled off so that it does not arrive as a sound. It arrives as a
## suspicion that the buzz had something in it, and only if you are near it and quiet.
##
## And it plays under about one in seven of the lamps that are genuinely broken, because a tell
## with no false positives is not a tell. It is a label.
func _stutter(l: Light3D, haunted := false) -> void:
	if _flickering or l == null or not Game.power_on:
		return
	_flickering = true
	var kind: int = [Stutter.BLINK, Stutter.BLINK, Stutter.STAMMER, Stutter.STAMMER,
		Stutter.DYING, Stutter.BANK].pick_random()
	var db := randf_range(-13.0, -6.0)
	Sfx.play_at("flicker", l.global_position, db, 25.0, randf_range(0.9, 1.15))
	Sfx.play_at("ballast", l.global_position, db - randf_range(2.0, 6.0), 18.0, randf_range(0.85, 1.2))
	if randf() < (HAUNTED_BREATH if haunted else FAULT_BREATH):
		_under(l.global_position)
	match kind:
		Stutter.BLINK:
			# one or two frames of nothing. Half the time you are not sure it happened
			for i in 1 + randi() % 2:
				l.visible = false
				await get_tree().create_timer(randf_range(0.03, 0.09)).timeout
				l.visible = Game.power_on
				await get_tree().create_timer(randf_range(0.05, 0.12)).timeout
		Stutter.STAMMER:
			for i in 5 + randi() % 6:
				if not Game.power_on:
					break
				l.visible = not l.visible
				await get_tree().create_timer(randf_range(0.04, 0.16)).timeout
		Stutter.DYING:
			# a ballast giving up: sinks, hangs there dim, comes back like nothing happened
			var full := l.light_energy
			var steps := 9
			for i in steps:
				l.light_energy = full * (1.0 - float(i) / steps) * randf_range(0.7, 1.0)
				await get_tree().create_timer(randf_range(0.05, 0.11)).timeout
			await get_tree().create_timer(randf_range(0.25, 0.9)).timeout
			l.light_energy = full
		Stutter.BANK:
			# it takes its neighbour with it, which is either a shared circuit or worse
			var st: Station = Game.station
			var other: Light3D = null
			var best := INF
			for o in st.lights:
				if o == l:
					continue
				var d := o.global_position.distance_squared_to(l.global_position)
				if d < best:
					best = d
					other = o
			for i in 3 + randi() % 4:
				if not Game.power_on:
					break
				l.visible = not l.visible
				if other:
					other.visible = l.visible if randf() < 0.7 else not l.visible
				await get_tree().create_timer(randf_range(0.05, 0.18)).timeout
			if other:
				other.visible = Game.power_on
	l.visible = Game.power_on
	_flickering = false

## The layer underneath. Started a beat into the stutter so it is inside the buzz rather than
## alongside it, and quiet enough that half the time the player will decide they imagined it.
func _under(pos: Vector3) -> void:
	await get_tree().create_timer(randf_range(0.10, 0.35)).timeout
	Sfx.play_at("underbreath", pos, -26.0, 7.0, randf_range(0.86, 1.02))

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
	watcher.stand(_pick_spot(spots, func(s): return s) as Vector3, eye)
	_flicker_near(watcher.global_position)
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
	_flicker_near(f.global_position)
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
	var c: Array = _pick_spot(spots, func(s): return s[0])
	var beast := Chupacabra.new()
	add_child(beast)
	beast.lurk_at(c[0], c[1])
	_flicker_near(beast.global_position)
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
	g.lure(_pick_spot(spots, func(s): return s) as Vector3, eye)
	_flicker_near(g.global_position)
	return true

# ---------------------------------------------------------------- night
func _start_night() -> void:
	_clear_figures()
	if is_instance_valid(stalker):
		stalker.queue_free()
	stalker = null
	next_event = randf_range(12.0, 25.0)
	if Game.night_power_out:
		Sfx.play("powerdown", -2.0)
	if not Game.is_quiet_night():
		_place_ritual()

## Tonight it walks. At the start of a power failure it comes from as far from where you woke as the
## deck goes; out of a toilet trip it comes from as far from where you are standing now - which is
## the stall - and never out of the room you are trying to get back to.
func _release_stalker() -> void:
	if Game.phase != Game.Phase.NIGHT or is_instance_valid(stalker):
		return
	var st: Station = Game.station
	stalker = Stalker.new()
	add_child(stalker)
	if Game.night_toilet and Game.player != null:
		stalker.global_position = st.stalker_spawn_far_from(Game.player.camera.global_position)
	else:
		stalker.global_position = st.stalker_spawn_point()
	stalker.caught.connect(_on_caught)
	Sfx.play_at("bang", stalker.global_position, -4.0, 60.0, 0.6)

## Once a night, in a room you are not waking up in and the stalker is not starting in, somebody is
## sitting in a circle of candles. Nothing announces it: either you see warm light coming out of a
## doorway at some point tonight, or you do not.
func _place_ritual() -> void:
	if Game.day < 6:
		return          # nothing sets this up until the last two nights
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
	if Game.is_quiet_night():
		return          # asleep: nothing to hear
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
