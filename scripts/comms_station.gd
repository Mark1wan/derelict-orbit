extends Interactable
class_name CommsStation
## The comms console: the deep-space uplink, and the instrument the story is told on.
##
## It is an Interactable so the player's existing point-and-hold works on it unchanged, but it is
## not a maintenance task - nothing routes to Game. What the hold does is key the mic: hold TRIGGER
## (USE on a phone) on it while a report is due and your answer goes to Earth (Comms.send_reply).
##
## The screen prints the message at the pace the voice reads it, so standing here and listening is
## the point. It is also the one panel that is lit at night, which is how the two night carriers
## find you in the dark.

const COL_IDLE_SCREEN := Color(0.05, 0.14, 0.2)
const COL_RX := Color(0.25, 0.8, 1.0)          # Gateway talking
const COL_TX := Color(0.1, 0.9, 0.4)           # you talking
const COL_DUE := Color(1.0, 0.55, 0.1)         # a report is waiting on you
const COL_WRONG := Color(1.0, 0.2, 0.12)       # the night carrier

var header: Label3D
var body: Label3D
var lamp: OmniLight3D
var carrier: AudioStreamPlayer3D
var _blink := 0.0

func setup_comms(room_label: String) -> void:
	setup("comms_reply", "TRANSMIT REPORT", room_label, false, "")
	hold_time = 2.5
	label.position = Vector3(0, 0.86, 0.07)
	label.text = "DEEP SPACE UPLINK\n%s" % room_label

	# a wider screen above the terminal's own: this is where Earth is read out
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.72, 0.08)
	back.mesh = bm
	back.position = Vector3(0, 0.46, 0.03)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.16, 0.17, 0.2)
	bmat.metallic = 0.6
	bmat.roughness = 0.45
	back.material_override = bmat
	add_child(back)

	var glass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(1.36, 0.6, 0.02)
	glass.mesh = gm
	glass.position = Vector3(0, 0.46, 0.075)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.01, 0.02, 0.03)
	gmat.emission_enabled = true
	gmat.emission = COL_IDLE_SCREEN
	gmat.emission_energy_multiplier = 0.5
	glass.material_override = gmat
	add_child(glass)
	screen_mat = gmat                     # the base class drives this one for focus / progress

	header = _text(0.026, Vector3(0, 0.72, 0.09), Color(0.45, 0.85, 1.0))
	body = _text(0.020, Vector3(0, 0.66, 0.09), Color(0.75, 0.92, 1.0))
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# speaker grille, so the voice has somewhere to come out of
	for i in 7:
		var slot := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.26, 0.012, 0.01)
		slot.mesh = sm
		slot.position = Vector3(-0.5, 0.02 + i * 0.028, 0.075)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.08, 0.08, 0.09)
		slot.material_override = mat
		add_child(slot)

	lamp = OmniLight3D.new()
	lamp.position = Vector3(0, 0.46, 0.5)
	lamp.light_color = COL_RX
	lamp.light_energy = 0.0
	lamp.omni_range = 5.0
	add_child(lamp)

	carrier = AudioStreamPlayer3D.new()
	carrier.stream = Sfx.streams.get("comms_carrier")
	carrier.volume_db = -26.0
	carrier.max_distance = 14.0
	add_child(carrier)
	if carrier.stream != null:
		carrier.play()

	Comms.state_changed.connect(_refresh_screen)
	Comms.console = self
	_refresh_screen()

func _text(size: float, pos: Vector3, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.font_size = 34
	l.pixel_size = size / 34.0
	l.outline_size = 6
	l.modulate = colour
	l.position = pos
	l.width = 1900
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = ""
	add_child(l)
	return l

## Keying the mic, not fixing anything: this only does something while a report is due, and it
## never reports a task to Game. A hold with any tool in the hand works - you are pressing a key.
func hold(delta: float, _with := "") -> bool:
	if not Comms.reply_pending or Comms.is_playing():
		return false
	progress += delta / hold_time
	_tick += delta
	if _tick > 0.3:
		_tick = 0.0
		Sfx.play_at("beep", global_position, -20.0, 12.0, 1.1 + progress * 0.5)
	if progress >= 1.0:
		progress = 1.0
		bar.scale.x = 1.0
		Comms.send_reply()
		progress = 0.0
	else:
		bar.scale.x = maxf(progress, 0.001)
	return true

func _refresh_screen() -> void:
	var due := Comms.reply_pending
	active = due                      # so the player's laser and the wrist treat it as live work
	done = false
	bar.visible = due or Comms.is_playing()
	if Comms.is_playing():
		var e := Comms.current
		header.text = str(e.get("from", Comms.ground))
		body.text = Comms.visible_text()
	elif due:
		header.text = "REPORT DUE - %s" % Comms.ground
		body.text = "Hold %s here to transmit\nyour shift report." % Game.use_word()
	else:
		header.text = "%s UPLINK" % Comms.station_name
		var last := Comms.transcript[-1] if not Comms.transcript.is_empty() else ""
		body.text = last if last != "" else "Channel open. No traffic."

func _process(delta: float) -> void:
	_blink += delta
	var colour := COL_IDLE_SCREEN
	var energy := 0.5
	if Comms.is_playing():
		var kind := str(Comms.current.get("kind", ""))
		colour = COL_TX if kind == "reply" else (COL_WRONG if kind == "night" else COL_RX)
		energy = 1.4 + 0.5 * sin(_blink * 9.0)
		body.text = Comms.visible_text()
	elif Comms.reply_pending:
		colour = COL_DUE
		energy = 1.2 + 0.7 * sin(_blink * 3.0)
	elif not Game.power_on:
		# the uplink runs off its own cell: at night this screen is the only one still lit
		colour = COL_IDLE_SCREEN
		energy = 0.35 + 0.15 * sin(_blink * 1.3)
	if focused and (Comms.reply_pending or Comms.is_playing()):
		colour = colour.lerp(COL_FOCUS, 0.35)
		energy += 0.6
	screen_mat.emission = colour
	screen_mat.emission_energy_multiplier = energy
	lamp.light_color = colour
	lamp.light_energy = clampf(energy * 0.35, 0.0, 1.2)
	if carrier != null:
		carrier.volume_db = -20.0 if Comms.is_playing() else -30.0
