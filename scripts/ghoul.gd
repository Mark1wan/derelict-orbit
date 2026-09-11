extends Node3D
class_name Ghoul
## The ghul: the apparition that pretends.
##
## In pre-Islamic Arabian folklore the ghul waits off the road in desolate country, takes the
## shape of a person to bring a traveller in off their route, and eats what it catches. It lives
## on the dead. The one thing it cannot change, in every version of the story, is its hooves.
##
## Here it stands at the far end of a corridor you are not due to be in, wearing the shape of a
## crew member, and waits. Nothing about it is lit - it is a shape against the light at the far
## end, which is all you ever really see down a corridor anyway. It is patient, and it is quiet,
## and while you are walking toward it you are not doing your shift. If you come close, or look
## too long, it stops pretending: the shoulders come up over the head, the arms go down to the
## deck, and two eyes open in the wrong colour - the first light it has shown. Then it takes
## itself away.
##
## It never touches you. The day is not when this station kills you - that is what the nights are
## for - but you will remember the corridor it was standing in.

const RIG := "res://kit/apparition_ghoul.json"
const TURN_TIME := 1.1       # how long it takes to stop pretending
const NOTICE_DIST := 6.5     # close enough that it does not need to keep up the act
const STARE_TIME := 2.6      # or you looked at it for this long
const LINGER := 2.2          # how long it holds the true shape before it goes

signal turned                ## it stopped pretending - the moment worth a sound

var body: Apparition
var looked := 0.0
var lifetime := 30.0
var _turning := false
var _leaving := false
var _linger := LINGER
var _drift := Vector3.ZERO

func _ready() -> void:
	body = Apparition.new()
	body.rig_path = RIG
	add_child(body)
	body.gather(1.1)         # it does not appear: it is already there when you look up

## Stand at `p`, wearing the lure, facing `face` (usually the player, lamp toward them).
func lure(p: Vector3, face: Vector3) -> void:
	global_position = p
	var f := face
	f.y = p.y
	if f.distance_to(p) > 0.01:
		look_at(f, Vector3.UP)
	# which way it will go when it leaves: further off your route, never past you
	_drift = -global_transform.basis.z * -1.0

func _process(delta: float) -> void:
	if Game.player == null:
		return
	var cam: Camera3D = Game.player.camera
	var eye := cam.global_position
	var to := global_position - eye
	var dist := to.length()
	if _leaving:
		global_position += _drift * delta * 2.4
		return

	if _turning:
		_linger -= delta
		# it holds still while you decide what to do about it, then leaves at speed
		if _linger <= 0.0:
			_leave()
		return

	if (-cam.global_transform.basis.z).dot(to.normalized()) > 0.9:
		looked += delta
	lifetime -= delta
	# it keeps up the act until you are close enough, or until you have looked too long
	if dist < NOTICE_DIST or looked > STARE_TIME:
		_turn()
	elif lifetime <= 0.0:
		_leave()

func _turn() -> void:
	if _turning:
		return
	_turning = true
	body.agitation = 0.6
	var tw := create_tween()
	tw.tween_property(body, "morph", 1.0, TURN_TIME).set_trans(Tween.TRANS_CUBIC)
	Sfx.play_at("breath", global_position, -3.0, 30.0, 0.65)
	turned.emit()

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play_at("whisper", global_position, -6.0, 30.0, 0.7)
	body.disperse(0.7).tween_callback(queue_free)
