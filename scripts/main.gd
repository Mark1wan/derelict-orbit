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
var touch_btn: Button
var touch_ui: TouchControls
var touch_device := false

func _ready() -> void:
	# playtest shortcut straight to the spacewalk day: ?eva in the URL, or DERELICT_EVA=1
	if OS.has_environment("DERELICT_EVA"):
		Game.start_day = 3
	elif OS.has_feature("web"):
		var eva: Variant = JavaScriptBridge.eval("/[?&]eva\\b/.test(location.search) ? 1 : 0", true)
		if eva != null and int(eva) == 1:
			Game.start_day = 3
	touch_device = Game.is_touch_device()
	if touch_device:
		# a smaller base size: the 2D UI comes out at thumb size on a phone held sideways
		get_window().content_scale_size = Vector2i(800, 450)
		Game.low_quality = true
	_make_env()
	_make_ui()
	_make_touch_ui()
	get_tree().root.size_changed.connect(func() -> void:
		if player.started and not player.xr_active:
			_apply_quality())
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
	if OS.get_environment("DERELICT_AUTOTEST") == "touch":
		_autotest_touch()
	elif OS.get_environment("DERELICT_AUTOTEST") == "eva":
		_autotest_eva()
	elif OS.get_environment("DERELICT_AUTOTEST") == "routes":
		_survey_routes()
	elif OS.has_environment("DERELICT_AUTOTEST"):
		_autotest()
	if OS.has_environment("DERELICT_SHOTS"):
		_photo_mode(OS.get_environment("DERELICT_SHOTS"))

