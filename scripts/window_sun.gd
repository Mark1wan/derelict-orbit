class_name WindowSun
extends Node3D
## Sunlight coming in through the station's windows.
##
## Real directional shadows across a whole deck cost too much on a Quest, and without them the sun
## would shine straight through the hull. So every outside window gets its own sunlight instead: a
## spot light aimed along the sun's rays from just outside the glass - the bright patch on the far
## wall - and a faint additive shaft from the glass inwards. A window is lit only when the sun is
## up (Orbit), the window faces it, and nothing of the station stands between the window and the
## sun, so modules shade each other's windows as the sun moves. Only the nearest few lit windows
## get a real light at a time.

const MAX_LIT := 6
const MAX_LIT_LOW := 2        # low graphics (phones)
const NEAR := 24.0            # metres from the player within which a window's light switches on
const OUTSIDE := 8.0          # how far outside the glass each window's light sits: far enough that
                              # its rays are near parallel and the patch keeps the window's shape
const SHAFT_LEN := 7.0
const CHECK_EVERY := 0.4

const SHAFT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.78);
uniform float strength = 0.09;
void fragment() {
	float along = 1.0 - UV.y;
	// a side seen edge-on adds nothing, so looking down the beam does not stack four faces into glare
	ALBEDO = tint * strength * along * sin(UV.x * 3.14159) * abs(dot(NORMAL, VIEW));
}
"""

class Pane:
	var center: Vector3
	var normal: Vector3       # outward, away from the module
	var u: Vector3            # half extents across the glass
	var v: Vector3
	var depth: float          # how far the room behind it goes
	var light: SpotLight3D
	var shaft: MeshInstance3D
	var lit := false
	var built_dir := Vector3.ZERO

var windows: Array = []
var _mat: ShaderMaterial
var _t := 0.0

func _init() -> void:
	name = "WindowSun"
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHAFT_SHADER
	_mat.shader = sh

## A window aperture from Kit.window_apertures(), placed by its piece transform `xf`.
func add_window(xf: Transform3D, ap: Dictionary, depth: float) -> void:
	var p := Pane.new()
	p.center = xf * (ap["center"] as Vector3)
	p.normal = (xf.basis * (ap["normal"] as Vector3)).normalized()
	p.u = xf.basis * (ap["u"] as Vector3)
	p.v = xf.basis * (ap["v"] as Vector3)
	p.depth = depth
	p.light = SpotLight3D.new()
	p.light.light_color = Color(1.0, 0.94, 0.82)
	p.light.shadow_enabled = false
	p.light.spot_attenuation = 0.6
	p.light.visible = false
	add_child(p.light)
	p.shaft = MeshInstance3D.new()
	p.shaft.material_override = _mat
	p.shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.shaft.visible = false
	add_child(p.shaft)
	windows.append(p)

## Does sunlight reach this window, or is part of the station in the way?
func clear_to_sun(p: Pane, s: Vector3) -> bool:
	var from := p.center + p.normal * 0.35
	var q := PhysicsRayQueryParameters3D.create(from, from + s * 60.0, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func refresh_now() -> void:
	_t = 0.0
	_update()

func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = CHECK_EVERY
		_update()

func _update() -> void:
	var orbit: Orbit = Game.orbit
	if orbit == null or windows.is_empty():
		return
	var s := orbit.sun_dir
	var up := orbit.sunlit()
	var player: Player = Game.player
	var eye := player.camera.global_position if player else Vector3.ZERO
	var candidates: Array = []
	for p: Pane in windows:
		p.lit = up and p.normal.dot(s) > 0.1 and clear_to_sun(p, s)
		if p.lit and p.center.distance_to(eye) < NEAR:
			candidates.append(p)
	candidates.sort_custom(func(a: Pane, b: Pane) -> bool: return a.center.distance_squared_to(eye) < b.center.distance_squared_to(eye))
	var on := {}
	for i in mini(MAX_LIT_LOW if Game.low_quality else MAX_LIT, candidates.size()):
		on[candidates[i]] = true
	for p: Pane in windows:
		var show := on.has(p)
		p.light.visible = show
		p.shaft.visible = show
		if show:
			_aim(p, s, orbit.sun_visible)

func _aim(p: Pane, s: Vector3, vis: float) -> void:
	var travel := -s
	var facing := p.normal.dot(s)
	var reach := maxf(p.u.length(), p.v.length())
	p.light.global_position = p.center + s * OUTSIDE
	var up := p.u.normalized()
	if absf(travel.dot(up)) > 0.95:
		up = p.v.normalized()
	p.light.look_at(p.center, up)
	p.light.spot_angle = rad_to_deg(atan(reach / OUTSIDE)) + 2.0
	p.light.spot_range = OUTSIDE + clampf(p.depth / maxf(facing, 0.35), 2.0, 16.0) + 5.0
	p.light.light_energy = 6.0 * vis * clampf(facing * 1.5, 0.3, 1.0)
	if p.built_dir.dot(s) < 0.9997:
		p.built_dir = s
		p.shaft.mesh = _prism(p, travel)

## An open prism from the glass along the sunlight: the aperture swept `SHAFT_LEN` inwards.
func _prism(p: Pane, travel: Vector3) -> ArrayMesh:
	var c := p.center
	var q := [c - p.u - p.v, c + p.u - p.v, c + p.u + p.v, c - p.u + p.v]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = q[i]
		var b: Vector3 = q[(i + 1) % 4]
		var a2 := a + travel * SHAFT_LEN
		var b2 := b + travel * SHAFT_LEN
		for vert: Array in [[a, 0.0, 0.0], [b, 1.0, 0.0], [b2, 1.0, 1.0], [a, 0.0, 0.0], [b2, 1.0, 1.0], [a2, 0.0, 1.0]]:
			st.set_uv(Vector2(vert[1], vert[2]))
			st.add_vertex(vert[0])
	return st.commit()
