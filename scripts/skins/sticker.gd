extends RefCounted
## Sticker decals on weapon models. A sticker is a textured quad pressed onto
## the side of whatever part sits under the chosen spot, so it hugs the
## receiver / handguard instead of floating at the gun's outer bounds. It is
## shrunk and nudged to lie wholly on that part, so one sticker fits every
## gun and knife (on a knife it rides the blade).
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
## Share of the host part's length / height a sticker may cover.
const FIT := 0.9

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


## Parts a sticker can sit flat on: those not tilted against the weapon's
## axes (a raked magazine or grip has a slanted side, and its bounding box
## is mostly air). Falls back to every part when none qualifies.
static func _hosts(root: Node3D) -> Array:
	var out: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with(NODE_NAME) or (mi as MeshInstance3D).mesh == null:
			continue
		var xf := _rel(mi, root)
		var square := true
		for axis in [xf.basis.x, xf.basis.y, xf.basis.z]:
			var a: Vector3 = (axis as Vector3).normalized().abs()
			if maxf(a.x, maxf(a.y, a.z)) < 0.999:
				square = false
		if square:
			out.append(xf * (mi as MeshInstance3D).mesh.get_aabb())
	return out if not out.is_empty() else _parts(root)


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
	# the part the sticker sits on: the one under the chosen spot, else (auto
	# height, or a spot over a gap) the biggest side-on part at this point
	# along the weapon, else the biggest part of all (receiver, slide, blade)
	var hosts := _hosts(model_root)
	var host := AABB()
	var best := -1.0
	if float(c.v) >= 0.0:
		for b in hosts:
			if z >= b.position.z and z <= b.end.z and y >= b.position.y and y <= b.end.y and b.size.z * b.size.y > best:
				best = b.size.z * b.size.y
				host = b
	if best < 0.0:
		for b in hosts:
			if z >= b.position.z and z <= b.end.z and b.size.z * b.size.y > best:
				best = b.size.z * b.size.y
				host = b
	if best < 0.0:
		for b in hosts:
			if b.size.z * b.size.y > best:
				best = b.size.z * b.size.y
				host = b
	var mat := _material(sticker_id)
	var tex := mat.albedo_texture
	var aspect := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0) if tex else 3.0
	var w := maxf(bounds.size.z * BASE_WIDTH, 0.075) * float(c.s)   # pistols get a readable minimum
	# fit: never larger than the face it sits on, and wholly inside it
	# a part taller than it is long (an upright blade): the sticker runs up it
	var upright := host.size.y > host.size.z * 1.2
	var along := host.size.y if upright else host.size.z
	var across := host.size.z if upright else host.size.y
	var fit := minf(1.0, minf(along * FIT / w, across * FIT / (w / aspect)))
	w *= fit
	var h := w / aspect
	var ez := h if upright else w   # sticker extent along the weapon and up it
	var ey := w if upright else h
	z = clampf(z, host.position.z + ez * 0.5, host.end.z - ez * 0.5) if host.size.z > ez else host.get_center().z
	y = clampf(y, host.position.y + ey * 0.5, host.end.y - ey * 0.5) if host.size.y > ey else host.get_center().y
	var roll := float(c.r) + (PI * 0.5 if upright else 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
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
		mi.basis = Basis(Vector3.UP, PI * 0.5 * sx) * Basis(Vector3.BACK, roll)
		mi.position = Vector3(x + 0.0015 * sx, y, z)
		model_root.add_child(mi)
