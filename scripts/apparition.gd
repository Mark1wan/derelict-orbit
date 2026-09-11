extends Node3D
class_name Apparition
## The daytime apparition: a smoke figure, not a body.
##
## Two ideas underneath it. The **jinn** of Islamic belief is made of smokeless fire - not the
## ghost of a dead person but a thing of another order sharing the room with you; so this is smoke
## with an ember somewhere inside it, and the embers are the only bright thing about it. The
## Brazilian **vulto** is the shadow that stands at the edge of sight, flat, man-shaped, gone the
## moment you look straight at it; so the smoke keeps a human outline - shoulders, a head, the
## suggestion of a hood - and it has no feet. It does not walk. It slides, and when you look at it
## it comes apart rather than fading out.
##
## Built from kit/apparition_corridor.json (authored in tools/apparition_spec.py, which also
## renders the reference images in docs/). The whole figure is two draw calls: one MultiMesh of
## camera-facing puffs for the smoke, one for the embers.

const RIG_PATH := "res://kit/apparition_corridor.json"

## 1 = gathered into a figure, 0 = dispersed. Staring at it drives this down.
var form := 1.0
## Extra churn while it is moving - it trails as it slides.
var agitation := 0.0
var ember_energy := 1.0

var _puffs: Array = []
var _embers: Array = []
var _cols := {}
var _smoke: MultiMesh
var _ember_mm: MultiMesh
var _t := 0.0

static var _rig_cache: Dictionary = {}
static var _tex: ImageTexture = null

func _ready() -> void:
	var rig := _load_rig()
	_puffs = rig["puffs"]
	_embers = rig["embers"]
	var smoke: Dictionary = rig["smoke"]
	for key: String in smoke:
		var c: Array = smoke[key]
		_cols[key] = Color(c[0], c[1], c[2])

	var tex := _smoke_texture(int(rig["texture"]["size"]), int(rig["texture"]["noise_seed"]))
	_smoke = _make_layer(tex, _puffs.size(), BaseMaterial3D.BLEND_MODE_MIX)
	_ember_mm = _make_layer(tex, _embers.size(), BaseMaterial3D.BLEND_MODE_ADD)
	_update(0.0)

static func _load_rig() -> Dictionary:
	if _rig_cache.has(RIG_PATH):
		return _rig_cache[RIG_PATH]
	var f := FileAccess.open(RIG_PATH, FileAccess.READ)
	assert(f != null, "apparition rig missing: " + RIG_PATH)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	_rig_cache[RIG_PATH] = data
	return data

## One MultiMeshInstance3D of billboarded quads: per-instance colour carries the alpha, so the
## whole layer is a single draw call however many puffs it has.
func _make_layer(tex: ImageTexture, count: int, blend: BaseMaterial3D.BlendMode) -> MultiMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = blend
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = count

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# it is a hole in the corridor, not a lamp: keep it out of the fog and out of the light loop
	add_child(mmi)
	return mm

func _process(delta: float) -> void:
	_t += delta
	_update(_t)

func _update(t: float) -> void:
	var churn := 1.0 + agitation * 2.0
	var spread := (1.0 - form) * 1.6
	var fade := pow(clampf(form, 0.0, 1.0), 0.6)
	for i in _puffs.size():
		var p: Dictionary = _puffs[i]
		var pos: Array = p["pos"]
		var ph: Array = p["phase"]
		var rate: Array = p["rate"]
		var out: Array = p["out"]
		var d: float = p["drift"] * churn
		var anchor := Vector3(
			pos[0] + sin(t * rate[0] + ph[0]) * d,
			pos[1] + sin(t * rate[1] + ph[1]) * d * 0.7 + p["rise"] * t * 0.35,
			pos[2] + sin(t * rate[2] + ph[2]) * d)
		anchor += Vector3(out[0], out[1], out[2]) * spread
		var size: float = p["size"] * (1.0 + 0.12 * sin(t * rate[0] * 1.7 + ph[1])) * (1.0 + (1.0 - form) * 1.2)
		var alpha: float = p["alpha"] * (0.75 + 0.25 * sin(t * rate[2] + ph[2])) * fade
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(size, size, size)), anchor)
		xf.basis = xf.basis.rotated(Vector3.FORWARD, sin(t * p["spin"] + ph[0]) * 0.6)
		_smoke.set_instance_transform(i, xf)
		var col: Color = _cols.get(p["tint"], _cols["core"])
		_smoke.set_instance_color(i, Color(col.r, col.g, col.b, alpha))
	for i in _embers.size():
		var e: Dictionary = _embers[i]
		var pos: Array = e["pos"]
		var flick := 0.75 + 0.25 * sin(t * 7.3 + i * 2.1) * sin(t * 2.7)
		var size: float = e["size"] * (0.7 + 0.5 * form)
		_ember_mm.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3(size, size, size)), Vector3(pos[0], pos[1], pos[2])))
		var col: Color = _cols["ember"]
		_ember_mm.set_instance_color(i, Color(col.r, col.g, col.b, e["energy"] * ember_energy * flick * form))

## Come apart. Returns the tween so a caller can free the node when it finishes.
func disperse(time := 0.45) -> Tween:
	var tw := create_tween()
	tw.tween_property(self, "form", 0.0, time)
	tw.parallel().tween_property(self, "ember_energy", 0.0, time * 0.55)
	return tw

## Gather out of nothing - the same thing run backwards, which is how it arrives.
func gather(time := 0.7) -> void:
	form = 0.0
	ember_energy = 0.0
	var tw := create_tween()
	tw.tween_property(self, "form", 1.0, time)
	tw.parallel().tween_property(self, "ember_energy", 1.0, time * 1.4)

# ---------------------------------------------------------------- the puff sprite
## Soft round falloff chewed by three octaves of value noise, so the edge frays instead of reading
## as a circle. The same formula as tools/apparition_spec.py's smoke_alpha(), on the same integer
## hash, so the reference renders and the game draw the same smoke.
static func _smoke_texture(size: int, seed_: int) -> ImageTexture:
	if _tex:
		return _tex
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / float(size)
			var v := (y + 0.5) / float(size)
			img.set_pixel(x, y, Color(1, 1, 1, _alpha_at(u, v, seed_)))
	_tex = ImageTexture.create_from_image(img)
	return _tex

static func _alpha_at(u: float, v: float, seed_: int) -> float:
	var dx := u - 0.5
	var dy := v - 0.5
	var r := sqrt(dx * dx + dy * dy) * 2.0
	if r >= 1.0:
		return 0.0
	var fall := pow(1.0 - r, 1.7)
	var n := 0.0
	var amp := 0.5
	var cells := 4
	for _i in 3:
		n += _value_noise(u * cells, v * cells, cells, seed_ + cells) * amp
		amp *= 0.5
		cells *= 2
	n /= 0.875
	return clampf(fall * (0.62 + 0.52 * n), 0.0, 1.0)

static func _value_noise(x: float, y: float, cells: int, seed_: int) -> float:
	var ix := int(floor(x))
	var iy := int(floor(y))
	var fx := x - ix
	var fy := y - iy
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := _hash2(ix % cells, iy % cells, seed_)
	var b := _hash2((ix + 1) % cells, iy % cells, seed_)
	var c := _hash2(ix % cells, (iy + 1) % cells, seed_)
	var d := _hash2((ix + 1) % cells, (iy + 1) % cells, seed_)
	return (a + (b - a) * sx) * (1.0 - sy) + (c + (d - c) * sx) * sy

static func _hash2(ix: int, iy: int, seed_: int) -> float:
	var h := (ix * 374761393 + iy * 668265263 + seed_ * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)
