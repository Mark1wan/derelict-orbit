extends Node3D
class_name StationClassic
## The original hand-laid Kestrel-9 (hub + four arms), kept as an alternative map: swap the
## script on the Station node in main.tscn to this file to play it. Builds Kestrel-9 procedurally. No asset files: geometry is batched through Geo (one mesh
## per material per area), textures come from StationTex, so the whole station is a few
## dozen draw calls + repeated small props, and 9 unshadowed omni lights - fine for Quest 3.
##
## Layout (top-down, +X right, -Z forward), unchanged - the haunt / stalker code depends on it:
##            Comms (arm 2, -Z)
##  LifeSup (arm 1, -X)  HUB  Reactor (arm 0, +X)
##            Crew (arm 3, +Z)

const HUB := 8.0
const ROOM := 8.0
const ARM := 14.0
const H := 4.0
const CW := 2.4      # corridor width & height (flat-to-flat of the octagonal tube)
const T := 0.2       # wall thickness
const SIDES := 8     # corridor cross-section

const ARMS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)]
const ROOM_NAMES := ["Reactor", "Life Support", "Comms", "Crew Quarters"]
const ROOM_CODES := ["MOD-A  REACTOR", "MOD-B  LIFE SUPPORT", "MOD-C  COMMS", "MOD-D  CREW QUARTERS"]

var geo: Node3D
var colliders: StaticBody3D
var lights: Array[Light3D] = []
var emissive_mats: Array[StandardMaterial3D] = []
var emergency_mats: Array[StandardMaterial3D] = []     # red guide strips: lit only when power is OFF
var emergency_lights: Array[Light3D] = []
var interactables := {}
var props: Array[Node3D] = []
var prop_spin: Array[Vector3] = []
var prop_vel: Array[Vector3] = []
var power_led: OmniLight3D
var planet: MeshInstance3D
var clouds: MeshInstance3D

# materials
var mat_hull: StandardMaterial3D        # light riveted plating (rooms)
var mat_hull_dark: StandardMaterial3D   # darker plating (corridors, ceilings)
var mat_floor: StandardMaterial3D       # grating
var mat_frame: StandardMaterial3D       # bulkhead frames, ribs, beams
var mat_metal: StandardMaterial3D       # plain dark machined metal
var mat_hazard: StandardMaterial3D
var mat_pipe: StandardMaterial3D
var mat_pipe2: StandardMaterial3D
var mat_glass: StandardMaterial3D
var mat_tank: StandardMaterial3D
var mat_strip: StandardMaterial3D       # white light fixtures
var mat_warm: StandardMaterial3D        # warm light fixtures (crew)
var mat_red: StandardMaterial3D         # emergency strips
var mat_crate: StandardMaterial3D
var mat_ext: StandardMaterial3D         # hull exterior
var mat_solar: StandardMaterial3D
var mat_truss: StandardMaterial3D        # exterior structure (self-lit a little)
var _t := 0.0
var _lamps: AreaGeo
var screen_mats: Array[StandardMaterial3D] = []   # unshaded displays: white by day, near-black in the dark

## One Geo builder per material for an area of the station; committed together.
class AreaGeo:
	var builders := {}
	var no_collide := {"strip": true, "warm": true, "red": true, "hazard": true, "ext": true}
	func g(key: String) -> Geo:
		if not builders.has(key):
			builders[key] = Geo.new()
		return builders[key]
	func commit(st: StationClassic, parent: Node, body: StaticBody3D, prefix: String) -> void:
		for key: String in builders:
			var mat: Material = st.material_for(key)
			var b: Geo = builders[key]
			b.commit(mat, parent, null if no_collide.has(key) else body, "%s_%s" % [prefix, key])

func material_for(key: String) -> Material:
	match key:
		"hull": return mat_hull
		"dark": return mat_hull_dark
		"floor": return mat_floor
		"frame": return mat_frame
		"metal": return mat_metal
		"hazard": return mat_hazard
		"pipe": return mat_pipe
		"pipe2": return mat_pipe2
		"strip": return mat_strip
		"warm": return mat_warm
		"red": return mat_red
		"ext": return mat_ext
		"solar": return mat_solar
		"truss": return mat_truss
		"crate": return mat_crate
	return mat_metal

func _ready() -> void:
	Game.station = self
	build()
	Game.power_changed.connect(set_power)
	Game.day_started.connect(_on_day_started)
	Game.game_reset.connect(func(): set_power(true))

