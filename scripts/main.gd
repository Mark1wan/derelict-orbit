extends Node3D
## Entry point. Handles the WebXR session (Quest 3 browser) with a desktop fallback,
## the start screen, environment lighting, and ambient audio per power state.

var webxr: WebXRInterface
@onready var player: Player = $Player
@onready var station: Station = $Station
@onready var env_node: WorldEnvironment = $WorldEnvironment
@onready var ui: CanvasLayer = $UI

var env: Environment
var status: Label
var vr_btn: Button
var desk_btn: Button

func _ready() -> void:
	_make_env()
	_make_ui()
	Game.power_changed.connect(_on_power)

	webxr = XRServer.find_interface("WebXR")
	if webxr:
		webxr.session_supported.connect(_on_session_supported)
		webxr.session_started.connect(_on_session_started)
		webxr.session_ended.connect(_on_session_ended)
		webxr.session_failed.connect(_on_session_failed)
		status.text = "Checking for a VR headset..."
		webxr.is_session_supported("immersive-vr")
	else:
		status.text = "WebXR not available here. Desktop mode."
	if OS.has_environment("DERELICT_AUTOTEST"):
		_autotest()
	if OS.has_environment("DERELICT_SHOTS"):
		_photo_mode(OS.get_environment("DERELICT_SHOTS"))

