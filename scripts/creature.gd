extends Node3D
class_name Creature
## The night stalker's body: a posable rig built from kit/creature_rig.json (authored in
## tools/creature_spec.py, which also renders the reference sheet in docs/).
##
## Anatomy: humanoid frame gone wrong - a lizard's soft snout on a human skull, horns sweeping
## down past the jaw, claws instead of fingers, spore growths up the shins, a tail, and wine-dark
## runes painted over the hide. The hide is near black on purpose: it has to vanish in an unlit
## corridor and only resolve when your flashlight finds it.
##
## Movement: it does not animate, it *snaps*. Poses are held, then changed between frames, with a
## per-joint jitter on top - the look of something whose joints dislocate and reseat as it walks.
## It travels belly up on all fours, head first, which is only geometrically possible if the body
## is also mirrored - that is the pose data's doing, and it is what makes the walk read as wrong.
## Standing still it comes upright, because a thing that stands up when it stops is worse.

const RIG_PATH := "res://kit/creature_rig.json"

## Poses it picks between while walking, and the odd broken frame it drops into mid-stride.
const WALK_CYCLE := ["crawl_a", "crawl_b"]
const BREAK_POSES := ["dislocate", "contort"]

var moving := false                  ## walking (belly-up crawl) vs. immobile (stands upright)
var glitch := 1.0                    ## 0 = still, 1 = normal, higher = more frequent contortions
var step_time := 0.42                ## seconds a stride pose is held
var _rig: Dictionary = {}
var _bones: Dictionary = {}          # name -> Node3D
var _rest: Dictionary = {}           # name -> rest position (bone offset)
var _mats: Dictionary = {}           # material key -> StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _pose: Dictionary = {}           # name -> current Vector3 of euler degrees
var _target: Dictionary = {}         # name -> where it is snapping to
var _root_y := 0.0
var _target_root_y := 0.0
var _timer := 0.0
var _hold := 0.0
var _cycle := 0
var _rng := RandomNumberGenerator.new()

static var _cache: Dictionary = {}

func _ready() -> void:
	_rng.randomize()
	_rig = _load_rig()
	_build_materials()
	_build_skeleton()
	set_pose("upright", true)

static func _load_rig() -> Dictionary:
	if _cache.has(RIG_PATH):
		return _cache[RIG_PATH]
	var f := FileAccess.open(RIG_PATH, FileAccess.READ)
	assert(f != null, "creature rig missing: " + RIG_PATH)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	_cache[RIG_PATH] = data
	return data

func _build_materials() -> void:
	for key: String in _rig["materials"]:
		var m: Dictionary = _rig["materials"][key]
		var mat := StandardMaterial3D.new()
		var a: Array = m["albedo"]
		mat.albedo_color = Color(a[0], a[1], a[2])
		mat.roughness = m["roughness"]
		mat.metallic = 0.0
		var e: Array = m["emission"]
		if e[0] + e[1] + e[2] > 0.0:
			mat.emission_enabled = true
			mat.emission = Color(e[0], e[1], e[2]).clamp()
			mat.emission_energy_multiplier = 1.0
		_mats[key] = mat
	_eye_mat = _mats["eye"]

## One Node3D per bone, with every part on that bone merged into a single mesh (one surface per
## material). 29 nodes for the whole creature instead of 300-odd MeshInstance3Ds.
func _build_skeleton() -> void:
	var by_bone := {}
	for p: Dictionary in _rig["parts"]:
		by_bone.get_or_add(p["bone"], []).append(p)

	for b: Dictionary in _rig["bones"]:
		var name: String = b["name"]
		var node := Node3D.new()
		node.name = name
		var off: Array = b["offset"]
		node.position = Vector3(off[0], off[1], off[2])
		_rest[name] = node.position
		var parent: String = b["parent"]
		if parent == "":
			add_child(node)
		else:
			_bones[parent].add_child(node)
		_bones[name] = node
		_pose[name] = Vector3.ZERO
		_target[name] = Vector3.ZERO
		var parts: Array = by_bone.get(name, [])
		if not parts.is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = _merge(parts)
			mi.name = "%s_mesh" % name
			node.add_child(mi)
			_meshes.append(mi)

func _merge(parts: Array) -> ArrayMesh:
	var tools := {}
	for p: Dictionary in parts:
		var key: String = p["mat"]
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
		var src := _primitive(p)
		if src:
			tools[key].append_from(src, 0, _part_transform(p))
	var mesh := ArrayMesh.new()
	for key: String in tools:
		tools[key].commit(mesh)   # the primitives already carry normals; append_from transforms them
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mats[key])
	return mesh