# ---------------------------------------------------------------- materials
func _mat(albedo: Color, rough := 0.7, metal := 0.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m

func _textured(tex: Dictionary, tint: Color, scale: float, rough: float, metal: float, normal_depth := 1.0) -> StandardMaterial3D:
	var m := _mat(tint, rough, metal)
	m.albedo_texture = tex["albedo"]
	m.normal_enabled = true
	m.normal_texture = tex["normal"]
	m.normal_scale = normal_depth
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _emissive(col: Color, energy := 2.0, emergency := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col * 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	if emergency:
		emergency_mats.append(m)
		m.emission_enabled = false
	else:
		emissive_mats.append(m)
	return m

func _screen_mat(seed_: int, energy := 1.1, hue := Color(0.3, 0.9, 1.0)) -> StandardMaterial3D:
	return _display_mat(StationTex.screen(seed_, 128, 80, hue), energy)

## Self-lit display surface (screens, LED rows): unshaded so the texture is the light.
func _display_mat(t: Texture2D, energy := 1.1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = t
	m.albedo_color = Color(1, 1, 1) * energy
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	screen_mats.append(m)
	return m

func _make_materials() -> void:
	var panel := StationTex.panel(256, Color(0.62, 0.65, 0.70))
	var panel_dark := StationTex.panel(256, Color(0.40, 0.42, 0.46))
	var grate := StationTex.grate(128)
	mat_hull = _textured(panel, Color(0.78, 0.8, 0.84), 0.5, 0.62, 0.35, 1.0)
	mat_hull_dark = _textured(panel_dark, Color(0.72, 0.74, 0.78), 0.5, 0.7, 0.4, 1.0)
	mat_floor = _textured(grate, Color(0.9, 0.9, 0.9), 1.0, 0.75, 0.5, 1.4)
	mat_frame = _textured(panel_dark, Color(0.45, 0.47, 0.5), 1.0, 0.5, 0.7, 0.6)
	mat_metal = _mat(Color(0.24, 0.26, 0.3), 0.45, 0.8)
	mat_pipe = _mat(Color(0.5, 0.36, 0.26), 0.35, 0.9)
	mat_pipe2 = _mat(Color(0.55, 0.58, 0.6), 0.6, 0.5)
	mat_crate = _textured(panel_dark, Color(0.6, 0.55, 0.4), 1.5, 0.85, 0.1, 0.8)
	mat_ext = _textured(panel_dark, Color(0.35, 0.36, 0.4), 0.25, 0.8, 0.5, 0.5)
	mat_hazard = _mat(Color(1, 1, 1), 0.8, 0.0)
	mat_hazard.albedo_texture = StationTex.hazard()
	mat_hazard.uv1_triplanar = true
	mat_hazard.uv1_world_triplanar = true
	mat_hazard.uv1_scale = Vector3.ONE * 2.0
	mat_ext.disable_fog = true
	mat_ext.emission_enabled = true
	mat_ext.emission = Color(0.16, 0.18, 0.22)
	mat_ext.emission_energy_multiplier = 0.9
	mat_truss = _mat(Color(0.5, 0.52, 0.56), 0.6, 0.6)
	mat_truss.disable_fog = true
	mat_truss.emission_enabled = true
	mat_truss.emission = Color(0.22, 0.23, 0.26)
	mat_truss.emission_energy_multiplier = 0.9
	mat_solar = _mat(Color(1, 1, 1), 0.3, 0.6)
	mat_solar.disable_fog = true
	mat_solar.emission_enabled = true
	mat_solar.emission_texture = StationTex.solar()
	mat_solar.emission = Color(0.6, 0.65, 0.8)
	mat_solar.emission_energy_multiplier = 0.6
	mat_solar.albedo_texture = StationTex.solar()
	mat_solar.uv1_triplanar = true
	mat_solar.uv1_world_triplanar = true
	mat_solar.uv1_scale = Vector3.ONE * 0.5
	mat_glass = _mat(Color(0.18, 0.28, 0.38, 0.1), 0.15, 0.1)
	mat_glass.metallic_specular = 0.35
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_tank = _mat(Color(0.4, 0.85, 0.8, 0.35), 0.1, 0.6)
	mat_tank.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_strip = _emissive(Color(0.8, 0.9, 1.0), 1.0)
	mat_warm = _emissive(Color(1.0, 0.85, 0.65), 0.9)
	mat_red = _emissive(Color(1.0, 0.12, 0.05), 3.5, true)

# ---------------------------------------------------------------- primitives (single meshes)
func _mesh(m: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	(parent if parent else geo).add_child(mi)
	return mi

func _box_collider(pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	cs.rotation = rot
	colliders.add_child(cs)

func _cyl(pos: Vector3, radius: float, height: float, mat: Material, rot := Vector3.ZERO, collide := false, segs := 16) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = segs
	var mi := _mesh(m, pos, mat, rot)
	if collide:
		var cs := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		cs.shape = s
		cs.position = pos
		cs.rotation = rot
		colliders.add_child(cs)
	return mi

## A flat display: QuadMesh with a generated screen texture, facing `facing`.
func _screen(pos: Vector3, size: Vector2, facing: Vector3, seed_: int, tilt_deg := 0.0, hue := Color(0.3, 0.9, 1.0)) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := _mesh(q, pos, _screen_mat(seed_, 1.1, hue))
	mi.look_at(pos - facing, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, deg_to_rad(tilt_deg))
	return mi

func _vent(pos: Vector3, size: Vector2, facing: Vector3) -> void:
	var q := QuadMesh.new()
	q.size = size
	var m := _mat(Color(1, 1, 1), 0.8, 0.3)
	m.albedo_texture = StationTex.vent()
	m.uv1_scale = Vector3(1, size.y / size.x, 1)
	var mi := _mesh(q, pos, m)
	mi.look_at(pos - facing, Vector3.UP)

func _leds(pos: Vector3, size: Vector2, facing: Vector3, seed_: int) -> void:
	var q := QuadMesh.new()
	q.size = size
	var mi := _mesh(q, pos, _display_mat(StationTex.leds(seed_), 1.3))
	mi.look_at(pos - facing, Vector3.UP)

func _sign(text: String, pos: Vector3, facing: Vector3, size := 48, col := Color(0.85, 0.92, 1.0), pixel := 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel * 1.3
	l.outline_size = 6
	l.shaded = true
	l.modulate = col
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	geo.add_child(l)
	l.position = pos
	l.look_at(pos - facing, Vector3.UP)
	return l

func _light(pos: Vector3, energy: float, range_: float, col := Color(0.8, 0.9, 1.0)) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_energy = energy
	l.omni_range = range_
	l.light_color = col
	l.shadow_enabled = false
	add_child(l)
	lights.append(l)
	return l

func _emergency_light(pos: Vector3, energy := 0.25, range_ := 6.0) -> void:
	var e := OmniLight3D.new()
	e.position = pos
	e.light_color = Color(1, 0.1, 0.05)
	e.light_energy = energy
	e.omni_range = range_
	e.visible = false
	add_child(e)
	emergency_lights.append(e)

func _prop_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = size
	var mi := _mesh(m, pos, mat)
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	props.append(mi)
	prop_spin.append(Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)))
	prop_vel.append(Vector3.ZERO)

func _panel(id: String, title: String, room: String, pos: Vector3, facing: Vector3, power := false) -> void:
	var it := Interactable.new()
	add_child(it)
	it.setup(id, title, room, power)
	it.global_position = pos
	it.look_at(pos - facing, Vector3.UP)
	it.completed.connect(_on_task_completed)
	interactables[id] = it

func _dust(center: Vector3, extents: Vector3, amount := 36) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.07
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.014)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.9, 1.0, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	p.mesh = q
	p.position = center
	geo.add_child(p)

# ---------------------------------------------------------------- wall helpers
## Quad on a vertical wall. `cc` = a point on the wall plane, n = normal INTO the room,
## lo/hi = corners in (tangent, up) coordinates relative to cc.
func _wq(g: Geo, cc: Vector3, n: Vector3, lo: Vector2, hi: Vector2, uv := 0.5) -> void:
	var t := Vector3(-n.z, 0, n.x)
	var a := cc + t * lo.x + Vector3.UP * lo.y
	var b := cc + t * hi.x + Vector3.UP * lo.y
	var c := cc + t * hi.x + Vector3.UP * hi.y
	var d := cc + t * lo.x + Vector3.UP * hi.y
	g.quad(a, d, c, b, uv)

## A wall `span` wide and `h` tall centred on cc, optionally with a rectangular hole.
func _wall(g: Geo, cc: Vector3, n: Vector3, span: float, h: float, hole := Rect2(), uv := 0.5) -> void:
	if hole.size == Vector2.ZERO:
		_wq(g, cc, n, Vector2(-span * 0.5, -h * 0.5), Vector2(span * 0.5, h * 0.5), uv)
		return
	var x0 := hole.position.x
	var x1 := hole.end.x
	var y0 := hole.position.y
	var y1 := hole.end.y
	_wq(g, cc, n, Vector2(-span * 0.5, -h * 0.5), Vector2(x0, h * 0.5), uv)
	_wq(g, cc, n, Vector2(x1, -h * 0.5), Vector2(span * 0.5, h * 0.5), uv)
	_wq(g, cc, n, Vector2(x0, y1), Vector2(x1, h * 0.5), uv)
	_wq(g, cc, n, Vector2(x0, -h * 0.5), Vector2(x1, y0), uv)

## Rectangular frame (four bars) around a hole in a wall; runs from depth_out behind the
## wall plane to depth_in in front of it, so the reveal is closed when you look out sideways.
func _rect_frame(g: Geo, cc: Vector3, n: Vector3, hole: Rect2, bar: float, depth_in: float, depth_out := 0.0) -> void:
	var t := Vector3(-n.z, 0, n.x)
	var depth := depth_in + depth_out
	var mid := cc + n * (depth_in - depth_out) * 0.5
	var w := hole.size.x
	var h := hole.size.y
	var cx := hole.get_center().x
	var cy := hole.get_center().y
	var sz_h := _sz(n, depth, w + 2 * bar, bar)
	var sz_v := _sz(n, depth, bar, h)
	g.box(mid + t * cx + Vector3.UP * (cy + h * 0.5 + bar * 0.5), sz_h)
	g.box(mid + t * cx + Vector3.UP * (cy - h * 0.5 - bar * 0.5), sz_h)
	g.box(mid + t * (cx - w * 0.5 - bar * 0.5) + Vector3.UP * cy, sz_v)
	g.box(mid + t * (cx + w * 0.5 + bar * 0.5) + Vector3.UP * cy, sz_v)

func _glass_pane(cc: Vector3, n: Vector3, hole: Rect2, thick := 0.04) -> void:
	var m := BoxMesh.new()
	m.size = _sz(n, thick, hole.size.x, hole.size.y)
	var t := Vector3(-n.z, 0, n.x)
	var pos := cc + t * hole.get_center().x + Vector3.UP * hole.get_center().y
	_mesh(m, pos, mat_glass)
	_box_collider(pos, m.size)

## Size vector with `along_n` on the normal axis and `along_t` on the tangent axis (XZ plane).
func _sz(n: Vector3, along_n: float, along_t: float, y: float) -> Vector3:
	var t := Vector3(-n.z, 0, n.x)
	return Vector3(along_n * absf(n.x) + along_t * absf(t.x), y, along_n * absf(n.z) + along_t * absf(t.z))

## Light strip lying on a tube face. f = unit direction from the axis to the face.
func _strip_on_face(g: Geo, p0: Vector3, p1: Vector3, f: Vector3, apothem: float, width: float, inset := 0.015) -> void:
	var axis := (p1 - p0).normalized()
	var s := f.cross(axis)
	var c0 := p0 + f * (apothem - inset)
	var c1 := p1 + f * (apothem - inset)
	g.quad(c0 - s * width * 0.5, c0 + s * width * 0.5, c1 + s * width * 0.5, c1 - s * width * 0.5, 1.0)

## Flat quad on the floor plane facing up, centred on c, half-extents along dir / t.
func _floor_quad(g: Geo, c: Vector3, dir: Vector3, half_along: float, half_across: float) -> void:
	var t := Vector3(-dir.z, 0, dir.x)
	g.quad(c - dir * half_along - t * half_across, c - dir * half_along + t * half_across,
		c + dir * half_along + t * half_across, c + dir * half_along - t * half_across, 1.0)

# ---------------------------------------------------------------- corridor
func _corridor(i: int, dir: Vector3, a: float, b: float) -> void:
	var area := AreaGeo.new()
	var t := Vector3(-dir.z, 0, dir.x)
	var p0 := dir * a
	var p1 := dir * b
	var ap := CW * 0.5
	var floor_i := Geo.floor_face(dir, ap, SIDES)
	var wall_g := area.g("dark")
	var floor_g := area.g("floor")
	var win_i := Geo.face_toward(dir, ap, SIDES, -t)
	var skip := Geo.new()
	wall_g.tube(p0, p1, ap, SIDES, true, func(fi: int) -> Geo: return floor_g if fi == floor_i else (skip if fi == win_i else wall_g))
	# the -t wall is rebuilt with a porthole halfway along: octagonal frame + glass, space outside
	var mid := (a + b) * 0.5
	var wall_h := 2.0 * ap * tan(PI / SIDES)
	var hole := Rect2(-0.3, -0.25, 0.6, 0.6)
	_wall(wall_g, dir * mid - t * ap, t, b - a, wall_h, hole)
	area.g("frame").ring(dir * mid - t * (ap + 0.02), t, 0.31, 0.46, 0.16, 8, 1.0)
	_glass_pane(dir * mid - t * (ap - 0.01), t, hole)
	# exterior shell (seen through windows / from the hub skylight)
	area.g("ext").tube(p0 - dir * 0.3, p1 + dir * 0.3, ap + 0.35, SIDES, false)

	# ribs every 3.5 m and bulkhead door frames straddling the wall at each end
	var frame := area.g("frame")
	var x := a + 1.75
	while x < b - 1.0:
		frame.ring(dir * x, dir, ap - 0.1, ap + 0.12, 0.18, SIDES, 1.0)
		x += 3.5
	for e: float in [a - T * 0.5, b + T * 0.5]:
		frame.ring(dir * e, dir, ap - 0.08, ap + 0.55, 0.42, SIDES, 1.0)
		area.g("hazard").ring(dir * e, dir, ap - 0.08, ap - 0.02, 0.44, SIDES, 1.0)
	# hazard thresholds on the floor at both ends
	for e: float in [a + 0.45, b - 0.45]:
		_floor_quad(area.g("hazard"), dir * e + Vector3(0, -ap + 0.01, 0), dir, 0.2, ap - 0.1)

	# light strips on the two upper chamfers, broken into segments between ribs
	var up_l := (Vector3.UP + t).normalized()
	var up_r := (Vector3.UP - t).normalized()
	var s := a + 0.6
	while s < b - 0.6:
		var e2 := minf(s + 2.6, b - 0.6)
		_strip_on_face(area.g("strip"), dir * s, dir * e2, up_l, ap, 0.14)
		_strip_on_face(area.g("strip"), dir * s, dir * e2, up_r, ap, 0.14)
		s += 3.5
	# red emergency guide strips along both floor edges (only lit in the dark)
	var dn_l := (-Vector3.UP + t).normalized()
	var dn_r := (-Vector3.UP - t).normalized()
	_strip_on_face(area.g("red"), p0 + dir * 0.5, p1 - dir * 0.5, dn_l, ap, 0.05)
	_strip_on_face(area.g("red"), p0 + dir * 0.5, p1 - dir * 0.5, dn_r, ap, 0.05)

	# handrails along both walls, with brackets
	var metal := area.g("metal")
	for side: float in [-1.0, 1.0]:
		var wall_off := t * side * (ap - 0.11)
		var ry := Vector3(0, -0.2, 0)
		if side < 0:   # porthole side: two rails either side of the window
			metal.pipe(p0 + dir * 0.7 + wall_off + ry, dir * (mid - 0.75) + wall_off + ry, 0.028)
			metal.pipe(dir * (mid + 0.75) + wall_off + ry, p1 - dir * 0.7 + wall_off + ry, 0.028)
		else:
			metal.pipe(p0 + dir * 0.7 + wall_off + ry, p1 - dir * 0.7 + wall_off + ry, 0.028)
		var bx := a + 0.9
		while bx < b - 0.7:
			if side > 0 or absf(bx - mid) > 0.9:
				metal.box(dir * bx + t * side * (ap - 0.06) + ry, _sz(dir, 0.06, 0.1, 0.05))
			bx += 2.2
	# conduit bundle along the lower-left chamfer, cable tray upper-right
	var pipe := area.g("pipe")
	var pipe2 := area.g("pipe2")
	var lc := dn_l * (ap - 0.16)
	pipe.pipe(p0 + lc, p1 + lc, 0.075)
	pipe2.pipe(p0 + lc + t * 0.16 + Vector3(0, 0.05, 0), p1 + lc + t * 0.16 + Vector3(0, 0.05, 0), 0.045)
	var uc := up_r * (ap - 0.1)
	for k in 3:
		var off := t * (-0.06 + k * 0.06) + Vector3(0, -0.06 + k * 0.03, 0)
		pipe2.pipe(p0 + uc + off, p1 + uc + off, 0.012, 6)
	# junction box halfway along the cable tray
	metal.box(dir * ((a + b) * 0.5) + uc + Vector3(0, -0.02, 0), _sz(dir, 0.3, 0.26, 0.14))

	# one ceiling light per corridor + a "section" label on both walls at the mid rib
	_light(dir * (a + b) * 0.5 + Vector3(0, 0.75, 0), 0.9, 11.0, Color(0.8, 0.88, 1.0))
	_sign("SECTION %d" % (i + 1), dir * (mid - 1.6) + t * (ap - 0.02) + Vector3(0, 0.33, 0), -t, 40, Color(0.7, 0.8, 0.9), 0.003)
	_sign("SECTION %d" % (i + 1), dir * (mid - 1.6) - t * (ap - 0.02) + Vector3(0, 0.33, 0), t, 40, Color(0.7, 0.8, 0.9), 0.003)
	area.commit(self, geo, colliders, "corridor%d" % i)

# ---------------------------------------------------------------- rooms
## Interior of a w x h x d room centred on c. doors/windows/no_rail: arrays of wall normals
## (pointing out of the room). skylight > 0 cuts a square opening that size in the ceiling.
func _room(c: Vector3, w: float, h: float, d: float, doors: Array, windows: Array, area: AreaGeo, warm := false, skylight := 0.0, no_rail: Array = []) -> void:
	var hull := area.g("hull")
	var dark := area.g("dark")
	var frame := area.g("frame")
	var metal := area.g("metal")
	var size := Vector3(w, h, d)
	var cy := c.y + h * 0.5
	area.g("floor").box_faces(c, size, [5], true, 0.5)
	if skylight > 0.0:
		var e := w * 0.5
		var s := skylight * 0.5
		var rim := (e - s) * 0.5
		dark.box_faces(Vector3(c.x, cy, c.z - s - rim), Vector3(w, 0.002, e - s), [5])
		dark.box_faces(Vector3(c.x, cy, c.z + s + rim), Vector3(w, 0.002, e - s), [5])
		dark.box_faces(Vector3(c.x - s - rim, cy, c.z), Vector3(e - s, 0.002, skylight), [5])
		dark.box_faces(Vector3(c.x + s + rim, cy, c.z), Vector3(e - s, 0.002, skylight), [5])
	else:
		dark.box_faces(c, size, [4], true, 0.5)
	area.g("ext").box(c, size + Vector3(2 * T + 0.3, 2 * T + 0.3, 2 * T + 0.3))
	for n: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var half := (w * 0.5) if absf(n.x) > 0.5 else (d * 0.5)
		var span := d if absf(n.x) > 0.5 else w
		var wc := c + n * half
		var into := -n
		var t := Vector3(-n.z, 0, n.x)
		if doors.has(n):
			_wall(hull, wc, into, span, h, Rect2(-CW * 0.5, -CW * 0.5, CW, CW))
		elif windows.has(n):
			var hole := Rect2(-1.7, -0.3, 3.4, 1.4)
			_wall(hull, wc, into, span, h, hole)
			_rect_frame(frame, wc, into, hole, 0.14, 0.16, 0.45)
			_glass_pane(wc + into * 0.02, into, hole)
			frame.box(wc + into * 0.05 + Vector3.UP * hole.get_center().y, _sz(n, 0.06, 0.05, hole.size.y))
		else:
			_wall(hull, wc, into, span, h)
		# darker wainscot band along the bottom of every wall, with a lip
		if not doors.has(n):
			_wq(dark, wc + into * 0.03, into, Vector2(-span * 0.5, -h * 0.5), Vector2(span * 0.5, -h * 0.5 + 0.7), 0.5)
			frame.box(wc + into * 0.035 + Vector3.UP * (-h * 0.5 + 0.72), _sz(n, 0.07, span - 0.2, 0.05))
		else:
			var piece := (span * 0.5 - CW * 0.5) * 0.5
			for side: float in [-1.0, 1.0]:
				var x0 := side * (CW * 0.5 + piece)
				_wq(dark, wc + into * 0.03, into, Vector2(x0 - piece, -h * 0.5), Vector2(x0 + piece, -h * 0.5 + 0.7), 0.5)
				frame.box(wc + into * 0.035 + t * x0 + Vector3.UP * (-h * 0.5 + 0.72), _sz(n, 0.07, piece * 2 - 0.2, 0.05))
		# handrail along the wall at chest height (short grab rails beside doors)
		if no_rail.has(n):
			continue
		var rail_y := -0.15
		var rail_in := into * 0.12
		if doors.has(n) or windows.has(n):
			var gap := CW * 0.5 + 0.2 if doors.has(n) else 1.9
			var x1 := CW * 0.5 + 1.3 if doors.has(n) else span * 0.5 - 0.4
			for side: float in [-1.0, 1.0]:
				metal.pipe(wc + rail_in + t * side * gap + Vector3.UP * rail_y, wc + rail_in + t * side * x1 + Vector3.UP * rail_y, 0.028)
				metal.box(wc + into * 0.06 + t * side * ((gap + x1) * 0.5) + Vector3.UP * rail_y, _sz(n, 0.06, 0.1, 0.05))
		else:
			metal.pipe(wc + rail_in - t * (span * 0.5 - 0.4) + Vector3.UP * rail_y, wc + rail_in + t * (span * 0.5 - 0.4) + Vector3.UP * rail_y, 0.028)
			for k: float in [-0.3, 0.3]:
				metal.box(wc + into * 0.06 + t * (span * k) + Vector3.UP * rail_y, _sz(n, 0.06, 0.1, 0.05))
	# chamfered vertical corners (octagonal footprint feel)
	var ch := 0.55
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var cx := c.x + sx * (w * 0.5)
			var cz := c.z + sz * (d * 0.5)
			var pa := Vector3(cx - sx * ch, c.y - h * 0.5, cz)
			var pb := Vector3(cx, c.y - h * 0.5, cz - sz * ch)
			var pc := Vector3(cx, c.y + h * 0.5, cz - sz * ch)
			var pd := Vector3(cx - sx * ch, c.y + h * 0.5, cz)
			if sx * sz > 0:
				frame.quad(pb, pa, pd, pc, 0.5)
			else:
				frame.quad(pa, pb, pc, pd, 0.5)
	# ceiling: crossing structural beams (not under a skylight) and four light panels
	if skylight <= 0.0:
		frame.box(Vector3(c.x, cy - 0.16, c.z), Vector3(w - 0.2, 0.32, 0.28))
		frame.box(Vector3(c.x, cy - 0.16, c.z), Vector3(0.28, 0.32, d - 0.2))
	var lamp := area.g("warm" if warm else "strip")
	var lx := w * 0.34 if skylight > 0.0 else w * 0.25
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lc := Vector3(c.x + sx * lx, cy - 0.02, c.z + sz * d * 0.25)
			lamp.box_faces(lc, Vector3(1.4, 0.03, 0.5), [5])
			frame.box(lc + Vector3(0, 0.01, 0), Vector3(1.5, 0.04, 0.6))
	# ceiling conduits along two edges
	area.g("pipe").pipe(c + Vector3(-w * 0.5 + 0.25, cy - 0.22, -d * 0.5 + 0.5), c + Vector3(-w * 0.5 + 0.25, cy - 0.22, d * 0.5 - 0.5), 0.07)
	area.g("pipe2").pipe(c + Vector3(-w * 0.5 + 0.42, cy - 0.16, -d * 0.5 + 0.5), c + Vector3(-w * 0.5 + 0.42, cy - 0.16, d * 0.5 - 0.5), 0.04)
	area.g("pipe2").pipe(c + Vector3(-w * 0.5 + 0.5, cy - 0.3, d * 0.5 - 0.5), c + Vector3(w * 0.5 - 0.5, cy - 0.3, d * 0.5 - 0.5), 0.04)
	_dust(c, Vector3(w * 0.45, h * 0.45, d * 0.45))

## Names on both faces of a bulkhead ring (centred on ring_c) plus status lamps:
## white bar on power, red bar in the dark.
func _door_signs(ring_c: Vector3, n_out: Vector3, inside_text: String, outside_text: String) -> void:
	var ap := CW * 0.5
	var y := ap + 0.36
	_sign(inside_text, ring_c - n_out * 0.225 + Vector3(0, y, 0), -n_out, 54, Color(0.95, 0.97, 1.0), 0.0035)
	_sign(outside_text, ring_c + n_out * 0.225 + Vector3(0, y, 0), n_out, 54, Color(0.95, 0.97, 1.0), 0.0035)
	for side: float in [-1.0, 1.0]:
		var p := ring_c + n_out * side * 0.222 + Vector3(0, ap + 0.16, 0)
		_lamps.g("strip").box(p, _sz(n_out, 0.02, 0.9, 0.05))
		_lamps.g("red").box(p + Vector3(0, -0.09, 0), _sz(n_out, 0.02, 0.9, 0.04))

# ---------------------------------------------------------------- outside
func _build_outside() -> void:
	var sky := SphereMesh.new()
	sky.radius = 170.0
	sky.height = 340.0
	sky.radial_segments = 24
	sky.rings = 12
	var sky_mat := StandardMaterial3D.new()
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	sky_mat.albedo_texture = StationTex.stars()
	sky_mat.disable_fog = true
	_mesh(sky, Vector3.ZERO, sky_mat)
	# the planet, big and close: fills the hub skylight
	var pm := SphereMesh.new()
	pm.radius = 26.0
	pm.height = 52.0
	pm.radial_segments = 48
	pm.rings = 24
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_texture = StationTex.planet()
	pmat.disable_fog = true
	planet = _mesh(pm, Vector3(16, 48, -20), pmat)
	planet.rotation = Vector3(0.3, 0, 0.2)
	var am := SphereMesh.new()
	am.radius = 26.9
	am.height = 53.8
	am.radial_segments = 32
	am.rings = 16
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.albedo_color = Color(0.45, 0.7, 1.0, 0.18)
	amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amat.disable_fog = true
	clouds = _mesh(am, planet.position, amat)
	# the sun: a bright disc far away, a focal point through the windows
	var sun := SphereMesh.new()
	sun.radius = 5.0
	sun.height = 10.0
	sun.radial_segments = 16
	sun.rings = 8
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.97, 0.9)
	smat.disable_fog = true
	_mesh(sun, Vector3(-120, 40, 90), smat)

	# structure outside the hull: a truss spine over the hub, solar wings, radiators, dish
	var ext := AreaGeo.new()
	var tr := ext.g("truss")
	var y := H * 0.5 + T + 0.9
	tr.box(Vector3(0, y, 0), Vector3(30, 0.5, 0.5))
	tr.box(Vector3(0, y, 0), Vector3(0.5, 0.5, 30))
	tr.box(Vector3(0, y + 1.6, 0), Vector3(30, 0.35, 0.35))
	tr.box(Vector3(0, y + 1.6, 0), Vector3(0.35, 0.35, 30))
	var k := -14.0
	while k <= 14.0:
		tr.box(Vector3(k, y + 0.8, 0), Vector3(0.18, 1.6, 0.18))
		tr.box(Vector3(0, y + 0.8, k), Vector3(0.18, 1.6, 0.18))
		k += 2.0
	var sol := ext.g("solar")
	for sz: float in [-1.0, 1.0]:
		var wing := Vector3(0, y + 2.6, sz * 24.0)
		tr.box(Vector3(0, y + 2.2, sz * 18.5), Vector3(0.3, 0.3, 9.0))
		sol.box(wing, Vector3(14.0, 0.08, 4.5))
		tr.box(wing, Vector3(14.2, 0.14, 0.2))
	var rad := ext.g("ext")
	for sx: float in [-1.0, 1.0]:
		rad.box(Vector3(HUB * 0.5 + ARM + ROOM + 3.0, 0.0, sx * 5.0), Vector3(6.0, 3.2, 0.1))
		tr.box(Vector3(HUB * 0.5 + ARM + ROOM + 0.9, 0.0, sx * 5.0), Vector3(2.0, 0.2, 0.2))
	# comms dish outside the comms window (-X side of the room)
	var cc := room_center(2)
	var dish_pos := cc + Vector3(-ROOM * 0.5 - 4.5, 0.6, 1.5)
	tr.box(dish_pos + Vector3(2.2, -1.2, 0), Vector3(4.6, 0.25, 0.25))
	tr.box(dish_pos + Vector3(0, -0.6, 0), Vector3(0.25, 1.4, 0.25))
	var dish := CylinderMesh.new()
	dish.top_radius = 2.2
	dish.bottom_radius = 1.7
	dish.height = 0.3
	dish.radial_segments = 20
	_mesh(dish, dish_pos, mat_truss, Vector3(0.5, 0, 0.4))
	# outside the crew window (+X side): an airlock collar and a docked supply capsule
	var crew := room_center(3)
	var hatch := crew + Vector3(ROOM * 0.5 + 1.3, 0.2, 1.0)
	rad.prism(hatch + Vector3(-0.6, 0, 0), hatch + Vector3(0.6, 0, 0), 1.1, 8)
	ext.g("truss").prism(hatch + Vector3(1.2, 0, 0), hatch + Vector3(5.2, 0, 0), 1.35, 10)
	ext.g("truss").prism(hatch + Vector3(5.2, 0, 0), hatch + Vector3(6.6, 0, 0), 0.9, 10)
	ext.commit(self, geo, null, "outside")

# ---------------------------------------------------------------- build
func build() -> void:
	geo = Node3D.new()
	geo.name = "Geometry"
	add_child(geo)
	colliders = StaticBody3D.new()
	colliders.name = "Colliders"
	colliders.collision_layer = 1
	colliders.collision_mask = 0
	add_child(colliders)
	_make_materials()
	_lamps = AreaGeo.new()

	# ---- hub
	var hub := AreaGeo.new()
	_room(Vector3.ZERO, HUB, H, HUB, ARMS, [], hub, false, 3.4)
	_build_hub(hub)
	hub.commit(self, geo, colliders, "hub")

	# ---- arms
	for i in 4:
		var d: Vector3 = ARMS[i]
		var t := Vector3(-d.z, 0, d.x)
		var a := HUB * 0.5 + T
		var b := HUB * 0.5 + ARM - T
		_corridor(i, d, a, b)
		var c := d * (HUB * 0.5 + ARM + ROOM * 0.5)
		var area := AreaGeo.new()
		var win: Array = [-t] if i >= 2 else []
		var no_rail: Array = [d, t] if i == 0 else [t]
		_room(c, ROOM, H, ROOM, [-d], win, area, i == 3, 0.0, no_rail)
		_door_signs(d * (HUB * 0.5 + T * 0.5), d, ROOM_NAMES[i].to_upper(), "HUB")
		_door_signs(d * (HUB * 0.5 + ARM - T * 0.5), d, ROOM_CODES[i], "HUB")
		_emergency_light(c - d * (ROOM * 0.5 - 1.2) + Vector3(0, 1.3, 0), 0.22, 5.0)
		var back := c + d * (ROOM * 0.5 - 0.07)
		var side := c + t * (ROOM * 0.5 - 0.07)
		match i:
			0: _build_reactor(area, c, d, t, back, side)
			1: _build_lifesupport(area, c, d, t, back, side)
			2: _build_comms(area, c, d, t, back, side)
			3: _build_crew(area, c, d, t, back, side)
		area.commit(self, geo, colliders, "room%d" % i)

	_lamps.commit(self, geo, null, "lamps")
	_build_outside()
	# a couple of loose crates drifting in the hub
	_prop_box(Vector3(-2.2, 0.6, -1.5), Vector3(0.6, 0.6, 0.6), mat_crate)
	_prop_box(Vector3(1.5, -0.9, -2.4), Vector3(0.4, 0.4, 0.8), mat_crate)

func _build_hub(area: AreaGeo) -> void:
	var frame := area.g("frame")
	var metal := area.g("metal")
	_light(Vector3(0, 1.3, 0), 1.0, 10.0)
	_emergency_light(Vector3(0, 1.6, 0), 0.22, 6.0)
	# skylight: frame ring around the opening, cross mullion, glass, a short shaft up to the outer hull
	var cy := H * 0.5
	var sk := 3.4
	var s := sk * 0.5
	for sx: float in [-1.0, 1.0]:
		frame.box(Vector3(sx * (s + 0.1), cy - 0.05, 0), Vector3(0.2, 0.12, sk + 0.4))
		frame.box(Vector3(0, cy - 0.05, sx * (s + 0.1)), Vector3(sk + 0.4, 0.12, 0.2))
	frame.box(Vector3(0, cy + 0.1, 0), Vector3(0.08, 0.3, sk))
	frame.box(Vector3(0, cy + 0.1, 0), Vector3(sk, 0.3, 0.08))
	for sx: float in [-1.0, 1.0]:
		frame.box_faces(Vector3(sx * s, cy + 0.35, 0), Vector3(0.001, 0.7, sk), [2 if sx < 0 else 3])
		frame.box_faces(Vector3(0, cy + 0.35, sx * s), Vector3(sk, 0.7, 0.001), [0 if sx < 0 else 1])
	var gm := BoxMesh.new()
	gm.size = Vector3(sk, 0.04, sk)
	_mesh(gm, Vector3(0, cy + 0.3, 0), mat_glass)
	_box_collider(Vector3(0, cy + 0.05, 0), Vector3(sk, 0.1, sk))
	area.g("strip").ring(Vector3(0, cy - 0.03, 0), Vector3.UP, s + 0.32, s + 0.42, 0.02, 8, 1.0)

	# nav console between the +X and +Z doors: desk, angled screens, keyboard
	var desk := Vector3(2.55, -1.35, 2.55)
	metal.box(desk, Vector3(1.5, 1.3, 1.5))
	frame.box(desk + Vector3(0, 0.7, 0), Vector3(1.6, 0.1, 1.6))
	_box_collider(desk, Vector3(1.5, 1.3, 1.5))
	_panel("hub_nav", "Sync nav computer", "Hub", Vector3(3.9 - T * 0.5 - 0.06, 0.3, 2.6), Vector3(-1, 0, 0))
	var face := Vector3(-0.7, 0.3, -0.7).normalized()
	_screen(desk + Vector3(-0.55, 0.95, -0.35), Vector2(0.7, 0.42), face, 3, 0.0)
	_screen(desk + Vector3(-0.2, 0.95, -0.62), Vector2(0.5, 0.32), face, 4, 0.0, Color(0.9, 0.6, 0.2))
	metal.box(desk + Vector3(-0.35, 0.72, -0.35), Vector3(0.5, 0.03, 0.2))
	# octagonal hazard ring on the floor in the middle of the hub
	area.g("hazard").ring(Vector3(0, -H * 0.5 + 0.006, 0), Vector3.UP, 1.5, 1.7, 0.005, 8, 1.0)
	# lockers in the three free corners, against the z-walls
	for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1)]:
		for k in 2:
			var p := Vector3(corner.x * (HUB * 0.5 - 0.75 - k * 0.68), -1.0, corner.z * (HUB * 0.5 - 0.26))
			metal.box(p, Vector3(0.62, 2.0, 0.5))
			frame.box(p + Vector3(0.2 * corner.x, 0, -corner.z * 0.26), Vector3(0.02, 1.1, 0.02))
		_box_collider(Vector3(corner.x * (HUB * 0.5 - 1.09), -1.0, corner.z * (HUB * 0.5 - 0.26)), Vector3(1.4, 2.0, 0.5))
	_vent(Vector3(-HUB * 0.5 + 0.01, 1.2, -2.9), Vector2(0.9, 0.45), Vector3(1, 0, 0))
	_vent(Vector3(HUB * 0.5 - 0.01, 1.2, -2.9), Vector2(0.9, 0.45), Vector3(-1, 0, 0))
	_leds(Vector3(-2.9, 0.9, HUB * 0.5 - 0.17), Vector2(0.3, 0.6), Vector3(0, 0, -1), 5)
	metal.box(Vector3(-2.9, 0.9, HUB * 0.5 - 0.09), Vector3(0.45, 0.8, 0.16))
	_sign("KESTREL-9\nORBITAL MAINTENANCE STATION", Vector3(-2.2, 1.55, HUB * 0.5 - 0.02), Vector3(0, 0, -1), 34, Color(0.75, 0.85, 0.95), 0.0035)
	_sign("KESTREL-9\nORBITAL MAINTENANCE STATION", Vector3(2.2, 1.55, -HUB * 0.5 + 0.02), Vector3(0, 0, 1), 34, Color(0.75, 0.85, 0.95), 0.0035)
	# handrail loop under the ceiling for pulling yourself across
	for sx: float in [-1.0, 1.0]:
		metal.pipe(Vector3(sx * 2.4, cy - 0.5, -2.6), Vector3(sx * 2.4, cy - 0.5, 2.6), 0.028)
		metal.pipe(Vector3(-2.6, cy - 0.5, sx * 2.4), Vector3(2.6, cy - 0.5, sx * 2.4), 0.028)