## Review tool: DERELICT_SHOTS=/some/dir godot --path .   (windowed, not headless)
## Starts desktop mode, jumps the camera through a list of viewpoints and saves a PNG of each,
## by day and again with the power off, then quits.
func _photo_mode(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_start_desktop()
	await get_tree().create_timer(1.8).timeout
	player.hud_label.visible = false
	player.wrist.visible = false
	# DERELICT_SHOTS_ONLY=sky renders just the sky and window-light shots
	var only_sky := OS.get_environment("DERELICT_SHOTS_ONLY") == "sky"
	if only_sky and station.has_method("place_name"):
		await _sky_shots(dir)
		print("[shots] done -> ", dir)
		get_tree().quit()
		return
	var shots: Array = station.viewpoints()
	for sh in shots:
		await _shot(dir, sh[0], sh[1], sh[2])
	if station.has_method("place_name"):
		await _item_shots(dir)
		await _sky_shots(dir)
	# night: power off, flashlight on
	station.set_power(false)
	_on_power(false)
	player.flashlight_on = true
	player.flashlight.visible = true
	var night: Array = station.viewpoints()
	for i in mini(4, night.size()):
		var sh: Array = night[i]
		await _shot(dir, "night_" + sh[0], sh[1], sh[2])
	print("[shots] done -> ", dir)
	get_tree().quit()

## The kit: the belt seen from above, a tool floating on the deck, the wrench up at its terminal.
func _item_shots(dir: String) -> void:
	var eye := station.wake_point()
	player.desk_slot(1)                     # flashlight onto the belt too, so the belt is full
	await _shot(dir, "kit_belt", eye, eye + Vector3(0, -1.0, -0.35))
	player.desk_slot(1)
	var loose := get_tree().get_nodes_in_group(Item.GROUP)
	if not loose.is_empty():
		var it := loose[0] as Item
		var p := it.global_position
		var rc := StationLayout.world(station.layout.node_of(p), 1.4)
		await _shot(dir, "kit_loose_" + it.kind, p + (rc - p).normalized() * 1.2 + Vector3(0, 0.15, 0), p)
	for id in station.interactables:
		var term: Interactable = station.interactables[id]
		if term.tool == Item.WRENCH:
			player.debug_equip(Item.WRENCH)
			var tp := term.global_position
			await _shot(dir, "kit_wrench_at_terminal", tp + term.global_transform.basis.z * 1.0 + Vector3(0.15, -0.05, 0), tp)
			player.debug_equip(Item.FLASHLIGHT)
			break

## The sky out of a window at noon, afternoon, sunset, in the Earth's shadow and at sunrise; then
## a window the sun comes straight through, seen from inside with its shaft and the patch it throws.
func _sky_shots(dir: String) -> void:
	var orbit: Orbit = Game.orbit
	var ws: WindowSun = station.window_sun
	if orbit == null or ws == null or ws.windows.is_empty():
		return
	# a window with nothing of the station outside it, facing the Earth as much as possible
	player.belt.visible = false
	var view: WindowSun.Pane = null
	var view_score := -2.0
	for p: WindowSun.Pane in ws.windows:
		if ws.clear_to_sun(p, p.normal):
			var sc := p.normal.dot(orbit.earth_dir)
			if sc > view_score:
				view_score = sc
				view = p
	print("[shots] %d outside windows, clear view: %s" % [ws.windows.size(), "yes" if view else "none"])
	if view:
		var eye := view.center - view.normal * 1.2
		var look := view.center + view.normal * 10.0 + orbit.earth_dir * 4.0
		for sh: Array in [["noon", 0.0], ["afternoon", 70.0], ["sunset", 116.0], ["eclipse", 180.0], ["sunrise", -117.0]]:
			orbit.hold(sh[1])
			await _shot(dir, "sky_" + sh[0], eye, look)
	# find a sun angle that comes squarely through some window
	var best: WindowSun.Pane = null
	var best_angle := 0.0
	var best_score := 0.25
	for p: WindowSun.Pane in ws.windows:
		for a in range(-100, 105, 10):
			orbit.set_angle(float(a))
			var f := p.normal.dot(orbit.sun_dir)
			if f > best_score and orbit.sun_visible > 0.9 and ws.clear_to_sun(p, orbit.sun_dir):
				best_score = f
				best = p
				best_angle = float(a)
	if best:
		orbit.hold(best_angle)
		var travel := -orbit.sun_dir
		var q := PhysicsRayQueryParameters3D.create(best.center + travel * 0.3, best.center + travel * 15.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var patch: Vector3 = hit["position"] if not hit.is_empty() else best.center + travel * 4.0
		var eye := best.center - best.normal * 0.9 + best.u.normalized() * 1.1
		player.teleport_head_to(eye)
		ws.refresh_now()
		var on := 0
		for p: WindowSun.Pane in ws.windows:
			if p.light.visible:
				on += 1
		print("[shots] window light: facing %.2f, %d window lights on, patch %.1f m from the glass" % [best_score, on, patch.distance_to(best.center)])
		player.flashlight.visible = false
		await _shot(dir, "sky_window_light", eye, (best.center + patch) * 0.5)
		# the same with the station's own lights out, so only the sunlight is left
		for l in station.lights:
			l.visible = false
		await _shot(dir, "sky_window_light_sunonly", eye, (best.center + patch) * 0.5)
		var eye2 := patch + (best.center - patch) * 0.3 + best.u.normalized() * 1.2
		await _shot(dir, "sky_window_shaft_sunonly", eye2, best.center)
		for l in station.lights:
			l.visible = true
		player.flashlight.visible = player.flashlight_on
	else:
		print("[shots] no window takes direct sun on this deck")
	orbit.release()
	player.belt.visible = true

func _shot(dir: String, name_: String, pos: Vector3, target: Vector3) -> void:
	player.teleport_head_to(pos)
	player.look_at_point(target)
	player.velocity = Vector3.ZERO
	for i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name_ + ".png"))

