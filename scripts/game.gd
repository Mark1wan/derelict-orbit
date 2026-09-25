extends Node
## Autoload "Game": global state and the day / night cycle.
##
## DAY   - power on, the crew member has maintenance tasks to finish, each with its repair tool.
## SLEEP - shift over, fade to black, moved to the sleep pod.
## NIGHT - something wakes you, or nothing does. Each night rolls its own events (see the night,
##         below): the main power may fail (reach the MAIN POWER panel in the power plant), you may
##         need the toilet (the washroom stall, scripts/washroom.gd), both, or neither. The thing
##         that walks the station is only sometimes out. Each night got through advances the day
##         counter; the haunting scales with intensity().

signal phase_changed(phase: int)
signal tasks_changed
signal notice(text: String, seconds: float)
signal power_changed(on: bool)
signal day_started(day: int)
signal game_reset
signal monster_released          ## the stalker is out tonight: the haunt manager lets it go
signal night_goal_changed        ## what tonight asks of you changed - the wrist redraws on it

enum Phase { TITLE, DAY, SLEEP, NIGHT, DEAD, WON }

const DAY_LENGTH := 150.0      # seconds of real time per shift
const MAX_DAYS := 7
const TASKS_PER_DAY := 3

## Mission days: one long job instead of three small ones. Its steps go on the crew terminal as the
## day's tasks and have to be done in order.
const MISSION_DAYS := {3: "eva_solar"}
const MISSION_DAY_LENGTH := 420.0
const EVA_STEPS := [
	{"id": "eva_suit", "title": "Put on an EVA suit", "room": "EVA AIRLOCK"},
	{"id": "eva_cycle_out", "title": "Depressurize the airlock", "room": "AIRLOCK CHAMBER"},
	{"id": "eva_reach", "title": "Tether out to the solar array", "room": "OUTSIDE"},
	{"id": "eva_unbolt", "title": "Unbolt the damaged panel", "room": "SOLAR ARRAY", "tool": "wrench"},
	{"id": "eva_splice", "title": "Splice the power coupling", "room": "SOLAR ARRAY", "tool": "multitool"},
	{"id": "eva_return", "title": "Get back in and repressurize", "room": "AIRLOCK CHAMBER"},
]

signal step_done(id: String)

## ---- the night
## Every night rolls its events independently, so they can land together. What they are, and how
## likely the thing that walks is to come with them - all tuned as one decision, against
## tools/simulate_run.py. Each odd climbs from its first-night value to its last-night value as the
## run goes on (night_ramp: the day number plus unfinished shifts), and two of them carry dread: the
## longer the power has held, or the stalker has stayed in, the likelier it is tonight. Over a
## 7-night run that is about 4 or 5 power failures and 4 nights the stalker walks, and never a run with
## only one of either.
const POWER_FAILURE_CHANCE := 0.40       ## the main power fails, on the first night...
const POWER_FAILURE_LAST := 0.70         ## ...climbing to this by the last
const POWER_DREAD := 0.15                ## added for every night in a row the power has held
const POWER_DRY_MAX := 2                 ## after this many nights in a row with the power holding, it fails
const TOILET_CHANCE := 0.25              ## you wake up needing the toilet (can land with a power failure)...
const TOILET_LAST := 0.40                ## ...climbing to this
const MONSTER_POWER := 0.80              ## a power failure from the second night on brings the stalker
const MONSTER_TOILET := 0.20             ## a trip to the toilet with the lights on
const MONSTER_COMBO := 0.45              ## a trip to the toilet with the power out
const MONSTER_RAMP := 0.20               ## added to all three by the last night
const MONSTER_DREAD := 0.20              ## ...and for every night since the second it has not walked
const STICKS_CHANCE := 0.50              ## the bundle of sticks outside the stall door, per toilet trip...
const STICKS_LAST := 0.70                ## ...climbing to this
const STICKS_MONSTER := 0.30             ## ...and what finding it adds to the odds of the stalker
const FIRST_MONSTER_NIGHT := 2           ## never on the first night, whatever else happens
const QUIET_NIGHT := 7.0                 ## seconds of black a night with nothing in it lasts

