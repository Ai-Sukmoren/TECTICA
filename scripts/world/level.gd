extends Node3D
## Builds the military compound: insertion yard, central warehouse, armory,
## barracks and command post. All solid props live under a NavigationRegion3D
## that is baked at load. Low cover generates tactical cover points for the AI.

const FX = preload("res://scripts/fx/fx.gd")
const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const Layers = preload("res://scripts/core/layers.gd")
const Destructible = preload("res://scripts/world/destructible.gd")
const PP = preload("res://scripts/core/pack_props.gd")

const WALL_H := 2.6
const WALL_T := 0.4

var nav_region: NavigationRegion3D
var cover_points: Array = []
var player_spawn := Vector3(0, 0, 17)
var player_yaw := 0.0
var enemy_spawns: Array = []
var ammo_crates: Array = []
var map_rects: Array = []
var zombie_spawns: Array = [
	Vector3(-10, 0, 18.5), Vector3(10.5, 0, 9.5), Vector3(-22.5, 0, -6), Vector3(22.5, 0, -6),
	Vector3(-22, 0, 3.5), Vector3(22, 0, 1), Vector3(-20, 0, -27.5), Vector3(-10, 0, -27.8),
	Vector3(0.5, 0, -28.2), Vector3(12, 0, -29), Vector3(22, 0, -24), Vector3(-4, 0, -15.5),
	Vector3(13, 0, -12.6), Vector3(-13, 0, -12.6),
]
var lights: Array = []
## Indoor reflection / ambient probes; the time of day keeps their fill in step.
var interior_probes: Array = []
var _dust: Array = []
var _cover_validated := false
var _nav_dirty := false
var props_destroyed := 0
## Destructible props by network id (registration order is identical on every peer).
var props: Array = []
var destroyed_ids: Array = []

var _mat_wall: Material
var _mat_wall_trim: Material
var _mat_crate: Material
var _mat_crate_frame: Material
var _mat_sandbag: Material
var _mat_concrete: Material
var _mat_metal: Material


func build() -> void:
	_mat_wall = M.concrete("wall", Color(0.36, 0.38, 0.42), 0.4)
	_mat_wall_trim = M.solid(Color(0.2, 0.21, 0.23), 0.8)
	_mat_crate = M.wood("crate", Color(0.46, 0.4, 0.28))
	_mat_crate_frame = M.wood("crate_frame", Color(0.34, 0.29, 0.2))
	_mat_sandbag = M.fabric("sandbag", Color(0.52, 0.47, 0.36), 4.0)
	_mat_concrete = M.concrete("barrier", Color(0.55, 0.55, 0.53), 0.6)
	_mat_metal = M.painted_metal("metal_grey", Color(0.3, 0.32, 0.33))
	FX.ground_surface = "stone"

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)

	_build_floors()
	_build_walls()
	_build_yard()
	_build_warehouse()
	_build_armory()
	_build_barracks()
	_build_command()
	_build_set_dressing()
	_build_lights()
	_build_dust()
	_define_enemies()
	_bake_navigation()


# ================================================================ geometry helpers

func _body(pos: Vector3, rot_y: float = 0.0, kind: String = "") -> StaticBody3D:
	var b: StaticBody3D
	if kind != "":
		b = Destructible.new()
		b.setup_kind(kind, self)
	else:
		b = StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	b.collision_mask = 0
	b.position = pos
	b.rotation.y = rot_y
	nav_region.add_child(b)
	return b


