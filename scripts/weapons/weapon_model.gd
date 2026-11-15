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
			b = _low_poly(root, model, String(att.get("handguard", "standard")))

	var parts := {"root": root, "blowback": float(b.get("blowback", 0.022 if b.get("pistol", false) else 0.045)), "grip": b.grip, "support": b.support, "charge": b.charge, "eject": b.eject,
			"pump": b.get("pump"), "bolt": b.get("bolt"), "roll": b.get("roll"), "hammer": b.get("hammer"), "twirl": b.get("twirl"), "lever": b.get("lever"), "laser": null}
	# magazine
	var mag_at: Node3D = b.mag_at
	if b.has("glb_mag"):
		parts.mag = _glb_mag(mag_at, b.glb_mag, String(att.get("magazine", "standard")))
	else:
		parts.mag = _marker(mag_at, "Mag", Vector3.ZERO)
	parts.mag_well = _marker(mag_at, "MagWell", Vector3(0, -0.05, 0))
	# muzzle device
	var mz := String(att.get("muzzle", "none"))
	if mz == "suppressor" and b.has("glb_suppressor") and _glb_suppressor(b.muzzle_at, String(b.glb_suppressor)):
		parts.muzzle = _marker(b.muzzle_at, "Muzzle", Vector3(0, 0, -float(b.glb_suppressor_len)))
	else:
		parts.muzzle = _muzzle(b.muzzle_at, mz, b.get("pistol", false))
	# underbarrel
	var ub_kind := String(att.get("underbarrel", "none"))
	var ub_at: Node3D = b.under_at
	var small := float(LP_PISTOL_UNDER_SCALE if b.get("pistol", false) else 1.0)
	# the rail slot: an adapter under the handguard (or frame) that underbarrel parts clamp to
	if String(att.get("rail", "none")) == "rail" or (ub_kind != "none" and b.get("rail_adapter", false)):
		var rail := _att_model(ub_at, "rail")
		if rail != null:
			rail.scale = Vector3.ONE * small
			ub_at = _marker(ub_at, "RailFace", Vector3(0, -LP_RAIL_DROP * small, 0))
	var ub := _underbarrel(ub_at, ub_kind, small)
	if ub.has("support"):
		parts.support = ub.support
	if ub.has("laser"):
		parts.laser = ub.laser
	parts.launcher = ub.get("launcher")
	# optic
	parts.sight = _optic(root, b, String(att.get("optic", "iron")))
	_signature_details(root, model, b)
	return parts


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


