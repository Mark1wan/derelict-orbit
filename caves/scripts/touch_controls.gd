class_name TouchControls
extends Control
## On-screen controls for phones and tablets, played sideways.
##
##  LEFT THUMB   anywhere in the lower left: a floating stick - where the thumb lands is its
##               centre. LOW and HIGH at the left edge change posture.
##  RIGHT SIDE   drag to look. Press and hold still on rock within reach to take hold of it
##               (the phone buzzes and a ring marks the hand), then drag to haul yourself up
##               it. Lift to let go.
##  EXHALE       the big one, bottom right, held. It is the biggest button on the screen
##               because it is the only one you will need in a hurry, and on a phone there is
##               no muscle memory to fall back on - you have to be able to find it without
##               looking away from the squeeze.
##  ALSO         LAMP, SLATE, ROPE, and BRAKE, which doubles as the rappel brake and a general
##               hold-still.
##
## Ported from derelict-orbit's scripts/touch_controls.gd: drawn entirely in _draw, laid out
## on NOTIFICATION_RESIZED, and driven by three public methods - finger_down / finger_move /
## finger_up - that the headless touch autotest calls with synthetic coordinates. The one
## change is the output: rather than forging keyboard actions with Input.action_press, it
## writes straight into the caver's Intent struct, which is the whole reason that struct exists.

const TINT := Color(0.98, 0.84, 0.46)
const DIM := Color(0.62, 0.58, 0.50)
const STICK_R := 62.0
const STICK_DEAD := 0.12
const LONG_PRESS := 0.26      # seconds a finger rests on rock before it takes hold
const STILL_PX := 14.0        # a finger that travelled further than this is looking, not grabbing
const PULL_GAIN := 1.0        # hand travel per screen height of drag

var caver: Caver
var debug_log := false
var _font: Font
var _buttons: Array[Dictionary] = []
var _fingers := {}
var _stick_center := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _held := {}               # button id -> true while a finger is on it
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
		{"id": "exhale", "c": Vector2(w - 82, h - 80), "r": 54.0, "label": "EXHALE"},
		{"id": "brake", "c": Vector2(w - 192, h - 54), "r": 30.0, "label": "BRAKE"},
		{"id": "rope", "c": Vector2(w - 186, h - 148), "r": 28.0, "label": "ROPE"},
		{"id": "lamp", "c": Vector2(w - 74, h - 194), "r": 28.0, "label": "LAMP"},
		{"id": "slate", "c": Vector2(52, 40), "r": 30.0, "label": "SLATE"},
		{"id": "low", "c": Vector2(36, h - 124), "r": 26.0, "label": "LOW"},
		{"id": "high", "c": Vector2(36, h - 58), "r": 26.0, "label": "HIGH"},
	]

## Where a button is drawn. The autotest presses them here, and so do the review screenshots.
func button_center(id: String) -> Vector2:
	for b: Dictionary in _buttons:
		if b["id"] == id:
			return b["c"]
	return Vector2(-1, -1)

func button_ids() -> Array:
	var out: Array = []
	for b: Dictionary in _buttons:
		out.append(b["id"])
	return out

func _button_at(p: Vector2) -> Dictionary:
	for b: Dictionary in _buttons:
		if p.distance_to(b["c"]) <= float(b["r"]) * 1.2:
			return b
	return {}

func _in_stick_zone(p: Vector2) -> bool:
	return p.x < size.x * 0.42 and p.y > size.y * 0.35

# ---------------------------------------------------------------- touches

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or caver == null:
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
		_fingers[i] = {"kind": "button", "id": b["id"]}
		_press(b["id"], true)
		_log("button %s" % b["id"])
	elif _in_stick_zone(p) and not _has_kind("stick"):
		_fingers[i] = {"kind": "stick"}
		_stick_center = p
		_stick_vec = Vector2.ZERO
		_log("stick")
	else:
		_fingers[i] = {"kind": "look", "pos": p, "start": p, "t": 0.0, "moved": false, "grab": false, "checked": false}
		_log("look")
	queue_redraw()

func finger_move(i: int, p: Vector2) -> void:
	if not _fingers.has(i):
		return
	var f: Dictionary = _fingers[i]
	match f["kind"]:
		"stick":
			var v: Vector2 = (p - _stick_center) / STICK_R
			_stick_vec = v.limit_length(1.0)
		"look":
			var rel: Vector2 = p - f["pos"]
			f["pos"] = p
			if f["start"].distance_to(p) > STILL_PX:
				f["moved"] = true
			if f["grab"]:
				caver.touch_pull(Vector2(rel.x, -rel.y) / maxf(size.y, 1.0) * PULL_GAIN)
			else:
				caver.touch_look(rel)
	_fingers[i] = f

func finger_up(i: int, _p: Vector2) -> void:
	if not _fingers.has(i):
		return
	var f: Dictionary = _fingers[i]
	match f["kind"]:
		"button":
			_press(f["id"], false)
		"stick":
			_stick_vec = Vector2.ZERO
		"look":
			if f["grab"]:
				caver.touch_grab_end()
	_fingers.erase(i)
	queue_redraw()