func _box_shape(body: Node3D, size: Vector3, offset: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	body.add_child(cs)
	if size.x < 40.0:
		var c := body.position + Basis(Vector3.UP, body.rotation.y) * offset
		var rect := {"c": Vector2(c.x, c.z), "s": Vector2(size.x, size.z), "r": body.rotation.y, "tall": size.y > 1.4}
		map_rects.append(rect)
		if body is Destructible:
			body.rects.append(rect)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Solid box standing on the floor at `pos` (bottom centre).
func solid_box(pos: Vector3, size: Vector3, mat: Material, rot_y: float = 0.0, low_cover: bool = false,
		kind: String = "") -> StaticBody3D:
	var b := _body(pos, rot_y, kind)
	if mat != null and mat.has_meta("surface"):
		b.set_meta("surface", mat.get_meta("surface"))
	_box_shape(b, size, Vector3(0, size.y * 0.5, 0))
	_mesh(b, ML.box(size), mat, Vector3(0, size.y * 0.5, 0))
	if low_cover:
		_add_cover(pos, size, rot_y, b)
	return b


func crate(pos: Vector3, size: Vector3, rot_y: float = 0.0, stacked: bool = false) -> StaticBody3D:
	var b := solid_box(pos, size, _mat_crate, rot_y, not stacked and size.y <= 1.25, "wood")
	var t := 0.05
	var h := size.y
	# edge frame
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_mesh(b, ML.box(Vector3(t, h, t)), _mat_crate_frame,
					Vector3(sx * (size.x * 0.5 - t * 0.3), h * 0.5, sz * (size.z * 0.5 - t * 0.3)))
	for sy in [0.0, 1.0]:
		var y: float = t * 0.5 + sy * (h - t)
		for sz in [-1, 1]:
			_mesh(b, ML.box(Vector3(size.x + 0.02, t, t)), _mat_crate_frame, Vector3(0, y, sz * (size.z * 0.5 - t * 0.3)))
		for sx in [-1, 1]:
			_mesh(b, ML.box(Vector3(t, t, size.z + 0.02)), _mat_crate_frame, Vector3(sx * (size.x * 0.5 - t * 0.3), y, 0))
	# diagonal brace on top + stencil band
	_mesh(b, ML.box(Vector3(t, 0.02, sqrt(size.x * size.x + size.z * size.z) * 0.92)), _mat_crate_frame,
			Vector3(0, h + 0.005, 0), Vector3(0, atan2(size.x, size.z), 0))
	_mesh(b, ML.box(Vector3(size.x * 0.5, 0.08, size.z + 0.015)), M.solid(Color(0.15, 0.14, 0.1), 0.9), Vector3(0, h * 0.62, 0))
	b.finalize()
	return b


func crate_stack(pos: Vector3, rot_y: float = 0.0) -> void:
	var bottom := crate(pos, Vector3(1.2, 1.0, 1.2), rot_y, true)
	var top := _body(pos + Vector3(0, 1.0, 0), rot_y + 0.2, "wood")
	_box_shape(top, Vector3(1.0, 0.9, 1.0), Vector3(0, 0.45, 0))
	_mesh(top, ML.box(Vector3(1.0, 0.9, 1.0)), _mat_crate, Vector3(0, 0.45, 0))
	_mesh(top, ML.box(Vector3(1.02, 0.06, 1.02)), _mat_crate_frame, Vector3(0, 0.88, 0))
	top.finalize()
	bottom.dependents.append(top)


func sandbags(pos: Vector3, length: float, rot_y: float = 0.0, rows: int = 3) -> void:
	var height := 0.24 * rows + 0.1
	var b := _body(pos, rot_y, "sand")
	_box_shape(b, Vector3(length, height, 0.6), Vector3(0, height * 0.5, 0))
	var bag := ML.capsule(0.15, 0.55)
	var use_pack := PP.available("sandbag")   # asset pack 4 bag model
	var n := int(length / 0.5)
	for r in rows:
		var off := 0.25 if r % 2 == 1 else 0.0
		var count := n - (1 if r % 2 == 1 else 0)
		for i in count:
			var x := -length * 0.5 + 0.27 + i * 0.5 + off
			for z in [-0.13, 0.13]:
				if use_pack:
					PP.add(b, "sandbag", Vector3(x, r * 0.24, z + randf_range(-0.02, 0.02)),
							randf_range(-0.12, 0.12), 0.0, Vector3(0.52, 0.25, 0.27))
					continue
				_mesh(b, bag, _mat_sandbag, Vector3(x, 0.12 + r * 0.24, z + randf_range(-0.02, 0.02)),
						Vector3(randf_range(-0.05, 0.05), randf_range(-0.12, 0.12), PI * 0.5), Vector3(1.0, 1.0, 0.62))
	_add_cover(pos, Vector3(length, height, 0.6), rot_y, b)
	b.finalize()


func barrel(pos: Vector3, color: Color) -> void:
	var b := _body(pos, 0.0, "explosive" if color.r > 0.5 else "metal")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 0.9
	cs.shape = cyl
	cs.position.y = 0.45
	b.add_child(cs)
	if color.r > 0.5 and not PP.add(b, "fuel_barrel", Vector3.ZERO, randf() * TAU, 0.0, Vector3(0.6, 0.9, 0.6)).is_empty():
		b.finalize()   # red/white fuel drum from asset pack 4
		return
	var mat := M.painted_metal("barrel_%s" % color.to_html(), color)
	_mesh(b, ML.cylinder(0.29, 0.29, 0.9, 18), mat, Vector3(0, 0.45, 0))
	for y in [0.06, 0.3, 0.6, 0.84]:
		_mesh(b, ML.cylinder(0.305, 0.305, 0.03, 18), mat, Vector3(0, y, 0))
	_mesh(b, ML.cylinder(0.05, 0.05, 0.02, 8), _mat_metal, Vector3(0.14, 0.905, 0.05))
	b.finalize()


func barrier(pos: Vector3, rot_y: float = 0.0) -> void:
	## Concrete jersey barrier: low cover.
	var b := _body(pos, rot_y, "concrete")
	_box_shape(b, Vector3(2.6, 0.95, 0.6), Vector3(0, 0.475, 0))
	_mesh(b, ML.box(Vector3(2.6, 0.35, 0.6)), _mat_concrete, Vector3(0, 0.175, 0))
	_mesh(b, ML.box(Vector3(2.6, 0.6, 0.3)), _mat_concrete, Vector3(0, 0.65, 0))
	_mesh(b, ML.box(Vector3(2.6, 0.08, 0.22)), M.hazard_stripes(), Vector3(0, 0.96, 0))
	_add_cover(pos, Vector3(2.6, 0.95, 0.6), rot_y, b)
	b.finalize()


func container(pos: Vector3, rot_y: float, color: Color) -> void:
	var size := Vector3(2.44, 2.6, 6.06)
	var b := _body(pos, rot_y)
	_box_shape(b, size, Vector3(0, size.y * 0.5, 0))
	var mat := M.painted_metal("container_%s" % color.to_html(), color)
	_mesh(b, ML.box(size - Vector3(0.08, 0, 0.08)), mat, Vector3(0, size.y * 0.5, 0))
	var n := 22
	for i in n:
		var z := -size.z * 0.5 + 0.2 + i * (size.z - 0.4) / (n - 1)
		for sx in [-1, 1]:
			_mesh(b, ML.box(Vector3(0.06, size.y - 0.2, 0.12)), mat, Vector3(sx * size.x * 0.5, size.y * 0.5, z))
	for sz in [-1, 1]:
		_mesh(b, ML.box(Vector3(size.x, 0.15, 0.15)), _mat_metal, Vector3(0, size.y - 0.075, sz * (size.z * 0.5 - 0.075)))
		_mesh(b, ML.box(Vector3(size.x, 0.15, 0.15)), _mat_metal, Vector3(0, 0.075, sz * (size.z * 0.5 - 0.075)))
	for i in 4:
		_mesh(b, ML.box(Vector3(0.04, 2.3, 0.04)), _mat_metal, Vector3(-0.8 + i * 0.53, 1.3, size.z * 0.5 + 0.02))
	_mesh(b, ML.box(Vector3(size.x - 0.2, 0.02, size.z - 0.3)), mat, Vector3(0, size.y + 0.01, 0))


func vehicle(pos: Vector3, rot_y: float) -> void:
	## Military utility truck (blocks line of sight).
	var b := _body(pos, rot_y)
	_box_shape(b, Vector3(2.3, 2.1, 5.6), Vector3(0, 1.05, 0))
	var paint := M.painted_metal("truck", Color(0.3, 0.33, 0.24))
	var tire := M.solid(Color(0.07, 0.07, 0.07), 0.9)
	var glass := M.solid(Color(0.1, 0.13, 0.16), 0.1, 0.5)
	_mesh(b, ML.box(Vector3(2.2, 0.3, 5.4)), _mat_metal, Vector3(0, 0.75, 0))
	_mesh(b, ML.box(Vector3(2.2, 1.0, 1.7)), paint, Vector3(0, 1.4, -1.75))
	_mesh(b, ML.box(Vector3(2.0, 0.5, 0.08)), glass, Vector3(0, 1.65, -2.6), Vector3(-0.3, 0, 0))
	_mesh(b, ML.box(Vector3(2.2, 0.5, 1.0)), paint, Vector3(0, 1.0, -2.75))
	_mesh(b, ML.box(Vector3(2.3, 0.08, 3.4)), paint, Vector3(0, 0.95, 0.95))
	for sx in [-1, 1]:
		_mesh(b, ML.box(Vector3(0.06, 0.6, 3.4)), paint, Vector3(sx * 1.12, 1.25, 0.95))
	var canvas := M.fabric("canvas", Color(0.36, 0.37, 0.27), 2.0)
	_mesh(b, ML.box(Vector3(2.2, 0.9, 3.4)), canvas, Vector3(0, 1.45, 0.95))
	_mesh(b, ML.box(Vector3(1.6, 0.12, 3.4)), canvas, Vector3(0, 1.94, 0.95))
	var trim := M.matte("truck_trim", Color(0.05, 0.05, 0.055), 0.6)
	var rim := M.solid(Color(0.3, 0.31, 0.3), 0.4, 0.8)
	for z in [-0.5, 0.95, 2.4]:
		_mesh(b, ML.box(Vector3(2.24, 0.04, 0.05)), trim, Vector3(0, 1.97, z))   # canvas hoops
	_mesh(b, ML.rbox(Vector3(2.3, 0.22, 0.16)), trim, Vector3(0, 0.55, -3.32))   # front bumper
	_mesh(b, ML.box(Vector3(0.9, 0.4, 0.03)), trim, Vector3(0, 1.05, -3.26))      # grille
	for sx in [-1, 1]:
		_mesh(b, ML.box(Vector3(0.28, 0.2, 0.04)), M.emissive("headlamp", Color(0.9, 0.9, 0.8), 0.15), Vector3(sx * 0.8, 1.05, -3.26))
		_mesh(b, ML.rbox(Vector3(0.08, 0.22, 0.14)), trim, Vector3(sx * 1.2, 1.7, -2.3))   # mirrors
	_mesh(b, ML.cylinder(0.05, 0.05, 1.4, 8), trim, Vector3(1.1, 1.6, -0.95))     # exhaust stack
	for z in [-1.9, 0.4, 1.9]:
		for sx in [-1, 1]:
			_mesh(b, ML.cylinder(0.45, 0.45, 0.35, 16), tire, Vector3(sx * 1.0, 0.45, z), Vector3(0, 0, PI * 0.5))
			_mesh(b, ML.cylinder(0.26, 0.26, 0.37, 12), rim, Vector3(sx * 1.0, 0.45, z), Vector3(0, 0, PI * 0.5))


func rack(pos: Vector3, rot_y: float, length: float) -> void:
	## Tall weapon / supply shelving.
	var b := _body(pos, rot_y, "rack")
	_box_shape(b, Vector3(length, 2.0, 0.6), Vector3(0, 1.0, 0))
	for y in [0.1, 0.75, 1.4, 1.98]:
		_mesh(b, ML.box(Vector3(length, 0.04, 0.6)), _mat_metal, Vector3(0, y, 0))
	for sx in [-1, 1]:
		_mesh(b, ML.box(Vector3(0.05, 2.0, 0.6)), _mat_metal, Vector3(sx * length * 0.5, 1.0, 0))
	var green := M.painted_metal("ammo_green", Color(0.24, 0.3, 0.18))
	for y in [0.12, 0.77, 1.42]:
		var x := -length * 0.5 + 0.25
		while x < length * 0.5 - 0.25:
			if randf() < 0.75:
				_mesh(b, ML.box(Vector3(0.38, 0.28, 0.25)), green, Vector3(x + 0.15, y + 0.16, randf_range(-0.12, 0.12)))
			x += 0.45
	b.finalize()


func desk(pos: Vector3, rot_y: float, monitor: bool = true) -> void:
	var b := solid_box(pos, Vector3(1.6, 0.78, 0.8), M.solid(Color(0.26, 0.27, 0.28), 0.6, 0.3), rot_y, true, "desk")
	_mesh(b, ML.box(Vector3(1.64, 0.04, 0.84)), M.solid(Color(0.4, 0.38, 0.33), 0.6), Vector3(0, 0.8, 0))
	if monitor:
		_mesh(b, ML.box(Vector3(0.55, 0.36, 0.04)), M.solid(Color(0.05, 0.05, 0.05), 0.4), Vector3(-0.3, 1.04, 0.2))
		_mesh(b, ML.box(Vector3(0.5, 0.31, 0.01)), M.emissive("screen", Color(0.2, 0.55, 0.45), 1.6), Vector3(-0.3, 1.04, 0.177))
		_mesh(b, ML.box(Vector3(0.45, 0.02, 0.16)), M.solid(Color(0.08, 0.08, 0.08), 0.6), Vector3(0.2, 0.83, -0.1))
	# asset pack 4 clutter: field radio, med kit / canteen
	PP.add(b, "radio", Vector3(0.62, 0.82, 0.18), -0.4, 0.43)
	PP.add(b, "medkit" if monitor else "canteen", Vector3(0.55, 0.82, -0.2), 0.3, 0.3 if monitor else 0.18)
	if not monitor:
		PP.add(b, "knife", Vector3(-0.3, 0.82, 0.0), 0.0, 0.0, Vector3(0, 0.04, 0.3))
	b.finalize()


func _add_cover(center: Vector3, size: Vector3, rot_y: float, owner_body: Node = null) -> void:
	var rb := Basis(Vector3.UP, rot_y)
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), size.z * 0.5, size.x * 0.5],
		[Vector3(0, 0, -1), Vector3(1, 0, 0), size.z * 0.5, size.x * 0.5],
		[Vector3(1, 0, 0), Vector3(0, 0, 1), size.x * 0.5, size.z * 0.5],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), size.x * 0.5, size.z * 0.5],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var tangent: Vector3 = f[1]
		var half_n: float = f[2]
		var ext: float = f[3]
		var count := maxi(1, int(floor((ext * 2.0 - 0.9) / 1.0)) + 1)
		for i in count:
			var t := 0.0 if count == 1 else lerpf(-ext + 0.45, ext - 0.45, float(i) / float(count - 1))
			var p := center + rb * (n * (half_n + 0.6) + tangent * t)
			var cp := {"pos": Vector3(p.x, 0, p.z), "normal": rb * n, "taken": null, "valid": true, "destroyed": false}
			cover_points.append(cp)
			if owner_body is Destructible:
				owner_body.covers.append(cp)


