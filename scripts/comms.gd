extends Node
## Autoload "Comms": the uplink, and the story it carries.
##
## Kestrel-9 talks to GATEWAY CONTROL in Houston once a shift. Gateway hails you a little way into
## the day, a voice reads the message while the comms console prints it, and then it is your turn:
## key the console (hold TRIGGER / USE on it) and your own report goes back. Seven shifts of that
## is the plot - the lighting that draws current with nobody awake, a scrubber working for two
## people, an answer that lands before you send the question, and your own voice on the airlock
## carrier at night asking to be let in.
##
## Everything it says lives in comms/log.json; every voice is a wav rendered from that same file by
## tools/gen_voice.py. Nothing here knows the words - it knows when to key the mic.

signal transmission_started(entry: Dictionary)
signal transmission_ended(entry: Dictionary)
signal state_changed                      ## anything the console or the wrist should redraw on

const LOG_PATH := "res://comms/log.json"
const VOICE_DIR := "res://audio/voice/"
const HAIL_AT := 20.0                     ## seconds into a shift before Gateway calls
const NIGHT_CARRIER := {4: 28.0, 6: 22.0} ## night -> seconds after the lights die that it keys up

var ground := "GATEWAY CONTROL"
var station_name := "KESTREL-9"
var entries := {}                         ## id -> entry from the log
var current := {}                         ## the transmission playing, {} when the channel is quiet
var reply_pending := false                ## Gateway called and you have not answered yet
var reply_id := ""
var missed := 0                           ## shifts you never keyed up on
var transcript: Array[String] = []        ## what the console has printed this run, newest last
var console: Node3D = null                ## set by the Station when it builds the console

var _voice: AudioStreamPlayer             ## the suit headset: you hear it wherever you are
var _queue: Array[String] = []
var _wait := 0.0                          ## seconds until the next queued transmission keys up
var _elapsed := 0.0
var _length := 0.0
var _lines: Array[String] = []
var _night_done := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_log()
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = -3.0
	add_child(_voice)
	Game.day_started.connect(_on_day_started)
	Game.phase_changed.connect(_on_phase_changed)
	Game.game_reset.connect(_on_reset)

func _load_log() -> void:
	if not ResourceLoader.exists(LOG_PATH) and not FileAccess.file_exists(LOG_PATH):
		push_warning("comms: no log at %s - the uplink will stay quiet" % LOG_PATH)
		return
	var text := FileAccess.get_file_as_string(LOG_PATH)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("comms: could not parse %s" % LOG_PATH)
		return
	ground = data.get("ground", ground)
	station_name = data.get("station", station_name)
	for e: Variant in data.get("entries", []):
		if typeof(e) == TYPE_DICTIONARY and e.has("id"):
			entries[e["id"]] = e

# ---------------------------------------------------------------- the shift
func _on_reset() -> void:
	_stop()
	missed = 0
	transcript.clear()
	_night_done.clear()
	reply_pending = false
	reply_id = ""
	state_changed.emit()

func _on_day_started(day: int) -> void:
	_stop()
	reply_pending = false
	reply_id = ""
	_queue.clear()
	# a shift you never answered is the first thing Gateway says on the next one
	if missed > 0 and entries.has("silence"):
		_queue.append("silence")
	if entries.has("d%d_in" % day):
		_queue.append("d%d_in" % day)
	_wait = HAIL_AT
	state_changed.emit()

func _on_phase_changed(phase: int) -> void:
	match phase:
		Game.Phase.SLEEP:
			if reply_pending:
				missed += 1
				_log("[ no report sent - %s is still waiting ]" % ground)
				reply_pending = false
			_stop()
			_queue.clear()
		Game.Phase.NIGHT:
			_stop()
			_queue.clear()
			var id := "n%d" % Game.day
			# a night you sleep straight through, you do not hear it
			if entries.has(id) and not _night_done.has(id) and not Game.is_quiet_night():
				_night_done[id] = true
				_queue.append(id)
				_wait = float(NIGHT_CARRIER.get(Game.day, 30.0))
		Game.Phase.WON:
			_stop()
			_queue.clear()
			if entries.has("won"):
				_queue.append("won")
				_wait = 2.0
		Game.Phase.DEAD, Game.Phase.TITLE:
			_stop()
			_queue.clear()
	state_changed.emit()

