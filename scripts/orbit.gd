class_name Orbit
extends Node3D
## Where Kestrel-9 is on its orbit, and so where the sun is.
##
## The Earth hangs below the deck and fills most of that half of the sky, the way it does from low
## orbit. The sun travels one great circle per day: it rises out from behind the Earth's limb as a
## shift begins, crosses overhead, sets as the shift ends, and at night the station is in the
## Earth's shadow - the orbital night is the power failure's darkness. Restoring power brings the
## next sunrise.
##
## sky/orbit_sky.gdshader draws the sky; this node feeds it the directions every frame, drives the
## sunlight on the station's exterior (a DirectionalLight3D limited to EXTERIOR_LAYER, so it can
## never shine through a hull into the corridors) and tells WindowSun whether the sun is up.

const EARTH_DIR := Vector3(0.18, -1.0, -0.22)   # world, toward the Earth's centre
const EARTH_SIN := 0.9           # sine of the Earth's angular radius from the station: ~64 degrees
const SUN_R := 0.0093            # the sun's angular radius, as drawn
const EXTERIOR_LAYER := 4        # render-layer bit (layer 3): the only things the sunlight touches
const SUN_ENERGY := 1.8

# degrees along the orbit: 0 = local noon, 180 = midnight behind the Earth
const DAY_START := -118.0        # a shift begins with the sun just behind the limb: sunrise
const DAY_END := 105.0
const SUNSET := 122.0
const MIDNIGHT := 180.0
const TITLE := -35.0

var earth_dir := Vector3.DOWN
var sun_dir := Vector3.UP        # unit, toward the sun
var angle := TITLE
var sun_visible := 1.0           # 0 while the Earth hides the sun, partial across the limb
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var _h := Vector3.RIGHT          # the orbit plane's horizontal axis
var _spin := 0.0
var _hold := false
var _pushed_dir := Vector3.ZERO
var _pushed_vis := -1.0
var _spin_t := 0.0

func _ready() -> void:
	Game.orbit = self
	earth_dir = EARTH_DIR.normalized()
	var v := Vector3(1.0, 0.0, 0.45)
	_h = (v - earth_dir * v.dot(earth_dir)).normalized()
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = false
	sun.light_cull_mask = EXTERIOR_LAYER
	add_child(sun)
	set_angle(angle)

## Point `env` at the orbital sky.
func attach(env: Environment) -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://sky/orbit_sky.gdshader")
	sky_mat.set_shader_parameter("earth_day", load("res://sky/earth_day.png"))
	sky_mat.set_shader_parameter("earth_night", load("res://sky/earth_night.png"))
	sky_mat.set_shader_parameter("stars", load("res://sky/stars.png"))
	sky_mat.set_shader_parameter("detail", load("res://sky/detail.png"))
	sky_mat.set_shader_parameter("earth_sin", EARTH_SIN)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# the background is drawn per pixel; the radiance map is unused (ambient and reflections are
	# not taken from the sky), so keep it as small as it goes
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_push()

func set_angle(deg: float) -> void:
	angle = wrapf(deg, -180.0, 180.0)
	var a := deg_to_rad(angle)
	sun_dir = (-earth_dir * cos(a) + _h * sin(a)).normalized()
	var sep := acos(clampf(sun_dir.dot(earth_dir), -1.0, 1.0)) - asin(EARTH_SIN)
	sun_visible = smoothstep(-SUN_R, SUN_R, sep)
	_push()

## Freeze the sun at `deg` (photo mode, tests). release() gives it back to the clock.
func hold(deg: float) -> void:
	_hold = true
	set_angle(deg)

func release() -> void:
	_hold = false

func sunlit() -> bool:
	return sun_visible > 0.05

func _target() -> float:
	match Game.phase:
		Game.Phase.DAY:
			return lerpf(DAY_START, DAY_END, clampf(Game.day_time / Game.day_length(), 0.0, 1.0))
		Game.Phase.SLEEP:
			return SUNSET
		Game.Phase.NIGHT, Game.Phase.DEAD:
			return MIDNIGHT
		Game.Phase.WON:
			return 20.0
	return TITLE

func _process(delta: float) -> void:
	_spin += delta * 0.0007
	_spin_t -= delta
	if not _hold:
		# the sun only ever moves forward along the orbit; quickly while the screen is dark
		var speed := 30.0 if Game.phase == Game.Phase.DAY else 70.0
		var diff := fposmod(_target() - angle, 360.0)
		if diff > 0.01 and diff < 359.99:
			set_angle(angle + minf(diff, speed * delta))
			return
	_push()

func _push() -> void:
	if sun:
		sun.visible = sun_visible > 0.01
		sun.light_energy = SUN_ENERGY * sun_visible
		var up := Vector3.UP if absf(sun_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		sun.transform = Transform3D(Basis.looking_at(-sun_dir, up), Vector3.ZERO)
	# a changed sky material re-renders the sky, so only send it when the sun has really moved
	if sky_mat and (_pushed_dir.dot(sun_dir) < 0.99999 or absf(_pushed_vis - sun_visible) > 0.01 or _spin_t <= 0.0):
		_pushed_dir = sun_dir
		_pushed_vis = sun_visible
		_spin_t = 2.0
		sky_mat.set_shader_parameter("earth_dir", earth_dir)
		sky_mat.set_shader_parameter("sun_dir", sun_dir)
		sky_mat.set_shader_parameter("sun_visible", sun_visible)
		sky_mat.set_shader_parameter("star_gain", 0.3 + 0.6 * (1.0 - sun_visible))
		sky_mat.set_shader_parameter("earth_basis", Basis(Vector3.UP, _spin * TAU) * Basis.from_euler(Vector3(0.41, 0.0, 0.2)))
