extends RefCounted
## Modular procedural weapon builder.
## Every base gun exposes mount points (rail, muzzle, underbarrel, magazine,
## stock); attachments are built onto those mounts.
## Convention: origin = pistol grip, barrel points -Z, +Y up.
## Returned markers: grip (right hand), support (left hand), muzzle, mag (Node3D),
## mag_well, charge, eject, laser (optional), pump / bolt (optional animated
## parts) and `sight` = {y, rear_z, relief} describing the sight line for ADS.

const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const WG = preload("res://scripts/weapons/weapon_geometry.gd")

const X90 := Vector3(PI * 0.5, 0, 0)
const Z90 := Vector3(0, 0, PI * 0.5)

static var _black: Material
static var _poly: Material
static var _worn: Material
static var _glass: Material
static var _tube: Material
## Bare machined steel (bolts, bolt handles) for models that export it as flat white.
static var _steel: Material


static func _mats() -> void:
	if _black != null:
		return
	_black = M.painted_metal("weapon_anodized", Color(0.12, 0.135, 0.15))
	_black.metallic = 0.8
	_black.roughness = 0.32
	_black.normal_scale = 0.16
	_black.rim_enabled = true
	_black.rim = 0.12
	_black.rim_tint = 0.3
	# gun finish, not weathered scenery steel: an even phosphate / anodised coat
	# whose only variation is fine handling wear (no rust blotches), at a scale
	# that reads on a part a few centimetres across
	if M.pbr("metal_detail") != null:
		_black.albedo_texture = M.pbr("metal_detail")
		_black.albedo_color = Color(0.12, 0.135, 0.15) / 0.72
		_black.uv1_scale = Vector3.ONE * 5.0
		_black.roughness = 0.5
		_black.normal_scale = 0.3
	var poly := StandardMaterial3D.new()
	poly.albedo_color = Color(0.085, 0.09, 0.098)
	poly.roughness = 0.6
	poly.normal_enabled = true
	poly.normal_texture = M.normal_tex(0.22, 19, 2.5)
	poly.normal_scale = 0.22
	poly.uv1_triplanar = true
	poly.uv1_scale = Vector3.ONE * 26.0
	poly.rim_enabled = true
	poly.rim = 0.08
	# moulded polymer: a pebbled grain with an uneven satin sheen
	if M.pbr("fabric_rough") != null:
		poly.roughness = 0.72
		poly.roughness_texture = M.pbr("fabric_rough")
		poly.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		poly.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_poly = poly
	_worn = M.solid(Color(0.29, 0.31, 0.34), 0.27, 0.9)
	_steel = M.solid(Color(0.46, 0.47, 0.49), 0.3, 0.9)
	var g := StandardMaterial3D.new()
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.7, 0.85, 0.95, 0.05)
	g.roughness = 0.05
	g.metallic = 0.6
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass = g
	var t := StandardMaterial3D.new()
	t.albedo_color = Color(0.07, 0.07, 0.075)
	t.roughness = 0.6
	t.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tube = t


static func build(model: String, att: Dictionary) -> Dictionary:
	_mats()
	var root := Node3D.new()
	root.name = "Model"
	var b: Dictionary
	match model:
		"mgp7":
			b = _mgp7(root)
		"zc57":
			b = _zc57(root)
		"marlin":
			b = _marlin(root)
		_:
			b = _low_poly(root, model, att)

	var parts := {"root": root, "blowback": float(b.get("blowback", 0.022 if b.get("pistol", false) else 0.045)), "grip": b.grip, "support": b.support, "charge": b.charge, "eject": b.eject,
			"bolt_action": b.get("bolt_action", []),
			"pump": b.get("pump"), "bolt": b.get("bolt"), "roll": b.get("roll"), "hammer": b.get("hammer"), "twirl": b.get("twirl"), "lever": b.get("lever"), "laser": null}
	# Every attachment's meshes are tagged with their slot ("skin_part") so each
	# attachment, and the magazine, can wear its own skin (see skins.gd).
	var seen := _meshes(root)
	# magazine
	var mag_at: Node3D = b.mag_at
	if b.has("glb_mag"):
		parts.mag = _glb_mag(mag_at, b.glb_mag, String(att.get("magazine", "standard")))
	else:
		parts.mag = _marker(mag_at, "Mag", Vector3.ZERO)
	parts.mag_well = _marker(mag_at, "MagWell", Vector3(0, -0.05, 0))
	_tag_new(root, seen, "magazine")
	# muzzle device
	var mz := String(att.get("muzzle", "none"))
	if mz == "suppressor" and b.has("factory_suppressor"):
		var silencer := _factory_part(root, "Att_suppressor", b.factory_suppressor)
		var tip: Vector3 = b.muzzle_at.position
		tip.z = _holder_box(silencer).position.z
		parts.muzzle = _marker(root, "Muzzle", tip)
	elif mz == "suppressor" and b.has("glb_suppressor") and _glb_suppressor(b.muzzle_at, String(b.glb_suppressor)):
		parts.muzzle = _marker(b.muzzle_at, "Muzzle", Vector3(0, 0, -float(b.glb_suppressor_len)))
	else:
		parts.muzzle = _muzzle(b.muzzle_at, mz, b.get("pistol", false))
	_tag_new(root, seen, "muzzle")
	# underbarrel
	var ub_kind := String(att.get("underbarrel", "none"))
	var side_kind := String(att.get("side", "laser" if ub_kind == "laser" else "none"))
	if ub_kind == "laser":
		ub_kind = "none"
	var ub_at: Node3D = b.under_at
	var small := float(LP_PISTOL_UNDER_SCALE if b.get("pistol", false) else 1.0)
	# the rail slot: an adapter under the handguard (or frame) that underbarrel parts clamp to
	if String(att.get("rail", "none")) == "rail" or (ub_kind != "none" and b.get("rail_adapter", false)):
		var rail := _att_model(ub_at, "rail")
		if rail != null:
			rail.scale = Vector3.ONE * small
			var moved := _fit_rail(root, ub_at, rail)
			ub_at = _marker(ub_at, "RailFace", Vector3(0, -LP_RAIL_DROP * small, 0) + moved)
			if ub_kind == "afg":
				# Follow the adapter's actual centre and tilt after fitting a sloped handguard.
				ub_at.transform = Transform3D(rail.basis.orthonormalized(), rail.position) * Transform3D(Basis.IDENTITY, Vector3.DOWN * LP_RAIL_DROP * small)
	_tag_new(root, seen, "rail")
	var ub := _underbarrel(ub_at, ub_kind)
	if ub_kind in ["afg", "vfg"] and ub.has("housing"):
		_seat_grip(root, ub.housing, ub_kind, "seat|%s|%s|%s" % [model, att.get("handguard", ""), ub_kind])
	_tag_new(root, seen, "underbarrel")
	if ub.has("support"):
		parts.support = ub.support
	parts.launcher = ub.get("launcher")
	var holds := _palm_sockets(root, b, model, att, ub_at, ub.get("housing"))
	parts.palm_grip = _marker(root, "PalmGrip", Vector3.ZERO)
	parts.palm_grip.transform = holds[1]
	parts.palm_support = _marker(root, "PalmSupport", Vector3.ZERO)
	parts.palm_support.transform = holds[0]
	parts.hand_open = holds[2]
	# optic
	parts.sight = _optic(root, b, String(att.get("optic", "iron")))
	_tag_new(root, seen, "optic")
	if side_kind == "laser":
		parts.laser = _side_laser(root, b, model, String(att.get("handguard", "standard")))
		_tag_new(root, seen, "side")
	_signature_details(root, model, b)
	_tag_tree(parts.mag, "magazine")   # details added on the magazine ride with it
	return parts


static func _meshes(root: Node) -> Dictionary:
	var out := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out[n] = true
	return out


## Tags the meshes built since `seen` with `slot` and adds them to `seen`.
static func _tag_new(root: Node, seen: Dictionary, slot: String) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if not seen.has(n):
			seen[n] = true
			n.set_meta("skin_part", slot)


static func _tag_tree(node: Node, slot: String) -> void:
	if node == null:
		return
	for n in node.find_children("*", "MeshInstance3D", true, false):
		n.set_meta("skin_part", slot)


## Weapon-specific construction details visible during inspection. Keep geometry
## on the correct moving parent (pump, bolt, magazine), never on the hands.
static func _signature_details(r: Node3D, model: String, b: Dictionary) -> void:
	match model:
		"mgp7", "zc57":
			# Preserve the licensed sculpt and add a machined barrel crown.
			var mz: Node3D = b.muzzle_at
			_part(mz, _ring(0.0045, 0.008), _worn, Vector3(0, 0, -0.002), X90)


# ====================================================================== helpers