func _process(delta: float) -> void:
	if is_playing():
		_elapsed += delta
		if _elapsed >= _length:
			_end()
		return
	if _queue.is_empty():
		return
	if Game.phase != Game.Phase.DAY and Game.phase != Game.Phase.NIGHT and Game.phase != Game.Phase.WON:
		return
	_wait -= delta
	if _wait <= 0.0:
		var id: String = _queue.pop_front()
		_play(id)

# ---------------------------------------------------------------- transmitting
func is_playing() -> bool:
	return not current.is_empty()

## Seconds of message gone by - the console prints itself at the pace the voice reads it.
func progress() -> float:
	return 0.0 if _length <= 0.0 else clampf(_elapsed / _length, 0.0, 1.0)

## The lines printed so far, the way the console shows them.
func visible_text() -> String:
	if _lines.is_empty():
		return ""
	var shown := int(ceil(progress() * _lines.size()))
	return "\n".join(_lines.slice(0, maxi(shown, 1)))

## Key the mic: your own report goes back to Earth. The console calls this when the hold completes.
func send_reply() -> bool:
	if not reply_pending or is_playing() or not entries.has(reply_id):
		return false
	reply_pending = false
	Sfx.play("comms_key", -6.0)
	_play(reply_id)
	return true

func _play(id: String) -> void:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty():
		return
	current = e
	_lines = []
	for l: Variant in e.get("text", []):
		_lines.append(str(l))
	_elapsed = 0.0
	_length = 6.0
	var path := VOICE_DIR + id + ".wav"
	if ResourceLoader.exists(path):
		var s: AudioStream = load(path)
		_voice.stream = s
		_voice.volume_db = -3.0 if e.get("kind", "") != "night" else 0.0
		_voice.play()
		_length = maxf(s.get_length(), 1.0)
	else:
		_voice.stop()
		_length = 2.0 + 0.9 * _lines.size()
	if e.get("kind", "") != "reply":
		Sfx.play("comms_hail", -4.0)
	_log("%s\n%s" % [e.get("from", ground), "\n".join(_lines)])
	transmission_started.emit(e)
	state_changed.emit()
	var where := "COMMS CONSOLE"
	if Game.station != null and Game.station.has_method("comms_room"):
		where = str(Game.station.call("comms_room"))
	match str(e.get("kind", "")):
		"night":
			Game.notice.emit("The comms console keys up by itself.\nSomething is transmitting.", 5.0)
		"reply":
			pass
		_:
			Game.notice.emit("INCOMING - %s\n%s\nAnswer it at the comms console (%s)." % [
				e.get("from", ground), _lines[0] if _lines.size() > 0 else "", where], 7.0)

func _end() -> void:
	var e := current
	current = {}
	_voice.stop()
	if str(e.get("kind", "")) == "inbound" and Game.phase == Game.Phase.DAY:
		var out := "d%d_out" % Game.day
		if entries.has(out):
			reply_id = out
			reply_pending = true
			Game.notice.emit("%s is waiting on your shift report.\nHold %s on the comms console to send it." % [
				ground, Game.use_word()], 6.0)
	transmission_ended.emit(e)
	state_changed.emit()

func _stop() -> void:
	if not current.is_empty():
		current = {}
	_voice.stop()
	_elapsed = 0.0

func _log(s: String) -> void:
	transcript.append(s)
	if transcript.size() > 24:
		transcript.remove_at(0)

# ---------------------------------------------------------------- autotest hooks
## Key the next queued transmission now instead of waiting out the hail timer.
func debug_hail() -> void:
	if not _queue.is_empty():
		_wait = 0.0

## Cut the transmission that is playing short, as if it had read itself out.
func debug_finish() -> void:
	if is_playing():
		_elapsed = _length + 1.0
		_end()

## One line for the crew terminal on the wrist.
func wrist_line() -> String:
	if is_playing():
		return "COMMS: receiving - %s" % str(current.get("from", ground))
	if reply_pending:
		return "COMMS: shift report due - key the console"
	if missed > 0:
		return "COMMS: %d report%s missed" % [missed, "" if missed == 1 else "s"]
	return "COMMS: channel open"