# ================================================================ layout

func _build_floors() -> void:
	var floor_body := _body(Vector3(0, 0, -5))
	_box_shape(floor_body, Vector3(80, 1, 70), Vector3(0, -0.5, 0))
	_mesh(floor_body, ML.plane(Vector2(80, 70)), M.floor_grid("floor_out", Color(0.13, 0.145, 0.16), Color(0.2, 0.22, 0.25), 0.2), Vector3.ZERO)
	# area overlays (no collision)
	_floor_patch(Vector3(0, 0.004, 14), Vector2(24, 12), M.floor_grid("floor_yard", Color(0.17, 0.18, 0.19), Color(0.27, 0.28, 0.3), 0.15))
	_floor_patch(Vector3(0, 0.004, -3), Vector2(48, 22), M.floor_grid("floor_wh", Color(0.18, 0.2, 0.235), Color(0.31, 0.34, 0.38), 0.4))
	_floor_patch(Vector3(-15.5, 0.004, -22), Vector2(17, 16), M.floor_grid("floor_arm", Color(0.2, 0.2, 0.19), Color(0.3, 0.3, 0.28), 0.35))
	_floor_patch(Vector3(0.5, 0.004, -22), Vector2(15, 16), M.floor_grid("floor_bar", Color(0.22, 0.2, 0.18), Color(0.3, 0.28, 0.25), 0.25))
	_floor_patch(Vector3(16, 0.004, -22), Vector2(16, 16), M.floor_grid("floor_cmd", Color(0.16, 0.19, 0.2), Color(0.26, 0.31, 0.33), 0.35))
	# painted lane markings in the warehouse
	var paint := M.solid(Color(0.75, 0.62, 0.15), 0.7)
	for x in [-9.0, 9.0]:
		_floor_patch(Vector3(x, 0.007, -3), Vector2(0.15, 20), paint)
	# hazard stripes at doorways
	for d in [Vector3(0, 0, 8), Vector3(8.25, 0, 8), Vector3(-13.5, 0, -14), Vector3(2.5, 0, -14), Vector3(16.5, 0, -14)]:
		_floor_patch(d + Vector3(0, 0.008, 0), Vector2(3.4, 0.9), M.hazard_stripes())
	# oil stains
	for i in 14:
		var p := Vector3(randf_range(-22, 22), 0.006, randf_range(-28, 18))
		var s := _floor_patch(p, Vector2.ONE * randf_range(0.8, 2.4), M.blot("oil", Color(0.02, 0.02, 0.02, 0.45)))
		s.rotation.y = randf() * TAU


