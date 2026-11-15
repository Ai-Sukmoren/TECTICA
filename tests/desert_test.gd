extends SceneTree
## ATOMIC ACRES desert map + MARLIN 1895: the map loads for Zombie Survival,
## navigation reaches every zombie spawn and both upstairs floors, the cafe
## model and the sale sign load, the boss-wave test flash fires and fades,
## PvP spawn layout; the Marlin builds with a lever and bolt that the rig
## swings after a shot.
##   godot --headless --path . -s res://tests/desert_test.gd
const Main = preload("res://scripts/main.gd")
const DesertLevel = preload("res://scripts/world/desert_level.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
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
	Main.saved_map = "desert"
	Main.quick_restart = true
	var t0 := Time.get_ticks_msec()
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	print("  first load + 60 frames: %d ms" % (Time.get_ticks_msec() - t0))
	check(main.map_id == "desert" and main.level is DesertLevel, "zombie mode loads the desert map")
	check(main.mode_token() == "zombie@desert", "network token carries the map (%s)" % main.mode_token())
	var lv = main.level
	print("  zombie spawns %d, cover points %d, map rects %d, lamps %d" % [lv.zombie_spawns.size(), lv.cover_points.size(), lv.map_rects.size(), lv.lamp_lights.size()])
	check(lv.zombie_spawns.size() >= 30, "enough zombie spawn points")
	check(lv.cover_points.size() > 20, "cars, bus, sandbags and furniture give cover points")
	check(lv._houses.size() == 2, "two two-storey houses")
	var p = main.player
	check(p.global_position.distance_to(lv.player_spawn) < 2.0 and absf(p.global_position.y) < 0.5, "player starts on the turning circle")
	# third-party models (local only): the cafe and the sale sign
	var cafe_ok := ResourceLoader.exists(DesertLevel.CAFE_GLB)
	var meshes := 0
	for n in lv.find_children("*", "MeshInstance3D", true, false):
		if (n as Node3D).global_position.distance_to(DesertLevel.CAFE_POS) < 9.0:
			meshes += 1
	print("  cafe glb present: %s, meshes around the cafe: %d" % [cafe_ok, meshes])
	check(meshes >= (12 if cafe_ok else 3), "the cafe is built at the south end")
	# navigation: spawns reach the circle, and both upstairs floors are reachable
	var map: RID = main.get_world_3d().navigation_map
	await physics_frame
	var unreachable := 0
	for sp in lv.zombie_spawns:
		var path := NavigationServer3D.map_get_path(map, sp, lv.player_spawn, true)
		if path.is_empty() or path[path.size() - 1].distance_to(lv.player_spawn) > 2.5:
			unreachable += 1
	print("  unreachable spawns: %d / %d" % [unreachable, lv.zombie_spawns.size()])
	check(unreachable <= lv.zombie_spawns.size() / 10, "zombie spawns can path to the circle")
	for h in lv._houses:
		var r: Rect2 = h.rect
		var up := Vector3(r.get_center().x, DesertLevel.FH, r.get_center().y + 2.5)
		var path := NavigationServer3D.map_get_path(map, lv.player_spawn, up, true)
		var end: Vector3 = path[path.size() - 1] if not path.is_empty() else Vector3.ZERO
		print("  upstairs %s: path end %s" % [h.upper.name, end])
		check(not path.is_empty() and end.y > DesertLevel.FH - 0.5 and end.distance_to(up) < 2.0, "the stair reaches the upstairs floor of %s" % h.upper.name)
	# a wave closes in
	p.health = 100000.0
	var d = main.director
	d.timer = 999.0
	var n := 0
	for k in 60:
		if n >= 8: break
		if d._spawn_one(): n += 1
	check(n >= 8, "director spawns zombies on the desert map")
	var dist0 := 0.0
	var zs: Array = main.enemies.filter(func(e): return not e.is_dead)
	for z in zs: dist0 += z.global_position.distance_to(p.global_position)
	for i in Engine.physics_ticks_per_second * 4: await physics_frame
	var dist1 := 0.0
	for z in zs: dist1 += z.global_position.distance_to(p.global_position) if is_instance_valid(z) else 0.0
	print("  mean zombie distance %.1f -> %.1f m" % [dist0 / zs.size(), dist1 / zs.size()])
	check(dist1 < dist0 - 3.0 * zs.size(), "zombies close in on the player")
	# boss wave: the test shot flashes white and fades
	d.wave = 5
	d.to_spawn = 26
	d._announce_wave()
	await process_frame
	await process_frame
	var a0: float = lv._flash.color.a if lv._flash != null else 0.0
	await create_timer(3.8).timeout
	var a1: float = lv._flash.color.a if lv._flash != null else 1.0
	print("  flash alpha %.2f -> %.2f" % [a0, a1])
	check(a0 > 0.8 and a1 < 0.05, "boss wave flashes white, then clears")
	# deathmatch layout
	var pv = DesertLevel.new()
	pv.mode = "pvp"
	root.add_child(pv)
	pv.build()
	check(pv.pvp_spawns.size() >= 14, "deathmatch has %d spawn points" % pv.pvp_spawns.size())
	pv.queue_free()
	# MARLIN 1895
	check(Data.PRIMARIES.has("marlin") and Data.WEAPONS.has("marlin"), "the Marlin is a primary weapon")
	var w = Weapon.new()
	root.add_child(w)
	w.setup("marlin")
	var glb := ResourceLoader.exists("res://assets/thirdparty/marlin_1895/marlin_1895.glb")
	if glb:
		check(w.lever != null and w.lever.get_child_count() > 0, "the Marlin has a lever on its own pivot")
		check(w.bolt != null and w.bolt.get_child_count() > 0, "the Marlin has a sliding bolt")
		var box := AABB()
		var first := true
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
		print("  Marlin size %s" % box.size)
		check(box.size.z > 0.85 and box.size.z < 1.1 and box.size.y < 0.3, "the Marlin is about a metre long, barrel along z")
	else:
		print("  (marlin glb not present: procedural fallback)")
	check(String(w.stats.cycle) == "lever", "lever-action cycle")
	# the player's rig swings the lever after a shot
	if glb:
		var rig = p.rig
		var old = rig.weapon
		rig.set_weapon(w, [])
		w.cycle_pending = 0.01
		var max_open := 0.0
		var t_end := Time.get_ticks_msec() + 1500
		while Time.get_ticks_msec() < t_end:
			await physics_frame
			max_open = maxf(max_open, w.lever.rotation.x)
		print("  lever opened to %.2f rad, rests at %.2f" % [max_open, w.lever.rotation.x])
		check(max_open > 0.6 and absf(w.lever.rotation.x) < 0.01, "the lever swings open and closes after a shot")
		rig.set_weapon(old, [])
	print("DESERT: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
