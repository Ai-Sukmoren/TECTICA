extends "res://scripts/world/town_level.gd"
## A Zombie Survival / Deathmatch map built from one third-party model (local
## only, not in the repository): WAREHOUSE, BACKROOMS, TOKYO. To add a map, convert
## its model into assets/thirdparty/ and add a CONFIGS entry and a MAPS name.
## The model is converted with Blender, centred on the origin with its lowest
## point at 0. Collision comes from its own meshes; spawns from the largest
## connected walkable area of the baked navigation mesh, so nobody spawns on a
## roof, a crate top or inside a closed-off room.

const MAP_DIR := "res://assets/thirdparty/"
## id -> glb, lights: mesh-name hints that get a lamp, indoor: add soft fill lights,
## floor_only: spawn only near the lowest floor (a flat roof is walkable too),
## wall: height (m above the lowest point) of a solid concrete wall drawn round the
## whole map; without it the edge is invisible,
## stairs: [[foot, top, width], ...] an invisible slope along a stair's step edges,
## so feet glide up it and navigation can follow,
## agent_radius: navigation agent radius (default 0.5 m; it rounds up to whole cells, so keep it above the
## 0.32 m body or bots hug walls they cannot pass), nav_cell: a finer navigation grid (default 0.25 m) so a
## narrow stair still has room for that radius,
## play_at: a point in the area to play in, when the largest walkable area is not
## it (the play area is then the walkable area nearest this point),
## ramps: [[foot, top], ...] visible concrete ramps joining walkable areas the model leaves apart (none in use:
## measure the real floor and every rail across the route before adding one),
const CONFIGS := {
	"warehouse": {"glb": "warehouse/warehouse.glb", "lights": [], "indoor": true},
	"backrooms": {"glb": "backrooms/backrooms.glb", "lights": [], "indoor": true, "floor_only": true},
	# open-air Tokyo back street (canal, bridge, rail line), car removed, walled in
	"tokyo": {"glb": "tokyo/tokyo.glb", "lights": [], "indoor": false, "wall": 12.0, "play_at": Vector3(-14.0, 3.8, 10.0), "agent_radius": 0.4, "nav_cell": 0.1,
			# the long stair from the west plaza up to the hotel level, between its walls
			# walls at x -13.07 / -11.86; the slope rides 0.12 m over the step nosings so no tread pokes through it
			"stairs": [[Vector3(-12.465, 3.46, 5.6), Vector3(-12.465, 7.80, -7.7), 1.19],
				# the 0.67 m kerb from the road up to the west plaza, in the two openings of the bamboo fence
				# (rails at 0.45 / 1.0 m along x -11.8 everywhere else): south end z 19.05-19.98, north by the stair foot
				# (the north opening by the stair foot is 0.65 m, too narrow for a body and its margin: jump it)
				[Vector3(-10.0, 2.67, 19.5), Vector3(-11.6, 3.34, 19.5), 0.85]]},
}
const MAX_LAMPS := 24
## Foliage and cloth (by material name) is drawn but not solid: leaf cards, ivy, flags. Made solid, a tree's
## crossing leaf planes caught a jumping body in the canopy. A tree drawn only from such cards keeps a trunk post.
const SOFT := ["leaves", "leaf", "ivy", "alley_plants", "tree2_tex", "bakeryflag"]
const TRUNK_RADIUS := 0.18
## Bushes (by mesh name) are one solid block over their visible volume: a hedge fills an open-topped planter, and
## with only its leaves to stand on a body dropped into the box and wedged there.
const BLOCKS := ["hedge"]
const RAMP_WIDTH := 1.8

