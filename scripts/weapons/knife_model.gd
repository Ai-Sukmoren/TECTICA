extends RefCounted
## Procedural knife models. Same part layout as weapon_model.gd so the rig can
## hold them: the grip marker sits in the palm, the blade points along -Z.
##   knife_combat  clip-point fighting knife, ridged rubber grip, cross guard
##   karambit      curved hooked blade, finger ring at the pommel
##   butterfly     balisong: two handles on pivots that flip around the blade
## Extra parts for the inspect / flip animations: "spin" (whole knife pivot)
## and, on the butterfly, "handle_safe" / "handle_bite" pivots.

const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const WG = preload("res://scripts/weapons/weapon_geometry.gd")

static var _steel: Material
static var _edge: Material
static var _rubber: Material
static var _g10: Material


static func _mats() -> void:
	if _steel != null:
		return
	_steel = M.solid(Color(0.62, 0.64, 0.67), 0.28, 0.92)
	_edge = M.solid(Color(0.86, 0.88, 0.9), 0.12, 1.0)
	_rubber = M.solid(Color(0.08, 0.08, 0.085), 0.85, 0.0)
	_g10 = M.solid(Color(0.13, 0.14, 0.12), 0.6, 0.1)


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


## Outline points are (z, y): z runs along the blade (forward = negative).
static func _blade(parent: Node3D, width: float, outline: Array, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _part(parent, WG.profile(width, PackedVector2Array(outline)), mat, pos)


static func build(model: String) -> Dictionary:
	_mats()
	var root := Node3D.new()
	root.name = "Model"
	# a touch larger than life so it reads on screen (viewmodel scale)
	root.scale = Vector3.ONE * 1.35
	# The hand closes round a weapon's grip like a pistol grip (running down
	# through the palm), so the knife stands up in a "Tilt" node: handle down
	# into the fist, blade up and slightly forward out of the top.
	# The karambit is held the real way, in reverse grip: index finger through
	# the ring on top of the fist, the hooked blade coming out under the pinky.
	# The offset puts the middle of the handle (0.05 m behind the guard, 0.04 m
	# on the short karambit grip) in the palm: offset = -R * (0, 0, mid).
	var reverse := model == "karambit"
	var angle := deg_to_rad(254.0 if reverse else 74.0)
	var mid := 0.04 if reverse else 0.05
	var tilt := _marker(root, "Tilt", Vector3(0, mid * sin(angle), -mid * cos(angle)), Vector3(angle, 0, 0))
	if reverse:   # roll about the blade's axis so the hook's tip points forward, at the target
		tilt.basis = Basis(Vector3.RIGHT, angle) * Basis(Vector3.BACK, PI)
	# everything visible hangs off "spin" so inspects can twirl the knife in the palm
	var spin := _marker(tilt, "Spin", Vector3.ZERO)
	var out := {"root": root, "spin": spin, "pump": null, "bolt": null, "laser": null, "mag": null,
			"sight": {"relief": 0.3, "y": 0.0, "rear_z": 0.0}}
	match model:
		"karambit":
			_karambit(spin, out)
		"butterfly":
			_butterfly(spin, out)
		_:
			_combat(spin, out)
	out.grip = _marker(root, "Grip", Vector3.ZERO, Vector3(-0.15, 0, 0))
	out.support = _marker(root, "Support", Vector3(-0.09, -0.06, 0.06))   # the free hand guards here
	out.mag_well = out.grip
	out.charge = out.grip
	out.eject = out.grip
	return out


static func _combat(r: Node3D, out: Dictionary) -> void:
	# grip: rubber with finger ridges, steel pommel
	_part(r, ML.cylinder(0.0145, 0.0135, 0.115, 14), _rubber, Vector3(0, 0, 0.05), Vector3(PI * 0.5, 0, 0))
	for i in 4:
		_part(r, ML.cylinder(0.0158, 0.0158, 0.008, 14), _rubber, Vector3(0, 0, 0.012 + i * 0.024), Vector3(PI * 0.5, 0, 0))
	_part(r, ML.cylinder(0.016, 0.011, 0.018, 14), _steel, Vector3(0, 0, 0.115), Vector3(PI * 0.5, 0, 0))
	# cross guard
	_part(r, ML.box(Vector3(0.012, 0.062, 0.012)), _steel, Vector3(0, 0.004, -0.012))
	# clip-point blade, spine on top, edge sweeping up to the tip
	_blade(r, 0.0045, [Vector2(-0.016, 0.014), Vector2(-0.13, 0.016), Vector2(-0.16, 0.009), Vector2(-0.19, 0.002),
			Vector2(-0.165, -0.012), Vector2(-0.12, -0.02), Vector2(-0.04, -0.02), Vector2(-0.016, -0.014)], _steel)
	# bright bevel along the edge and a fuller groove
	_blade(r, 0.0052, [Vector2(-0.03, -0.012), Vector2(-0.12, -0.012), Vector2(-0.165, -0.006), Vector2(-0.182, 0.0),
			Vector2(-0.165, -0.0125), Vector2(-0.12, -0.0205), Vector2(-0.03, -0.0205)], _edge)
	_part(r, ML.box(Vector3(0.0056, 0.0035, 0.085)), _rubber, Vector3(0, 0.006, -0.07))
	# serrations on the spine near the guard
	for i in 6:
		_part(r, ML.box(Vector3(0.0048, 0.004, 0.004)), _steel, Vector3(0, 0.017, -0.03 - i * 0.008), Vector3(0.6, 0, 0))
	out.muzzle = _marker(r, "Tip", Vector3(0, 0.002, -0.19))


static func _karambit(r: Node3D, out: Dictionary) -> void:
	# short grip with a finger ring behind the pommel
	_part(r, ML.box(Vector3(0.016, 0.026, 0.085)), _g10, Vector3(0, 0, 0.035))
	for i in 3:
		_part(r, ML.cylinder(0.0035, 0.0035, 0.018, 8), _steel, Vector3(0, 0, 0.005 + i * 0.03), Vector3(0, 0, PI * 0.5))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.016
	ring.outer_radius = 0.023
	ring.rings = 18
	ring.ring_segments = 8
	_part(r, ring, _steel, Vector3(0, 0.002, 0.095), Vector3(0, 0, PI * 0.5))
	# hooked blade: a chain of tapering segments curving down and forward
	var pts := 9
	for i in pts:
		var u := float(i) / (pts - 1)
		var a := lerpf(0.15, 1.45, u)               # bends from straight to hooked
		var z := -0.008 - sin(a) * 0.075 - u * 0.02
		var y := 0.006 - (1.0 - cos(a)) * 0.06
		var h := lerpf(0.026, 0.006, u)
		_part(r, ML.box(Vector3(0.0042, h, 0.017)), _steel, Vector3(0, y, z), Vector3(-a * 0.75, 0, 0))
		_part(r, ML.box(Vector3(0.005, 0.004, 0.016)), _edge, Vector3(0, y - h * 0.45, z), Vector3(-a * 0.75, 0, 0))
	out.muzzle = _marker(r, "Tip", Vector3(0, -0.055, -0.1))


static func _butterfly(r: Node3D, out: Dictionary) -> void:
	# blade on the pivots (tang at the grip marker)
	_blade(r, 0.004, [Vector2(-0.012, 0.011), Vector2(-0.11, 0.011), Vector2(-0.135, 0.001), Vector2(-0.11, -0.011),
			Vector2(-0.012, -0.011)], _steel)
	_blade(r, 0.0048, [Vector2(-0.02, -0.004), Vector2(-0.11, -0.004), Vector2(-0.13, 0.0), Vector2(-0.11, -0.0115),
			Vector2(-0.02, -0.0115)], _edge)
	_part(r, ML.box(Vector3(0.0045, 0.01, 0.012)), _steel, Vector3(0, 0.0, 0.0))
	# two handles, each on its own pivot pin either side of the tang. Open:
	# they lie back along +Z (in the palm). The flip swings them 180 deg round
	# the pin so they close over the blade.
	for side in [-1.0, 1.0]:
		var pivot := _marker(r, "HandleSafe" if side < 0 else "HandleBite", Vector3(side * 0.0055, 0, 0.004))
		var h := Node3D.new()
		pivot.add_child(h)
		_part(h, ML.box(Vector3(0.0055, 0.022, 0.125)), _steel, Vector3(0, 0, 0.066))
		for k in 4:   # skeletonised cut-outs
			_part(h, ML.box(Vector3(0.0062, 0.009, 0.018)), _rubber, Vector3(0, 0, 0.03 + k * 0.026))
		_part(h, ML.cylinder(0.004, 0.004, 0.012, 8), _edge, Vector3(0, 0, 0.004), Vector3(0, 0, PI * 0.5))
		if side > 0:
			_part(h, ML.box(Vector3(0.006, 0.008, 0.014)), _edge, Vector3(0, -0.012, 0.124))   # latch
		out["handle_safe" if side < 0 else "handle_bite"] = pivot
	out.muzzle = _marker(r, "Tip", Vector3(0, 0.0, -0.135))