## Copies every mesh of a glb into `r` (in weapon space), except names that
## contain `skip`. Returns {mesh name: [mesh, transform]} for the skipped ones.
static func _glb_meshes(r: Node3D, path: String, conv: Basis, skip: String = "") -> Dictionary:
	var held := {}
	if not ResourceLoader.exists(path):
		return held
	var inst := (load(path) as PackedScene).instantiate()
	var list: Array = []
	_glb_walk(inst, Transform3D.IDENTITY, list)
	inst.free()
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
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.073, -0.27)),
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
	var inst := (load(MARLIN_GLB) as PackedScene).instantiate()
	var list: Array = []
	_glb_walk(inst, Transform3D.IDENTITY, list)
	inst.free()
	# Body stays on the gun; Bolt and Lever each get a pivot node the rig moves
	var lever: Node3D = null
	var bolt: Node3D = null
	for e in list:
		var part := String(e[0])
		var xf: Transform3D = e[2]
		var mi := MeshInstance3D.new()
		mi.mesh = e[1]
		mi.set_meta("pack4", true)   # skins recolour these too
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
		"rail_adapter": true,
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
			"muzzle": Vector2(3.944, 0.214), "eject": Vector2(-1.5, 0.2), "charge": Vector2(0.95, 0.3), "under": Vector2(2.3, 0.0), "rail_adapter": true,
			"sight": Vector2(-1.43, 0.92), "relief": 0.06},
	"hk33": {"hex": [-0.46, -0.15], "length": 0.93, "grip": Vector2(-1.834, -0.26), "support": Vector2(0.5, 0.12), "mag": Vector2(-0.08, 0.1),
			"muzzle": Vector2(4.472, 0.378), "eject": Vector2(-0.6, 0.5), "charge": Vector2(1.9, 0.65), "under": Vector2(1.4, 0.07), "rail_adapter": true,
			"sight": Vector2(-1.897, 0.95)},
	"uar10": {"hex": [-0.58, -0.27], "length": 1.03, "grip": Vector2(-1.902, -0.5), "support": Vector2(1.5, -0.04), "mag": Vector2(-0.4, -0.1),
			"muzzle": Vector2(5.356, 0.227), "eject": Vector2(-1.0, 0.25), "charge": Vector2(-2.1, 0.49), "under": Vector2(2.1, -0.05), "rail_adapter": true,
			"sight": Vector2(-1.855, 0.964), "relief": 0.1},
	"as_val": {"length": 0.9, "grip": Vector2(-1.422, -0.426), "support": Vector2(0.8, 0.02), "mag": Vector2(0.14, -0.1),
			"muzzle": Vector2(4.375, 0.33), "eject": Vector2(-0.3, 0.3), "charge": Vector2(0.5, 0.35), "under": Vector2(0.9, 0.0), "snap_under": true,
			"sight": Vector2(1.708, 0.63), "rail": Vector2(-0.5, 0.624), "relief": 0.4},
	"gepard": {"length": 0.68, "grip": Vector2(0.114, -0.437), "support": Vector2(1.685, -0.16), "mag": Vector2(0.1, -0.3),
			"muzzle": Vector2(3.718, 0.21), "eject": Vector2(0.62, 0.35), "charge": Vector2(0.4, 0.4), "under": Vector2(1.9, -0.17), "snap_under": true,
			"sight": Vector2(0.253, 0.72), "rail": Vector2(-0.3, 0.53), "relief": 0.2},
	"p90": {"length": 0.5, "grip": Vector2(0.75, -0.74), "support": Vector2(1.55, -0.7), "mag": Vector2(0.47, 0.08),
			"muzzle": Vector2(2.6, -0.13), "eject": Vector2(0.4, -1.0), "charge": Vector2(1.2, -0.2), "under": Vector2(1.8, -0.75), "rail_adapter": true,
			"sight": Vector2(0.6, 0.83), "rail": Vector2(1.1, 0.82), "relief": 0.2},
	"scar_h": {"length": 0.91, "grip": Vector2(-1.75, -0.7), "support": Vector2(1.3, -0.05), "mag": Vector2(-0.34, -0.6),
			"muzzle": Vector2(4.81, 0.226), "eject": Vector2(-0.3, 0.45), "charge": Vector2(1.6, 0.4), "under": Vector2(2.0, -0.05), "rail_adapter": true,
			"sight": Vector2(-1.88, 0.98), "rail": Vector2(-0.6, 0.7)},
	"l96a1": {"length": 1.18, "grip": Vector2(-1.4, -0.65), "support": Vector2(2.0, -0.05), "mag": Vector2(0.0, -0.3),
			"muzzle": Vector2(6.855, 0.435), "eject": Vector2(0.0, 0.5), "charge": Vector2(-1.0, 0.45), "under": Vector2(3.5, -0.15), "rail_adapter": true,
			"sight": Vector2(-1.39, 0.95), "rail": Vector2(0.0, 0.7), "relief": 0.1},
	"mosin": {"length": 1.24, "grip": Vector2(-3.2, -0.05), "support": Vector2(0.2, 0.1), "mag": Vector2(-1.7, -0.3),
			"muzzle": Vector2(5.86, 0.6), "eject": Vector2(-1.5, 0.6), "charge": Vector2(-2.3, 0.45), "under": Vector2(2.5, 0.0), "rail_adapter": true,
			"sight": Vector2(0.05, 0.8), "rail": Vector2(-1.5, 0.75), "relief": 0.45},
	"g17": {"length": 0.2, "pistol": true, "grip": Vector2(-0.62, -0.08), "mag": Vector2(-0.5, 0.3),
			"muzzle": Vector2(1.17, 0.566), "eject": Vector2(0.2, 0.62), "charge": Vector2(-0.75, 0.55), "under": Vector2(0.524, 0.295),
			"sight": Vector2(-0.787, 0.69)},
	"vp9": {"length": 0.27, "pistol": true, "grip": Vector2(-0.823, -0.33), "mag": Vector2(-0.77, -0.15),
			"muzzle": Vector2(1.424, 0.0), "eject": Vector2(-0.6, 0.1), "charge": Vector2(-1.35, 0.0), "under": Vector2(0.3, -0.15),
			"sight": Vector2(-1.053, 0.19)},
}


## A source side-view point (x forward, z up, 10 cm units) in weapon space.
static func _lp(v: Vector2, g: Vector2, side: float = 0.0) -> Vector3:
	return Vector3(side, (v.y - g.y) * 0.1, -(v.x - g.x) * 0.1)


