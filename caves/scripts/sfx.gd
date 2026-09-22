extends Node
## Autoloaded as `Sfx`. The sound bank, ported from derelict-orbit's scripts/sfx.gd: load every
## wav once, mark the loops, and spawn a throwaway player per one-shot.
##
## Two things here are not in the original, and both exist because a cave is quiet enough that
## your own body is most of what you hear. `set_scrape` drives a loop off contact pressure, so
## the rock on your shoulders is audible before anything on screen says so. `set_breath` drives
## another off exertion and how much of a held exhale is left, which is the only readout the
## squeeze has that does not need you to look at something.

const NAMES := ["breath", "deep", "drip", "exhale", "gasp", "grab", "gravel", "helmet",
	"rope", "scrape", "water", "wind"]
const LOOPS := ["breath", "deep", "scrape", "water", "wind"]

var streams := {}
var ambient: AudioStreamPlayer
var breath: AudioStreamPlayer

var _breath_rate := 1.0
var _exhaling := false

func _ready() -> void:
	for n: String in NAMES:
		var path := "res://audio/%s.wav" % n
		if not ResourceLoader.exists(path):
			continue
		var s: AudioStream = load(path)
		if s is AudioStreamWAV and LOOPS.has(n):
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = w.data.size() / 2   # 16-bit mono frames
		streams[n] = s

	ambient = AudioStreamPlayer.new()
	ambient.bus = "Master"
	add_child(ambient)

	breath = AudioStreamPlayer.new()
	breath.bus = "Master"
	breath.volume_db = -20.0
	add_child(breath)
	if streams.has("breath"):
		breath.stream = streams["breath"]
		breath.play()

func play(n: String, db := 0.0, pitch := 1.0) -> void:
	if not streams.has(n):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[n]
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

## A sound with a position in the cave. `max_dist` is deliberately small for drips - a drip you
## can hear from thirty metres tells you nothing, and one you can hear from six tells you which
## side of the passage the water is on.
func play_at(n: String, pos: Vector3, db := 0.0, max_dist := 18.0, pitch := 1.0) -> AudioStreamPlayer3D:
	if not streams.has(n):
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[n]
	p.volume_db = db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 2.0
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p

func set_ambient(n: String, db := -16.0) -> void:
	if not streams.has(n):
		return
	if ambient.stream == streams[n] and ambient.playing:
		ambient.volume_db = db
		return
	ambient.stream = streams[n]
	ambient.volume_db = db
	ambient.play()

## The suit on the rock. Silent in open passage, and by the time pressure is at 0.9 it is the
## loudest thing in the cave - but only while you are actually moving, because rock you are
## resting against does not make a sound.
func set_scrape(player: AudioStreamPlayer, pressure: float, speed: float) -> void:
	if player == null or not streams.has("scrape"):
		return
	if player.stream == null:
		player.stream = streams["scrape"]
	var moving: float = clampf(speed / 0.5, 0.0, 1.0)
	var amount: float = clampf((pressure - 0.25) / 0.70, 0.0, 1.0) * moving
	if amount <= 0.01:
		if player.playing:
			player.volume_db = maxf(player.volume_db - 2.0, -60.0)
			if player.volume_db <= -55.0:
				player.stop()
		return
	if not player.playing:
		player.volume_db = -60.0
		player.play()
	var want: float = lerpf(-34.0, -7.0, amount)
	player.volume_db = lerpf(player.volume_db, want, 0.25)
	player.pitch_scale = lerpf(0.82, 1.18, amount)

## Your own breathing. Faster and louder the harder the cave is pressing; held while you are
## emptying your chest, with a gasp when your body takes the decision back.
func set_breath(exhale: float, air: float, pressure: float) -> void:
	if breath == null or breath.stream == null:
		return
	var effort: float = clampf(pressure * 0.8 + (1.0 - air) * 0.5, 0.0, 1.0)
	var want_rate: float = lerpf(0.85, 1.55, effort)
	if exhale > 0.2:
		# Holding it out: the loop slows almost to a stop and drops away.
		want_rate = lerpf(want_rate, 0.30, exhale)
	_breath_rate = lerpf(_breath_rate, want_rate, 0.06)
	breath.pitch_scale = _breath_rate
	breath.volume_db = lerpf(-26.0, -11.0, effort) - exhale * 12.0

	if exhale > 0.5 and not _exhaling:
		_exhaling = true
		play("exhale", -13.0, randf_range(0.95, 1.05))
	elif exhale < 0.2 and _exhaling:
		_exhaling = false
		if air < 0.25:
			play("gasp", -10.0, randf_range(0.95, 1.08))
