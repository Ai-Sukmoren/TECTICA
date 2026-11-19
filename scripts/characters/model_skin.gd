extends Node3D
## Skinned character model (e.g. Quaternius SWAT) driven by the procedural
## SoldierRig. The rig keeps doing all the animation work (locomotion, aim,
## reload hand paths, vault, kick, death...) with its own meshes hidden; every
## frame this copies its pose onto the model's skeleton:
##   * torso / head / hips: bone directions follow the matching rig joints
##   * arms and legs: two-bone IK so hands land on the rig's hands (which hold
##     the gun) and feet on the rig's planted feet, bending toward the rig's
##     elbows / knees
## In first person the model only casts shadows; its arms (fp_arms, a copy of
## just the arm triangles) are drawn, or the rig's own arms when it has none.

## [model bone, rig node property, index or -1, primary axis, secondary axis]
## Axes are in the rig node's local space. Rig limbs point down -Y and face -Z.
const DIRECT := [
	["Body", "hips", -1, Vector3.UP, Vector3.FORWARD],
	["Hips", "hips", -1, Vector3.UP, Vector3.FORWARD],
	["Abdomen", "spine", -1, Vector3.UP, Vector3.FORWARD],
	["Torso", "spine", -1, Vector3.UP, Vector3.FORWARD],
	["Chest", "chest", -1, Vector3.UP, Vector3.FORWARD],
	["Head", "head", -1, Vector3.UP, Vector3.FORWARD],
]
## [upper bone, lower bone, end bone, rig index, rig upper, rig mid, rig end, end primary, end secondary]
const CHAINS := [
	["UpperArm.L", "LowerArm.L", "Wrist.L", 0, "shoulders", "elbows", "hands", Vector3.DOWN, Vector3.FORWARD],
	["UpperArm.R", "LowerArm.R", "Wrist.R", 1, "shoulders", "elbows", "hands", Vector3.DOWN, Vector3.FORWARD],
	["UpperLeg.L", "LowerLeg.L", "Foot.L", 0, "thighs", "shins", "feet", Vector3.FORWARD, Vector3.UP],
	["UpperLeg.R", "LowerLeg.R", "Foot.R", 1, "thighs", "shins", "feet", Vector3.FORWARD, Vector3.UP],
]
## The same bones on a 3ds Max biped rig (e.g. the casual low-poly characters),
## tried when a Quaternius name is missing. A biped has no separate Body bone:
## its pelvis is the root that follows the rig's hips.
const BIPED := {
	"Hips": "bip Pelvis", "Abdomen": "bip Spine", "Chest": "bip Spine1", "Head": "bip Head",
	"UpperArm.L": "bip L UpperArm", "LowerArm.L": "bip L Forearm", "Wrist.L": "bip L Hand",
	"UpperArm.R": "bip R UpperArm", "LowerArm.R": "bip R Forearm", "Wrist.R": "bip R Hand",
	"UpperLeg.L": "bip L Thigh", "LowerLeg.L": "bip L Calf", "Foot.L": "bip L Foot",
	"UpperLeg.R": "bip R Thigh", "LowerLeg.R": "bip R Calf", "Foot.R": "bip R Foot",
}
## How far back from the rig's palm centre the model's wrist goes, as a share
## of the model's wrist-to-knuckle length.
const PALM_BACK := 0.6
## The same bones on a Mixamo auto-rig, without its "mixamorig:" prefix (which
## differs between exports, so _find() matches any prefix).
const MIXAMO := {
	"Hips": "Hips", "Abdomen": "Spine", "Chest": "Spine2", "Head": "Head",
	"UpperArm.L": "LeftArm", "LowerArm.L": "LeftForeArm", "Wrist.L": "LeftHand",
	"UpperArm.R": "RightArm", "LowerArm.R": "RightForeArm", "Wrist.R": "RightHand",
	"UpperLeg.L": "LeftUpLeg", "LowerLeg.L": "LeftLeg", "Foot.L": "LeftFoot",
	"UpperLeg.R": "RightUpLeg", "LowerLeg.R": "RightLeg", "Foot.R": "RightFoot",
}
## The same bones on a Character Creator (Reallusion) rig. Exports number
## every bone ("CC_Base_L_Upperarm_050"), so _find() ignores that suffix.
const CC := {
	"Hips": "CC_Base_Hip", "Abdomen": "CC_Base_Waist", "Chest": "CC_Base_Spine02", "Head": "CC_Base_Head",
	"UpperArm.L": "CC_Base_L_Upperarm", "LowerArm.L": "CC_Base_L_Forearm", "Wrist.L": "CC_Base_L_Hand",
	"UpperArm.R": "CC_Base_R_Upperarm", "LowerArm.R": "CC_Base_R_Forearm", "Wrist.R": "CC_Base_R_Hand",
	"UpperLeg.L": "CC_Base_L_Thigh", "LowerLeg.L": "CC_Base_L_Calf", "Foot.L": "CC_Base_L_Foot",
	"UpperLeg.R": "CC_Base_R_Thigh", "LowerLeg.R": "CC_Base_R_Calf", "Foot.R": "CC_Base_R_Foot",
}
## Height of the rig's foot joint above the sole (SoldierRig.ANKLE_H).
const RIG_ANKLE := 0.088

