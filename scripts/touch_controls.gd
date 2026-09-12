class_name TouchControls
extends Control
## On-screen controls for phones and tablets, played sideways.
##
##  LEFT THUMB  anywhere in the lower left: a floating thruster stick - where the thumb lands is its
##              centre. UP and DN at the left edge fire the thrusters along the body's up.
##  RIGHT SIDE  drag to look. Press and hold still on a surface within arm's reach to grab it (the
##              phone buzzes and a ring marks the hand), then drag to pull yourself: the station
##              moves with your finger. Lift to let go and keep the momentum. Two fingers: twist to
##              roll, slide up or down together to pitch the whole body. A quick tap picks up a loose
##              item near the middle of the view.
##  BUTTONS     USE (hold it on a terminal, holding that terminal's tool), BRACE (hold on to what is
##              in front of you), DROP, LIGHT, TASKS (the crew terminal), and the four belt holsters
##              along the bottom - tap one to swap your hand with it.
##
## Every button presses the input action its keyboard key does, so the game logic is the desktop
## one. Positions are in the stretched viewport's 2D coordinates; main.gd gives touch devices a small
## base size so all of it comes out at thumb size. Held upright, a card asks to turn the phone.

const TINT := Color(0.3, 0.85, 1.0)
const STICK_R := 62.0
const STICK_DEAD := 0.12
const LONG_PRESS := 0.28      # seconds a finger rests on a surface before it takes hold
const STILL_PX := 14.0        # a finger that travelled further than this is looking, not grabbing
const TAP_TIME := 0.22
const LOOK_GAIN := 2.4        # radians of turn per screen height of drag
const PULL_GAIN := 1.3        # metres of hand travel per screen height of drag
const PITCH_GAIN := 2.0       # two-finger slide: radians of body pitch per screen height

const HOLD_ACTIONS := {"use": "d_interact", "brace": "d_brake", "up": "d_up", "down": "d_down",
	"drop": "d_drop", "light": "d_flash", "tasks": "d_menu"}

var player: Player
var debug_log := false        # print gestures to the console (?touchdebug in the page URL)
var _font: Font
var _buttons: Array[Dictionary] = []
var _fingers := {}            # touch index -> Dictionary
var _stick_center := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _twist_prev := {}
var _fps := 0.0

func _init() -> void:
	name = "TouchControls"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release_all()

func _layout() -> void:
	var w := size.x
	var h := size.y
	_buttons = [
		{"id": "use", "c": Vector2(w - 80, h - 84), "r": 46.0, "label": "USE"},
		{"id": "brace", "c": Vector2(w - 192, h - 52), "r": 30.0, "label": "BRACE"},
		{"id": "drop", "c": Vector2(w - 180, h - 146), "r": 28.0, "label": "DROP"},
		{"id": "light", "c": Vector2(w - 70, h - 196), "r": 28.0, "label": "LIGHT"},
		{"id": "tasks", "c": Vector2(52, 40), "r": 30.0, "label": "TASKS"},
		{"id": "up", "c": Vector2(36, h - 122), "r": 25.0, "label": "UP"},
		{"id": "down", "c": Vector2(36, h - 56), "r": 25.0, "label": "DN"},
	]
	for i in ToolBelt.SLOTS:
		_buttons.append({"id": "belt%d" % i, "c": Vector2(w * 0.5 + (i - 1.5) * 70.0, h - 34), "r": 27.0, "label": ""})

## Where a button is drawn (tests and review shots press it there).
func button_center(id: String) -> Vector2:
	for b: Dictionary in _buttons:
		if b["id"] == id:
			return b["c"]
	return Vector2(-1, -1)

func _button_at(p: Vector2) -> Dictionary:
	for b: Dictionary in _buttons:
		if p.distance_to(b["c"]) <= float(b["r"]) * 1.2:
			return b
	return {}

func _in_stick_zone(p: Vector2) -> bool:
	return p.x < size.x * 0.42 and p.y > size.y * 0.35

