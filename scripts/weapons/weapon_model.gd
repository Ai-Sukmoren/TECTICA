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
	_black = M.painted_metal("weapon_anodized", Color(0.19, 0.21, 0.23))
	_black.metallic = 0.35
	_black.roughness = 0.42
	_black.normal_scale = 0.12
	_poly = M.solid(Color(0.105, 0.115, 0.12), 0.72)
	_worn = M.solid(Color(0.22, 0.22, 0.23), 0.5, 0.5)
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
		_:
			b = _pistol(root, _poly, false)

	var parts := {"root": root, "grip": b.grip, "support": b.support, "charge": b.charge, "eject": b.eject,
			"pump": b.get("pump"), "bolt": b.get("bolt"), "laser": null}
	# magazine
	var mag_at: Node3D = b.mag_at
	parts.mag = _magazine(mag_at, String(b.mag_style), String(att.get("magazine", "standard")))
	parts.mag_well = _marker(mag_at, "MagWell", Vector3(0, -0.05, 0))
	# stock
	if String(b.stock_style) != "":
		_stock(b.stock_at, String(b.stock_style), String(att.get("stock", "standard")))
	# muzzle device
	parts.muzzle = _muzzle(b.muzzle_at, String(att.get("muzzle", "none")), b.get("pistol", false))
	# underbarrel
	var ub := _underbarrel(b.under_at, String(att.get("underbarrel", "none")))
	if ub.has("support"):
		parts.support = ub.support
	if ub.has("laser"):
		parts.laser = ub.laser
	# optic
	parts.sight = _optic(root, b, String(att.get("optic", "iron")))
	return parts


# ====================================================================== helpers

static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


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
	_part(r, ML.box(Vector3(0.026, 0.012, length)), _black, Vector3(0, y - 0.006, z))
	var n := int(length / 0.03)
	for i in n:
		_part(r, ML.box(Vector3(0.03, 0.005, 0.012)), _black, Vector3(0, y - 0.001, z - length * 0.5 + 0.015 + i * 0.03))


static func _grip(r: Node3D, mat: Material, tilt: float = -0.3) -> void:
	_part(r, ML.box(Vector3(0.032, 0.105, 0.045)), mat, Vector3(0, -0.035, 0.018), Vector3(tilt, 0, 0))
	_part(r, ML.box(Vector3(0.008, 0.008, 0.07)), _black, Vector3(0, -0.005, -0.035))
	_part(r, ML.box(Vector3(0.008, 0.035, 0.008)), _black, Vector3(0, 0.01, -0.07))


# ====================================================================== base guns

static func _m4(r: Node3D) -> Dictionary:
	_part(r, ML.box(Vector3(0.046, 0.06, 0.2)), _black, Vector3(0, 0.03, -0.05))
	_part(r, ML.box(Vector3(0.046, 0.05, 0.26)), _black, Vector3(0, 0.075, -0.08))
	_rail(r, 0.112, -0.13, 0.36)
	_part(r, ML.box(Vector3(0.056, 0.056, 0.26)), _black, Vector3(0, 0.072, -0.34))
	for sx in [-1, 1]:
		_part(r, ML.box(Vector3(0.006, 0.04, 0.24)), _worn, Vector3(sx * 0.03, 0.072, -0.34))
	_part(r, ML.cylinder(0.011, 0.011, 0.14, 12), _black, Vector3(0, 0.072, -0.53), X90)
	_part(r, ML.box(Vector3(0.012, 0.03, 0.02)), _black, Vector3(0.026, 0.06, -0.02))
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
		"stock_at": _marker(r, "StockAt", Vector3(0, 0.07, 0.07)),
		"stock_style": "polymer",
		"rail_y": 0.118, "rail_z": -0.08, "iron_front_z": -0.44, "iron_rear_z": 0.04,
	}


