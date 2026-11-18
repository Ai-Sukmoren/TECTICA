extends RefCounted
## Sticker art printed into a finish's own surface (skins.gd FINISH_SHADER).
## The art is projected across the gun from the side, so it follows every part
## and curve under it: receiver, handguard, magazine, grip, stock and the optic
## body. Where a surface turns away it fades out, wrapping round rounded edges
## rather than ending in a hard line. Glass and parts left in their factory look
## never take it. It sits under the finish's lacquer and lighting like a printed wrap.
##
## Placement (per gun, edited in the Armory, saved in collection.gd):
##   on    bool    shown or hidden
##   u     0..1    centre along the gun, 0 = stock end, 1 = muzzle end
##   v     0..1    centre height, 0 = bottom, 1 = top; -1 = auto (middle of the gun)
##   s     size: 1 = a full wrap that covers the whole side of the gun (the art
##         scaled to cover its length and height, like a background "cover");
##         smaller is a patch, bigger crops further into the art
##   r     radians roll
##   side  0 right, 1 left, 2 both (each side reads the right way round)
##
## Each skinned part gets per-instance shader parameters: its transform into
## the gun's space (stk_r0..2), the sticker rectangle (stk_a) and its roll and
## side (stk_b). Changing the placement only rewrites those numbers.

const Skins = preload("res://scripts/skins/skins.gd")

## Legacy flat sticker quads (removed when found).
const NODE_NAME := "Sticker"
const S_MIN := 0.12
const S_MAX := 1.6
## Default: a full wrap over the whole gun, on both sides.
const DEFAULT := {"on": true, "u": 0.5, "v": -1.0, "s": 1.0, "r": 0.0, "side": 2}


static func clamp_cfg(d: Dictionary) -> Dictionary:
	return {
		"on": bool(d.get("on", DEFAULT.on)),
		"u": clampf(float(d.get("u", DEFAULT.u)), 0.0, 1.0),
		"v": -1.0 if float(d.get("v", -1.0)) < 0.0 else clampf(float(d.get("v", -1.0)), 0.0, 1.0),
		"s": clampf(float(d.get("s", DEFAULT.s)), S_MIN, S_MAX),
		"r": wrapf(float(d.get("r", 0.0)), -PI, PI),
		"side": clampi(int(d.get("side", DEFAULT.side)), 0, 2),
	}


static func texture(sticker_id: String) -> Texture2D:
	if not Skins.STICKERS.has(sticker_id) or not ResourceLoader.exists(String(Skins.STICKERS[sticker_id])):
		return null   # sticker art is not part of the public source
	return load(String(Skins.STICKERS[sticker_id])) as Texture2D


## Transform of `n` relative to `root` (works before the model is in the tree).
static func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Every drawn part of the model: [mesh instance, its box in model space].
static func _parts(root: Node3D) -> Array:
	var out: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with(NODE_NAME) or (mi as MeshInstance3D).mesh == null:
			continue
		out.append(_rel(mi, root) * (mi as MeshInstance3D).mesh.get_aabb())
	return out


## The gun's extent in its own space (what u / v / s are measured against).
static func bounds(root: Node3D) -> AABB:
	var parts := _parts(root)
	if parts.is_empty():
		return AABB()
	var b: AABB = parts[0]
	for p in parts:
		b = b.merge(p)
	return b


## True when a surface of `mi` wears a finish material that carries sticker art.
static func _prints(mi: MeshInstance3D) -> bool:
	var mats: Array = [mi.material_override]
	if mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			mats.append(mi.get_surface_override_material(s))
	for m in mats:
		if m is ShaderMaterial and (m as ShaderMaterial).shader == Skins.finish_shader() \
				and (m as ShaderMaterial).get_shader_parameter("use_sticker") == true:
			return true
	return false


## The sticker rectangle in gun space for `cfg`: [centre z, centre y, width, height].
static func rect(root: Node3D, sticker_id: String, cfg: Dictionary) -> Array:
	var c := clamp_cfg(cfg)
	var b := bounds(root)
	var tex := texture(sticker_id)
	var aspect := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0) if tex else 3.0
	var w := maxf(maxf(b.size.z, b.size.y * aspect) * float(c.s), 0.05)
	var z := lerpf(b.end.z, b.position.z, float(c.u))   # muzzle points -Z
	var y := b.get_center().y if float(c.v) < 0.0 else lerpf(b.position.y, b.end.y, float(c.v))
	return [z, y, w, w / aspect]


## Gun-space point under the sticker's centre for (u, v) in `root` (for dragging it).
static func uv_at(root: Node3D, point: Vector3) -> Vector2:
	var b := bounds(root)
	return Vector2(clampf((b.end.z - point.z) / maxf(b.size.z, 0.001), 0.0, 1.0),
			clampf((point.y - b.position.y) / maxf(b.size.y, 0.001), 0.0, 1.0))


## Takes the sticker off every part of `model_root`.
static func remove(model_root: Node3D) -> void:
	if model_root == null:
		return
	for ch in model_root.get_children():
		if String(ch.name).begins_with(NODE_NAME):
			model_root.remove_child(ch)
			ch.queue_free()
	for mi in model_root.find_children("*", "MeshInstance3D", true, false):
		if _prints(mi):
			(mi as MeshInstance3D).set_instance_shader_parameter("stk_a", Vector4.ZERO)


## Prints `sticker_id` per `cfg` across every part of `model_root` that wears a
## sticker-carrying finish (call after the finish is applied).
static func attach(model_root: Node3D, sticker_id: String, cfg: Dictionary) -> void:
	remove(model_root)
	if model_root == null or texture(sticker_id) == null:
		return
	var c := clamp_cfg(cfg)
	if not c.on:
		return
	var r := rect(model_root, sticker_id, c)
	var a := Vector4(r[0], r[1], float(r[2]) * 0.5, float(r[3]) * 0.5)
	var bp := Vector4(cos(float(c.r)), sin(float(c.r)), float(c.side), 0.0)
	for n in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not _prints(mi):
			continue
		var xf := _rel(mi, model_root)
		var bx := xf.basis
		mi.set_instance_shader_parameter("stk_r0", Vector4(bx.x.x, bx.y.x, bx.z.x, xf.origin.x))
		mi.set_instance_shader_parameter("stk_r1", Vector4(bx.x.y, bx.y.y, bx.z.y, xf.origin.y))
		mi.set_instance_shader_parameter("stk_r2", Vector4(bx.x.z, bx.y.z, bx.z.z, xf.origin.z))
		mi.set_instance_shader_parameter("stk_a", a)
		mi.set_instance_shader_parameter("stk_b", bp)
