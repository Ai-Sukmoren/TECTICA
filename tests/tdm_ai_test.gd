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
	Main.saved_map = "warehouse"
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
	# sides read at a glance: teammates blue (through walls) with armbands, opponents red
	var Soldier = preload("res://scripts/characters/soldier.gd")
	var right := 0
	for e in m.enemies:
		var ally: bool = e.team == m.player.team
		if e.name_tag != null and e.name_tag.modulate == (Soldier.ALLY_COLOR if ally else Soldier.FOE_COLOR) 				and e.name_tag.no_depth_test == ally and e._team_bands.size() == 2:
			right += 1
	check(right == 6, "every bot is marked with its side's tag colour and armbands (%d)" % right)
	check(m.player._team_bands.is_empty(), "no armband on the operator (it would sit in the first-person view)")
	var start := {}
	for e in m.enemies:
		start[e] = e.global_position
	for i in Engine.physics_ticks_per_second * 8: await physics_frame
	var moved := 0
	for e in m.enemies:
		# active: left its spawn, or already fighting (in cover / peeking) near it
		if is_instance_valid(e) and not e.is_dead and (e.global_position.distance_to(start[e]) > 4.0 or e.is_in_combat()):
			moved += 1
	print("  bots hunting or fighting after 8 s: %d / 6" % moved)
	check(moved >= 5, "bots go hunting instead of waiting at spawn")
	# the old bug: every bot and the operator piled onto one point, climbing on each other
	var alive: Array = m.enemies.filter(func(e): return is_instance_valid(e) and not e.is_dead)
	var stacked := 0
	var top := -INF
	for a in alive:
		top = maxf(top, a.global_position.y - (start[a] as Vector3).y)
		for b in alive:
			if a != b and Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length() < 0.5:
				stacked += 1
	print("  bot pairs closer than 0.5 m: %d, highest climb %.2f m" % [stacked / 2, top])
	check(stacked == 0, "bots do not pile onto one point")
	check(top < 2.0, "bots do not climb onto each other")
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
