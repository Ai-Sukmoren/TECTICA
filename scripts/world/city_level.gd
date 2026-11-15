extends "res://scripts/world/town_level.gd"
## NEIGHBOURHOOD: a city block about 42 x 39 m, built from a third-party
## modular low-poly scene (local only): five-storey brick apartment blocks,
## streets with kerbs and crossings, street trees and lamps, a car park,
## road barriers and cones. Zombie Survival and Deathmatch.
## Collision comes from the model's own meshes; spawns from the walkable
## street level of the baked navigation mesh.

const CITY_GLB := "res://assets/thirdparty/neighbourhood_city/neighbourhood_city.glb"
## The model's footprint (game x / z), from the source scene's bounds.
const MIN_X := -18.3
const MAX_X := 23.7
const MIN_Z := -21.2
const MAX_Z := 17.9
const MAX_LAMPS := 16

var _walkable: Array = []   # street-level points on the navigation mesh
static var _city_nav: NavigationMesh


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

	# ground under everything (the model's own pavement sits on it)
	var g := _body(Vector3.ZERO)
	_box_shape(g, Vector3(200, 1, 200), Vector3(0, -0.5, 0))
	_mesh(g, ML.plane(Vector2(200, 200)), M.concrete("city_ground", Color(0.22, 0.22, 0.23), 0.5), Vector3(0, -0.01, 0))
	if ResourceLoader.exists(CITY_GLB):
		_build_city()
	_build_edges()
	_bake_navigation()
	_collect_walkable()
	_define_mode()
	seed(Time.get_ticks_usec())


## The scene, solid wherever it has geometry, with lights on its street lamps
## and cover behind its barricades and barriers.
func _build_city() -> void:
	var inst := (load(CITY_GLB) as PackedScene).instantiate() as Node3D
	var body := _body(Vector3.ZERO)
	body.add_child(inst)
	var lamps := 0
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != inst:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var aabb: AABB = xf * mi.mesh.get_aabb()
		var nm := String(mi.name)
		# small clutter (balcony plants, AC grilles, lamp heads) gets no collision
		if aabb.size.x * aabb.size.y * aabb.size.z > 0.02 or aabb.size.y > 1.5:
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_trimesh_shape()
			cs.transform = xf
			body.add_child(cs)
		if nm.begins_with("streetLights") and lamps < MAX_LAMPS and aabb.size.y > 2.0:
			lamps += 1
			var l := OmniLight3D.new()
			l.position = Vector3(aabb.get_center().x, aabb.end.y - 0.4, aabb.get_center().z)
			l.light_color = Color(1.0, 0.82, 0.55)
			l.omni_range = 11.0
			l.omni_attenuation = 1.1
			add_child(l)
			lamp_lights.append({"light": l, "base": 2.0, "group": "street", "flicker": lamps % 6 == 3})
			lights.append({"light": l, "shadow": lamps % 4 == 0})
		if nm.begins_with("SM_Barricade") or nm.begins_with("SM_TrafficBarrier") or nm.begins_with("SM_Verticade"):
			if aabb.size.y < 1.6:
				_add_cover(aabb.get_center() * Vector3(1, 0, 1), aabb.size, 0.0, body)
				map_rects.append({"c": Vector2(aabb.get_center().x, aabb.get_center().z), "s": Vector2(aabb.size.x, aabb.size.z), "r": 0.0, "tall": false})
		elif aabb.size.y > 6.0:
			map_rects.append({"c": Vector2(aabb.get_center().x, aabb.get_center().z), "s": Vector2(aabb.size.x, aabb.size.z), "r": 0.0, "tall": true})


## Invisible walls just outside the model's edge keep everyone in the block.
func _build_edges() -> void:
	var cx := (MIN_X + MAX_X) * 0.5
	var cz := (MIN_Z + MAX_Z) * 0.5
	var w := MAX_X - MIN_X
	var d := MAX_Z - MIN_Z
	for e in [[Vector3(cx, 0, MIN_Z - 0.3), Vector3(w + 1.0, 6, 0.6)], [Vector3(cx, 0, MAX_Z + 0.3), Vector3(w + 1.0, 6, 0.6)],
			[Vector3(MIN_X - 0.3, 0, cz), Vector3(0.6, 6, d + 1.0)], [Vector3(MAX_X + 0.3, 0, cz), Vector3(0.6, 6, d + 1.0)]]:
		var b := _body(e[0])
		_box_shape(b, e[1], Vector3(0, 3, 0))


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
	nm.filter_baking_aabb = AABB(Vector3(MIN_X, -2, MIN_Z), Vector3(MAX_X - MIN_X, 6, MAX_Z - MIN_Z))
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
	return p.x > MIN_X + 1 and p.x < MAX_X - 1 and p.z > MIN_Z + 1 and p.z < MAX_Z - 1


func _define_mode() -> void:
	enemy_spawns.clear()
	zombie_spawns.clear()
	var centre := Vector3((MIN_X + MAX_X) * 0.5, 0, (MIN_Z + MAX_Z) * 0.5)
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
	var pool := _walkable.filter(func(w): return (w as Vector3).distance_to(best) > 12.0)
	for i in mini(40, pool.size()):
		zombie_spawns.append(pool[rng.randi() % pool.size()])
	ammo_crates.append(best + Vector3(1.5, 0, 0))


func _process(_delta: float) -> void:
	pass
