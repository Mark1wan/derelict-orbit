shader_type sky;
// Kestrel-9's sky: the stars, the sun, and the Earth filling most of one half of the view the way it
// does from low orbit. The Earth is lit by the sun - a day side, a night side of city lights, ocean
// glint, a blue atmosphere along the limb that turns orange where the sun is rising or setting
// through it. Everything is infinitely far away, so none of it can intersect the station.
// Orbit (scripts/orbit.gd) sets the directions every frame. Textures: tools/bake_sky.gd.

uniform sampler2D earth_day : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_night : filter_linear_mipmap, repeat_enable;   // population density
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;        // R grain, G towns, B cloud wisps
uniform sampler2D stars : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 earth_dir = vec3(0.0, -1.0, 0.0);   // unit, from the station toward the Earth's centre
uniform float earth_sin = 0.9;                   // sine of the Earth's angular radius
uniform vec3 sun_dir = vec3(0.0, 0.34, -0.94);    // unit, from the station toward the sun
uniform mat3 earth_basis = mat3(1.0);             // world -> Earth-fixed frame: tilt and spin
uniform float sun_visible : hint_range(0.0, 1.0) = 1.0;
uniform float star_gain = 0.85;

const float TAU_ = 6.28318531;
const float PI_ = 3.14159265;
const float SUN_R = 0.0093;     // angular radius, radians - twice the real sun, so it reads in VR
const float ATMO = 1.016;       // atmosphere shell, in Earth radii

vec2 equirect(vec3 n) {
	return vec2(atan(n.x, n.z) / TAU_ + 0.5, acos(clamp(n.y, -1.0, 1.0)) / PI_);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	// the Earth as a unit sphere at distance D, so that 1 / D is the sine of its angular radius
	float D = 1.0 / earth_sin;
	vec3 C = earth_dir * D;
	float b = dot(d, C);
	float h = sqrt(max(D * D - b * b, 0.0));   // how close this view ray passes to the centre
	float sd = dot(d, sun_dir);
	vec3 col;

	if (b > 0.0 && h < 1.0) {
		float t = b - sqrt(1.0 - h * h);
		vec3 N = normalize(d * t - C);
		vec2 uv = equirect(earth_basis * N);
		vec3 day = texture(earth_day, uv).rgb;
		float pop = texture(earth_night, uv).r;
		// the ground below is magnified far past the texture: tile detail over it at two scales
		vec2 duv = uv * vec2(40.0, 20.0);
		vec3 dt = texture(detail, duv).rgb;
		vec3 dt2 = texture(detail, duv * 5.3 + vec2(0.37, 0.11)).rgb;
		float cloud = smoothstep(0.45, 0.85, min(day.r, min(day.g, day.b)));
		day *= mix(mix(0.8, 1.2, mix(dt.r, dt2.r, 0.5)), 0.7 + 0.45 * mix(dt.b, dt2.b, 0.4), cloud);
		float l = dot(N, sun_dir);
		float dayf = smoothstep(-0.06, 0.18, l);
		col = day * (0.015 + 1.2 * max(l, 0.0)) * dayf;
		vec3 towns = vec3(1.0, 0.72, 0.38) * pop * (dt.g * 0.7 + dt2.g * 0.6) * 2.2;
		col += towns * (1.0 - smoothstep(-0.12, 0.04, l));
		// sun glint on open water
		float water = clamp((day.b - day.r) * 4.0, 0.0, 1.0);
		col += vec3(1.0, 0.92, 0.78) * pow(max(dot(reflect(d, N), sun_dir), 0.0), 80.0) * water * dayf * 0.9;
		// looking through more air near the edge of the disc
		float rim = pow(1.0 - clamp(dot(N, -d), 0.0, 1.0), 3.0);
		col += vec3(0.25, 0.5, 1.0) * rim * smoothstep(-0.25, 0.35, l) * 0.8;
		col += vec3(1.0, 0.4, 0.12) * rim * (1.0 - smoothstep(0.0, 0.25, abs(l))) * 0.6;
	} else {
		col = texture(stars, equirect(d)).rgb * star_gain;
		// the sun's disc is cut by the limb geometrically; its glare fades as the Earth covers it
		float disc = smoothstep(cos(SUN_R * 1.2), cos(SUN_R), sd);
		col = mix(col, vec3(5.0, 4.8, 4.4), disc);
		col += vec3(1.0, 0.92, 0.8) * (pow(max(sd, 0.0), 2000.0) * 2.0 + pow(max(sd, 0.0), 80.0) * 0.12) * sun_visible;
		if (b > 0.0 && h < ATMO) {
			vec3 limb = normalize(d * b - C);
			float lit = dot(limb, sun_dir);
			float thick = 1.0 - smoothstep(1.0, ATMO, h);
			vec3 blue = vec3(0.28, 0.55, 1.0) * smoothstep(-0.2, 0.3, lit);
			vec3 dawn = vec3(1.0, 0.42, 0.12) * (1.0 - smoothstep(0.0, 0.3, abs(lit))) * (0.3 + 3.0 * pow(max(sd, 0.0), 12.0));
			col += (blue + dawn) * thick * thick * 1.4;
		}
	}
	COLOR = col;
}
