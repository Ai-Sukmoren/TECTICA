extends SceneTree
## Headless test: props break from bullets/grenades, barrels chain-explode,
## cover points + radar footprint are removed, navmesh re-bakes.
##   godot --headless --path . -s res://tests/destruct_test.gd
var main
var f := 0
var crate
var cover_before := 0
var rects_before := 0
var nav_polys_before := 0
func _initialize() -> void:
	load("res://scripts/main.gd").saved_mode = "operation"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
func _nav_polys() -> int:
	var nm: NavigationMesh = main.level.nav_region.navigation_mesh
	return nm.get_polygon_count()
func _physics_process(_d: float) -> bool:
	f += 1
	var p = main.player
	var lvl = main.level
	if f == 2:
		main.hud._deploy()
		for e in main.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		var props = get_nodes_in_group("destructibles")
		var kinds := {}
		for d in props:
			kinds[d.kind] = kinds.get(d.kind, 0) + 1
		print("[props] destructible=", props.size(), " kinds=", kinds)
		cover_before = lvl.cover_points.size()
		rects_before = lvl.map_rects.size()
		nav_polys_before = _nav_polys()
	if f == 5:
		# 1) shoot a crate until it breaks
		for d in get_nodes_in_group("destructibles"):
			if d.kind == "wood" and d.covers.size() > 0:
				crate = d
				break
		var c: Vector3 = crate.center()
		var shots := 0
		while is_instance_valid(crate) and not crate.destroyed and shots < 100:
			crate.apply_damage(30.0, c + Vector3(0, 0, 0.5), Vector3(0, 0, -1), p)
			shots += 1
		print("[bullets] crate destroyed after %d x 30-dmg hits" % shots)
		print("[cover] points %d -> %d, radar rects %d -> %d" % [cover_before, lvl.cover_points.size(), rects_before, lvl.map_rects.size()])
		print("[fragments] live=", load("res://scripts/world/fragment.gd")._live.size())
	if f == 40:
		print("[nav] polygons %d -> %d (rebaked=%s)" % [nav_polys_before, _nav_polys(), str(_nav_polys() != nav_polys_before)])
		# 2) red barrel chain reaction from one bullet hit
		var reds: Array = []
		for d in get_nodes_in_group("destructibles"):
			if d.kind == "explosive":
				reds.append(d)
		print("[barrels] red barrels=", reds.size())
		reds[0].apply_damage(60.0, reds[0].center(), Vector3(1, 0, 0), p)
	if f == 100:
		var left := 0
		for d in get_nodes_in_group("destructibles"):
			if d.kind == "explosive":
				left += 1
		print("[barrels] red barrels left after chain = ", left, " (expected 0)")
		# 3) grenade vs sandbags (sand is tough to bullets, weak to blasts)
		var bag
		for d in get_nodes_in_group("destructibles"):
			if d.kind == "sand":
				bag = d
				break
		var hp0: float = bag.health
		for i in 10:
			bag.apply_damage(30.0, bag.center(), Vector3(0, 0, -1), p)
		print("[sand] 10 bullets: hp %.0f -> %.0f" % [hp0, bag.health])
		load("res://scripts/weapons/blast.gd").detonate(main.level, bag.center() + Vector3(0, -0.3, 1.0), 150.0, 6.5, p)
		print("[sand] after a frag 1 m away: destroyed=", bag.destroyed)
		print("[player] hp=", p.health)
	if f == 400:
		print("[fragments] live after 5 s=", load("res://scripts/world/fragment.gd")._live.size())
		print("[done] props destroyed=", lvl.props_destroyed)
		quit()
	return false
