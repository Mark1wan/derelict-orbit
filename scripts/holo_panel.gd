class_name HoloPanel
extends Node3D
## The crew terminal: shift clock, thruster fuel, tasks and where the kit is - as a hologram.
##
## In VR it is projected from an emitter on the left wrist: a translucent cyan sheet with a glowing
## frame, drifting scanlines and a scan band, joined to the emitter by a faint beam. The sheet turns
## to face your head, so it reads at any wrist angle. On the desktop it floats low on the left of
## the view. Y (left hand) or TAB toggles it, and it powers up and down with a short stutter.
## While it is closed a pulse says there is something to read - the wrist emitter in VR, a small
## "[TAB] TASKS" tag on the desktop - and it brightens when the tasks change.

const W := 0.34                  # sheet size in metres, at wrist scale
const H := 0.23
const TEXT_PIXEL := 0.00042      # metres per font pixel, at wrist scale
const OPEN_TIME := 0.22
const EMITTER_POS := Vector3(0.0, 0.028, 0.06)   # on top of the left controller, toward the wrist
const DESK_SCALE := 3.4
const DESK_POS := Vector3(-0.86, -0.46, -1.3)

const SHEET_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(0.3, 0.85, 1.0);
uniform float amount = 1.0;
uniform float aspect = 1.48;
void fragment() {
	vec2 e = min(UV, 1.0 - UV) * vec2(aspect, 1.0);   // distance to the nearest edge, in sheet heights
	float d = min(e.x, e.y);
	float frame = 1.0 - smoothstep(0.0, 0.005, abs(d - 0.012));
	float corner = 1.0 - smoothstep(0.07, 0.15, max(e.x, e.y));
	float fill = 0.06 + 0.06 * (1.0 - smoothstep(0.0, 0.3, d));
	float scan = 0.65 + 0.35 * sin(UV.y * 230.0 - TIME * 8.0);
	float sweep = exp(-pow((fract(UV.y + TIME * 0.28) - 0.5) * 16.0, 2.0));
	float grain = fract(sin(dot(floor(UV * vec2(170.0, 115.0)) + floor(TIME * 18.0), vec2(12.9898, 78.233))) * 43758.5453);
	float c = fill * scan + frame * (0.7 + 1.4 * corner) + sweep * 0.07 + grain * 0.02;
	ALBEDO = tint * c * amount;
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(0.3, 0.85, 1.0);
uniform float amount = 1.0;
void fragment() {
	// UV.y runs from the emitter (0) to the edge of the sheet (1)
	float streak = 0.6 + 0.4 * sin(UV.x * 36.0 + TIME * 3.0);
	ALBEDO = tint * 0.16 * amount * (0.2 + 0.8 * UV.y) * streak;
}
"""

var is_open := true
var holo: Node3D                 # sheet + text: what scales, fades and faces the viewer
var sheet_mat: ShaderMaterial
var title: Label3D
var text: Label3D
var hint: Label3D
var beam: MeshInstance3D
var beam_mat: ShaderMaterial
var _emitter: MeshInstance3D
var _emitter_mat: StandardMaterial3D
var _mode := "view"
var _controller: Node3D
var _camera: Node3D
var _amount := 0.0
var _pulse := 0.0
var _flicker := 1.0
var _t := 0.0

func _init() -> void:
	name = "CrewTerminal"
	holo = Node3D.new()
	add_child(holo)
	var sheet := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(W, H)
	sheet.mesh = q
	sheet_mat = _shader_mat(SHEET_SHADER, 40)
	sheet_mat.set_shader_parameter("aspect", W / H)
	sheet.material_override = sheet_mat
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holo.add_child(sheet)

	title = _label(24)
	title.text = "KESTREL-9  //  CREW TERMINAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector3(0, H * 0.5 - 0.02, 0.001)
	holo.add_child(title)

	text = _label(18)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.width = (W - 0.03) / TEXT_PIXEL
	# a left-aligned Label3D grows rightwards from its origin: put the origin at the left margin
	text.position = Vector3(-W * 0.5 + 0.014, H * 0.5 - 0.036, 0.001)
	holo.add_child(text)

	beam = MeshInstance3D.new()
	beam.mesh = ImmediateMesh.new()
	beam_mat = _shader_mat(BEAM_SHADER, 39)
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.top_level = true
	beam.visible = false
	add_child(beam)

	hint = _label(28)
	hint.text = "[TAB]  TASKS"
	hint.pixel_size = 0.0011
	hint.visible = false
	add_child(hint)

func _shader_mat(code: String, priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	m.shader = sh
	m.render_priority = priority
	return m

func _label(size: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = TEXT_PIXEL
	l.outline_size = 4
	l.modulate = Color(0.6, 0.95, 1.0)
	l.outline_modulate = Color(0.0, 0.3, 0.45, 0.6)
	l.no_depth_test = true
	l.shaded = false
	l.double_sided = true
	l.render_priority = 45
	return l

## Projected from the left wrist (VR), facing `cam`.
func attach_wrist(controller: Node3D, cam: Node3D) -> void:
	_mode = "wrist"
	_controller = controller
	_camera = cam
	_move_under(controller)
	holo.scale = Vector3.ONE
	hint.visible = false
	if _emitter == null:
		_emitter = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.014
		cm.height = 0.005
		cm.radial_segments = 12
		_emitter.mesh = cm
		_emitter_mat = StandardMaterial3D.new()
		_emitter_mat.albedo_color = Color(0.05, 0.2, 0.25)
		_emitter_mat.emission_enabled = true
		_emitter_mat.emission = Color(0.3, 0.85, 1.0)
		_emitter.material_override = _emitter_mat
		_emitter.position = EMITTER_POS
	if _emitter.get_parent() != controller:
		if _emitter.get_parent():
			_emitter.get_parent().remove_child(_emitter)
		controller.add_child(_emitter)
	_emitter.visible = true

## Floating low on the left of the view (desktop).
func attach_view(cam: Node3D) -> void:
	_mode = "view"
	_camera = cam
	_move_under(cam)
	holo.position = DESK_POS
	holo.rotation = Vector3(0.0, deg_to_rad(14.0), 0.0)
	holo.scale = Vector3.ONE * DESK_SCALE
	hint.position = Vector3(-1.45, -0.9, -1.3)
	beam.visible = false
	if _emitter:
		_emitter.visible = false

func _move_under(p: Node) -> void:
	if get_parent() == p:
		return
	if get_parent():
		reparent(p, false)
	else:
		p.add_child(self)
	transform = Transform3D.IDENTITY

func toggle() -> void:
	set_open(not is_open)

func set_open(on: bool) -> void:
	if on == is_open:
		return
	is_open = on
	_pulse = 0.0
	Sfx.play("static", -24.0, 2.3 if on else 1.5)

func set_text(s: String) -> void:
	if text.text != s:
		text.text = s

## Something on the terminal changed: if it is closed, make the pulse say so.
func notify() -> void:
	if not is_open:
		_pulse = 1.0

func _process(delta: float) -> void:
	_t += delta
	_amount = move_toward(_amount, 1.0 if is_open else 0.0, delta / OPEN_TIME)
	# a stutter while it powers up or down, and now and then a flicker
	if _amount > 0.0 and _amount < 1.0:
		_flicker = 0.55 + 0.45 * absf(sin(_t * 70.0))
	elif randf() < delta * 0.3:
		_flicker = 0.55
	else:
		_flicker = move_toward(_flicker, 1.0, delta * 6.0)
	var a := _amount * _flicker
	holo.visible = _amount > 0.001
	sheet_mat.set_shader_parameter("amount", a)
	beam_mat.set_shader_parameter("amount", a)
	title.modulate = Color(0.55, 0.95, 1.0, a)
	text.modulate = Color(0.62, 0.96, 1.0, 0.95 * a)
	title.outline_modulate = Color(0.0, 0.3, 0.45, 0.6 * a)
	text.outline_modulate = Color(0.0, 0.3, 0.45, 0.6 * a)
	_pulse = maxf(0.0, _pulse - delta * 0.35)
	var squash := lerpf(0.05, 1.0, ease(_amount, 0.4))
	var closed_glow := 0.35 + 0.35 * absf(sin(_t * 2.0)) + 2.5 * _pulse * absf(sin(_t * 7.0))
	if _mode == "wrist":
		_place_on_wrist(squash, a)
		if _emitter_mat:
			_emitter_mat.emission_energy_multiplier = 1.8 if is_open else closed_glow
	else:
		holo.scale = Vector3(DESK_SCALE, DESK_SCALE * squash, DESK_SCALE)
		hint.visible = not is_open
		hint.modulate = Color(0.55, 0.95, 1.0, clampf(0.25 + 0.3 * closed_glow, 0.0, 1.0))

func _place_on_wrist(squash: float, a: float) -> void:
	if _controller == null or _camera == null:
		return
	var emit := _controller.global_transform * EMITTER_POS
	var head := _camera.global_position
	var up := _controller.global_transform.basis.y.normalized()
	var toward := (head - emit).normalized()
	var center := emit + up * 0.14 + toward * 0.03
	var cam_up := _camera.global_transform.basis.y
	var face := (head - center).normalized()
	if absf(face.dot(cam_up)) > 0.98:
		cam_up = _camera.global_transform.basis.z
	holo.global_transform = Transform3D(Basis.looking_at(-face, cam_up), center)
	holo.scale = Vector3(1.0, squash, 1.0)
	# the beam: from the emitter to the four corners of the sheet
	beam.visible = a > 0.01
	var im := beam.mesh as ImmediateMesh
	im.clear_surfaces()
	if not beam.visible:
		return
	var bx := holo.global_transform.basis.x * (W * 0.5)
	var by := holo.global_transform.basis.y * (H * 0.5 * squash)
	var corners := [center - bx - by, center + bx - by, center + bx + by, center - bx + by]
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, beam_mat)
	for i in 4:
		var c0: Vector3 = corners[i]
		var c1: Vector3 = corners[(i + 1) % 4]
		im.surface_set_uv(Vector2(0.5, 0.0))
		im.surface_add_vertex(emit)
		im.surface_set_uv(Vector2(0.0, 1.0))
		im.surface_add_vertex(c0)
		im.surface_set_uv(Vector2(1.0, 1.0))
		im.surface_add_vertex(c1)
	im.surface_end()
