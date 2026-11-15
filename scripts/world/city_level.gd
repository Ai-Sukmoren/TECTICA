extends "res://scripts/world/town_level.gd"
## NEIGHBOURHOOD: one city block built from a third-party modular low-poly scene
## (local only): five-storey brick apartment blocks, streets with kerbs and
## crossings, street trees and lamps, a car park, road barriers and cones.
## Zombie Survival and Deathmatch.
##
## The source block (42 x 39 m) is drawn SCALE times larger so its streets and
## storeys feel full size around the operator; an asphalt ring road runs round
## it and a tall board fence closes the map in. Each source mesh is drawn as one
## MultiMesh. Collision comes from the meshes; spawns from the navigation mesh.

const CITY_GLB := "res://assets/thirdparty/neighbourhood_city/neighbourhood_city.glb"
## The source block's footprint (model x / z), from its bounds.
const SRC_MIN := Vector2(-18.3, -21.2)
const SRC_MAX := Vector2(23.7, 17.9)
## The whole block is drawn this much larger than the source model.
const SCALE := 1.4
## Ring road between the block and the fence.
const RING := 9.0
const FENCE_H := 2.6
const MAX_LAMPS := 16

var _walkable: Array = []   # street-level points on the navigation mesh
## Play area (world x / z): inside the fence.
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
static var _city_nav: NavigationMesh

## Source pieces: {mesh, xf (scaled, model space), aabb (model space), name, solid}
var _items: Array = []
## mesh -> Array[Transform3D] of every placement, drawn as MultiMeshes at the end.
var _draws: Dictionary = {}
## item index -> ConcavePolygonShape3D in model space.
var _shapes: Dictionary = {}
var _lamps := 0


func build() -> void:
	seed(4711)
	Terrain.clear()
	_mat_wall = M.concrete("city_wall", Color(0.5, 0.48, 0.45), 0.6)
	_mat_wall_trim = M.solid(Color(0.2, 0.2, 0.2), 0.8)
	_mat_crate = M.wood("crate", Color(0.46, 0.4, 0.28))
	_mat_crate_frame = M.wood("crate_frame", Color(0.34, 0.29, 0.2))
	_mat_sandbag = M.fabric("sandbag", Color(0.52, 0.47, 0.36), 4.0)
	_mat_concrete = M.concrete("barrier", Color(0.58, 0.57, 0.54), 0.6)
	_mat_metal = M.painted_metal("metal_grey", Color(0.3, 0.32, 0.33))
	_mat_roof = Nature.roof_material(Color(0.2, 0.18, 0.17))
	Nature.fade_materials = Nature.fade_materials.filter(func(m): return m == _mat_roof)
	FX.ground_surface = "stone"
	Water.clear()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)

	var half := (SRC_MAX - SRC_MIN) * SCALE * 0.5
	_lo = -half - Vector2(RING, RING)
	_hi = half + Vector2(RING, RING)
	var size := (_hi - _lo) + Vector2(60, 60)
	var g := _body(Vector3.ZERO)
	_box_shape(g, Vector3(size.x, 1, size.y), Vector3(0, -0.5, 0))
	_mesh(g, ML.plane(size), M.concrete("city_ground", Color(0.2, 0.2, 0.21), 0.5), Vector3(0, -0.01, 0))
	if ResourceLoader.exists(CITY_GLB):
		_read_source()
		var body := _body(Vector3.ZERO)
		var c := (SRC_MIN + SRC_MAX) * 0.5 * SCALE
		var at := Transform3D(Basis.IDENTITY, Vector3(-c.x, 0, -c.y))
		for idx in _items.size():
			_place(idx, at, body)
		_flush_draws()
	_build_ring_road()
	_build_fence()
	_build_edges()
	_bake_navigation()
	_collect_walkable()
	_define_mode()
	seed(Time.get_ticks_usec())


## Every mesh of the source scene, its transform in model space scaled up.
func _read_source() -> void:
	var inst := (load(CITY_GLB) as PackedScene).instantiate() as Node3D
	var scale_xf := Transform3D(Basis.from_scale(Vector3.ONE * SCALE), Vector3.ZERO)
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != inst:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		xf = scale_xf * xf
		var aabb: AABB = xf * mi.mesh.get_aabb()
		# small clutter (balcony plants, AC grilles, lamp heads) gets no collision
		var solid := aabb.size.x * aabb.size.y * aabb.size.z > 0.04 or aabb.size.y > 2.0
		_items.append({"mesh": mi.mesh, "xf": xf, "aabb": aabb, "name": String(mi.name), "solid": solid})
	inst.free()


