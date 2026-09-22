class_name CaverBody
extends RefCounted
## The caver's body as a shape that has to fit, rather than a capsule that bumps into things.
##
## Everything a tight-passage game is about lives here. A body is a cross-section - a width
## across the shoulders and a depth through the chest - and a posture is a choice about how to
## fold that section into the space available. You do not squeeze by pressing forward harder;
## you squeeze by being a smaller shape, and there are only so many ways to be one.
##
## The chest is the part that matters. A relaxed chest is 30 cm deep. At the bottom of a full
## exhale it is 26.5 cm, and it will stay there for about six seconds before your body takes
## the decision away from you. Three and a half centimetres is not much. It is the difference
## between the Devil's Pinch being a passage and being a wall, and every number in
## cave/sowbelly.json was chosen against it.
##
## This class holds no nodes and does no movement. It reads the rock with raycasts, decides
## what shape you currently are, and reports how hard the cave is pressing on you.
## scripts/caver.gd does the moving.

# ---------------------------------------------------------------- the body

const CHEST_RELAXED := 0.30   ## chest depth, metres, breathing normally
const CHEST_SQUEEZE := 0.035  ## how much of that a full exhale gives back
const SHOULDER := 0.46        ## shoulder span, both arms at your sides

## Postures, roomiest first. `w` and `h` are the box this shape has to get through; whichever
## of them is named by `chest` is supplied by the chest depth instead of a fixed number, plus
## `gear` for the helmet, the oversuit and whatever is on your back. `eye` is where your head
## ends up. Nothing outside this table decides how big you are - tools/check_fit.py reads it
## out of this file with a regex and checks the whole cave against it, so a number changed
## here is a cave re-verified in CI rather than a cave quietly broken.
const POSTURES := [
	{"name": "stand", "h": 1.75, "w": 0.46, "chest": "none", "gear": 0.04, "speed": 1.40, "eye": 1.62},
	{"name": "stoop", "h": 1.25, "w": 0.46, "chest": "none", "gear": 0.04, "speed": 1.00, "eye": 1.12},
	{"name": "knees", "h": 0.75, "w": 0.46, "chest": "none", "gear": 0.04, "speed": 0.75, "eye": 0.58},
	{"name": "belly", "h": 0.00, "w": 0.46, "chest": "h", "gear": 0.04, "speed": 0.34, "eye": 0.19},
	{"name": "commit", "h": 1.25, "w": 0.00, "chest": "w", "gear": 0.005, "speed": 0.13, "eye": 1.10},
	{"name": "superman", "h": 0.00, "w": 0.32, "chest": "h", "gear": 0.02, "speed": 0.10, "eye": 0.17},
]

## What the slate says you are doing, and the line of advice under it.
const POSTURE_LABEL := {
	"stand": "standing", "stoop": "stooping", "knees": "hands and knees",
	"belly": "flat out", "commit": "committed, sideways", "superman": "head first, one arm ahead",
}

const STAND = 0
const STOOP = 1
const KNEES = 2
const BELLY = 3
const COMMIT = 4
const SUPERMAN = 5

# ---------------------------------------------------------------- breath

const EXHALE_IN := 1.25     ## how fast the chest empties, fraction per second
const EXHALE_OUT := 2.40    ## how fast it comes back when you stop
const AIR_DRAIN := 0.165    ## a full exhale lasts about six seconds
const AIR_REGAIN := 0.30    ## and takes about three and a half to get back
const AIR_REARM := 0.22     ## below this you cannot start another one

# ---------------------------------------------------------------- the rock

const RING := 12            ## rays around the chest, in the plane across the passage
const RING_REACH := 1.30    ## how far out to look before calling it open space
const HEAD_REACH := 2.60
const WORLD_MASK := 1

