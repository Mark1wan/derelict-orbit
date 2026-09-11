extends Node
## Autoload "Game": global state and the day / night cycle.
##
## DAY   - power on, the crew member has maintenance tasks to finish.
## SLEEP - shift over, fade to black, moved to the sleep pod.
## NIGHT - main power fails. Reach the power panel in the Reactor with the flashlight.
## Each restored night advances the day counter; the haunting scales with intensity().

signal phase_changed(phase: int)
signal tasks_changed
signal notice(text: String, seconds: float)
signal power_changed(on: bool)
signal day_started(day: int)
signal game_reset

enum Phase { TITLE, DAY, SLEEP, NIGHT, DEAD, WON }

const DAY_LENGTH := 150.0      # seconds of real time per shift
const MAX_DAYS := 7
const TASKS_PER_DAY := 3

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	layout_seed = randi() % 10000
	_setup_input()

## How bad things are. Day number, plus one per unfinished shift.
func intensity() -> float:
	return float(day) + float(night_penalty)

func start_game() -> void:
	day = 1
	night_penalty = 0
	nights_survived = 0
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
	tasks.clear()
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
	if day == 1:
		notice.emit("DAY %d  -  KESTREL-9 DECK %04d\nShift begins. %d maintenance tasks.\nCheck your wrist terminal. Grab rails to move." % [day, layout_seed, TASKS_PER_DAY], 8.0)
	else:
		notice.emit("DAY %d\nShift begins. %d maintenance tasks.\nCheck your wrist terminal." % [day, TASKS_PER_DAY], 7.0)

func _process(delta: float) -> void:
	if phase == Phase.DAY:
		day_time += delta
		if day_time >= DAY_LENGTH:
			_end_day(false)

func on_task_completed(id: String) -> void:
	if id == "power":
		_on_power_restored()
		return
	if phase != Phase.DAY:
		return
	for t in tasks:
		if t["id"] == id:
			t["done"] = true
	tasks_changed.emit()
	var remaining := 0
	for t in tasks:
		if not t["done"]:
			remaining += 1
	if remaining == 0:
		_end_day(true)
	else:
		notice.emit("Task complete. %d remaining." % remaining, 3.0)

func _end_day(all_done: bool) -> void:
	if phase != Phase.DAY:
		return
	phase = Phase.SLEEP
	phase_changed.emit(phase)
	if all_done:
		notice.emit("Shift complete.\nReturning to the sleep pod...", 5.0)
	else:
		night_penalty += 1
		notice.emit("Shift over. Tasks left unfinished.\nSomething noticed.", 5.0)
	await get_tree().create_timer(6.0).timeout
	if phase == Phase.SLEEP:
		_begin_night()

func _begin_night() -> void:
	phase = Phase.NIGHT
	power_on = false
	power_changed.emit(false)
	phase_changed.emit(phase)
	notice.emit("NIGHT %d\nMain power failure.\nReach the MAIN POWER panel in the POWER PLANT.\nKeep the light on it." % day, 8.0)

func _on_power_restored() -> void:
	if phase != Phase.NIGHT:
		return
	power_on = true
	nights_survived += 1
	power_changed.emit(true)
	day += 1
	if day > MAX_DAYS:
		phase = Phase.WON
		phase_changed.emit(phase)
		notice.emit("DAY %d\nA docking alarm. The rescue shuttle is here.\nYou kept Kestrel-9 alive.\n\nHold TRIGGER to play again." % day, 999.0)
		return
	_begin_day()

func player_caught() -> void:
	if phase != Phase.NIGHT:
		return
	phase = Phase.DEAD
	phase_changed.emit(phase)
	notice.emit("SIGNAL LOST\n\nYou survived %d night%s.\n\nHold TRIGGER to try again." % [nights_survived, "" if nights_survived == 1 else "s"], 999.0)

func clock_string() -> String:
	var frac := clampf(day_time / DAY_LENGTH, 0.0, 1.0)
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