func _build_reactor(area: AreaGeo, c: Vector3, d: Vector3, t: Vector3, back: Vector3, side: Vector3) -> void:
	var frame := area.g("frame")
	var metal := area.g("metal")
	var pipe := area.g("pipe")
	var core := c + t * 1.6
	_light(c + Vector3(0, 1.4, 0), 0.9, 9.0, Color(0.85, 0.9, 0.85))
	# core vessel: tall cylinder with glowing coolant rings, inside a cage of vertical bars
	var mat_reactor_glow := _emissive(Color(0.15, 1.0, 0.35), 0.9)
	_cyl(core, 1.0, 3.5, mat_metal, Vector3.ZERO, true, 20)
	_cyl(core + Vector3(0, 1.8, 0), 1.15, 0.2, mat_frame, Vector3.ZERO, false, 20)
	_cyl(core + Vector3(0, -1.8, 0), 1.15, 0.2, mat_frame, Vector3.ZERO, false, 20)
	for y: float in [-1.1, 0.0, 1.1]:
		_cyl(core + Vector3(0, y, 0), 1.04, 0.16, mat_reactor_glow, Vector3.ZERO, false, 20)
	for k in 12:
		var ang := TAU * k / 12.0
		frame.box(core + Vector3(cos(ang), 0, sin(ang)) * 1.55, Vector3(0.08, 3.9, 0.08))
	frame.ring(core + Vector3(0, 1.95, 0), Vector3.UP, 1.5, 1.65, 0.1, 12, 1.0)
	frame.ring(core + Vector3(0, -1.95, 0), Vector3.UP, 1.5, 1.65, 0.1, 12, 1.0)
	area.g("hazard").ring(core + Vector3(0, -H * 0.5 + 0.006, 0), Vector3.UP, 1.7, 1.95, 0.005, 12, 1.0)
	_box_collider(core, Vector3(3.2, 4.0, 3.2))
	# coolant loops: pipes from the core top out toward the walls
	for k in 4:
		var ang := TAU * k / 4.0 + PI * 0.25
		var dirv := Vector3(cos(ang), 0, sin(ang))
		var a := core + Vector3(0, 1.75, 0) + dirv * 1.0
		var b := a + Vector3(0, 0.15, 0)
		pipe.pipe(a, b, 0.08)
		pipe.pipe(b, b + dirv * 2.3, 0.08)
	# pump skid against the side wall, with the pump reset terminal above it
	var skid := side - t * 0.55 - d * 1.5 + Vector3(0, -1.35, 0)
	metal.box(skid, _sz(t, 1.1, 1.3, 1.3))
	pipe.pipe(skid + Vector3(0, 0.66, 0), skid + Vector3(0, 1.1, 0), 0.1)
	pipe.pipe(skid + Vector3(0, 1.1, 0), skid + Vector3(0, 1.1, 0) + t * 0.5, 0.1)
	_box_collider(skid, _sz(t, 1.1, 1.3, 1.3))
	_panel("reactor_pump", "Reset coolant pump", ROOM_NAMES[0], side - d * 1.5 + Vector3(0, 0.1, 0), -t)
	# main power: a big breaker cabinet on the back wall with the power panel in it
	metal.box(back - d * 0.35 + Vector3(0, -0.5, 0), _sz(d, 0.7, 2.2, 3.0))
	_box_collider(back - d * 0.35 + Vector3(0, -0.5, 0), _sz(d, 0.7, 2.2, 3.0))
	_panel("power", "MAIN POWER", ROOM_NAMES[0], back - d * 0.72 + Vector3(0, 0.55, 0), -d, true)
	_leds(back - d * 0.72 + t * 0.85 + Vector3(0, -0.6, 0), Vector2(0.3, 0.9), -d, 7)
	_leds(back - d * 0.72 - t * 0.85 + Vector3(0, -0.6, 0), Vector2(0.3, 0.9), -d, 8)
	area.g("hazard").box(back - d * 0.72 + Vector3(0, -1.9, 0), _sz(d, 0.02, 2.2, 0.16))
	_sign("DANGER\nHIGH VOLTAGE", back - d * 0.72 + Vector3(0, 1.45, 0), -d, 30, Color(1.0, 0.75, 0.2), 0.003)
	# control desk facing the core with three screens
	var desk := c - t * 2.3 - d * 1.2 + Vector3(0, -1.4, 0)
	metal.box(desk, _sz(t, 0.9, 2.0, 1.2))
	_box_collider(desk, _sz(t, 0.9, 2.0, 1.2))
	for k in 3:
		_screen(desk + Vector3(0, 0.95, 0) + t * 0.3 + d * (-0.6 + k * 0.6), Vector2(0.5, 0.34), t, 10 + k, -20.0, Color(0.9, 0.35, 0.2) if k == 1 else Color(0.3, 0.9, 1.0))
	_vent(c + d * 1.5 + Vector3(0, 1.5, 0) - t * (ROOM * 0.5 - 0.01), Vector2(1.1, 0.5), t)
	_sign("REACTOR CORE  -  KEEP CLEAR", core + Vector3(0, 1.98, 0) - t * 1.75, -t, 28, Color(1.0, 0.75, 0.2), 0.0028)
	power_led = OmniLight3D.new()
	power_led.position = back - d * 1.0 + Vector3(0, 0.5, 0)
	power_led.light_color = Color(1, 0.15, 0.05)
	power_led.light_energy = 0.0
	power_led.omni_range = 5.0
	add_child(power_led)

