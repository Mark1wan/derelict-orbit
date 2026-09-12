extends SceneTree
## Bakes Kestrel-9's sky textures once, into res://sky/:
##   earth_day.png    2048 x 1024  equirectangular Earth: oceans, continents, ice and clouds
##   earth_night.png  2048 x 1024  city lights on land, dimmed under cloud
##   stars.png        2048 x 1024  starfield with a faint galactic band
##   detail.png        512 x 512   tiling detail: R terrain grain, G town specks, B cloud wisps
##
## Why a detail texture: from low orbit the ground straight below is magnified about 13 times more than
## the Earth texture's own resolution, so no single texture stays sharp there. The sky shader tiles
## detail.png over the surface at two scales, and the night map is a smooth population density that
## the town specks are cut out of - city lights stay points of light however close you look.
##
##   godot --headless --path . --script tools/bake_sky.gd
##
## Noise is sampled on the unit sphere, so there is no seam at the date line and no pinching at the
## poles. Fixed seeds: re-running reproduces the same files. The mapping matches sky/orbit_sky.gdshader:
## u = atan(n.x, n.z) / TAU + 0.5, v = acos(n.y) / PI.

const W := 2048
const H := 1024

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sky"))
	var t0 := Time.get_ticks_msec()
	_bake_earth()
	print("[bake_sky] earth in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	t0 = Time.get_ticks_msec()
	_bake_stars()
	print("[bake_sky] stars in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_bake_detail()
	quit()

static func _noise(seed_: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n

static func _byte(f: float) -> int:
	return int(clampf(f, 0.0, 1.0) * 255.0 + 0.5)

func _bake_earth() -> void:
	var land_n := _noise(51, 1.1, 6)
	var detail_n := _noise(52, 5.0, 3)
	var moist_n := _noise(53, 1.6, 3)
	var cloud_n := _noise(54, 1.9, 5)
	var warp_n := _noise(55, 0.9, 2)
	var city_n := _noise(56, 6.0, 2)       # where people live
	var day := PackedByteArray()
	day.resize(W * H * 3)
	var night := PackedByteArray()
	night.resize(W * H * 3)
	var i := 0
	for y in H:
		var theta := (y + 0.5) / H * PI
		var sy := cos(theta)
		var r := sin(theta)
		var lat := absf(sy)                  # sine of the latitude: 0 at the equator, 1 at a pole
		for x in W:
			var lon := ((x + 0.5) / W - 0.5) * TAU
			var p := Vector3(r * sin(lon), sy, r * cos(lon))
			var w := warp_n.get_noise_3dv(p) * 0.35
			var land := land_n.get_noise_3dv(p + Vector3(w, -w, w * 0.5))
			var det := detail_n.get_noise_3dv(p) * 0.5 + 0.5
			var is_land := land > 0.12
			# land: deserts belt the subtropics where it is dry, forest everywhere wetter
			var k := clampf((land - 0.12) / 0.35, 0.0, 1.0)
			var moist := moist_n.get_noise_3dv(p) * 0.5 + 0.5
			var dry := clampf(1.0 - absf(lat - 0.42) * 3.0, 0.0, 1.0) * (1.0 - moist)
			var green := Color(0.10, 0.24, 0.08).lerp(Color(0.21, 0.31, 0.12), det)
			var desert := Color(0.62, 0.50, 0.32).lerp(Color(0.74, 0.62, 0.42), det)
			var lc := green.lerp(desert, clampf(dry * 1.7, 0.0, 1.0))
			lc = lc.lerp(Color(0.36, 0.31, 0.27), clampf((k - 0.55) * 2.0, 0.0, 0.8))       # highlands
			lc = lc.lerp(Color(0.56, 0.53, 0.41), clampf(1.0 - k / 0.04, 0.0, 1.0) * 0.7)  # beaches
			lc = lc.lerp(Color(0.92, 0.94, 0.97), clampf((lat - 0.85) * 8.0 + (k - 0.85) * 4.0, 0.0, 1.0))
			# sea: shallows to deep water, and sea ice toward the poles
			var depth := clampf((0.12 - land) / 0.4, 0.0, 1.0)
			var oc := Color(0.05, 0.22, 0.36).lerp(Color(0.015, 0.07, 0.20), sqrt(depth))
			oc = oc.lerp(Color(0.02, 0.09, 0.22), det * 0.12)
			oc = oc.lerp(Color(0.9, 0.93, 0.97), clampf((lat - 0.93) * 14.0 + det * 0.3, 0.0, 1.0))
			# a soft shore: blend across the threshold, or the coast is a staircase of texels up close
			var c := oc.lerp(lc, smoothstep(0.105, 0.135, land))
			# clouds: weather systems, a little stretched along the latitudes
			var cl := cloud_n.get_noise_3dv(p * Vector3(1.0, 1.6, 1.0) + Vector3(w, 0.0, -w))
			var cover := clampf((cl + 0.1 * cos(lat * 3.0 * PI) - 0.04) * 2.2, 0.0, 0.92)
			c = c.lerp(Color(0.95, 0.96, 0.98), cover)
			day[i] = _byte(c.r)
			day[i + 1] = _byte(c.g)
			day[i + 2] = _byte(c.b)
			# population density for the night side: the shader cuts town specks out of it
			var lv := 0.0
			if lat < 0.8:
				var region := pow(city_n.get_noise_3dv(p) * 0.5 + 0.5, 3.0) * 2.5
				var coast := 1.0 - clampf((land - 0.12) / 0.08, 0.0, 1.0)
				lv = smoothstep(0.105, 0.135, land) * region * (0.5 + coast) * (1.0 - cover * 0.5)
			night[i] = _byte(lv)
			night[i + 1] = _byte(lv)
			night[i + 2] = _byte(lv)
			i += 3
	Image.create_from_data(W, H, false, Image.FORMAT_RGB8, day).save_png("res://sky/earth_day.png")
	Image.create_from_data(W, H, false, Image.FORMAT_RGB8, night).save_png("res://sky/earth_night.png")

func _bake_stars() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	var axis := Vector3(0.35, 0.8, -0.48).normalized()      # the galactic plane's pole
	var band_n := _noise(61, 3.0, 4)
	for y in H:
		var theta := (y + 0.5) / H * PI
		for x in W:
			var lon := ((x + 0.5) / W - 0.5) * TAU
			var p := Vector3(sin(theta) * sin(lon), cos(theta), sin(theta) * cos(lon))
			var g := absf(p.dot(axis))
			if g < 0.3:
				var v := pow(1.0 - g / 0.3, 2.0) * (band_n.get_noise_3dv(p) * 0.5 + 0.5) * 0.09
				img.set_pixel(x, y, Color(v * 0.8, v * 0.85, v))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var placed := 0
	while placed < 16000:
		var z := rng.randf_range(-1.0, 1.0)
		var t := rng.randf() * TAU
		var rr := sqrt(1.0 - z * z)
		var d := Vector3(rr * cos(t), z, rr * sin(t))
		# a third of the stars crowd into the galactic band
		if placed % 3 == 0 and absf(d.dot(axis)) > 0.22:
			continue
		placed += 1
		var px := clampi(int((atan2(d.x, d.z) / TAU + 0.5) * W), 0, W - 1)
		var py := clampi(int(acos(clampf(d.y, -1.0, 1.0)) / PI * H), 0, H - 1)
		var b := pow(rng.randf(), 4.0)
		var col := Color(0.6 + b * 0.4, 0.6 + b * 0.4, 0.68 + b * 0.32)
		var tint := rng.randf()
		if tint < 0.12:
			col = Color(1.0, 0.78 + b * 0.18, 0.55 + b * 0.3)
		elif tint < 0.22:
			col = Color(0.65 + b * 0.2, 0.78 + b * 0.18, 1.0)
		col = col * (0.25 + b * 0.75)
		img.set_pixel(px, py, col)
		if b > 0.45:
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var qx := (px + o.x + W) % W
				var qy := clampi(py + o.y, 0, H - 1)
				var old := img.get_pixel(qx, qy)
				img.set_pixel(qx, qy, Color(maxf(old.r, col.r * 0.35), maxf(old.g, col.g * 0.35), maxf(old.b, col.b * 0.35)))
	img.save_png("res://sky/stars.png")

func _bake_detail() -> void:
	const S := 512
	var grain := _seamless(81, 0.06, 4, S)
	var wisps := _seamless(82, 0.03, 5, S)
	var clusters := _seamless(83, 0.012, 2, S)
	var towns := PackedFloat32Array()
	towns.resize(S * S)
	var rng := RandomNumberGenerator.new()
	rng.seed = 84
	var placed := 0
	while placed < 1400:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		if rng.randf() > pow(clusters.get_pixel(x, y).r, 2.0):
			continue
		placed += 1
		var r := rng.randf_range(0.6, 1.8)
		var b := rng.randf_range(0.35, 1.0)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var f := b * clampf(1.0 - Vector2(dx, dy).length() / r, 0.0, 1.0)
				var k := ((y + dy + S) % S) * S + (x + dx + S) % S
				towns[k] = maxf(towns[k], f)
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	for y in S:
		for x in S:
			img.set_pixel(x, y, Color(grain.get_pixel(x, y).r, towns[y * S + x], wisps.get_pixel(x, y).r))
	img.save_png("res://sky/detail.png")

static func _seamless(seed_: int, freq: float, octaves: int, size: int) -> Image:
	var n := _noise(seed_, freq, octaves)
	var img := n.get_seamless_image(size, size, false, false, 0.1, true)
	img.convert(Image.FORMAT_RGB8)
	return img

