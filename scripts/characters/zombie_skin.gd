extends Node3D
## A third-party animated model drawn in place of a zombie's built body (local
## only, not in the repository). The zombie keeps its own hidden rig, so hit
## zones, headshots, pathing and attacks work exactly as before; this node only
## draws, faces the zombie's aim and picks an animation from its speed.
##
##   "polyart"   — Polyart zombie pack: ten characters sharing one shambling take,
##                 played faster or slower with the zombie's speed.
##   "partygoer" — the Backrooms Partygoer (Entity 67): idle / walk / run, and its
##                 eating clip for attacks.

const POLYART := "res://assets/thirdparty/polyart_zombies/zombie_ani_player.fbx"
const PARTYGOER := "res://assets/thirdparty/partygoer/partygoer.glb"
## Characters in the Polyart pack (each its own mesh and skeleton in one scene).
const POLYART_COUNT := 10
## The models face +Z; the game's forward is -Z.
const FACING := PI

## id -> [PackedScene per variant]: one stripped copy per character, built once.
static var _templates := {}

var id := ""
var _anim: AnimationPlayer
var _clip := ""
var _dead := false
var _hider: SkeletonModifier3D


## True when the model file for `skin_id` is present.
static func available(skin_id: String) -> bool:
	match skin_id:
		"polyart":
			return ResourceLoader.exists(POLYART)
		"partygoer":
			return ResourceLoader.exists(PARTYGOER)
	return false


## Builds the model for `skin_id`, `height` metres tall. False if it could not.
func build(skin_id: String, variant: int, height: float) -> bool:
	id = skin_id
	var model: Node3D = null
	match skin_id:
		"polyart":
			model = _polyart_character(variant % POLYART_COUNT)
		"partygoer":
			model = (load(PARTYGOER) as PackedScene).instantiate() as Node3D
	if model == null:
		return false
	add_child(model)
	# scale to the wanted height from the model's own bounds
	var box := _bounds(model)
	if box.size.y > 0.01:
		var s := height / box.size.y
		model.scale = Vector3.ONE * s
		model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_anim = aps[0]
		for a in _anim.get_animation_list():
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR if a != "sit" else Animation.LOOP_NONE
		_anim.seek(randf() * 2.0)
	if skin_id == "partygoer":
		_fit_by_bones(model, height)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return true


## The Partygoer's bounds include its balloon and string, and its rest pose is
## not how it walks: size and ground it from its skeleton in the walking pose
## instead. Feet bones to the head bone are FEET_TO_HEAD of its full height.
const FEET_TO_HEAD := 0.68
func _fit_by_bones(model: Node3D, height: float) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty() or _anim == null:
		return
	model.scale = Vector3.ONE
	model.position = Vector3.ZERO
	_anim.play("walk" if _anim.has_animation("walk") else _anim.get_animation_list()[0])
	_anim.advance(0.0)
	var sk := skels[0] as Skeleton3D
	var to_self := (global_transform.affine_inverse() * sk.global_transform) if is_inside_tree() else _chain(sk)
	var low := INF
	var head := -INF
	for b in sk.get_bone_count():
		var y := (to_self * sk.get_bone_global_pose(b)).origin.y
		var nm := sk.get_bone_name(b).to_lower()
		if nm.contains("feet") or nm.contains("foot"):
			low = minf(low, y)
		if nm == "head":
			head = y
	if low == INF or head == -INF or head <= low:
		return
	var s := height * FEET_TO_HEAD / (head - low)
	model.scale = Vector3.ONE * s
	model.position.y = -low * s + 0.07   # the feet bones sit a little above the soles


