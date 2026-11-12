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
	_poly = poly
	_worn = M.solid(Color(0.29, 0.31, 0.34), 0.27, 0.9)
	var g := StandardMaterial3D.new()
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.45, 0.75, 0.9, 0.12)
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
		"m4":
			b = _m4(root)
		"akm":
			b = _ak(root)
		"as_val":
			b = _val(root)
		"mp7":
			b = _mp7(root)
		"awp":
			b = _awp(root)
		"m870":
			b = _m870(root)
		"m249":
			b = _m249(root)
		"g18":
			b = _pistol(root, M.solid(Color(0.13, 0.12, 0.1), 0.7), true)
		"mgp7":
			b = _mgp7(root)
		"zc57":
			b = _zc57(root)
		_:
			b = _pistol(root, _poly, false)

	var parts := {"root": root, "grip": b.grip, "support": b.support, "charge": b.charge, "eject": b.eject,
			"pump": b.get("pump"), "bolt": b.get("bolt"), "laser": null}
	# magazine
	var mag_at: Node3D = b.mag_at
	if b.has("glb_mag"):
		parts.mag = _glb_mag(mag_at, b.glb_mag, String(att.get("magazine", "standard")))
	else:
		parts.mag = _magazine(mag_at, String(b.mag_style), String(att.get("magazine", "standard")))
	parts.mag_well = _marker(mag_at, "MagWell", Vector3(0, -0.05, 0))
	# stock
	if String(b.stock_style) != "":
		_stock(b.stock_at, String(b.stock_style), String(att.get("stock", "standard")))
	# muzzle device
	var mz := String(att.get("muzzle", "none"))
	if mz == "suppressor" and b.has("glb_suppressor") and _glb_suppressor(b.muzzle_at, String(b.glb_suppressor)):
		parts.muzzle = _marker(b.muzzle_at, "Muzzle", Vector3(0, 0, -float(b.glb_suppressor_len)))
	else:
		parts.muzzle = _muzzle(b.muzzle_at, mz, b.get("pistol", false))
	# underbarrel
	var ub := _underbarrel(b.under_at, String(att.get("underbarrel", "none")))
	if ub.has("support"):
		parts.support = ub.support
	if ub.has("laser"):
		parts.laser = ub.laser
	# optic
	parts.sight = _optic(root, b, String(att.get("optic", "iron")))
	if not b.get("glb", false):
		_details(root, b)
	_signature_details(root, model, b)
	return parts


## Shared surface detail from each gun's own markers: ejection port + bolt,
## receiver pins, trigger, selector, handguard vents, charging handle, mag-well
## flare (pistols: slide serrations, port, trigger, slide stop).
static func _details(r: Node3D, b: Dictionary) -> void:
	var dark := M.solid(Color(0.025, 0.027, 0.03), 0.5, 0.4)
	var e: Vector3 = (b.eject as Node3D).position
	var g: Vector3 = (b.grip as Node3D).position
	if b.get("pistol", false):
		for i in 6:
			for sx in [-1, 1]:
				_part(r, WG.machined(Vector3(0.002, 0.026, 0.0035)), dark, Vector3(sx * 0.0154, 0.061, 0.012 - i * 0.0075))
		_part(r, WG.machined(Vector3(0.0025, 0.013, 0.034)), dark, Vector3(0.0152, 0.068, e.z))
		_part(r, WG.machined(Vector3(0.002, 0.008, 0.02)), _worn, Vector3(0.0158, 0.068, e.z + 0.004))
		_part(r, WG.machined(Vector3(0.005, 0.02, 0.006)), _worn, Vector3(0, 0.006, -0.033), Vector3(0.4, 0, 0))
		_part(r, WG.machined(Vector3(0.003, 0.006, 0.028)), _worn, Vector3(-0.0152, 0.044, -0.055))
		for i in 3:
			_part(r, WG.machined(Vector3(0.022, 0.004, 0.006)), dark, Vector3(0, 0.0185, -0.105 - i * 0.012))
		return
	var hw := 0.0236
	var hg: float = float(b.get("hg_w", 0.0296))
	# ejection port with the bolt carrier showing
	_part(r, WG.machined(Vector3(0.003, 0.022, 0.062)), dark, Vector3(hw, e.y, e.z))
	_part(r, WG.machined(Vector3(0.0025, 0.012, 0.036)), _worn, Vector3(hw + 0.0008, e.y, e.z + 0.009))
	# take-down pins through the receiver
	for dz in [-0.075, 0.05]:
		_part(r, ML.cylinder(0.0042, 0.0042, hw * 2.0 + 0.005, 10), _worn, Vector3(0, e.y - 0.036, e.z + dz), Z90)
	# trigger and fire selector
	_part(r, WG.machined(Vector3(0.005, 0.024, 0.007)), _worn, Vector3(0, g.y + 0.012, g.z - 0.05), Vector3(0.38, 0, 0))
	_part(r, WG.machined(Vector3(0.004, 0.007, 0.03)), _worn, Vector3(-hw - 0.001, g.y + 0.058, g.z - 0.004), Vector3(0.5, 0, 0))
	# handguard vent slots
	var sp: Vector3 = (b.support as Node3D).position
	for k in 5:
		for sx in [-1, 1]:
			_part(r, WG.machined(Vector3(0.002, 0.011, 0.027)), dark, Vector3(sx * hg, sp.y + 0.03, sp.z - 0.09 + k * 0.045))
	# charging handle
	_part(r, WG.machined(Vector3(0.016, 0.01, 0.018)), _worn, (b.charge as Node3D).position)
	# flared magazine well
	_part(b.mag_at, WG.machined(Vector3(0.037, 0.014, 0.076)), _black, Vector3.ZERO)


