class_name StationTex
extends RefCounted
## Procedural textures for Kestrel-9. Everything is generated at start-up from noise and
## simple drawing so the project still ships with zero third-party assets.
## Each function returns a Dictionary {albedo: ImageTexture, normal: ImageTexture} or a bare texture.

static var _cache := {}

static func _noise(seed_: int, freq: float, w: int, h: int, octaves := 3) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var img := n.get_image(w, h, false, false, true)
	img.convert(Image.FORMAT_RGB8)
	return img

static func _tex(img: Image, mipmaps := true) -> ImageTexture:
	if mipmaps:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _normal_from(hgt: Image, scale := 4.0) -> ImageTexture:
	var n := hgt.duplicate() as Image
	n.bump_map_to_normal_map(scale)
	return _tex(n)

## Draw a filled rectangle with clipping (Image.fill_rect asserts on out-of-range rects).
static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)

static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var px := cx + x
				var py := cy + y
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, c)

# ---------------------------------------------------------------- wall / hull panels
## Riveted hull plating: 2x2 plates per tile, grooves between, rivets in the corners, wear noise.
static func panel(size := 256, tint := Color(0.62, 0.65, 0.70)) -> Dictionary:
	var key := "panel_%d_%s" % [size, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var grain := _noise(11, 0.06, size, size, 4)
	var wear := _noise(12, 0.015, size, size, 2)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var g := grain.get_pixel(x, y).r
			var w := wear.get_pixel(x, y).r
			var v := 0.82 + (g - 0.5) * 0.22 + (w - 0.5) * 0.28
			img.set_pixel(x, y, Color(tint.r * v, tint.g * v, tint.b * v))
			var hv := 0.5 + (g - 0.5) * 0.06
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	var half := size / 2
	var groove := Color(0.16, 0.17, 0.19)
	var gw := maxi(3, size / 64)
	for k in [0, half]:
		_rect(img, k, 0, gw, size, groove)
		_rect(img, 0, k, size, gw, groove)
		_rect(hgt, k, 0, gw, size, Color(0.1, 0.1, 0.1))
		_rect(hgt, 0, k, size, gw, Color(0.1, 0.1, 0.1))
		# bevel: slightly lighter edge next to the groove
		_rect(img, k + gw, 0, 1, size, Color(tint.r * 1.05, tint.g * 1.05, tint.b * 1.05))
		_rect(img, 0, k + gw, size, 1, Color(tint.r * 1.05, tint.g * 1.05, tint.b * 1.05))
	# rivets inset from each plate corner
	var inset := size / 16
	var rr := maxi(2, size / 96)
	for px in [inset, half - inset, half + inset, size - inset]:
		for py in [inset, half - inset, half + inset, size - inset]:
			_disc(img, px, py, rr, Color(0.3, 0.31, 0.34))
			_disc(img, px, py, rr - 1, Color(0.48, 0.5, 0.54))
			_disc(hgt, px, py, rr, Color(0.9, 0.9, 0.9))
	# a few scratches
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var sx := rng.randi_range(0, size - 1)
		var sy := rng.randi_range(0, size - 1)
		var len := rng.randi_range(size / 12, size / 4)
		var dx := rng.randf_range(-1, 1)
		var dy := rng.randf_range(-1, 1)
		for s in len:
			var px := int(sx + dx * s) % size
			var py := int(sy + dy * s) % size
			if px < 0: px += size
			if py < 0: py += size
			var c := img.get_pixel(px, py)
			img.set_pixel(px, py, c * 0.7)
	var out := {"albedo": _tex(img), "normal": _normal_from(hgt, 3.0)}
	_cache[key] = out
	return out

## Floor grating: a lattice of bars over a dark void.
static func grate(size := 128) -> Dictionary:
	if _cache.has("grate"):
		return _cache["grate"]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.06, 0.065, 0.075))
	hgt.fill(Color(0.1, 0.1, 0.1))
	var cell := size / 4
	var bar := maxi(3, size / 20)
	var grain := _noise(21, 0.12, size, size, 2)
	for k in 4:
		var p := k * cell
		_rect(img, p, 0, bar, size, Color(0.42, 0.44, 0.47))
		_rect(img, 0, p, size, bar, Color(0.42, 0.44, 0.47))
		_rect(hgt, p, 0, bar, size, Color(0.85, 0.85, 0.85))
		_rect(hgt, 0, p, size, bar, Color(0.85, 0.85, 0.85))
		# highlight on one edge of each bar
		_rect(img, p, 0, 1, size, Color(0.6, 0.62, 0.66))
		_rect(img, 0, p, size, 1, Color(0.6, 0.62, 0.66))
	for y in size:
		for x in size:
			var c := img.get_pixel(x, y)
			if c.r > 0.2:
				var g := grain.get_pixel(x, y).r
				img.set_pixel(x, y, c * (0.85 + g * 0.3))
	var out := {"albedo": _tex(img), "normal": _normal_from(hgt, 5.0)}
	_cache["grate"] = out
	return out