static func _low_poly(r: Node3D, model: String, handguard: String = "standard") -> Dictionary:
	var spec: Dictionary = LP_GUNS.get(model, {})
	var pistol := bool(spec.get("pistol", false))
	var path := LOW_POLY + model + ".glb"
	if spec.is_empty() or not ResourceLoader.exists(path):
		return _placeholder(r, float(spec.get("length", 0.8)), pistol)
	var inst := (load(path) as PackedScene).instantiate()
	var list: Array = []
	_glb_walk(inst, Transform3D.IDENTITY, list)
	inst.free()
	var mag: Array = []
	var bolt: Node3D = null
	for e in list:
		var part := String(e[0])
		if part.begins_with("Mag"):
			mag = [e[1], e[2]]
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = e[1]
		mi.transform = e[2]
		mi.set_meta("pack4", true)   # skins recolour these too
		_clear_glass(mi)
		if part.begins_with("Body") and handguard == "hex" and spec.has("hex"):
			mi.mesh = _without_handguard(model, e[1], e[2], spec)
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
	var under := _lp(spec.under, g)
	# every gun can take the rail now, so its mount sits on the model's real underside
	under.y = _bottom_at(r, under.z, under.y)
	var sight := _lp(spec.sight, g)
	var rail := _lp(spec.get("rail", spec.sight), g)
	var out := {
		"glb": true, "glb_mag": mag, "bolt": bolt, "pistol": pistol,
		"grip": _marker(r, "Grip", Vector3(0, -0.01, 0.0), Vector3(-0.25 if pistol else -0.3, 0, 0)),
		"charge": _marker(r, "Charge", _lp(spec.charge, g)),
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
	return out


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
## The PEQ-2 is drawn at this scale (full size swamps slim handguards like the
## AS VAL's), and where its beam leaves it, from its mount (it hangs under the handguard).
const LP_LASER_SCALE := 0.6
## The rail adapter's depth: an underbarrel part hangs this far below the gun.
const LP_RAIL_DROP := 0.0126
const LP_LASER_AT := Vector3(0, -0.053, -0.051) * LP_LASER_SCALE
## Rail and laser are drawn smaller still on a pistol's short dust cover.
const LP_PISTOL_UNDER_SCALE := 0.6


## The attachment model `name` under `at`, or null when its file is missing.
static func _att_model(at: Node3D, name: String) -> Node3D:
	var path := LP_ATT + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var inst := (load(path) as PackedScene).instantiate()
	var list: Array = []
	_glb_walk(inst, Transform3D.IDENTITY, list)
	inst.free()
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
## sight glass, so aiming down the sights is not blocked.
static func _clear_glass(mi: MeshInstance3D) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m != null:
			var n := m.resource_name.to_lower()
			if n.contains("glass") or n.contains("lens"):
				mi.set_surface_override_material(s, _glass)


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


static func _underbarrel(at: Node3D, kind: String, small: float = 1.0) -> Dictionary:
	if kind == "gp25":
		var g := _att_model(at, "gp25")
		if g != null:
			return {"launcher": _marker(at, "Launcher", _bore_front(g))}
		return {"launcher": _marker(at, "Launcher", Vector3(0, -0.045, -0.16))}
	if kind == "laser":
		var m := _att_model(at, "laser")
		if m != null:
			m.scale = Vector3.ONE * LP_LASER_SCALE * small
			return {"laser": _marker(at, "Laser", LP_LASER_AT * small)}
	return {}


## The optic on the rail, or the gun's own sights.
static func _optic(r: Node3D, b: Dictionary, kind: String) -> Dictionary:
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
			var y := float(b.rail_y) + (c.y if c != Vector3.INF else float(o[0]))
			var rear := float(b.rail_z) + (c.z + 0.02 if c != Vector3.INF else float(o[1]))
			return {"y": y, "rear_z": rear, "relief": float(o[2])}
		mount.free()
	return {"y": float(b.iron_y), "rear_z": float(b.iron_rear_z), "relief": float(b.get("iron_relief", 0.16))}


## Lowest point of the gun's underside at `z` along the centreline (where a
## rail adapter clamps), from the parts built so far; `fallback` if nothing is there.
static func _bottom_at(r: Node3D, z: float, fallback: float) -> float:
	var best := INF
	for n in r.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != r:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := xf * faces[i]
			var c := xf * faces[i + 1]
			var d := xf * faces[i + 2]
			if minf(a.z, minf(c.z, d.z)) > z or maxf(a.z, maxf(c.z, d.z)) < z:
				continue
			# exact: where a vertical line up the centreline at `z` crosses this face
			var hit = Geometry3D.ray_intersects_triangle(Vector3(0, -1.0, z), Vector3.UP, a, c, d)
			if hit != null:
				best = minf(best, (hit as Vector3).y)
	return best if best < INF else fallback


## Centre of an optic model's glowing reticle, in its holder's space (INF if none).
static func _reticle_centre(holder: Node3D) -> Vector3:
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