static func _ak(r: Node3D) -> Dictionary:
	var wood := M.wood("ak_wood", Color(0.42, 0.22, 0.1))
	_part(r, ML.box(Vector3(0.046, 0.068, 0.3)), _black, Vector3(0, 0.052, -0.08))
	_part(r, ML.cylinder(0.022, 0.022, 0.26, 10), _black, Vector3(0, 0.084, -0.08), X90)
	_part(r, ML.cylinder(0.011, 0.011, 0.42, 10), _black, Vector3(0, 0.058, -0.43), X90)
	_part(r, ML.box(Vector3(0.012, 0.035, 0.012)), _black, Vector3(0, 0.085, -0.6))
	_part(r, ML.box(Vector3(0.02, 0.02, 0.03)), _black, Vector3(0, 0.1, -0.21))
	_part(r, ML.cylinder(0.013, 0.013, 0.22, 10), _black, Vector3(0, 0.088, -0.33), X90)
	_part(r, ML.box(Vector3(0.056, 0.05, 0.2)), wood, Vector3(0, 0.05, -0.31))
	_part(r, ML.box(Vector3(0.046, 0.026, 0.17)), wood, Vector3(0, 0.09, -0.32))
	_part(r, ML.box(Vector3(0.032, 0.1, 0.045)), wood, Vector3(0, -0.035, 0.018), Vector3(-0.28, 0, 0))
	_part(r, ML.box(Vector3(0.008, 0.008, 0.07)), _black, Vector3(0, -0.005, -0.035))
	_part(r, ML.box(Vector3(0.028, 0.012, 0.03)), _black, Vector3(0.032, 0.06, -0.1))
	# side-rail optic mount
	_part(r, ML.box(Vector3(0.03, 0.01, 0.16)), _black, Vector3(0, 0.103, -0.06))
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
	_part(r, ML.box(Vector3(0.046, 0.072, 0.3)), _black, Vector3(0, 0.058, -0.07))
	_part(r, ML.box(Vector3(0.036, 0.018, 0.27)), _worn, Vector3(0, 0.102, -0.07))
	_rail(r, 0.117, -0.06, 0.24)
	_part(r, ML.cylinder(0.025, 0.025, 0.42, 16), _poly, Vector3(0, 0.062, -0.43), X90)
	_part(r, ML.cylinder(0.026, 0.026, 0.02, 16), _worn, Vector3(0, 0.062, -0.23), X90)
	_part(r, ML.cylinder(0.024, 0.026, 0.02, 16), _worn, Vector3(0, 0.062, -0.645), X90)
	_part(r, ML.box(Vector3(0.054, 0.05, 0.15)), _poly, Vector3(0, 0.035, -0.28))
	_part(r, ML.box(Vector3(0.03, 0.012, 0.012)), _black, Vector3(0.03, 0.07, -0.12))
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
	_part(r, ML.box(Vector3(0.048, 0.075, 0.26)), _poly, Vector3(0, 0.06, -0.08))
	_part(r, ML.box(Vector3(0.05, 0.03, 0.1)), _black, Vector3(0, 0.04, -0.19))
	_rail(r, 0.104, -0.08, 0.22)
	_part(r, ML.cylinder(0.009, 0.009, 0.08, 10), _black, Vector3(0, 0.06, -0.25), X90)
	_part(r, ML.box(Vector3(0.034, 0.11, 0.045)), _poly, Vector3(0, -0.035, 0.0), Vector3(-0.2, 0, 0))
	_part(r, ML.box(Vector3(0.008, 0.008, 0.06)), _black, Vector3(0, -0.005, -0.045))
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
	_part(r, ML.box(Vector3(0.046, 0.06, 0.26)), _black, Vector3(0, 0.07, -0.08))
	_part(r, ML.box(Vector3(0.062, 0.075, 0.36)), green, Vector3(0, 0.025, -0.24))
	_part(r, ML.cylinder(0.015, 0.013, 0.6, 14), _black, Vector3(0, 0.07, -0.5), X90)
	_rail(r, 0.106, -0.08, 0.2)
	_part(r, ML.box(Vector3(0.034, 0.1, 0.045)), green, Vector3(0, -0.035, 0.018), Vector3(-0.3, 0, 0))
	_part(r, ML.box(Vector3(0.008, 0.008, 0.07)), _black, Vector3(0, -0.005, -0.035))
	var bolt := _marker(r, "Bolt", Vector3(0.0, 0.0, 0.0))
	_part(bolt, ML.cylinder(0.005, 0.005, 0.05, 8), _black, Vector3(0.035, 0.075, 0.0), Z90)
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
	_part(r, ML.box(Vector3(0.05, 0.07, 0.22)), _black, Vector3(0, 0.06, -0.05))
	_part(r, ML.cylinder(0.013, 0.013, 0.5, 12), _black, Vector3(0, 0.085, -0.41), X90)
	_part(r, ML.cylinder(0.013, 0.013, 0.4, 12), _black, Vector3(0, 0.048, -0.36), X90)
	_part(r, ML.box(Vector3(0.006, 0.008, 0.006)), _worn, Vector3(0, 0.1, -0.64))
	_rail(r, 0.1, -0.05, 0.14)
	_grip(r, _poly, -0.35)
	var pump := _marker(r, "Pump", Vector3(0, 0.045, -0.33))
	_part(pump, ML.box(Vector3(0.05, 0.045, 0.16)), _poly, Vector3.ZERO)
	for i in 5:
		_part(pump, ML.box(Vector3(0.054, 0.004, 0.008)), _black, Vector3(0, -0.01, -0.06 + i * 0.03))
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
	_part(r, ML.box(Vector3(0.07, 0.1, 0.32)), _black, Vector3(0, 0.06, -0.06))
	_part(r, ML.box(Vector3(0.072, 0.02, 0.18)), _worn, Vector3(0, 0.115, -0.02))
	_part(r, ML.cylinder(0.015, 0.015, 0.45, 14), _black, Vector3(0, 0.07, -0.44), X90)
	_part(r, ML.box(Vector3(0.06, 0.06, 0.18)), _poly, Vector3(0, 0.045, -0.29))
	_part(r, ML.box(Vector3(0.012, 0.05, 0.1)), _black, Vector3(0, 0.12, -0.42))
	_part(r, ML.box(Vector3(0.012, 0.012, 0.12)), _black, Vector3(0, 0.15, -0.42))
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
	_part(r, ML.box(Vector3(0.03, 0.034, 0.2)), _black, Vector3(0, 0.06, -0.08))
	_part(r, ML.box(Vector3(0.028, 0.026, 0.17)), frame, Vector3(0, 0.032, -0.07))
	_part(r, ML.box(Vector3(0.03, 0.11, 0.048)), frame, Vector3(0, -0.02, 0.005), Vector3(-0.25, 0, 0))
	_part(r, ML.box(Vector3(0.008, 0.008, 0.05)), frame, Vector3(0, 0.005, -0.03))
	if auto:
		_part(r, ML.box(Vector3(0.006, 0.01, 0.012)), _worn, Vector3(-0.017, 0.06, 0.0))
	for sx in [-1, 1]:
		_part(r, ML.box(Vector3(0.008, 0.012, 0.008)), _black, Vector3(sx * 0.009, 0.083, 0.01))
	_part(r, ML.box(Vector3(0.004, 0.012, 0.006)), _black, Vector3(0, 0.083, -0.17))
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
				_part(mag, ML.box(Vector3(0.03, 0.08, 0.06)), _poly, Vector3(0, -0.01, 0))
				for sx in [-1, 1]:
					_part(mag, ML.cylinder(0.055, 0.055, 0.045, 18), _poly, Vector3(sx * 0.04, -0.1, 0), Z90)
				bottom = -0.155
			else:
				var h := 0.15 * ext
				_part(mag, ML.box(Vector3(0.028, h, 0.064)), _poly, Vector3(0, 0.03 - h * 0.5, 0))
				_part(mag, ML.box(Vector3(0.032, 0.012, 0.068)), _black, Vector3(0, 0.03 - h, 0))
				bottom = 0.03 - h
		"ak":
			if kind == "drum":
				_part(mag, ML.box(Vector3(0.03, 0.06, 0.07)), _poly, Vector3(0, -0.005, 0))
				_part(mag, ML.cylinder(0.085, 0.085, 0.07, 22), _poly, Vector3(0, -0.11, -0.02), Z90)
				bottom = -0.195
			else:
				_part(mag, ML.box(Vector3(0.028, 0.1, 0.07)), _poly, Vector3(0, -0.025, 0))
				var h2 := 0.1 * ext
				_part(mag, ML.box(Vector3(0.028, h2, 0.068)), _poly, Vector3(0, -0.075 - h2 * 0.5, -0.03), Vector3(0.35, 0, 0))
				bottom = -0.075 - h2
		"smg":
			var h3 := 0.13 * ext
			_part(mag, ML.box(Vector3(0.024, h3, 0.034)), _poly, Vector3(0, -0.02 - h3 * 0.5 + 0.06, 0))
			_part(mag, ML.box(Vector3(0.028, 0.01, 0.038)), _black, Vector3(0, 0.04 - h3, 0))
			bottom = 0.04 - h3
		"sniper":
			var h4 := 0.065 * ext
			_part(mag, ML.box(Vector3(0.032, h4, 0.085)), _black, Vector3(0, -h4 * 0.5 + 0.01, 0))
			bottom = 0.01 - h4
		"box":
			var h5 := 0.12 * ext
			_part(mag, ML.box(Vector3(0.08, h5, 0.15)), M.solid(Color(0.25, 0.28, 0.2), 0.7), Vector3(0, -h5 * 0.5, 0))
			for i in 4:
				_part(mag, ML.box(Vector3(0.012, 0.012, 0.012)), M.solid(Color(0.75, 0.6, 0.25), 0.3, 0.9), Vector3(0.045, 0.01 + i * 0.012, -0.02 + i * 0.01))
			bottom = -h5
		"shell":
			_part(mag, ML.box(Vector3(0.03, 0.035, 0.06)), M.solid(Color(0.55, 0.1, 0.08), 0.6), Vector3(0, -0.02, 0))
			bottom = -0.04
		"pistol":
			_part(mag, ML.box(Vector3(0.024, 0.1, 0.038)), _poly, Vector3(0, 0.0, 0.0))
			if kind == "drum":
				_part(mag, ML.cylinder(0.045, 0.045, 0.035, 18), _poly, Vector3(0, -0.09, 0), Z90)
				bottom = -0.135
			elif kind == "extended":
				_part(mag, ML.box(Vector3(0.026, 0.06, 0.04)), _poly, Vector3(0, -0.075, 0))
				bottom = -0.105
			else:
				_part(mag, ML.box(Vector3(0.03, 0.012, 0.046)), _black, Vector3(0, -0.055, 0))
				bottom = -0.06
	if kind == "fast":
		_part(mag, ML.box(Vector3(0.012, 0.035, 0.012)), M.solid(Color(0.9, 0.4, 0.1), 0.6), Vector3(0, bottom - 0.015, 0.0))
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
				_part(at, ML.box(Vector3(0.012, 0.012, length)), _black, Vector3(0, y, length * 0.5))
			_part(at, ML.box(Vector3(0.03, 0.1, 0.018)), _poly, Vector3(0, -0.015, length))
		"heavy":
			_part(at, ML.box(Vector3(0.046, 0.1, length)), mat, Vector3(0, -0.025, length * 0.5))
			_part(at, ML.box(Vector3(0.03, 0.03, length * 0.5)), mat, Vector3(0, 0.035, length * 0.6))
			_part(at, ML.box(Vector3(0.05, 0.13, 0.025)), M.solid(Color(0.04, 0.04, 0.04), 0.95), Vector3(0, -0.03, length))
		_:
			match style:
				"skeletal":
					_part(at, ML.box(Vector3(0.018, 0.018, 0.24)), _black, Vector3(0, 0.015, 0.11))
					_part(at, ML.box(Vector3(0.018, 0.018, 0.22)), _black, Vector3(0, -0.055, 0.1), Vector3(0.28, 0, 0))
					_part(at, ML.box(Vector3(0.034, 0.12, 0.026)), _poly, Vector3(0, -0.025, 0.22))
				"rods":
					for sx in [-1, 1]:
						_part(at, ML.box(Vector3(0.008, 0.008, 0.16)), _black, Vector3(sx * 0.018, 0.0, 0.08))
					_part(at, ML.box(Vector3(0.05, 0.06, 0.02)), _poly, Vector3(0, -0.01, 0.16))
				"polymer":
					_part(at, ML.cylinder(0.014, 0.014, 0.18, 10), _black, Vector3(0, 0.0, 0.09), X90)
					_part(at, ML.box(Vector3(0.042, 0.085, 0.13)), mat, Vector3(0, -0.02, 0.17))
					_part(at, ML.box(Vector3(0.044, 0.12, 0.02)), M.solid(Color(0.04, 0.04, 0.04), 0.95), Vector3(0, -0.025, 0.24))
				_:
					_part(at, ML.box(Vector3(0.042, 0.09, length)), mat, Vector3(0, -0.02, length * 0.5), Vector3(0.06, 0, 0))
					_part(at, ML.box(Vector3(0.044, 0.12, 0.02)), M.solid(Color(0.04, 0.04, 0.04), 0.95), Vector3(0, -0.035, length))