## Yellow / black diagonal warning stripes.
static func hazard(size := 64) -> ImageTexture:
	if _cache.has("hazard"):
		return _cache["hazard"]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var period := size / 2
	for y in size:
		for x in size:
			var k := int((x + y) / float(period) * 2.0) % 2
			img.set_pixel(x, y, Color(0.95, 0.75, 0.12) if k == 0 else Color(0.08, 0.08, 0.08))
	var t := _tex(img)
	_cache["hazard"] = t
	return t

## Dark slatted vent grille.
static func vent(size := 64) -> ImageTexture:
	if _cache.has("vent"):
		return _cache["vent"]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.06))
	var slat := size / 8
	for k in 8:
		_rect(img, 0, k * slat, size, slat / 2, Color(0.28, 0.29, 0.32))
		_rect(img, 0, k * slat, size, 1, Color(0.4, 0.42, 0.45))
	_rect(img, 0, 0, 2, size, Color(0.3, 0.31, 0.34))
	_rect(img, size - 2, 0, 2, size, Color(0.3, 0.31, 0.34))
	var t := _tex(img)
	_cache["vent"] = t
	return t

## A console screen full of scrolling telemetry: header bar, columns of "text", a graph.
static func screen(seed_ := 1, w := 128, h := 80, hue := Color(0.3, 0.9, 1.0)) -> ImageTexture:
	var key := "screen_%d" % seed_
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(hue * 0.08)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 977 + 13
	_rect(img, 0, 0, w, 6, hue * 0.7)
	_rect(img, 2, 2, rng.randi_range(20, 50), 2, hue * 0.1)
	var y := 10
	while y < h - 12:
		var x := 4
		while x < w - 8:
			var len := rng.randi_range(4, 18)
			if rng.randf() < 0.75:
				var c := hue * rng.randf_range(0.35, 0.9)
				if rng.randf() < 0.08:
					c = Color(1.0, 0.55, 0.15)
				_rect(img, x, y, len, 2, c)
			x += len + 4
		y += 5
	# a little graph along the bottom
	var prev := h - 4
	for x in range(4, w - 4):
		var v := h - 4 - int(abs(sin(x * 0.15 + seed_) * 7.0 + rng.randf() * 2.0))
		_rect(img, x, mini(v, prev), 1, absi(v - prev) + 1, hue)
		prev = v
	# scanlines
	for yy in range(0, h, 2):
		for xx in w:
			img.set_pixel(xx, yy, img.get_pixel(xx, yy) * 0.8)
	var t := _tex(img)
	_cache[key] = t
	return t

## Rows of tiny status LEDs for server racks.
static func leds(seed_ := 1, w := 64, h := 128) -> ImageTexture:
	var key := "leds_%d" % seed_
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.02, 0.02, 0.025))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 31 + 5
	var y := 4
	while y < h - 4:
		_rect(img, 2, y - 2, w - 4, 1, Color(0.12, 0.12, 0.14))
		var x := 6
		while x < w - 6:
			var r := rng.randf()
			var c := Color(0.1, 0.8, 0.3) if r < 0.6 else (Color(1.0, 0.6, 0.1) if r < 0.85 else (Color(1.0, 0.1, 0.1) if r < 0.92 else Color(0.05, 0.05, 0.05)))
			_rect(img, x, y, 2, 2, c)
			x += 5
		y += 9
	var t := _tex(img)
	_cache[key] = t
	return t

