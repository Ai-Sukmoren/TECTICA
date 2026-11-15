extends SceneTree
## Maps built from one model (WAREHOUSE): each loads for Zombie Survival and
## Deathmatch with spawns on the walkable floor and the player standing on it.
##   godot --headless --path . -s res://tests/model_maps_test.gd
const Main = preload("res://scripts/main.gd")
const ModelLevel = preload("res://scripts/world/model_level.gd")
const Net = preload("res://scripts/net/net.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	load("res://scripts/core/profile.gd").current = "model_maps_test"
	for id in ModelLevel.CONFIGS.keys():
		for mode in ["zombie", "pvp"]:
			# Deathmatch outside a multiplayer session is solo Team Deathmatch vs bots
			Main.saved_mode = mode; Main.saved_map = id; Main.quick_restart = true
			Main.saved_tdm = mode == "pvp"; Main.saved_bots = 2 if mode == "pvp" else 0
			if mode == "pvp" and Net.host("pvp", 17895, false) != OK:
				print("%-9s %-6s FAIL: could not start a local match" % [id, mode])
				failures += 1
				continue
			var t := Time.get_ticks_msec()
			change_scene_to_file("res://scenes/main.tscn")
			await process_frame
			await process_frame
			var load_ms := Time.get_ticks_msec() - t
			for i in 120: await physics_frame
			var m = current_scene
			var lv = m.level
			if m.map_id != id or lv.get_script() != ModelLevel:
				print("%-9s %-6s FAIL: loaded map %s" % [id, mode, m.map_id])
				failures += 1
				continue
			var p: Vector3 = m.player.global_position
			var spawn: Vector3 = lv.player_spawn
			var spawns: int = lv.zombie_spawns.size() if mode == "zombie" else lv.pvp_spawns.size()
			# the player has not fallen through the floor or out of the map
			# standing on the floor inside the map (Deathmatch spawns are spread out, some on stair-reached platforms)
			var standing: bool = m.player.is_on_floor() and p.y > lv._lo.y - 0.5 and p.y < lv._hi.y
			var ok: bool = m.map_id == id and spawns >= 10 and lv._walkable.size() >= 20 and standing
			print("%-9s %-6s load %5d ms  walkable %4d  spawns %2d  player %s (spawn %s)  %s" % [id, mode, load_ms, lv._walkable.size(), spawns, p.snapped(Vector3.ONE * 0.01), spawn.snapped(Vector3.ONE * 0.01), "ok" if ok else "FAIL"])
			if not ok:
				failures += 1
			if mode == "pvp":
				Net.leave()
	print("MODEL MAPS: failures=%d" % failures)
	quit(0 if failures == 0 else 1)