## Weapon-specific construction details visible during inspection. Keep geometry
## on the correct moving parent (pump, bolt, magazine), never on the hands.
static func _signature_details(r: Node3D, model: String, b: Dictionary) -> void:
	var dark := M.solid(Color(0.025, 0.029, 0.032), 0.7, 0.2)
	match model:
		"m4":
			_part(r, ML.cylinder(0.009, 0.009, 0.035, 16), _black, Vector3(0.027, 0.065, 0.018), Vector3(0, 0, -0.6))
			_part(r, WG.machined(Vector3(0.008, 0.023, 0.055)), _black, Vector3(0.027, 0.049, -0.072), Vector3(0.12, 0, 0))
			for sx in [-1, 1]:
				for i in 5:
					_part(r, WG.machined(Vector3(0.002, 0.008, 0.024)), dark, Vector3(sx * 0.0305, 0.073, -0.245 - i * 0.043))
			_part(r, ML.cylinder(0.017, 0.017, 0.015, 24), _worn, Vector3(0, 0.072, -0.477), X90)
		"akm":
			# Stamped selector, rivet heads and gas-block collar.
			_part(r, WG.machined(Vector3(0.004, 0.011, 0.1)), _black, Vector3(0.025, 0.059, -0.035), Vector3(-0.12, 0, 0))
			for z in [-0.185, -0.155, 0.018]:
				_part(r, ML.cylinder(0.0034, 0.0034, 0.05, 10), _worn, Vector3(0, 0.035, z), Z90)
			_part(r, ML.cylinder(0.018, 0.018, 0.03, 24), _black, Vector3(0, 0.068, -0.445), X90)
			_part(r, WG.machined(Vector3(0.012, 0.026, 0.035)), _black, Vector3(0, 0.082, -0.446))
		"as_val":
			for z in [-0.37, -0.56]:
				_part(r, _ring(0.024, 0.0265), _black, Vector3(0, 0.062, z), X90)
			_part(r, WG.machined(Vector3(0.049, 0.008, 0.21)), dark, Vector3(0, 0.096, -0.07))
			_part(r, ML.cylinder(0.012, 0.012, 0.054, 16), _worn, Vector3(0, 0.058, 0.071), Z90)
		"mp7":
			for sx in [-1, 1]:
				_part(r, WG.machined(Vector3(0.004, 0.024, 0.092)), _black, Vector3(sx * 0.025, 0.049, -0.157))
				_part(r, WG.machined(Vector3(0.004, 0.008, 0.022)), _worn, Vector3(sx * 0.025, 0.039, -0.016), Vector3(-0.35, 0, 0))
			_part(r, WG.machined(Vector3(0.043, 0.008, 0.025)), _black, Vector3(0, 0.097, 0.042))
		"awp":
			for sx in [-1, 1]:
				_part(r, WG.machined(Vector3(0.003, 0.025, 0.17)), _poly, Vector3(sx * 0.032, 0.024, -0.275))
				for z in [-0.2, -0.35]:
					_part(r, ML.cylinder(0.004, 0.004, 0.004, 12), _worn, Vector3(sx * 0.034, 0.024, z), Z90)
			_part(r, ML.cylinder(0.021, 0.021, 0.035, 24), _black, Vector3(0, 0.07, -0.217), X90)
		"m870":
			# Side saddle, brass shell heads, and action bars connected to pump.
			_part(r, WG.machined(Vector3(0.008, 0.05, 0.12)), _poly, Vector3(-0.031, 0.06, -0.045))
			for i in 4:
				_part(r, ML.cylinder(0.007, 0.007, 0.037, 16), M.solid(Color(0.32, 0.055, 0.03), 0.5), Vector3(-0.041, 0.058, -0.09 + i * 0.028))
				_part(r, ML.cylinder(0.0075, 0.0075, 0.007, 16), M.solid(Color(0.5, 0.36, 0.13), 0.3, 0.8), Vector3(-0.041, 0.08, -0.09 + i * 0.028))
			for sx in [-1, 1]:
				_part(b.pump, WG.machined(Vector3(0.005, 0.008, 0.18)), _worn, Vector3(sx * 0.018, 0.005, 0.12))
		"m249":
			_part(r, WG.machined(Vector3(0.074, 0.008, 0.2)), _black, Vector3(0, 0.119, -0.025))
			_part(r, ML.cylinder(0.009, 0.009, 0.078, 16), _worn, Vector3(0, 0.108, -0.14), Z90)
			for sx in [-1, 1]:
				_part(r, ML.cylinder(0.006, 0.006, 0.19, 16), _black, Vector3(sx * 0.025, 0.023, -0.495), X90)
				_part(r, WG.machined(Vector3(0.023, 0.012, 0.025)), _poly, Vector3(sx * 0.025, 0.023, -0.59))
		"pistol", "g18":
			_part(r, WG.machined(Vector3(0.008, 0.028, 0.008)), _poly, Vector3(0, 0.014, -0.056), Vector3(-0.15, 0, 0))
			_part(r, WG.machined(Vector3(0.032, 0.009, 0.025)), _poly, Vector3(0, 0.026, 0.025))
			for sx in [-1, 1]:
				_part(r, WG.machined(Vector3(0.002, 0.06, 0.029)), dark, Vector3(sx * 0.0158, -0.02, 0.004), Vector3(-0.25, 0, 0))
			if model == "g18":
				for i in 3:
					_part(r, WG.machined(Vector3(0.014, 0.001, 0.007)), dark, Vector3(0, 0.0795, -0.11 - i * 0.015))
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


static func _rail(r: Node3D, y: float, z: float, length: float) -> void:
	_part(r, WG.machined(Vector3(0.026, 0.012, length)), _black, Vector3(0, y - 0.006, z))
	var n := int(length / 0.03)
	for i in n:
		_part(r, WG.machined(Vector3(0.03, 0.005, 0.012)), _black, Vector3(0, y - 0.001, z - length * 0.5 + 0.015 + i * 0.03))


static func _grip(r: Node3D, mat: Material, tilt: float = -0.3) -> void:
	_part(r, WG.machined(Vector3(0.032, 0.105, 0.045)), mat, Vector3(0, -0.035, 0.018), Vector3(tilt, 0, 0))
	_part(r, WG.machined(Vector3(0.008, 0.008, 0.07)), _black, Vector3(0, -0.005, -0.035))
	_part(r, WG.machined(Vector3(0.008, 0.035, 0.008)), _black, Vector3(0, 0.01, -0.07))


# ====================================================================== base guns

static func _m4(r: Node3D) -> Dictionary:
	_body(r, 0.046, [Vector2(0.05, 0.06), Vector2(-0.15, 0.06), Vector2(-0.16, 0.0), Vector2(-0.095, -0.012), Vector2(-0.065, 0.018), Vector2(0.03, 0.018)], _black)
	_part(r, WG.machined(Vector3(0.046, 0.05, 0.26)), _black, Vector3(0, 0.075, -0.08))
	_rail(r, 0.112, -0.13, 0.36)
	_part(r, WG.machined(Vector3(0.056, 0.056, 0.26)), _black, Vector3(0, 0.072, -0.34))
	for sx in [-1, 1]:
		_part(r, WG.machined(Vector3(0.004, 0.024, 0.23)), _poly, Vector3(sx * 0.028, 0.065, -0.34))
	_part(r, ML.cylinder(0.011, 0.011, 0.14, 18), _black, Vector3(0, 0.072, -0.53), X90)
	_part(r, WG.machined(Vector3(0.012, 0.03, 0.02)), _black, Vector3(0.026, 0.06, -0.02))
	_grip(r, _poly)
	return {
		"grip": _marker(r, "Grip", Vector3(0, -0.02, 0.012), Vector3(-0.3, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.035, -0.34), Vector3(0, 0, -0.5)),
		"charge": _marker(r, "Charge", Vector3(0.0, 0.09, 0.07)),
		"eject": _marker(r, "Eject", Vector3(0.03, 0.075, -0.05)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.072, -0.6)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.044, -0.36)),
		"mag_at": _marker(r, "MagAt", Vector3(0, 0.0, -0.11), Vector3(0.12, 0, 0)),
		"mag_style": "stanag",
		"hg_w": 0.0338,
		"stock_at": _marker(r, "StockAt", Vector3(0, 0.07, 0.07)),
		"stock_style": "polymer",
		"rail_y": 0.118, "rail_z": -0.08, "iron_front_z": -0.44, "iron_rear_z": 0.04,
	}