const ZombieSkin = preload("res://scripts/characters/zombie_skin.gd")

var rig: Node3D
var model: Node3D
var skel: Skeleton3D
var meshes: Array[MeshInstance3D] = []

var _order: PackedInt32Array = []
var _rest_g: Array[Transform3D] = []     # global (skeleton-space) rest per bone
var _rest_l: Array[Transform3D] = []     # local rest per bone
var _g: Array[Transform3D] = []          # working global poses
var _direct := {}                        # bone -> [node getter, primary, secondary]
var _chains: Array = []                  # resolved CHAINS
var _clav := {}                          # collarbone -> [its upper arm bone, rig side index]
var _body_off := Vector3.ZERO            # Body origin relative to the rig hip point, in Body rest frame
var _foot_lift := 0.0                    # model foot bone height above the sole at rest
var _first_person := false
var _curl := {}                          # finger bone -> extra bend (radians, round _curl_axis)
var _curl_axis := {}                     # finger bone -> its bend axis (local)
var _axis := {}                          # bone -> its length direction in its own rest frame
var _root := -1                          # bone placed at the rig's hips (Body, or a biped's pelvis)
var _rest_fwd := Vector3.BACK            # model forward (+Z) in skeleton space
var _rest_up := Vector3.UP               # model up in skeleton space
## Bend per finger joint (knuckle, middle, tip) and for the thumb. Negative =
## toward the palm on the Quaternius rig (positive bends fingers backwards).
const GRIP_CURL := [-0.9, -1.0, -0.6]
const THUMB_CURL := -0.35
static var curl_sign := 1.0   # test hook (tools/preview_soldiers.gd "curlneg")
## 3ds Max biped fingers (Finger0 = thumb, Finger1 = the fingers as one mitten).
const BIPED_FINGERS := [["Finger1", -0.9], ["Finger11", -1.1], ["Finger0", -0.3], ["Finger01", -0.35]]

## Only the model's arms (upper arm to fingertips), shown in first person in
## place of the rig's arms. Built the first time first person is switched on
## (bots and zombies never need them); empty when the model has no arm bones.
var fp_arms: Array[MeshInstance3D] = []
var _fp_arms_built := false
## Off: first person keeps the rig's own slim arms (for a model whose bulky
## sleeves would hide the gun from the eye camera).
var use_fp_arms := true


## `path`: glTF/GLB scene. `tint`: multiplies every albedo (Color.WHITE = as is).
## `hide_meshes`: mesh names inside the model to hide (e.g. a built-in prop).
func setup(p_rig: Node3D, path: String, tint: Color = Color.WHITE, hide_meshes: Array = []) -> bool:
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("model_skin: cannot load " + path)
		return false
	return setup_scene(p_rig, ps, tint, hide_meshes)


## As setup(), from a scene already in memory (e.g. one zombie split out of a pack).
func setup_scene(p_rig: Node3D, ps: PackedScene, tint: Color = Color.WHITE, hide_meshes: Array = []) -> bool:
	rig = p_rig
	var path := ps.resource_path
	model = ps.instantiate() as Node3D
	model.rotation.y = PI          # glTF characters face +Z, the rig faces -Z
	add_child(model)
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("model_skin: no skeleton in " + path)
		return false
	skel = found[0]
	# a pack can hold several characters, each on its own skeleton: drive the one
	# the visible skinned mesh is bound to, not merely the first one found
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin != null and not String(mi.name) in hide_meshes:
			var bound := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			if bound != null:
				skel = bound
				break
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
		(ap as AnimationPlayer).active = false
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if String(mi.name) in hide_meshes:
			mi.visible = false
			continue
		mi.extra_cull_margin = 0.6       # posed far from the bind pose (crouch, death)
		if tint != Color.WHITE:
			_tint(mi, tint)
		meshes.append(mi)
	_prepare()
	return true


