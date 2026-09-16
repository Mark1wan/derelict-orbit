class_name Ps1
extends RefCounted
## Retro mode: the station drawn the way a 1996 console drew, which is also the way a Quest 3
## browser can draw it at 72 Hz.
##
## Every trick here is period-correct *and* cheap, which is not a coincidence - the look came out
## of the same constraints a standalone headset has:
##
##   vertex lighting   the lamps are worked out once per corner and smeared across the triangle
##                     (Gouraud), so a corridor lit by four lights costs four sums per vertex
##                     instead of four per pixel. On a tiler this is the single biggest win.
##   vertex snapping   no sub-pixel precision: vertices land on a coarse grid, which is where the
##                     wobble of a PS1 scene comes from. Free - it happens in the vertex shader.
##   affine mapping    no perspective correction on texture coordinates, so textures swim across
##                     big triangles. Free, and the thing that most says "this is not modern".
##   nearest, no mips  point-sampled low-resolution textures: less bandwidth, less memory, and the
##                     chunky pixels are the point.
##   no normal maps    a second texture read and a tangent per vertex, for detail this look does
##                     not want anyway.
##
## Anything that has to keep working - the emissive screens the power cuts, the glass, the amber
## floor markers - stays a StandardMaterial3D with per-vertex shading, so Palette.set_power goes on
## driving them exactly as before. This shader is for the surfaces that never change.

const SNAP := 200.0          ## vertices land on a grid this many steps across the view
const SNAP_XR := 160.0       ## a headset is closer to the eye: coarser reads as deliberate

## One shader for everything static. Godot applies the environment's fog to it for free, so the
## corridors keep their depth.
const CODE := """
shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D tex : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec4 emission_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float snap = 200.0;
uniform float affine : hint_range(0.0, 1.0) = 1.0;
uniform float vertex_tint : hint_range(0.0, 1.0) = 1.0;
uniform float atlas : hint_range(0.0, 1.0) = 0.0;   // texture page: UV2 picks the quarter
uniform float gain = 1.0;  // what a metal lost when its specular highlight went away

varying vec3 uvw;          // uv * w and w: divided again in the fragment, that is affine mapping
varying vec2 uv_plain;     // the same coordinate the modern way, for affine = 0
varying vec2 page;         // which quarter of the texture page this surface draws from

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	page = UV2;
	vec2 uv = UV * uv_scale;
	uv_plain = uv;
	if (clip.w > 0.0) {
		// the console had no sub-pixel precision: snap to a grid of whole screen steps
		vec2 grid = vec2(snap, snap * 0.75);
		vec2 ndc = clip.xy / clip.w;
		clip.xy = floor(ndc * grid + 0.5) / grid * clip.w;
		POSITION = clip;
		uvw = vec3(uv * clip.w, clip.w);
	} else {
		uvw = vec3(uv, 1.0);
	}
}

void fragment() {
	// hardware interpolates uv*w and w perspective-correctly; dividing one by the other gives
	// back a plain linear walk across the triangle, which is the swim you remember
	vec2 base = mix(uv_plain, uvw.xy / uvw.z, affine);
	// the page: wrap inside this surface's quarter, a texel in from the edge so the lower mip
	// levels cannot fetch the quarter next door. fract() puts a seam in the derivative every time
	// the texture repeats, which would pick the smallest mip along that line - so the gradient is
	// handed over from the unwrapped coordinate instead.
	vec2 uv = mix(base, page + 0.004 + fract(base) * 0.492, atlas);
	vec2 grad = mix(vec2(1.0), vec2(0.492), atlas);
	vec4 c = textureGrad(tex, uv, dFdx(base) * grad, dFdy(base) * grad) * albedo;
	// the merged hull carries each piece's tint as a vertex colour, already linear by the time it
	// reaches here - converting it again is what made an early cut of this mode half as bright
	c.rgb *= mix(vec3(1.0), max(COLOR.rgb, vec3(0.0)), vertex_tint);
	ALBEDO = c.rgb * gain;
	EMISSION = emission_col.rgb * emission_energy;
}
"""