static func _ak(r: Node3D) -> Dictionary:
	var wood := M.wood("ak_wood", Color(0.42, 0.22, 0.1))
	_part(r, WG.machined(Vector3(0.046, 0.068, 0.3)), _black, Vector3(0, 0.052, -0.08))
	_part(r, ML.cylinder(0.022, 0.022, 0.26, 18), _black, Vector3(0, 0.084, -0.08), X90)
	_part(r, ML.cylinder(0.011, 0.011, 0.42, 18), _black, Vector3(0, 0.058, -0.43), X90)
	_part(r, WG.machined(Vector3(0.012, 0.035, 0.012)), _black, Vector3(0, 0.085, -0.6))
	_part(r, WG.machined(Vector3(0.02, 0.02, 0.03)), _black, Vector3(0, 0.1, -0.21))
	_part(r, ML.cylinder(0.013, 0.013, 0.22, 18), _black, Vector3(0, 0.088, -0.33), X90)
	_part(r, WG.machined(Vector3(0.056, 0.05, 0.2)), wood, Vector3(0, 0.05, -0.31))
	_part(r, WG.machined(Vector3(0.046, 0.026, 0.17)), wood, Vector3(0, 0.09, -0.32))
	_part(r, WG.machined(Vector3(0.032, 0.1, 0.045)), wood, Vector3(0, -0.035, 0.018), Vector3(-0.28, 0, 0))
	_part(r, WG.machined(Vector3(0.008, 0.008, 0.07)), _black, Vector3(0, -0.005, -0.035))
	_part(r, WG.machined(Vector3(0.028, 0.012, 0.03)), _black, Vector3(0.032, 0.06, -0.1))
	# side-rail optic mount
	_part(r, WG.machined(Vector3(0.03, 0.01, 0.16)), _black, Vector3(0, 0.103, -0.06))
	return {
		"grip": _marker(r, "Grip", Vector3(0, -0.02, 0.012), Vector3(-0.28, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.02, -0.3), Vector3(0, 0, -0.5)),
		"charge": _marker(r, "Charge", Vector3(0.045, 0.06, -0.1)),
		"eject": _marker(r, "Eject", Vector3(0.03, 0.07, -0.06)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.058, -0.64)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.025, -0.32)),
		"mag_at": _marker(r, "MagAt", Vector3(0, 0.0, -0.13), Vector3(0.15, 0, 0)),
		"mag_style": "ak",
		"stock_at": _marker(r, "StockAt", Vector3(0, 0.05, 0.07), Vector3(-0.1, 0, 0)),
		"stock_style": "wood",
		"rail_y": 0.108, "rail_z": -0.06, "iron_builtin": true, "iron_y": 0.105, "iron_rear_z": -0.2, "iron_relief": 0.3,
	}


static func _val(r: Node3D) -> Dictionary:
	_part(r, WG.machined(Vector3(0.046, 0.072, 0.3)), _black, Vector3(0, 0.058, -0.07))
	_part(r, WG.machined(Vector3(0.036, 0.018, 0.27)), _worn, Vector3(0, 0.102, -0.07))
	_rail(r, 0.117, -0.06, 0.24)
	_part(r, ML.cylinder(0.025, 0.025, 0.42, 16), _poly, Vector3(0, 0.062, -0.43), X90)
	_part(r, ML.cylinder(0.026, 0.026, 0.02, 16), _worn, Vector3(0, 0.062, -0.23), X90)
	_part(r, ML.cylinder(0.024, 0.026, 0.02, 16), _worn, Vector3(0, 0.062, -0.645), X90)
	_part(r, WG.machined(Vector3(0.054, 0.05, 0.15)), _poly, Vector3(0, 0.035, -0.28))
	_part(r, WG.machined(Vector3(0.03, 0.012, 0.012)), _black, Vector3(0.03, 0.07, -0.12))
	_grip(r, _poly)
	return {
		"grip": _marker(r, "Grip", Vector3(0, -0.02, 0.012), Vector3(-0.3, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.02, -0.29), Vector3(0, 0, -0.5)),
		"charge": _marker(r, "Charge", Vector3(0.04, 0.07, -0.12)),
		"eject": _marker(r, "Eject", Vector3(0.03, 0.07, -0.06)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.062, -0.66)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.01, -0.28)),
		"mag_at": _marker(r, "MagAt", Vector3(0, 0.0, -0.125), Vector3(0.22, 0, 0)),
		"mag_style": "stanag",
		"stock_at": _marker(r, "StockAt", Vector3(0, 0.06, 0.08)),
		"stock_style": "skeletal",
		"rail_y": 0.123, "rail_z": -0.06, "iron_front_z": -0.3, "iron_rear_z": 0.02,
	}


static func _mp7(r: Node3D) -> Dictionary:
	_body(r, 0.048, [Vector2(0.05, 0.098), Vector2(-0.195, 0.098), Vector2(-0.218, 0.065), Vector2(-0.19, 0.026), Vector2(-0.09, 0.022), Vector2(-0.05, 0.006), Vector2(0.038, 0.022)], _poly)
	_part(r, WG.machined(Vector3(0.05, 0.03, 0.1)), _black, Vector3(0, 0.04, -0.19))
	_rail(r, 0.104, -0.08, 0.22)
	_part(r, ML.cylinder(0.009, 0.009, 0.08, 18), _black, Vector3(0, 0.06, -0.25), X90)
	_part(r, WG.machined(Vector3(0.034, 0.11, 0.045)), _poly, Vector3(0, -0.035, 0.0), Vector3(-0.2, 0, 0))
	_part(r, WG.machined(Vector3(0.008, 0.008, 0.06)), _black, Vector3(0, -0.005, -0.045))
	return {
		"grip": _marker(r, "Grip", Vector3(0, -0.02, 0.0), Vector3(-0.2, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.02, -0.18), Vector3(0, 0, -0.5)),
		"charge": _marker(r, "Charge", Vector3(0.0, 0.1, 0.04)),
		"eject": _marker(r, "Eject", Vector3(0.03, 0.07, -0.06)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.06, -0.29)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.022, -0.18)),
		"mag_at": _marker(r, "MagAt", Vector3(0, -0.03, 0.005), Vector3(-0.2, 0, 0)),
		"mag_style": "smg",
		"stock_at": _marker(r, "StockAt", Vector3(0, 0.06, 0.05)),
		"stock_style": "rods",
		"rail_y": 0.11, "rail_z": -0.07, "iron_front_z": -0.17, "iron_rear_z": 0.02,
	}