## `n`'s transform relative to this node, walking up its parents.
func _chain(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != self:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Faces `yaw` and plays the clip that fits `speed` (m/s) and an attack in progress.
func update(yaw: float, speed: float, attacking: bool) -> void:
	rotation.y = yaw + FACING
	if _anim == null or _dead:
		return
	if id == "partygoer":
		var want := "eating_meat" if attacking else ("run" if speed > 3.0 else ("walk" if speed > 0.25 else "idle"))
		if want != _clip:
			_clip = want
			_anim.play(want, 0.2)
		_anim.speed_scale = clampf(speed / (4.5 if want == "run" else 1.6), 0.6, 1.8) if want in ["run", "walk"] else 1.0
	else:
		if _clip == "":
			_clip = _anim.get_animation_list()[0]
			_anim.play(_clip)
		_anim.speed_scale = 2.2 if attacking else clampf(0.35 + speed / 1.8, 0.3, 2.0)


## Dismemberment: the limb the zombie lost disappears from the model too.
## `key` "arm0" / "arm1" / "leg0" / "leg1" (0 = left), `at` "upper" (from the
## shoulder / hip) or "lower" (from the elbow / knee).
func sever(key: String, at: String) -> void:
	var skels := find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	var bone := _limb_bone(sk, key.begins_with("arm"), int(key.right(1)), at == "upper")
	if bone < 0:
		return
	if _hider == null:
		_hider = LimbHider.new()
		sk.add_child(_hider)
	_hider.bones.append(bone)


## The bone a limb comes off at, found by name and hierarchy so it works for any
## rig: the side's arm / leg bones, then the root of that chain (upper) or its
## next bone down (lower).
static func _limb_bone(sk: Skeleton3D, arm: bool, side: int, upper: bool) -> int:
	var side_tags := [" l ", "left", "_l", ".l", "l_"] if side == 0 else [" r ", "right", "_r", ".r", "r_"]
	var limb_tags := ["upperarm", "forearm", "arm"] if arm else ["thigh", "calf", "leg", "shin"]
	var chain: Array = []
	for b in sk.get_bone_count():
		var nm := " " + sk.get_bone_name(b).to_lower() + " "
		if side_tags.any(func(t): return nm.contains(t)) and limb_tags.any(func(t): return nm.contains(t)) and not nm.contains("finger") and not nm.contains("clavicle"):
			chain.append(b)
	if chain.is_empty():
		return -1
	var root := -1
	for b in chain:
		if not chain.has(sk.get_bone_parent(b)):
			root = b
			break
	if root < 0 or upper:
		return root
	for b in chain:
		if sk.get_bone_parent(b) == root:
			return b
	return root


## Shrinks the severed bones (and so everything below them) to nothing after
## the animation has posed the skeleton each frame.
class LimbHider extends SkeletonModifier3D:
	var bones: Array = []
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for b in bones:
			sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)


## Death: the Partygoer sinks down, a Polyart zombie topples over backwards.
func die(dir: Vector3) -> void:
	_dead = true
	if id == "partygoer" and _anim != null and _anim.has_animation("sit"):
		_anim.speed_scale = 1.0
		_anim.play("sit", 0.15)
		return
	if _anim != null:
		_anim.pause()
	var fall := Vector3(dir.x, 0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else -global_transform.basis.z
	var axis := fall.cross(Vector3.UP).normalized()
	var tw := create_tween()
	tw.tween_property(self, "quaternion", Quaternion(axis, -PI * 0.5) * quaternion, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(self, "position:y", position.y + 0.15, 0.55)


## One Polyart character on its own: the others and the display stand are removed.
func _polyart_character(i: int) -> Node3D:
	if not _templates.has("polyart"):
		var list: Array = []
		var src := (load(POLYART) as PackedScene).instantiate() as Node3D
		var meshes := src.find_children("lp*_zombie_*", "MeshInstance3D", true, false)
		meshes.sort_custom(func(a, b): return String(a.name) < String(b.name))
		for k in meshes.size():
			var copy := (load(POLYART) as PackedScene).instantiate() as Node3D
			var keep := String((meshes[k] as Node).name)
			var keep_skel: Node = (copy.find_child(keep, true, false) as MeshInstance3D).get_node_or_null((copy.find_child(keep, true, false) as MeshInstance3D).skeleton)
			for n in copy.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				var skel: Node = mi.get_node_or_null(mi.skeleton) if mi.skin != null else null
				# the character, plus the hair / hat that rides on its skeleton
				if String(mi.name) != keep and (skel == null or skel != keep_skel):
					mi.get_parent().remove_child(mi)
					mi.free()
			_own(copy, copy)
			var ps := PackedScene.new()
			ps.pack(copy)
			copy.free()
			list.append(ps)
		src.free()
		_templates["polyart"] = list
	var templates: Array = _templates["polyart"]
	if templates.is_empty():
		return null
	return (templates[i % templates.size()] as PackedScene).instantiate() as Node3D


## Makes every node belong to `root` so PackedScene.pack keeps the whole tree.
static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)


## Bounds of all meshes under `model`, in this node's space (bind pose).
func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != self:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var a: AABB = xf * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box
