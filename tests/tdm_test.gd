extends SceneTree
const Main = preload("res://scripts/main.gd")
const Net = preload("res://scripts/net/net.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	preload("res://scripts/core/profile.gd").current = "tdm_test"
	check(Net.host("pvp", 17893, false) == OK, "host starts")
	Main.saved_mode = "pvp"
	Main.saved_map = "warehouse"
	Main.saved_tdm = true
	Main.saved_bots = 2
	Main.saved_quality = 0
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var m = current_scene
	paused = true
	check(m.mode_token() == "tdm2@warehouse", "join token preserves TDM, bots and map")
	check(m.enemies.size() == 2, "optional bots spawned")
	check(m.enemies[0].team != m.player.team, "first bot balances onto opponent team")
	check(m.enemies[1].team == m.player.team, "second bot joins player's team")
	var ally = m.enemies[1]
	var foe = m.enemies[0]
	var hp: float = ally.health
	ally.apply_damage(20.0, ally.global_position, Vector3.FORWARD, m.player)
	check(ally.health == hp, "friendly fire blocked")
	foe.last_attacker_name = String(m.player.name)
	m._pvp_on_death(foe)
	check(m.team_scores[m.player.team] == 1, "enemy kill scores for team")
	check(m._pvp_leader() == m.player.team, "team leader")
	check(m.net_world_state().pvp[2] == m.team_scores, "team scores replicated")
	check(m.hud._mp_items()[7] == "HOST TEAM DEATHMATCH", "TDM host option")
	m.hud._mp_tdm_bots = 0
	check(m.hud._mp_items()[8].ends_with("OFF"), "AI can be disabled")
	check(m._team_for(12345) != m.player.team, "joining human balances teams")
	paused = false
	foe.die(Vector3.FORWARD)
	await create_timer(Main.PVP_RESPAWN + 0.3).timeout
	check(m.enemies.size() == 3, "dead bot respawns")
	Net.leave()
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	print("TDM TEST failures=", failures)
	quit(1 if failures else 0)