## Severed limbs: these bones (and all below them) are shrunk to nothing.
var hidden_bones := {}


## Takes a limb off the model: `key` "arm0" / "leg1" ... (0 = left), `at` "upper" / "lower".
func hide_limb(key: String, at: String) -> void:
	if skel == null:
		return
	var b := ZombieSkin._limb_bone(skel, key.begins_with("arm"), int(key.right(1)), at == "upper")
	if b >= 0:
		hidden_bones[b] = true


func _tint(mi: MeshInstance3D, tint: Color) -> void:
	if mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s)
		if src is BaseMaterial3D:
			var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			m.albedo_color = m.albedo_color * tint
			mi.set_surface_override_material(s, m)


func _prepare() -> void:
	var n := skel.get_bone_count()
	_rest_g.resize(n)
	_rest_l.resize(n)
	_g.resize(n)
	for i in n:
		_rest_l[i] = skel.get_bone_rest(i)
		_rest_g[i] = skel.get_bone_global_rest(i)
	# parents before children
	var roots: Array[int] = []
	for i in n:
		if skel.get_bone_parent(i) < 0:
			roots.append(i)
	var stack: Array[int] = roots.duplicate()
	stack.reverse()
	while not stack.is_empty():
		var b: int = stack.pop_back()
		_order.append(b)
		var kids := skel.get_bone_children(b)
		for k in range(kids.size() - 1, -1, -1):
			stack.append(kids[k])
	# the model's forward / up in skeleton space (a Z-up FBX skeleton is turned by its node)
	var to_model := Transform3D.IDENTITY
	var pn: Node = skel
	while pn != null and pn != model:
		to_model = (pn as Node3D).transform * to_model
		pn = pn.get_parent()
	var inv := to_model.basis.orthonormalized().inverse()
	_rest_fwd = (inv * Vector3.BACK).normalized()
	_rest_up = (inv * Vector3.UP).normalized()
	# each bone's length direction: towards the child that carries on the line from
	# its parent (glTF bones run along +Y; biped bones do not, and a biped hand's
	# first child is the thumb, which would aim the whole hand sideways)
	for i in n:
		var kids := skel.get_bone_children(i)
		_axis[i] = Vector3.UP
		var incoming := _rest_l[i].basis.inverse() * _rest_l[i].origin   # parent -> bone, in bone space
		var best := -2.0
		for k in kids:
			var d := _rest_l[k].origin
			if d.length() <= 0.001:
				continue
			var score := d.normalized().dot(incoming.normalized()) if incoming.length() > 0.001 else (1.0 if k == kids[0] else -1.0)
			if score > best:
				best = score
				_axis[i] = d.normalized()
		if best == -2.0 and incoming.length() > 0.001 and skel.get_bone_parent(i) >= 0 and not kids.is_empty():
			# only children sitting on the joint (a Character Creator head): carry
			# on along the line from the parent, not the bone's own +Y
			_axis[i] = incoming.normalized()
	for d in DIRECT:
		var bi := _find(d[0])
		if bi >= 0:
			_direct[bi] = d
	_root = _find("Body")
	if _root < 0 and (skel.find_bone("Hips") < 0 or _mixamo_prefix() != ""):
		_root = _find("Hips")   # biped / Mixamo: the pelvis is the root
	for c in CHAINS:
		var u := _find(c[0])
		var l := _find(c[1])
		var e := _find(c[2])
		if u < 0 or l < 0 or e < 0:
			continue
		# wrist-to-knuckle length: the rig's hand joint is the palm centre, the model's is the wrist
		var palm := 0.0
		for k in skel.get_bone_children(e):
			palm = maxf(palm, _rest_l[k].origin.dot(_axis[e]))
		var clav := skel.get_bone_parent(u)
		if c[4] == "shoulders" and clav >= 0 and not _direct.has(clav):
			_clav[clav] = [u, c[3]]
		_chains.append({"u": u, "l": l, "e": e, "i": c[3], "ru": c[4], "rm": c[5], "re": c[6], "ep": c[7], "es": c[8], "palm": palm,
			"a": _rest_g[u].origin.distance_to(_rest_g[l].origin),
			"b": _rest_g[l].origin.distance_to(_rest_g[e].origin)})
	# the rig's hip joint sits at (0, HIP_STAND, 0) in its own space at rest,
	# which is the same point in skeleton space (model is only turned around Y)
	var body := skel.find_bone("Body")
	if body >= 0:
		var hip_point := Vector3(0, 0.93, 0)
		_body_off = _rest_g[body].basis.inverse() * (_rest_g[body].origin - hip_point)
	# fingers closed around a grip (the rest pose is an open hand)
	for side in [".L", ".R"]:
		for f in ["Index", "Middle", "Ring", "Pinky"]:
			for k in 3:
				var fb := skel.find_bone("%s%d%s" % [f, k + 1, side])
				if fb >= 0:
					_curl[fb] = GRIP_CURL[k]
		for k in 2:
			var tb := skel.find_bone("Thumb%d%s" % [k + 2, side])
			if tb >= 0:
				_curl[tb] = THUMB_CURL
		var bs := " L " if side == ".L" else " R "
		for f in BIPED_FINGERS:
			var bb := skel.find_bone("bip" + bs + String(f[0]))
			if bb >= 0:
				_curl[bb] = f[1]
				_curl_axis[bb] = Vector3.FORWARD   # biped bones run along X and bend round Z
	var foot := _find("Foot.R")
	if foot >= 0:
		_foot_lift = _rest_g[foot].origin.dot(_rest_up)
	# a biped (no Body bone) of another height: scale it so its pelvis sits on the
	# rig's hip joint, or its legs could not reach the rig's feet
	if _root >= 0 and skel.find_bone("Body") < 0:
		var pelvis_h := (to_model * _rest_g[_root]).origin.y
		if pelvis_h > 0.3:
			model.scale = Vector3.ONE * (0.93 / pelvis_h)
			_foot_lift *= 1.0   # skeleton space: unchanged by the model scale