static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _body(parent: Node3D, width: float, outline: Array, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _part(parent, WG.profile(width, PackedVector2Array(outline)), mat, pos)


static func _marker(parent: Node3D, n: String, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var m := Node3D.new()
	m.name = n
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
	return m


static func _open_tube(radius: float, length: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.cap_top = false
	c.cap_bottom = false
	c.radial_segments = 24
	return c


static func _ring(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 8
	return t


# ============================================================ asset pack 4 guns
# alstraInfinite "PPS Shooter Essentials" (credit: Alstra Infinite).
# Both models already have their origin on the pistol grip with the barrel
# along -X; the MGP7 is Y-up, the ZC57 is Z-up.

const PACK4 := "res://assets/thirdparty/alstra_shooter_essentials/Guns/"
const _Y90 := Vector3(0, -PI * 0.5, 0)


## Gun and attachment model files stay loaded once used (GunWarmup loads them
## all with the map), so switching guns never waits on the disk.
static var _scenes := {}

static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## Copies every mesh of a glb into `r` (in weapon space), except names that
## contain `skip`. Returns {mesh name: [mesh, transform]} for the skipped ones.
static func _glb_meshes(r: Node3D, path: String, conv: Basis, skip: String = "") -> Dictionary:
	var held := {}
	if not ResourceLoader.exists(path):
		return held
	var list := _glb_list(path)
	for e in list:
		var xf := Transform3D(conv, Vector3.ZERO) * (e[2] as Transform3D)
		var mesh: Mesh = e[1]
		# Parts modelled in other units (the ZC57 is in centimetres, scaled by
		# 0.01 on its node) get the scale baked into the mesh: skin patterns are
		# computed in mesh space and were 100x too fine on them.
		var sc := xf.basis.get_scale()
		if absf(sc.x - 1.0) > 0.01 or absf(sc.y - 1.0) > 0.01 or absf(sc.z - 1.0) > 0.01:
			mesh = _baked(mesh, sc)
			xf = Transform3D(xf.basis.orthonormalized(), xf.origin)
		if skip != "" and String(e[0]).contains(skip):
			held[String(e[0])] = [mesh, xf]
			continue
		var mi := MeshInstance3D.new()
		mi.name = String(e[0])
		mi.mesh = mesh
		mi.transform = xf
		mi.set_meta("pack4", true)   # skins recolour these too
		r.add_child(mi)
	return held


static var _baked_cache: Dictionary = {}


## A copy of `mesh` with every vertex multiplied by `sc` (cached).
static func _baked(mesh: Mesh, sc: Vector3) -> Mesh:
	var key := "%d_%s" % [mesh.get_instance_id(), sc]
	if _baked_cache.has(key):
		return _baked_cache[key]
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = verts[i] * sc
		arr[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, mesh.surface_get_material(s))
	_baked_cache[key] = out
	return out


## Every mesh of a model file with its transform in the model's space, as [name, mesh, transform]. The scene is
## instantiated and walked once per file and the list kept: doing it on every build cost 20+ ms for a big model
## (the underbarrel laser) each time a gun was built, e.g. on every gunsmith click. Callers only read the list;
## the meshes are the file's own shared resources, as they are on any instance of it.
static var _lists := {}
static func _glb_list(path: String) -> Array:
	if not _lists.has(path):
		var inst := _scene(path).instantiate()
		var list: Array = []
		_glb_walk(inst, Transform3D.IDENTITY, list)
		inst.free()
		_lists[path] = list
	return _lists[path]


static func _glb_walk(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n.name, (n as MeshInstance3D).mesh, here])
	for c in n.get_children():
		_glb_walk(c, here, out)


## The model's own magazine, re-parented under a Mag node at `at` so the
## reload animation can drop and insert it. Extended mags are stretched.
static func _glb_mag(at: Node3D, held: Array, kind: String) -> Node3D:
	var mag := Node3D.new()
	mag.name = "Mag"
	at.add_child(mag)
	if held.is_empty():
		return mag
	var mi := MeshInstance3D.new()
	mi.mesh = held[0]
	var at_xf := Transform3D(Basis.from_euler(at.rotation), at.position)
	mi.transform = at_xf.affine_inverse() * (held[1] as Transform3D)
	mi.set_meta("pack4", true)
	mag.add_child(mi)
	if kind == "extended":
		mag.scale = Vector3(1.0, 1.4, 1.0)
	elif kind == "dual":
		_tape_twin(mag)
	elif kind == "fast":
		# pull tab under the middle of the magazine's floor plate (these mags
		# angle forward, so the floor is not under the mag well)
		var low := INF
		var pts: Array = []
		for s in mi.mesh.get_surface_count():
			for v in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = mi.transform * v
				pts.append(p)
				low = minf(low, p.y)
		var c := Vector3.ZERO
		var n := 0
		for p in pts:
			if p.y < low + 0.004:
				c += p
				n += 1
		c = c / maxi(n, 1)
		_part(mag, WG.machined(Vector3(0.012, 0.035, 0.012)), M.solid(Color(0.9, 0.4, 0.1), 0.6), Vector3(c.x, low - 0.015, c.z))
	return mag


## Taped dual mag: a copy of the magazine beside it (to the left, upside
## down like the real thing), two bands of tape around both.
static func _tape_twin(mag: Node3D) -> void:
	var parts: Array = mag.get_children().duplicate()
	var box := AABB()
	var first := true
	for c in parts:
		if c is MeshInstance3D:
			var a: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
	if first:
		return
	var twin := Node3D.new()
	twin.name = "TwinMag"
	mag.add_child(twin)
	var gap := box.size.x + 0.002
	for c in parts:
		if c is MeshInstance3D:
			var mi := (c as MeshInstance3D).duplicate() as MeshInstance3D
			twin.add_child(mi)
	twin.position = Vector3(-gap, 0, 0)
	var tape := M.matte("mag_tape", Color(0.12, 0.13, 0.12), 0.95)
	# every vertex of the magazine in mag space, so each band hugs the mag's
	# real depth at its height (curved / angled mags are much slimmer than their box)
	var tris := PackedVector3Array()   # every triangle of the magazine, in mag space
	for c in parts:
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ix = arr[Mesh.ARRAY_INDEX]
				if ix != null and (ix as PackedInt32Array).size() > 0:
					for i in (ix as PackedInt32Array):
						tris.append(mi.transform * vs[i])
				else:
					for v in vs:
						tris.append(mi.transform * v)
	var h := box.size.y
	for k in [0.4, 0.7]:
		var yk: float = box.end.y - h * k
		# the magazine's front-to-back extent where its surface crosses y = yk
		var z0 := INF
		var z1 := -INF
		for t in range(0, tris.size() - 2, 3):
			for e in 3:
				var a: Vector3 = tris[t + e]
				var b: Vector3 = tris[t + (e + 1) % 3]
				if (a.y - yk) * (b.y - yk) <= 0.0 and absf(a.y - b.y) > 1e-6:
					var z := lerpf(a.z, b.z, (yk - a.y) / (b.y - a.y))
					z0 = minf(z0, z)
					z1 = maxf(z1, z)
		if z0 > z1:
			continue
		_part(mag, WG.machined(Vector3(gap + box.size.x + 0.004, 0.012, z1 - z0 + 0.004)), tape,
				Vector3(box.get_center().x - gap * 0.5, yk, (z0 + z1) * 0.5))


static func _glb_suppressor(at: Node3D, file: String) -> bool:
	var path := PACK4 + file
	if not ResourceLoader.exists(path):
		return false
	_glb_meshes(at, path, Basis.from_euler(_Y90))
	return true


static func _mgp7(r: Node3D) -> Dictionary:
	var conv := Basis.from_euler(_Y90)
	var held := _glb_meshes(r, PACK4 + "MGP7/MGP7_Rigged.glb", conv, "_Mag_")
	var bolt := _moving_part(r, "MGP7_BulletEject")
	var mag: Array = []
	for k in held:
		if not String(k).contains("Eject"):
			mag = held[k]
	_keep_eject(r, held)
	return {
		"glb": true, "glb_mag": mag, "bolt": bolt, "blowback": 0.035,
		"glb_suppressor": "MGP7/MGP7 Attachments/MGP7_Attachment_SuppressorV1.glb", "glb_suppressor_len": 0.2,
		"grip": _marker(r, "Grip", Vector3(0, -0.015, 0.0), Vector3(-0.2, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.055, -0.26), Vector3(0, 0, -0.5)),
		"charge": _marker(r, "Charge", Vector3(-0.02, 0.14, -0.23)),
		"eject": _marker(r, "Eject", Vector3(0.02, 0.13, -0.14)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.108, -0.41)),
		"under_at": _marker(r, "UnderAt", Vector3(0, _bottom_at(r, -0.27, 0.073), -0.27)),
		"mag_at": _marker(r, "MagAt", Vector3(0, 0.06, -0.17)),
		"mag_style": "smg",
		"stock_at": r,
		"stock_style": "",
		"rail_y": 0.157, "rail_z": -0.1,
		"iron_builtin": true, "iron_y": 0.17, "iron_rear_z": 0.0,
	}


static func _zc57(r: Node3D) -> Dictionary:
	var conv := Basis.from_euler(_Y90) * Basis.from_euler(Vector3(-PI * 0.5, 0, 0))
	var held := _glb_meshes(r, PACK4 + "ZC57/ZC57_Rigged.glb", conv, "_Mag")
	var bolt := _moving_part(r, "ZC57_Slide")
	var mag: Array = []
	for k in held:
		if not String(k).contains("Eject"):
			mag = held[k]
	_keep_eject(r, held)
	return {
		"pistol": true, "glb": true, "glb_mag": mag, "bolt": bolt, "blowback": 0.02,
		"glb_suppressor": "ZC57/ZC57 Attachments/ZC57_Attachment_SuppressorV1.glb", "glb_suppressor_len": 0.18,
		"grip": _marker(r, "Grip", Vector3(0, -0.01, 0.01), Vector3(-0.25, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.03, -0.025, 0.0), Vector3(-0.25, 0, -0.6)),
		"charge": _marker(r, "Charge", Vector3(0, 0.07, 0.01)),
		"eject": _marker(r, "Eject", Vector3(0.02, 0.07, -0.05)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.064, -0.17)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.035, -0.12)),
		"mag_at": _marker(r, "MagAt", Vector3(0, 0.02, 0.0)),
		"mag_style": "pistol",
		"stock_at": r,
		"stock_style": "",
		"rail_y": 0.0755, "rail_z": -0.05, "mini": true,
		"iron_builtin": true, "iron_y": 0.082, "iron_rear_z": 0.005,
	}