func _build_lifesupport(area: AreaGeo, c: Vector3, d: Vector3, t: Vector3, back: Vector3, side: Vector3) -> void:
	var frame := area.g("frame")
	var metal := area.g("metal")
	var pipe := area.g("pipe2")
	_light(c + Vector3(0, 1.4, 0), 0.9, 9.0, Color(0.8, 0.95, 0.9))
	# three tanks along the back wall on a manifold, glass sight-bands showing the liquid
	var mat_liquid := _emissive(Color(0.2, 0.9, 0.8), 0.4)
	for k in 3:
		var p := c + t * (-2.4 + k * 2.4) + d * 2.3 + Vector3(0, -0.3, 0)
		_cyl(p, 0.62, 3.0, mat_metal, Vector3.ZERO, true, 16)
		_cyl(p + Vector3(0, 0.2, 0), 0.65, 0.9, mat_tank, Vector3.ZERO, false, 16)
		_cyl(p + Vector3(0, -0.05, 0), 0.6, 0.35, mat_liquid, Vector3.ZERO, false, 16)
		_cyl(p + Vector3(0, 1.55, 0), 0.5, 0.15, mat_frame, Vector3.ZERO, false, 16)
		_cyl(p + Vector3(0, -1.55, 0), 0.7, 0.15, mat_frame, Vector3.ZERO, false, 16)
		pipe.pipe(p + Vector3(0, 1.62, 0), p + Vector3(0, 1.9, 0), 0.06)
		pipe.pipe(p + Vector3(0, 1.9, 0), p + Vector3(0, 1.9, 0) + d * 1.6, 0.06)
		_sign("O2 %d" % (k + 1), p - d * 0.63 + Vector3(0, 0.95, 0), -d, 30, Color(0.7, 0.95, 0.9), 0.003)
	pipe.pipe(c + t * (-2.4) + d * 2.3 + Vector3(0, 1.9, 0), c + t * 2.4 + d * 2.3 + Vector3(0, 1.9, 0), 0.06)
	# scrubber rack on the side wall under the CO2 vent terminal; filter terminal beside it
	var rack := side - t * 0.45 - d * 1.0 + Vector3(0, -0.9, 0)
	metal.box(rack, _sz(t, 0.9, 2.2, 2.2))
	_box_collider(rack, _sz(t, 0.9, 2.2, 2.2))
	for r in 4:
		for col in 3:
			frame.box(rack - t * 0.46 + d * (-0.7 + col * 0.7) + Vector3(0, -0.85 + r * 0.55, 0), _sz(t, 0.06, 0.55, 0.42))
	_leds(rack - t * 0.5 + Vector3(0, 0.6, 0), Vector2(0.6, 0.35), -t, 12)
	_panel("ls_filter", "Swap O2 scrubber filter", ROOM_NAMES[1], side + d * 2.0 + Vector3(0, 0.3, 0), -t)
	_panel("ls_vent", "Purge CO2 vent", ROOM_NAMES[1], side - d * 1.0 + Vector3(0, 0.9, 0), -t)
	_vent(side - t * 0.01 - d * 2.6 + Vector3(0, 0.6, 0), Vector2(1.2, 0.6), -t)
	_vent(side - t * 0.01 - d * 2.6 + Vector3(0, -0.5, 0), Vector2(1.2, 0.6), -t)
	# hydroponics wall opposite: shelves with plants under magenta grow-lights
	var mat_leaf := _mat(Color(0.25, 0.55, 0.2), 0.9, 0.0)
	var mat_grow := _emissive(Color(1.0, 0.3, 0.9), 1.6)
	var hw := c - t * (ROOM * 0.5 - 0.45)
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	for r in 3:
		var y := -1.3 + r * 0.95
		metal.box(hw + Vector3(0, y, 0), _sz(t, 0.9, 5.2, 0.05))
		metal.box(hw + Vector3(0, y + 0.9, 0), _sz(t, 0.9, 5.2, 0.04))
		var strip := BoxMesh.new()
		strip.size = _sz(t, 0.04, 5.0, 0.03)
		_mesh(strip, hw + t * 0.35 + Vector3(0, y + 0.84, 0), mat_grow)
		for k in 8:
			var px := -2.3 + k * 0.66 + rng.randf_range(-0.1, 0.1)
			var tray := hw + d * px + Vector3(0, y + 0.12, 0)
			metal.box(tray, _sz(t, 0.6, 0.5, 0.2))
			for leaf in 3:
				var lp := tray + Vector3(0, 0.25 + rng.randf() * 0.2, 0) + t * rng.randf_range(-0.2, 0.2) + d * rng.randf_range(-0.18, 0.18)
				var lm := SphereMesh.new()
				lm.radius = rng.randf_range(0.09, 0.16)
				lm.height = lm.radius * 1.6
				lm.radial_segments = 6
				lm.rings = 3
				_mesh(lm, lp, mat_leaf)
	_box_collider(hw, _sz(t, 0.95, 5.3, 3.2))
	_sign("HYDROPONICS  -  DO NOT TOUCH THE LAMPS", hw + t * 0.5 + Vector3(0, 1.75, 0), t, 26, Color(1.0, 0.6, 0.9), 0.0028)
	_prop_box(c - t * 1.2 + Vector3(0.3, 0.4, 0), Vector3(0.7, 0.7, 0.7), mat_crate)
	_prop_box(c - t * 0.5 + Vector3(-0.4, -0.6, 0.8), Vector3(0.5, 0.5, 0.5), mat_crate)