## Contact pressure: how much of the space available to you, your body is currently taking up.
## It is the number the whole feel of the game hangs off - the scrape loop, the haptics, the
## vignette, and how fast you move - so it has to mean the right thing.
##
## The naive version, "average how far away the rock is", is wrong, and wrong in a way that
## matters. A bedding crawl is three metres wide and thirty-eight centimetres tall: average the
## ring and it reads as open, because the two horizontal rays fly off into the dark. But
## nothing about that passage is open. What is pressing on you is the ceiling, and a measure
## that lets the wide directions vote is measuring the wrong thing.
##
## So each ray is compared against the body's own half-extent in that same direction, and what
## comes back is the fraction of the available room you are occupying along that line. A
## letterbox reads high because your chest fills the height; a rift reads high because your
## chest fills the width; a walking passage reads low both ways. Then the worst third of the
## ring is averaged, so one unlucky ray into a pocket cannot spike it and one real contact
## cannot be voted away.
const CONTACT_FLOOR := 0.42  ## occupying less of the space than this does not register at all
const CONTACT_SPAN := 0.50   ## and this much more of it is full contact
const CONTACT_WORST := 4     ## how many of the RING rays the reading is taken from
const LOOKAHEAD := 0.30      ## how far up the passage the second ring is cast
const WEDGE_PRESSURE := 0.90
const WEDGE_STALL := 0.70   ## seconds of asking to go forward before it counts as not going
const WEDGE_CREEP := 0.020  ## and how little ground you have to make in that time
const WEDGE_SHRANK := 0.012 ## how much smaller you have to get for the rock to let you go

## Extra headroom a roomier posture must find before you take it. Dropping is instant - the
## ceiling is right there - but standing up waits for real room, or a passage that hovers
## around 75 cm has you bobbing onto your knees and back down twice a second. Nobody caves
## like that: once you are down, you stay down until it is clearly worth getting up.
const POSTURE_HYSTERESIS := 0.09

var posture := STAND
var posture_blend := 0.0    ## 0..1 eased height between the last posture and this one
var forced_low := false     ## the player asked to be lower than the ceiling requires

var chest := CHEST_RELAXED
var exhale := 0.0           ## 0 relaxed, 1 fully emptied
var air := 1.0              ## how much of a held exhale is left
var air_locked := false     ## ran out; cannot exhale again until AIR_REARM

var pressure := 0.0
var headroom := HEAD_REACH
var width := RING_REACH * 2.0
var clearances := PackedFloat32Array()
var tightest_dir := Vector3.ZERO

var wedged := false
var _stall := 0.0
var _stall_from := Vector3.ZERO
var _wedge_box := Vector2.ZERO
var _wedge_at := Vector3.ZERO

func _init() -> void:
	clearances.resize(RING)

# ---------------------------------------------------------------- shape

static func box_of(p: Dictionary, chest_depth: float) -> Vector2:
	var gear: float = p.get("gear", 0.04)
	var w: float = p["w"]
	var h: float = p["h"]
	match p.get("chest", "none"):
		"w": w = chest_depth + gear
		"h": h = chest_depth + gear
	return Vector2(w, h)

## The box the body currently has to push through the rock: x across, y through.
func box() -> Vector2:
	return box_of(POSTURES[posture], chest)

func speed() -> float:
	return POSTURES[posture]["speed"]

func eye_height() -> float:
	return POSTURES[posture]["eye"]

func label() -> String:
	return POSTURE_LABEL.get(POSTURES[posture]["name"], "")

func name_of() -> String:
	return POSTURES[posture]["name"]

## Would this posture fit the space we have just measured? `margin` is the extra room a
## roomier posture has to find before it is worth standing back up - see choose_posture.
func fits(i: int, margin := 0.0) -> bool:
	var b := box_of(POSTURES[i], chest)
	return b.y + margin <= headroom + 0.02 and b.x + margin <= width + 0.02

# ---------------------------------------------------------------- breath