# Low-poly Marlin 1895 (blued "gbl" variant), converted with Blender to one
# glb: Body, Bolt (slides back on the cycle) and Lever (origin on its front
# pin). Grip at the origin, barrel along -Z, metres. Not in the repository:
# without it the gun falls back to the procedural M870 body.
const MARLIN_GLB := "res://assets/thirdparty/marlin_1895/marlin_1895.glb"
## The lever's finger loop, from its front pin (closed).
const LEVER_LOOP := Vector3(0, -0.058, 0.098)

static func _marlin(r: Node3D) -> Dictionary:
	if not ResourceLoader.exists(MARLIN_GLB):
		return _placeholder(r, 0.97, false)
	var list := _glb_list(MARLIN_GLB)
	# Body stays on the gun; Bolt and Lever each get a pivot node the rig moves
	var lever: Node3D = null
	var bolt: Node3D = null
	for e in list:
		var part := String(e[0])
		var xf: Transform3D = e[2]
		var mi := MeshInstance3D.new()
		mi.mesh = e[1]
		mi.set_meta("pack4", true)   # skins recolour these too
		_clear_glass(mi)   # its bolt and hammer come in flat white ("1w")
		if part.begins_with("Lever"):
			lever = Node3D.new()
			lever.name = "Lever"
			lever.position = xf.origin   # the front pin
			r.add_child(lever)
			mi.transform = Transform3D(xf.basis, Vector3.ZERO)
			lever.add_child(mi)
		elif part.begins_with("Bolt"):
			bolt = Node3D.new()
			bolt.name = "Bolt"
			r.add_child(bolt)
			mi.transform = xf
			bolt.add_child(mi)
		else:
			mi.transform = xf
			r.add_child(mi)
	# spin cocking: the rifle turns round the lever loop the fingers sit in
	var spin: Node3D = null
	if lever != null:
		spin = _marker(r, "Twirl", lever.position + LEVER_LOOP)
	return {
		"glb": true, "lever": lever, "bolt": bolt, "twirl": spin,
		"grip": _marker(r, "Grip", Vector3(0, -0.01, 0.0), Vector3(-0.35, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.035, -0.31), Vector3(0, 0, -0.5)),
		"charge": _marker(lever if lever != null else r, "Charge", LEVER_LOOP),
		"eject": _marker(r, "Eject", Vector3(0.022, 0.055, -0.157)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.069, -0.68)),
		"under_at": _marker(r, "UnderAt", Vector3(0, _bottom_at(r, -0.42, 0.03), -0.42)),
		"mag_at": _marker(r, "MagAt", Vector3(0.02, 0.038, -0.132)),
		"mag_style": "shell",
		"stock_at": r,
		"stock_style": "",
		"rail_y": 0.09, "rail_z": -0.15,
		"iron_builtin": true, "iron_y": 0.09, "iron_rear_z": -0.272, "iron_relief": 0.3,
	}


# ====================================================== low-poly asset guns
# One glb per gun in assets/thirdparty/low_poly_guns/ (not in the repository),
# converted with Blender from the "low-poly" series: Body, Mag (the magazine in
# the well) and, where it moves, Bolt. Grip at the origin, barrel along -Z, metres.
# The points below are in the source model's side view (x forward, z up, 10 cm
# per unit) and turned into weapon space by _lp, so they can be checked against
# a render of the source file.
const LOW_POLY := "res://assets/thirdparty/low_poly_guns/"
const LP_GUNS := {
	"aug_a1": {"length": 0.79, "grip": Vector2(-0.767, -0.304), "support": Vector2(1.33, -0.41), "mag": Vector2(-1.81, -0.1),
			"muzzle": Vector2(3.944, 0.214), "eject": Vector2(-1.5, 0.2), "charge": Vector2(0.95, 0.3), "under": Vector2(2.3, 0.0),
			"sight": Vector2(-1.43, 0.92), "relief": 0.06},
	"hk33": {"hex": [-0.46, -0.15], "length": 0.93, "grip": Vector2(-1.834, -0.26), "support": Vector2(0.5, 0.12), "mag": Vector2(-0.08, 0.1),
			"muzzle": Vector2(4.472, 0.378), "eject": Vector2(-0.6, 0.5), "charge": Vector2(1.9, 0.65), "under": Vector2(1.4, 0.07), "rail_adapter": true,
			"sight": Vector2(-1.897, 0.95)},
	"uar10": {"hex": [-0.58, -0.27], "length": 1.03, "grip": Vector2(-1.902, -0.5), "support": Vector2(1.5, -0.04), "mag": Vector2(-0.4, -0.1),
			"muzzle": Vector2(5.356, 0.227), "eject": Vector2(-1.0, 0.25), "charge": Vector2(-2.1, 0.49), "under": Vector2(1.45, -0.05), "rail_adapter": true,
			"sight": Vector2(-1.855, 0.964), "relief": 0.1},
	"as_val": {"length": 0.9, "grip": Vector2(-1.422, -0.426), "support": Vector2(0.8, 0.02), "mag": Vector2(0.14, -0.1),
			"muzzle": Vector2(4.375, 0.33), "eject": Vector2(-0.3, 0.3), "charge": Vector2(0.5, 0.35), "under": Vector2(0.9, 0.0), "snap_under": true,
			"sight": Vector2(1.708, 0.63), "rail": Vector2(-0.5, 0.624), "relief": 0.4},
	"gepard": {"length": 0.68, "grip": Vector2(0.114, -0.437), "support": Vector2(1.685, -0.16), "mag": Vector2(0.1, -0.3),
			"muzzle": Vector2(3.718, 0.114), "eject": Vector2(0.62, 0.35), "charge": Vector2(0.4, 0.4), "under": Vector2(1.9, -0.17), "snap_under": true,
			"sight": Vector2(0.253, 0.72), "rail": Vector2(-0.3, 0.53), "relief": 0.2},
	"p90": {"length": 0.5, "grip": Vector2(0.75, -0.74), "support": Vector2(1.55, -0.7), "mag": Vector2(0.47, 0.08),
			"muzzle": Vector2(2.6, -0.13), "eject": Vector2(0.4, -1.0), "charge": Vector2(1.2, -0.2), "under": Vector2(1.15, -0.75),
			"sight": Vector2(0.6, 0.83), "rail": Vector2(1.1, 0.82), "relief": 0.2},
	"scar_h": {"length": 0.91, "grip": Vector2(-1.75, -0.7), "support": Vector2(1.3, -0.05), "mag": Vector2(-0.34, -0.6),
			"muzzle": Vector2(4.81, 0.226), "eject": Vector2(-0.3, 0.45), "charge": Vector2(1.6, 0.4), "under": Vector2(2.0, -0.05),
			"sight": Vector2(-1.88, 1.12), "rail": Vector2(-0.6, 0.7)},
	# bolt_action: [handle lift (rad), bolt throw (m)]. The AW's three-lug bolt
	# lifts a short 60 degrees and runs back a short stroke; the Mosin's two-lug
	# bolt turns a full 90 degrees and runs back much further.
	"l96a1": {"drop": ["blt"], "bolt_action": [1.05, 0.085], "length": 1.18, "grip": Vector2(-1.4, -0.65), "support": Vector2(2.0, -0.05), "mag": Vector2(0.0, -0.3),
			"muzzle": Vector2(7.25, 0.469), "eject": Vector2(0.0, 0.5), "charge": Vector2(-1.0, 0.45), "under": Vector2(3.5, -0.15),
			"sight": Vector2(-1.39, 0.95), "rail": Vector2(0.0, 0.7), "relief": 0.1},
	"mosin": {"bolt_action": [1.55, 0.105], "length": 1.24, "grip": Vector2(-3.2, -0.05), "support": Vector2(0.2, 0.1), "mag": Vector2(-1.7, -0.3),
			"muzzle": Vector2(6.2, 0.513), "eject": Vector2(-1.5, 0.6), "charge": Vector2(-2.3, 0.45), "under": Vector2(2.5, 0.0),
			"sight": Vector2(0.05, 0.8), "rail": Vector2(-1.5, 0.75), "relief": 0.45},
	# Remington 700: two-lug push-feed bolt, a full 90 degree lift and a long-action throw;
	# source scaled x1.3 at conversion (the model is drawn at 0.83 m)
	"m700": {"bolt_action": [1.5, 0.1], "length": 1.08, "grip": Vector2(-1.625, -0.39), "support": Vector2(1.69, -0.04), "mag": Vector2(0.17, -0.36),
			"muzzle": Vector2(6.2, 0.25), "eject": Vector2(-0.26, 0.29), "charge": Vector2(-0.72, 0.0), "under": Vector2(2.98, -0.09), "rail_adapter": true,
			"sight": Vector2(-1.9, 0.72), "rail": Vector2(0.0, 0.3), "relief": 0.1},
	"g17": {"length": 0.2, "pistol": true, "grip": Vector2(-0.62, -0.08), "mag": Vector2(-0.5, 0.3),
			"muzzle": Vector2(1.17, 0.566), "eject": Vector2(0.2, 0.62), "charge": Vector2(-0.75, 0.55), "under": Vector2(0.524, 0.295),
			"sight": Vector2(-0.787, 0.69)},
	"vp9": {"length": 0.27, "pistol": true, "grip": Vector2(-0.823, -0.33), "mag": Vector2(-0.77, -0.15),
			"muzzle": Vector2(1.424, 0.0), "eject": Vector2(-0.6, 0.1), "charge": Vector2(-1.35, 0.0), "under": Vector2(0.3, -0.15),
			"sight": Vector2(-1.053, 0.19)},
	# the v1.52 additions (assets-source/_tools/gun_specs/<id>.json). Points measured on gridded side renders of the
	# sources; "mag" is the top of the magazine in its well (the extended mag stretches down from it).
	# AUG A3/A4: the A1's receiver, so grip, mag, port and charging handle match it; railed handguard, flip-up irons
	"aug_a4": {"length": 0.7, "grip": Vector2(-0.767, -0.304), "support": Vector2(1.7, -0.05), "mag": Vector2(-1.81, -0.1),
			"muzzle": Vector2(3.06, 0.215), "eject": Vector2(-1.5, 0.2), "charge": Vector2(0.95, 0.3), "under": Vector2(2.2, -0.1),
			"sight": Vector2(-1.18, 1.0), "rail": Vector2(-0.4, 0.63), "relief": 0.1},
	"bren_2": {"length": 0.76, "grip": Vector2(-1.38, -0.75), "support": Vector2(1.35, -0.12), "mag": Vector2(-0.14, -0.22),
			"muzzle": Vector2(3.65, 0.02), "eject": Vector2(-0.6, 0.15), "charge": Vector2(0.6, 0.35), "under": Vector2(1.8, -0.2),
			"sight": Vector2(-1.5, 0.89), "rail": Vector2(-0.6, 0.5)},
	# MP7A1: the magazine sits in the pistol grip; the support hand takes the folded foregrip under the front.
	# Its suppressor is the glb's Suppressor part, already seated over the flash hider.
	"mp7_a1": {"length": 0.42, "grip": Vector2(-0.56, -0.22), "support": Vector2(0.9, -0.05), "mag": Vector2(-0.5, 0.04),
			"muzzle": Vector2(2.08, 0.305), "eject": Vector2(0.1, 0.35), "charge": Vector2(-1.85, 0.66), "under": Vector2(1.0, -0.16),
			"sight": Vector2(-1.405, 0.95), "rail": Vector2(-0.3, 0.8), "relief": 0.2},
	# PDR-C: bullpup, the support hand on its built-in vertical front grip; irons are the glb's Iron part (MBUS 3)
	"pdr_c": {"length": 0.46, "grip": Vector2(0.58, -0.47), "support": Vector2(1.82, -0.4), "mag": Vector2(-0.6, -0.03),
			"muzzle": Vector2(2.28, 0.265), "eject": Vector2(0.5, 0.3), "charge": Vector2(1.7, 0.22), "under": Vector2(1.6, 0.0),
			"sight": Vector2(-0.05, 0.94), "rail": Vector2(0.8, 0.615), "relief": 0.1},
	# Honey Badger: integral suppressor (the muzzle is its front cap)
	"honey_badger": {"length": 0.81, "grip": Vector2(-1.62, -0.62), "support": Vector2(1.3, 0.0), "mag": Vector2(-0.37, -0.02),
			"muzzle": Vector2(3.71, 0.22), "eject": Vector2(-0.5, 0.3), "charge": Vector2(-1.8, 0.45), "under": Vector2(2.2, 0.0),
			"sight": Vector2(-1.47, 0.9), "rail": Vector2(-0.6, 0.54)},
	# SCAR-SC: the SCAR-H's receiver and sights on a short barrel and handguard
	"scar_sc": {"length": 0.52, "grip": Vector2(-1.78, -0.7), "support": Vector2(0.6, -0.05), "mag": Vector2(-0.43, -0.04),
			"muzzle": Vector2(2.03, 0.23), "eject": Vector2(-0.3, 0.45), "charge": Vector2(0.3, 0.3), "under": Vector2(0.85, -0.1),
			"sight": Vector2(-1.88, 1.12), "rail": Vector2(-0.6, 0.7)},
	# MCX Spear: the EOTech XPS2 is the glb's Optic part; irons are its Iron part (MBUS 3 behind and ahead of it)
	"mcx_spear": {"length": 0.81, "grip": Vector2(-1.1, -0.62), "support": Vector2(1.6, 0.0), "mag": Vector2(0.15, -0.02),
			"muzzle": Vector2(3.78, 0.245), "eject": Vector2(0.2, 0.3), "charge": Vector2(-1.65, 0.65), "under": Vector2(2.4, 0.0),
			"sight": Vector2(-1.2, 1.06), "rail": Vector2(0.66, 0.74)},
}