const TASK_POOL := [
	{"id": "reactor_pump", "title": "Reset coolant pump", "room": "Reactor"},
	{"id": "ls_filter", "title": "Swap O2 scrubber filter", "room": "Life Support"},
	{"id": "ls_vent", "title": "Purge CO2 vent", "room": "Life Support"},
	{"id": "comms_antenna", "title": "Realign antenna", "room": "Comms"},
	{"id": "comms_log", "title": "Upload signal log", "room": "Comms"},
	{"id": "crew_pod", "title": "Run sleep-pod diagnostics", "room": "Crew Quarters"},
	{"id": "crew_galley", "title": "Check galley circuit", "room": "Crew Quarters"},
	{"id": "hub_nav", "title": "Sync nav computer", "room": "Hub"},
]

var day := 1
var layout_seed := 0            # deck plan for this run; a new one every start
var task_pool: Array = TASK_POOL # filled by the station from the rooms it actually built
var phase: int = Phase.TITLE
var day_time := 0.0
var tasks: Array = []
var power_on := true
var night_penalty := 0          # unfinished shifts make the nights worse
var nights_survived := 0
var player: Node3D = null
var station: Node3D = null
var orbit: Node3D = null
var comfort_snap := false      # VR: rotate in 30 degree snaps instead of a smooth spin (title screen)
var touch := false             # playing with on-screen touch controls (a phone or tablet)
var low_quality := false       # lower render resolution, fewer lights - on by default on phones
var xr := false                # in a headset: everything is drawn twice, at high resolution
var mission := ""              # today's mission ("" on an ordinary shift)
var start_day := 1             # playtest shortcut: ?eva in the page URL or DERELICT_EVA=1 starts on day 3

# tonight (see the night, below)
var night_power_out := false   # the main power failed
var night_toilet := false      # you woke up needing the toilet
var toilet_pending := false    # ...and have not been yet: the power panel waits on it
var sticks := false            # the bundle was outside the stall door
var monster_out := false       # the stalker is walking
var _toilet_monster := false   # rolled in the stall's blackout, let out when the door opens
var power_held := 0            # nights in a row the power has not failed (dread, see the night)
var monster_kept := 0          # nights since the second the stalker has not walked (dread)
var _night_id := 0             # which night a delayed callback belongs to
## Tests and playtests pin tonight's rolls: {"power": bool, "toilet": bool, "sticks": bool,
## "monster": bool}, any subset - what is not pinned is rolled. DERELICT_NIGHT=power,toilet,sticks
## (or "quiet", or ?night=... in the page URL) pins every night of the run to exactly that.
var debug_night := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	# DERELICT_SEED=1234 pins the deck plan: the same station twice, for comparing a change against
	# the one before it (tools, the perf probe) rather than against a different deck
	layout_seed = int(OS.get_environment("DERELICT_SEED")) if OS.has_environment("DERELICT_SEED") else randi() % 10000
	_setup_input()
	_read_night_pin()

## A phone or tablet: a touch screen whose main pointer is a finger. Headset browsers report touch
## too, so they are left out. DERELICT_TOUCH=1 forces it (tests, review shots).
func is_touch_device() -> bool:
	if OS.has_environment("DERELICT_TOUCH"):
		return true
	if not OS.has_feature("web"):
		return false
	var v: Variant = JavaScriptBridge.eval("/OculusBrowser|Quest|Pico|Wolvic/.test(navigator.userAgent) ? 0 : ((navigator.maxTouchPoints > 0 && matchMedia('(pointer: coarse)').matches) ? 1 : 0)", true)
	return v != null and int(v) == 1

## The control that restarts the game and works terminals, in this session's words.
func use_word() -> String:
	return "USE" if touch else "TRIGGER"

func day_length() -> float:
	return MISSION_DAY_LENGTH if mission != "" else DAY_LENGTH

## The first unfinished step of today's mission, or "".
func next_step_id() -> String:
	if mission == "" or phase != Phase.DAY:
		return ""
	for t in tasks:
		if not t["done"]:
			return t["id"]
	return ""

## Something went wrong out there: the shift ends now, unfinished.
func abort_shift(text: String) -> void:
	if phase != Phase.DAY:
		return
	_end_day(false)
	notice.emit(text, 6.0)