## Headless smoke test: drives the whole loop without a human. Run with
## DERELICT_AUTOTEST=1 godot --headless --path . --quit-after 3000
func _autotest() -> void:
	var haunt = $Haunt
	print("[autotest] start desktop")
	_start_desktop()
	await get_tree().create_timer(2.0).timeout
	assert(Game.phase == Game.Phase.DAY, "should be DAY")
	print("[autotest] day %d tasks: %s" % [Game.day, str(Game.tasks)])
	var meshes := 0
	for n in station.root.get_children():
		if n is MeshInstance3D:
			meshes += 1
	print("[autotest] deck %s: %d corridor cells, %d rooms, %d merged meshes" % [station.layout_label(), station.layout.corridor.size(), station.layout.rooms.size(), meshes])
	# locomotion: thrusters burn fuel and move you; a grab pulls the body toward the anchor
	Input.action_press("d_forward")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("d_forward")
	print("[autotest] thrust: fuel=%.2f speed=%.2f" % [player.fuel, player.velocity.length()])
	assert(player.fuel < 0.9 and player.velocity.length() > 0.3, "thrusters should burn fuel and move")
	player.velocity = Vector3.ZERO
	var before := player.camera.global_position
	player.debug_grab_pull(Vector3(0.6, 0, 0))
	await get_tree().create_timer(0.5).timeout
	var moved := player.camera.global_position - before
	player.debug_release()
	print("[autotest] grab pull moved %s (hand offset +0.6 x)" % moved)
	assert(moved.x < -0.3 and absf(moved.z) < 0.2, "a grab should pull the body opposite to the hand offset")
	# tool belt: on the desktop you start holding the flashlight, the wrench is in holster 3
	assert(player.held_kind() == Item.FLASHLIGHT, "desktop should start holding the flashlight")
	assert(player.belt.slot_of(Item.WRENCH) == 2, "the wrench should start in holster 3")
	player.desk_slot(2)
	assert(player.held_kind() == Item.WRENCH and player.belt.slot_of(Item.FLASHLIGHT) == 2, "a number key swaps hand and holster")
	var wrench: Item = player.held_item()
	player.debug_let_go()
	await get_tree().create_timer(0.5).timeout
	assert(player.held_kind() == "" and wrench.where == Item.Where.WORLD and wrench.is_in_group(Item.GROUP), "Q lets the wrench float off")
	var drifted := wrench.global_position.distance_to(player.camera.global_position)
	assert(player.pick_up_nearest(), "the drifting wrench should be catchable")
	assert(player.held_kind() == Item.WRENCH, "caught the wrench")
	player.desk_slot(2)
	assert(player.held_kind() == Item.FLASHLIGHT and player.belt.slot_of(Item.WRENCH) == 2, "back to the starting kit")
	var loose_kinds := []
	for n in get_tree().get_nodes_in_group(Item.GROUP):
		loose_kinds.append((n as Item).kind)
	assert(loose_kinds.has(Item.SCANNER) and loose_kinds.has(Item.MULTITOOL), "the scanner and multitool should be out on the deck")
	print("[autotest] belt ok: swap, let go (%.2f m away), catch, holster. On the deck: %s" % [drifted, loose_kinds])
	# rotation: spin from the thrusters keeps going after the input stops, a hand on the station stops it
	Game.comfort_snap = false
	var fwd0 := -player.camera.global_transform.basis.z
	var up0 := player.origin.global_basis.y
	for i in 30:
		player.apply_rotation_input(Vector3(0.0, 0.0, 1.0), 1.0 / 30.0)
		await get_tree().physics_frame
	var spin := player.ang_vel.length()
	await get_tree().create_timer(0.5).timeout
	var rolled := rad_to_deg(up0.angle_to(player.origin.global_basis.y))
	assert(spin > 0.5 and player.ang_vel.length() > spin * 0.8, "spin should keep going once the thrusters stop")
	assert(rolled > 30.0 and fwd0.angle_to(-player.camera.global_transform.basis.z) < 0.35, "a roll turns the body about the view axis")
	var belt_err := player.belt.global_position.distance_to(player.camera.global_position - player.origin.global_basis.y * ToolBelt.DROP)
	assert(belt_err < 0.05, "the belt should stay at the waist whichever way up the body is")
	player.debug_grab_pull(Vector3.ZERO)
	await get_tree().create_timer(0.2).timeout
	player.debug_release()
	assert(player.ang_vel.length() < 0.01, "a hand on the station should stop the spin")
	Game.comfort_snap = true
	var up_snap := player.origin.global_basis.y
	player.apply_rotation_input(Vector3(1.0, 0.0, 0.0), 0.016)
	var snapped := rad_to_deg(up_snap.angle_to(player.origin.global_basis.y))
	assert(absf(snapped - 30.0) < 1.0, "comfort mode should pitch in 30 degree snaps")
	player.apply_rotation_input(Vector3.ZERO, 0.016)
	Game.comfort_snap = false
	player.reset_orientation()
	assert(player.origin.global_basis.y.angle_to(Vector3.UP) < 0.01, "reset should stand the body upright")
	print("[autotest] rotation ok: spin %.2f rad/s kept after release, rolled %.0f deg, belt at the waist, grab stops it, snap %.0f deg" % [spin, rolled, snapped])
	# the orbit: the sun is up at noon and hidden behind the Earth at midnight
	var orbit: Orbit = Game.orbit
	orbit.hold(0.0)
	assert(orbit.sun_visible > 0.99, "the sun should be up at noon")
	orbit.hold(180.0)
	assert(orbit.sun_visible < 0.01, "the sun should be behind the Earth at midnight")
	orbit.release()
	print("[autotest] orbit ok: %d outside windows on this deck" % station.window_sun.windows.size())
	# force a few day events of every kind
	for kind in ["shadow", "bang", "flicker", "whisper", "watcher", "drift", "blackout", "shadow_close"]:
		haunt._fire_day_event(9.0)
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(3.5).timeout
	# complete tasks the way a player must: fetch the tool each terminal names, then hold trigger on it
	for t in Game.tasks:
		var it: Interactable = station.interactables[t["id"]]
		assert(it.tool != "", "%s should need a tool" % t["id"])
		assert(not it.hold(0.5, Item.FLASHLIGHT) and it.progress == 0.0, "the wrong tool should do nothing")
		assert(player.debug_equip(it.tool), "could not get hold of the %s" % it.tool)
		player.teleport_head_to(it.global_position + it.global_transform.basis.z * 1.5)
		var guard := 0
		while not it.done and guard < 600:
			it.hold(0.05, player.held_kind())
			guard += 1
		print("[autotest] completed %s with the %s (done=%s)" % [t["id"], it.tool, it.done])
	assert(Game.phase == Game.Phase.SLEEP, "all tasks done -> SLEEP")
	await get_tree().create_timer(7.0).timeout
	assert(Game.phase == Game.Phase.NIGHT, "should be NIGHT")
	assert(not Game.power_on, "power should be off")
	print("[autotest] night, player head at %s stalker at %s" % [player.camera.global_position, haunt.stalker.global_position])
	# let the stalker walk a bit with flashlight off
	player.flashlight_on = false
	await get_tree().create_timer(3.0).timeout
	print("[autotest] stalker moved to %s lit=%s" % [haunt.stalker.global_position, haunt.stalker.is_lit(player)])
	assert((Game.orbit as Orbit).sun_visible < 0.01, "night should be the Earth's shadow")
	# restore power
	var pp: Interactable = station.interactables["power"]
	player.teleport_head_to(pp.global_position + pp.global_transform.basis.z * 1.5)
	var g := 0
	while not pp.done and g < 600:
		pp.hold(0.05)
		g += 1
	assert(Game.phase == Game.Phase.DAY and Game.day == 2, "power restored -> DAY 2")
	print("[autotest] day 2 ok, intensity %.1f" % Game.intensity())
	# fast-forward to night 2 and get caught
	Game.day_time = Game.DAY_LENGTH + 1.0
	await get_tree().create_timer(8.0).timeout
	assert(Game.phase == Game.Phase.NIGHT, "should be NIGHT 2")
	haunt.stalker.global_position = player.camera.global_position + Vector3(0.5, 0, 0)
	await get_tree().create_timer(1.5).timeout
	assert(Game.phase == Game.Phase.DEAD, "should be DEAD")
	print("[autotest] caught ok, restarting")
	Game.restart()
	await get_tree().create_timer(0.5).timeout
	assert(Game.phase == Game.Phase.DAY and Game.day == 1, "restart -> DAY 1")
	print("[autotest] ALL OK  station children=%d" % station.get_child_count())
	get_tree().quit()