## Review tool: DERELICT_SHOTS=/some/dir godot --path .   (windowed, not headless)
## Starts desktop mode, jumps the camera through a list of viewpoints and saves a PNG of each,
## by day and again with the power off, then quits.
func _photo_mode(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	if OS.get_environment("DERELICT_SHOTS_ONLY") == "touch":
		await _touch_shots(dir)
		print("[shots] done -> ", dir)
		get_tree().quit()
		return
	if OS.get_environment("DERELICT_SHOTS_ONLY") == "eva":
		await _eva_shots(dir)
		print("[shots] done -> ", dir)
		get_tree().quit()
		return
	_start_desktop()
	await get_tree().create_timer(1.8).timeout
	player.hud_label.visible = false
	player.wrist.visible = false
	# DERELICT_SHOTS_ONLY=sky renders just the sky and window-light shots
	var only_sky := OS.get_environment("DERELICT_SHOTS_ONLY") == "sky"
	if OS.get_environment("DERELICT_SHOTS_ONLY") == "hud" and station.has_method("place_name"):
		await _item_shots(dir)
		print("[shots] done -> ", dir)
		get_tree().quit()
		return
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
	# the crew terminal hologram: on the desktop, then projected from a posed left wrist as in VR
	player.wrist.visible = true
	player.wrist.set_open(true)
	await get_tree().create_timer(0.4).timeout
	await _shot(dir, "hud_terminal", eye, eye + Vector3(0, 0, -3))
	player.debug_preview_wrist(true)
	await get_tree().create_timer(0.2).timeout
	await _shot(dir, "hud_terminal_wrist", eye, eye + Vector3(0, -0.35, -1))
	player.debug_preview_wrist(false)
	player.wrist.visible = false
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
	var hull := 0
	for n in station.root.get_children():
		if n is MeshInstance3D:
			meshes += 1
			if n.name.begins_with("c") or n.name.begins_with("room"):
				hull += 1
	print("[autotest] deck %s: %d corridor cells, %d rooms, %d hull meshes + %d other meshes" % [station.layout_label(), station.layout.corridor.size(), station.layout.rooms.size(), hull, meshes - hull])
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
	# the crew terminal: TAB toggles the hologram
	var was_open := player.wrist.is_open
	Input.action_press("d_menu")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("d_menu")
	assert(player.wrist.is_open != was_open, "TAB should toggle the crew terminal")
	player.toggle_panel()
	assert(player.wrist.is_open == was_open, "and toggle it back")
	print("[autotest] crew terminal ok: TAB toggles the hologram")
	# the uplink: Gateway hails, the console prints what it says, and the hold sends the report back
	assert(station.comms != null, "the deck should have a comms console")
	assert(Comms.entries.has("d1_in"), "comms/log.json should have loaded")
	Comms.debug_hail()
	await get_tree().create_timer(0.6).timeout
	assert(Comms.is_playing(), "%s should be transmitting" % Comms.ground)
	var console := Comms.console as CommsStation
	assert(console != null and console.body.text != "", "the console should print the message")
	Comms.debug_finish()
	await get_tree().process_frame
	assert(Comms.reply_pending, "a shift report should be due once Gateway has finished")
	station.comms.hold(3.0)
	await get_tree().create_timer(0.3).timeout
	assert(not Comms.reply_pending and Comms.is_playing(), "holding the console should key the mic and answer")
	Comms.debug_finish()
	print("[autotest] uplink ok: %s hails, the console prints it, the report goes back (%d entries)" % [Comms.ground, Comms.entries.size()])
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
	# the chupacabra is built on its own rig, which has none of the stalker's poses: force a few,
	# lurking, withdrawing and bolting, and check it only ever asks for poses its rig has
	var corners: Array = station.corner_spots()
	for i in 4:
		var spot: Array = corners[(i * 7) % corners.size()]
		var beast := Chupacabra.new()
		haunt.add_child(beast)
		beast.lurk_at(spot[0], spot[1])
		var poses: Dictionary = beast.body._rig["poses"]
		assert(poses.has(beast.body.idle_pose) and poses.has(beast.body.twitch_pose), "the chupacabra's idle poses should be in its own rig")
		await get_tree().create_timer(0.2).timeout
		if i % 2 == 0:
			beast._withdraw()
		else:
			beast._state = Chupacabra.State.COIL
			beast._t = 0.0
			beast.body.set_pose("coil", true)
		await get_tree().create_timer(1.2).timeout
		assert(not is_instance_valid(beast), "the chupacabra should be gone after it leaves")
	print("[autotest] chupacabra ok: 4 forced (withdraw, bolt)")
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
	Game.day_time = Game.day_length() + 1.0
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

## Touch controls, headless: DERELICT_TOUCH=1 DERELICT_AUTOTEST=touch godot --headless --path .
## Fingers are fed straight to TouchControls, in its own 2D coordinates.
func _autotest_touch() -> void:
	print("[touch-test] start")
	# headless has no real window to be landscape: pin the 2D layout to the 800x450 base
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_start_touch()
	await get_tree().create_timer(2.0).timeout
	assert(Game.phase == Game.Phase.DAY and Game.touch, "should be a touch DAY")
	var tc := touch_ui
	var sz := tc.size
	print("[touch-test] controls %s, low graphics %s, 3D scale %.2f, msaa %d" % [sz, Game.low_quality, get_viewport().scaling_3d_scale, get_viewport().msaa_3d])
	assert(tc.visible and sz.x > sz.y, "the controls should be up, landscape")
	assert(not Game.low_quality or get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "low graphics should drop MSAA")
	# a mouse event made up from a touch must not turn the view or grab the pointer
	var basis0 := player.camera.global_transform.basis
	var em := InputEventMouseMotion.new()
	em.device = InputEvent.DEVICE_ID_EMULATION
	em.relative = Vector2(300, 120)
	player._unhandled_input(em)
	assert(player.camera.global_transform.basis.is_equal_approx(basis0) and not player.mouse_captured, "an emulated mouse should be ignored")
	# left thumb pushed up: forward thrust
	player.velocity = Vector3.ZERO
	var fuel0 := player.fuel
	var fwd := -player.camera.global_transform.basis.z
	var s0 := Vector2(150, sz.y - 110)
	tc.finger_down(0, s0)
	tc.finger_move(0, s0 + Vector2(0, -80))
	assert(Input.get_action_strength("d_forward") > 0.9, "the stick pushed up should press forward")
	await get_tree().create_timer(0.3).timeout
	tc.finger_up(0, s0)
	assert(Input.get_action_strength("d_forward") == 0.0, "lifting the thumb should stop the burn")
	print("[touch-test] stick: fuel %.2f -> %.2f, speed along the view %.2f" % [fuel0, player.fuel, player.velocity.dot(fwd)])
	assert(player.fuel < fuel0 and player.velocity.dot(fwd) > 0.2, "the stick should fire the thrusters")
	player.velocity = Vector3.ZERO
	# one finger dragged right on the look side: turn right
	var right0 := player.camera.global_transform.basis.x
	var l0 := Vector2(sz.x * 0.62, sz.y * 0.4)
	tc.finger_down(1, l0)
	for k in 6:
		tc.finger_move(1, l0 + Vector2(15.0 * (k + 1), 0))
	tc.finger_up(1, l0 + Vector2(90, 0))
	var fwd1 := -player.camera.global_transform.basis.z
	print("[touch-test] look: a 90 px drag turned %.0f deg" % rad_to_deg(fwd.angle_to(fwd1)))
	assert(fwd1.dot(right0) > 0.2, "dragging right should turn right")
	# press and hold on a wall in reach, drag down: the body is pulled up; lift: let go
	var term: Interactable = station.interactables.values()[0]
	player.teleport_head_to(term.global_position + term.global_transform.basis.z * 0.9)
	player.look_at_point(term.global_position)
	await get_tree().physics_frame
	var c := sz * 0.5
	tc.finger_down(2, c)
	await get_tree().create_timer(0.45).timeout
	assert(player.d_grabbing, "a finger resting on the wall in reach should take hold")
	var head0 := player.camera.global_position
	var up := player.camera.global_transform.basis.y
	for k in 5:
		tc.finger_move(2, c + Vector2(0, 20.0 * (k + 1)))
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	var pulled := (player.camera.global_position - head0).dot(up)
	tc.finger_up(2, c + Vector2(0, 100))
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[touch-test] grab: took hold after %.2f s, dragging the wall down 100 px pulled the body up %.2f m" % [TouchControls.LONG_PRESS, pulled])
	assert(pulled > 0.15 and not player.d_grabbing, "the drag should pull and lifting should let go")
	player.velocity = Vector3.ZERO
	# two fingers twisted clockwise: the body rolls clockwise (the top of the head goes right)
	player.reset_orientation()
	await get_tree().physics_frame
	var right1 := player.camera.global_transform.basis.x
	var a := Vector2(sz.x * 0.55, sz.y * 0.35)
	tc.finger_down(3, a)
	tc.finger_down(4, a + Vector2(120, 0))
	await get_tree().create_timer(0.4).timeout
	assert(not player.d_grabbing, "two fingers should not grab")
	for k in 7:
		var ang := deg_to_rad(5.0 * k)
		tc.finger_move(4, a + Vector2(cos(ang), sin(ang)) * 120.0)
	tc.finger_up(4, a)
	tc.finger_up(3, a)
	var tilt := player.camera.global_transform.basis.y.dot(right1)
	print("[touch-test] twist: 30 deg clockwise rolled the head %.0f deg toward its right" % rad_to_deg(asin(clampf(tilt, -1.0, 1.0))))
	assert(tilt > 0.3, "a clockwise twist should roll clockwise")
	player.reset_orientation()
	# buttons: TASKS toggles the terminal, a belt button swaps the hand
	var was_open := player.wrist.is_open
	await _tap(tc.button_center("tasks"))
	assert(player.wrist.is_open != was_open, "TASKS should toggle the crew terminal")
	await _tap(tc.button_center("tasks"))
	var wslot := player.belt.slot_of(Item.WRENCH)
	await _tap(tc.button_center("belt%d" % wslot))
	assert(player.held_kind() == Item.WRENCH, "a belt button should swap the wrench into the hand")
	# USE held on a task terminal with its tool makes progress
	var task_term: Interactable = station.interactables[Game.tasks[0]["id"]]
	assert(player.debug_equip(task_term.tool), "could not get hold of the %s" % task_term.tool)
	player.teleport_head_to(task_term.global_position + task_term.global_transform.basis.z * 1.2)
	player.look_at_point(task_term.global_position)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var use_c := tc.button_center("use")
	tc.finger_down(8, use_c)
	await get_tree().create_timer(0.8).timeout
	var prog := task_term.progress
	tc.finger_up(8, use_c)
	print("[touch-test] USE: %s at %s with the %s, progress %.2f" % [task_term.id, task_term.room, task_term.tool, prog])
	assert(prog > 0.1, "holding USE on the terminal with its tool should make progress")
	# low graphics: only a couple of windows get sunlight
	var ws: WindowSun = station.window_sun
	if ws and Game.low_quality:
		(Game.orbit as Orbit).hold(0.0)
		ws.refresh_now()
		var on := 0
		for p: WindowSun.Pane in ws.windows:
			if p.light.visible:
				on += 1
		(Game.orbit as Orbit).release()
		print("[touch-test] low graphics: %d sunlit window lights" % on)
		assert(on <= WindowSun.MAX_LIT_LOW, "low graphics should light at most %d windows" % WindowSun.MAX_LIT_LOW)
	print("[touch-test] ALL OK")
	get_tree().quit()

## The spacewalk, headless: DERELICT_AUTOTEST=eva godot --headless --path .
## Starts on the mission day and does every step the way a player has to, tethering out along the
## anchor route for real (physics, collisions) and reporting any hop that needed help.
func _autotest_eva() -> void:
	print("[eva-test] start")
	Game.start_day = 3
	_start_desktop()
	await get_tree().create_timer(2.5).timeout
	assert(Game.phase == Game.Phase.DAY and Game.mission == "eva_solar" and Game.tasks.size() == Game.EVA_STEPS.size(), "day 3 should be the spacewalk")
	var al: Airlock = station.airlock
	var ex: Exterior = station.exterior
	assert(al != null and ex != null, "the EVA room should have its airlock, and the outside its anchors")
	print("[eva-test] deck %s: %d anchors, route ok %s (%d anchors long), wing %+d, shift %.0f s" % [station.layout_label(), ex.anchors.size(), ex.route_ok, ex.route.size(), int(ex.wing_side), Game.day_length()])
	assert(ex.route_ok, "a chain of anchors should reach the array")
	assert(not player.outside and not player.in_vacuum, "the start should be inside, in air")
	# 1. suit up
	var rack: Interactable = station.interactables["eva_suit"]
	assert(rack.active, "the suit rack should be the first step")
	var g := 0
	while not rack.done and g < 400:
		rack.hold(0.05, player.held_kind())
		g += 1
	assert(player.suit_on and Game.next_step_id() == "eva_cycle_out", "the rack should put the suit on")
	# 2. the airlock refuses from the room, cycles from inside the chamber
	player.teleport_head_to(al.room_point())
	al.debug_cycle()
	assert(al.state == Airlock.State.PRESSURIZED, "the airlock should not cycle with you outside the chamber")
	player.teleport_head_to(al.centre())
	await get_tree().physics_frame
	al.debug_cycle()
	assert(al.state == Airlock.State.DEPRESSURIZING, "inside the chamber, suited, it should cycle")
	await get_tree().create_timer(Airlock.CYCLE_TIME + 3.5).timeout
	print("[eva-test] airlock: %s, in vacuum %s, O2 %.3f" % [al.state, player.in_vacuum, player.suit_o2])
	assert(al.state == Airlock.State.VACUUM and player.in_vacuum and Game.next_step_id() == "eva_reach", "the chamber should be open to space")
	# 3. out along the anchors by tether
	player.teleport_head_to(al.exit_point())
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(player.outside, "past the outer hatch should count as outside")
	var o2_out := player.suit_o2
	var t0 := Time.get_ticks_msec()
	var reeled := 0
	var helped := 0
	for idx: int in ex.route:
		var target: Vector3 = ex.anchors[idx]
		if player.belt.global_position.distance_to(target) < 2.0:
			continue
		var ok := player.debug_tether_to(target)
		if ok:
			player.debug_reel(true)
			var t := 0.0
			while t < 10.0 and player.belt.global_position.distance_to(target) > Tether.MIN_LEN + 0.7:
				await get_tree().physics_frame
				t += 1.0 / 72.0
			player.debug_reel(false)
			ok = player.belt.global_position.distance_to(target) <= Tether.MIN_LEN + 0.7
		if ok:
			reeled += 1
		else:
			helped += 1
			print("[eva-test]   hop to anchor %d needed help (aim %s, %.1f m away)" % [idx, player.tether.latched, player.belt.global_position.distance_to(target)])
			player.tether.release()
			player.teleport_head_to(target + Vector3(0, 1.2, 0))
		player.velocity = player.velocity * 0.2
	await get_tree().create_timer(0.3).timeout
	print("[eva-test] tethered out: %d hops reeled, %d helped, %.1f s, O2 %.2f -> %.2f" % [reeled, helped, (Time.get_ticks_msec() - t0) / 1000.0, o2_out, player.suit_o2])
	assert(helped <= maxi(1, (reeled + helped) / 4), "most hops along the route should work by tether alone")
	assert(Game.next_step_id() == "eva_unbolt", "reaching the array should tick off the traverse")
	assert(player.suit_o2 < o2_out, "the suit should use air outside")
	# 4-5. the repair: wrench, then multitool
	for it: Interactable in [ex.unbolt, ex.splice]:
		assert(it.active, "%s should be up next" % it.id)
		assert(player.debug_equip(it.tool), "could not get hold of the %s" % it.tool)
		player.teleport_head_to(it.global_position + Vector3.UP * 1.2)
		g = 0
		while not it.done and g < 600:
			it.hold(0.05, player.held_kind())
			g += 1
		print("[eva-test] %s with the %s: done %s" % [it.id, it.tool, it.done])
	assert(Game.next_step_id() == "eva_return", "the array fixed, the last step is getting back in")
	# 6. back in and repressurize
	player.teleport_head_to(al.centre())
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	al.debug_cycle()
	await get_tree().create_timer(Airlock.CYCLE_TIME + 3.5).timeout
	assert(al.state == Airlock.State.PRESSURIZED, "the chamber should repressurize")
	assert(Game.phase == Game.Phase.SLEEP, "every step done -> SLEEP")
	await get_tree().create_timer(7.0).timeout
	assert(Game.phase == Game.Phase.NIGHT and not player.suit_on and not player.tether.latched, "night: suit off, tether in")
	print("[eva-test] ALL OK")
	get_tree().quit()

## Spacewalk routes over many decks: DERELICT_AUTOTEST=routes godot --headless --path .
## Every deck must have an airlock and a rope route to the array; prints how long each walk is.
func _survey_routes() -> void:
	var lengths := []
	var fails := 0
	for s in range(100, 4100, 250):
		station.regenerate(s)
		for i in 4:
			await get_tree().physics_frame
		var ex: Exterior = station.exterior
		var ok := ex != null and ex.route_ok
		if not ok:
			fails += 1
		var walk := 0.0
		if ok:
			var prev: Vector3 = station.airlock.exit_point()
			for idx: int in ex.route:
				walk += prev.distance_to(ex.anchors[idx])
				prev = ex.anchors[idx]
			lengths.append(ex.route.size())
		print("[routes] deck %04d: airlock %s, route %s, %d anchors, %.0f m of rope" % [s, station.airlock != null, ok, ex.route.size() if ex else 0, walk])
	print("[routes] %d decks, %d without a route, anchors per route %s" % [16, fails, lengths])
	assert(fails == 0, "every deck should have a route")
	get_tree().quit()

## Review shots of the spacewalk: the hatch, the chamber through the visor, the open outer hatch,
## the station from outside, a tether latched on, the damaged array, and the whole route.
func _eva_shots(dir: String) -> void:
	Game.start_day = 3
	_start_desktop()
	await get_tree().create_timer(3.0).timeout
	player.hud_label.visible = false
	player.wrist.visible = false
	var al: Airlock = station.airlock
	var ex: Exterior = station.exterior
	var orbit: Orbit = Game.orbit
	orbit.hold(-20.0)
	var out := al.outward()
	await _shot(dir, "eva_hatch", al.room_point() - out * 2.5, al.room_point() + out * 4.0)
	player.set_suit(true)
	player.hud_label.visible = false
	await _shot(dir, "eva_chamber", al.centre() - out * 1.6, al.centre() + out * 3.0)
	al.state = Airlock.State.VACUUM
	await get_tree().create_timer(2.5).timeout
	await _shot(dir, "eva_open_hatch", al.centre() - out * 1.2, al.exit_point() + out * 6.0)
	await _shot(dir, "eva_station_from_outside", al.exit_point() + out * 7.0 + Vector3(0, 4.0, 0), al.centre())
	if ex.route.size() > 2:
		var first: Vector3 = ex.anchors[ex.route[1]]
		player.teleport_head_to(al.exit_point() + Vector3(0, 0.6, 0))
		player.look_at_point(first)
		player.debug_tether_to(first)
		await get_tree().create_timer(0.5).timeout
		await _save(dir, "eva_tether")
		player.tether.release()
	await _shot(dir, "eva_site", ex.site + Vector3(-ex.wing_side * 3.2, 2.6, -3.4), ex.site + Vector3(ex.wing_side * 1.5, 0, 2.0))
	await _shot(dir, "eva_route_overview", ex.site + Vector3(-ex.wing_side * 16.0, 14.0, 26.0), ex.site + Vector3(-ex.wing_side * 14.0, -6.0, 0))
	orbit.release()

func _tap(p: Vector2) -> void:
	touch_ui.finger_down(9, p)
	await get_tree().physics_frame
	await get_tree().physics_frame
	touch_ui.finger_up(9, p)
	await get_tree().physics_frame

## Review shots of the phone UI: the title, play with the controls idle, a thumb on the stick and a
## finger holding the wall, the 3D view at half resolution, and the phone held upright.
func _touch_shots(dir: String) -> void:
	await get_tree().create_timer(1.2).timeout
	await _save(dir, "touch_title")
	_start_touch()
	await get_tree().create_timer(2.5).timeout
	var term: Interactable = station.interactables.values()[0]
	player.teleport_head_to(term.global_position + term.global_transform.basis.z * 1.4 + term.global_transform.basis.x * 0.4)
	player.look_at_point(term.global_position)
	await get_tree().create_timer(0.3).timeout
	await _save(dir, "touch_play")
	player.hud_label.visible = false
	var sz := touch_ui.size
	touch_ui.finger_down(0, Vector2(160, sz.y - 120))
	touch_ui.finger_move(0, Vector2(185, sz.y - 165))
	touch_ui.finger_down(1, sz * 0.5 + Vector2(130, -10))
	await get_tree().create_timer(0.5).timeout
	await _save(dir, "touch_grab")
	touch_ui.release_all()
	player.velocity = Vector3.ZERO
	player.wrist.set_open(false)
	get_viewport().scaling_3d_scale = 0.5
	await get_tree().create_timer(0.4).timeout
	await _save(dir, "touch_scale50")
	_apply_quality()
	get_window().size = Vector2i(405, 760)
	await get_tree().create_timer(0.8).timeout
	await _save(dir, "touch_portrait")

func _save(dir: String, name_: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir.path_join(name_ + ".png"))

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
	# phones and tablets: on-screen controls (TouchControls)
	touch_btn = Button.new()
	touch_btn.text = "  PLAY  "
	touch_btn.visible = touch_device
	touch_btn.add_theme_font_size_override("font_size", 30)
	touch_btn.pressed.connect(_start_touch)
	box.add_child(touch_btn)
	desk_btn = Button.new()
	desk_btn.text = "  Play with keyboard + mouse  " if touch_device else "  Play on desktop (WASD + mouse)  "
	desk_btn.pressed.connect(_start_desktop)
	box.add_child(desk_btn)
	var comfort := CheckButton.new()
	comfort.text = "VR comfort: rotate in 30 degree snaps instead of a smooth spin"
	comfort.button_pressed = Game.comfort_snap
	comfort.toggled.connect(func(on: bool) -> void: Game.comfort_snap = on)
	comfort.visible = not touch_device
	box.add_child(comfort)
	var gfx := CheckButton.new()
	gfx.text = "Low graphics (smoother on phones)"
	gfx.button_pressed = Game.low_quality
	gfx.toggled.connect(func(on: bool) -> void: Game.low_quality = on)
	gfx.visible = touch_device
	box.add_child(gfx)
	var help := Label.new()
	if touch_device:
		help.text = "Hold the phone sideways. Left thumb: thrusters. Right side: drag to look.\nPress and hold a wall to grab it, then drag to pull yourself. Two fingers twist to roll.\nUSE works a terminal with the right tool. The belt buttons swap what is in your hand."
		help.add_theme_font_size_override("font_size", 14)
	else:
		help.text = "VR: GRIP an empty hand on anything to pull yourself - GRIP an item to hold it, let go over a belt holster to stow it - trigger = use the held tool - sticks = thrusters - hold B + sticks = rotate - A/X flashlight - Y = crew terminal\nDesktop: RIGHT MOUSE grab + drag - WASD/Space/C thrusters - R + mouse = roll/pitch - TAB = crew terminal - 1-4 swap hand with belt - Q let go - E/click pick up or use - F flashlight"
		help.add_theme_font_size_override("font_size", 13)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(0.5, 0.55, 0.6)
	box.add_child(help)

func _make_touch_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TouchLayer"
	layer.layer = 2
	add_child(layer)
	touch_ui = TouchControls.new()
	touch_ui.player = player
	touch_ui.visible = false
	layer.add_child(touch_ui)
	touch_ui.debug_log = OS.has_environment("DERELICT_TOUCH_DEBUG")
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search.indexOf('touchdebug') >= 0 ? 1 : 0", true)
		touch_ui.debug_log = touch_ui.debug_log or (q != null and int(q) == 1)
	if touch_ui.debug_log:
		# where to tap PLAY, for the browser phone test
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			print("[touch] play button %s in a %s view, window %s" % [touch_btn.get_global_rect(), get_viewport().get_visible_rect().size, get_window().size]))

