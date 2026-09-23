class_name CaveTex
extends RefCounted
## Procedural rock for Sowbelly. Same recipe as derelict-orbit's scripts/tex.gd - two noise
## layers at different frequencies, drawn structure on top, and a height image built in
## parallel that `bump_map_to_normal_map` turns into a normal map for free - so the project
## still ships with no third-party assets of any kind.
##
## Everything here is lit by one headlamp and nothing else, which changes what matters. Albedo
## barely reads at all; the normal map is doing almost all the work, because a beam raking
## across rock at a shallow angle is the only thing telling you what shape the passage is.
## The normal scales below are therefore deliberately strong.
##
## Each function returns {albedo: ImageTexture, normal: ImageTexture} and caches on its args.
##
## Sowbelly itself is built out of `limestone` alone, twice: once dry as the fallback, once wet
## as every surface you actually touch. `mud`, `flowstone` and `breakdown` are kept because this
## is a library of rock and the next cave may want a floor that is not the wall - nothing calls
## them today, so nothing pays for them at start-up.

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

static func _disc(img: Image, cx: int, cy: int, r: int, c: Color, blend := 1.0) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var px := posmod(cx + x, img.get_width())
				var py := posmod(cy + y, img.get_height())
				img.set_pixel(px, py, img.get_pixel(px, py).lerp(c, blend))

## Soft-edged dip - a solution pocket, a scallop. Depth falls off toward the rim so the normal
## map reads it as a bowl rather than a punched hole.
static func _dimple(hgt: Image, cx: int, cy: int, r: int, depth: float) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var d2 := x * x + y * y
			if d2 <= r * r:
				var f := 1.0 - sqrt(float(d2)) / float(r)
				var px := posmod(cx + x, hgt.get_width())
				var py := posmod(cy + y, hgt.get_height())
				var v: float = hgt.get_pixel(px, py).r - depth * f * f
				hgt.set_pixel(px, py, Color(v, v, v))

## Wrapping line from (x0,y0) along (dx,dy), used for bedding planes and calcite veins.
static func _streak(img: Image, hgt: Image, x0: int, y0: int, dx: float, dy: float, n: int,
		tint: Color, mul: float, bump: float, width := 1) -> void:
	for s in n:
		for w in range(-width, width + 1):
			var px := posmod(int(x0 + dx * s), img.get_width())
			var py := posmod(int(y0 + dy * s) + w, img.get_height())
			var fade: float = 1.0 - absf(float(w)) / float(width + 1)
			img.set_pixel(px, py, img.get_pixel(px, py).lerp(tint, fade * 0.55) * lerpf(1.0, mul, fade))
			if hgt:
				var v: float = clampf(hgt.get_pixel(px, py).r + bump * fade, 0.0, 1.0)
				hgt.set_pixel(px, py, Color(v, v, v))

# ---------------------------------------------------------------- limestone