func _build_comms(area: AreaGeo, c: Vector3, d: Vector3, t: Vector3, back: Vector3, side: Vector3) -> void:
	var frame := area.g("frame")
	var metal := area.g("metal")
	_light(c + Vector3(0, 1.4, 0), 0.9, 9.0, Color(0.8, 0.85, 1.0))
	# main console: a long desk under a bank of five screens on the back wall
	var desk := c + d * 2.9 + Vector3(0, -1.4, 0)
	metal.box(desk, _sz(d, 1.2, 4.6, 1.2))
	frame.box(desk + Vector3(0, 0.63, 0), _sz(d, 1.3, 4.7, 0.06))
	_box_collider(desk, _sz(d, 1.2, 4.6, 1.2))
	for k in 5:
		var hue := Color(0.3, 0.9, 1.0) if k % 2 == 0 else Color(0.5, 1.0, 0.6)
		_screen(back - d * 0.08 + t * (-1.8 + k * 0.9) + Vector3(0, 0.55, 0), Vector2(0.82, 0.55), -d, 20 + k, 0.0, hue)
	_screen(desk + Vector3(0, 0.75, 0) - d * 0.2, Vector2(1.2, 0.5), -d, 26, -35.0, Color(1.0, 0.7, 0.3))
	metal.box(desk + Vector3(0, 0.66, 0) - d * 0.35 + t * 0.9, _sz(d, 0.25, 0.7, 0.03))
	_panel("comms_antenna", "Realign antenna", ROOM_NAMES[2], back + t * 2.9 + Vector3(0, 0.2, 0), -d)
	_panel("comms_log", "Upload signal log", ROOM_NAMES[2], side - d * 1.0 + Vector3(0, 0.3, 0), -t)
	# server racks along the side wall with LED faces
	for k in 3:
		var p := side - t * 0.45 + d * (1.0 + k * 0.85) + Vector3(0, -0.6, 0)
		metal.box(p, _sz(t, 0.9, 0.8, 2.6))
		_leds(p - t * 0.46, Vector2(0.6, 2.3), -t, 30 + k)
	_box_collider(side - t * 0.45 + d * 1.85 + Vector3(0, -0.6, 0), _sz(t, 0.9, 2.6, 2.6))
	# antenna drive cabinet under the window, foot restraints on the floor
	var wn := c - t * (ROOM * 0.5 - 0.45)
	metal.box(wn + Vector3(0, -1.5, 0), _sz(t, 0.9, 3.6, 1.0))
	_box_collider(wn + Vector3(0, -1.5, 0), _sz(t, 0.9, 3.6, 1.0))
	area.g("hazard").box(wn + t * 0.46 + Vector3(0, -1.5, 0), _sz(t, 0.02, 3.4, 0.12))
	_leds(wn + t * 0.46 + Vector3(0, -1.2, 0) + d * 1.2, Vector2(0.5, 0.4), t, 33)
	for k in 3:
		frame.box(c + Vector3(0, -H * 0.5 + 0.03, 0) + d * 2.0 + t * (-1.2 + k * 1.2), Vector3(0.3, 0.06, 0.3))
	_vent(c - d * 2.0 + Vector3(0, 1.55, 0) + t * (ROOM * 0.5 - 0.01), Vector2(1.0, 0.5), -t)
	_sign("SIGNAL ROOM", back - d * 0.01 + Vector3(0, 1.45, 0), -d, 36, Color(0.75, 0.85, 1.0), 0.0035)
	_prop_box(c - t * 1.5 - d * 1.5 + Vector3(0, -0.5, 0), Vector3(0.6, 0.6, 0.6), mat_crate)
	_prop_box(c + t * 0.8 - d * 0.5 + Vector3(0, 0.9, 0), Vector3(0.25, 0.35, 0.05), mat_metal)