var map_key := "warehouse"
var _walkable: Array = []
## navigation polygons of the play area (the island _walkable comes from)
var _walk_polys: Array = []
var _cover_made := false
var _lo := Vector3.ZERO
var _hi := Vector3.ZERO
## where the ground ends (the boundary stands here): may be inside _lo/_hi, which also take in overhangs
var _ground_lo := Vector3.ZERO
var _ground_hi := Vector3.ZERO
static var _navs := {}
## map -> cover spots found on it (positions only; each match gets fresh copies)
static var _covers := {}


func _init(id: String = "warehouse") -> void:
	map_key = id if CONFIGS.has(id) else "warehouse"


func build() -> void:
	for step in build_steps():
		step.call()


func build_steps() -> Array:
	return [_build_start, _build_main_model, _build_extras, _build_finish]


func _build_start() -> void:
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


func _build_main_model() -> void:
	var cfg: Dictionary = CONFIGS[map_key]
	var path := MAP_DIR + String(cfg.glb)
	if ResourceLoader.exists(path):
		_build_model(path, cfg)
	else:
		_lo = Vector3(-20, 0, -20)
		_hi = Vector3(20, 4, 20)


func _build_extras() -> void:
	var cfg: Dictionary = CONFIGS[map_key]
	var path := MAP_DIR + String(cfg.glb)
	# a catch floor well below the model (out of the navigation bake), in case anyone slips through
	var g := _body(Vector3.ZERO)
	var size := Vector2(_hi.x - _lo.x, _hi.z - _lo.z) + Vector2(20, 20)
	_box_shape(g, Vector3(size.x, 1, size.y), Vector3((_lo.x + _hi.x) * 0.5, _lo.y - 3.5, (_lo.z + _hi.z) * 0.5))
	if not ResourceLoader.exists(path):
		_mesh(g, ML.plane(size), M.concrete("model_ground", Color(0.22, 0.22, 0.23), 0.5), Vector3(0, -0.01, 0))
	_build_edges()
	for r in cfg.get("ramps", []):
		_build_ramp(r[0], r[1])
	for r in cfg.get("stairs", []):
		_build_ramp(r[0], r[1], r[2], false)


func _build_finish() -> void:
	_bake_navigation()
	_collect_walkable()
	_define_mode()
	seed(Time.get_ticks_usec())
	_warm_cover.call_deferred()


## Finds the AI's cover while the map loads (a few ms, once per map) instead of in the first fire fight.
func _warm_cover() -> void:
	# the spots are checked against the navigation map: wait until it holds this map's mesh (its first syncs can be
	# empty, and every query then answers the origin)
	for i in 120:
		await get_tree().physics_frame
		if not is_inside_tree() or _cover_validated:
			return
		# During staged loading the navigation map can be ready before the
		# level's colliders are active. Don't cache cover from an empty world.
		if get_parent().process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		var map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			continue   # (a query before the first sync is an error)
		var probe: Vector3 = _walkable[0] if not _walkable.is_empty() else player_spawn
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 1.0:
			_validate_cover()
			return


## The model, solid wherever it has geometry, with lamps on its light fittings.
func _build_model(path: String, cfg: Dictionary) -> void:
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	var body := _body(Vector3.ZERO)
	body.add_child(inst)
	var first := true
	var lamps := 0
	var hints: Array = cfg.lights
	var boxes: Array = []
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
		boxes.append(aabb)
		if first:
			_lo = aabb.position
			_hi = aabb.end
			first = false
		else:
			_lo = _lo.min(aabb.position)
			_hi = _hi.max(aabb.end)
		# small clutter gets no collision
		if aabb.size.x * aabb.size.y * aabb.size.z > 0.02 or aabb.size.y > 1.5 or aabb.size.x > 3.0 or aabb.size.z > 3.0:
			var solid := _solid_part(mi.mesh)
			var cs := CollisionShape3D.new()
			cs.name = mi.name
			if BLOCKS.any(func(h): return String(mi.name).to_lower().contains(String(h))):
				var box := BoxShape3D.new()
				box.size = aabb.size
				cs.shape = box
				cs.position = aabb.get_center()
				body.add_child(cs)
			elif solid != null:
				var tri := solid.create_trimesh_shape()
				# solid from both sides: one-sided faces stop pushing back once a fast body is past them, and it falls
				# through a deck or into a hollow shell (a wall, a planter, a building)
				tri.backface_collision = true
				cs.shape = tri
				cs.transform = xf
				body.add_child(cs)
			elif aabb.size.y > 2.5:
				var trunk := CylinderShape3D.new()
				trunk.radius = TRUNK_RADIUS
				trunk.height = minf(aabb.size.y * 0.5, 3.0)
				cs.shape = trunk
				cs.position = Vector3(aabb.get_center().x, aabb.position.y + trunk.height * 0.5, aabb.get_center().z)
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
	_find_ground(boxes)
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