## Copies the triangles skinned mostly to the arm bones into fp_arms meshes,
## sharing the model's skeleton, skin and materials.
func _build_fp_arms() -> void:
	_fp_arms_built = true
	var arm := {}
	for key in ["UpperArm.L", "UpperArm.R"]:
		var stack: Array[int] = [_find(key)]
		while not stack.is_empty():
			var b: int = stack.pop_back()
			if b < 0:
				continue
			arm[b] = true
			stack.append_array(skel.get_bone_children(b))
	if arm.is_empty():
		return
	for mi in meshes:
		if mi.mesh == null or mi.skin == null:
			continue
		var bind_bone := PackedInt32Array()   # skin bind index -> skeleton bone
		for i in mi.skin.get_bind_count():
			var bb := mi.skin.get_bind_bone(i)
			bind_bone.append(bb if bb >= 0 else skel.find_bone(mi.skin.get_bind_name(i)))
		var out := ArrayMesh.new()
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones.is_empty():
				continue
			var per := bones.size() / verts.size()
			var on_arm := PackedByteArray()
			on_arm.resize(verts.size())
			for v in verts.size():
				var w := 0.0
				for k in per:
					var bi := bones[v * per + k]
					if bi < bind_bone.size() and arm.has(bind_bone[bi]):
						w += weights[v * per + k]
				on_arm[v] = 1 if w >= 0.5 else 0
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				for v in verts.size():
					idx.append(v)
			var keep := PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				if on_arm[idx[t]] and on_arm[idx[t + 1]] and on_arm[idx[t + 2]]:
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			if keep.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = keep
			# custom vertex channels would need their packed formats passed along;
			# the arms draw without them
			for ch in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
				arrays[ch] = null
			var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
			out.surface_set_material(out.get_surface_count() - 1, mi.get_active_material(si))
		if out.get_surface_count() == 0:
			continue
		var a := MeshInstance3D.new()
		a.name = String(mi.name) + "_FPArms"
		a.mesh = out
		a.skin = mi.skin
		a.transform = mi.transform
		a.extra_cull_margin = mi.extra_cull_margin
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.visible = _first_person
		mi.get_parent().add_child(a)
		a.skeleton = a.get_path_to(skel)
		fp_arms.append(a)