func _place(idx: int, at: Transform3D, body: StaticBody3D) -> void:
	var it: Dictionary = _items[idx]
	var xf: Transform3D = at * (it.xf as Transform3D)
	if not _draws.has(it.mesh):
		_draws[it.mesh] = []
	(_draws[it.mesh] as Array).append(xf)
	var aabb: AABB = at * (it.aabb as AABB)
	var nm: String = it.name
	if it.solid:
		if not _shapes.has(idx):
			var faces: PackedVector3Array = (it.mesh as Mesh).get_faces()
			var mxf: Transform3D = it.xf
			for f in faces.size():
				faces[f] = mxf * faces[f]
			var s := ConcavePolygonShape3D.new()
			s.set_faces(faces)
			_shapes[idx] = s
		var cs := CollisionShape3D.new()
		cs.shape = _shapes[idx]
		cs.transform = at
		body.add_child(cs)
	if nm.begins_with("streetLights") and _lamps < MAX_LAMPS and aabb.size.y > 2.0 and _lamps_spaced(aabb.get_center()):
		_lamps += 1
		var l := OmniLight3D.new()
		l.position = Vector3(aabb.get_center().x, aabb.end.y - 0.4, aabb.get_center().z)
		l.light_color = Color(1.0, 0.82, 0.55)
		l.omni_range = 11.0
		l.omni_attenuation = 1.1
		add_child(l)
		lamp_lights.append({"light": l, "base": 2.0, "group": "street", "flicker": _lamps % 6 == 3})
		lights.append({"light": l, "shadow": _lamps % 5 == 0})
	if nm.begins_with("SM_Barricade") or nm.begins_with("SM_TrafficBarrier") or nm.begins_with("SM_Verticade"):
		if aabb.size.y < 1.6:
			_add_cover(aabb.get_center() * Vector3(1, 0, 1), aabb.size, 0.0, body)
			map_rects.append({"c": Vector2(aabb.get_center().x, aabb.get_center().z), "s": Vector2(aabb.size.x, aabb.size.z), "r": 0.0, "tall": false})
	elif aabb.size.y > 6.0:
		map_rects.append({"c": Vector2(aabb.get_center().x, aabb.get_center().z), "s": Vector2(aabb.size.x, aabb.size.z), "r": 0.0, "tall": true})


## Lights spread over the whole district instead of all in the first copy.

## Lights spread over the block instead of bunched together.
func _lamps_spaced(p: Vector3) -> bool:
	for e in lamp_lights:
		var l: OmniLight3D = e.light
		if Vector2(l.position.x - p.x, l.position.z - p.z).length() < 10.0:
			return false
	return true


## Asphalt ring road between the block and the fence, kerbs on both edges, dashed centre lines.
func _build_ring_road() -> void:
	var asphalt := M.concrete("city_asphalt", Color(0.11, 0.11, 0.12), 0.85)
	var paint := M.solid(Color(0.85, 0.82, 0.7), 0.6)
	var kerb := M.concrete("city_kerb", Color(0.45, 0.44, 0.42), 0.6)
	var root := Node3D.new()
	root.name = "RingRoad"
	add_child(root)
	var w := _hi.x - _lo.x
	var d := _hi.y - _lo.y
	for side in [-1.0, 1.0]:
		var cz: float = (_lo.y + RING * 0.5) if side < 0 else (_hi.y - RING * 0.5)
		var cx: float = (_lo.x + RING * 0.5) if side < 0 else (_hi.x - RING * 0.5)
		_mesh(root, ML.plane(Vector2(w, RING - 1.0)), asphalt, Vector3(0, 0.004, cz))
		_mesh(root, ML.plane(Vector2(RING - 1.0, d)), asphalt, Vector3(cx, 0.005, 0))
		_mesh(root, ML.box(Vector3(w, 0.15, 0.3)), kerb, Vector3(0, 0.075, cz + side * (RING * 0.5 - 0.2)))
		_mesh(root, ML.box(Vector3(0.3, 0.15, d)), kerb, Vector3(cx + side * (RING * 0.5 - 0.2), 0.075, 0))
		var x := _lo.x + RING
		while x < _hi.x - RING:
			_mesh(root, ML.plane(Vector2(2.4, 0.18)), paint, Vector3(x, 0.01, cz))
			x += 6.0
		var z := _lo.y + RING
		while z < _hi.y - RING:
			_mesh(root, ML.plane(Vector2(0.18, 2.4)), paint, Vector3(cx, 0.01, z))
			z += 6.0


