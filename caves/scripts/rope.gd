class_name Rope
extends Node3D
## The rope down The Pitch, and the descender on your harness.
##
## Built from derelict-orbit's scripts/tether.gd, which had the same two jobs - draw a line
## between two points and let the player reel along it - and the same constraint, that it has
## to work identically for a controller, a mouse and a thumb.
##
## Deliberately the simplest thing that reads as single rope technique rather than a
## simulation of it. The rope is fixed, you clip on within reach of it, and from then on your
## height is yours to control: let the brake off and you slide, hold it and you stop, push up
## and you climb. What it has to get right is the only part that matters at the top of a
## forty-seven metre shaft - that going down is easy, going up is work, and letting go of the
## brake is a decision.

const CLIP_REACH := 1.4       ## how close to the rope you must be to clip on
const FREE_FALL := 4.2        ## m/s with the brake fully off
const BRAKED := 0.35          ## m/s with it fully on
const CLIMB := 0.55           ## m/s hauling yourself back up
const RADIUS := 0.012
const SLACK := 0.10           ## how far the rope bows out under its own weight, at mid-span

var id := ""
var label := ""
var top := Vector3.ZERO
var bottom := Vector3.ZERO
var clipped := false

var _line: MeshInstance3D
var _mat: StandardMaterial3D
var _sound: AudioStreamPlayer3D
var _last_speed := 0.0

func setup(data: Dictionary, mat: StandardMaterial3D) -> void:
	id = data.get("id", "rope")
	label = data.get("label", id)
	var t: Array = data.get("top", [0, 0, 0])
	var b: Array = data.get("bottom", [0, -10, 0])
	top = Vector3(t[0], t[1], t[2])
	bottom = Vector3(b[0], b[1], b[2])
	_mat = mat
	_build()

func _build() -> void:
	# A hanging rope is not a straight line, and on a forty-seven metre pitch you can see it.
	# Fourteen segments bowed along a shallow catenary is enough to sell it and costs nothing.
	var g := Geo.new()
	var segs := 14
	var prev := top
	for i in range(1, segs + 1):
		var f := float(i) / float(segs)
		var p: Vector3 = top.lerp(bottom, f)
		p.x += sin(f * PI) * SLACK
		g.pipe(prev, p, RADIUS, 5)
		prev = p
	# The anchor at the head of the pitch: two bolts and a loop of tape.
	g.pipe(top + Vector3(0.9, 0.1, 0.2), top, RADIUS * 2.2, 5)
	_line = g.commit(_mat, self, null, "rope_line")
	if _line:
		_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_sound = AudioStreamPlayer3D.new()
	_sound.max_distance = 30.0
	add_child(_sound)

## Nearest point on the rope to `p`, clamped to the pitch.
func point_near(p: Vector3) -> Vector3:
	var v := bottom - top
	var f: float = clampf((p - top).dot(v) / maxf(v.length_squared(), 0.0001), 0.0, 1.0)
	var q: Vector3 = top.lerp(bottom, f)
	q.x += sin(f * PI) * SLACK
	return q

func in_reach(p: Vector3) -> bool:
	return point_near(p).distance_to(p) <= CLIP_REACH

## Called by the caver every physics frame. Owns the caver's vertical motion while clipped,
## and nothing else - you can still turn, still look, still reach out and touch the wall.
func caver_moved(caver: Caver, intent: Intent, delta: float) -> void:
	if intent.rope:
		if clipped:
			unclip(caver)
		elif in_reach(caver.global_position):
			clip_on(caver)
		else:
			Cave.say("nothing to clip to", 2.0)

	if not clipped:
		return

	var anchor := point_near(caver.global_position)
	# Held to the rope laterally, so you hang under the anchor rather than swinging off it.
	var lateral := Vector3(anchor.x - caver.global_position.x, 0.0, anchor.z - caver.global_position.z)
	caver.velocity.x = lateral.x * 4.0
	caver.velocity.z = lateral.z * 4.0

	# Down is gravity you are allowing; up is work. The brake is the whole interface.
	var brake: float = clampf(intent.brake, 0.0, 1.0)
	var up: float = clampf(intent.move.y, -1.0, 1.0)
	var speed := 0.0
	if up > 0.1 and caver.global_position.y < top.y - 0.5:
		speed = CLIMB * up
	else:
		speed = -lerpf(FREE_FALL, BRAKED, brake)
		if caver.global_position.y <= bottom.y + 0.05:
			speed = 0.0
	caver.velocity.y = speed

	if caver.global_position.y <= bottom.y + 0.35 and speed <= 0.0:
		unclip(caver)
		Cave.say("off rope", 2.5)
		return

	_run_sound(caver, absf(speed))

func clip_on(caver: Caver) -> void:
	clipped = true
	caver.velocity = Vector3.ZERO
	Sfx.play("helmet", -22.0, 1.6)
	Cave.say("%s - on rope. hold the brake to slow down" % label, 4.5)

func unclip(caver: Caver) -> void:
	clipped = false
	if _sound.playing:
		_sound.stop()
	Cave.say("unclipped", 2.0)

func _run_sound(caver: Caver, speed: float) -> void:
	if speed < 0.05:
		if _sound.playing:
			_sound.stop()
		return
	if not _sound.playing and Sfx.streams.has("rope"):
		_sound.stream = Sfx.streams["rope"]
		_sound.play()
	_sound.global_position = caver.global_position
	_sound.pitch_scale = lerpf(0.7, 1.5, clampf(speed / FREE_FALL, 0.0, 1.0))
	_sound.volume_db = lerpf(-26.0, -8.0, clampf(speed / FREE_FALL, 0.0, 1.0))

# ---------------------------------------------------------------- test hooks

func debug_clip(caver: Caver) -> void:
	# Through teleport, not a bare position write: the caver traces its own centre from step
	# to step, and a body that appears at the head of the pitch from the far end of the cave
	# has, as far as that trace can tell, just come through forty metres of rock.
	caver.teleport(point_near(top + Vector3(0, -1.0, 0)) + Vector3(0, -0.6, 0))
	clip_on(caver)