func _build_crew(area: AreaGeo, c: Vector3, d: Vector3, t: Vector3, back: Vector3, side: Vector3) -> void:
	var frame := area.g("frame")
	var metal := area.g("metal")
	_light(c + Vector3(0, 1.4, 0), 0.85, 9.0, Color(1.0, 0.9, 0.78))
	# three sleep pods against the back wall: metal shell, glass canopy, soft interior light
	var mat_pod_light := _emissive(Color(0.5, 0.75, 1.0), 0.9)
	var mat_canopy := _mat(Color(0.55, 0.75, 0.9, 0.32), 0.05, 0.7)
	mat_canopy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in 3:
		var p := c + t * (-2.5 + k * 2.5) + d * 2.4 + Vector3(0, -1.15, 0)
		var shell := BoxMesh.new()
		shell.size = _sz(d, 2.3, 1.0, 0.7)
		_mesh(shell, p, mat_metal)
		var rim_y := p + Vector3(0, 0.38, 0)
		frame.box(rim_y + t * 0.5, _sz(d, 2.4, 0.1, 0.1))
		frame.box(rim_y - t * 0.5, _sz(d, 2.4, 0.1, 0.1))
		frame.box(rim_y + d * 1.15, _sz(d, 0.1, 1.1, 0.1))
		frame.box(rim_y - d * 1.15, _sz(d, 0.1, 1.1, 0.1))
		var pad := BoxMesh.new()
		pad.size = _sz(d, 2.1, 0.8, 0.1)
		_mesh(pad, p + Vector3(0, 0.36, 0), mat_pod_light)
		var canopy := CapsuleMesh.new()
		canopy.radius = 0.5
		canopy.height = 2.3
		canopy.radial_segments = 12
		canopy.rings = 4
		var rot := Vector3(PI * 0.5, 0, 0) if absf(d.z) > 0.5 else Vector3(0, 0, PI * 0.5)
		_mesh(canopy, p + Vector3(0, 0.55, 0), mat_canopy, rot)
		_box_collider(p + Vector3(0, 0.3, 0), _sz(d, 2.3, 1.1, 1.6))
		_sign("POD %d" % (k + 1), p - d * 1.2 + Vector3(0, 0.15, 0), -d, 26, Color(0.8, 0.9, 1.0), 0.003)
	_panel("crew_pod", "Run sleep-pod diagnostics", ROOM_NAMES[3], back + Vector3(0, 0.75, 0), -d)
	# galley along the side wall: counter, cabinets, hatch doors, the galley terminal
	var counter := side - t * 0.4 - d * 0.8 + Vector3(0, -1.4, 0)
	metal.box(counter, _sz(t, 0.8, 3.6, 1.2))
	frame.box(counter + Vector3(0, 0.62, 0), _sz(t, 0.85, 3.7, 0.05))
	_box_collider(counter, _sz(t, 0.8, 3.6, 1.2))
	for k in 4:
		frame.box(counter - t * 0.41 + d * (-1.35 + k * 0.9) + Vector3(0, -0.1, 0), _sz(t, 0.02, 0.8, 0.9))
		metal.box(counter - t * 0.44 + d * (-1.35 + k * 0.9) + Vector3(0, -0.1, 0), _sz(t, 0.02, 0.05, 0.3))
	metal.box(side - t * 0.25 - d * 0.8 + Vector3(0, 0.9, 0), _sz(t, 0.5, 3.6, 1.0))
	_box_collider(side - t * 0.25 - d * 0.8 + Vector3(0, 0.9, 0), _sz(t, 0.5, 3.6, 1.0))
	_panel("crew_galley", "Check galley circuit", ROOM_NAMES[3], side - d * 1.0 + Vector3(0, -0.15, 0), -t)
	_screen(side - t * 0.51 - d * 2.2 + Vector3(0, 0.9, 0), Vector2(0.5, 0.35), -t, 40, 0.0, Color(1.0, 0.7, 0.3))
	# lockers beside the door, a strapped-down table, personal stuff floating about
	for k in 3:
		var p := c - d * 3.55 + t * (-3.4 + k * 0.66) + Vector3(0, -0.6, 0)
		metal.box(p, _sz(d, 0.5, 0.62, 2.0))
		frame.box(p + d * 0.26, _sz(d, 0.02, 0.02, 1.2))
	_box_collider(c - d * 3.55 + t * (-2.74) + Vector3(0, -0.6, 0), _sz(d, 0.5, 2.0, 2.0))
	var table := c - t * 1.4 + Vector3(0, -1.2, 0)
	metal.box(table, Vector3(0.12, 1.4, 0.12))
	frame.box(table + Vector3(0, 0.72, 0), Vector3(1.3, 0.06, 0.9))
	_box_collider(table + Vector3(0, 0.3, 0), Vector3(1.3, 1.6, 0.9))
	_vent(c - d * 2.0 + Vector3(0, 1.55, 0) - t * (ROOM * 0.5 - 0.01), Vector2(0.9, 0.45), t)
	_sign("CREW QUARTERS  -  QUIET HOURS 22:00 - 06:00", back - d * 0.01 + Vector3(0, 1.5, 0), -d, 26, Color(1.0, 0.9, 0.75), 0.0032)
	_prop_box(c - t * 1.0 + Vector3(0.2, 0.3, -0.3), Vector3(0.45, 0.45, 0.45), mat_crate)
	_prop_box(c - t * 0.2 + Vector3(-0.5, 0.9, 0.4), Vector3(0.3, 0.6, 0.3), mat_crate)
	_prop_box(table + Vector3(0.2, 1.1, 0.1), Vector3(0.2, 0.28, 0.03), mat_metal)
	_prop_box(c + t * 1.2 - d * 1.5 + Vector3(0, 0.6, 0), Vector3(0.12, 0.12, 0.3), mat_pipe2)