# ---------------------------------------------------------------- WebXR
func _on_session_supported(session_mode: String, supported: bool) -> void:
	if session_mode != "immersive-vr":
		return
	vr_btn.visible = supported
	if supported:
		status.text = "VR headset ready."
	elif touch_device:
		status.text = "Touch controls ready. Hold your phone sideways."
	else:
		status.text = "No immersive VR available in this browser."

func _enter_vr() -> void:
	webxr.session_mode = "immersive-vr"
	webxr.requested_reference_space_types = "local-floor, local"
	webxr.required_features = "local"
	webxr.optional_features = "local-floor"
	webxr.render_target_size_multiplier = 0.85   # Quest 3: ~28% fewer pixels per eye, barely visible
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

## Phones and tablets: on-screen controls, and fullscreen sideways where the browser allows it
## (Android Chrome does; an iPhone keeps its browser bars).
func _start_touch() -> void:
	Game.touch = true
	Input.emulate_mouse_from_touch = false
	touch_ui.visible = true
	_start_desktop()
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_tree().create_timer(0.8).timeout.connect(func() -> void:
			JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function () {}); } catch (e) {}"))

## Low graphics: the 3D view at about 1100 pixels across whatever the screen (a phone's is often
## 2500), no MSAA, a smaller shadow map for the flashlight, and fewer windows lit by the sun.
func _apply_quality() -> void:
	var vp := get_viewport()
	if Game.low_quality:
		var wide := float(get_window().size.x)
		vp.scaling_3d_scale = clampf(1100.0 / wide, 0.35, 1.0) if wide > 1.0 else 0.6
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.positional_shadow_atlas_size = 1024
	else:
		vp.scaling_3d_scale = 1.0
		vp.msaa_3d = Viewport.MSAA_2X
		vp.positional_shadow_atlas_size = 2048