## How bad things are. Day number, plus one per unfinished shift.
func intensity() -> float:
	return float(day) + float(night_penalty)

func start_game() -> void:
	day = start_day
	night_penalty = 0
	nights_survived = 0
	power_held = 0
	monster_kept = 0
	_begin_day()

func restart() -> void:
	phase = Phase.TITLE
	layout_seed = randi() % 10000   # a different station every run
	game_reset.emit()
	start_game()

func _begin_day() -> void:
	phase = Phase.DAY
	day_time = 0.0
	power_on = true
	_clear_night()
	tasks.clear()
	mission = MISSION_DAYS.get(day, "")
	if mission != "":
		for s: Dictionary in EVA_STEPS:
			var t := s.duplicate()
			t["done"] = false
			tasks.append(t)
	else:
		var pool := task_pool.duplicate()
		pool.shuffle()
		for i in TASKS_PER_DAY:
			var t: Dictionary = pool[i].duplicate()
			t["done"] = false
			tasks.append(t)
	power_changed.emit(true)
	phase_changed.emit(phase)
	tasks_changed.emit()
	day_started.emit(day)
	if mission != "":
		notice.emit("DAY %d  -  SPACEWALK\nThe solar array is failing. One job today:\nsuit up in the EVA AIRLOCK, go outside and fix it.\nBring the wrench and the multitool.\n%s: the steps." % [day, "TASKS" if touch else "TAB / Y"], 10.0)
	elif day == 1 and touch:
		notice.emit("DAY %d  -  KESTREL-9 DECK %04d\nShift begins. %d maintenance tasks.\nTASKS: what to fix and the tool each needs.\nPress and hold a wall to grab it, drag to pull." % [day, layout_seed, TASKS_PER_DAY], 8.0)
	elif day == 1:
		notice.emit("DAY %d  -  KESTREL-9 DECK %04d\nShift begins. %d maintenance tasks.\nTAB, or Y on the left hand: tasks and the tool each needs.\nGrab rails to move, belt what you are not holding." % [day, layout_seed, TASKS_PER_DAY], 8.0)
	else:
		notice.emit("DAY %d\nShift begins. %d maintenance tasks.\n%s: your crew terminal." % [day, TASKS_PER_DAY, "TASKS" if touch else "TAB / Y"], 7.0)

func _process(delta: float) -> void:
	if phase == Phase.DAY:
		day_time += delta
		if day_time >= day_length():
			_end_day(false)
	elif phase == Phase.NIGHT:
		_process_night()

func on_task_completed(id: String) -> void:
	if id == "power":
		_on_power_restored()
		return
	if phase != Phase.DAY:
		return
	if mission != "" and id != next_step_id():
		return
	var found := false
	for t in tasks:
		if t["id"] == id and not t["done"]:
			t["done"] = true
			found = true
	if not found:
		return
	step_done.emit(id)
	tasks_changed.emit()
	var remaining := 0
	for t in tasks:
		if not t["done"]:
			remaining += 1
	if remaining == 0:
		_end_day(true)
	elif mission != "":
		notice.emit("Done. Next: %s" % String(tasks[tasks.size() - remaining]["title"]), 4.0)
	else:
		notice.emit("Task complete. %d remaining." % remaining, 3.0)

func _end_day(all_done: bool) -> void:
	if phase != Phase.DAY:
		return
	phase = Phase.SLEEP
	phase_changed.emit(phase)
	if all_done and mission != "":
		notice.emit("The array is back online.\nShift complete. Returning to the sleep pod...", 5.0)
	elif all_done:
		notice.emit("Shift complete.\nReturning to the sleep pod...", 5.0)
	else:
		night_penalty += 1
		notice.emit("Shift over. Tasks left unfinished.\nSomething noticed.", 5.0)
	await get_tree().create_timer(6.0).timeout
	if phase == Phase.SLEEP:
		_begin_night()

