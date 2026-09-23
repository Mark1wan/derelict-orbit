extends Node3D
## Boots the game: platform sniff, environment, title screen, WebXR session, quality, and the
## headless autotests. Structure ported from derelict-orbit's scripts/main.gd, which negotiates
## the same three platforms out of one static web build.
##
## The environment is the one real difference and it is a big one. Kestrel-9 sets ambient light
## to 0.12 and drops it to 0.008 when the power fails; down here 0.008 IS the setting, there is
## no sky, no sun and no windows, and the only light in the world is strapped to your head.
## That makes this by far the cheaper of the two games to draw - which is the budget the
## headlamp's shadow map is spent out of.

# The dark cave: ambient barely above nothing and fog that eats everything past ~14 m, so the
# headlamp is the whole of your vision.
const FOG_DENSITY := 0.048
const AMBIENT := 0.0055

# The lit cave (Cave.lit, on by default). Enough ambient to read shape at distance, fog pulled
# right back so a passage is legible end to end, and cave.gd hangs fill lights down every
# passage on top. See CaveGame.lit for why this is the default for now.
const FOG_DENSITY_LIT := 0.0085
const AMBIENT_LIT := 0.30

@onready var cave: Node3D = $Cave
@onready var caver: Caver = $Caver
@onready var ui: CanvasLayer = $UI

var webxr: WebXRInterface
var touch_ui: TouchControls
var vr_btn: Button
var touch_btn: Button
var desk_btn: Button
var status: Label
var hud: Label3D
var lamp: Lamp
var slate: Slate

func _ready() -> void:
	if Cave.is_touch_device():
		get_window().content_scale_size = Vector2i(820, 460)
		Cave.low_quality = true
	_make_env()
	_make_ui()
	_make_touch_ui()
	_fit_out()
	get_tree().root.size_changed.connect(func() -> void:
		if not get_viewport().use_xr:
			_apply_quality())

	webxr = XRServer.find_interface("WebXR") as WebXRInterface
	if webxr:
		webxr.session_supported.connect(_on_session_supported)
		webxr.session_started.connect(_on_session_started)
		webxr.session_ended.connect(_on_session_ended)
		webxr.session_failed.connect(_on_session_failed)
		webxr.is_session_supported("immersive-vr")
	else:
		status.text = "WebXR not available here. Desktop mode."

	var mode := OS.get_environment("CAVE_AUTOTEST")
	if mode == "touch":
		_autotest_touch()
	elif mode == "clear":
		_autotest_clear()
	elif mode == "route":
		_autotest_route()
	elif mode == "shots":
		_autotest_shots()
	elif mode != "":
		_autotest()

# ---------------------------------------------------------------- world

func _make_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if Cave.lit:
		# Warm and neutral rather than the cold wash of the dark version: this is standing in
		# for lamps that are notionally strung through the cave, not for starlight.
		env.ambient_light_color = Color(0.72, 0.70, 0.66)
		env.ambient_light_energy = AMBIENT_LIT
		env.fog_light_color = Color(0.10, 0.10, 0.11)
		env.fog_density = FOG_DENSITY_LIT
	else:
		# Not quite zero. A cave is absolutely black and a game that is absolutely black is
		# unplayable, so there is the faintest wash of cold light - enough to tell a wall from
		# a void at two metres once your eyes have given up.
		env.ambient_light_color = Color(0.42, 0.46, 0.55)
		env.ambient_light_energy = AMBIENT
		env.fog_light_color = Color(0.018, 0.020, 0.024)
		env.fog_density = FOG_DENSITY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	# No glow, no SSAO, no reflections: GL Compatibility on a Quest pays for all of them and
	# in a cave lit by one lamp none of them would be visible anyway.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	$WorldEnvironment.environment = env

## Kit the caver out: the lamp on the helmet, the slate on the wrist, and the rope the cave
## rigged for us. Done here rather than in caver.gd so the caver stays a body and a controller.
func _fit_out() -> void:
	lamp = Lamp.new()
	lamp.name = "Lamp"
	caver.camera.add_child(lamp)
	caver.lamp = lamp

	slate = Slate.new()
	slate.name = "Slate"
	add_child(slate)
	caver.slate = slate

	if cave.ropes.size() > 0:
		caver.rope = cave.ropes[0]

	hud = Label3D.new()
	hud.font_size = 30
	hud.pixel_size = 0.0014
	hud.modulate = Color(0.95, 0.88, 0.72)
	hud.outline_size = 8
	hud.outline_modulate = Color(0, 0, 0, 0.8)
	hud.position = Vector3(0, -0.14, -1.5)
	hud.no_depth_test = true
	hud.render_priority = 50
	hud.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	caver.camera.add_child(hud)
	Cave.notice.connect(_on_notice)

func _on_notice(text: String, seconds: float) -> void:
	hud.text = text
	var mine := text
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if hud.text == mine:
			hud.text = "")

# ---------------------------------------------------------------- title

