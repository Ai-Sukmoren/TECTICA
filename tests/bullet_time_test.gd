extends SceneTree
## FOCUS and bullet time, and shooting in the middle of a vault:
##  - aiming in a jump with FOCUS slows the game (and the sound) and spends the meter; landing ends it, speed returns;
##  - without enough FOCUS nothing happens; kills fill the meter, headshots more;
##  - during a vault the operator fires, the gun stays up (no hand on the obstacle);
##  - a local match against bots allows it (nobody else's game to slow).
##   godot --headless --path . -s res://tests/bullet_time_test.gd
const Main = preload("res://scripts/main.gd")
const Net = preload("res://scripts/net/net.gd")
var failures := 0
var p


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


func _initialize() -> void:
	run.call_deferred()


func real(sec: float) -> void:
	await create_timer(sec, true, false, true).timeout


func release_all() -> void:
	for a in ["vault", "aim", "fire", "move_forward", "sprint"]:
		Input.action_release(a)


func load_map(mode: String) -> void:
	Main.saved_mode = mode
	Main.saved_map = "warehouse"
	Main.saved_tdm = true
	Main.saved_bots = 1
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90:
		await process_frame
	var main = current_scene
	if main.director != null:
		main.director.set_physics_process(false)
	for e in main.enemies:
		e.set_physics_process(false)
	p = main.player
	p.health = 100000.0
	p.max_health = 100000.0
	p.global_position = main.level.player_spawn + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame


## Jump and aim at the top; true if bullet time started.
func jump_and_aim() -> bool:
	release_all()
	Input.action_press("vault")
	await physics_frame
	await physics_frame
	Input.action_release("vault")
	for i in 12:
		await physics_frame
	Input.action_press("aim")
	var started := false
	for i in 30:
		await physics_frame
		started = started or p.bullet_time
	return started


func run() -> void:
	load("res://scripts/core/profile.gd").current = "bullet_time_test"
	await load_map("zombie")
	var hud = current_scene.hud

	# 1 bullet time in a jump
	p.focus = 1.0
	check(await jump_and_aim(), "aiming in a jump with FOCUS starts bullet time")
	await real(0.25)
	print("    game speed %.2f · sound speed %.2f · FOCUS %.2f" % [Engine.time_scale, AudioServer.playback_speed_scale, p.focus])
	check(Engine.time_scale < 0.5, "the game slows down (%.2f)" % Engine.time_scale)
	check(AudioServer.playback_speed_scale < 0.9, "and the sound drops with it (%.2f)" % AudioServer.playback_speed_scale)
	check(p.focus < 1.0, "bullet time spends FOCUS (%.2f)" % p.focus)
	release_all()
	for i in 600:
		await physics_frame
		if p.is_on_floor() and not p.bullet_time:
			break
	check(not p.bullet_time, "landing ends it")
	await real(0.5)
	check(Engine.time_scale > 0.97, "the game is back to full speed (%.2f)" % Engine.time_scale)
	check(AudioServer.playback_speed_scale > 0.97, "and so is the sound")

	# 2 not enough FOCUS; kills fill it
	p.focus = 0.1
	check(not await jump_and_aim(), "without enough FOCUS nothing happens")
	release_all()
	for i in 200:
		await physics_frame
	var f0: float = p.focus
	p.add_focus(false)
	var f1: float = p.focus
	p.add_focus(true)
	check(is_equal_approx(f1 - f0, p.FOCUS_KILL) and is_equal_approx(p.focus - f1, p.FOCUS_HEADSHOT), "a kill fills FOCUS, a headshot more (%.2f -> %.2f -> %.2f)" % [f0, f1, p.focus])

	# 3 firing in a vault
	p.focus = 1.0
	var w = p.current_weapon()
	w.ammo = int(w.stats.mag)
	var fwd := Vector3(-sin(p.aim_yaw), 0, -cos(p.aim_yaw))
	var shots0: int = p.shots_fired
	p._start_vault({"to": p.global_position + fwd * 2.2, "top": p.global_position.y + 0.8, "plant": p.global_position + fwd * 0.6 + Vector3.UP * 0.8}, fwd)
	Input.action_press("aim")
	var gun_up := false
	var bt := false
	for i in 40:
		if i == 6:
			Input.action_press("fire")
		if i == 8:
			Input.action_release("fire")
		await physics_frame
		gun_up = gun_up or p.rig.vault_aim
		bt = bt or p.bullet_time
		if not p.vaulting:
			break
	release_all()
	check(p.shots_fired > shots0, "the operator fires during a vault (%d shots)" % (p.shots_fired - shots0))
	check(gun_up, "the gun stays up through it (no hand on the obstacle)")
	check(bt, "and a vault shot with FOCUS is in bullet time")
	for i in 240:
		await physics_frame
	check(not p.rig.vault_aim, "the next vault plants the hand again")

	# 4 a local match against bots allows it
	check(Net.host("pvp", 17903, false) == OK, "a local match against bots starts")
	await load_map("pvp")
	check(Net.alone(), "nobody else is in the local match")
	p.focus = 1.0
	check(await jump_and_aim(), "bullet time works against bots")
	release_all()
	for i in 600:
		await physics_frame
		if p.is_on_floor() and not p.bullet_time:
			break
	Net.leave()
	await real(0.5)
	check(Engine.time_scale > 0.97, "full speed after leaving")
	print("BULLET TIME: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