## A source side-view point (x forward, z up, 10 cm units) in weapon space.
static func _lp(v: Vector2, g: Vector2, side: float = 0.0) -> Vector3:
	return Vector3(side, (v.y - g.y) * 0.1, -(v.x - g.x) * 0.1)


static func _low_poly(r: Node3D, model: String, att: Dictionary = {}) -> Dictionary:
	var spec: Dictionary = LP_GUNS.get(model, {})
	var handguard := String(att.get("handguard", "standard"))
	var pistol := bool(spec.get("pistol", false))
	var path := LOW_POLY + model + ".glb"
	if spec.is_empty() or not ResourceLoader.exists(path):
		return _placeholder(r, float(spec.get("length", 0.8)), pistol)
	var list := _glb_list(path)
	var factory_parts := {}
	var mag: Array = []
	var bolt: Node3D = null
	for e in list:
		var part := String(e[0])
		if part.begins_with("Optic") or part.begins_with("Suppressor"):
			factory_parts["factory_optic" if part.begins_with("Optic") else "factory_suppressor"] = e
			continue
		if part.begins_with("Iron") and att.get("optic", "iron") != "iron":
			continue
		if part.begins_with("Mag"):
			mag = [e[1], e[2]]
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = e[1]
		mi.transform = e[2]
		mi.set_meta("pack4", true)   # skins recolour these too
		if part.begins_with("Body") and handguard == "hex" and spec.has("hex"):
			mi.mesh = _without_handguard(model, e[1], e[2], spec)
		if part.begins_with("Body") and spec.has("drop"):
			mi.mesh = _without_surfaces(mi.mesh, spec.drop)
		_clear_glass(mi)   # after the mesh is final: overrides go by surface index
		if part.begins_with("Bolt"):
			bolt = Node3D.new()
			bolt.name = "Bolt"
			r.add_child(bolt)
			bolt.add_child(mi)
		else:
			r.add_child(mi)
	var g: Vector2 = spec.grip
	if handguard == "hex" and spec.has("hex"):
		# the tube's rear sits where the gun's own handguard began, on the bore line
		var hz: Array = spec.hex
		var tube := _att_model(r, "hex_handguard")
		if tube != null:
			tube.position = Vector3(0, (spec.muzzle.y - g.y) * 0.1, float(hz[1]))
			_tag_tree(tube, "handguard")
	var under := _lp(spec.under, g)
	# every gun can take the rail now, so its mount sits on the model's real underside
	under.y = _bottom_at(r, under.z, under.y)
	var sight := _lp(spec.sight, g)
	var rail := _lp(spec.get("rail", spec.sight), g)
	var action: Array = spec.get("bolt_action", [])
	var charge: Node3D
	if bolt != null and not action.is_empty():
		charge = _turn_bolt(bolt)
	else:
		charge = _marker(r, "Charge", _lp(spec.charge, g))
		action = []
	var out := {
		"glb": true, "glb_mag": mag, "bolt": bolt, "pistol": pistol, "bolt_action": action,
		"grip": _marker(r, "Grip", Vector3(0, -0.01, 0.0), Vector3(-0.25 if pistol else -0.3, 0, 0)),
		"charge": charge,
		"eject": _marker(r, "Eject", _lp(spec.eject, g, 0.02)),
		"muzzle_at": _marker(r, "MuzzleAt", _lp(spec.muzzle, g)),
		"under_at": _marker(r, "UnderAt", under),
		"rail_adapter": bool(spec.get("rail_adapter", false)),
		"mag_at": _marker(r, "MagAt", _lp(spec.mag, g)),
		"mag_style": "none",
		"stock_at": r,
		"stock_style": "",
		"rail_y": rail.y, "rail_z": rail.z,
		"iron_builtin": true, "iron_y": sight.y, "iron_rear_z": sight.z, "iron_relief": float(spec.get("relief", 0.16)),
	}
	if pistol:
		out.support = _marker(r, "Support", Vector3(-0.03, -0.025, 0.0), Vector3(-0.25, 0, -0.6))
		out.mini = true
	else:
		out.support = _marker(r, "Support", _lp(spec.support, g, -0.005), Vector3(0, 0, -0.5))
	out.merge(factory_parts)
	return out