# ---------------------------------------------------------------- the night
func _begin_night() -> void:
	phase = Phase.NIGHT
	_night_id += 1
	_clear_night()
	night_power_out = _roll("power", power_chance())
	night_toilet = _roll("toilet", toilet_chance())
	power_held = 0 if night_power_out else power_held + 1
	toilet_pending = night_toilet
	power_on = not night_power_out
	if night_power_out:
		power_changed.emit(false)
	phase_changed.emit(phase)
	# a power failure on its own brings the stalker with it, or does not, straight away. A toilet
	# trip decides in the stall, in the dark (toilet_blackout)
	if night_power_out and not night_toilet and _roll("monster", monster_chance()):
		_release_monster()
	night_goal_changed.emit()
	var power := "the MAIN POWER panel in the POWER PLANT"
	if night_power_out and night_toilet:
		notice.emit("NIGHT %d\nMain power failure.\nAnd you need the toilet - the WASHROOM first,\nthen %s." % [day, power], 9.0)
	elif night_power_out:
		notice.emit("NIGHT %d\nMain power failure.\nReach %s.%s" % [day, power, "\nKeep the light on it." if monster_out else ""], 8.0)
	elif night_toilet:
		notice.emit("NIGHT %d\nYou wake up needing the toilet.\nThe WASHROOM. Shut the stall door behind you." % day, 8.0)
	else:
		notice.emit("NIGHT %d\nA quiet night.\nNothing wakes you." % day, QUIET_NIGHT)
		var id := _night_id
		await get_tree().create_timer(QUIET_NIGHT).timeout
		if phase == Phase.NIGHT and _night_id == id:
			_night_over()

## Nothing tonight: no failure, no toilet. The screen stays black and the next shift starts.
func is_quiet_night() -> bool:
	return phase == Phase.NIGHT and not night_power_out and not night_toilet

## How far into the run the nights are: 0 on the first, 1 on the last. Unfinished shifts push it
## on, the same way they push intensity().
func night_ramp() -> float:
	return clampf((intensity() - 1.0) / float(MAX_DAYS - 1), 0.0, 1.0)

## How likely the main power is to fail tonight.
func power_chance() -> float:
	if power_held >= POWER_DRY_MAX:
		return 1.0
	return clampf(lerpf(POWER_FAILURE_CHANCE, POWER_FAILURE_LAST, night_ramp()) + POWER_DREAD * power_held, 0.0, 1.0)

func toilet_chance() -> float:
	return lerpf(TOILET_CHANCE, TOILET_LAST, night_ramp())

func sticks_chance() -> float:
	return lerpf(STICKS_CHANCE, STICKS_LAST, night_ramp())

## How likely the stalker is tonight, given what has happened so far.
func monster_chance() -> float:
	if day < FIRST_MONSTER_NIGHT:
		return 0.0
	var p := 0.0
	if night_toilet:
		p = MONSTER_COMBO if night_power_out else MONSTER_TOILET
	elif night_power_out:
		p = MONSTER_POWER
	else:
		return 0.0          # a quiet night: nothing to come out of
	p += MONSTER_RAMP * night_ramp() + MONSTER_DREAD * monster_kept
	if sticks:
		p += STICKS_MONSTER
	return clampf(p, 0.0, 1.0)

## The stall has gone black (scripts/washroom.gd). This is where the bundle is decided - it is put
## outside the door while nobody can see it - and with it whether the stalker comes. Returns
## whether the bundle is there.
func toilet_blackout() -> bool:
	if phase != Phase.NIGHT or not toilet_pending:
		return false
	sticks = _roll("sticks", sticks_chance())
	_toilet_monster = _roll("monster", monster_chance())
	return sticks

## Out of the stall. With the power still on that is half the night: back to bed. With it out, the
## power panel is live now.
func toilet_done() -> void:
	if phase != Phase.NIGHT or not toilet_pending:
		return
	toilet_pending = false
	if _toilet_monster:
		_release_monster()
	night_goal_changed.emit()
	if night_power_out:
		notice.emit("Now the power.\nThe MAIN POWER panel in the POWER PLANT.", 6.0)
	else:
		notice.emit("Back to bed.\n%s." % bed_room(), 5.0)

func _release_monster() -> void:
	if monster_out:
		return
	monster_out = true
	monster_released.emit()
	night_goal_changed.emit()