func _floor_patch(pos: Vector3, size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ML.plane(size)
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _wall_x(z: float, x0: float, x1: float, gaps: Array = []) -> void:
	var segs := _segments(x0, x1, gaps)
	for s in segs:
		var seg_len: float = s[1] - s[0]
		if seg_len < 0.05:
			continue
		_wall_piece(Vector3((s[0] + s[1]) * 0.5, 0, z), Vector3(seg_len, WALL_H, WALL_T))


func _wall_z(x: float, z0: float, z1: float, gaps: Array = []) -> void:
	var segs := _segments(z0, z1, gaps)
	for s in segs:
		var seg_len: float = s[1] - s[0]
		if seg_len < 0.05:
			continue
		_wall_piece(Vector3(x, 0, (s[0] + s[1]) * 0.5), Vector3(WALL_T, WALL_H, seg_len))


func _segments(a: float, b: float, gaps: Array) -> Array:
	var out: Array = []
	var cur := a
	for g in gaps:
		out.append([cur, float(g[0])])
		cur = float(g[1])
	out.append([cur, b])
	return out


func _wall_piece(pos: Vector3, size: Vector3) -> void:
	var b := solid_box(pos, size, _mat_wall)
	_mesh(b, ML.box(Vector3(size.x + 0.04, 0.25, size.z + 0.04)), _mat_wall_trim, Vector3(0, 0.125, 0))
	_mesh(b, ML.box(Vector3(size.x + 0.06, 0.08, size.z + 0.06)), _mat_wall_trim, Vector3(0, size.y + 0.04, 0))


func _build_walls() -> void:
	# yard
	_wall_x(20, -12.2, 12.2)
	_wall_z(-12, 8, 20)
	_wall_z(12, 8, 20)
	# warehouse south wall with two entries
	_wall_x(8, -24.2, 24.2, [[-1.7, 1.7], [6.6, 9.9]])
	# outer walls
	_wall_z(-24, -30, 8)
	_wall_z(24, -30, 8)
	_wall_x(-30, -24.2, 24.2)
	# warehouse north wall
	_wall_x(-14, -24, 24, [[-15.2, -11.8], [0.8, 4.2], [14.8, 18.2]])
	# north wing partitions
	_wall_z(-7, -30, -14, [[-24.2, -20.8]])
	_wall_z(8, -30, -14, [[-21.2, -17.8]])


func _build_yard() -> void:
	vehicle(Vector3(-7.5, 0, 14.5), 0.08)
	sandbags(Vector3(3.5, 0, 10.6), 3.0, 0.0)
	sandbags(Vector3(-3.2, 0, 11.2), 2.5, 0.25)
	crate(Vector3(8.5, 0, 16.5), Vector3(1.2, 1.0, 1.2), 0.3)
	crate(Vector3(9.8, 0, 17.6), Vector3(1.0, 0.8, 1.0), -0.2)
	crate_stack(Vector3(9.5, 0, 12.5), 0.1)
	barrel(Vector3(-10.8, 0, 9.2), Color(0.25, 0.3, 0.42))
	barrel(Vector3(-10.9, 0, 10.0), Color(0.25, 0.3, 0.42))
	barrier(Vector3(5.5, 0, 18.4), 0.0)
	ammo_crates.append(Vector3(-2.5, 0, 15.5))


func _build_warehouse() -> void:
	container(Vector3(-18.5, 0, -7.5), 0.0, Color(0.5, 0.22, 0.14))
	container(Vector3(18.5, 0, -10.2), PI * 0.5, Color(0.2, 0.3, 0.4))
	container(Vector3(6.5, 0, -9.5), PI * 0.5, Color(0.28, 0.36, 0.25))
	# defensive line facing the south entrance
	sandbags(Vector3(0, 0, 3.6), 4.0, 0.0)
	sandbags(Vector3(-3.0, 0, 3.0), 2.0, -0.6)
	barrier(Vector3(8.0, 0, 4.2), 0.0)
	# crate cover field
	crate(Vector3(-6.5, 0, 0.5), Vector3(1.4, 1.1, 1.4), 0.15)
	crate(Vector3(-11.5, 0, -4.5), Vector3(1.2, 1.0, 2.2), 0.0)
	crate(Vector3(11.5, 0, -2.0), Vector3(2.2, 1.0, 1.2), 0.1)
	crate(Vector3(3.0, 0, -4.0), Vector3(1.4, 1.1, 1.4), -0.3)
	crate(Vector3(-2.0, 0, -9.0), Vector3(2.4, 1.0, 1.2), 0.0)
	crate(Vector3(14.5, 0, 2.5), Vector3(1.2, 1.0, 1.2), 0.4)
	crate_stack(Vector3(-10.5, 0, 4.5), 0.2)
	crate_stack(Vector3(4.5, 0, 0.5), -0.15)
	crate_stack(Vector3(-4.5, 0, -5.5), 0.35)
	barrier(Vector3(-15.0, 0, 2.0), 0.0)
	barrier(Vector3(15.5, 0, -4.0), PI * 0.5)
	barrier(Vector3(-6.0, 0, -12.0), 0.0)
	# barrels
	for p in [Vector3(21.5, 0, 6.0), Vector3(22.3, 0, 6.4), Vector3(21.8, 0, 5.2)]:
		barrel(p, Color(0.55, 0.2, 0.12))
	for p in [Vector3(-21.6, 0, 6.2), Vector3(-22.3, 0, 5.4), Vector3(-21.5, 0, -12.2), Vector3(-22.4, 0, -12.6)]:
		barrel(p, Color(0.28, 0.32, 0.2))
	rack(Vector3(-21.0, 0, 1.0), PI * 0.5, 3.0)
	rack(Vector3(23.2, 0, -1.0), PI * 0.5, 3.0)
	ammo_crates.append(Vector3(-20.0, 0, -2.0))


func _build_armory() -> void:
	rack(Vector3(-20.0, 0, -29.3), 0.0, 5.0)
	rack(Vector3(-13.0, 0, -29.3), 0.0, 5.0)
	rack(Vector3(-23.3, 0, -24.0), PI * 0.5, 4.0)
	crate(Vector3(-15.0, 0, -20.0), Vector3(2.2, 1.0, 1.2), 0.0)
	crate(Vector3(-11.0, 0, -25.5), Vector3(1.2, 1.0, 1.2), 0.25)
	crate(Vector3(-19.5, 0, -24.0), Vector3(1.2, 1.0, 1.4), 0.0)
	desk(Vector3(-10.0, 0, -16.2), 0.0, false)
	barrier(Vector3(-18.5, 0, -17.0), 0.0)
	ammo_crates.append(Vector3(-21.5, 0, -16.5))


func _build_barracks() -> void:
	var frame := M.painted_metal("bunk", Color(0.25, 0.28, 0.22))
	var mattress := M.fabric("mattress", Color(0.38, 0.38, 0.32))
	for p in [Vector3(-4.5, 0, -27.5), Vector3(-1.0, 0, -27.5), Vector3(5.5, 0, -27.5), Vector3(-4.5, 0, -18.0), Vector3(5.5, 0, -18.0)]:
		var b := solid_box(p, Vector3(0.95, 1.7, 2.0), frame)
		b.get_child(1).visible = false
		for y in [0.45, 1.3]:
			_mesh(b, ML.box(Vector3(0.95, 0.06, 2.0)), frame, Vector3(0, y, 0))
			_mesh(b, ML.box(Vector3(0.85, 0.14, 1.9)), mattress, Vector3(0, y + 0.1, 0))
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				_mesh(b, ML.box(Vector3(0.05, 1.7, 0.05)), frame, Vector3(sx * 0.45, 0.85, sz * 0.97))
	# lockers along the north wall
	var locker := M.painted_metal("locker", Color(0.32, 0.36, 0.38))
	for i in 6:
		var b := solid_box(Vector3(-5.6 + i * 0.75 + 4.0, 0, -29.4), Vector3(0.7, 2.0, 0.5), locker)
		_mesh(b, ML.box(Vector3(0.02, 0.1, 0.01)), _mat_metal, Vector3(0.25, 1.1, -0.26))
	crate(Vector3(1.0, 0, -22.5), Vector3(1.4, 0.9, 1.0), 0.1)
	sandbags(Vector3(2.0, 0, -15.6), 2.5, 0.0, 3)


func _build_command() -> void:
	desk(Vector3(11.5, 0, -27.5), 0.0)
	desk(Vector3(14.0, 0, -27.5), 0.0)
	desk(Vector3(21.5, 0, -20.0), -PI * 0.5)
	# central map table
	var t := solid_box(Vector3(16.0, 0, -22.0), Vector3(2.6, 0.9, 1.6), M.wood("table", Color(0.35, 0.27, 0.18)), 0.0, true, "wood")
	var map_tex := M.noise_texture([Color(0.45, 0.5, 0.36), Color(0.62, 0.6, 0.45), Color(0.35, 0.45, 0.5)], [0.0, 0.5, 1.0], 0.03, 17)
	var map_mat := StandardMaterial3D.new()
	map_mat.albedo_texture = map_tex
	map_mat.roughness = 0.9
	_mesh(t, ML.box(Vector3(2.2, 0.01, 1.3)), map_mat, Vector3(0, 0.905, 0))
	t.finalize()
	# server racks with status LEDs
	for i in 4:
		var r := solid_box(Vector3(23.3, 0, -28.5 + i * 0.9), Vector3(0.6, 2.1, 0.8), M.solid(Color(0.08, 0.08, 0.09), 0.5, 0.4), PI * 0.5)
		for j in 5:
			var col := Color(0.2, 0.9, 0.3) if (i + j) % 3 != 0 else Color(0.95, 0.5, 0.1)
			_mesh(r, ML.box(Vector3(0.03, 0.03, 0.02)), M.emissive("led_%s" % col.to_html(), col, 4.0), Vector3(0.2, 0.4 + j * 0.3, -0.41))
	sandbags(Vector3(11.0, 0, -16.5), 2.5, 0.4, 3)
	crate(Vector3(19.5, 0, -16.0), Vector3(1.2, 1.0, 1.2), 0.0)


## Visual-only architecture stays outside navigation and collision geometry.
func _build_set_dressing() -> void:
	var steel := M.painted_metal("architecture", Color(0.16, 0.21, 0.24))
	var paint := M.solid(Color(0.72, 0.60, 0.32), 0.85)
	# Wall pilasters, inset service bands and conduit give the perimeter scale.
	for x in [-23.73, 23.73]:
		for z in range(-28, 8, 4):
			_mesh(self, ML.box(Vector3(0.16, 2.6, 0.24)), steel, Vector3(x, 1.3, z))
		_mesh(self, ML.box(Vector3(0.035, 0.16, 37.5)), paint, Vector3(x, 0.85, -11))
		_mesh(self, ML.cylinder(0.035, 0.035, 37.5, 8), steel, Vector3(x, 2.25, -11), Vector3(PI / 2.0, 0, 0))
	for z in [19.76, -29.76]:
		var span := 23.5 if z > 0 else 47.5
		_mesh(self, ML.box(Vector3(span, 0.15, 0.025)), paint, Vector3(0, 0.85, z))
	# Painted loading bays, dashed approach lane and a deployment pad.
	for x in [-4.0, 4.0]:
		for z in range(12, 19, 2):
			_floor_patch(Vector3(x, 0.012, z), Vector2(0.10, 0.8), paint)
	for x in [-16.0, -8.0, 8.0, 16.0]:
		_floor_patch(Vector3(x, 0.012, 5.5), Vector2(4.0, 0.08), paint)
		_floor_patch(Vector3(x - 2.0, 0.012, 4.6), Vector2(0.08, 1.8), paint)
	# Signs face the approach so room identity is readable in first person.
	for entry in [[Vector3(-17.5, 1.95, -13.77), "01 / ARMORY"],
			[Vector3(-2.0, 1.95, -13.77), "02 / BARRACKS"],
			[Vector3(12.0, 1.95, -13.77), "03 / COMMAND"],
			[Vector3(-4.5, 1.95, 8.23), "DEPOT / 07"]]:
		var pos: Vector3 = entry[0]
		_mesh(self, ML.box(Vector3(3.2, 0.58, 0.035)), steel, pos)
		var label := Label3D.new()
		label.text = entry[1]
		label.font_size = 48
		label.pixel_size = 0.004
		label.modulate = Color(0.91, 0.85, 0.66)
		label.outline_size = 0
		label.position = pos + Vector3(0, 0, 0.025)
		add_child(label)
	# Recessed drainage grates break up the open concrete apron.
	for x in [-10.0, 10.0]:
		_floor_patch(Vector3(x, 0.013, 13.8), Vector2(0.45, 3.0), steel)
		for i in 15:
			_floor_patch(Vector3(x, 0.015, 12.45 + i * 0.19), Vector2(0.39, 0.045), _mat_wall_trim)


func _build_lights() -> void:
	var warm := Color(1.0, 0.82, 0.6)
	var cool := Color(0.75, 0.85, 1.0)
	var spots := [
		[Vector3(-4, 3.2, 14), cool, 14.0, true], [Vector3(6, 3.2, 14), cool, 12.0, false],
		[Vector3(-14, 3.4, -2), warm, 13.0, true], [Vector3(0, 3.4, -2), warm, 13.0, true],
		[Vector3(14, 3.4, -2), warm, 13.0, false], [Vector3(-8, 3.4, -10), warm, 10.0, false],
		[Vector3(12, 3.4, 4), warm, 10.0, false],
		[Vector3(-15, 3.2, -22), warm, 12.0, true], [Vector3(0.5, 3.2, -22), Color(1.0, 0.75, 0.5), 11.0, false],
		[Vector3(16, 3.2, -22), Color(0.7, 0.9, 1.0), 12.0, true],
	]
	for s in spots:
		var l := OmniLight3D.new()
		l.position = s[0]
		l.light_color = s[1]
		l.omni_range = s[2]
		l.light_energy = 1.25
		l.shadow_enabled = s[3]
		l.omni_attenuation = 1.2
		l.light_volumetric_fog_energy = 1.2
		l.shadow_blur = 1.4
		add_child(l)
		lights.append({"light": l, "shadow": s[3]})
		var fixture := MeshInstance3D.new()
		fixture.mesh = ML.box(Vector3(0.9, 0.06, 0.25))
		fixture.material_override = M.emissive("lamp_%s" % (s[1] as Color).to_html(), s[1], 3.0)
		fixture.position = s[0] + Vector3(0, 0.3, 0)
		fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fixture)
	# red emergency light in the command post
	var red := OmniLight3D.new()
	red.position = Vector3(22, 2.0, -15.5)
	red.light_color = Color(1.0, 0.15, 0.1)
	red.light_energy = 1.2
	red.omni_range = 6.0
	add_child(red)


