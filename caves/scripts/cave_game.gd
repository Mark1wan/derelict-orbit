extends Node
## Autoloaded as `Cave`. Session state, settings, and the input map - the things every other
## script needs a handle on. Ported in shape from derelict-orbit's scripts/game.gd, minus the
## day/night machine: this build is environment and movement, so there is no shift to run out
## of, nothing to survive and nothing to fail.
##
## Systems register themselves here rather than being wired in the scene (`Cave.caver = self`
## in Caver._ready, and so on), which is how derelict-orbit does it and why its scene file is
## forty lines long.

signal phase_changed(p: int)
signal notice(text: String, seconds: float)
signal progress_changed

enum Phase { TITLE, CAVING }

const DEEPEST_LABEL := "sump level"

var phase := Phase.TITLE

# Settings, all set from the title screen before anything starts.
var comfort_snap := false     ## snap turn instead of smooth, for people who get sick
var low_quality := false      ## phones by default; a title toggle otherwise
var touch := false            ## the touch overlay is up and driving the intent struct
var invert_look := false

# Who is who. Set by the nodes themselves on _ready.
var caver: Node3D = null
var cave: Node3D = null

# Where you have been. The only progress this build keeps, and the slate reads it.
var depth := 0.0              ## metres below the entrance rim, right now
var deepest := 0.0            ## the deepest you have been this trip
var travelled := 0.0          ## metres of passage crawled
var passage := ""             ## the label of the passage you are in
var visited := {}             ## passage id -> true, in the order you found them
var turned_back := false      ## you pushed the Drainpipe and backed out of it

func _ready() -> void:
	_setup_input()

func start() -> void:
	phase = Phase.CAVING
	phase_changed.emit(phase)

func reset() -> void:
	depth = 0.0
	deepest = 0.0
	travelled = 0.0
	passage = ""
	visited.clear()
	turned_back = false
	phase = Phase.TITLE
	phase_changed.emit(phase)
	progress_changed.emit()

func say(text: String, seconds := 3.5) -> void:
	notice.emit(text, seconds)

## Called by the caver every station it passes. `id` is a passage id from sowbelly.json.
func enter_passage(id: String, label: String) -> void:
	if passage == label:
		return
	passage = label
	if not visited.has(id):
		visited[id] = true
		say(label, 3.0)
	progress_changed.emit()

func note_depth(y: float) -> void:
	depth = -y
	if depth > deepest:
		deepest = depth

## True on a phone or tablet, false in a headset browser and on the desktop. Lifted verbatim
## in approach from derelict-orbit's game.gd: sniff the headset browsers out by user agent
## first, because they report coarse touch pointers and would otherwise look like phones.
func is_touch_device() -> bool:
	if OS.has_environment("CAVE_TOUCH"):
		return true
	if not OS.has_feature("web"):
		return false
	var v: int = JavaScriptBridge.eval(
		"/OculusBrowser|Quest|Pico|Wolvic/.test(navigator.userAgent) ? 0 :"
		+ " ((navigator.maxTouchPoints > 0 && matchMedia('(pointer: coarse)').matches) ? 1 : 0)", true)
	return v == 1

## Every action the game reads, built here rather than stored in project.godot so the whole
## control scheme is one readable block. Physical keycodes throughout, so it works on a
## keyboard that is not QWERTY.
func _setup_input() -> void:
	var binds := {
		"c_forward": [KEY_W],
		"c_back": [KEY_S],
		"c_left": [KEY_A],
		"c_right": [KEY_D],
		"c_exhale": [KEY_SHIFT],          # the one that matters
		"c_lower": [KEY_CTRL, KEY_C],
		"c_raise": [KEY_SPACE],
		"c_brake": [KEY_ALT],
		"c_lamp": [KEY_F],
		"c_backup": [KEY_G],
		"c_slate": [KEY_TAB],
		"c_rope": [KEY_R],
		"c_use": [KEY_E],
		"c_reset": [KEY_ENTER],
	}
	for action: String in binds:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)
		for key: int in binds[action]:
			var e := InputEventKey.new()
			e.physical_keycode = key
			InputMap.action_add_event(action, e)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("c_use", click)
