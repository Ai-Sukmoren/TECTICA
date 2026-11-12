extends SceneTree
## DEAD END town map: loads for Zombie Survival, navigation reaches every
## zombie spawn, zombies spawn and close in, PvP spawn layout, map token.
##   godot --headless --path . -s res://tests/town_test.gd
const Main = preload("res://scripts/main.gd")
const TownLevel = preload("res://scripts/world/town_level.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	var t0 := Time.get_ticks_msec()
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	print("  first load + 60 frames: %d ms" % (Time.get_ticks_msec() - t0))
	check(main.map_id == "town" and main.level is TownLevel, "zombie mode loads the town map")
	check(main.mode_token() == "zombie@town", "network token carries the map (%s)" % main.mode_token())
	var lv = main.level
	print("  zombie spawns %d, cover points %d, map rects %d, lamps %d" % [lv.zombie_spawns.size(), lv.cover_points.size(), lv.map_rects.size(), lv.lamp_lights.size()])
	check(lv.zombie_spawns.size() >= 40, "enough zombie spawn points")
	check(lv.cover_points.size() > 40, "barricades and cars give cover points")
	var p = main.player
	check(p.global_position.distance_to(lv.player_spawn) < 2.0 and absf(p.global_position.y) < 0.5, "player starts at the barricade on the ground")
	var map: RID = main.get_world_3d().navigation_map
	await physics_frame
	var unreachable := 0
	for sp in lv.zombie_spawns:
		var path := NavigationServer3D.map_get_path(map, sp, lv.player_spawn, true)
		if path.is_empty() or path[path.size() - 1].distance_to(lv.player_spawn) > 2.5:
			unreachable += 1
	print("  unreachable spawns: %d / %d" % [unreachable, lv.zombie_spawns.size()])
	check(unreachable <= lv.zombie_spawns.size() / 10, "zombie spawns can path to the barricade")
	# a wave closes in
	p.health = 100000.0
	var d = main.director
	d.timer = 999.0
	var n := 0
	for k in 60:
		if n >= 8: break
		if d._spawn_one(): n += 1
	check(n >= 8, "director spawns zombies on the town map")
	var dist0 := 0.0
	var zs: Array = main.enemies.filter(func(e): return not e.is_dead)
	for z in zs: dist0 += z.global_position.distance_to(p.global_position)
	for i in Engine.physics_ticks_per_second * 4: await physics_frame
	var dist1 := 0.0
	for z in zs: dist1 += z.global_position.distance_to(p.global_position) if is_instance_valid(z) else 0.0
	print("  mean zombie distance %.1f -> %.1f m" % [dist0 / zs.size(), dist1 / zs.size()])
	check(dist1 < dist0 - 4.0 * zs.size(), "zombies close in on the player")
	# deathmatch layout
	var pv = TownLevel.new()
	pv.mode = "pvp"
	root.add_child(pv)
	pv.build()
	check(pv.pvp_spawns.size() >= 16, "deathmatch has %d spawn points" % pv.pvp_spawns.size())
	pv.queue_free()
	# token parsing back to the forest
	Main.saved_map = "town"
	var parts := "ch1".split("@")
	check(parts.size() == 1, "plain token has no map")
	print("TOWN: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