func breathe(want: float, delta: float) -> void:
	if air_locked:
		want = 0.0
		if air >= AIR_REARM:
			air_locked = false
	var rate := EXHALE_IN if want > exhale else EXHALE_OUT
	exhale = move_toward(exhale, clampf(want, 0.0, 1.0), rate * delta)
	if exhale > 0.15:
		air = maxf(air - AIR_DRAIN * delta * exhale, 0.0)
		if air <= 0.0:
			# Your body takes the decision back. This is not a punishment - it just means the
			# squeeze has to be solved again, and the next attempt starts from further back.
			air_locked = true
	else:
		air = minf(air + AIR_REGAIN * delta, 1.0)
	chest = CHEST_RELAXED - CHEST_SQUEEZE * exhale

## Seconds of squeeze left before your chest opens again, for the slate.
func breath_left() -> float:
	if exhale <= 0.15:
		return 0.0
	return air / maxf(AIR_DRAIN * exhale, 0.001)

# ---------------------------------------------------------------- reading the rock

## Measure the space around a point. `basis` is the body's frame: x across the passage,
## y up it, z back along the way you came, so the ring is cast in the x/y plane - the
## cross-section you actually have to fit through, not an arbitrary horizontal slice.
##
## The ring is what makes a passage feel narrow before it stops you. Godot will happily let a
## capsule slide along a wall with no complaint at all; the ring notices that the wall is
## 4 cm away and says so, which is the entire difference between a corridor and a squeeze.
func probe(space: PhysicsDirectSpaceState3D, centre: Vector3, basis: Basis, foot: Vector3) -> void:
	var b := box()
	var hw: float = maxf(b.x * 0.5, 0.02)
	var hh: float = maxf(b.y * 0.5, 0.02)

	# Two rings: one at the chest, one a body's-length ahead of it. The near ring is the rock
	# you are touching; the far ring is the rock you are about to be in, and in a passage that
	# narrows those are not the same reading. Measuring only the chest means a caver stopped
	# dead by a pinch 30 cm in front of them reports plenty of room, because the pinch is not
	# at their chest yet - which is the one moment the number most needs to be right.
	var near := _ring(space, centre, basis, hw, hh, true)
	var ahead := _ring(space, centre - basis.z * LOOKAHEAD, basis, hw, hh, false)
	pressure = clampf((maxf(near, ahead) - CONTACT_FLOOR) / CONTACT_SPAN, 0.0, 1.0)

	# Headroom is measured from the floor, not from the chest, because that is the number that
	# decides whether you could stand up here if you wanted to.
	headroom = _cast(space, foot + basis.y * 0.04, basis.y, HEAD_REACH) + 0.04
	var left := _cast(space, centre, -basis.x, RING_REACH)
	var right := _cast(space, centre, basis.x, RING_REACH)
	width = left + right

## One ring of rays in the plane across the passage, reported as occupancy: the worst few
## values of "how much of the room along this line is me". `keep` stores the raw distances
## for anything that wants the shape rather than the number.
func _ring(space: PhysicsDirectSpaceState3D, centre: Vector3, basis: Basis,
		hw: float, hh: float, keep: bool) -> float:
	var fill := PackedFloat32Array()
	fill.resize(RING)
	var worst := 0.0
	for i in RING:
		var a := TAU * float(i) / float(RING)
		var ca := cos(a)
		var sa := sin(a)
		var dir: Vector3 = (basis.x * ca + basis.y * sa).normalized()
		var d := _cast(space, centre, dir, RING_REACH)
		if keep:
			clearances[i] = d
		# How far the body itself reaches along this line: the radius of the body's own
		# cross-section ellipse at this angle.
		var reach: float = 1.0 / sqrt((ca / hw) * (ca / hw) + (sa / hh) * (sa / hh))
		fill[i] = clampf(reach / maxf(d, 0.004), 0.0, 1.4)
		if keep and fill[i] > worst:
			worst = fill[i]
			tightest_dir = dir
	var sorted := Array(fill)
	sorted.sort()
	sorted.reverse()
	var sum := 0.0
	var n: int = mini(CONTACT_WORST, sorted.size())
	for i in n:
		sum += sorted[i]
	return sum / float(maxi(n, 1))