## The mesh's solid surfaces (foliage and cloth left out), the mesh itself when all are solid, null when none is.
func _solid_part(mesh: Mesh) -> Mesh:
	var keep: Array = []
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var nm := String(m.resource_name).to_lower() if m != null else ""
		if not SOFT.any(func(h): return nm.contains(String(h))):
			keep.append(i)
	if keep.size() == mesh.get_surface_count():
		return mesh
	if keep.is_empty():
		return null
	var am := ArrayMesh.new()
	for i in keep:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(i))
	return am


## The ground's footprint: the big pieces that sit on the model's lowest level (a street, a floor slab, a rail bed)
## and span a good part of the map. A building that overhangs the ground's edge is left out, so the boundary does
## not stand beyond the floor and leave a slot down the side of the model to fall into.
func _find_ground(boxes: Array) -> void:
	_ground_lo = _lo
	_ground_hi = _hi
	var size := _hi - _lo
	var first := true
	for b in boxes:
		var a: AABB = b
		if a.position.y > _lo.y + 1.0 or (a.size.x < size.x * 0.35 and a.size.z < size.z * 0.35):
			continue
		if first:
			_ground_lo = a.position
			_ground_hi = a.end
			first = false
		else:
			_ground_lo = _ground_lo.min(a.position)
			_ground_hi = _ground_hi.max(a.end)
	_ground_lo.y = _lo.y
	_ground_hi.y = _hi.y


## Walls just outside the model keep everyone in: invisible, or solid concrete
## (with the invisible part above it) when the map's config asks for a wall.
func _build_edges() -> void:
	var lo := _ground_lo if _ground_lo != _ground_hi else _lo
	var hi := _ground_hi if _ground_lo != _ground_hi else _hi
	var c := (lo + hi) * 0.5
	var s := hi - lo
	var h := (_hi.y - _lo.y) + 6.0
	var wall := float(CONFIGS[map_key].get("wall", 0.0))
	var t := 0.6 if wall <= 0.0 else 1.0
	for e in [[Vector3(c.x, _lo.y, lo.z - t * 0.5), Vector3(s.x + t * 2.0, h, t)], [Vector3(c.x, _lo.y, hi.z + t * 0.5), Vector3(s.x + t * 2.0, h, t)],
			[Vector3(lo.x - t * 0.5, _lo.y, c.z), Vector3(t, h, s.z + t * 2.0)], [Vector3(hi.x + t * 0.5, _lo.y, c.z), Vector3(t, h, s.z + t * 2.0)]]:
		var b := _body(e[0])
		_box_shape(b, e[1], Vector3(0, h * 0.5, 0))
		if wall > 0.0:
			var size: Vector3 = e[1]
			size.y = wall
			_mesh(b, ML.box(size), _mat_wall, Vector3(0, wall * 0.5, 0))
			# a darker coping along the top
			_mesh(b, ML.box(Vector3(size.x + 0.1, 0.25, size.z + 0.1)), _mat_wall_trim, Vector3(0, wall + 0.125, 0))