## Bedded limestone: the default wall of the whole cave. Coarse noise for the bedding, fine
## noise for grain, horizontal bedding planes cut across it, solution pockets dissolved into
## it, and calcite veins drawn over the top. The bedding planes are the important part - they
## are what tells you which way is up when the passage has rolled and your only light is
## strapped to your head.
static func limestone(size := 256, tint := Color(0.50, 0.47, 0.42)) -> Dictionary:
	var key := "limestone_%d_%s" % [size, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var bed := _noise(31, 0.011, size, size, 2)
	var grain := _noise(32, 0.075, size, size, 4)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var b := bed.get_pixel(x, y).r
			var g := grain.get_pixel(x, y).r
			var v := 0.74 + (b - 0.5) * 0.40 + (g - 0.5) * 0.24
			img.set_pixel(x, y, Color(tint.r * v, tint.g * v, tint.b * v))
			var hv := 0.52 + (b - 0.5) * 0.30 + (g - 0.5) * 0.18
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	var rng := RandomNumberGenerator.new()
	rng.seed = 104
	# Bedding planes: near-horizontal partings where one layer of rock meets the next.
	for i in 5:
		var y0 := rng.randi_range(0, size - 1)
		var slope := rng.randf_range(-0.07, 0.07)
		_streak(img, hgt, 0, y0, 1.0, slope, size, Color(0.22, 0.20, 0.18), 0.62, -0.20,
			maxi(2, size / 110))
	# Solution pockets - water taking the rock away wherever it found it soft.
	for i in 26:
		var r := rng.randi_range(size / 40, size / 13)
		var cx := rng.randi_range(0, size - 1)
		var cy := rng.randi_range(0, size - 1)
		_dimple(hgt, cx, cy, r, rng.randf_range(0.10, 0.26))
		_disc(img, cx, cy, r, Color(tint.r * 0.62, tint.g * 0.60, tint.b * 0.58), 0.35)
	# Joints: thin cracks running across the bedding rather than along it. Dark and RECESSED,
	# not bright and raised. A pale line standing proud of the rock reads as something painted
	# on it, which is what these used to look like; a dark line sitting in a groove reads as a
	# crack, and down here the normal map is doing most of the work anyway.
	for i in 7:
		var sx := rng.randi_range(0, size - 1)
		var sy := rng.randi_range(0, size - 1)
		var ang := rng.randf_range(-1.4, 1.4) + PI * 0.5
		_streak(img, hgt, sx, sy, cos(ang), sin(ang), rng.randi_range(size / 3, size),
			Color(0.04, 0.04, 0.05), 0.40, -0.18, 1)
	var out := {"albedo": _tex(img), "normal": _normal_from(hgt, 6.0)}
	_cache[key] = out
	return out

# ---------------------------------------------------------------- mud

## Wet clay - the stuff that gives a cave like this its name. Almost featureless, because it
## is smeared flat by everyone who has ever crawled through it; what structure there is comes
## from drag marks and the odd pebble pressed into the surface. Low normal scale on purpose:
## mud under a headlamp is a dull sheet, and that contrast is what makes the limestone read.
static func mud(size := 192, tint := Color(0.30, 0.24, 0.18)) -> Dictionary:
	var key := "mud_%d_%s" % [size, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var slick := _noise(41, 0.018, size, size, 2)
	var grit := _noise(42, 0.11, size, size, 3)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var s := slick.get_pixel(x, y).r
			var g := grit.get_pixel(x, y).r
			var v := 0.80 + (s - 0.5) * 0.46 + (g - 0.5) * 0.10
			img.set_pixel(x, y, Color(tint.r * v, tint.g * v, tint.b * v))
			var hv := 0.5 + (s - 0.5) * 0.10 + (g - 0.5) * 0.06
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	# Drag marks: somebody came through here on their belly, not that long ago.
	for i in 9:
		var y0 := rng.randi_range(0, size - 1)
		_streak(img, hgt, 0, y0, 1.0, rng.randf_range(-0.04, 0.04), size,
			Color(tint.r * 1.5, tint.g * 1.45, tint.b * 1.4), 1.12, 0.05, maxi(2, size / 64))
	# Pebbles trodden into the clay.
	for i in 30:
		var r := rng.randi_range(1, maxi(2, size / 70))
		var cx := rng.randi_range(0, size - 1)
		var cy := rng.randi_range(0, size - 1)
		_disc(img, cx, cy, r, Color(0.42, 0.39, 0.35), 0.7)
		_dimple(hgt, cx, cy, r + 1, -0.10)
	var out := {"albedo": _tex(img), "normal": _normal_from(hgt, 2.0)}
	_cache[key] = out
	return out

# ---------------------------------------------------------------- flowstone

## Calcite poured down a wall over a few thousand years: banded, glossy where it is still wet,
## with vertical drip lines. Only the drip lines get the wet sheen - the trick borrowed from
## derelict-orbit's grate(), where the grain only modulates where the drawn structure is.
static func flowstone(size := 192) -> Dictionary:
	if _cache.has("flowstone"):
		return _cache["flowstone"]
	var band := _noise(51, 0.030, size, size, 3)
	var fine := _noise(52, 0.13, size, size, 2)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGB8)
	var wet := Image.create(size, size, false, Image.FORMAT_RGB8)
	wet.fill(Color(0.25, 0.25, 0.25))
	for y in size:
		for x in size:
			# Bands follow the flow, so they stretch along y and ripple along x.
			var b: float = band.get_pixel(x, posmod(y / 3, size)).r
			var f := fine.get_pixel(x, y).r
			var warm: float = 0.62 + b * 0.40
			var c := Color(0.76, 0.66, 0.50).lerp(Color(0.92, 0.88, 0.80), b)
			var v := warm + (f - 0.5) * 0.12
			img.set_pixel(x, y, c * v)
			var hv := 0.5 + (b - 0.5) * 0.34
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Drip lines run straight down, stand proud, and are the only wet part.
	for i in 16:
		var x0 := rng.randi_range(0, size - 1)
		var w := maxi(2, size / 48)
		for y in size:
			for k in range(-w, w + 1):
				var px := posmod(x0 + k, size)
				var fade: float = 1.0 - absf(float(k)) / float(w + 1)
				img.set_pixel(px, y, img.get_pixel(px, y).lerp(Color(0.95, 0.92, 0.86), fade * 0.5))
				var hv: float = clampf(hgt.get_pixel(px, y).r + 0.20 * fade, 0.0, 1.0)
				hgt.set_pixel(px, y, Color(hv, hv, hv))
				var wv: float = 0.25 + 0.70 * fade
				wet.set_pixel(px, y, Color(wv, wv, wv))
	var out := {"albedo": _tex(img), "normal": _normal_from(hgt, 4.5), "rough": _tex(wet)}
	_cache["flowstone"] = out
	return out

# ---------------------------------------------------------------- breakdown

## Collapsed blocks: the floor of any big chamber. Angular facets rather than smooth bedding,
## because this rock broke rather than dissolved.
static func breakdown(size := 256) -> Dictionary:
	if _cache.has("breakdown"):
		return _cache["breakdown"]
	var coarse := _noise(61, 0.022, size, size, 1)
	var chip := _noise(62, 0.09, size, size, 2)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var hgt := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var c := coarse.get_pixel(x, y).r
			var k := chip.get_pixel(x, y).r
			# Quantising the coarse layer turns smooth noise into flat facets with hard edges.
			var facet := floorf(c * 7.0) / 7.0
			var v := 0.58 + facet * 0.42 + (k - 0.5) * 0.20
			img.set_pixel(x, y, Color(0.46 * v, 0.44 * v, 0.41 * v))
			var hv := 0.35 + facet * 0.55 + (k - 0.5) * 0.10
			hgt.set_pixel(x, y, Color(hv, hv, hv))
	var out := {"albedo": _tex(img), "normal": _normal_from(hgt, 7.0)}
	_cache["breakdown"] = out
	return out