static func _muzzle(at: Node3D, kind: String, pistol: bool) -> Node3D:
	var end := 0.0
	match kind:
		"suppressor":
			var rad := 0.016 if pistol else 0.022
			var length := 0.13 if pistol else 0.18
			_part(at, ML.cylinder(rad, rad, length, 16), _poly, Vector3(0, 0, -length * 0.5), X90)
			_part(at, ML.cylinder(rad * 0.7, rad, 0.015, 16), _worn, Vector3(0, 0, -length), X90)
			end = -length - 0.01
		"compensator":
			_part(at, ML.cylinder(0.016, 0.016, 0.055, 12), _black, Vector3(0, 0, -0.027), X90)
			for i in 3:
				_part(at, ML.box(Vector3(0.018, 0.005, 0.008)), _worn, Vector3(0, 0.014, -0.012 - i * 0.015))
			end = -0.055
		"flash_hider":
			_part(at, ML.cylinder(0.013, 0.013, 0.02, 10), _black, Vector3(0, 0, -0.01), X90)
			for k in 4:
				var a := k * PI * 0.5 + PI * 0.25
				_part(at, ML.box(Vector3(0.004, 0.004, 0.04)), _black, Vector3(cos(a) * 0.01, sin(a) * 0.01, -0.035))
			end = -0.055
		"brake":
			_part(at, ML.box(Vector3(0.04, 0.026, 0.065)), _black, Vector3(0, 0, -0.032))
			for i in 3:
				_part(at, ML.box(Vector3(0.042, 0.018, 0.006)), _worn, Vector3(0, 0, -0.015 - i * 0.017))
			end = -0.065
		"choke":
			_part(at, ML.cylinder(0.014, 0.016, 0.04, 12), _worn, Vector3(0, 0, -0.02), X90)
			end = -0.04
	return _marker(at, "Muzzle", Vector3(0, 0, end))