func _make_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(centre)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	centre.add_child(box)

	var t := Label.new()
	t.text = "SOWBELLY"
	t.add_theme_font_size_override("font_size", 54)
	t.add_theme_color_override("font_color", Color(0.94, 0.86, 0.68))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)

	var sub := Label.new()
	sub.text = "Twenty-eight metres down, and the passage is getting smaller"
	sub.add_theme_color_override("font_color", Color(0.55, 0.52, 0.47))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	status = Label.new()
	status.text = "checking for a headset..."
	status.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)

	vr_btn = Button.new()
	vr_btn.text = "ENTER VR"
	vr_btn.visible = false
	vr_btn.pressed.connect(_enter_vr)
	box.add_child(vr_btn)

	var is_touch := Cave.is_touch_device()
	touch_btn = Button.new()
	touch_btn.text = "PLAY"
	touch_btn.visible = is_touch
	touch_btn.custom_minimum_size = Vector2(220, 56)
	touch_btn.pressed.connect(_start_touch)
	box.add_child(touch_btn)

	desk_btn = Button.new()
	desk_btn.text = "Play with keyboard + mouse" if is_touch else "Play on desktop"
	desk_btn.pressed.connect(_start_desktop)
	box.add_child(desk_btn)

	var comfort := CheckButton.new()
	comfort.text = "VR comfort: snap turning"
	comfort.visible = not is_touch
	comfort.toggled.connect(func(on: bool) -> void: Cave.comfort_snap = on)
	box.add_child(comfort)

	var low := CheckButton.new()
	low.text = "Low graphics"
	low.button_pressed = Cave.low_quality
	low.visible = is_touch
	low.toggled.connect(func(on: bool) -> void:
		Cave.low_quality = on
		_apply_quality())
	box.add_child(low)

	var help := Label.new()
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color(0.42, 0.40, 0.37))
	if is_touch:
		help.text = "Hold the phone sideways.\nLeft thumb moves, drag right to look.\nEXHALE is the big one - you will need it."
	else:
		help.text = "WASD to move, mouse to look, right mouse to take hold of the rock.\nSHIFT empties your chest. It is the only way through the Devil's Pinch.\nF lamp, TAB slate, R rope, CTRL lower, SPACE up."
	box.add_child(help)

func _make_touch_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	touch_ui = TouchControls.new()
	touch_ui.visible = false
	touch_ui.caver = caver
	layer.add_child(touch_ui)
	if OS.has_feature("web"):
		var dbg: int = JavaScriptBridge.eval("location.search.indexOf('touchdebug') >= 0 ? 1 : 0", true)
		touch_ui.debug_log = dbg == 1
	if OS.has_environment("CAVE_TOUCH_DEBUG"):
		touch_ui.debug_log = true

# ---------------------------------------------------------------- starting

func _on_session_supported(mode: String, supported: bool) -> void:
	if mode == "immersive-vr":
		vr_btn.visible = supported
		status.text = "Headset found." if supported else "No headset here. Desktop or phone."

func _enter_vr() -> void:
	webxr.session_mode = "immersive-vr"
	webxr.requested_reference_space_types = "local-floor, local"
	webxr.required_features = "local"
	webxr.optional_features = "local-floor"
	# 0.85 per eye: about 28% fewer pixels, and in a cave where nothing is more than fifteen
	# metres away and the fog takes the rest, you cannot see where it went.
	webxr.render_target_size_multiplier = 0.85
	if not webxr.initialize():
		status.text = "Could not start the VR session."

func _on_session_started() -> void:
	get_viewport().use_xr = true
	ui.visible = false
	_begin(true)

func _on_session_ended() -> void:
	get_viewport().use_xr = false
	status.text = "VR session ended. Reload the page to go back in."

func _on_session_failed(message: String) -> void:
	status.text = "VR failed: " + message

func _start_desktop() -> void:
	ui.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_begin(false)

func _start_touch() -> void:
	Cave.touch = true
	Input.emulate_mouse_from_touch = false
	touch_ui.visible = true
	ui.visible = false
	_begin(false)
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# The orientation lock only resolves once fullscreen has landed, so it waits. iOS
		# refuses either way, which is what the "turn your phone sideways" card is for.
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function () {}); } catch (e) {}"))

func _begin(xr: bool) -> void:
	if not xr:
		_apply_quality()
	caver.begin(xr)
	caver.teleport(cave.start_point, cave.start_look)
	# Already clipped on, a few metres down. There is no standing about at the top to get
	# wrong - you open your eyes hanging in a shaft with the walls in reach.
	if cave.start_on_rope and caver.rope:
		caver.rope.clip_on(caver)
	if xr:
		slate.attach_wrist(caver.left_hand, caver.camera)
	else:
		slate.attach_view(caver.camera)
	Sfx.set_ambient("wind", -24.0)
	await _warm_up()
	Cave.start()
	Cave.say("Sowbelly. ALT brakes, W climbs.", 5.0)

## Walk the cave with the lamp on before handing it over, so every shader the headlamp will
## ever compile is compiled while the screen is still black. Straight out of derelict-orbit's
## main.gd:881-926, including the five-second budget: a loading screen that takes as long as it
## takes is how you lose a headset player.
func _warm_up() -> void:
	caver.fade_target = 1.0
	Cave.say("SOWBELLY\nchecking lights", 6.0)
	if OS.has_environment("CAVE_AUTOTEST"):
		await get_tree().create_timer(0.4).timeout
		caver.fade_target = 0.0
		hud.text = ""
		return
	var deadline := Time.get_ticks_msec() + 5000
	var here := caver.global_position
	var here_look: Vector3 = cave.start_look
	for p: Dictionary in cave.data.get("passages", []):
		for t: float in [0.15, 0.55, 0.9]:
			if Time.get_ticks_msec() > deadline:
				break
			caver.teleport(cave.point_in(p["id"], t) + Vector3(0, 0.5, 0), cave.heading_in(p["id"], t))
			await get_tree().process_frame
			await get_tree().process_frame
	caver.teleport(here, here_look)
	if cave.start_on_rope and caver.rope and not caver.rope.clipped:
		caver.rope.clip_on(caver)
	await get_tree().create_timer(0.5).timeout
	hud.text = ""
	caver.fade_target = 0.0

## Resolution scale, MSAA and the shadow atlas, exactly as derelict-orbit does it. Never
## applied in XR, where the eye buffers are sized by render_target_size_multiplier instead.
func _apply_quality() -> void:
	var vp := get_viewport()
	if Cave.low_quality:
		var wide := float(get_window().size.x)
		vp.scaling_3d_scale = clampf(1100.0 / wide, 0.35, 1.0) if wide > 1.0 else 0.6
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.positional_shadow_atlas_size = 1024
	else:
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_2X
		vp.positional_shadow_atlas_size = 2048
	if caver.started and lamp:
		lamp.set_shadow_allowed(caver.shadow_allowed())