static func _awp(r: Node3D) -> Dictionary:
	var green := M.solid(Color(0.24, 0.3, 0.2), 0.75)
	_part(r, WG.machined(Vector3(0.046, 0.06, 0.26)), _black, Vector3(0, 0.07, -0.08))
	_body(r, 0.062, [Vector2(-0.06, 0.062), Vector2(-0.41, 0.062), Vector2(-0.43, 0.028), Vector2(-0.39, -0.006), Vector2(-0.16, -0.012), Vector2(-0.065, 0.005)], green)
	_part(r, ML.cylinder(0.015, 0.013, 0.6, 14), _black, Vector3(0, 0.07, -0.5), X90)
	_rail(r, 0.106, -0.08, 0.2)
	_part(r, WG.machined(Vector3(0.034, 0.1, 0.045)), green, Vector3(0, -0.035, 0.018), Vector3(-0.3, 0, 0))
	_part(r, WG.machined(Vector3(0.008, 0.008, 0.07)), _black, Vector3(0, -0.005, -0.035))
	var bolt := _marker(r, "Bolt", Vector3(0.0, 0.0, 0.0))
	_part(bolt, ML.cylinder(0.005, 0.005, 0.05, 18), _black, Vector3(0.035, 0.075, 0.0), Z90)
	_part(bolt, ML.sphere(0.011, false, 8), _black, Vector3(0.062, 0.075, 0.0))
	return {
		"grip": _marker(r, "Grip", Vector3(0, -0.02, 0.012), Vector3(-0.3, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.0, -0.3), Vector3(0, 0, -0.5)),
		"charge": _marker(bolt, "Charge", Vector3(0.062, 0.075, 0.0)),
		"eject": _marker(r, "Eject", Vector3(0.03, 0.08, -0.06)),
		"bolt": bolt,
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.07, -0.8)),
		"under_at": _marker(r, "UnderAt", Vector3(0, -0.015, -0.36)),
		"mag_at": _marker(r, "MagAt", Vector3(0, -0.01, -0.12)),
		"mag_style": "sniper",
		"stock_at": _marker(r, "StockAt", Vector3(0, 0.05, 0.06)),
		"stock_style": "chassis",
		"rail_y": 0.112, "rail_z": -0.07, "iron_front_z": -0.72, "iron_rear_z": -0.02,
	}


static func _m870(r: Node3D) -> Dictionary:
	_body(r, 0.05, [Vector2(0.06, 0.075), Vector2(0.035, 0.095), Vector2(-0.15, 0.095), Vector2(-0.16, 0.075), Vector2(-0.16, 0.025), Vector2(0.025, 0.025)], _black)
	_part(r, ML.cylinder(0.013, 0.013, 0.5, 18), _black, Vector3(0, 0.085, -0.41), X90)
	_part(r, ML.cylinder(0.013, 0.013, 0.4, 18), _black, Vector3(0, 0.048, -0.36), X90)
	_part(r, WG.machined(Vector3(0.006, 0.008, 0.006)), _worn, Vector3(0, 0.1, -0.64))
	_rail(r, 0.1, -0.05, 0.14)
	_grip(r, _poly, -0.35)
	var pump := _marker(r, "Pump", Vector3(0, 0.045, -0.33))
	_part(pump, WG.machined(Vector3(0.05, 0.045, 0.16)), _poly, Vector3.ZERO)
	for i in 5:
		_part(pump, WG.machined(Vector3(0.054, 0.004, 0.008)), _black, Vector3(0, -0.01, -0.06 + i * 0.03))
	return {
		"grip": _marker(r, "Grip", Vector3(0, -0.02, 0.012), Vector3(-0.35, 0, 0)),
		"support": _marker(pump, "Support", Vector3(-0.005, -0.012, 0.0), Vector3(0, 0, -0.5)),
		"charge": _marker(pump, "Charge", Vector3(0.0, -0.02, 0.0)),
		"eject": _marker(r, "Eject", Vector3(0.03, 0.07, -0.06)),
		"pump": pump,
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.085, -0.66)),
		"under_at": _marker(pump, "UnderAt", Vector3(0, -0.022, 0.0)),
		"mag_at": _marker(r, "MagAt", Vector3(0, 0.02, -0.06)),
		"mag_style": "shell",
		"stock_at": _marker(r, "StockAt", Vector3(0, 0.05, 0.06), Vector3(-0.12, 0, 0)),
		"stock_style": "polymer",
		"rail_y": 0.106, "rail_z": -0.05, "iron_front_z": -0.63, "iron_rear_z": 0.0,
	}


static func _m249(r: Node3D) -> Dictionary:
	_body(r, 0.07, [Vector2(0.1, 0.11), Vector2(-0.195, 0.11), Vector2(-0.22, 0.085), Vector2(-0.22, 0.028), Vector2(-0.17, 0.01), Vector2(0.065, 0.01), Vector2(0.1, 0.035)], _black)
	_part(r, WG.machined(Vector3(0.072, 0.02, 0.18)), _worn, Vector3(0, 0.115, -0.02))
	_part(r, ML.cylinder(0.015, 0.015, 0.45, 14), _black, Vector3(0, 0.07, -0.44), X90)
	_part(r, WG.machined(Vector3(0.06, 0.06, 0.18)), _poly, Vector3(0, 0.045, -0.29))
	_part(r, WG.machined(Vector3(0.012, 0.05, 0.1)), _black, Vector3(0, 0.12, -0.42))
	_part(r, WG.machined(Vector3(0.012, 0.012, 0.12)), _black, Vector3(0, 0.15, -0.42))
	_rail(r, 0.13, -0.05, 0.16)
	_grip(r, _poly)
	return {
		"grip": _marker(r, "Grip", Vector3(0, -0.02, 0.012), Vector3(-0.3, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.02, -0.29), Vector3(0, 0, -0.5)),
		"charge": _marker(r, "Charge", Vector3(0.04, 0.08, -0.12)),
		"eject": _marker(r, "Eject", Vector3(0.04, 0.06, -0.06)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.07, -0.67)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.014, -0.3)),
		"mag_at": _marker(r, "MagAt", Vector3(-0.07, 0.0, -0.06)),
		"mag_style": "box",
		"stock_at": _marker(r, "StockAt", Vector3(0, 0.06, 0.1)),
		"stock_style": "lmg",
		"rail_y": 0.136, "rail_z": -0.05, "iron_front_z": -0.55, "iron_rear_z": 0.04,
	}