func _define_enemies() -> void:
	enemy_spawns = [
		{"pos": Vector3(-14, 0, -2), "yaw": 0.0, "patrol": [Vector3(-14, 0, -2), Vector3(-14, 0, 5.5), Vector3(-19, 0, 4)]},
		{"pos": Vector3(8, 0, -5.5), "yaw": 0.0, "patrol": [Vector3(8, 0, -5.5), Vector3(13.5, 0, -6), Vector3(13, 0, 5.5)]},
		{"pos": Vector3(0.5, 0, 2.2), "yaw": PI, "patrol": []},
		{"pos": Vector3(19.5, 0, -2), "yaw": PI * 0.5, "patrol": [Vector3(19.5, 0, -2), Vector3(19.5, 0, 5.5)]},
		{"pos": Vector3(-3, 0, -11), "yaw": 0.0, "patrol": [Vector3(-3, 0, -11), Vector3(11, 0, -12.5)]},
		{"pos": Vector3(-15, 0, -23), "yaw": PI, "patrol": []},
		{"pos": Vector3(-11, 0, -18), "yaw": 0.0, "patrol": [Vector3(-11, 0, -18), Vector3(-19, 0, -27), Vector3(-12, 0, -28)]},
		{"pos": Vector3(1.5, 0, -20), "yaw": 0.0, "patrol": [Vector3(1.5, 0, -20), Vector3(1.5, 0, -26), Vector3(-3, 0, -16.5)]},
		{"pos": Vector3(16, 0, -25.5), "yaw": PI * 0.75, "patrol": []},
		{"pos": Vector3(20, 0, -17), "yaw": 0.0, "patrol": [Vector3(20, 0, -17), Vector3(11, 0, -24), Vector3(18, 0, -28.5)]},
	]


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