static func _underbarrel(at: Node3D, kind: String) -> Dictionary:
	match kind:
		"vgrip":
			_part(at, ML.box(Vector3(0.028, 0.012, 0.04)), _black, Vector3(0, -0.006, 0))
			_part(at, ML.cylinder(0.015, 0.016, 0.09, 12), _poly, Vector3(0, -0.055, 0))
			return {"support": _marker(at, "Support", Vector3(-0.01, -0.06, 0.0), Vector3(0.0, 0.0, -0.25))}
		"agrip":
			_part(at, ML.box(Vector3(0.028, 0.035, 0.08)), _poly, Vector3(0, -0.02, 0.0), Vector3(0.45, 0, 0))
			return {"support": _marker(at, "Support", Vector3(-0.01, -0.03, 0.01), Vector3(0.2, 0, -0.4))}
		"laser":
			_part(at, ML.box(Vector3(0.028, 0.024, 0.06)), _black, Vector3(0, -0.015, 0))
			_part(at, ML.cylinder(0.005, 0.005, 0.005, 8), M.emissive("laser_lens", Color(1.0, 0.1, 0.05), 3.0), Vector3(0, -0.015, -0.032), X90)
			return {"laser": _marker(at, "Laser", Vector3(0, -0.015, -0.035))}
		"bipod":
			_part(at, ML.box(Vector3(0.03, 0.02, 0.03)), _black, Vector3(0, -0.01, 0))
			for sx in [-1, 1]:
				_part(at, ML.cylinder(0.005, 0.005, 0.2, 6), _black, Vector3(sx * 0.012, -0.022, -0.1), X90)
	return {}