# ---------------------------------------------------------------- runtime
func _process(delta: float) -> void:
	_t += delta
	for i in props.size():
		var p := props[i]
		p.rotation += prop_spin[i] * delta
		p.position += prop_vel[i] * delta
		prop_vel[i] = prop_vel[i].lerp(Vector3.ZERO, 0.4 * delta)
		# gentle bob so nothing feels bolted down
		p.position.y += sin(_t * 0.5 + float(i)) * 0.03 * delta
	if power_led and not Game.power_on:
		power_led.light_energy = 1.2 if fmod(_t, 1.2) < 0.15 else 0.05
	if planet:
		planet.rotate_y(delta * 0.006)
		clouds.rotate_y(delta * 0.009)

func set_power(on: bool) -> void:
	for l in lights:
		l.visible = on
	for m in emissive_mats:
		m.emission_enabled = on
	for m in emergency_mats:
		m.emission_enabled = not on
	for m in screen_mats:
		m.albedo_color = Color(1, 1, 1) * 1.1 if on else Color(0.04, 0.04, 0.05)
	for e in emergency_lights:
		e.visible = not on
	if power_led:
		power_led.light_energy = 0.0
	for id in interactables:
		var it: Interactable = interactables[id]
		it.set_label_visible(on)
		if it.is_power:
			it.set_active(not on)
		else:
			it._refresh()