## Optional parts exported in the same grip-centred coordinates as the body.
static func _factory_part(root: Node3D, part_name: String, entry: Array) -> Node3D:
	var holder := _marker(root, part_name, Vector3.ZERO)
	holder.set_meta("factory_part", true)   # drawn where the gun's own model put it (tests know it clamps on)
	var mi := MeshInstance3D.new()
	mi.mesh = entry[1]
	mi.transform = entry[2]
	mi.set_meta("pack4", true)
	_clear_glass(mi)
	holder.add_child(mi)
	return holder


## Turn-bolt rifles: the bolt pivot moves onto the bolt body's own axis (the
## middle of its geometry along the centreline), so lifting the handle turns the
## bolt in place instead of swinging it round the grip. The hand's target is the
## handle's knob (its outermost point to the right), on the bolt, so the hand
## rides with the lift and the pull. Returns that "Charge" marker.
static func _turn_bolt(bolt: Node3D) -> Node3D:
	var lo := INF
	var hi := -INF
	var knob := Vector3(-INF, 0, 0)
	for c in bolt.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		for v in mi.mesh.get_faces():
			var p: Vector3 = mi.transform * v
			if absf(p.x) < 0.012:
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
			if p.x > knob.x:
				knob = p
	var axis := (lo + hi) * 0.5 if lo < hi else knob.y
	bolt.position = Vector3(0, axis, 0)
	for c in bolt.get_children():
		(c as Node3D).position.y -= axis
	return _marker(bolt, "Charge", Vector3(knob.x - 0.008, knob.y - axis, knob.z))


## Ring round the bore (m) that is the handguard shell: inside is the barrel, outside
## sights / scopes that overhang it, both kept.
const HANDGUARD_SHELL := Vector2(0.017, 0.045)
static var _hg_cache := {}


## The gun's body mesh with its own handguard cut away (triangles in the
## handguard's length whose centre lies in the shell round the bore), for the hex tube.
static func _without_handguard(model: String, mesh: Mesh, xf: Transform3D, spec: Dictionary) -> Mesh:
	if _hg_cache.has(model):
		return _hg_cache[model]
	var g: Vector2 = spec.grip
	var bore_y := (float(spec.muzzle.y) - g.y) * 0.1
	var hz: Array = spec.hex
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var c := (xf * verts[idx[t]] + xf * verts[idx[t + 1]] + xf * verts[idx[t + 2]]) / 3.0
			var rad := Vector2(c.x, c.y - bore_y).length()
			var cut := c.z > float(hz[0]) and c.z < float(hz[1]) and rad > HANDGUARD_SHELL.x and rad < HANDGUARD_SHELL.y
			if not cut:
				keep.append(idx[t]); keep.append(idx[t + 1]); keep.append(idx[t + 2])
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	_hg_cache[model] = out
	return out


## Stand-in when a gun's model file is missing (the asset packs are not in the
## repository): a plain dark block of the right length, so the gun still works.
static func _placeholder(r: Node3D, length: float, pistol: bool) -> Dictionary:
	var h := 0.05 if pistol else 0.07
	_part(r, ML.box(Vector3(0.03 if pistol else 0.045, h, length)), _black, Vector3(0, h * 0.5, -length * 0.35))
	_part(r, ML.box(Vector3(0.03, 0.1, 0.04)), _black, Vector3(0, -0.04, 0.01), Vector3(-0.3, 0, 0))
	return {
		"plain": true, "pistol": pistol, "mini": pistol,
		"grip": _marker(r, "Grip", Vector3(0, -0.01, 0.0), Vector3(-0.25 if pistol else -0.3, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.03, -0.025, 0.0) if pistol else Vector3(-0.005, 0.0, -length * 0.45), Vector3(0, 0, -0.5)),
		"charge": _marker(r, "Charge", Vector3(0, h, 0.0)),
		"eject": _marker(r, "Eject", Vector3(0.02, h, -0.05)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, h * 0.5, -length * 0.85)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.0, -length * 0.4)),
		"mag_at": _marker(r, "MagAt", Vector3(0, 0.0, -0.05)),
		"mag_style": "pistol" if pistol else "box",
		"stock_at": r,
		"stock_style": "",
		"rail_y": h, "rail_z": -0.05,
		"iron_builtin": true, "iron_y": h + 0.01, "iron_rear_z": 0.0,
	}


## Moves the part named `part_name` under a "Bolt" pivot the weapon slides
## back on every shot (pistol slide, rifle bolt); null if the model lacks it.
static func _moving_part(r: Node3D, part_name: String) -> Node3D:
	var mi := r.get_node_or_null(part_name)
	if mi == null:
		return null
	var bolt := Node3D.new()
	bolt.name = "Bolt"
	r.add_child(bolt)
	mi.reparent(bolt, false)   # the pivot sits at the origin: same transform
	return bolt


## The mag-release button matched the "Mag" filter but stays on the frame.
static func _keep_eject(r: Node3D, held: Dictionary) -> void:
	for k in held:
		if String(k).contains("Eject"):
			var mi := MeshInstance3D.new()
			mi.mesh = held[k][0]
			mi.transform = held[k][1]
			mi.set_meta("pack4", true)
			r.add_child(mi)

# ====================================================================== attachments
# Every attachment is a low-poly model (assets/thirdparty/low_poly_attachments/,
# not in the repository), converted with Blender so its mount point is at the
# origin and its front faces -Z. A missing model leaves the slot bare: the
# stats still apply.

const LP_ATT := "res://assets/thirdparty/low_poly_attachments/"
## Optic sight lines measured on the models: height of the dot above the mount
## base, and how far behind the mount centre the rear of the window sits.
const LP_OPTICS := {"reddot": [0.0561, 0.062, 0.16], "holo": [0.0561, 0.024, 0.24],
		"micro_dot": [0.045, 0.03, 0.18], "reflex": [0.038, 0.035, 0.18], "uh1_holo": [0.042, 0.04, 0.22]}
## The PEQ asset's origin is on its inward-facing clamp. The smaller front aperture
## and the angled grip's finger contact were measured in the converted meshes.
const PEQ_EMITTER := Vector3(0.01703, -0.0177, -0.0285)
const AFG_CONTACT := Vector3(0, -0.027, 0)
## The angled foregrip is drawn at this share of its 12 cm: full length overran the short handguards (SCAR-SC,
## SCAR-H) onto the barrel. Where the vertical grip's palm sits on it (its middle, 4 cm below the rail).
const AFG_LENGTH := 0.8
const VFG_CONTACT := Vector3(0, -0.04, 0)
## The rail adapter's depth: an underbarrel part hangs this far below the gun.
const LP_RAIL_DROP := 0.0126
## Compact bottom adapter for pistols.
const LP_PISTOL_UNDER_SCALE := 0.6


## The attachment model `name` under `at`, or null when its file is missing.
static func _att_model(at: Node3D, name: String) -> Node3D:
	var path := LP_ATT + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var list := _glb_list(path)
	var holder := Node3D.new()
	holder.name = "Att_" + name
	at.add_child(holder)
	for e in list:
		var mi := MeshInstance3D.new()
		mi.mesh = e[1]
		mi.transform = e[2]
		mi.set_meta("pack4", true)   # skins recolour attachments too (glass and reticles excepted)
		_clear_glass(mi)
		holder.add_child(mi)
	return holder


## Lenses and sight windows exported as opaque surfaces get the see-through
## sight glass, so aiming down the sights is not blocked. The palette-named
## models (L96A1, AS VAL, P90) call their lens "1g" and their bare steel "1w";
## both come in flat white, which drew chalk-white bolts and scope lenses.
static func _clear_glass(mi: MeshInstance3D) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m != null:
			var n := m.resource_name.to_lower()
			if n.contains("glass") or n.contains("lens") or n == "1g":
				mi.set_surface_override_material(s, _glass)
			elif n == "1w":
				mi.set_surface_override_material(s, _steel)


## `mesh` without the surfaces whose material is named in `names` (stray parts
## baked into a model, like the loose cartridge under the L96A1's action).
static var _drop_cache := {}

static func _without_surfaces(mesh: Mesh, names: Array) -> Mesh:
	if _drop_cache.has(mesh):
		return _drop_cache[mesh]
	var out := ArrayMesh.new()
	_drop_cache[mesh] = out
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat != null and names.has(mat.resource_name):
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## The centre of a launcher's muzzle: the middle of the geometry within 1.5 cm
## of the model's front face (its barrel's mouth), in the holder's space.
static func _bore_front(holder: Node3D) -> Vector3:
	var front := -_reach(holder)
	var sum := Vector3.ZERO
	var n := 0
	for c in holder.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			for v in mi.mesh.get_faces():
				var w: Vector3 = mi.transform * v
				if w.z < front + 0.015:
					sum += w
					n += 1
	return Vector3(0, sum.y / n, front) if n > 0 else Vector3(0, -0.045, front)


## How far a model reaches forward (-Z) of its origin.
static func _reach(holder: Node3D) -> float:
	var front := 0.0
	for c in holder.get_children():
		if c is MeshInstance3D:
			var a: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb()
			front = minf(front, a.position.z)
	return -front


static func _muzzle(at: Node3D, kind: String, pistol: bool) -> Node3D:
	if kind in ["suppressor", "heavy_suppressor", "flash_hider", "brake"]:
		var m := _att_model(at, "pistol_suppressor" if pistol and kind == "suppressor" else kind)
		if m != null:
			return _marker(at, "Muzzle", Vector3(0, 0, -_reach(m)))
	return _marker(at, "Muzzle", Vector3.ZERO)