static func _optic(r: Node3D, b: Dictionary, kind: String) -> Dictionary:
	var ry: float = b.rail_y
	var rz: float = b.rail_z
	var s := 0.75 if b.get("mini", false) else 1.0
	match kind:
		"reddot":
			_part(r, ML.box(Vector3(0.026, 0.02, 0.06) * s), _black, Vector3(0, ry + 0.008 * s, rz))
			for z in [0.03, -0.04]:
				_part(r, _ring(0.0165 * s, 0.021 * s), _poly, Vector3(0, ry + 0.042 * s, rz + z * s), X90)
			for sx in [-1, 1]:
				_part(r, ML.box(Vector3(0.004, 0.012, 0.07) * s), _poly, Vector3(sx * 0.019 * s, ry + 0.034 * s, rz - 0.005 * s))
			_part(r, ML.cylinder(0.0165 * s, 0.0165 * s, 0.001, 20), _glass, Vector3(0, ry + 0.042 * s, rz - 0.04 * s), X90)
			_dot(r, Vector3(0, ry + 0.042 * s, rz - 0.041 * s), Color(1.0, 0.08, 0.05))
			return {"y": ry + 0.042 * s, "rear_z": rz + 0.03 * s, "relief": 0.2}
		"holo":
			_part(r, ML.box(Vector3(0.034, 0.016, 0.09)), _black, Vector3(0, ry + 0.008, rz + 0.01))
			var wy := ry + 0.046
			var wz := rz - 0.02
			_part(r, ML.box(Vector3(0.05, 0.006, 0.02)), _poly, Vector3(0, wy + 0.022, wz))
			for sx in [-1, 1]:
				_part(r, ML.box(Vector3(0.006, 0.05, 0.02)), _poly, Vector3(sx * 0.025, wy, wz))
			_part(r, ML.box(Vector3(0.044, 0.04, 0.001)), _glass, Vector3(0, wy, wz))
			var ring := _part(r, _ring(0.0055, 0.0065), M.emissive("holo_red", Color(1.0, 0.1, 0.06), 6.0), Vector3(0, wy, wz - 0.002), X90)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_dot(r, Vector3(0, wy, wz - 0.002), Color(1.0, 0.1, 0.06))
			return {"y": wy, "rear_z": rz + 0.055, "relief": 0.2}
		"acog":
			var ay := ry + 0.05
			_part(r, ML.box(Vector3(0.026, 0.03, 0.06)), _black, Vector3(0, ry + 0.012, rz))
			_part(r, _open_tube(0.02, 0.15), _tube, Vector3(0, ay, rz), X90)
			_part(r, _open_tube(0.027, 0.04), _tube, Vector3(0, ay, rz - 0.085), X90)
			_part(r, _ring(0.019, 0.023), _poly, Vector3(0, ay, rz + 0.075), X90)
			_part(r, ML.cylinder(0.026, 0.026, 0.001, 20), _glass, Vector3(0, ay, rz - 0.1), X90)
			_part(r, ML.box(Vector3(0.008, 0.01, 0.01)), _poly, Vector3(0, ay + 0.024, rz + 0.01))
			var chev := _part(r, ML.box(Vector3(0.0016, 0.0016, 0.0005)), M.emissive("acog_chev", Color(1.0, 0.25, 0.05), 6.0), Vector3(0, ay, rz - 0.099), Vector3(0, 0, PI * 0.25))
			chev.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return {"y": ay, "rear_z": rz + 0.075, "relief": 0.08}
		"scope":
			var sy := ry + 0.058
			for z in [0.06, -0.06]:
				_part(r, ML.box(Vector3(0.022, 0.05, 0.02)), _black, Vector3(0, ry + 0.022, rz + z))
			_part(r, _open_tube(0.017, 0.3), _tube, Vector3(0, sy, rz), X90)
			_part(r, _open_tube(0.027, 0.08), _tube, Vector3(0, sy, rz - 0.18), X90)
			_part(r, _open_tube(0.022, 0.06), _tube, Vector3(0, sy, rz + 0.17), X90)
			_part(r, ML.cylinder(0.009, 0.009, 0.03, 10), _black, Vector3(0, sy + 0.025, rz))
			_part(r, ML.cylinder(0.009, 0.009, 0.03, 10), _black, Vector3(0.025, sy, rz), Z90)
			_part(r, ML.cylinder(0.027, 0.027, 0.001, 20), _glass, Vector3(0, sy, rz - 0.22), X90)
			return {"y": sy, "rear_z": rz + 0.2, "relief": 0.07}
	# iron sights
	if b.get("iron_builtin", false):
		return {"y": float(b.iron_y), "rear_z": float(b.iron_rear_z), "relief": float(b.get("iron_relief", 0.16))}
	var fz: float = b.iron_front_z
	var rr: float = b.iron_rear_z
	for sx in [-1, 1]:
		_part(r, ML.box(Vector3(0.006, 0.026, 0.012)), _black, Vector3(sx * 0.008, ry + 0.013, rr))
	_part(r, ML.box(Vector3(0.022, 0.006, 0.012)), _black, Vector3(0, ry + 0.003, rr))
	_part(r, ML.box(Vector3(0.004, 0.032, 0.006)), _black, Vector3(0, ry + 0.012, fz))
	_part(r, ML.box(Vector3(0.022, 0.012, 0.02)), _black, Vector3(0, ry - 0.0, fz))
	return {"y": ry + 0.026, "rear_z": rr, "relief": 0.15}


static func _dot(r: Node3D, pos: Vector3, col: Color) -> void:
	var d := _part(r, ML.sphere(0.0011, false, 6), M.emissive("dot_%s" % col.to_html(), col, 8.0), pos)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