# ---------------------------------------------------------------- autotests
#
# CAVE_AUTOTEST=1 walks the whole cave and asserts its way down. A linear await script with
# plain assert(cond, "message") and prints for the record, on derelict-orbit's pattern - no
# framework, and it drives the real classes through the real entry points. Unlike upstream's
# smoke test this one runs in CI WITHOUT `|| true`, so it can actually fail a build.

func _autotest() -> void:
	print("[autotest] Sowbelly")
	_start_desktop()
	await get_tree().create_timer(1.2).timeout

	var b: CaverBody = caver.body
	assert(cave.bores.size() >= 5, "cave did not build its passages")
	var tris := 0
	for c in cave.get_children():
		if c is MeshInstance3D:
			tris += (c as MeshInstance3D).mesh.get_faces().size() / 3
	print("[autotest] %d passages, %d meshes, %d tris" % [cave.bores.size(), _mesh_children(), tris])
	# A floor, not a target. 86 m of passage at Bore.STATION_STEP with Bore.SIDES faces per
	# ring cannot come out under this unless a passage silently failed to sweep, which is the
	# only failure this is here to catch.
	assert(tris > 6000, "cave is suspiciously small: %d tris" % tris)
	for bore in cave.bores:
		assert(bore.points.size() > 4, "passage '%s' has only %d stations" % [bore.id, bore.points.size()])

	# 1. Standing room in the Cellar, and the lamp is the only thing lighting it.
	await _put_in("cellar", 0.5)
	assert(b.name_of() == "stand", "cannot stand up in the Cellar: %s (%.2f m of headroom)"
		% [b.name_of(), b.headroom])
	assert(b.pressure < 0.45, "the Cellar feels tight: pressure %.2f" % b.pressure)
	var lights := 0
	for n in _all_nodes(self):
		if n is Light3D and (n as Light3D).visible:
			lights += 1
	print("[autotest] cellar: %s, headroom %.2f m, pressure %.2f, %d lights in the world"
		% [b.name_of(), b.headroom, b.pressure, lights])
	# The budget depends on which cave you asked for. Lit, the fill is what you see by and the
	# cap is what the Compatibility renderer will carry; dark, the headlamp is the whole of it
	# and anything else on is a mistake.
	if Cave.lit:
		assert(lights >= 8, "lit mode but only %d lights - the cave will be black" % lights)
		assert(lights <= 60, "%d lights is more than the renderer should carry" % lights)
	else:
		assert(lights <= 4, "the dark cave should have almost no lights, found %d" % lights)

	# 2. The Gullet puts you on your hands and knees without being asked.
	await _put_in("gullet", 0.6)
	assert(b.posture >= CaverBody.KNEES, "the Gullet should fold you down, got %s" % b.name_of())
	print("[autotest] gullet: %s, headroom %.2f m" % [b.name_of(), b.headroom])

	# 3. The Flatiron puts you flat, and it registers as tight.
	await _put_in("flatiron", 0.5)
	assert(b.posture >= CaverBody.BELLY, "the Flatiron should put you flat, got %s" % b.name_of())
	assert(b.pressure > 0.45, "the Flatiron does not feel tight: pressure %.2f" % b.pressure)
	print("[autotest] flatiron: %s, headroom %.2f m, pressure %.2f"
		% [b.name_of(), b.headroom, b.pressure])

	# 4. Breath. A full exhale takes 3.5 cm off the chest and it does not last forever.
	caver.debug_exhale(1.0)
	await get_tree().create_timer(1.2).timeout
	var squeezed := b.chest
	assert(squeezed < CaverBody.CHEST_RELAXED - 0.030,
		"exhaling barely shrank the chest: %.3f m" % squeezed)
	assert(b.air < 0.95, "a held exhale is not costing anything")
	print("[autotest] chest %.1f cm relaxed -> %.1f cm exhaled, %.1f s of hold left"
		% [CaverBody.CHEST_RELAXED * 100.0, squeezed * 100.0, b.breath_left()])
	caver.debug_exhale(0.0)
	await get_tree().create_timer(1.0).timeout
	assert(b.chest > CaverBody.CHEST_RELAXED - 0.010, "the chest did not open again")

	# 5. The Devil's Pinch: the whole cave in one assertion. The crux admits an exhaled chest
	# and refuses a relaxed one, and check_fit.py proves the same thing about the data.
	var pinch: Bore = cave.bore("pinch")
	assert(pinch != null, "no Devil's Pinch in the cave")
	var crux: Dictionary = pinch.tightest(CaverBody.CHEST_RELAXED)
	var crux_wide := _section_width(pinch, crux["i"])
	assert(crux_wide < CaverBody.CHEST_RELAXED,
		"the crux is %.3f m wide - a relaxed chest walks it" % crux_wide)
	assert(crux_wide > CaverBody.CHEST_RELAXED - CaverBody.CHEST_SQUEEZE,
		"the crux is %.3f m wide - nobody gets through it" % crux_wide)
	print("[autotest] pinch crux %.1f cm: relaxed %.1f cm no, exhaled %.1f cm yes"
		% [crux_wide * 100.0, CaverBody.CHEST_RELAXED * 100.0,
			(CaverBody.CHEST_RELAXED - CaverBody.CHEST_SQUEEZE) * 100.0])

	# 6. Wedged, and out again. Push into the crux with a full chest until the rock stops you,
	# then empty it and watch the same passage let you through. This is the whole game in one
	# step, and it is the one that would notice if any part of it stopped being true.
	var crux_t: float = float(crux["i"]) / float(maxi(pinch.points.size() - 1, 1))
	await _put_in("pinch", maxf(crux_t - 0.07, 0.02))
	caver.debug_face(cave.heading_in("pinch", crux_t))
	caver.debug_move(Vector2(0, 1))
	var held := 0.0
	# It shuffles in at 13 cm/s, so this is a minute of crawling, not a fixed guess at how
	# many frames a metre takes.
	var start_at := caver.global_position
	for i in 1400:
		await get_tree().physics_frame
		held = maxf(held, b.pressure)
		if b.wedged:
			break
	var got_to: Dictionary = pinch.nearest(caver.global_position)
	print("[autotest] walked in to %.2f m of a %.2f m crux, %s"
		% [got_to["along"], crux["along"], b.name_of()])
	print("[autotest] pushing the crux with a full chest: pressure %.2f (peak %.2f), %s, %s"
		% [b.pressure, held, "WEDGED" if b.wedged else "not wedged", b.advice()])
	assert(held > 0.85, "the crux never pressed on you: peak pressure %.2f" % held)
	assert(b.wedged, "a relaxed chest should not get through a %.1f cm slot" % (crux_wide * 100.0))
	assert(b.advice() != "", "wedged and the slate says nothing")

	caver.debug_exhale(1.0)
	for i in 300:
		await get_tree().physics_frame
		if not b.wedged:
			break
	assert(not b.wedged, "still wedged after emptying the chest: pressure %.2f" % b.pressure)
	print("[autotest] exhaled to %.1f cm: pressure %.2f, moving again"
		% [b.chest * 100.0, b.pressure])
	caver.debug_move(Vector2.ZERO)
	caver.debug_exhale(0.0)

	# 7. The Drainpipe is a lead, not a route: it closes, and you can back out of it.
	var pipe: Bore = cave.bore("drainpipe")
	assert(pipe != null, "no Drainpipe")
	var end_wide := _section_width(pipe, pipe.points.size() - 1)
	assert(end_wide < CaverBody.CHEST_RELAXED - CaverBody.CHEST_SQUEEZE,
		"the Drainpipe does not pinch out: %.3f m at the end" % end_wide)
	print("[autotest] drainpipe closes to %.1f cm - nobody is getting through that" % (end_wide * 100.0))

	# 8. The rope goes down the pitch and comes back up.
	assert(caver.rope != null, "the pitch is not rigged")
	var top_y := caver.rope.top.y
	caver.rope.debug_clip(caver)
	assert(caver.rope.clipped, "could not clip on")
	caver.debug_brake(0.0)
	for i in 260:
		await get_tree().physics_frame
	var fell := top_y - caver.global_position.y
	print("[autotest] rope: %.1f m down in %.1f s" % [fell, 260.0 / 72.0])
	assert(fell > 8.0, "the rope did not let you down: %.1f m" % fell)
	caver.debug_brake(1.0)
	caver.debug_move(Vector2(0, 1))
	var before := caver.global_position.y
	for i in 120:
		await get_tree().physics_frame
	assert(caver.global_position.y > before + 0.4,
		"cannot climb the rope: %.2f m" % (caver.global_position.y - before))
	print("[autotest] rope: climbed %.2f m back up" % (caver.global_position.y - before))
	caver.rope.unclip(caver)
	caver.debug_move(Vector2.ZERO)

	# 9. Graphics gates.
	assert(caver.shadow_allowed(), "the headlamp shadow should be on for flat high graphics")
	Cave.low_quality = true
	_apply_quality()
	assert(not caver.shadow_allowed(), "low graphics should drop the headlamp shadow")
	assert(get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "low graphics should drop MSAA")
	Cave.low_quality = false
	_apply_quality()
	print("[autotest] quality gates ok")

	# 10. The slate says something true.
	slate.toggle()
	await get_tree().create_timer(0.4).timeout
	assert(slate.open, "the slate did not open")
	assert(slate.body_text.text.contains("depth"), "the slate is not reporting depth")
	print("[autotest] slate:\n" + slate.body_text.text)

	print("[autotest] deepest %.1f m, crawled %.0f m, found %d passages"
		% [Cave.deepest, Cave.travelled, Cave.visited.size()])
	print("[autotest] PASS")
	get_tree().quit()