## Godot primitives matching the three shapes the rig is authored from. "cone" is a tapered
## cylinder growing along +Y from its origin - limbs, horns, claws, quills and the tail.
func _primitive(p: Dictionary) -> Mesh:
	match String(p["shape"]):
		"box":
			var box := BoxMesh.new()
			var s: Array = p["size"]
			box.size = Vector3(s[0], s[1], s[2])
			return box
		"sph":
			var sph := SphereMesh.new()
			sph.radius = 0.5                  # unit sphere; the part transform scales it
			sph.height = 1.0
			sph.radial_segments = 10
			sph.rings = 5
			return sph
		_:
			var cyl := CylinderMesh.new()
			cyl.bottom_radius = p["r"]
			cyl.top_radius = maxf(p["r2"], 0.0005)
			cyl.height = maxf(p["h"], 0.001)
			cyl.radial_segments = 8
			cyl.rings = 1
			return cyl

func _part_transform(p: Dictionary) -> Transform3D:
	var pos: Array = p["pos"]
	var rot: Array = p["rot"]
	var basis := Basis.from_euler(Vector3(deg_to_rad(rot[0]), deg_to_rad(rot[1]), deg_to_rad(rot[2])))
	var xf := Transform3D(basis, Vector3(pos[0], pos[1], pos[2]))
	match String(p["shape"]):
		"sph":
			var s: Array = p["size"]
			xf.basis = xf.basis.scaled(Vector3(s[0], s[1], s[2]))
		"cone":
			xf = xf.translated_local(Vector3(0, p["h"] * 0.5, 0))   # Godot's cylinder is centred
	return xf

# ---------------------------------------------------------------- posing
## Set the pose. `snap` applies it on this frame (the glitch); otherwise it is eased into.
func set_pose(name: String, snap := false) -> void:
	var pose: Dictionary = _rig["poses"][name]
	var bones: Dictionary = pose["bones"]
	for bone: String in _bones:
		var a: Array = bones.get(bone, [0, 0, 0])
		_target[bone] = Vector3(a[0], a[1], a[2])
	_target_root_y = pose["root_pos"][1]
	if snap:
		for bone: String in _bones:
			_pose[bone] = _target[bone]
		_root_y = _target_root_y
	_apply()

func _apply() -> void:
	for bone: String in _bones:
		var e: Vector3 = _pose[bone]
		var node: Node3D = _bones[bone]
		node.rotation = Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z))
	var root: Node3D = _bones["root"]
	root.position = Vector3(_rest["root"].x, _rest["root"].y + _root_y, _rest["root"].z)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _hold:
		_timer = 0.0
		_next_pose()
	# joints ease toward the pose, but only most of the way - the last of it is never resolved,
	# which is what keeps the silhouette shivering
	var k := clampf(delta * 22.0, 0.0, 1.0)
	for bone: String in _bones:
		var jitter := Vector3.ZERO
		if glitch > 0.0 and _rng.randf() < 0.06 * glitch:
			jitter = Vector3(_rng.randfn(0.0, 2.4), _rng.randfn(0.0, 2.4), _rng.randfn(0.0, 2.4))
		_pose[bone] = _pose[bone].lerp(_target[bone] + jitter, k)
	_root_y = lerpf(_root_y, _target_root_y, k)
	_apply()

## Picks what it does next: stride, stride, then every so often a frame in a shape a body cannot
## hold. Standing still it comes upright and only twitches.
func _next_pose() -> void:
	if moving:
		if glitch > 0.0 and _rng.randf() < 0.18 * glitch:
			set_pose(BREAK_POSES[_rng.randi() % BREAK_POSES.size()], true)
			_hold = _rng.randf_range(0.08, 0.22)
			return
		_cycle = (_cycle + 1) % WALK_CYCLE.size()
		set_pose(WALK_CYCLE[_cycle], true)
		_hold = step_time * _rng.randf_range(0.8, 1.2)
	else:
		if glitch > 0.0 and _rng.randf() < 0.25 * glitch:
			set_pose("freeze", true)
			_hold = _rng.randf_range(0.1, 0.5)
		else:
			set_pose("upright")
			_hold = _rng.randf_range(0.7, 2.2)

## The jumpscare shape, held.
func lunge_pose() -> void:
	set_pose("lunge", true)
	_hold = 99.0

## Flatten the whole body to one unlit colour and hand the material back, so it can be faded out.
## The daytime apparitions are a silhouette of this same thing: what crosses a doorway at the far
## end of a corridor is recognisably what walks the station at night.
func make_silhouette(col := Color(0, 0, 0, 1)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for mi in _meshes:
		mi.material_override = m
	return m

## Eyes only catch the light from the second night on.
func set_eye_glow(energy: float) -> void:
	_eye_mat.emission_energy_multiplier = energy
	_eye_mat.albedo_color = Color(0.4, 0.04, 0.02) * clampf(energy, 0.2, 1.0)

## Height of the head above the creature's origin right now - for the breath sound and the stare.
func head_position() -> Vector3:
	return _bones["head"].global_position
