extends RefCounted
## Sticker decals on weapon models. A sticker is a textured quad pressed onto
## the side of whatever part sits under the chosen spot, so it hugs the
## receiver / handguard instead of floating at the gun's outer bounds.
##
## Placement (per gun, edited in the Armory, saved in collection.gd):
##   on    bool    shown or hidden
##   u     0..1    along the gun, 0 = stock end, 1 = muzzle end
##   v     0..1    height, 0 = bottom, 1 = top; -1 = auto (centre of the gun's main body)
##   s     0.4..2.5 size multiplier
##   r     radians roll
##   side  0 right, 1 left, 2 both

const Skins = preload("res://scripts/skins/skins.gd")

const NODE_NAME := "Sticker"
## Base sticker width as a share of the gun's length.
const BASE_WIDTH := 0.2

static var _mats: Dictionary = {}


static func clamp_cfg(d: Dictionary) -> Dictionary:
	return {
		"on": bool(d.get("on", true)),
		"u": clampf(float(d.get("u", 0.5)), 0.0, 1.0),
		"v": -1.0 if float(d.get("v", -1.0)) < 0.0 else clampf(float(d.get("v", -1.0)), 0.0, 1.0),
		"s": clampf(float(d.get("s", 1.0)), 0.4, 2.5),
		"r": wrapf(float(d.get("r", 0.0)), -PI, PI),
		"side": clampi(int(d.get("side", 0)), 0, 2),
	}


static func _material(sticker_id: String) -> StandardMaterial3D:
	if _mats.has(sticker_id):
		return _mats[sticker_id]
	var tex := load(String(Skins.STICKERS[sticker_id])) as Texture2D
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[sticker_id] = m
	return m


static func remove(model_root: Node3D) -> void:
	if model_root == null:
		return
	for ch in model_root.get_children():
		if String(ch.name).begins_with(NODE_NAME):
			model_root.remove_child(ch)
			ch.queue_free()


## Transform of `n` relative to `root` (works before the model is in the tree).
static func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _parts(root: Node3D) -> Array:
	var out: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with(NODE_NAME) or (mi as MeshInstance3D).mesh == null:
			continue
		out.append(_rel(mi, root) * (mi as MeshInstance3D).mesh.get_aabb())
	return out


## Replaces any sticker on `model_root` with one placed per `cfg`.
static func attach(model_root: Node3D, sticker_id: String, cfg: Dictionary) -> void:
	remove(model_root)
	if model_root == null or not Skins.STICKERS.has(sticker_id):
		return
	if not ResourceLoader.exists(String(Skins.STICKERS[sticker_id])):
		return   # sticker art is not part of the public source
	var c := clamp_cfg(cfg)
	if not c.on:
		return
	var parts := _parts(model_root)
	if parts.is_empty():
		return
	var bounds: AABB = parts[0]
	for b in parts:
		bounds = bounds.merge(b)
	var z := lerpf(bounds.end.z, bounds.position.z, float(c.u))   # muzzle points -Z
	var y := lerpf(bounds.position.y, bounds.end.y, float(c.v))
	if float(c.v) < 0.0:
		# auto: the biggest side-on part under this spot is the receiver / body
		var best := -1.0
		for b in parts:
			if z >= b.position.z and z <= b.end.z and b.size.z * b.size.y > best:
				best = b.size.z * b.size.y
				y = b.get_center().y
	var mat := _material(sticker_id)
	var tex := mat.albedo_texture
	var aspect := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0) if tex else 3.0
	var w := maxf(bounds.size.z * BASE_WIDTH, 0.075) * float(c.s)   # pistols get a readable minimum
	var quad := QuadMesh.new()
	quad.size = Vector2(w, w / aspect)
	var sides: Array = [[1.0], [-1.0], [1.0, -1.0]][int(c.side)]
	for sx in sides:
		# outermost surface of the parts under this spot (fallback: whole gun)
		var x := bounds.end.x if sx > 0.0 else bounds.position.x
		var found := false
		for b in parts:
			if y >= b.position.y and y <= b.end.y and z >= b.position.z and z <= b.end.z:
				var bx: float = b.end.x if sx > 0.0 else b.position.x
				if not found or (sx > 0.0 and bx > x) or (sx < 0.0 and bx < x):
					x = bx
					found = true
		var mi := MeshInstance3D.new()
		mi.name = NODE_NAME + ("R" if sx > 0.0 else "L")
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# quad faces +Z; turn it to face out of this side, then roll it
		mi.basis = Basis(Vector3.UP, PI * 0.5 * sx) * Basis(Vector3.BACK, float(c.r))
		mi.position = Vector3(x + 0.0015 * sx, y, z)
		model_root.add_child(mi)