## Floating dust motes catching the work lights.
func _build_dust() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.9, 0.85, 0.75, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.75)
	mat.emission_energy_multiplier = 0.25
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.018, 0.018)
	for area in [[Vector3(0, 1.4, -3), Vector3(22, 1.2, 10)], [Vector3(0, 1.4, 14), Vector3(11, 1.2, 5)],
			[Vector3(-15, 1.4, -22), Vector3(8, 1.2, 7)], [Vector3(16, 1.4, -22), Vector3(7, 1.2, 7)]]:
		var p := CPUParticles3D.new()
		p.amount = 260
		p.lifetime = 9.0
		p.preprocess = 9.0
		p.mesh = mesh
		p.material_override = mat
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = area[1]
		p.direction = Vector3(1, 0.2, 0.3)
		p.spread = 180.0
		p.initial_velocity_min = 0.02
		p.initial_velocity_max = 0.12
		p.gravity = Vector3(0, -0.01, 0)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = area[0]
		add_child(p)
		_dust.append(p)


## Scales light shadows and ambient particles with the graphics preset.
## A room: reflections come from the room itself (box-projected) instead of
## the open sky, and the sky's ambient fill is cut down to what leaks indoors.
func _interior_probe(center: Vector3, size: Vector3, rot: float = 0.0) -> void:
	var rp := ReflectionProbe.new()
	rp.position = center + Vector3(0, size.y * 0.5, 0)
	rp.rotation.y = rot
	rp.size = size
	rp.interior = true
	rp.box_projection = true
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	rp.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	rp.ambient_color = Color(0.55, 0.57, 0.6)
	rp.ambient_color_energy = 0.36
	rp.blend_distance = 0.4
	rp.max_distance = maxf(size.x, size.z) * 1.5
	add_child(rp)
	interior_probes.append(rp)