static func _pistol(r: Node3D, frame: Material, auto: bool) -> Dictionary:
	_body(r, 0.03 if auto else 0.034, [Vector2(0.02, 0.043), Vector2(0.02, 0.069), Vector2(0.01, 0.079), Vector2(-0.16, 0.079), Vector2(-0.18, 0.067), Vector2(-0.18, 0.043)], _black)
	_part(r, WG.machined(Vector3(0.028, 0.026, 0.17)), frame, Vector3(0, 0.032, -0.07))
	_part(r, WG.machined(Vector3(0.03, 0.11, 0.048)), frame, Vector3(0, -0.02, 0.005), Vector3(-0.25, 0, 0))
	_part(r, WG.machined(Vector3(0.008, 0.008, 0.05)), frame, Vector3(0, 0.005, -0.03))
	if auto:
		_part(r, WG.machined(Vector3(0.006, 0.01, 0.012)), _worn, Vector3(-0.017, 0.06, 0.0))
	for sx in [-1, 1]:
		_part(r, WG.machined(Vector3(0.008, 0.012, 0.008)), _black, Vector3(sx * 0.009, 0.083, 0.01))
	_part(r, WG.machined(Vector3(0.004, 0.012, 0.006)), _black, Vector3(0, 0.083, -0.17))
	_part(r, ML.sphere(0.0013, false, 6), M.emissive("tritium", Color(0.4, 1.0, 0.4), 4.0), Vector3(0, 0.087, -0.1735))
	return {
		"pistol": true,
		"grip": _marker(r, "Grip", Vector3(0, -0.01, 0.01), Vector3(-0.25, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.03, -0.025, 0.0), Vector3(-0.25, 0, -0.6)),
		"charge": _marker(r, "Charge", Vector3(0, 0.07, 0.01)),
		"eject": _marker(r, "Eject", Vector3(0.02, 0.07, -0.05)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.06, -0.18)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.017, -0.12)),
		"mag_at": _marker(r, "MagAt", Vector3(0, -0.035, 0.01), Vector3(-0.25, 0, 0)),
		"mag_style": "pistol",
		"stock_at": r,
		"stock_style": "",
		"rail_y": 0.077, "rail_z": -0.05, "iron_builtin": true, "iron_y": 0.089, "iron_rear_z": 0.01, "mini": true,
	}


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
		if skip != "" and String(e[0]).contains(skip):
			held[String(e[0])] = [e[1], xf]
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = e[1]
		mi.transform = xf
		mi.set_meta("pack4", true)   # skins recolour these too
		r.add_child(mi)
	return held


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
	elif kind == "fast":
		var bottom: float = (mi.transform * mi.mesh.get_aabb()).position.y
		_part(mag, WG.machined(Vector3(0.012, 0.035, 0.012)), M.solid(Color(0.9, 0.4, 0.1), 0.6), Vector3(0, bottom - 0.015, 0.0))
	return mag


static func _glb_suppressor(at: Node3D, file: String) -> bool:
	var path := PACK4 + file
	if not ResourceLoader.exists(path):
		return false
	_glb_meshes(at, path, Basis.from_euler(_Y90))
	return true


