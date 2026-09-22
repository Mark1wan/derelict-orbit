class_name Slate
extends Node3D
## The survey slate: a scratched plastic card on a cord, with a pencil line of numbers on it.
##
## Ported in structure from derelict-orbit's scripts/holo_panel.gd - a quad with a shader and
## three Label3Ds over it, wrist-mounted in VR and camera-mounted on a flat screen - with the
## hologram taken out. A cave has no power, so the card is lit by your own lamp like everything
## else, and the only reason you can read it is that you are looking at it with a light on your
## head. That is a better fit than a projection, and it is also cheaper: no emission, no beam.
##
## What it says is deliberately short. Depth, distance, where you are, what shape you are, and
## how much of a held breath is left - which is the only number you will actually want when it
## matters.

const SIZE := Vector2(0.20, 0.135)
const TEXT_PIXEL := 0.00040
const OPEN_TIME := 0.20
const WRIST_POS := Vector3(0.0, 0.035, 0.09)
const VIEW_POS := Vector3(0.235, -0.185, -0.50)

## Unshaded on purpose. The card sits 50 cm from a headlamp putting out 5.2 - anything lit
## would come back pure white, and a survey slate you cannot read is not a survey slate. So
## the light is painted in instead: a soft fall-off from the top left, which is roughly where
## the beam would come from anyway since the lamp is strapped above your eyes.
const CARD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 base : source_color = vec3(0.60, 0.58, 0.52);
uniform float grime : hint_range(0.0, 1.0) = 0.40;
void fragment() {
	// Mud in the scratches, and a bevel of clean plastic at the rim.
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float scuff = fract(sin(dot(floor(UV * vec2(64.0, 44.0)), vec2(12.99, 78.23))) * 43758.5);
	vec3 c = base * (0.86 + 0.14 * scuff);
	c = mix(c, vec3(0.20, 0.15, 0.11), grime * scuff * 0.55);
	// Painted-in beam: brightest at the top left, falling away across the card.
	float lit = 1.0 - 0.45 * clamp(distance(UV, vec2(0.28, 0.22)), 0.0, 1.0);
	c *= lit;
	c = mix(c * 1.18, c, smoothstep(0.0, 0.035, edge));
	ALBEDO = c;
}
"""

var open := false
var _amount := 0.0
var card: MeshInstance3D
var title: Label3D
var body_text: Label3D
var hint: Label3D
var _mat: ShaderMaterial
var _cam: Camera3D
var _tick := 0.0

func _ready() -> void:
	card = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = SIZE
	card.mesh = qm
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = CARD_SHADER
	card.material_override = _mat
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(card)

	title = _label(24, Color(0.14, 0.12, 0.10), Vector3(0, SIZE.y * 0.5 - 0.016, 0.001))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_text = _label(19, Color(0.16, 0.14, 0.12), Vector3(-SIZE.x * 0.5 + 0.012, SIZE.y * 0.5 - 0.038, 0.001))
	body_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hint = _label(18, Color(0.45, 0.16, 0.10), Vector3(0, -SIZE.y * 0.5 + 0.014, 0.001))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visible = false

func _label(size: int, col: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = TEXT_PIXEL
	l.modulate = col
	l.position = pos
	l.no_depth_test = true
	l.render_priority = 45
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	card.add_child(l)
	return l

## Clipped to the left wrist in VR, where you look at it by turning your hand over.
func attach_wrist(controller: Node3D, cam: Camera3D) -> void:
	_cam = cam
	if get_parent():
		get_parent().remove_child(self)
	controller.add_child(self)
	position = WRIST_POS
	rotation_degrees = Vector3(-62, 0, 0)

## Bottom-right of the view on a flat screen, angled as though held.
func attach_view(cam: Camera3D) -> void:
	_cam = cam
	if get_parent():
		get_parent().remove_child(self)
	cam.add_child(self)
	position = VIEW_POS
	rotation_degrees = Vector3(-11, 13, 4)
	scale = Vector3.ONE

func toggle() -> void:
	open = not open
	if open:
		visible = true
		_refresh()

func _process(delta: float) -> void:
	_amount = move_toward(_amount, 1.0 if open else 0.0, delta / OPEN_TIME)
	if _amount <= 0.001:
		visible = false
		return
	visible = true
	# A card coming up on its cord, rather than a panel fading in.
	var s: float = ease(_amount, 0.4)
	card.scale = Vector3(s, s, 1.0)
	card.position.y = (1.0 - s) * -0.05
	if Cave.touch and _cam:
		_place_touch()
	_tick -= delta
	if _tick <= 0.0 and open:
		_tick = 0.2
		_refresh()

## On a phone the card has to be recomputed from the live viewport every frame, or turning the
## handset pushes it off the edge of the screen. Same fix as holo_panel.gd:185-194.
func _place_touch() -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect: float = maxf(vp.x / maxf(vp.y, 1.0), 0.1)
	var tan_v: float = tan(deg_to_rad(_cam.fov * 0.5))
	position = Vector3(tan_v * aspect * 0.50 * 0.60, -tan_v * 0.50 * 0.62, -0.50)
	scale = Vector3.ONE * clampf(aspect * 0.72, 0.8, 1.5)

func _refresh() -> void:
	var c: Caver = Cave.caver
	if c == null:
		return
	var b: CaverBody = c.body
	title.text = Cave.passage if Cave.passage != "" else "SOWBELLY"

	var lines: Array[String] = []
	lines.append("depth    %5.1f m" % Cave.depth)
	lines.append("deepest  %5.1f m" % Cave.deepest)
	lines.append("crawled  %5.0f m" % Cave.travelled)
	lines.append("")
	lines.append(b.label())
	lines.append("chest    %4.1f cm" % (b.chest * 100.0))
	if b.exhale > 0.15:
		lines.append("holding  %4.1f s" % b.breath_left())
	else:
		var bar := int(round(b.air * 8.0))
		lines.append("breath   " + "|".repeat(bar) + ".".repeat(8 - bar))
	body_text.text = "\n".join(lines)

	var say := b.advice()
	if say == "" and c.rope and c.rope.clipped:
		say = "on rope"
	hint.text = say
	hint.modulate = Color(0.62, 0.14, 0.08) if b.wedged else Color(0.36, 0.26, 0.12)
