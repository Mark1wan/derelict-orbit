extends Area3D
class_name Interactable
## A wall terminal the player points at and holds TRIGGER on to complete a task.
## A task terminal names the repair tool it needs (`tool`, an Item kind): only that tool in the
## hand doing it makes progress. The main power panel needs none. All meshes are built in code
## (no assets). Collision layer 2 = interactables.

signal completed(id: String)

const COL_IDLE := Color(0.05, 0.14, 0.2)
const COL_ACTIVE := Color(1.0, 0.55, 0.1)
const COL_DONE := Color(0.1, 0.9, 0.3)
const COL_FOCUS := Color(0.35, 0.85, 1.0)
const COL_POWER := Color(1.0, 0.12, 0.05)

var id := ""
var title := ""
var room := ""
var tool := ""                  # Item kind this task needs in the hand; "" = bare hands do
var hold_time := 2.5
var is_power := false
var active := false
var done := false
var focused := false
var progress := 0.0

var screen_mat: StandardMaterial3D
var bar: MeshInstance3D
var label: Label3D
var _t := 0.0
var _tick := 0.0
var _warn := 0.0                # wrong tool: the screen blinks red for a moment

func setup(p_id: String, p_title: String, p_room: String, p_power := false, p_tool := "") -> void:
	id = p_id
	title = p_title
	room = p_room
	is_power = p_power
	tool = p_tool
	hold_time = 4.0 if p_power else 2.5
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.95, 0.75, 0.35)
	shape.shape = box
	add_child(shape)

	var housing := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.82, 0.62, 0.12)
	housing.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.22, 0.24, 0.27)
	hmat.metallic = 0.5
	hmat.roughness = 0.5
	housing.material_override = hmat
	add_child(housing)

	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.62, 0.34, 0.02)
	screen.mesh = sm
	screen.position = Vector3(0, 0.07, 0.07)
	screen_mat = StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.02, 0.02, 0.03)
	screen_mat.emission_enabled = true
	screen_mat.emission = COL_IDLE
	screen_mat.emission_energy_multiplier = 0.6
	screen.material_override = screen_mat
	add_child(screen)

	bar = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.05, 0.02)
	bar.mesh = bm
	bar.position = Vector3(0, -0.17, 0.07)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.1, 0.9, 0.3)
	bmat.emission_enabled = true
	bmat.emission = Color(0.1, 0.9, 0.3)
	bmat.emission_energy_multiplier = 2.0
	bar.material_override = bmat
	bar.scale.x = 0.001
	bar.visible = false
	add_child(bar)

	label = Label3D.new()
	label.text = _label_text()
	label.font_size = 36
	label.pixel_size = 0.0016
	label.outline_size = 8
	label.position = Vector3(0, 0.58 if tool != "" else 0.52, 0.07)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(0.8, 0.9, 1.0)
	add_child(label)
	for n in [housing, screen, bar, label]:
		n.visibility_range_end = 16.0
	_refresh()

func _label_text() -> String:
	var s := "%s\n%s" % [title.to_upper(), room]
	if tool != "":
		s += "\nNEEDS %s" % Item.LABEL.get(tool, tool.to_upper())
	return s

func set_active(on: bool) -> void:
	active = on
	done = false
	progress = 0.0
	bar.scale.x = 0.001
	_refresh()

func set_focused(f: bool) -> void:
	focused = f
	_refresh()

## Called every frame the player holds the trigger while pointing at this panel. `with` is the
## Item kind in the hand doing it ("" = empty hand). Returns false when that is not the tool this
## task needs - then nothing happens but a red blink and a buzz.
func hold(delta: float, with := "") -> bool:
	if done or not active:
		return false
	if is_power and Game.toilet_pending:
		# a night that is a power failure and a toilet trip at once: the trip comes first
		if _warn <= 0.0:
			Sfx.play_at("powerdown", global_position, -18.0, 10.0, 2.2)
			Game.notice.emit("Not yet.\nYou need the WASHROOM first.", 3.0)
		_warn = 0.5
		release()
		return false
	if tool != "" and with != tool:
		if _warn <= 0.0:
			Sfx.play_at("powerdown", global_position, -18.0, 10.0, 2.2)
		_warn = 0.5
		release()
		return false
	progress += delta / hold_time
	_tick += delta
	if _tick > 0.35:
		_tick = 0.0
		match tool:
			Item.WRENCH:
				Sfx.play_at("bang", global_position, -24.0, 10.0, 2.6 + randf() * 0.4)
			Item.MULTITOOL:
				Sfx.play_at("static", global_position, -20.0, 10.0, 1.7)
			_:
				Sfx.play_at("beep", global_position, -18.0, 12.0, 0.8 + progress * 0.6)
	if progress >= 1.0:
		progress = 1.0
		done = true
		active = false
		bar.scale.x = 1.0
		Sfx.play_at("powerup" if is_power else "complete", global_position, -4.0, 30.0)
		_refresh()
		completed.emit(id)
	else:
		bar.scale.x = maxf(progress, 0.001)
	return true

func release() -> void:
	if not done and progress > 0.0:
		progress = 0.0
		bar.scale.x = 0.001

func set_label_visible(v: bool) -> void:
	label.visible = v or is_power

func _refresh() -> void:
	var c := COL_IDLE
	var energy := 0.6
	if done:
		c = COL_DONE
		energy = 1.2
	elif active:
		c = COL_POWER if is_power else COL_ACTIVE
		energy = 1.6
	if focused and active:
		c = c.lerp(COL_FOCUS, 0.45)
		energy = 2.2
	if not Game.power_on and not is_power:
		energy = 0.0
	screen_mat.emission = c
	screen_mat.emission_energy_multiplier = energy
	bar.visible = active or done

func _process(delta: float) -> void:
	if _warn > 0.0:
		_warn -= delta
		screen_mat.emission = COL_POWER
		screen_mat.emission_energy_multiplier = 2.4 if fmod(_warn, 0.2) < 0.1 else 0.3
		if _warn <= 0.0:
			_refresh()
		return
	if not active:
		return
	_t += delta
	if is_power:
		# distress beacon: sharp blink so it can be found in the dark
		screen_mat.emission_energy_multiplier = 2.5 if fmod(_t, 1.2) < 0.15 else 0.15
	elif not focused:
		screen_mat.emission_energy_multiplier = 1.3 + 0.6 * sin(_t * 4.0)
