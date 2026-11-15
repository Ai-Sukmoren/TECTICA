extends SceneTree
## Solo team deathmatch vs AI: bots split across both teams leave their spawns
## to hunt, and bots fight bots, so the score moves with the operator idle.
##   godot --headless --path . -s res://tests/tdm_ai_test.gd
const Main = preload("res://scripts/main.gd")
const Net = preload("res://scripts/net/net.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	preload("res://scripts/core/profile.gd").current = "tdm_ai_test"
	check(Net.host("pvp", 17894, false) == OK, "local match starts")
	Main.saved_mode = "pvp"
	Main.saved_map = "desert"
	Main.saved_tdm = true
	Main.saved_bots = 6
	Main.saved_quality = 0
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var m = current_scene
	m.player.health = 1.0e9
	m.player.max_health = 1.0e9
	check(m.enemies.size() == 6, "six bots spawned")
	var mine := 0
	for e in m.enemies:
		if e.team == m.player.team:
			mine += 1
	check(mine == 3, "three bots on the operator's team, three against (%d)" % mine)
	var start := {}
	for e in m.enemies:
		start[e] = e.global_position
	for i in Engine.physics_ticks_per_second * 8: await physics_frame
	var moved := 0
	for e in m.enemies:
		if is_instance_valid(e) and not e.is_dead and e.global_position.distance_to(start[e]) > 4.0:
			moved += 1
	print("  bots that left their spawn in 8 s: %d / 6" % moved)
	check(moved >= 4, "bots go hunting instead of waiting at spawn")
	var t_end := Time.get_ticks_msec() + 60000
	var total := 0
	while Time.get_ticks_msec() < t_end:
		await physics_frame
		total = int(m.team_scores[0]) + int(m.team_scores[1])
		if total >= 2:
			break
	print("  team scores %s" % [m.team_scores])
	check(total >= 1, "bots kill bots of the other team (score moves with the operator idle)")
	m.player.global_position += Vector3.ZERO
	print("TDM AI: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