func _begin(xr: bool) -> void:
	if not xr:
		_apply_quality()
	player.begin(xr)
	player.teleport_head_to(station.start_point())
	Sfx.set_ambient("hum")
	if OS.has_environment("DERELICT_AUTOTEST") or OS.has_environment("DERELICT_SHOTS"):
		await get_tree().create_timer(1.2).timeout
	else:
		await _warm_up()
	Game.start_game()

## The loading stage. Shaders compile the first time a material is drawn, so without this the first
## look into every room and every lamp, screen and pane of glass costs a hitch during play. Behind
## the black fade the camera visits each room and a spread of corridor cells for a frame or two,
## then spins at the start point, so everything on the deck has been drawn once before the fade lifts.
func _warm_up() -> void:
	player.fade_target = 1.0
	player.fade_mat.albedo_color.a = 1.0
	Game.notice.emit("KESTREL-9\nInitialising deck systems...", 8.0)
	var start := station.start_point()
	var lay: StationLayout = station.layout
	var deadline := Time.get_ticks_msec() + 5000   # a slow machine gets the rooms, then we go anyway
	for r: Dictionary in lay.rooms:
		if Time.get_ticks_msec() > deadline:
			break
		var dir: Vector2i = r["dir"]
		_look_from(station.room_entry(r["index"]), StationLayout.world(r["center"], 1.4))
		for i in 2:
			await get_tree().process_frame
		_look_from(StationLayout.world(r["center"], 1.4), StationLayout.world(r["center"], 1.4) + Vector3(dir.x, 0, dir.y) * 5.0)
		await get_tree().process_frame
	var n := 0
	for c: Vector2i in lay.corridor:
		n += 1
		if n % 3 != 0 or Time.get_ticks_msec() > deadline:
			continue
		var cell: Dictionary = lay.corridor[c]
		var d: Vector2i = cell["open"][0]
		_look_from(StationLayout.world(c, 1.5), StationLayout.world(c, 1.5) + Vector3(d.x, 0, d.y) * 6.0)
		await get_tree().process_frame
	player.teleport_head_to(start)
	for k in 8:
		if Time.get_ticks_msec() > deadline + 1500:
			break
		player.origin.rotation.y = k * TAU / 8.0
		await get_tree().process_frame
	player.origin.rotation.y = 0.0
	player.yaw = 0.0
	await get_tree().create_timer(0.6).timeout
	player.hud_label.text = ""
	player.fade_target = 0.0

func _look_from(eye: Vector3, target: Vector3) -> void:
	player.teleport_head_to(eye)
	if player.xr_active:
		return
	var v := target - eye
	player.yaw = atan2(-v.x, -v.z)
	player.pitch = atan2(v.y, Vector2(v.x, v.z).length())
	player.origin.rotation.y = player.yaw
	player.camera.rotation.x = player.pitch

## Dev shortcut (desktop keyboard): Ctrl+Shift+N ends the current shift immediately.
func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.ctrl_pressed and e.shift_pressed and e.keycode == KEY_N:
		if Game.phase == Game.Phase.DAY:
			Game.day_time = Game.day_length() + 1.0

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