static func _underbarrel(at: Node3D, kind: String) -> Dictionary:
	if kind == "gp25":
		var g := _att_model(at, "gp25")
		if g != null:
			return {"launcher": _marker(at, "Launcher", _bore_front(g)), "housing": g}
		return {"launcher": _marker(at, "Launcher", Vector3(0, -0.045, -0.16))}
	if kind == "afg":
		var grip := _att_model(at, "afg")
		if grip != null:
			# the hand on the grip's ramp keeps the handguard hold's roll: tilting it 30 degrees along the ramp
			# bent the left wrist 55-75 degrees in the high-port sprint (fp_hand_pose_test)
			return {"housing": grip, "support": _marker(grip, "AFGSupport", AFG_CONTACT, Vector3(0.0, 0, -0.5))}
	if kind == "vfg":
		var grip := _att_model(at, "vfg")
		if grip != null:
			# the hand round the post keeps the handguard hold's roll, like the angled grip: the AUG A1's
			# upright hand passed the high-port sprint 1 degree past the left wrist's range (fp_hand_pose_test)
			return {"housing": grip, "support": _marker(grip, "VFGSupport", VFG_CONTACT, Vector3(0.0, 0, -0.5))}
	return {}


## A bottom-rail grip (angled or vertical) seated on this gun: shortened (the angled one), slid back until it
## ends before the handguard does (the gun's underside rising more than 12 mm ahead of it is the barrel), and
## raised or lowered so its top meets the lowest point of the underside over its length and width: never floating under
## a suppressor or sunk into a sloped handguard. Worked out once per gun and handguard.
static func _seat_grip(root: Node3D, grip: Node3D, kind: String, key: String) -> void:
	if kind == "afg":
		grip.scale = Vector3(grip.scale.x, grip.scale.y, grip.scale.z * AFG_LENGTH)
	if not _fit_memo.has(key):
		var to_root := Transform3D.IDENTITY   # the grip's parent in root space
		var p := grip.get_parent()
		while p != null and p != root:
			to_root = (p as Node3D).transform * to_root
			p = p.get_parent()
		var box: AABB = to_root * _holder_box(grip)
		var probe := Probe.new(_faces_of(root, grip))
		var rear := box.end.z
		var base := probe.bottom(rear - 0.004)
		var shift := Vector3.ZERO
		if is_finite(base):
			# walk forward from the grip's rear while the handguard's underside carries on
			var front_ok := rear
			var z := rear - 0.004
			while z > box.position.z - 0.08:
				var b := probe.bottom(z)
				if not is_finite(b) or b > base + 0.012:
					break
				front_ok = z
				z -= 0.004
			if box.position.z < front_ok + 0.003:
				shift.z = front_ok + 0.003 - box.position.z
			# the top meets the lowest point of the underside over its (moved) length
			var low := INF
			for k in 7:
				var zz := lerpf(box.position.z + shift.z + 0.004, box.end.z + shift.z - 0.004, k / 6.0)
				for x in [-0.008, 0.0, 0.008]:   # either side too: a slotted handguard (MCX) has gaps on the centre line
					low = minf(low, probe.bottom(zz, x))
			if is_finite(low):
				shift.y = low - box.end.y
		_fit_memo[key] = to_root.basis.inverse() * shift
	grip.position += _fit_memo[key]


## Compact guns with their torch on the right use the opposite cheek. Each gun's
## clamp seats against its own mesh at the selected handguard station.
static func _side_laser(root: Node3D, b: Dictionary, model: String, handguard: String) -> Node3D:
	var housing := _att_model(root, "peq2")
	if housing == null:
		return null
	var key := "peq|%s|%s" % [model, handguard]
	if not _fit_memo.has(key):
		var side := -1.0 if model in ["p90", "mgp7", "mp7_a1", "pdr_c"] else 1.0
		var compact := bool(b.get("pistol", false))
		var size := 0.46 if compact else (0.68 if model in ["mp7_a1", "pdr_c", "gepard", "p90", "mgp7"] else 0.84)
		var muzzle: Vector3 = b.muzzle_at.position
		var centre: Vector3 = b.under_at.position
		centre.y = muzzle.y - (0.016 if compact else 0.004)
		if model == "p90":
			centre.z = muzzle.z + 0.073
			centre.y += 0.018
		# Restrict the probe to the barrel and receiver. An installed launcher, optic
		# or detachable magazine cannot change how far the side mount stands off.
		var faces := PackedVector3Array()
		for child in root.get_children():
			if child is MeshInstance3D and not child.has_meta("skin_part"):
				faces.append_array(child.transform * _mesh_faces(child.mesh))
		var width := -INF
		for dz: float in [-0.018, 0.0, 0.018]:
			var hit := _surface_x(faces, centre + Vector3.BACK * dz * size, side)
			if is_finite(hit):
				width = maxf(width, hit * side)
		centre.x = side * (width if is_finite(width) else 0.018)
		var roll := PI if side < 0.0 else 0.0
		_fit_memo[key] = Transform3D(Basis(Vector3.BACK, roll).scaled(Vector3.ONE * size), centre)
	housing.transform = _fit_memo[key]
	return _marker(housing, "Laser", PEQ_EMITTER)


## Fit the glove to the rendered prop in model space. Only the contact geometry
## enters this cache; paints, optics and muzzle finishes share the same holds.
static func _palm_sockets(root: Node3D, b: Dictionary, model: String, att: Dictionary,
		mount: Node3D, housing: Node3D) -> Array:
	var key := "palms|%s|%s|%s|%s|%s" % [model, att.get("handguard", ""), att.get("rail", ""),
			att.get("underbarrel", ""), att.get("magazine", "")]
	if _fit_memo.has(key):
		return _fit_memo[key]
	var faces := _faces_of(root)
	var right: Transform3D = b.grip.transform
	var left: Transform3D = b.support.transform
	var pistol := bool(b.get("pistol", false))
	var z := left.origin.z
	var under := String(att.get("underbarrel", "none"))
	var post_y := NAN   # a vertical grip's middle: the hand closes round it there
	if housing != null and not pistol:
		var mount_xf := mount.transform
		var parent := mount.get_parent() as Node3D
		while parent != null and parent != root:
			mount_xf = parent.transform * mount_xf
			parent = parent.get_parent() as Node3D
		var bounds: AABB = mount_xf * _holder_box(housing)
		if under == "gp25":
			# Use the reachable end when an adapter sits unusually far forward.
			z = clampf(left.origin.z, bounds.position.z + 0.025, bounds.end.z - 0.025)
		elif under == "vfg":
			z = bounds.get_center().z   # the hand round the vertical grip's post
			post_y = bounds.get_center().y
		elif z >= bounds.position.z - 0.025 and z <= bounds.end.z + 0.035:
			z = minf(bounds.end.z + 0.036, lerpf(left.origin.z, right.origin.z, 0.35))
	var vertical := (model == "aug_a1" and under != "gp25") or under == "vfg"
	var grip_slice := _faces_near(faces, right.origin.z - 0.025, right.origin.z + 0.025)
	var pitch: float = {"mosin": -0.12, "marlin": -0.18, "l96a1": -0.24, "m700": -0.18}.get(model, right.basis.get_euler().x)
	right.basis = Basis(Vector3.RIGHT, pitch)
	# How open each hand is still follows where a palm laid against the prop's side would sit (its width there).
	var palm_side := _palm_edge(grip_slice, right.origin, 1.0, right.basis, 0.018)
	var openness := Vector2(0, clampf(palm_side.x * 3.0, 0.025, 0.12))
	right.origin = _wrap_hold(grip_slice, right.origin, 1.0, right.basis)
	right = _tilt_hold(right, right * GLOVE_CHANNEL, HOLD_TILT[1])
	if pistol:
		# The second hand wraps the first glove on compact props.
		left.origin = right.origin + Vector3(-0.055, -0.014, -0.01)
		left.basis = Basis.from_euler(Vector3(-0.21, 0.10, -0.24))
		openness.x = 0.12
	else:
		var section := _faces_near(faces, z - 0.012, z + 0.012)
		var bottom := _bottom_in(section, z)
		var top := _top_in(section, z, 0.004)
		var y := left.origin.y if is_nan(post_y) else post_y
		if is_finite(bottom) and is_finite(top):
			y = clampf(y, bottom + 0.008, maxf(bottom + 0.008, top - 0.006)) if vertical else bottom + minf(0.022, (top - bottom) * 0.4)
		var roll := -0.30 if model in ["gepard", "p90"] else -0.12
		left.basis = Basis.from_euler(Vector3(-0.14, 0, -0.08 if vertical else roll))
		var palm_left := _palm_edge(section, Vector3(-0.014, y, z), -1.0, left.basis, 0.024)
		openness.x = clampf((absf(palm_left.x) - 0.023) * 4.5, 0.02, 0.24)
		left.origin = _wrap_hold(section, Vector3(0, y, z), -1.0, left.basis)
	left = _tilt_hold(left, left * (GLOVE_CHANNEL * Vector3(-1, 1, 1)), HOLD_TILT[0])
	_fit_memo[key] = [left, right, openness]
	return _fit_memo[key]


## The operator glove (operator_hand.gd) is a closed fist: its curled fingers form a channel about 2 cm across,
## centred 6.8 cm in front of the heel of the palm (the knife's PALM_FROM_HANDLE measures the same channel).
## Put the palm behind the prop so the grip or handguard runs through that channel instead of through the heel.
const GLOVE_CHANNEL := Vector3(-0.005, 0, -0.068)