## Drive the phone layout with synthetic fingers, the way derelict-orbit's _autotest_touch
## does: the overlay's own finger_down / finger_move / finger_up, at the coordinates it says
## it drew its buttons at, so a button that moved off the screen fails the build.
func _autotest_touch() -> void:
	print("[autotest] Sowbelly, touch")
	Cave.low_quality = true
	_start_touch()
	await get_tree().create_timer(1.2).timeout
	touch_ui.size = Vector2(820, 460)
	touch_ui._layout()

	var rect := Rect2(Vector2.ZERO, touch_ui.size)
	for id: String in touch_ui.button_ids():
		var c := touch_ui.button_center(id)
		assert(rect.has_point(c), "touch button '%s' is off the screen at %s" % [id, c])
	print("[autotest] %d buttons, all on screen at %s" % [touch_ui.button_ids().size(), touch_ui.size])

	# EXHALE is the one that has to work.
	touch_ui.finger_down(0, touch_ui.button_center("exhale"))
	for i in 100:
		await get_tree().physics_frame
	assert(caver.body.chest < CaverBody.CHEST_RELAXED - 0.030,
		"the EXHALE button did not empty the chest: %.3f m" % caver.body.chest)
	print("[autotest] EXHALE: chest %.1f cm" % (caver.body.chest * 100.0))
	touch_ui.finger_up(0, touch_ui.button_center("exhale"))

	# The stick moves you - on the floor of the Cellar, not at the head of the pitch, where
	# what it would actually measure is gravity.
	await _put_in("cellar", 0.5)
	var before := caver.global_position
	touch_ui.finger_down(1, Vector2(120, 340))
	touch_ui.finger_move(1, Vector2(120, 280))
	for i in 90:
		await get_tree().physics_frame
	touch_ui.finger_up(1, Vector2(120, 280))
	var walked := before.distance_to(caver.global_position)
	assert(walked > 0.25 and walked < 5.0, "the touch stick moved you %.2f m in 1.2 s" % walked)
	print("[autotest] stick moved %.2f m" % walked)

	# Dragging on the right looks around.
	var yaw := caver.yaw
	touch_ui.finger_down(2, Vector2(620, 220))
	for x in range(620, 540, -10):
		touch_ui.finger_move(2, Vector2(x, 220))
		await get_tree().process_frame
	touch_ui.finger_up(2, Vector2(540, 220))
	assert(absf(caver.yaw - yaw) > 0.05, "dragging did not turn the view")
	print("[autotest] look drag turned %.2f rad" % (caver.yaw - yaw))

	# Posture buttons, the lamp and the slate. Two frames each, not one: SceneTree.physics_frame
	# fires immediately BEFORE _physics_process runs, so a single await resumes before anything
	# has read the edge that was just written.
	touch_ui.finger_down(3, touch_ui.button_center("low"))
	touch_ui.finger_up(3, touch_ui.button_center("low"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(caver.body.forced_low, "LOW did not ask for a lower posture")
	touch_ui.finger_down(3, touch_ui.button_center("lamp"))
	touch_ui.finger_up(3, touch_ui.button_center("lamp"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not lamp.on, "LAMP did not turn the headlamp off")
	touch_ui.finger_down(3, touch_ui.button_center("slate"))
	touch_ui.finger_up(3, touch_ui.button_center("slate"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(slate.open, "SLATE did not open the slate")
	print("[autotest] LOW, LAMP and SLATE all reachable")

	touch_ui.release_all()
	print("[autotest] PASS")
	get_tree().quit()

## CAVE_AUTOTEST=clear - is there anything in the cave that should not be there?
##
## The route walker only sees what is on the line it walks, which is how three invisible walls
## survived it. This looks at the whole cave at once: from every station of every passage, cast
## a ray along each of the section's own directions and compare where it hits to how far that
## vertex says the wall is. Displacement only ever pushes rock OUTWARD, so a hit that comes back
## closer than the section is geometry inside the passage that has no business being there - a
## wall left hanging through somewhere you walk, invisible because its faces are single-sided
## and solid because its collider is not.
##
## This is the direct test for "no invisible walls", and unlike walking it cannot miss one by
## taking a different line through the room.
func _autotest_clear() -> void:
	print("[autotest] Sowbelly, looking for anything in the way")
	_start_desktop()
	await get_tree().create_timer(1.5).timeout
	var space := get_world_3d().direct_space_state

	# Formations are on their own body and are skipped: a stalactite is meant to be in the way,
	# you can see it, and a passage that has one in it is not the bug this pass is looking for.
	# Junction seams are NOT skipped. They are rock kept on purpose, but kept rock that reaches
	# into a passage still blocks it, and skipping them once hid the lip that stopped the route
	# walker a metre short of the Bone Box.
	var skip: Array[RID] = []
	if cave.decor:
		skip.append(cave.decor.get_rid())

	var checked := 0
	var bad: Array[String] = []
	var worst := 1.0
	var worst_at := Vector3.ZERO
	for b in cave.bores:
		var hits := 0
		var tightest := 1.0
		var where := 0.0
		var where_at := Vector3.ZERO
		var where_on := ""
		var last: int = b.points.size() - 1
		for i in b.points.size():
			var sec: PackedVector2Array = b.sections[i]
			var f: Basis = b.frames[i]
			var o: Vector3 = b.points[i]
			# A capped end is a wall, and the rays at that station lie in its plane, where a
			# ray-triangle test is degenerate and reports a hit at zero distance. Step a little
			# off the cap before casting: what it walls off is rock, and is supposed to be.
			if i == 0:
				o += f.z * 0.12
			elif i == last:
				o -= f.z * 0.12
			for k in sec.size():
				var q: Vector2 = sec[k]
				var want: float = q.length()
				if want < 0.02:
					continue
				var dir: Vector3 = (f.x * q.x + f.y * q.y).normalized()
				# A little past the wall, so the passage's own surface is a hit at `want`.
				var to: Vector3 = o + dir * (want + 0.35)
				var ray := PhysicsRayQueryParameters3D.create(o, to, 1, skip)
				var hit := space.intersect_ray(ray)
				checked += 1
				if hit.is_empty():
					continue
				var d: float = o.distance_to(hit["position"])
				var frac: float = d / want
				if frac < tightest:
					tightest = frac
					where = b.along[i]
					where_at = hit["position"]
					var who: Object = hit["collider"]
					where_on = who.name if who else "?"
				if frac < worst:
					worst = frac
					worst_at = hit["position"]
				# Two conditions, and the second is what makes this work at a junction. A hit
				# is only a fault if it is BOTH early and well inside THIS passage.
				#
				# Early: 0.80 rather than 1.0, because the section is a 22-gon inscribed in its
				# own curve and a ray between two vertices legitimately meets the chord a little
				# short. Inside this passage: at a mouth a ray leaves through the hole and
				# measures the neighbour, whose wall is legitimately nearer than this section
				# claims - that is a junction, not a fault, and the neighbour's own stations
				# measure it properly. Rock a third of the way across a passage you have to
				# crawl through is a fault wherever it came from.
				if frac < 0.80 and b.contains_point(hit["position"], 1.15):
					hits += 1
		if hits > 0:
			bad.append("%s: %d rays blocked, worst %.0f%% of the section at %.1f m in, hitting %s at (%.2f %.2f %.2f)"
				% [b.label, hits, tightest * 100.0, where, where_on,
					where_at.x, where_at.y, where_at.z])
		print("[autotest]   %-20s %4d stations, closest hit %.0f%% of the section"
			% [b.label, b.points.size(), tightest * 100.0])

	print("[autotest] %d rays cast, worst %.0f%% of the expected section at (%.1f %.1f %.1f)"
		% [checked, worst * 100.0, worst_at.x, worst_at.y, worst_at.z])
	for line in bad:
		print("[autotest]   BLOCKED  " + line)

	# Second pass: is the way ALONG the passage clear? The rays above all go sideways, out from
	# the centreline, so a membrane stretched across a passage - which is precisely what a
	# junction leaves if it goes wrong - is the one thing they can never hit. This walks the
	# centreline itself, station to station, which is the line the body follows.
	var across: Array[String] = []
	for b in cave.bores:
		var stops := 0
		var first := Vector3.ZERO
		var first_at := 0.0
		var on := ""
		var tail: int = b.points.size() - 1
		for i in b.points.size() - 1:
			# Stop short of the two end faces. A passage that runs into rock ends in its own
			# cap, and a room's centreline ends in the room's back wall - both are rock the
			# centreline is supposed to meet.
			var from: Vector3 = b.points[i]
			var to: Vector3 = b.points[i + 1]
			if i == 0:
				from += (b.frames[0] as Basis).z * 0.15
			if i == tail - 1:
				to -= (b.frames[tail] as Basis).z * 0.15
			var ray := PhysicsRayQueryParameters3D.create(from, to, 1, skip)
			var hit := space.intersect_ray(ray)
			checked += 1
			if hit.is_empty():
				continue
			if stops == 0:
				first = hit["position"]
				first_at = b.along[i]
				var who: Object = hit["collider"]
				on = who.name if who else "?"
			stops += 1
		if stops > 0:
			across.append("%s: the centreline is blocked at %d places, first %.1f m in, by %s at (%.2f %.2f %.2f)"
				% [b.label, stops, first_at, on, first.x, first.y, first.z])
			print("[autotest]   ACROSS   " + across[across.size() - 1])
	if across.is_empty():
		print("[autotest] every passage is clear end to end along its own centreline")

	# Third pass, the other failure: not rock where there should be none, but no rock where
	# there should be some. A cave is a closed shell, so from anywhere inside it every
	# direction ends in rock. A ray that reaches eighty metres without hitting anything has
	# left the world, and where it left is a hole you can walk out of.
	var leaks: Array[String] = []
	for b in cave.bores:
		var out := 0
		var first_dir := Vector3.ZERO
		var first_out := Vector3.ZERO
		var first_at := 0.0
		var last: int = b.points.size() - 1
		for i in b.points.size():
			# Off the end faces, for the same reason as above: at station 0 the ray would
			# start on the cap's own centre vertex, where the test is degenerate and every
			# ray reports a miss. That is not a hole, it is a fan apex.
			var o: Vector3 = b.points[i]
			if i == 0:
				o += (b.frames[i] as Basis).z * 0.12
			elif i == last:
				o -= (b.frames[i] as Basis).z * 0.12
			for k in SKY_DIRS.size():
				var to: Vector3 = o + SKY_DIRS[k].normalized() * 80.0
				var ray := PhysicsRayQueryParameters3D.create(o, to, 1)
				checked += 1
				if space.intersect_ray(ray).is_empty():
					if out == 0:
						first_at = b.along[i]
						first_dir = SKY_DIRS[k].normalized()
						# Walk the ray until it is in no passage at all. That is where it left
						# the rock, and saying so beats reporting where it started - a hole a
						# few centimetres across at a junction is not findable from the origin.
						for step in 400:
							var probe: Vector3 = o + first_dir * (float(step) * 0.2)
							if not cave.inside_any(probe, 1.0):
								first_out = probe
								break
					out += 1
		if out > 0:
			leaks.append("%s: %d rays out, first at %.1f m in, leaving the rock at (%.2f %.2f %.2f)"
				% [b.label, out, first_at, first_out.x, first_out.y, first_out.z])
			print("[autotest]   LEAK     " + leaks[leaks.size() - 1])
	if leaks.is_empty():
		print("[autotest] the shell is closed - every direction from every station ends in rock")

	assert(across.is_empty(), "a passage is blocked across: %s" % ", ".join(across))
	assert(bad.is_empty(), "there is rock inside the passages: %s" % ", ".join(bad))
	assert(leaks.is_empty(), "the cave leaks: %s" % ", ".join(leaks))
	print("[autotest] PASS - nothing in the way anywhere in the cave, and nothing missing")
	get_tree().quit()

## 32 directions spread evenly over a sphere, for asking "is this point enclosed".
const SKY_DIRS: Array[Vector3] = [
	Vector3(0.0, 1.0, 0.0), Vector3(0.0, -1.0, 0.0),
	Vector3(0.379, 0.939, 0.108), Vector3(-0.163, 0.879, 0.448),
	Vector3(-0.520, 0.818, -0.246), Vector3(0.308, 0.758, -0.575),
	Vector3(0.518, 0.697, 0.496), Vector3(-0.767, 0.636, 0.086),
	Vector3(0.457, 0.576, -0.678), Vector3(0.219, 0.515, 0.829),
	Vector3(-0.831, 0.455, -0.320), Vector3(0.895, 0.394, 0.211),
	Vector3(-0.404, 0.333, 0.851), Vector3(-0.311, 0.273, -0.910),
	Vector3(0.871, 0.212, -0.443), Vector3(-0.858, 0.152, 0.491),
	Vector3(0.198, 0.091, 0.976), Vector3(0.494, 0.030, -0.869),
	Vector3(-0.963, -0.030, -0.267), Vector3(0.812, -0.091, 0.577),
	Vector3(-0.190, -0.152, 0.970), Vector3(-0.508, -0.212, -0.834),
	Vector3(0.937, -0.273, -0.218), Vector3(-0.807, -0.333, 0.487),
	Vector3(0.269, -0.394, 0.879), Vector3(0.319, -0.455, -0.831),
	Vector3(-0.735, -0.515, -0.441), Vector3(0.724, -0.576, 0.380),
	Vector3(-0.385, -0.636, 0.669), Vector3(-0.122, -0.697, -0.707),
	Vector3(0.480, -0.758, -0.441), Vector3(-0.451, -0.818, 0.358),
]

## CAVE_AUTOTEST=route - walk the whole cave from the spawn point and report where it stops.
##
## The other two tests teleport into each passage and check it behaves. This one refuses to
## teleport: it starts where a player starts, walks the centreline station by station, and says
## where the rock would not let it through. That is the only way to catch the class of problem
## a player actually hits - an unlit lip between two passages, a wall left across a
## mouth, a spawn point with no floor under it - because every one of those is invisible to a
## test that puts the body past it.
func _autotest_route() -> void:
	print("[autotest] Sowbelly, walking the route")
	_start_desktop()
	await get_tree().create_timer(1.5).timeout
	var b: CaverBody = caver.body

	# 1. Does the spawn hold you up? On the rope that means the rope caught you; on the floor it
	# means there was a floor. Either way you must not still be going down after three seconds.
	caver.teleport(cave.start_point, cave.start_look)
	if cave.start_on_rope and caver.rope:
		caver.rope.clip_on(caver)
		caver.debug_brake(1.0)
	var fell := caver.global_position.y
	for i in 220:
		await get_tree().physics_frame
	var drop: float = fell - caver.global_position.y
	print("[autotest] spawn: %s, moved %.2f m in 3 s, at %.1f m down"
		% ["on the rope" if caver.rope and caver.rope.clipped else "on foot",
			drop, -caver.global_position.y])
	var held: bool = caver.is_on_floor() or (caver.rope != null and caver.rope.clipped)
	assert(held, "the spawn point holds nothing up - dropped %.1f m" % drop)
	assert(drop < 4.0, "you are still falling %.1f m after three seconds at the spawn" % drop)
	if caver.rope:
		caver.rope.unclip(caver)
	caver.debug_brake(0.0)

	# 2. Walk each passage along its own centreline, and report the first station the body
	# cannot reach. Teleporting is allowed only between passages, so a blockage inside one is
	# always found.
	# Steps are in METRES, not fractions, and each gets long enough for the slowest shape the
	# rock can force on you. A 3 % step of a short passage is less than the arrival tolerance -
	# the body is already there and never moves, which reads as blocked - and a committed
	# shuffle covers 4 cm a second, so a step budget sized for walking condemns every squeeze
	# in the cave. Both of those were bugs in this test before they were anything else.
	var blocked: Array[String] = []
	for bore in cave.bores:
		if bore.kind == "shaft":
			# You do not walk down a shaft. This one is rigged; the rope test covers it.
			print("[autotest]   %-20s   -   a pitch: rigged, not walked" % bore.label)
			continue
		var length: float = bore.length()
		var step_t: float = clampf(1.0 / maxf(length, 0.1), 0.02, 0.25)
		# 90 s a metre. `superman` moves at 10 cm a second before pressure takes a third of that
		# off again, and a body flat out does not travel in a straight line down the centreline
		# either - so a budget sized for walking condemns every squeeze in the cave, and a
		# budget sized for a straight line condemns every bend.
		var budget := int(90.0 * Engine.physics_ticks_per_second)
		await _put_in(bore.id, 0.04)
		var reached := 0.04
		var stuck := 0.0
		var t := 0.04
		while t < 0.97:
			t = minf(t + step_t, 0.99)
			var want: Vector3 = cave.point_in(bore.id, t) + Vector3(0, 0.1, 0)
			caver.debug_face(cave.heading_in(bore.id, t))
			caver.debug_move(Vector2(0, 1))
			var before := caver.global_position
			var closest: float = before.distance_to(want)
			var got := 0.0
			var arrived := false
			for i in budget:
				await get_tree().physics_frame
				# Steer. A player faces where they are going and keeps facing it; pointing the
				# body once at the start of a 1.5 m step and letting it run is how you crawl
				# into the outer wall of a bend and slide along it for forty-five seconds, which
				# is a flaw in the test rather than in the cave.
				if i % 12 == 0:
					var aim: Vector3 = want - caver.global_position
					aim.y = 0.0
					if aim.length_squared() > 0.04:
						caver.debug_look(aim.normalized())
				# Breathe out when it gets tight, which is what a player does and what the
				# cave is designed around. Without it the walker reaches the Devil's Pinch,
				# meets a slot narrower than a relaxed chest, and reports the game's central
				# mechanic as a bug.
				caver.debug_exhale(1.0 if b.pressure > 0.82 else 0.0)
				closest = minf(closest, caver.global_position.distance_to(want))
				# Progress is measured ALONG the passage, not as distance to a point on its
				# centreline. A bedding crawl is three metres wide and forty centimetres high:
				# a body crosses it a metre to one side of the line and never comes within
				# 80 cm of the station. That is not a blockage, that is a bedding crawl.
				got = maxf(got, float(bore.nearest(caver.global_position)["along"]) / maxf(length, 0.001))
				# Arrival is progress ALONG the passage. The old test also accepted "within 80 cm
				# of the station", which in a five-metre lead with 1.25 m steps means arriving
				# without going anywhere - the Drainpipe reported itself walked, 99 % of a
				# passage whose entire purpose is to pinch shut.
				if got >= t - 0.01 or closest < 0.35:
					arrived = true
					break
			caver.debug_exhale(0.0)
			if not arrived:
				var made: float = before.distance_to(caver.global_position)
				print("[autotest]     %.1f m in: made %.2f m in 45 s, reached %.0f%%, still %.2f m off the line, %s, p=%.2f, head %.2f, wide %.2f, at %s"
					% [t * length, made, got * 100.0, closest, b.name_of(), b.pressure,
						b.headroom, b.width, caver.global_position])
				_what_is_in_the_way(caver.global_position, cave.heading_in(bore.id, t))
				stuck = t
				break
			reached = t
		caver.debug_move(Vector2.ZERO)
		var pct := int(round(reached * 100.0))
		var note := "walked it"
		if stuck > 0.0:
			note = "STOPPED at %d%% (%.1f m in), %s, pressure %.2f" % [
				int(round(stuck * 100.0)), stuck * bore.length(), b.name_of(), b.pressure]
			# The Drainpipe is meant to stop you; everything else is not.
			var lead := false
			for p: Dictionary in cave.data.get("passages", []):
				if p.get("id", "") == bore.id and p.get("dead_end", false):
					lead = true
			if lead:
				note = "closed at %d%% - which is the point of a lead" % int(round(stuck * 100.0))
			else:
				blocked.append("%s at %d%%" % [bore.label, int(round(stuck * 100.0))])
		print("[autotest]   %-20s %3d%%  %s" % [bore.label, pct, note])

	# 3. The lights.
	var lights := 0
	for n in _all_nodes(self):
		if n is Light3D and (n as Light3D).visible:
			lights += 1
	print("[autotest] %d lights (Cave.lit = %s)" % [lights, Cave.lit])
	if Cave.lit:
		assert(lights >= 8, "lit mode but only %d lights - the cave will be black" % lights)
		assert(lights <= 60, "%d lights is more than the Compatibility renderer should carry" % lights)

	# Trimming too much punches a hole to the void. The safety net would quietly put you back
	# and you would never know, so it is asserted rather than trusted.
	print("[autotest] safety net fired %d times" % caver.rescues)
	assert(caver.rescues == 0, "fell out of the world %d times - the cave leaks" % caver.rescues)

	if not blocked.is_empty():
		print("[autotest] BLOCKED: " + ", ".join(blocked))
	assert(blocked.is_empty(), "a player cannot get through: %s" % ", ".join(blocked))
	print("[autotest] PASS - the whole route walks")
	get_tree().quit()

## CAVE_AUTOTEST=shots - stand in each passage and photograph it.
##
## The rules this cave is built to are visual ones - round rather than slab-sided, only ever
## tighter, wet dark rock, cracks that read as cracks - and not one of them is something an
## assertion can settle. check_fit can prove the Flatiron is 51 cm high and has nothing at all
## to say about whether it looks like a bedding plane or a drainpipe.
##
## So this puts the body where a player would be, lets it take the posture the rock gives it,
## and saves what it sees. Needs a real framebuffer:
##
##     xvfb-run -a godot --rendering-driver opengl3 --path caves --resolution 1280x720
##
func _autotest_shots() -> void:
	print("[autotest] Sowbelly, photographing it")
	_start_desktop()
	await get_tree().create_timer(1.5).timeout
	var dir: String = OS.get_environment("CAVE_SHOTS")
	if dir == "":
		dir = "res://build/shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	# Where to stand, and which way to look. A passage is photographed from far enough in that
	# the mouth is behind you - standing in a doorway shows you the doorway, not the passage.
	var views: Array = [
		["cellar", 0.30, "the cellar, from the foot of the rope"],
		["cellar", 0.66, "the cellar, looking at the gullet"],
		["gullet", 0.10, "the gullet, at its mouth"],
		["gullet", 0.55, "the gullet, halfway"],
		["gullet", 0.82, "the gullet, where it closes down"],
		["bonebox", 0.55, "the bone box"],
		["flatiron", 0.30, "the flatiron"],
		["flatiron", 0.62, "the flatiron, at its worst"],
		["pinch", 0.25, "the devil's pinch, on the way in"],
		["pinch", 0.47, "the devil's pinch, at the crux"],
		["drainpipe", 0.20, "the drainpipe"],
	]
	var n := 0
	for v: Array in views:
		var id: String = v[0]
		var t: float = v[1]
		caver.teleport(cave.point_in(id, t) + Vector3(0, 0.12, 0), cave.heading_in(id, t))
		# Long enough for the body to fall to the floor, measure, fold, and for the eye height
		# to finish easing - a shot taken mid-fold is a photograph of a bug that is not there.
		for i in 90:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		n += 1
		var path := "%s/%02d-%s.png" % [dir, n, id]
		img.save_png(path)
		print("[autotest]   %-40s %s, head %.2f m  ->  %s"
			% [v[2], caver.body.name_of(), caver.body.headroom, path])
	print("[autotest] PASS - %d shots" % n)
	get_tree().quit()

## Cast forward at four heights and say what is there. Called when the route walker gives up:
## "it will not go" is not a bug report, and the difference between rock across the passage, a
## lip on the floor and nothing at all is the whole of the diagnosis.
func _what_is_in_the_way(from: Vector3, heading: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var dir := heading.normalized()
	for h: float in [0.05, 0.35, 0.75, 1.20]:
		var o: Vector3 = from + Vector3(0, h, 0)
		var ray := PhysicsRayQueryParameters3D.create(o, o + dir * 2.0, 1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			print("[autotest]       +%.2f m: clear for 2 m" % h)
			continue
		var who: Object = hit["collider"]
		print("[autotest]       +%.2f m: %s at %.2f m, %s" % [h, who.name if who else "?",
			o.distance_to(hit["position"]), hit["position"]])
	# The rays are the passage; this is the body. When the two disagree the body is right.
	for line: String in caver.debug_contacts(dir):
		print("[autotest]       " + line)

# ---------------------------------------------------------------- test helpers

func _put_in(id: String, t: float) -> void:
	caver.teleport(cave.point_in(id, clampf(t, 0.0, 1.0)) + Vector3(0, 0.12, 0),
		cave.heading_in(id, clampf(t, 0.0, 1.0)))
	for i in 40:
		await get_tree().physics_frame

func _section_width(b: Bore, i: int) -> float:
	var sec: PackedVector2Array = b.sections[clampi(i, 0, b.sections.size() - 1)]
	var lo := INF
	var hi := -INF
	for p: Vector2 in sec:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return hi - lo

func _mesh_children() -> int:
	var n := 0
	for c in cave.get_children():
		if c is MeshInstance3D:
			n += 1
	return n

func _all_nodes(root: Node) -> Array:
	var out: Array = [root]
	for c in root.get_children():
		out.append_array(_all_nodes(c))
	return out