## A bone by its Quaternius name, or the biped bone that plays that part.
## Packs with several bipeds number every copy after the first ("bip Pelvis003")
## and renumber the spine ("bip Spine006"), so the spine is found by its place.
func _find(bone_name: String) -> int:
	var b := skel.find_bone(bone_name)
	if b < 0 and MIXAMO.has(bone_name):
		b = skel.find_bone(_mixamo_prefix() + String(MIXAMO[bone_name]))
	if b < 0 and CC.has(bone_name):
		b = _find_numbered(String(CC[bone_name]))
	if b >= 0 or not BIPED.has(bone_name):
		return b
	var bn := String(BIPED[bone_name])
	b = skel.find_bone(bn)
	if b < 0:
		b = skel.find_bone(bn + _biped_suffix())
	if b < 0 and bn.begins_with("bip Spine"):
		var spine := _biped_child(_find("Hips"), "bip Spine")
		b = spine if bn == "bip Spine" else _biped_child(spine, "bip Spine")
	return b


## A bone called `base` or `base` + "_" + a number.
func _find_numbered(base: String) -> int:
	var b := skel.find_bone(base)
	if b >= 0:
		return b
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		if nm.begins_with(base + "_") and nm.substr(base.length() + 1).is_valid_int():
			return i
	return -1


## "mixamorig:" (or however this export spells it) when the skeleton is a Mixamo rig, else "".
func _mixamo_prefix() -> String:
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		if nm.ends_with("Hips") and nm.to_lower().begins_with("mixamo"):
			return nm.left(nm.length() - 4)
	return ""


## The number a biped's bones carry in a multi-character pack ("" for the first).
func _biped_suffix() -> String:
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		if skel.get_bone_parent(i) < 0 and nm.begins_with("bip"):
			return nm.substr(3)
	return ""


func _biped_child(parent: int, prefix: String) -> int:
	if parent < 0:
		return -1
	for k in skel.get_bone_children(parent):
		if skel.get_bone_name(k).begins_with(prefix):
			return k
	return -1


func set_first_person(on: bool) -> void:
	_first_person = on
	if on and use_fp_arms and not _fp_arms_built and skel != null:
		_build_fp_arms()
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mi in meshes:
		mi.cast_shadow = mode
	for a in fp_arms:
		a.visible = on


# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if rig == null or skel == null or rig.get("hips") == null:
		return
	# The skin rides under the rig, so a frame the rig's LOD skipped keeps the last fit
	var posed = rig.get("posed_frame")
	if posed != null and posed != Engine.get_process_frames():
		return
	_retarget()


