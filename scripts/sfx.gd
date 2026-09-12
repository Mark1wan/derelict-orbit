extends Node
## Autoload "Sfx": tiny sound bank. Every WAV is synthesised - tools/gen_audio.py for the bank,
## tools/gen_flicker_audio.py for the two the flickering lights need.

const NAMES := ["hum", "drone", "heartbeat", "bang", "whisper", "powerdown", "powerup",
	"beep", "complete", "flicker", "breath", "scream", "static",
	# the flicker family (tools/gen_flicker_audio.py): what a failing fitting sounds like, and
	# what is sometimes mixed in underneath it
	"ballast", "underbreath",
	# the comms console (tools/gen_voice.py): the hail that opens a transmission, the mic key
	# when you answer, and the open carrier the console sits on
	"comms_hail", "comms_key", "comms_carrier"]
const LOOPS := ["hum", "drone", "breath", "heartbeat", "comms_carrier"]

var streams := {}
var ambient: AudioStreamPlayer
var heart: AudioStreamPlayer
var _heart_on := false

func _ready() -> void:
	for n in NAMES:
		var path := "res://audio/%s.wav" % n
		if ResourceLoader.exists(path):
			var s := load(path)
			if s is AudioStreamWAV and n in LOOPS:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = s.data.size() / 2   # 16-bit mono frames
			streams[n] = s
	ambient = AudioStreamPlayer.new()
	ambient.volume_db = -12.0
	add_child(ambient)
	heart = AudioStreamPlayer.new()
	heart.stream = streams.get("heartbeat")
	heart.volume_db = -6.0
	add_child(heart)

func play(n: String, db := 0.0, pitch := 1.0) -> void:
	if not streams.has(n):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[n]
	p.volume_db = db
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()

func play_at(n: String, pos: Vector3, db := 0.0, max_dist := 40.0, pitch := 1.0) -> AudioStreamPlayer3D:
	if not streams.has(n):
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[n]
	p.volume_db = db
	p.max_distance = max_dist
	p.pitch_scale = pitch
	p.finished.connect(p.queue_free)
	add_child(p)
	p.global_position = pos
	p.play()
	return p

func set_ambient(n: String, db := -12.0) -> void:
	var s = streams.get(n)
	if s == null:
		ambient.stop()
		return
	if ambient.stream == s and ambient.playing:
		ambient.volume_db = db
		return
	ambient.stream = s
	ambient.volume_db = db
	ambient.play()

## Heartbeat: rate 0..1 maps to slow/quiet -> fast/loud.
func set_heartbeat(on: bool, rate := 0.0) -> void:
	if on and not _heart_on:
		heart.play()
	elif not on and _heart_on:
		heart.stop()
	_heart_on = on
	if on:
		heart.pitch_scale = lerpf(0.85, 1.6, rate)
		heart.volume_db = lerpf(-18.0, -2.0, rate)