# ---------------------------------------------------------------- outside
## Equirectangular starfield for the sky sphere.
static func stars(w := 1024, h := 512) -> ImageTexture:
	if _cache.has("stars"):
		return _cache["stars"]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.004, 0.005, 0.01))
	# faint galactic band
	var band := _noise(31, 0.01, w, h, 3)
	for y in h:
		var fy := (float(y) / h - 0.5) * 2.0
		for x in w:
			var fx := float(x) / w
			var center := sin(fx * TAU) * 0.35
			var d := absf(fy - center)
			if d < 0.35:
				var n := band.get_pixel(x, y).r
				var a := (0.35 - d) / 0.35
				var v := a * a * n * 0.14
				img.set_pixel(x, y, Color(0.004 + v * 0.8, 0.005 + v * 0.85, 0.01 + v))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 6500:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		var b := rng.randf()
		b = b * b * b
		var c := Color(0.55 + b * 0.45, 0.55 + b * 0.45, 0.65 + b * 0.35)
		if rng.randf() < 0.12:
			c = Color(1.0, 0.75 + b * 0.2, 0.5 + b * 0.3)
		elif rng.randf() < 0.1:
			c = Color(0.6 + b * 0.2, 0.75 + b * 0.2, 1.0)
		img.set_pixel(x, y, c * (0.35 + b * 0.65))
		if b > 0.55:
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var px := (x + o.x + w) % w
				var py := clampi(y + o.y, 0, h - 1)
				img.set_pixel(px, py, c * 0.4)
	var t := _tex(img, false)
	_cache["stars"] = t
	return t

## A blue planet with continents, ice caps and a cloud layer. Equirectangular.
static func planet(w := 512, h := 256) -> ImageTexture:
	if _cache.has("planet"):
		return _cache["planet"]
	var land := _noise(51, 0.012, w, h, 5)
	var detail := _noise(52, 0.05, w, h, 3)
	var cloud := _noise(53, 0.02, w, h, 4)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var lat := absf(float(y) / h - 0.5) * 2.0    # 0 equator .. 1 pole
		for x in w:
			var l := land.get_pixel(x, y).r
			var d := detail.get_pixel(x, y).r
			var c := Color(0.03, 0.12, 0.38).lerp(Color(0.05, 0.22, 0.5), d)     # ocean
			if l > 0.56:
				var k := clampf((l - 0.56) / 0.2, 0.0, 1.0)
				var green := Color(0.16, 0.36, 0.12).lerp(Color(0.45, 0.4, 0.22), d)
				c = Color(0.55, 0.5, 0.32).lerp(green, k)   # beach -> land
				if lat > 0.45:
					c = c.lerp(Color(0.85, 0.85, 0.85), clampf((lat - 0.45) * 3.0, 0.0, 1.0))
			elif l > 0.52:
				c = c.lerp(Color(0.1, 0.4, 0.55), (l - 0.52) / 0.04)   # shallows
			if lat > 0.8:
				c = c.lerp(Color(0.92, 0.95, 1.0), clampf((lat - 0.8) * 4.0 + d * 0.3, 0.0, 1.0))
			var cl := cloud.get_pixel(x, y).r
			if cl > 0.55:
				c = c.lerp(Color(0.97, 0.97, 1.0), clampf((cl - 0.55) * 3.2, 0.0, 0.95))
			img.set_pixel(x, y, c)
	var t := _tex(img)
	_cache["planet"] = t
	return t

## Solar array: dark blue cells with a bright grid.
static func solar(size := 128) -> ImageTexture:
	if _cache.has("solar"):
		return _cache["solar"]
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.08, 0.2))
	var cell := size / 8
	for k in 9:
		_rect(img, k * cell, 0, 1, size, Color(0.55, 0.6, 0.7))
		_rect(img, 0, k * cell, size, 1, Color(0.55, 0.6, 0.7))
	var n := _noise(61, 0.1, size, size, 2)
	for y in size:
		for x in size:
			var c := img.get_pixel(x, y)
			if c.r < 0.3:
				img.set_pixel(x, y, c * (0.8 + n.get_pixel(x, y).r * 0.5))
	var t := _tex(img)
	_cache["solar"] = t
	return t