## Palm socket that wraps the glove's fingers round the prop's cross-section at `at` (centred on its width there).
static func _wrap_hold(faces: PackedVector3Array, at: Vector3, side: float, basis: Basis) -> Vector3:
	var near := _surface_x(faces, at, side)
	var far := _surface_x(faces, at, -side)
	var centre := at
	if is_finite(near) and is_finite(far):
		centre.x = (near + far) * 0.5
	return centre - basis * Vector3(GLOVE_CHANNEL.x * side, GLOVE_CHANNEL.y, GLOVE_CHANNEL.z)

## Turns a palm socket about the prop at `pivot` (the grip in the finger channel) so the wrist can sit straighter.
static func _tilt_hold(xf: Transform3D, pivot: Vector3, euler: Vector3) -> Transform3D:
	var turned := xf.basis * Basis.from_euler(euler)
	return Transform3D(turned, pivot + turned * (xf.basis.inverse() * (xf.origin - pivot)))

## Tilt (radians, hand space) of each glove about the prop it wraps: [left, right]. Wrapping puts the palm 5 cm
## further back than the old palm-side sockets; these keep the wrists inside fp_hand_pose_test's limits through the
## sprint carry (found by sweeping each axis against that test).
const HOLD_TILT := [Vector3(0.1, -0.06, 0.0), Vector3(0.1, 0.0, 0.0)]

