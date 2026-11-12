extends Node3D
## Skinned character model (e.g. Quaternius SWAT) driven by the procedural
## SoldierRig. The rig keeps doing all the animation work (locomotion, aim,
## reload hand paths, vault, kick, death...) with its own meshes hidden; every
## frame this copies its pose onto the model's skeleton:
##   * torso / head / hips: bone directions follow the matching rig joints
##   * arms and legs: two-bone IK so hands land on the rig's hands (which hold
##     the gun) and feet on the rig's planted feet, bending toward the rig's
##     elbows / knees
## In first person the model only casts shadows; the rig's own arms are shown.

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
## Height of the rig's foot joint above the sole (SoldierRig.ANKLE_H).
const RIG_ANKLE := 0.088

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
var _body_off := Vector3.ZERO            # Body origin relative to the rig hip point, in Body rest frame
var _foot_lift := 0.0                    # model foot bone height above the sole at rest
var _first_person := false
var _curl := {}                          # finger bone -> extra bend (radians, local X)
## Bend per finger joint (knuckle, middle, tip) and for the thumb. Negative =
## toward the palm on the Quaternius rig (positive bends fingers backwards).
const GRIP_CURL := [-0.9, -1.0, -0.6]
const THUMB_CURL := -0.35
static var curl_sign := 1.0   # test hook (tools/preview_soldiers.gd "curlneg")


## `path`: glTF/GLB scene. `tint`: multiplies every albedo (Color.WHITE = as is).
## `hide_meshes`: mesh names inside the model to hide (e.g. a built-in prop).
func setup(p_rig: Node3D, path: String, tint: Color = Color.WHITE, hide_meshes: Array = []) -> bool:
	rig = p_rig
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("model_skin: cannot load " + path)
		return false
	model = ps.instantiate() as Node3D
	model.rotation.y = PI          # glTF characters face +Z, the rig faces -Z
	add_child(model)
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("model_skin: no skeleton in " + path)
		return false
	skel = found[0]
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
	for d in DIRECT:
		var bi := skel.find_bone(d[0])
		if bi >= 0:
			_direct[bi] = d
	for c in CHAINS:
		var u := skel.find_bone(c[0])
		var l := skel.find_bone(c[1])
		var e := skel.find_bone(c[2])
		if u < 0 or l < 0 or e < 0:
			continue
		_chains.append({"u": u, "l": l, "e": e, "i": c[3], "ru": c[4], "rm": c[5], "re": c[6], "ep": c[7], "es": c[8],
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
	var foot := skel.find_bone("Foot.R")
	if foot >= 0:
		_foot_lift = _rest_g[foot].origin.y


func set_first_person(on: bool) -> void:
	_first_person = on
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for mi in meshes:
		mi.cast_shadow = mode


# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if rig == null or skel == null or rig.get("hips") == null:
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


## Rotation taking a rest bone (primary = its +Y, secondary = rest hint) to the target directions.
func _aligned(rest: Basis, rest_secondary: Vector3, tp: Vector3, ts: Vector3) -> Basis:
	var rb := rest.orthonormalized()
	var fr := _frame(rb.y, rest_secondary)
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
	var rest_fwd := Vector3.BACK
	var rest_up := Vector3.UP
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
			var basis := _aligned(_rest_g[b].basis, rest_fwd, tb * (nb * d[3]), tb * (nb * d[4]))
			var origin := pg * _rest_l[b].origin
			if skel.get_bone_name(b) == "Body":
				origin = to_skel * node.global_position + basis * _body_off
			_g[b] = Transform3D(basis, origin)
		elif chain_of.has(b):
			_solve_chain(chain_of[b], pg, to_skel, rest_fwd, rest_up)
			done[chain_of[b].l] = true
			done[chain_of[b].e] = true
		elif _curl.has(b):
			_g[b] = pg * _rest_l[b] * Transform3D(Basis(Vector3.RIGHT, _curl[b] * curl_sign), Vector3.ZERO)
		else:
			_g[b] = pg * _rest_l[b]
		done[b] = true
	for b in _order:
		var parent := skel.get_bone_parent(b)
		var local: Transform3D = (_g[parent].affine_inverse() * _g[b]) if parent >= 0 else _g[b]
		skel.set_bone_pose_position(b, local.origin)
		skel.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(b, Vector3.ONE)


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
		target = to_skel * (ne.global_transform * Vector3(0, _foot_lift - RIG_ANKLE, 0))
	else:
		target = to_skel * ne.global_position
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
	_g[c.u] = Transform3D(_aligned(_rest_g[c.u].basis, rest_fwd, elbow - p0, tb * (ub * Vector3.FORWARD)), p0)
	_g[c.l] = Transform3D(_aligned(_rest_g[c.l].basis, rest_fwd, wrist - elbow, tb * (mb * Vector3.FORWARD)), elbow)
	var end_hint: Vector3 = rest_up if is_leg else rest_fwd
	_g[c.e] = Transform3D(_aligned(_rest_g[c.e].basis, end_hint, tb * (eb * c.ep), tb * (eb * c.es)), wrist)