## Where you sleep: the room you woke up in tonight.
func bed_room() -> String:
	if station != null and station.has_method("wake_room_name"):
		return str(station.call("wake_room_name"))
	return "your bunk"

## Tonight's jobs, for the crew terminal on the wrist.
func night_goal() -> String:
	if is_quiet_night():
		return "> quiet night. sleep.\n"
	var s := ""
	if toilet_pending:
		s += "> you need the toilet (WASHROOM)\n> go in, shut the stall door\n"
	if night_power_out:
		s += "POWER: OFFLINE\n> %srestore main power (POWER PLANT)\n" % ("then " if toilet_pending else "")
	elif night_toilet and not toilet_pending:
		s += "> back to bed (%s)\n" % bed_room()
	if monster_out:
		s += "> light freezes it. dark does not.\n"
	return s

func _process_night() -> void:
	# a toilet trip with the power on ends when you are back where you sleep
	if night_power_out or not night_toilet or toilet_pending:
		return
	if player == null or station == null or not station.has_method("in_wake_room"):
		return
	if station.call("in_wake_room", player.camera.global_position):
		notice.emit("Back in your bunk.", 3.0)
		_night_over()

func _clear_night() -> void:
	night_power_out = false
	night_toilet = false
	toilet_pending = false
	sticks = false
	monster_out = false
	_toilet_monster = false

func _roll(what: String, chance: float) -> bool:
	if chance <= 0.0:
		return false          # a pin does not beat a rule: nothing brings the stalker on night one
	if debug_night.has(what):
		return bool(debug_night[what])
	return randf() < chance

func _read_night_pin() -> void:
	var pin := OS.get_environment("DERELICT_NIGHT") if OS.has_environment("DERELICT_NIGHT") else ""
	if pin == "" and OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval("(location.search.match(/[?&]night=([a-z,]+)/) || [])[1] || ''", true)
		pin = str(v) if v != null else ""
	if pin == "":
		return
	debug_night = {"power": false, "toilet": false, "sticks": false}
	for k: String in pin.split(",", false):
		if k in ["power", "toilet", "sticks", "monster"]:
			debug_night[k] = true

func _on_power_restored() -> void:
	if phase != Phase.NIGHT or toilet_pending:
		return
	power_on = true
	power_changed.emit(true)
	_night_over()

## Got through it, however it went: the next shift.
func _night_over() -> void:
	if phase != Phase.NIGHT:
		return
	nights_survived += 1
	if day >= FIRST_MONSTER_NIGHT:
		monster_kept = 0 if monster_out else monster_kept + 1
	day += 1
	if day > MAX_DAYS:
		phase = Phase.WON
		phase_changed.emit(phase)
		notice.emit("DAY %d\nA docking alarm. The rescue shuttle is here.\nYou kept Kestrel-9 alive.\n\nHold %s to play again." % [day, use_word()], 999.0)
		return
	_begin_day()

func player_caught() -> void:
	if phase != Phase.NIGHT:
		return
	phase = Phase.DEAD
	phase_changed.emit(phase)
	notice.emit("SIGNAL LOST\n\nYou survived %d night%s.\n\nHold %s to try again." % [nights_survived, "" if nights_survived == 1 else "s", use_word()], 999.0)

func clock_string() -> String:
	var frac := clampf(day_time / day_length(), 0.0, 1.0)
	var minutes := int(8 * 60 + frac * 12 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]

# ---- desktop fallback input map (built in code so project.godot stays simple)
func _setup_input() -> void:
	_add_key("d_forward", KEY_W)
	_add_key("d_back", KEY_S)
	_add_key("d_left", KEY_A)
	_add_key("d_right", KEY_D)
	_add_key("d_up", KEY_SPACE)
	_add_key("d_down", KEY_C)
	_add_key("d_brake", KEY_SHIFT)
	_add_key("d_flash", KEY_F)
	_add_key("d_interact", KEY_E)
	_add_key("d_drop", KEY_Q)
	_add_key("d_menu", KEY_TAB)
	_add_key("d_tether", KEY_T)
	_add_mouse("d_interact", MOUSE_BUTTON_LEFT)

func _add_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)

func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