## The prop's outer surface seen from one side along x, at the height and depth of `at` (INF when missed).
static func _surface_x(faces: PackedVector3Array, at: Vector3, side: float) -> float:
	var start := Vector3(side * 0.25, at.y, at.z)
	var best := INF
	var x := INF
	for i in range(0, faces.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(start, Vector3.LEFT * side, faces[i], faces[i + 1], faces[i + 2])
		if hit != null and start.distance_squared_to(hit) < best:
			best = start.distance_squared_to(hit)
			x = hit.x
	return x


## The socket is the wrist. Fit the fleshy part of the palm, slightly ahead
## of that socket, to the first triangle seen from this side of the prop.
static func _palm_edge(faces: PackedVector3Array, center: Vector3, side: float, basis: Basis, palm_length: float) -> Vector3:
	var start := Vector3(side * 0.25, center.y, center.z)
	var direction := Vector3.LEFT * side
	var edge := center
	var nearest := INF
	for i in range(0, faces.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(start, direction, faces[i], faces[i + 1], faces[i + 2])
		if hit != null:
			var distance := start.distance_squared_to(hit)
			if distance < nearest:
				nearest = distance
				edge = hit
	return edge - basis * Vector3(-side * 0.010, 0, -palm_length)


## The optic on the rail, or the gun's own sights.
static func _optic(r: Node3D, b: Dictionary, kind: String) -> Dictionary:
	if kind == "holo" and b.has("factory_optic"):
		var mount := _marker(r, "OpticMount", Vector3.ZERO)
		var sight := _factory_part(mount, "Att_holo", b.factory_optic)
		var dot := _reticle_centre(sight)
		if dot != Vector3.INF:
			sight.position.x = -dot.x
			return {"y": dot.y, "rear_z": dot.z + 0.02, "relief": float(LP_OPTICS.holo[2])}
		mount.free()
	if LP_OPTICS.has(kind):
		var mount := Node3D.new()
		mount.name = "OpticMount"
		mount.position = Vector3(0, float(b.rail_y), float(b.rail_z))
		r.add_child(mount)
		var m := _att_model(mount, kind)
		if m != null:
			# the sight line runs through the optic's own reticle
			var o: Array = LP_OPTICS[kind]
			var c := _reticle_centre(m)
			if c != Vector3.INF:
				m.position.x = -c.x   # the models sit a little off-centre: put the reticle on the bore line
			_seat_optic(r, mount, m, float(b.rail_y))
			var y := mount.position.y + (c.y if c != Vector3.INF else float(o[0]))
			var rear := mount.position.z + (c.z + 0.02 if c != Vector3.INF else float(o[1]))
			return {"y": y, "rear_z": rear, "relief": float(o[2])}
		mount.free()
	return {"y": float(b.iron_y), "rear_z": float(b.iron_rear_z), "relief": float(b.get("iron_relief", 0.16))}


## Sits the optic's base flush on the gun's top rail. The nominal mount point
## can leave it floating above the rail (P90) or sunk into a sight block
## (Gepard): the rail's real top is measured under the optic's whole footprint,
## the mount slides along the rail (up to 6 cm) to the nearest stretch that is
## flat at rail height, and the optic is set down on it.
static func _seat_optic_compute(r: Node3D, mount: Node3D, optic: Node3D, rail_y: float) -> void:
	var box := _holder_box(optic)
	var z0 := mount.position.z
	var probe := Probe.new(_faces_near(_faces_of(r, mount), z0 + box.position.z - 0.065, z0 + box.end.z + 0.065))
	var best_dz := 0.0
	var best_top := _top_under(probe, z0 + box.position.z, z0 + box.end.z)
	if not is_finite(best_top):
		return
	if absf(best_top - rail_y) > 0.004:
		for i in range(1, 49):
			var dz := 0.0025 * float((i + 1) / 2) * (1.0 if i % 2 == 1 else -1.0)
			var top := _top_under(probe, z0 + dz + box.position.z, z0 + dz + box.end.z)
			if is_finite(top) and absf(top - rail_y) <= 0.004:
				best_dz = dz
				best_top = top
				break
	mount.position = Vector3(0, best_top - box.position.y, z0 + best_dz)


## Highest point of the gun along the centre of its top between z0 and z1
## (both rail edges and the middle), or -INF over nothing.
static func _top_under(probe: Probe, z0: float, z1: float) -> float:
	var best := -INF
	for k in 7:
		var z := lerpf(z0 + 0.004, z1 - 0.004, k / 6.0)
		for x in [-0.008, 0.0, 0.008]:
			best = maxf(best, probe.top(z, x))
	return best


## Vertical probes into one fixed set of triangles, for fits that probe it hundreds of times (seating an optic,
## sliding a rail adapter along the underside). For each probe line x it keeps the triangles that cross it, sorted
## into Z_BIN slices along z, so a probe tests only its own slice of its own line instead of every triangle.
## Each answer is still the exact ray test over every triangle the line can pass through: the same result as
## _top_in / _bottom_in on the whole set.
class Probe:
	const Z_BIN := 0.005
	var faces: PackedVector3Array
	var _lines := {}

	func _init(f: PackedVector3Array) -> void:
		faces = f

	## Highest surface the vertical line at (x, z) meets, -INF when it misses.
	func top(z: float, x: float = 0.0) -> float:
		var best := -INF
		for i in _slice(x, z):
			var hit = Geometry3D.ray_intersects_triangle(Vector3(x, 1.0, z), Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2])
			if hit != null:
				best = maxf(best, (hit as Vector3).y)
		return best

	## Lowest surface the vertical line at (x, z) meets, INF when it misses.
	func bottom(z: float, x: float = 0.0) -> float:
		var best := INF
		for i in _slice(x, z):
			var hit = Geometry3D.ray_intersects_triangle(Vector3(x, -1.0, z), Vector3.UP, faces[i], faces[i + 1], faces[i + 2])
			if hit != null:
				best = minf(best, (hit as Vector3).y)
		return best

	## First-vertex indices of the triangles spanning x whose z range reaches z's slice.
	func _slice(x: float, z: float) -> Array:
		if not _lines.has(x):
			var bins := {}
			for i in range(0, faces.size(), 3):
				var a := faces[i]
				var b := faces[i + 1]
				var c := faces[i + 2]
				if minf(a.x, minf(b.x, c.x)) > x or maxf(a.x, maxf(b.x, c.x)) < x:
					continue
				var lo := int(floor(minf(a.z, minf(b.z, c.z)) / Z_BIN))
				var hi := int(floor(maxf(a.z, maxf(b.z, c.z)) / Z_BIN))
				for k in range(lo, hi + 1):
					if not bins.has(k):
						bins[k] = []
					bins[k].append(i)
			_lines[x] = bins
		return _lines[x].get(int(floor(z / Z_BIN)), [])


## Lowest point of the gun's underside at `z` along the centreline (where a
## rail adapter clamps), from the parts built so far; `fallback` if nothing is there.
static func _bottom_at_compute(r: Node3D, z: float, fallback: float) -> float:
	var best := _bottom_in(_faces_of(r), z)
	return best if best < INF else fallback


## Every triangle under `r` in r's space, leaving out the subtree `skip`.
static func _faces_of(r: Node3D, skip: Node = null) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in r.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or (skip != null and (skip == mi or skip.is_ancestor_of(mi))):
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != r:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		out.append_array(xf * _mesh_faces(mi.mesh))   # one native transform, not a GDScript loop
	return out


## A mesh's triangles (mesh space), cached: models never change once loaded, and
## Mesh.get_faces() builds a fresh array on every call.
static var _faces_cache := {}

static func _mesh_faces(mesh: Mesh) -> PackedVector3Array:
	var k := mesh.get_instance_id()
	if not _faces_cache.has(k):
		_faces_cache[k] = mesh.get_faces()
	return _faces_cache[k]


## The triangles that reach into z0..z1 near the centreline (|x| < 3 cm).
static func _faces_near(faces: PackedVector3Array, z0: float, z1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if maxf(a.z, maxf(b.z, c.z)) < z0 or minf(a.z, minf(b.z, c.z)) > z1:
			continue
		if minf(a.x, minf(b.x, c.x)) > 0.03 or maxf(a.x, maxf(b.x, c.x)) < -0.03:
			continue
		out.append(a)
		out.append(b)
		out.append(c)
	return out


## Lowest surface a vertical line at (x, z) meets (INF when it misses the gun).
static func _bottom_in(faces: PackedVector3Array, z: float, x: float = 0.0) -> float:
	var best := INF
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var c := faces[i + 1]
		var d := faces[i + 2]
		if minf(a.z, minf(c.z, d.z)) > z or maxf(a.z, maxf(c.z, d.z)) < z:
			continue
		var hit = Geometry3D.ray_intersects_triangle(Vector3(x, -1.0, z), Vector3.UP, a, c, d)
		if hit != null:
			best = minf(best, (hit as Vector3).y)
	return best


## Highest surface a vertical line at (x, z) meets (-INF when it misses the gun).
static func _top_in(faces: PackedVector3Array, z: float, x: float = 0.0) -> float:
	var best := -INF
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var c := faces[i + 1]
		var d := faces[i + 2]
		if minf(a.z, minf(c.z, d.z)) > z or maxf(a.z, maxf(c.z, d.z)) < z:
			continue
		var hit = Geometry3D.ray_intersects_triangle(Vector3(x, 1.0, z), Vector3.DOWN, a, c, d)
		if hit != null:
			best = maxf(best, (hit as Vector3).y)
	return best


## Bounds of an attachment holder's meshes in its parent's space.
static func _holder_box(holder: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in holder.get_children():
		if c is MeshInstance3D:
			var a: AABB = holder.transform * ((c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb())
			box = a if first else box.merge(a)
			first = false
	return box


## the least share of its length a rail keeps when the underside has no flat stretch that long
const RAIL_MIN_SHARE := 0.45
## How far the rail may slide along the gun to find a flat underside: forward, back (m), in steps.
const RAIL_SLIDE_FORWARD := 0.25
const RAIL_SLIDE_BACK := 0.08
const RAIL_SLIDE_STEP := 0.005


## Fits the rail adapter flat to the gun's underside at `at`, cut to the clear stretch
## if a magazine or grip hangs lower within its length, and returns how far it moved
## (the underbarrel part then hangs from the rail's new face). Where the mount point has
## no flat underside long enough (over a magazine, a trigger loop or under a
## suppressor) the rail slides along the gun to the nearest stretch that has one,
## forward first, instead of hanging in the air below the lowest point.
static func _fit_rail_compute(r: Node3D, at: Node3D, rail: Node3D) -> Vector3:
	var box := _holder_box(rail)
	# the bar itself sits flush on the gun: its clamp posts (the model's top) sink
	# into the handguard instead of holding the bar off it with air showing
	var bar_top := _top_in(_faces_of(rail), box.get_center().z, box.get_center().x)
	var flush := (box.end.y - bar_top) * rail.scale.y if is_finite(bar_top) else 0.0
	var all := _faces_of(r, rail)
	var probe := Probe.new(all)   # the slide below probes the underside many times (x = 0 throughout)
	var half := box.size.z * 0.5
	var need := box.size.z * RAIL_MIN_SHARE
	var z0 := at.position.z
	var face_y := at.position.y
	var ends := _flat_span(probe, z0, face_y, half)
	var moved := Vector3.ZERO
	if float(ends[1]) - float(ends[0]) < need:
		var d := RAIL_SLIDE_STEP
		while d <= RAIL_SLIDE_FORWARD:
			for zc: float in ([z0 - d, z0 + d] if d <= RAIL_SLIDE_BACK else [z0 - d]):
				var fy := probe.bottom(zc)
				if not is_finite(fy):
					continue
				var e := _flat_span(probe, zc, fy, half)
				if float(e[1]) - float(e[0]) >= need:
					moved = Vector3(0, fy - face_y, zc - z0)
					z0 = zc
					face_y = fy
					ends = e
					break
			if moved != Vector3.ZERO:
				break
			d += RAIL_SLIDE_STEP
		rail.position += moved
	var span: float = float(ends[1]) - float(ends[0])
	var k := 1.0
	var mid := z0
	if span < box.size.z - 0.002:
		# never a stub: a rail shorter than this read as no rail at all (AS VAL, P90 came out 3 cm long)
		k = maxf(span, need) / box.size.z
		rail.scale.z *= k
		# centre the shortened rail on the clear stretch
		mid = (float(ends[0]) + float(ends[1])) * 0.5
		rail.position.z += mid - z0 - box.get_center().z * k
	var half_k := box.size.z * k * 0.5
	# follow the underside's slope: handguards rise or fall toward the muzzle, and a
	# level rail touched only at one end (the other clamp post hung in the air)
	var zf := mid - half_k * 0.92
	var zb := mid + half_k * 0.92
	var yf := probe.bottom(zf)
	var yb := probe.bottom(zb)
	if is_finite(yf) and is_finite(yb) and absf(yf - yb) < 0.03:
		var top := Vector3(box.get_center().x, box.end.y, box.get_center().z) * rail.scale
		var tilt := Basis(Vector3.RIGHT, atan2(yf - yb, zb - zf))
		rail.basis = tilt * Basis.from_scale(rail.scale)
		rail.position += top - tilt * top   # turn about the rail's top centre
		var dy := (yf + yb) * 0.5 - face_y + flush
		rail.position.y += dy
		return moved + Vector3(0, dy, 0)
	# a curved underside has no flat stretch even as long as the shortest rail: it
	# drops just clear of the lowest point over its length instead
	var low := INF
	for i in 7:
		low = minf(low, probe.bottom(lerpf(mid - half_k, mid + half_k, i / 6.0)))
	var drop := maxf(face_y - low, 0.0) if is_finite(low) else 0.0
	rail.position.y += flush - drop
	return moved + Vector3(0, flush - drop, 0)


## The stretch [z_front, z_back] around z0 where the gun's underside stays at
## face_y (nothing hangs below it, it doesn't step up away), at most `half` each way.
static func _flat_span(probe: Probe, z0: float, face_y: float, half: float) -> Array:
	var ends: Array = []
	for dir: float in [-1.0, 1.0]:
		var reach := 0.0
		while reach < half:
			var z := z0 + dir * (reach + 0.002)
			var low := probe.bottom(z)
			# something hangs below the clamp face, or the underside steps up away from it
			if low < face_y - 0.0015 or low > face_y + 0.006:
				break
			reach += 0.002
		ends.append(z0 + dir * reach)
	return ends


## Centre of an optic model's glowing reticle, in its holder's space (INF if none).
static func _reticle_centre_compute(holder: Node3D) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for c in holder.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).emission_enabled:
				for v in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					sum += mi.transform * v
					n += 1
	return sum / n if n > 0 else Vector3.INF

# ------------------------------------------------------------------ fit memo
## Fitting parts onto a gun (seating an optic on the rail, sliding an under-rail
## to a flat stretch, finding the underside, a reticle's centre) scans the gun's
## triangles in GDScript: tens of milliseconds per build. The answers depend only
## on which meshes sit where, so each is worked out once per configuration and
## remembered: the gunsmith rebuilds a gun on every click.
static var _fit_memo := {}


## Which meshes are under `r` and where (to the millimetre), leaving out `skip`.
static func _geo_key(r: Node3D, skip: Node = null) -> String:
	var parts := PackedStringArray()
	for n in r.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or (skip != null and (skip == mi or skip.is_ancestor_of(mi))):
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != r:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		parts.append("%d:%s" % [mi.mesh.get_instance_id(), _xf_key(xf)])
	return ";".join(parts)


static func _xf_key(xf: Transform3D) -> String:
	var b := xf.basis
	return "%.3f,%.3f,%.3f|%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [xf.origin.x, xf.origin.y, xf.origin.z,
			b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]


static func _seat_optic(r: Node3D, mount: Node3D, optic: Node3D, rail_y: float) -> void:
	var k := "seat|%s|%s|%s|%.4f" % [_geo_key(r, mount), _geo_key(optic), _xf_key(mount.transform), rail_y]
	if _fit_memo.has(k):
		mount.position = _fit_memo[k]
		return
	_seat_optic_compute(r, mount, optic, rail_y)
	_fit_memo[k] = mount.position


static func _fit_rail(r: Node3D, at: Node3D, rail: Node3D) -> Vector3:
	var k := "rail|%s|%s|%s|%s" % [_geo_key(r, rail), _geo_key(rail), _xf_key(at.transform), _xf_key(rail.transform)]
	if _fit_memo.has(k):
		rail.transform = _fit_memo[k][0]
		return _fit_memo[k][1]
	var moved := _fit_rail_compute(r, at, rail)
	_fit_memo[k] = [rail.transform, moved]
	return moved


static func _bottom_at(r: Node3D, z: float, fallback: float) -> float:
	var k := "bottom|%s|%.4f|%.4f" % [_geo_key(r), z, fallback]
	if not _fit_memo.has(k):
		_fit_memo[k] = _bottom_at_compute(r, z, fallback)
	return _fit_memo[k]


static func _reticle_centre(holder: Node3D) -> Vector3:
	var k := "reticle|%s" % _geo_key(holder)
	if not _fit_memo.has(k):
		_fit_memo[k] = _reticle_centre_compute(holder)
	return _fit_memo[k]