func _has_kind(kind: String) -> bool:
	for i in _fingers:
		if _fingers[i]["kind"] == kind:
			return true
	return false

## Held buttons write held values; the rest fire once on the way down. The caver's Intent is
## cleared every physics frame, so anything held has to be rewritten in _process below.
func _press(id: String, down: bool) -> void:
	_held[id] = down
	if not down:
		return
	Input.vibrate_handheld(12)
	match id:
		"lamp": caver.intent.lamp = true
		"slate": caver.intent.slate = true
		"rope": caver.intent.rope = true
		"low": caver.intent.lower = true
		"high": caver.intent.raise = true

func release_all() -> void:
	_held.clear()
	_fingers.clear()
	_stick_vec = Vector2.ZERO
	if caver:
		caver.touch_grab_end()

# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_fps = lerpf(_fps, 1.0 / maxf(delta, 0.0001), 0.05)
	if caver == null or not is_visible_in_tree():
		return

	# Held state, rewritten every frame into the struct the caver reads.
	var it := caver.intent
	it.source = Intent.Source.TOUCH
	it.move = Vector2(_stick_vec.x, -_stick_vec.y) if _stick_vec.length() > STICK_DEAD else Vector2.ZERO
	it.exhale = 1.0 if _held.get("exhale", false) else 0.0
	it.brake = 1.0 if _held.get("brake", false) else 0.0
	it.hands[0].active = true
	it.hands[1].active = false

	# A finger resting still on rock takes hold of it after a moment.
	for i in _fingers:
		var f: Dictionary = _fingers[i]
		if f["kind"] != "look" or f["grab"] or f["moved"]:
			continue
		f["t"] = float(f["t"]) + delta
		if f["t"] >= LONG_PRESS and not f["checked"]:
			f["checked"] = true
			if caver.touch_grab_begin(f["pos"]):
				f["grab"] = true
				Input.vibrate_handheld(26)
				_log("grabbed")
		_fingers[i] = f
	queue_redraw()

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if size.y > size.x:
		# Portrait is unplayable - the controls do not fit and neither does the passage.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.88))
		_text(Vector2(size.x * 0.5, size.y * 0.5), "TURN YOUR PHONE SIDEWAYS", 22, TINT, true)
		return

	for b: Dictionary in _buttons:
		var down: bool = _held.get(b["id"], false)
		var r: float = b["r"]
		var col: Color = TINT if down else DIM
		draw_circle(b["c"], r, Color(col.r, col.g, col.b, 0.14 if down else 0.07))
		draw_arc(b["c"], r, 0, TAU, 28, Color(col.r, col.g, col.b, 0.75), 2.0)
		_text(b["c"] + Vector2(0, 5), b["label"], 15 if r > 40 else 12, col, true)

	if _has_kind("stick"):
		draw_arc(_stick_center, STICK_R, 0, TAU, 32, Color(TINT.r, TINT.g, TINT.b, 0.35), 2.0)
		draw_circle(_stick_center + _stick_vec * STICK_R, 20.0, Color(TINT.r, TINT.g, TINT.b, 0.40))

	for i in _fingers:
		var f: Dictionary = _fingers[i]
		if f["kind"] == "look" and f["grab"]:
			draw_arc(f["pos"], 30.0, 0, TAU, 24, Color(0.45, 0.85, 0.45, 0.8), 3.0)
		elif f["kind"] == "look" and not f["moved"]:
			var t: float = clampf(float(f["t"]) / LONG_PRESS, 0.0, 1.0)
			if t > 0.05:
				draw_arc(f["pos"], 30.0, -PI * 0.5, -PI * 0.5 + TAU * t, 24, Color(TINT.r, TINT.g, TINT.b, 0.7), 3.0)

	# The two numbers worth having on screen on a phone, where there is no slate in view unless
	# you open it: how deep you are, and how much of a held breath is left.
	if caver and caver.started:
		_text(Vector2(size.x - 8, 16), "%.0f fps" % _fps, 12, Color(0.5, 0.5, 0.5, 0.6), false, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(size.x - 8, 34), "%.1f m down" % Cave.depth, 13, DIM, false, HORIZONTAL_ALIGNMENT_RIGHT)
		var b: CaverBody = caver.body
		if b.exhale > 0.15:
			_text(Vector2(size.x * 0.5, 34), "%.1f s" % b.breath_left(), 20, TINT, true)
		var say := b.advice()
		if say != "":
			_text(Vector2(size.x * 0.5, size.y - 176), say, 16,
				Color(0.95, 0.42, 0.30) if b.wedged else TINT, true)

func _text(at: Vector2, s: String, px: int, col: Color, centre := false,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p := at
	if centre:
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

func _log(s: String) -> void:
	if debug_log:
		print("[touch] ", s)