func _bake_navigation(fresh: bool = false) -> void:
	if _navs.has(map_key) and not fresh:
		var cached := (_navs[map_key] as NavigationMesh).duplicate() as NavigationMesh
		NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, cached.cell_size)
		NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, cached.cell_height)
		nav_region.navigation_mesh = cached
		return
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	var cell := float(CONFIGS[map_key].get("nav_cell", 0.25))
	nm.cell_size = cell
	nm.cell_height = cell
	nm.agent_radius = float(CONFIGS[map_key].get("agent_radius", 0.5))
	nm.agent_height = 2.0
	# no higher than a body actually steps (soldier.gd STEP_HEIGHT), where the grid is fine enough to say so
	nm.agent_max_climb = 0.4 if cell < 0.2 else 0.5
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nm.filter_baking_aabb = AABB(_lo - Vector3(0, 1, 0), _hi - _lo + Vector3(0, 2, 0))
	# the navigation map works on the same grid as this mesh
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, cell)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, cell)
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
	_navs[map_key] = nm.duplicate()


## Connected groups of navigation polygons (they touch where they share a
## vertex position): {"polys": [index...], "centres": [Vector3...], "area": m2}.
## With floor_only, islands grow only from polygons near the lowest floor.
func _nav_islands() -> Array:
	var nm := nav_region.navigation_mesh
	if nm == null or nm.get_polygon_count() == 0:
		return []
	var verts := nm.get_vertices()
	var n := nm.get_polygon_count()
	var centres: Array = []
	var by_vert := {}
	for i in n:
		var poly := nm.get_polygon(i)
		var c := Vector3.ZERO
		for k in poly:
			c += verts[k]
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
	var islands: Array = []
	var seen := {}
	for s0 in n:
		if seen.has(s0) or (floor_only and (centres[s0] as Vector3).y > floor_y + 1.0):
			continue
		var polys: Array = []
		var group: Array = []
		var area := 0.0
		seen[s0] = true
		var queue: Array = [s0]
		while not queue.is_empty():
			var i: int = queue.pop_back()
			polys.append(i)
			group.append(centres[i])
			var poly := nm.get_polygon(i)
			for t in range(1, poly.size() - 1):
				area += (verts[poly[t]] - verts[poly[0]]).cross(verts[poly[t + 1]] - verts[poly[0]]).length() * 0.5
			for k in poly:
				for j in by_vert[Vector3i((verts[k] * 20.0).round())]:
					if not seen.has(j):
						seen[j] = true
						queue.append(j)
		islands.append({"polys": polys, "centres": group, "area": area})
	return islands


## Centres of the largest (by floor area) connected group of navigation polygons:
## the map's real walkable area (roofs, crate tops and sealed rooms are left out).
func _collect_walkable() -> void:
	_walkable.clear()
	var best := -INF
	var cfg: Dictionary = CONFIGS[map_key]
	for isl in _nav_islands():
		var score := float(isl.area)
		if cfg.has("play_at"):
			score = -INF
			for c in isl.centres:
				score = maxf(score, -(c as Vector3).distance_to(cfg.play_at))
		if score > best:
			best = score
			_walkable = isl.centres
			_walk_polys = isl.polys