static func _mgp7(r: Node3D) -> Dictionary:
	var conv := Basis.from_euler(_Y90)
	var held := _glb_meshes(r, PACK4 + "MGP7/MGP7_Rigged.glb", conv, "_Mag_")
	var mag: Array = []
	for k in held:
		if not String(k).contains("Eject"):
			mag = held[k]
	_keep_eject(r, held)
	return {
		"glb": true, "glb_mag": mag,
		"glb_suppressor": "MGP7/MGP7 Attachments/MGP7_Attachment_SuppressorV1.glb", "glb_suppressor_len": 0.2,
		"grip": _marker(r, "Grip", Vector3(0, -0.015, 0.0), Vector3(-0.2, 0, 0)),
		"support": _marker(r, "Support", Vector3(-0.005, 0.055, -0.26), Vector3(0, 0, -0.5)),
		"charge": _marker(r, "Charge", Vector3(-0.02, 0.14, -0.23)),
		"eject": _marker(r, "Eject", Vector3(0.02, 0.13, -0.14)),
		"muzzle_at": _marker(r, "MuzzleAt", Vector3(0, 0.108, -0.41)),
		"under_at": _marker(r, "UnderAt", Vector3(0, 0.06, -0.27)),
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
	var mag: Array = []
	for k in held:
		if not String(k).contains("Eject"):
			mag = held[k]
	_keep_eject(r, held)
	return {
		"pistol": true, "glb": true, "glb_mag": mag,
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
		"rail_y": 0.07, "rail_z": -0.05, "mini": true,
		"iron_builtin": true, "iron_y": 0.082, "iron_rear_z": 0.005,
	}


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

static func _magazine(at: Node3D, style: String, kind: String) -> Node3D:
	var mag := Node3D.new()
	mag.name = "Mag"
	at.add_child(mag)
	var ext := 1.5 if kind == "extended" else 1.0
	var bottom := -0.1
	match style:
		"stanag":
			if kind == "drum":
				_part(mag, WG.machined(Vector3(0.03, 0.08, 0.06)), _poly, Vector3(0, -0.01, 0))
				for sx in [-1, 1]:
					_part(mag, ML.cylinder(0.055, 0.055, 0.045, 18), _poly, Vector3(sx * 0.04, -0.1, 0), Z90)
				bottom = -0.155
			else:
				var h := 0.15 * ext
				_body(mag, 0.028, [Vector2(-0.032, 0.03), Vector2(0.032, 0.03), Vector2(0.032, 0.03 - h * 0.5), Vector2(0.016, 0.03 - h), Vector2(-0.048, 0.03 - h), Vector2(-0.036, 0.03 - h * 0.5)], _poly)
				for sx in [-1, 1]:
					for z in [-0.021, 0.0, 0.02]:
						_part(mag, WG.machined(Vector3(0.002, h * 0.7, 0.004)), _black, Vector3(sx * 0.0148, 0.025 - h * 0.5, z - 0.005), Vector3(-0.08, 0, 0))
				_part(mag, WG.machined(Vector3(0.032, 0.012, 0.068)), _black, Vector3(0, 0.03 - h, -0.016))
				bottom = 0.03 - h
		"ak":
			if kind == "drum":
				_part(mag, WG.machined(Vector3(0.03, 0.06, 0.07)), _poly, Vector3(0, -0.005, 0))
				_part(mag, ML.cylinder(0.085, 0.085, 0.07, 22), _poly, Vector3(0, -0.11, -0.02), Z90)
				bottom = -0.195
			else:
				var h2 := 0.1 * ext
				bottom = -0.075 - h2
				_body(mag, 0.028, [Vector2(-0.035, 0.025), Vector2(0.035, 0.025), Vector2(0.031, -0.045), Vector2(0.015, -0.10), Vector2(-0.015, bottom), Vector2(-0.077, bottom + 0.017), Vector2(-0.052, -0.085), Vector2(-0.038, -0.035)], _black)
				for sx in [-1, 1]:
					for z in [-0.018, 0.003, 0.024]:
						_part(mag, WG.machined(Vector3(0.0025, 0.084, 0.004)), _poly, Vector3(sx * 0.015, -0.038, z - 0.005), Vector3(-0.1, 0, 0))
				_part(mag, WG.machined(Vector3(0.032, 0.009, 0.073)), _worn, Vector3(0, bottom + 0.003, -0.046), Vector3(-0.23, 0, 0))
		"smg":
			var h3 := 0.13 * ext
			_part(mag, WG.machined(Vector3(0.024, h3, 0.034)), _poly, Vector3(0, -0.02 - h3 * 0.5 + 0.06, 0))
			_part(mag, WG.machined(Vector3(0.028, 0.01, 0.038)), _black, Vector3(0, 0.04 - h3, 0))
			bottom = 0.04 - h3
		"sniper":
			var h4 := 0.065 * ext
			_part(mag, WG.machined(Vector3(0.032, h4, 0.085)), _black, Vector3(0, -h4 * 0.5 + 0.01, 0))
			bottom = 0.01 - h4
		"box":
			var h5 := 0.12 * ext
			_part(mag, WG.machined(Vector3(0.08, h5, 0.15)), M.solid(Color(0.25, 0.28, 0.2), 0.7), Vector3(0, -h5 * 0.5, 0))
			for i in 4:
				_part(mag, ML.cylinder(0.0045, 0.0045, 0.034, 12), M.solid(Color(0.55, 0.4, 0.15), 0.3, 0.9), Vector3(0.045 + i * 0.008, 0.012 + sin(i * 0.5) * 0.025, -0.025), X90)
				_part(mag, ML.cylinder(0.001, 0.0045, 0.014, 12), _worn, Vector3(0.045 + i * 0.008, 0.012 + sin(i * 0.5) * 0.025, -0.049), X90)
			bottom = -h5
		"shell":
			_part(mag, ML.cylinder(0.009, 0.009, 0.055, 20), M.solid(Color(0.45, 0.075, 0.045), 0.5), Vector3(0, -0.02, 0), X90)
			_part(mag, ML.cylinder(0.0095, 0.0095, 0.009, 20), M.solid(Color(0.55, 0.4, 0.15), 0.3, 0.9), Vector3(0, -0.02, 0.028), X90)
			bottom = -0.04
		"pistol":
			_part(mag, WG.machined(Vector3(0.024, 0.1, 0.038)), _poly, Vector3(0, 0.0, 0.0))
			if kind == "drum":
				_part(mag, ML.cylinder(0.045, 0.045, 0.035, 18), _poly, Vector3(0, -0.09, 0), Z90)
				bottom = -0.135
			elif kind == "extended":
				_part(mag, WG.machined(Vector3(0.026, 0.06, 0.04)), _poly, Vector3(0, -0.075, 0))
				bottom = -0.105
			else:
				_part(mag, WG.machined(Vector3(0.03, 0.012, 0.046)), _black, Vector3(0, -0.055, 0))
				bottom = -0.06
	if kind == "fast":
		var tab := M.solid(Color(0.25, 0.22, 0.16), 0.85)
		_part(mag, _ring(0.008, 0.013), tab, Vector3(0, bottom - 0.014, 0), Vector3(0, 0, PI * 0.5))
		_part(mag, WG.machined(Vector3(0.035, 0.008, 0.044)), tab, Vector3(0, bottom, 0))
	elif kind == "ap":
		_part(mag, WG.machined(Vector3(0.03, 0.009, 0.045)), M.solid(Color(0.45, 0.37, 0.18), 0.5, 0.3), Vector3(0, bottom + 0.018, 0))
	if kind == "drum":
		var radius := 0.085 if style == "ak" else (0.045 if style == "pistol" else 0.055)
		var cy := bottom + radius
		var cz := -0.02 if style == "ak" else 0.0
		var cx := 0.036 if style == "ak" else (0.019 if style == "pistol" else 0.064)
		for sx in [-1, 1]:
			_part(mag, _ring(radius * 0.82, radius * 0.9), _black, Vector3(sx * cx, cy, cz), Z90)
			_part(mag, ML.cylinder(radius * 0.28, radius * 0.28, 0.005, 20), _worn, Vector3(sx * cx, cy, cz), Z90)
	return mag


static func _stock(at: Node3D, style: String, kind: String) -> void:
	var mat: Material = _poly
	if style == "wood":
		mat = M.wood("ak_wood", Color(0.42, 0.22, 0.1))
	elif style == "chassis":
		mat = M.solid(Color(0.24, 0.3, 0.2), 0.75)
	var length := 0.26 if style != "rods" else 0.2
	if style == "chassis" or style == "lmg":
		length = 0.32
	match kind:
		"light":
			for y in [0.02, -0.05]:
				_part(at, WG.machined(Vector3(0.012, 0.012, length)), _black, Vector3(0, y, length * 0.5))
			_part(at, WG.machined(Vector3(0.03, 0.1, 0.018)), _poly, Vector3(0, -0.015, length))
		"heavy":
			_part(at, WG.machined(Vector3(0.046, 0.1, length)), mat, Vector3(0, -0.025, length * 0.5))
			_part(at, WG.machined(Vector3(0.03, 0.03, length * 0.5)), mat, Vector3(0, 0.035, length * 0.6))
			_part(at, WG.machined(Vector3(0.05, 0.13, 0.025)), M.solid(Color(0.04, 0.04, 0.04), 0.95), Vector3(0, -0.03, length))
		_:
			match style:
				"skeletal":
					_part(at, WG.machined(Vector3(0.018, 0.018, 0.24)), _black, Vector3(0, 0.015, 0.11))
					_part(at, WG.machined(Vector3(0.018, 0.018, 0.22)), _black, Vector3(0, -0.055, 0.1), Vector3(0.28, 0, 0))
					_part(at, WG.machined(Vector3(0.034, 0.12, 0.026)), _poly, Vector3(0, -0.025, 0.22))
				"rods":
					for sx in [-1, 1]:
						_part(at, WG.machined(Vector3(0.008, 0.008, 0.16)), _black, Vector3(sx * 0.018, 0.0, 0.08))
					_part(at, WG.machined(Vector3(0.05, 0.06, 0.02)), _poly, Vector3(0, -0.01, 0.16))
				"polymer":
					_part(at, ML.cylinder(0.014, 0.014, 0.18, 18), _black, Vector3(0, 0.0, 0.09), X90)
					_part(at, WG.machined(Vector3(0.042, 0.085, 0.13)), mat, Vector3(0, -0.02, 0.17))
					_part(at, WG.machined(Vector3(0.044, 0.12, 0.02)), M.solid(Color(0.04, 0.04, 0.04), 0.95), Vector3(0, -0.025, 0.24))
				_:
					_part(at, WG.machined(Vector3(0.042, 0.09, length)), mat, Vector3(0, -0.02, length * 0.5), Vector3(0.06, 0, 0))
					_part(at, WG.machined(Vector3(0.044, 0.12, 0.02)), M.solid(Color(0.04, 0.04, 0.04), 0.95), Vector3(0, -0.035, length))


## All muzzle devices have a recessed bore: no solid caps over the barrel.
static func _muzzle(at: Node3D, kind: String, pistol: bool) -> Node3D:
	var length := 0.0
	var bore := 0.0045 if pistol else 0.0055
	match kind:
		"suppressor":
			length = 0.13 if pistol else 0.18
			var rad := 0.016 if pistol else 0.022
			_part(at, _open_tube(rad, length), _black, Vector3(0, 0, -length * 0.5), X90)
			for z in [-0.012, -length + 0.012]:
				_part(at, _ring(rad - 0.0015, rad + 0.001), _worn, Vector3(0, 0, z), X90)
			_part(at, _ring(bore, rad), _black, Vector3(0, 0, -length), X90)
			for k in 6:
				var a := k * TAU / 6.0
				_part(at, WG.machined(Vector3(0.003, 0.003, length * 0.4)), _poly, Vector3(cos(a) * rad, sin(a) * rad, -length * 0.42), Vector3(0, 0, a))
		"compensator", "brake":
			length = 0.065 if kind == "brake" else 0.055
			var width := 0.04 if kind == "brake" else 0.028
			# Separate top/bottom bridge and port walls leave genuine side openings.
			for y in [-0.010, 0.010]:
				_part(at, WG.machined(Vector3(width, 0.006, length)), _black, Vector3(0, y, -length * 0.5))
			for z in [-0.005, -length * 0.48, -length + 0.005]:
				_part(at, _ring(bore, 0.013), _black, Vector3(0, 0, z), X90)
		"flash_hider":
			length = 0.055
			_part(at, _ring(bore, 0.013), _black, Vector3(0, 0, -0.006), X90)
			for k in 4:
				var a := k * PI * 0.5 + PI * 0.25
				_part(at, WG.machined(Vector3(0.005, 0.005, 0.043)), _black, Vector3(cos(a) * 0.01, sin(a) * 0.01, -0.032), Vector3(0, 0, a))
		"choke":
			length = 0.04
			bore = 0.010
			_part(at, _open_tube(0.014, length), _black, Vector3(0, 0, -length * 0.5), X90)
			_part(at, _ring(bore, 0.014), _worn, Vector3(0, 0, -length), X90)
			for i in 3:
				_part(at, _ring(0.0136, 0.0148), _worn, Vector3(0, 0, -0.023 - i * 0.005), X90)
		_:
			_part(at, _ring(bore, 0.009 if pistol else 0.012), _worn, Vector3(0, 0, -0.001), X90)
	# Dark chamber sits behind the rim, preserving depth from oblique views.
	_part(at, ML.cylinder(bore, bore, 0.001, 24), M.solid(Color(0.008, 0.009, 0.01), 1.0), Vector3(0, 0, -length + 0.004), X90)
	return _marker(at, "Muzzle", Vector3(0, 0, -length))


static func _underbarrel(at: Node3D, kind: String) -> Dictionary:
	if kind == "none":
		return {}
	_part(at, WG.machined(Vector3(0.031, 0.012, 0.045)), _black, Vector3(0, -0.006, 0))
	_part(at, ML.cylinder(0.004, 0.004, 0.036, 12), _worn, Vector3(0, -0.006, 0.01), Z90)
	match kind:
		"vgrip":
			_part(at, ML.cylinder(0.013, 0.017, 0.083, 24), _poly, Vector3(0, -0.054, 0))
			for i in 5:
				_part(at, _ring(0.013, 0.016), _poly, Vector3(0, -0.028 - i * 0.012, 0))
			_part(at, WG.machined(Vector3(0.034, 0.009, 0.034)), _black, Vector3(0, -0.098, 0))
			return {"support": _marker(at, "Support", Vector3(-0.01, -0.06, 0), Vector3(0, 0, -0.25))}
		"agrip":
			_body(at, 0.028, [Vector2(-0.045, -0.011), Vector2(0.04, -0.011), Vector2(0.04, -0.027), Vector2(0.015, -0.052), Vector2(-0.04, -0.027)], _poly)
			for i in 4:
				_part(at, WG.machined(Vector3(0.029, 0.004, 0.004)), _black, Vector3(0, -0.035 + i * 0.004, -0.018 - i * 0.009), Vector3(0.45, 0, 0))
			return {"support": _marker(at, "Support", Vector3(-0.01, -0.03, 0.01), Vector3(0.2, 0, -0.4))}
		"laser":
			_part(at, WG.machined(Vector3(0.032, 0.026, 0.062)), _black, Vector3(0, -0.021, 0))
			_part(at, ML.cylinder(0.008, 0.008, 0.01, 20), _poly, Vector3(0, -0.021, -0.035), X90)
			_part(at, ML.cylinder(0.005, 0.005, 0.001, 20), M.emissive("laser_lens", Color(1, 0.1, 0.05), 2.0), Vector3(0, -0.021, -0.041), X90)
			_part(at, WG.machined(Vector3(0.012, 0.003, 0.025)), _poly, Vector3(0, -0.035, 0.004))
			_part(at, ML.cylinder(0.004, 0.004, 0.003, 12), _worn, Vector3(0.018, -0.021, 0.0), Z90)
			return {"laser": _marker(at, "Laser", Vector3(0, -0.021, -0.043))}
		"bipod":
			for sx in [-1, 1]:
				_part(at, ML.cylinder(0.008, 0.008, 0.014, 16), _worn, Vector3(sx * 0.019, -0.019, 0), Z90)
				_part(at, ML.cylinder(0.006, 0.006, 0.17, 16), _black, Vector3(sx * 0.022, -0.025, -0.085), X90)
				_part(at, ML.cylinder(0.004, 0.004, 0.045, 16), _worn, Vector3(sx * 0.022, -0.025, -0.18), X90)
				_part(at, WG.machined(Vector3(0.022, 0.012, 0.016)), _poly, Vector3(sx * 0.022, -0.025, -0.204))
	return {}


static func _optic(r: Node3D, b: Dictionary, kind: String) -> Dictionary:
	var ry: float = b.rail_y
	var rz: float = b.rail_z
	var s := 0.75 if b.get("mini", false) else 1.0
	match kind:
		"reddot":
			_part(r, WG.machined(Vector3(0.026, 0.02, 0.06) * s), _black, Vector3(0, ry + 0.008 * s, rz))
			for z in [0.03, -0.04]:
				_part(r, _ring(0.0165 * s, 0.021 * s), _poly, Vector3(0, ry + 0.042 * s, rz + z * s), X90)
			for sx in [-1, 1]:
				_part(r, WG.machined(Vector3(0.004, 0.012, 0.07) * s), _poly, Vector3(sx * 0.019 * s, ry + 0.034 * s, rz - 0.005 * s))
			_part(r, ML.cylinder(0.0165 * s, 0.0165 * s, 0.001, 20), _glass, Vector3(0, ry + 0.042 * s, rz - 0.04 * s), X90)
			_dot(r, Vector3(0, ry + 0.042 * s, rz - 0.041 * s), Color(1.0, 0.08, 0.05))
			return {"y": ry + 0.042 * s, "rear_z": rz + 0.03 * s, "relief": 0.2}
		"holo":
			_part(r, WG.machined(Vector3(0.034, 0.016, 0.09)), _black, Vector3(0, ry + 0.008, rz + 0.01))
			var wy := ry + 0.046
			var wz := rz - 0.02
			_part(r, WG.machined(Vector3(0.05, 0.006, 0.02)), _poly, Vector3(0, wy + 0.022, wz))
			for sx in [-1, 1]:
				_part(r, WG.machined(Vector3(0.006, 0.05, 0.02)), _poly, Vector3(sx * 0.025, wy, wz))
			_part(r, WG.machined(Vector3(0.044, 0.04, 0.001)), _glass, Vector3(0, wy, wz))
			var ring := _part(r, _ring(0.0055, 0.0065), M.emissive("holo_red", Color(1.0, 0.1, 0.06), 6.0), Vector3(0, wy, wz - 0.002), X90)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_dot(r, Vector3(0, wy, wz - 0.002), Color(1.0, 0.1, 0.06))
			return {"y": wy, "rear_z": rz + 0.055, "relief": 0.2}
		"acog":
			var ay := ry + 0.05
			_part(r, WG.machined(Vector3(0.026, 0.03, 0.06)), _black, Vector3(0, ry + 0.012, rz))
			_part(r, _open_tube(0.02, 0.15), _tube, Vector3(0, ay, rz), X90)
			_part(r, _open_tube(0.027, 0.04), _tube, Vector3(0, ay, rz - 0.085), X90)
			_part(r, _ring(0.019, 0.023), _poly, Vector3(0, ay, rz + 0.075), X90)
			_part(r, ML.cylinder(0.026, 0.026, 0.001, 20), _glass, Vector3(0, ay, rz - 0.1), X90)
			_part(r, WG.machined(Vector3(0.008, 0.01, 0.01)), _poly, Vector3(0, ay + 0.024, rz + 0.01))
			var chev := _part(r, WG.machined(Vector3(0.0016, 0.0016, 0.0005)), M.emissive("acog_chev", Color(1.0, 0.25, 0.05), 6.0), Vector3(0, ay, rz - 0.099), Vector3(0, 0, PI * 0.25))
			chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return {"y": ay, "rear_z": rz + 0.075, "relief": 0.08}
		"scope":
			var sy := ry + 0.058
			for z in [0.06, -0.06]:
				_part(r, WG.machined(Vector3(0.022, 0.05, 0.02)), _black, Vector3(0, ry + 0.022, rz + z))
			_part(r, _open_tube(0.017, 0.3), _tube, Vector3(0, sy, rz), X90)
			_part(r, _open_tube(0.027, 0.08), _tube, Vector3(0, sy, rz - 0.18), X90)
			_part(r, _open_tube(0.022, 0.06), _tube, Vector3(0, sy, rz + 0.17), X90)
			_part(r, ML.cylinder(0.009, 0.009, 0.03, 18), _black, Vector3(0, sy + 0.025, rz))
			_part(r, ML.cylinder(0.009, 0.009, 0.03, 18), _black, Vector3(0.025, sy, rz), Z90)
			_part(r, ML.cylinder(0.027, 0.027, 0.001, 20), _glass, Vector3(0, sy, rz - 0.22), X90)
			return {"y": sy, "rear_z": rz + 0.2, "relief": 0.07}
	# iron sights
	if b.get("iron_builtin", false):
		return {"y": float(b.iron_y), "rear_z": float(b.iron_rear_z), "relief": float(b.get("iron_relief", 0.16))}
	var fz: float = b.iron_front_z
	var rr: float = b.iron_rear_z
	for sx in [-1, 1]:
		_part(r, WG.machined(Vector3(0.006, 0.026, 0.012)), _black, Vector3(sx * 0.008, ry + 0.013, rr))
	_part(r, WG.machined(Vector3(0.022, 0.006, 0.012)), _black, Vector3(0, ry + 0.003, rr))
	_part(r, WG.machined(Vector3(0.004, 0.032, 0.006)), _black, Vector3(0, ry + 0.012, fz))
	_part(r, WG.machined(Vector3(0.022, 0.012, 0.02)), _black, Vector3(0, ry - 0.0, fz))
	return {"y": ry + 0.026, "rear_z": rr, "relief": 0.15}


static func _dot(r: Node3D, pos: Vector3, col: Color) -> void:
	var d := _part(r, ML.sphere(0.0011, false, 6), M.emissive("dot_%s" % col.to_html(), col, 8.0), pos)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