## Orthonormal frame from a primary direction and a secondary hint.
static func _frame(p: Vector3, s: Vector3) -> Basis:
	var x := p.normalized()
	var z := s - x * s.dot(x)
	if z.length_squared() < 1e-8:
		z = Vector3.FORWARD if absf(x.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		z = z - x * z.dot(x)
	z = z.normalized()
	return Basis(x, z.cross(x), z)


## Rotation taking a rest bone (primary = its length axis, secondary = rest hint) to the target directions.
func _aligned(rest: Basis, rest_secondary: Vector3, tp: Vector3, ts: Vector3, axis: Vector3 = Vector3.UP) -> Basis:
	var rb := rest.orthonormalized()
	var fr := _frame(rb * axis, rest_secondary)
	var ft := _frame(tp, ts)
	return (ft * fr.transposed()) * rb


func _rig_node(prop: String, idx: int) -> Node3D:
	var v = rig.get(prop)
	if idx >= 0:
		return (v as Array)[idx]
	return v


func _retarget() -> void:
	var to_skel := skel.global_transform.affine_inverse()
	var tb := to_skel.basis
	# model forward (+Z) / up (+Y) in skeleton space are the rest-pose hints
	var rest_fwd := _rest_fwd
	var rest_up := _rest_up
	var chain_of := {}
	for c in _chains:
		chain_of[c.u] = c
	var done := {}
	for b in _order:
		if done.has(b):
			continue
		var parent := skel.get_bone_parent(b)
		var pg: Transform3D = _g[parent] if parent >= 0 else Transform3D.IDENTITY
		if _direct.has(b):
			var d: Array = _direct[b]
			var node := _rig_node(d[1], d[2])
			var nb := node.global_transform.basis.orthonormalized()
			var basis := _aligned(_rest_g[b].basis, rest_fwd, tb * (nb * d[3]), tb * (nb * d[4]), _axis[b])
			var origin := pg * _rest_l[b].origin
			if b == _root:
				origin = to_skel * node.global_position + basis * _body_off
			_g[b] = Transform3D(basis, origin)
		elif chain_of.has(b):
			_solve_chain(chain_of[b], pg, to_skel, rest_fwd, rest_up)
			done[chain_of[b].l] = true
			done[chain_of[b].e] = true
		elif _clav.has(b):
			# the collarbone turns so the shoulder joint lands on the rig's shoulder
			# (the model's shoulders sit higher than the rig's, which would hold
			# the gun at chest height)
			var g := pg * _rest_l[b]
			var arm_at: Vector3 = g * _rest_l[_clav[b][0]].origin
			var want := to_skel * (rig.shoulders[_clav[b][1]] as Node3D).global_position
			var from := arm_at - g.origin
			var to := want - g.origin
			if from.length() > 0.001 and to.length() > 0.001:
				var q := Quaternion(from.normalized(), to.normalized())
				g.basis = Basis(q) * g.basis
			_g[b] = g
		elif _curl.has(b):
			_g[b] = pg * _rest_l[b] * Transform3D(Basis(_curl_axis.get(b, Vector3.RIGHT), _curl[b] * curl_sign), Vector3.ZERO)
		else:
			_g[b] = pg * _rest_l[b]
		done[b] = true
	for b in _order:
		var parent := skel.get_bone_parent(b)
		var local: Transform3D = (_g[parent].affine_inverse() * _g[b]) if parent >= 0 else _g[b]
		skel.set_bone_pose_position(b, local.origin)
		skel.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(b, Vector3.ONE * 0.001 if hidden_bones.has(b) else Vector3.ONE)


func _solve_chain(c: Dictionary, pg: Transform3D, to_skel: Transform3D, rest_fwd: Vector3, rest_up: Vector3) -> void:
	var tb := to_skel.basis
	var nu := _rig_node(c.ru, c.i)
	var nm := _rig_node(c.rm, c.i)
	var ne := _rig_node(c.re, c.i)
	var is_leg: bool = c.ru == "thighs"
	var p0: Vector3 = (pg * _rest_l[c.u]).origin
	var target: Vector3
	if is_leg:
		# the model's foot bone sits _foot_lift above the sole, the rig's foot joint RIG_ANKLE above it
		# _foot_lift is in skeleton units (centimetres on some exports): convert
		# it to the rig foot's own units before offsetting along the foot
		var lift := _foot_lift * skel.global_transform.basis.get_scale().y / ne.global_transform.basis.get_scale().y
		target = to_skel * (ne.global_transform * Vector3(0, lift - RIG_ANKLE, 0))
	else:
		# the model's wrist sits behind the rig's palm centre, back along the hand
		target = to_skel * ne.global_position + (tb * (ne.global_transform.basis * Vector3.UP)).normalized() * (float(c.palm) * PALM_BACK)
	var pole := to_skel * nm.global_position
	var a: float = c.a
	var bl: float = c.b
	var to_t := target - p0
	var dist := clampf(to_t.length(), 0.001, (a + bl) * 0.9995)
	var u := to_t.normalized() if to_t.length() > 0.001 else tb * (nu.global_transform.basis * Vector3.DOWN)
	var pv := (pole - p0) - u * (pole - p0).dot(u)
	if pv.length() < 0.0001:
		pv = tb * (nu.global_transform.basis * Vector3.FORWARD)
		pv -= u * pv.dot(u)
	pv = pv.normalized()
	var cos_a := clampf((a * a + dist * dist - bl * bl) / (2.0 * a * dist), -1.0, 1.0)
	var elbow := p0 + u * (a * cos_a) + pv * (a * sqrt(1.0 - cos_a * cos_a))
	var wrist := p0 + u * dist
	var ub := nu.global_transform.basis.orthonormalized()
	var mb := nm.global_transform.basis.orthonormalized()
	var eb := ne.global_transform.basis.orthonormalized()
	_g[c.u] = Transform3D(_aligned(_rest_g[c.u].basis, rest_fwd, elbow - p0, tb * (ub * Vector3.FORWARD), _axis[c.u]), p0)
	_g[c.l] = Transform3D(_aligned(_rest_g[c.l].basis, rest_fwd, wrist - elbow, tb * (mb * Vector3.FORWARD), _axis[c.l]), elbow)
	# the rig hand's FORWARD is its palm (the fingers curl that way); a T-posed
	# model hand has its palm facing down
	var end_hint: Vector3 = rest_up if is_leg else -rest_up
	_g[c.e] = Transform3D(_aligned(_rest_g[c.e].basis, end_hint, tb * (eb * c.ep), tb * (eb * c.es), _axis[c.e]), wrist)