func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, reach: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return reach
	return from.distance_to(hit["position"])

# ---------------------------------------------------------------- posture

## Pick the roomiest posture the space allows, unless the player has asked to go lower.
##
## This is automatic on purpose. In a real cave nobody decides to crouch - the ceiling decides
## for them, and the only real choice is whether to go lower still than you have to, which is
## what `want_low` is for. Taking the routine choice away leaves the interesting one.
func choose_posture(want_low: bool, want_high: bool, delta: float) -> void:
	if want_low:
		forced_low = true
	if want_high:
		forced_low = false

	var best := SUPERMAN
	for i in POSTURES.size():
		# Standing back up needs the margin; staying where you are, or going lower, does not.
		var margin: float = POSTURE_HYSTERESIS if i < posture else 0.0
		if fits(i, margin):
			best = i
			break
	if forced_low:
		# One step tighter than the rock demands, but never past the last posture that fits.
		var lower := mini(best + 1, POSTURES.size() - 1)
		while lower < POSTURES.size() and not fits(lower):
			lower += 1
		if lower < POSTURES.size():
			best = lower
	if best != posture:
		posture = best
		posture_blend = 0.0
	posture_blend = minf(posture_blend + delta * 3.4, 1.0)

# ---------------------------------------------------------------- wedged

## Wedged is a movement state, not a death. The rock is holding you, ordinary movement does
## nothing, and the way out is the way in reversed: empty your chest, change shape, back off.
## There is no timer and nothing is counting down - working it out IS the thing.
##
## Progress is measured over a window rather than per frame, because a real squeeze is not
## stationary, it is slow: four centimetres a second with the rock on both shoulders is
## movement, and a per-frame threshold would call it being stuck.
##
## The escape that matters is the size one. You got held at a particular shape; get
## meaningfully smaller than that shape and the rock lets go, whether or not you have managed
## to move yet. Without this the only ways out are pressure dropping - which it will not,
## because you are still in the same slot - or moving, which you cannot. Emptying your chest
## has to be an answer here, or the mechanic the whole cave is built around does nothing at
## the one moment it is supposed to matter.
func update_wedge(asking_forward: bool, pos: Vector3, delta: float) -> void:
	if wedged:
		var b := box()
		var shrank: bool = (_wedge_box.x - b.x) > WEDGE_SHRANK or (_wedge_box.y - b.y) > WEDGE_SHRANK
		if shrank or pressure < WEDGE_PRESSURE - 0.10 or pos.distance_to(_wedge_at) > 0.06:
			wedged = false
			_stall = 0.0
			_stall_from = pos
		return
	# You can only be wedged in a shape the chest is part of. Standing against a wall you
	# cannot walk through is not being wedged, it is being somewhere you should not be - and
	# calling it wedged would be a trap, because the way out of a wedge is to empty your chest
	# and a standing body's size does not depend on its chest at all.
	if POSTURES[posture].get("chest", "none") == "none":
		_stall = 0.0
		return
	if asking_forward and pressure >= WEDGE_PRESSURE:
		if _stall <= 0.0:
			_stall_from = pos
		_stall += delta
		if _stall >= WEDGE_STALL:
			if pos.distance_to(_stall_from) < WEDGE_CREEP:
				wedged = true
				_wedge_box = box()
				_wedge_at = pos
			_stall = 0.0
			_stall_from = pos
	else:
		_stall = 0.0

## What the slate should say. Never a scolding, and never silent when you are stuck.
func advice() -> String:
	if wedged:
		return "WEDGED - empty your chest and back off"
	if pressure > 0.80 and exhale < 0.3:
		return "tight - try breathing out"
	if air_locked:
		return "out of breath - let your chest open"
	if posture >= BELLY and headroom > 1.0 and not forced_low:
		return ""
	return ""
