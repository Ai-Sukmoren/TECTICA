extends SceneTree
## Finds the ramps that join a model map's walkable islands (kerbs and ledges the
## model leaves apart) and prints them as the map's "ramps" config entry.
##   godot --headless --path . -s res://tools/link_map_islands.gd -- tokyo
## Again and again it joins the closest two islands a ramp can link: a ledge up to
## RISE across a gap up to REACH, no wall or railing across the ramp, real floor
## at its foot. Then it rebakes navigation and looks again.
const ModelLevel = preload("res://scripts/world/model_level.gd")
const Layers = preload("res://scripts/core/layers.gd")
const RISE := 4.6           # highest ledge a ramp bridges (m)
const LOW_RISE := 1.45      # up to this a gentle ramp, above it a steep stair-like one
const REACH := 3.5          # widest gap between two islands' edges (m)
const MIN_POLYS := 6        # smaller islands (planters, crate tops) are left alone
const SLOPE := 0.42         # rise per metre of a gentle ramp (about 23 degrees)
const STEEP := 0.7          # rise per metre of a steep ramp (35 degrees, still walkable)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if not args.is_empty() else "tokyo"
	var lv = ModelLevel.new(id)
	root.add_child(lv)
	lv.build()
	var made: Array = []
	var tried := {}
	for pass_i in 400:
		await physics_frame
		await physics_frame
		var islands: Array = lv._nav_islands().filter(func(isl): return (isl.polys as Array).size() >= MIN_POLYS)
		if islands.size() < 2:
			break
		var found := _closest_pair(lv, islands, tried)
		if found.is_empty():
			break
		tried[found[2]] = true
		var a: Vector3 = found[0]
		var b: Vector3 = found[1]
		var ramp := _ramp_ends(lv, a if a.y < b.y else b, b if a.y < b.y else a)
		if ramp.is_empty():
			continue
		var bodies: Array = []
		for r in ramp:
			bodies.append(lv._build_ramp(r[0], r[1]))
		lv._bake_navigation(true)
		var after: int = lv._nav_islands().filter(func(isl): return (isl.polys as Array).size() >= MIN_POLYS).size()
		if after >= islands.size():
			# it joined nothing (a ledge the agent still cannot step on): take it away
			for body in bodies:
				body.free()
			lv._bake_navigation(true)
			continue
		made.append_array(ramp)
		print("ramp %d: %s  (islands %d -> %d)" % [made.size(), ramp, islands.size(), after])
	var parts: Array = []
	for r in made:
		parts.append("[%s, %s]" % [_v(r[0]), _v(r[1])])
	print("RAMPS := [%s]" % ", ".join(parts))
	quit()


func _v(p: Vector3) -> String:
	return "Vector3(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


## The closest two edge points on different islands that a ramp could join:
## [a, b, key], or [] when none is left untried.
func _closest_pair(lv, islands: Array, tried: Dictionary) -> Array:
	var nm: NavigationMesh = lv.nav_region.navigation_mesh
	var verts := nm.get_vertices()
	# points every half metre along the polygon edges, bucketed on a REACH grid:
	# only neighbouring buckets are compared
	var grid := {}
	for id in islands.size():
		for i in islands[id].polys:
			var poly := nm.get_polygon(i)
			for j in poly.size():
				var p0 := verts[poly[j]]
				var p1 := verts[poly[(j + 1) % poly.size()]]
				var steps := maxi(1, ceili(p0.distance_to(p1) / 0.5))
				for t in steps:
					var p := p0.lerp(p1, float(t) / steps)
					var cell := Vector2i(floori(p.x / REACH), floori(p.z / REACH))
					if not grid.has(cell):
						grid[cell] = []
					(grid[cell] as Array).append([p, id])
	var found: Array = []
	var best := INF
	for cell in grid:
		for e in grid[cell]:
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for f in grid.get(cell + Vector2i(dx, dz), []):
						if int(f[1]) <= int(e[1]):
							continue
						var a: Vector3 = e[0]
						var b: Vector3 = f[0]
						var rise := absf(a.y - b.y)
						var d := Vector2(a.x - b.x, a.z - b.z).length()
						if rise < 0.45 or rise > RISE or d > REACH or d + rise * 0.5 >= best:
							continue
						var key := Vector3i((a + b).snapped(Vector3.ONE * 0.5) * 2.0)
						if tried.has(key):
							continue
						best = d + rise * 0.5
						found = [a, b, key]
	return found


## Ramp slabs [[foot, top], ...] from the lower floor up onto the upper edge, or []
## when the model is in the way (a wall or railing across it, no floor at its foot).
## A low kerb gets one gentle ramp straight at it; a tall ledge gets a steep one,
## straight out from the wall or along it with a flat landing across the top.
func _ramp_ends(lv, lo: Vector3, hi: Vector3) -> Array:
	var n := Vector3(hi.x - lo.x, 0, hi.z - lo.z)
	if n.length() < 0.05:
		return []
	n = n.normalized()
	var rise := hi.y - lo.y
	var slope := SLOPE if rise <= LOW_RISE else STEEP
	var run := rise / slope
	var t := n.cross(Vector3.UP)
	var land := hi + n * 0.6
	var options: Array = [[[Vector3(land.x, lo.y, land.z) - n * (run + 0.6), land]]]
	if rise > LOW_RISE:
		for side in [1.0, -1.0]:
			var top := Vector3(lo.x, hi.y, lo.z)
			options.append([[Vector3(lo.x, lo.y, lo.z) + t * side * run, top], [top - n * 0.3, land]])
	for slabs in options:
		if _clear(lv, slabs, lo.y):
			return slabs
	return []


func _clear(lv, slabs: Array, floor_y: float) -> bool:
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	for k in slabs.size():
		var foot: Vector3 = slabs[k][0]
		var top: Vector3 = slabs[k][1]
		var dir := Vector3(top.x - foot.x, 0, top.z - foot.z).normalized()
		for side in [-0.7, 0.0, 0.7]:
			var off := dir.cross(Vector3.UP) * float(side)
			# chest height along the slab: nothing across it
			var q := PhysicsRayQueryParameters3D.create(foot + off + Vector3(0, 1.1, 0), top + off + Vector3(0, 1.1, 0), Layers.WORLD)
			var hh := space.intersect_ray(q)
			if not hh.is_empty():
				if OS.has_environment("LINK_DEBUG"):
					var sh = (hh.collider as CollisionObject3D).shape_owner_get_owner((hh.collider as CollisionObject3D).shape_find_owner(hh.shape))
					print("  blocked by ", sh.name if sh else "?", " at ", hh.position.snapped(Vector3.ONE * 0.1), " slab ", k, " rise ", top.y - floor_y)
				return false
			if k > 0:
				continue
			# real floor under the foot on both sides
			var down := PhysicsRayQueryParameters3D.create(foot + off + Vector3(0, 0.6, 0), foot + off - Vector3(0, 0.6, 0), Layers.WORLD)
			var hit := space.intersect_ray(down)
			if hit.is_empty() or absf(float(hit.position.y) - floor_y) > 0.4:
				return false
	return true