const CODE_UNSHADED := """
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D tex : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float snap = 200.0;
uniform float affine : hint_range(0.0, 1.0) = 1.0;
uniform float vertex_tint : hint_range(0.0, 1.0) = 1.0;
uniform float atlas : hint_range(0.0, 1.0) = 0.0;

varying vec3 uvw;
varying vec2 uv_plain;
varying vec2 page;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	page = UV2;
	vec2 uv = UV * uv_scale;
	uv_plain = uv;
	if (clip.w > 0.0) {
		vec2 grid = vec2(snap, snap * 0.75);
		vec2 ndc = clip.xy / clip.w;
		clip.xy = floor(ndc * grid + 0.5) / grid * clip.w;
		POSITION = clip;
		uvw = vec3(uv * clip.w, clip.w);
	} else {
		uvw = vec3(uv, 1.0);
	}
}

void fragment() {
	vec2 base = mix(uv_plain, uvw.xy / uvw.z, affine);
	// the page: wrap inside this surface's quarter, a texel in from the edge so the lower mip
	// levels cannot fetch the quarter next door. fract() puts a seam in the derivative every time
	// the texture repeats, which would pick the smallest mip along that line - so the gradient is
	// handed over from the unwrapped coordinate instead.
	vec2 uv = mix(base, page + 0.004 + fract(base) * 0.492, atlas);
	vec2 grad = mix(vec2(1.0), vec2(0.492), atlas);
	vec4 c = textureGrad(tex, uv, dFdx(base) * grad, dFdy(base) * grad) * albedo;
	c.rgb *= mix(vec3(1.0), max(COLOR.rgb, vec3(0.0)), vertex_tint);
	ALBEDO = c.rgb;
}
"""

static var _shader: Shader
static var _shader_unshaded: Shader

static func shader(unshaded := false) -> Shader:
	if unshaded:
		if _shader_unshaded == null:
			_shader_unshaded = Shader.new()
			_shader_unshaded.code = CODE_UNSHADED
		return _shader_unshaded
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	return _shader

## A static surface: `tex` may be null for a flat colour. `vertex_tint` is for the merged hull
## groups, which carry their piece's colour per vertex.
static func mat(tint: Color, tex: Texture2D = null, uv_scale := 1.0, vertex_tint := false,
		emission := Color(0, 0, 0), emission_energy := 0.0, unshaded := false,
		atlas := false, gain := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(unshaded)
	m.set_shader_parameter("albedo", tint)
	if tex != null:
		m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("uv_scale", Vector2(uv_scale, uv_scale))
	m.set_shader_parameter("vertex_tint", 1.0 if vertex_tint else 0.0)
	m.set_shader_parameter("snap", snap_grid())
	m.set_shader_parameter("affine", 1.0)
	m.set_shader_parameter("atlas", 1.0 if atlas else 0.0)
	if not unshaded:
		m.set_shader_parameter("gain", gain)
	if not unshaded:
		m.set_shader_parameter("emission_col", emission)
		m.set_shader_parameter("emission_energy", emission_energy)
	return m

static func snap_grid() -> float:
	return SNAP_XR if Game.xr else SNAP

## Turn a StandardMaterial3D that has to stay one (the emissives the power drives, glass, screens)
## into its cheapest form: lighting worked out per vertex, no specular highlight, no normal map,
## point-sampled textures.
## Walk a branch of the tree and cheapen every StandardMaterial3D on it: the things built outside
## Palette - the terminals, the tools, the airlock, the suit, the creature that walks at night.
static func cheapen_tree(n: Node) -> void:
	if not Game.retro:
		return
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		cheapen(mi.material_override as StandardMaterial3D)
		for i in mi.get_surface_override_material_count():
			cheapen(mi.get_surface_override_material(i) as StandardMaterial3D)
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				cheapen(mi.mesh.surface_get_material(i) as StandardMaterial3D)

static func cheapen(m: StandardMaterial3D) -> StandardMaterial3D:
	if m == null:
		return m
	if m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.normal_enabled = false
	m.normal_texture = null
	m.uv1_triplanar = false
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m