func apply_quality(q: int) -> void:
	for entry in lights:
		var l: OmniLight3D = entry.light
		l.shadow_enabled = (q == 2) or (q == 1 and entry.shadow)
		if not l.distance_fade_enabled:
			l.distance_fade_enabled = true   # only very far away
			l.distance_fade_begin = 70.0
			l.distance_fade_length = 15.0
		l.distance_fade_shadow = 24.0 if q < 2 else 34.0   # far lights skip the shadow pass
	for p in _dust:
		p.visible = q >= 1
		p.emitting = q >= 1
		p.amount = 260 if q == 2 else 120


# ================================================================ destruction

## A prop was destroyed: drop its cover points and radar footprint and
## re-bake navigation so agents can path through the gap.
func register_prop(p: Node) -> int:
	props.append(p)
	return props.size() - 1


func prop_by_id(id: int):
	if id < 0 or id >= props.size() or not is_instance_valid(props[id]):
		return null
	return props[id]


func on_prop_destroyed(prop: Node) -> void:
	props_destroyed += 1
	if int(prop.get("net_id")) >= 0:
		destroyed_ids.append(int(prop.net_id))
	for c in prop.covers:
		c.valid = false
		c.destroyed = true
		c.taken = null
		cover_points.erase(c)
	for r in prop.rects:
		map_rects.erase(r)
	_nav_dirty = true