func _make_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.8)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# a whisper of depth fog: corridors read as long, the far end of a room goes soft
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.04, 0.06)
	env.fog_density = 0.018
	env.fog_sky_affect = 0.0
	env_node.environment = env
	# the sky, the Earth and the sun - and where the sun is, which is where the light comes from
	var orbit := Orbit.new()
	orbit.name = "Orbit"
	add_child(orbit)
	orbit.attach(env)

func _make_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "DERELICT ORBIT"
	title.add_theme_font_size_override("font_size", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Station Kestrel-9  -  zero-G maintenance shift\nKeep it running by day. Survive the dark by night."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.7, 0.8, 0.9)
	box.add_child(sub)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.modulate = Color(0.6, 0.9, 0.7)
	box.add_child(status)
	vr_btn = Button.new()
	vr_btn.text = "  ENTER VR  "
	vr_btn.visible = false
	vr_btn.add_theme_font_size_override("font_size", 30)
	vr_btn.pressed.connect(_enter_vr)
	box.add_child(vr_btn)
	desk_btn = Button.new()
	desk_btn.text = "  Play on desktop (WASD + mouse)  "
	desk_btn.pressed.connect(_start_desktop)
	box.add_child(desk_btn)
	var comfort := CheckButton.new()
	comfort.text = "VR comfort: rotate in 30 degree snaps instead of a smooth spin"
	comfort.button_pressed = Game.comfort_snap
	comfort.toggled.connect(func(on: bool) -> void: Game.comfort_snap = on)
	box.add_child(comfort)
	var help := Label.new()
	help.text = "VR: GRIP an empty hand on anything to pull yourself - GRIP an item to hold it, let go over a belt holster to stow it - trigger = use the held tool - sticks = thrusters - hold B + sticks = rotate - A/X flashlight\nDesktop: RIGHT MOUSE grab + drag - WASD/Space/C thrusters - R + mouse = roll/pitch - 1-4 swap hand with belt - Q let go - E/click pick up or use - F flashlight"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(0.5, 0.55, 0.6)
	help.add_theme_font_size_override("font_size", 13)
	box.add_child(help)

# ---------------------------------------------------------------- WebXR
func _on_session_supported(session_mode: String, supported: bool) -> void:
	if session_mode != "immersive-vr":
		return
	vr_btn.visible = supported
	status.text = "VR headset ready." if supported else "No immersive VR available in this browser."

func _enter_vr() -> void:
	webxr.session_mode = "immersive-vr"
	webxr.requested_reference_space_types = "local-floor, local"
	webxr.required_features = "local"
	webxr.optional_features = "local-floor"
	if not webxr.initialize():
		status.text = "Failed to start the VR session."

func _on_session_started() -> void:
	get_viewport().use_xr = true
	ui.visible = false
	_begin(true)

func _on_session_ended() -> void:
	get_viewport().use_xr = false
	ui.visible = true
	status.text = "VR session ended. Reload to play again."

func _on_session_failed(message: String) -> void:
	status.text = "VR failed: " + message

func _start_desktop() -> void:
	ui.visible = false
	_begin(false)

func _begin(xr: bool) -> void:
	player.begin(xr)
	player.teleport_head_to(station.start_point())
	Sfx.set_ambient("hum")
	await get_tree().create_timer(1.2).timeout
	Game.start_game()

## Dev shortcut (desktop keyboard): Ctrl+Shift+N ends the current shift immediately.
func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.ctrl_pressed and e.shift_pressed and e.keycode == KEY_N:
		if Game.phase == Game.Phase.DAY:
			Game.day_time = Game.DAY_LENGTH + 1.0

# ---------------------------------------------------------------- power / mood
func _on_power(on: bool) -> void:
	env.ambient_light_energy = 0.12 if on else 0.008
	env.fog_density = 0.018 if on else 0.045
	env.fog_light_color = Color(0.03, 0.04, 0.06) if on else Color(0.004, 0.003, 0.004)
	if on:
		Sfx.set_ambient("hum", -12.0)
		if Game.nights_survived > 0:
			Sfx.play("powerup", -4.0)
	else:
		Sfx.set_ambient("drone", -9.0)