## Cover for the AI along the edge of the play area's navigation mesh, where it stops short of an obstacle: a spot
## every metre or so with something solid in front at crouch height (0.85 m, as level.is_covered() checks). Low cover
## (clear at standing eye height) is fired over standing up; a wall is used only at its corner, where a sidestep
## ("peek") clears it to fire past. Drops and kerbs (nothing in front) and flat wall faces are left out.
func _generate_cover() -> void:
	if _cover_made:
		return
	_cover_made = true
	if _covers.has(map_key):
		for c in _covers[map_key]:
			var d: Dictionary = (c as Dictionary).duplicate()
			d.taken = null
			cover_points.append(d)
		return
	var found: Array = []
	_covers[map_key] = found
	var nm := nav_region.navigation_mesh
	if nm == null or _walk_polys.is_empty():
		return
	var verts := nm.get_vertices()
	var key := func(v: Vector3) -> Vector3i: return Vector3i((v * 20.0).round())
	# edges used by one polygon only are the mesh's boundary
	var uses := {}
	var edges: Array = []   # [a, b, polygon centre]
	for i in _walk_polys:
		var poly := nm.get_polygon(i)
		var c := Vector3.ZERO
		for k in poly:
			c += verts[k]
		c /= poly.size()
		for j in poly.size():
			var a: Vector3 = verts[poly[j]]
			var b: Vector3 = verts[poly[(j + 1) % poly.size()]]
			var ka: Vector3i = key.call(a)
			var kb: Vector3i = key.call(b)
			var ek := str(ka) + str(kb) if str(ka) < str(kb) else str(kb) + str(ka)
			uses[ek] = int(uses.get(ek, 0)) + 1
			edges.append([a, b, c, ek])
	var space := get_world_3d().direct_space_state
	var map := get_world_3d().navigation_map
	var taken := {}
	var ray := func(from: Vector3, to: Vector3) -> Dictionary:
		return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD))
	for e in edges:
		if int(uses[e[3]]) != 1:
			continue
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var length := along.length()
		if length < 0.05:
			continue
		var t := along / length
		var n := Vector3(t.z, 0.0, -t.x)
		if n.dot((a + b) * 0.5 - (e[2] as Vector3)) < 0.0:
			n = -n   # out of the polygon, toward what stops the mesh
		var steps := maxi(1, int(length / 1.2))
		for s_i in steps:
			var p := a.lerp(b, (s_i + 0.5) / steps)
			var cell := Vector3i(floori(p.x), floori(p.y / 1.5), floori(p.z))
			if taken.has(cell):
				continue
			var low: Dictionary = ray.call(p + Vector3.UP * 0.85, p + Vector3.UP * 0.85 + n * 1.3)
			if low.is_empty() or (low.normal as Vector3).dot(n) > -0.5:
				continue   # a drop or a kerb, or a sloping face: nothing to hide behind
			var peek := Vector3.ZERO
			if not ray.call(p + Vector3.UP * 1.5, p + Vector3.UP * 1.5 + n * 1.3).is_empty():
				# a wall: only worth it at a corner a sidestep clears
				var ok := false
				for side in [1.0, -1.0]:
					var off: Vector3 = t * side * 0.9
					var q := p + off
					var on_mesh := NavigationServer3D.map_get_closest_point(map, q)
					if Vector2(on_mesh.x - q.x, on_mesh.z - q.z).length() > 0.3 or absf(on_mesh.y - q.y) > 0.5:
						continue
					if not ray.call(p + Vector3.UP * 1.45, q + Vector3.UP * 1.45).is_empty():
						continue
					if ray.call(q + Vector3.UP * 1.45, q + Vector3.UP * 1.45 + n * 1.3).is_empty():
						peek = off
						ok = true
						break
				if not ok:
					continue
			taken[cell] = true
			found.append({"pos": p, "normal": -n, "taken": null, "valid": true, "destroyed": false, "peek": peek})
	for c in found:
		cover_points.append((c as Dictionary).duplicate())


## A concrete ramp slab from foot to top (its upper face runs between them);
## an invisible one when `visible` is off (laid over a stair).
func _build_ramp(foot: Vector3, top: Vector3, width: float = RAMP_WIDTH, visible: bool = true) -> StaticBody3D:
	var along := top - foot
	var b := _body((foot + top) * 0.5)
	b.basis = Basis.looking_at(along.normalized(), Vector3.UP)
	var size := Vector3(width, 0.3, along.length() + 0.2)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, -0.15, 0)
	b.add_child(cs)
	if visible:
		_mesh(b, ML.box(size), _mat_concrete, Vector3(0, -0.15, 0))
	return b


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
