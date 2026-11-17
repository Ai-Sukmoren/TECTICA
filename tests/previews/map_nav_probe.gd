extends SceneTree
## Prints each connected walkable area of a model map (size, height, extent).
##   godot --headless --path . -s res://tests/previews/map_nav_probe.gd -- tokyo
const ModelLevel = preload("res://scripts/world/model_level.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var id: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "tokyo"
	var lv = ModelLevel.new(id)
	root.add_child(lv)
	lv.build()
	await physics_frame
	var nm: NavigationMesh = lv.nav_region.navigation_mesh
	var verts := nm.get_vertices()
	var n := nm.get_polygon_count()
	var by_vert := {}
	var cen: Array = []
	for i in n:
		var c := Vector3.ZERO
		for k in nm.get_polygon(i):
			c += verts[k]
			var key := Vector3i((verts[k] * 20.0).round())
			if not by_vert.has(key): by_vert[key] = []
			by_vert[key].append(i)
		cen.append(c / nm.get_polygon(i).size())
	var seen := {}
	var groups: Array = []
	for s in n:
		if seen.has(s): continue
		seen[s] = true
		var q := [s]; var g: Array = []
		while not q.is_empty():
			var i: int = q.pop_back(); g.append(cen[i])
			for k in nm.get_polygon(i):
				for j in by_vert[Vector3i((verts[k] * 20.0).round())]:
					if not seen.has(j): seen[j] = true; q.append(j)
		groups.append(g)
	groups.sort_custom(func(a, b): return a.size() > b.size())
	print("bounds ", lv._lo, " .. ", lv._hi, "  polys ", n, "  groups ", groups.size())
	for g in groups.slice(0, 15):
		var lo: Vector3 = g[0]; var hi: Vector3 = g[0]
		for p in g: lo = lo.min(p); hi = hi.max(p)
		print("  %4d polys  y %.1f..%.1f  x %.1f..%.1f  z %.1f..%.1f" % [g.size(), lo.y, hi.y, lo.x, hi.x, lo.z, hi.z])
	# height map: one char per 0.5 m cell, height of the highest surface below 13 m
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var chars := "0123456789abcdefghijklmnopqrstuvwxyz"
	var z: float = lv._lo.z + 0.25
	while z < lv._hi.z:
		var row := ""
		var x: float = lv._lo.x + 0.25
		while x < lv._hi.x:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 11.0, z), Vector3(x, -5, z))
			var hit := space.intersect_ray(q)
			row += ("nan" if hit.is_empty() else "%.2f" % hit.position.y) + " "
			x += 0.5
		print("H ", row.strip_edges())
		z += 0.5
	quit()
