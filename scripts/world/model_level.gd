extends "res://scripts/world/town_level.gd"
## A Zombie Survival / Deathmatch map built from one third-party model (local
## only, not in the repository): WAREHOUSE, BACKROOMS. To add a map, convert
## its model into assets/thirdparty/ and add a CONFIGS entry and a MAPS name.
## The model is converted with Blender, centred on the origin with its lowest
## point at 0. Collision comes from its own meshes; spawns from the largest
## connected walkable area of the baked navigation mesh, so nobody spawns on a
## roof, a crate top or inside a closed-off room.

const MAP_DIR := "res://assets/thirdparty/"
## id -> glb, lights: mesh-name hints that get a lamp, indoor: add soft fill lights,
## floor_only: spawn only near the lowest floor (a flat roof is walkable too).
const CONFIGS := {
	"warehouse": {"glb": "warehouse/warehouse.glb", "lights": [], "indoor": true},
	"backrooms": {"glb": "backrooms/backrooms.glb", "lights": [], "indoor": true, "floor_only": true},
}
const MAX_LAMPS := 24

var map_key := "warehouse"
var _walkable: Array = []
var _lo := Vector3.ZERO
var _hi := Vector3.ZERO
static var _navs := {}


func _init(id: String = "warehouse") -> void:
	map_key = id if CONFIGS.has(id) else "warehouse"


func build() -> void:
	seed(4711)
	Terrain.clear()
	_mat_wall = M.concrete("model_wall", Color(0.5, 0.48, 0.45), 0.6)
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
	var cfg: Dictionary = CONFIGS[map_key]
	var path := MAP_DIR + String(cfg.glb)
	if ResourceLoader.exists(path):
		_build_model(path, cfg)
	else:
		_lo = Vector3(-20, 0, -20)
		_hi = Vector3(20, 4, 20)
	# a catch floor well below the model (out of the navigation bake), in case anyone slips through
	var g := _body(Vector3.ZERO)
	var size := Vector2(_hi.x - _lo.x, _hi.z - _lo.z) + Vector2(20, 20)
	_box_shape(g, Vector3(size.x, 1, size.y), Vector3((_lo.x + _hi.x) * 0.5, _lo.y - 3.5, (_lo.z + _hi.z) * 0.5))
	if not ResourceLoader.exists(path):
		_mesh(g, ML.plane(size), M.concrete("model_ground", Color(0.22, 0.22, 0.23), 0.5), Vector3(0, -0.01, 0))
	_build_edges()
	_bake_navigation()
	_collect_walkable()
	_define_mode()
	seed(Time.get_ticks_usec())


## The model, solid wherever it has geometry, with lamps on its light fittings.
func _build_model(path: String, cfg: Dictionary) -> void:
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	var body := _body(Vector3.ZERO)
	body.add_child(inst)
	var first := true
	var lamps := 0
	var hints: Array = cfg.lights
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
		if first:
			_lo = aabb.position
			_hi = aabb.end
			first = false
		else:
			_lo = _lo.min(aabb.position)
			_hi = _hi.max(aabb.end)
		# small clutter gets no collision
		if aabb.size.x * aabb.size.y * aabb.size.z > 0.02 or aabb.size.y > 1.5 or aabb.size.x > 3.0 or aabb.size.z > 3.0:
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_trimesh_shape()
			cs.transform = xf
			body.add_child(cs)
		var nm := String(mi.name).to_lower()
		if lamps < MAX_LAMPS and hints.any(func(h): return nm.contains(String(h))):
			lamps += 1
			var l := OmniLight3D.new()
			l.position = aabb.get_center() + Vector3(0, minf(aabb.size.y * 0.5, 0.3), 0)
			l.light_color = Color(0.75, 0.9, 1.0)
			l.omni_range = 9.0
			l.omni_attenuation = 1.2
			add_child(l)
			lamp_lights.append({"light": l, "base": 1.6, "group": "lab", "flicker": lamps % 7 == 3})
			lights.append({"light": l, "shadow": lamps % 6 == 0})
		if aabb.size.y > 2.2 and aabb.size.x < 40.0 and aabb.size.z < 40.0:
			map_rects.append({"c": Vector2(aabb.get_center().x, aabb.get_center().z), "s": Vector2(aabb.size.x, aabb.size.z), "r": 0.0, "tall": true})
	if bool(cfg.indoor):
		# indoors: a few soft fill lights spread over the floor so it is never pitch black
		var step := 12.0
		var x := _lo.x + step * 0.5
		while x < _hi.x:
			var z := _lo.z + step * 0.5
			while z < _hi.z:
				var l := OmniLight3D.new()
				l.position = Vector3(x, _lo.y + 2.2, z)
				l.light_color = Color(1.0, 0.92, 0.8)
				l.light_energy = 0.35
				l.omni_range = step
				add_child(l)
				z += step
			x += step