# ---------------------------------------------------------------- touches
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or player == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			finger_down(t.index, t.position)
		else:
			finger_up(t.index, t.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		finger_move(d.index, d.position)
		get_viewport().set_input_as_handled()

func finger_down(i: int, p: Vector2) -> void:
	if _fingers.has(i):
		finger_up(i, p)
	var b := _button_at(p)
	if not b.is_empty():
		_fingers[i] = {"kind": "button", "id": b["id"], "pos": p}
		_press(b["id"], true)
	elif _in_stick_zone(p) and not _has_kind("stick"):
		_fingers[i] = {"kind": "stick", "pos": p}
		_stick_center = p
		_stick_vec = Vector2.ZERO
		_log("stick")
	else:
		_fingers[i] = {"kind": "look", "pos": p, "start": p, "t": 0.0, "moved": false, "grab": false, "checked": false}
		# a second finger on the look side: this is a twist, neither finger is grabbing
		var looks := _looks()
		if looks.size() >= 2:
			for f: Dictionary in looks:
				f["moved"] = true
		_twist_prev = {}
	queue_redraw()

func finger_move(i: int, p: Vector2) -> void:
	if not _fingers.has(i):
		return
	var f: Dictionary = _fingers[i]
	var prev: Vector2 = f["pos"]
	f["pos"] = p
	match f["kind"]:
		"stick":
			_stick_vec = ((p - _stick_center) / STICK_R).limit_length(1.0)
			_apply_stick()
		"look":
			if f["grab"]:
				player.touch_pull((p - prev) / size.y * PULL_GAIN)
			else:
				if not f["moved"] and p.distance_to(f["start"]) > STILL_PX:
					f["moved"] = true
					_log("look")
				if f["moved"] and not _grabbing():
					var looks := _looks()
					if looks.size() >= 2:
						_twist(looks)
					else:
						player.touch_look((p - prev) / size.y * LOOK_GAIN)
	queue_redraw()

func finger_up(i: int, p: Vector2) -> void:
	if not _fingers.has(i):
		return
	var f: Dictionary = _fingers[i]
	_fingers.erase(i)
	match f["kind"]:
		"button":
			_press(f["id"], false)
		"stick":
			_stick_vec = Vector2.ZERO
			_apply_stick()
		"look":
			if f["grab"]:
				player.touch_grab_end()
				_log("let go")
			elif not f["moved"] and float(f["t"]) < TAP_TIME:
				_log("tap")
				player.touch_tap(p)
	_twist_prev = {}
	queue_redraw()

## Lift every finger: nothing stays pressed while the controls are hidden.
func release_all() -> void:
	for i in _fingers.keys():
		var f: Dictionary = _fingers[i]
		finger_up(i, f["pos"])
	_fingers.clear()
	_stick_vec = Vector2.ZERO
	for id: String in HOLD_ACTIONS:
		Input.action_release(HOLD_ACTIONS[id])
	for a in ["d_forward", "d_back", "d_left", "d_right"]:
		Input.action_release(a)

func _has_kind(kind: String) -> bool:
	for f: Dictionary in _fingers.values():
		if f["kind"] == kind:
			return true
	return false

func _looks() -> Array:
	var out := []
	for f: Dictionary in _fingers.values():
		if f["kind"] == "look" and not f["grab"]:
			out.append(f)
	return out

func _grabbing() -> bool:
	for f: Dictionary in _fingers.values():
		if f["kind"] == "look" and f["grab"]:
			return true
	return false

func _twist(looks: Array) -> void:
	var a: Vector2 = looks[0]["pos"]
	var b: Vector2 = looks[1]["pos"]
	var ang := (b - a).angle()
	var mid := (a + b) * 0.5
	if not _twist_prev.is_empty():
		var da := wrapf(ang - float(_twist_prev["ang"]), -PI, PI)
		var dm: Vector2 = (mid - (_twist_prev["mid"] as Vector2)) / size.y
		player.touch_turn_body(da, -dm.y * PITCH_GAIN)
	_twist_prev = {"ang": ang, "mid": mid}

func _press(id: String, down: bool) -> void:
	if id.begins_with("belt"):
		if down:
			player.desk_slot(int(id.substr(4)))
			Input.vibrate_handheld(15)
		return
	var action: String = HOLD_ACTIONS.get(id, "")
	if action == "":
		return
	if down:
		Input.action_press(action)
		Input.vibrate_handheld(10)
	else:
		Input.action_release(action)
	_log("%s %s" % [id, "down" if down else "up"])

func _apply_stick() -> void:
	var v := _stick_vec if _stick_vec.length() > STICK_DEAD else Vector2.ZERO
	_axis("d_forward", "d_back", -v.y)
	_axis("d_right", "d_left", v.x)

func _axis(pos_action: String, neg_action: String, value: float) -> void:
	if value > 0.0:
		Input.action_press(pos_action, value)
	else:
		Input.action_release(pos_action)
	if value < 0.0:
		Input.action_press(neg_action, -value)
	else:
		Input.action_release(neg_action)

func _log(s: String) -> void:
	if debug_log:
		print("[touch] ", s)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if not is_visible_in_tree() or player == null:
		return
	# a finger resting still on the look side for a moment takes hold of the surface under it
	for i in _fingers.keys():
		var f: Dictionary = _fingers[i]
		if f["kind"] != "look" or f["moved"] or f["grab"]:
			continue
		f["t"] = float(f["t"]) + delta
		if float(f["t"]) >= LONG_PRESS and not f["checked"]:
			f["checked"] = true
			if player.touch_grab_begin(f["pos"]):
				f["grab"] = true
				Input.vibrate_handheld(30)
				_log("grab")
			else:
				_log("no surface in reach")
	_fps = lerpf(_fps, Engine.get_frames_per_second(), 0.1)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if h > w:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.88))
		_text(Vector2(w * 0.5, h * 0.5 - 30), "TURN YOUR PHONE SIDEWAYS", 44, TINT)
		_text(Vector2(w * 0.5, h * 0.5 + 34), "Derelict Orbit plays in landscape", 26, Color(0.6, 0.7, 0.8))
		return
	# the view's centre: what USE, BRACE and a tap act on
	if not _grabbing():
		draw_arc(size * 0.5, 5.0, 0.0, TAU, 16, Color(1, 1, 1, 0.55), 1.5, true)
	# the stick
	var ring_c := _stick_center if _has_kind("stick") else Vector2(150, h - 110)
	var active := _has_kind("stick")
	draw_arc(ring_c, STICK_R, 0.0, TAU, 40, _col(0.5 if active else 0.18), 2.0, true)
	if active:
		draw_circle(ring_c + _stick_vec * STICK_R, 24.0, _col(0.35))
	else:
		_text(ring_c, "MOVE", 14, _col(0.35))
	# buttons
	var held := {}
	for f: Dictionary in _fingers.values():
		if f["kind"] == "button":
			held[f["id"]] = true
	var hand := player.held_kind() if player else ""
	for b: Dictionary in _buttons:
		var id: String = b["id"]
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		var label: String = b["label"]
		var lit := held.has(id)
		if id.begins_with("belt") and player:
			var it: Item = player.belt.items[int(id.substr(4))]
			label = Item.SHORT[it.kind] if it else "%d" % (int(id.substr(4)) + 1)
		draw_circle(c, r, _col(0.32 if lit else 0.08))
		draw_arc(c, r, 0.0, TAU, 32, _col(0.9 if lit else 0.45), 2.0, true)
		_text(c, label, 13 if r < 30.0 else 17, Color(0.85, 0.97, 1.0, 0.95))
	_text(Vector2(w * 0.5, h - 76), "HAND: " + (Item.LABEL.get(hand, hand.to_upper()) if hand != "" else "EMPTY"), 13, _col(0.75))
	# the hand that has hold of the station
	for f: Dictionary in _fingers.values():
		if f["kind"] == "look":
			var p: Vector2 = f["pos"]
			if f["grab"]:
				draw_circle(p, 34.0, Color(0.3, 0.85, 0.45, 0.25))
				draw_arc(p, 34.0, 0.0, TAU, 32, Color(0.4, 1.0, 0.55, 0.9), 3.0, true)
			elif not f["moved"]:
				# charging: the ring fills while the finger rests
				var k := clampf(float(f["t"]) / LONG_PRESS, 0.0, 1.0)
				draw_arc(p, 30.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, _col(0.6), 3.0, true)
	_text(Vector2(w - 34, 16), "%d fps" % roundi(_fps), 11, Color(0.6, 0.7, 0.8, 0.6))

func _col(a: float) -> Color:
	return Color(TINT.r, TINT.g, TINT.b, a)

func _text(center: Vector2, s: String, font_size: int, col: Color) -> void:
	var width := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 4.0
	draw_string(_font, center + Vector2(-width * 0.5, font_size * 0.36), s, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, col)