func _physics_process(_delta: float) -> void:
	if _nav_dirty and nav_region != null and not nav_region.is_baking():
		_nav_dirty = false
		# destroyed bodies are freed at the end of the frame they break in;
		# baking a tick later parses the world without them
		nav_region.bake_navigation_mesh(true)


# ================================================================ cover queries

func _validate_cover() -> void:
	_cover_validated = true
	var map := get_world_3d().navigation_map
	for c in cover_points:
		var p: Vector3 = c.pos
		var snapped := NavigationServer3D.map_get_closest_point(map, p)
		c.valid = not c.destroyed and Vector2(snapped.x - p.x, snapped.z - p.z).length() < 0.35


func is_covered(pos: Vector3, threat: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.85, 0), threat + Vector3(0, 1.3, 0), Layers.WORLD)
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and (hit.position as Vector3).distance_to(pos) < 2.0


func is_cover_good(c: Dictionary, threat: Vector3) -> bool:
	var p: Vector3 = c.pos
	return p.distance_to(threat) > 4.0 and is_covered(p, threat)


## retreat: only cover further from the threat than the agent is now, ideally ~20 m out.
func find_cover(agent: Node3D, threat: Vector3, retreat: bool = false):
	if not _cover_validated:
		_validate_cover()
	var best = null
	var best_score := INF
	var my := agent.global_position
	var my_threat_dist := my.distance_to(threat)
	for c in cover_points:
		if not c.valid:
			continue
		var taker = c.taken
		if taker != null and taker != agent and is_instance_valid(taker) and not taker.is_dead:
			continue
		var p: Vector3 = c.pos
		var d_self := p.distance_to(my)
		if d_self > 16.0:
			continue
		var d_threat := p.distance_to(threat)
		if d_threat < 5.0 or d_threat > 26.0:
			continue
		if retreat and d_threat < my_threat_dist + 2.0:
			continue
		var to_threat := threat - p
		to_threat.y = 0.0
		if to_threat.normalized().dot(-(c.normal as Vector3)) < 0.35:
			continue
		var score := d_self + absf(d_threat - (20.0 if retreat else 12.0)) * 0.6
		if d_threat < my_threat_dist - 4.0:
			score += 6.0
		if score < best_score and is_covered(p, threat):
			best = c
			best_score = score
	if best != null:
		best.taken = agent
	return best