## Invisible walls just outside the model keep everyone in.
func _build_edges() -> void:
	var c := (_lo + _hi) * 0.5
	var s := _hi - _lo
	var h := s.y + 6.0
	for e in [[Vector3(c.x, _lo.y, _lo.z - 0.3), Vector3(s.x + 1.0, h, 0.6)], [Vector3(c.x, _lo.y, _hi.z + 0.3), Vector3(s.x + 1.0, h, 0.6)],
			[Vector3(_lo.x - 0.3, _lo.y, c.z), Vector3(0.6, h, s.z + 1.0)], [Vector3(_hi.x + 0.3, _lo.y, c.z), Vector3(0.6, h, s.z + 1.0)]]:
		var b := _body(e[0])
		_box_shape(b, e[1], Vector3(0, h * 0.5, 0))


func _bake_navigation() -> void:
	if _navs.has(map_key):
		nav_region.navigation_mesh = (_navs[map_key] as NavigationMesh).duplicate()
		return
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nm.filter_baking_aabb = AABB(_lo - Vector3(0, 1, 0), _hi - _lo + Vector3(0, 2, 0))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
	_navs[map_key] = nm.duplicate()


## Centres of the largest connected group of navigation polygons: the map's
## real walkable area (roofs, crate tops and sealed rooms are islands, left out).
func _collect_walkable() -> void:
	_walkable.clear()
	var nm := nav_region.navigation_mesh
	if nm == null or nm.get_polygon_count() == 0:
		return
	var verts := nm.get_vertices()
	var n := nm.get_polygon_count()
	var centres: Array = []
	var by_vert := {}
	for i in n:
		var poly := nm.get_polygon(i)
		var c := Vector3.ZERO
		for k in poly:
			c += verts[k]
			# polygons touch where they share a vertex position
			var key := Vector3i((verts[k] * 20.0).round())
			if not by_vert.has(key):
				by_vert[key] = []
			(by_vert[key] as Array).append(i)
		centres.append(c / poly.size())
	var floor_only := bool(CONFIGS[map_key].get("floor_only", false))
	# the floor is the lowest walkable surface (the model may reach below it)
	var floor_y := INF
	for c in centres:
		floor_y = minf(floor_y, (c as Vector3).y)
	var seen := {}
	for s0 in n:
		if seen.has(s0) or (floor_only and (centres[s0] as Vector3).y > floor_y + 1.0):
			continue
		var group: Array = []
		seen[s0] = true
		var queue: Array = [s0]
		while not queue.is_empty():
			var i: int = queue.pop_back()
			group.append(centres[i])
			for k in nm.get_polygon(i):
				for j in by_vert[Vector3i((verts[k] * 20.0).round())]:
					if not seen.has(j):
						seen[j] = true
						queue.append(j)
		if group.size() > _walkable.size():
			_walkable = group


func _free(p: Vector3, _margin: float = 0.0) -> bool:
	return p.x > _lo.x + 1 and p.x < _hi.x - 1 and p.z > _lo.z + 1 and p.z < _hi.z - 1


func _define_mode() -> void:
	enemy_spawns.clear()
	zombie_spawns.clear()
	# the player starts at the walkable spot nearest the middle of the walkable area
	var start := Vector3.ZERO
	for w in _walkable:
		start += w
	start = start / maxf(1.0, _walkable.size()) if not _walkable.is_empty() else Vector3((_lo.x + _hi.x) * 0.5, _lo.y, (_lo.z + _hi.z) * 0.5)
	if _walkable.is_empty():
		_walkable = [start, start + Vector3(4, 0, 0), start + Vector3(-4, 0, 0), start + Vector3(0, 0, 4)]
	var best: Vector3 = _walkable[0]
	for w in _walkable:
		if (w as Vector3).distance_to(start) < best.distance_to(start):
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
		ammo_crates.append(best + Vector3(1.0, 0, 0))
		return
	player_spawn = best
	player_yaw = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var pool := _walkable.filter(func(w): var d := (w as Vector3).distance_to(best); return d > 10.0 and d < 70.0)
	if pool.is_empty():
		pool = _walkable.filter(func(w): return (w as Vector3).distance_to(best) > 6.0)
	if pool.is_empty():
		pool = _walkable
	for i in mini(40, pool.size()):
		zombie_spawns.append(pool[rng.randi() % pool.size()])
	ammo_crates.append(best + Vector3(1.0, 0, 0))


func _process(_delta: float) -> void:
	pass
