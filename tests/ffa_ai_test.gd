extends SceneTree
## Solo free for all vs AI: bots spawn with no teams, every one is marked as an
## opponent (red tag, no armbands), they fight each other, and the declared
## winner is the top of the ranked scoreboard.
##   godot --headless --path . -s res://tests/ffa_ai_test.gd
const Main = preload("res://scripts/main.gd")
const Net = preload("res://scripts/net/net.gd")
const Soldier = preload("res://scripts/characters/soldier.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	preload("res://scripts/core/profile.gd").current = "ffa_ai_test"
	check(Net.host("pvp", 17897, false) == OK, "local match starts")
	Main.saved_mode = "pvp"
	Main.saved_map = "desert"
	Main.saved_tdm = false
	Main.saved_bots = 5
	Main.saved_quality = 0
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var m = current_scene
	check(m.mode_token() == "ffa5@desert", "mode token round-trips (%s)" % m.mode_token())
	m.player.health = 1.0e9
	m.player.max_health = 1.0e9
	check(m.enemies.size() == 5, "five bots spawned (%d)" % m.enemies.size())
	var teams := {m.player.team: true}
	for e in m.enemies:
		teams[e.team] = true
	check(teams.size() == 6, "every fighter is on their own side")
	var marked := 0
	for e in m.enemies:
		if e.name_tag != null and e.name_tag.modulate == Soldier.FOE_COLOR and not e.name_tag.no_depth_test and e._team_bands.is_empty():
			marked += 1
	check(marked == 5, "every bot wears a red tag, hidden by walls, and no armband (%d)" % marked)
	var t_end := Time.get_ticks_msec() + 60000
	var kills := 0
	while Time.get_ticks_msec() < t_end:
		await physics_frame
		kills = 0
		for id in m.pvp_scores:
			kills += int(m.pvp_scores[id][1])
		if kills >= 2:
			break
	print("  kills after the bots fought: %d" % kills)
	check(kills >= 2, "bots fight each other")
	var ranked: Array = m.pvp_ranked()
	check(m._pvp_leader() == int(ranked[0]), "the leader is the top of the scoreboard")
	print("FFA AI: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