func _on_day_started(_day: int) -> void:
	var ids := []
	for t in Game.tasks:
		ids.append(t["id"])
	for id in interactables:
		var it: Interactable = interactables[id]
		if it.is_power:
			continue
		it.set_active(id in ids)

func _on_task_completed(id: String) -> void:
	Game.on_task_completed(id)

## Nudge every prop (paranormal "something moved").
func shove_props(strength := 0.6) -> void:
	for i in props.size():
		prop_vel[i] += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * strength
		prop_spin[i] += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.8

func random_light() -> Light3D:
	return lights.pick_random()

# ---------------------------------------------------------------- navigation helpers
func room_center(i: int) -> Vector3:
	return ARMS[i] * (HUB * 0.5 + ARM + ROOM * 0.5)

## -1 = hub, else arm index 0..3.
func arm_of(p: Vector3) -> int:
	if absf(p.x) < HUB * 0.5 and absf(p.z) < HUB * 0.5:
		return -1
	if absf(p.x) > absf(p.z):
		return 0 if p.x > 0 else 1
	return 2 if p.z < 0 else 3

func arm_dist(p: Vector3, arm: int) -> float:
	return p.dot(ARMS[arm])

## Next point to walk toward along the plus-shaped station graph.
func next_waypoint(from: Vector3, to: Vector3) -> Vector3:
	var a := arm_of(from)
	var b := arm_of(to)
	var room_edge := HUB * 0.5 + ARM
	if a == b:
		if a == -1:
			return to
		var in_room_a := arm_dist(from, a) > room_edge
		var in_room_b := arm_dist(to, b) > room_edge
		if in_room_a == in_room_b:
			return to
		return ARMS[a] * room_edge
	if a == -1:
		return ARMS[b] * (HUB * 0.5 + 0.8)
	if arm_dist(from, a) > room_edge:
		return ARMS[a] * (room_edge - 0.8)
	return ARMS[a] * (HUB * 0.5 - 0.8)

## True when nothing solid (walls, layer 1) is between two points.
func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# ---------------------------------------------------------------- API shared with the procedural station
func regenerate(_seed: int) -> void:
	pass

func task_pool() -> Array:
	return Game.TASK_POOL

func start_point() -> Vector3:
	return Vector3(0, 0.4, 0)

func wake_point() -> Vector3:
	return room_center(3) + Vector3(0, 0.3, 0)

func stalker_spawn_point() -> Vector3:
	return room_center(1 + randi() % 2)

func random_point() -> Vector3:
	return room_center(randi() % 4)

## [point, tangent] pairs where a silhouette can cross a doorway.
func crossing_spots() -> Array:
	var out := []
	for i in 4:
		var d: Vector3 = ARMS[i]
		var t := Vector3(-d.z, 0, d.x)
		for dist: float in [HUB * 0.5 - 0.9, HUB * 0.5 + ARM + 0.9]:
			out.append([d * dist + Vector3(0, 0.1, 0), t])
	return out

## Places far down a corridor where a watcher can stand.
func watcher_spots() -> Array:
	var out := []
	for i in 4:
		var d: Vector3 = ARMS[i]
		for dist: float in [HUB * 0.5 + ARM * 0.5, HUB * 0.5 + ARM - 1.0]:
			out.append(d * dist)
	return out

func layout_label() -> String:
	return "CLASSIC"

## Review viewpoints for main.gd's photo mode: [name, eye, target].
func viewpoints() -> Array:
	var R := HUB * 0.5 + ARM + ROOM * 0.5
	var D := HUB * 0.5 + ARM
	return [
		["hub_to_reactor", Vector3(-1.0, 0.3, 0.3), Vector3(20, 0, 0)],
		["hub_skylight", Vector3(0, -0.6, 0.8), Vector3(0.5, 6, -0.4)],
		["corridor", Vector3(HUB * 0.5 + 1.2, 0.05, 0), Vector3(30, 0, 0)],
		["reactor_room", Vector3(D + 0.7, 0.3, -0.4), Vector3(R + 1.5, -0.3, 1.5)],
		["lifesupport", Vector3(-D - 0.7, 0.3, 0.3), Vector3(-R - 2, -0.2, -0.5)],
		["comms", Vector3(0.3, 0.3, -D - 0.7), Vector3(-0.5, -0.2, -R - 3)],
		["crew", Vector3(0.2, 0.3, D + 0.7), Vector3(-0.5, -0.4, R + 3)],
	]