## A tall board fence on posts all round the map, with a rail along the top.
func _build_fence() -> void:
	var boards := M.wood("city_fence", Color(0.42, 0.33, 0.24))
	var post_mat := M.wood("city_fence_post", Color(0.3, 0.24, 0.17))
	var root := Node3D.new()
	root.name = "Fence"
	add_child(root)
	var corners := [Vector3(_lo.x, 0, _lo.y), Vector3(_hi.x, 0, _lo.y), Vector3(_hi.x, 0, _hi.y), Vector3(_lo.x, 0, _hi.y)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var l := a.distance_to(b)
		var along := (b - a) / l
		var rot := atan2(along.x, along.z) + PI * 0.5
		var mid := (a + b) * 0.5
		var panel := _mesh(root, ML.box(Vector3(l, FENCE_H, 0.08)), boards, mid + Vector3(0, FENCE_H * 0.5, 0), Vector3(0, rot, 0))
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_mesh(root, ML.box(Vector3(l, 0.1, 0.16)), post_mat, mid + Vector3(0, FENCE_H + 0.05, 0), Vector3(0, rot, 0))
		var n := int(l / 2.4)
		for k in n + 1:
			var p := a + along * (l * k / maxi(n, 1))
			_mesh(root, ML.box(Vector3(0.14, FENCE_H + 0.15, 0.14)), post_mat, p + Vector3(0, (FENCE_H + 0.15) * 0.5, 0))


## One MultiMeshInstance3D per source mesh, holding every copy of it.
func _flush_draws() -> void:
	for mesh in _draws:
		var xfs: Array = _draws[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	_draws.clear()


func _build_edges() -> void:
	var c := (_lo + _hi) * 0.5
	var s := _hi - _lo
	for e in [[Vector3(c.x, 0, _lo.y - 0.3), Vector3(s.x + 1.0, 8, 0.6)], [Vector3(c.x, 0, _hi.y + 0.3), Vector3(s.x + 1.0, 8, 0.6)],
			[Vector3(_lo.x - 0.3, 0, c.y), Vector3(0.6, 8, s.y + 1.0)], [Vector3(_hi.x + 0.3, 0, c.y), Vector3(0.6, 8, s.y + 1.0)]]:
		var b := _body(e[0])
		_box_shape(b, e[1], Vector3(0, 4, 0))


func _bake_navigation() -> void:
	if _city_nav != null:
		nav_region.navigation_mesh = _city_nav.duplicate()
		return
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.45
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nm.filter_baking_aabb = AABB(Vector3(_lo.x, -2, _lo.y), Vector3(_hi.x - _lo.x, 6, _hi.y - _lo.y))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
	_city_nav = nm.duplicate()


## Centres of the navigation mesh's street-level polygons: open, walkable spots.
func _collect_walkable() -> void:
	_walkable.clear()
	var nm := nav_region.navigation_mesh
	if nm == null:
		return
	var verts := nm.get_vertices()
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var c := Vector3.ZERO
		for k in poly:
			c += verts[k]
		c /= poly.size()
		if c.y < 0.6:
			_walkable.append(Vector3(c.x, 0.0, c.z))


func _free(p: Vector3, _margin: float = 0.0) -> bool:
	return p.x > _lo.x + 1 and p.x < _hi.x - 1 and p.z > _lo.y + 1 and p.z < _hi.y - 1


func _define_mode() -> void:
	enemy_spawns.clear()
	zombie_spawns.clear()
	var centre := Vector3((_lo.x + _hi.x) * 0.5, 0, (_lo.y + _hi.y) * 0.5)
	if _walkable.is_empty():
		_walkable = [centre, centre + Vector3(8, 0, 0), centre + Vector3(-8, 0, 0), centre + Vector3(0, 0, 8)]
	var best: Vector3 = _walkable[0]
	for w in _walkable:
		if w.distance_to(centre) < best.distance_to(centre):
			best = w
	if mode == "pvp":
		# spread out: each next spawn is the walkable spot farthest from those chosen
		pvp_spawns = [best]
		for k in 17:
			var far: Vector3 = _walkable[0]
			var far_d := -1.0
			for w in _walkable:
				var d := INF
				for s in pvp_spawns:
					d = minf(d, (w as Vector3).distance_to(s))
				if d > far_d:
					far_d = d
					far = w
			pvp_spawns.append(far)
		player_spawn = pvp_spawns[0]
		ammo_crates.append(best + Vector3(1.5, 0, 0))
		return
	player_spawn = best
	player_yaw = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	# zombies come from the streets around the player, not across the whole district
	var pool := _walkable.filter(func(w): var d := (w as Vector3).distance_to(best); return d > 14.0 and d < 70.0)
	if pool.is_empty():
		pool = _walkable.filter(func(w): return (w as Vector3).distance_to(best) > 12.0)
	for i in mini(40, pool.size()):
		zombie_spawns.append(pool[rng.randi() % pool.size()])
	ammo_crates.append(best + Vector3(1.5, 0, 0))


func _process(_delta: float) -> void:
	pass
