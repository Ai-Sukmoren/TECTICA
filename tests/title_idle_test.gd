extends SceneTree
## Title screen: the world is paused, but the operator and the enemies keep
## animating (idle look-around); deploying hands them back to the game.
##   godot --headless --path . -s res://tests/title_idle_test.gd
const Main = preload("res://scripts/main.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	Main.quick_restart = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 40: await process_frame
	var main = current_scene
	var hud = main.hud
	check(hud.title and paused, "title screen with the world paused")
	var guards: Array = main.enemies.filter(func(e): return not e.is_dead)
	check(not guards.is_empty(), "%d guards stand in the world" % guards.size())
	var before: Array = guards.map(func(e): return e.rig.aim_yaw)
	var p_before: float = main.player.rig.aim_yaw
	# random look phases: one guard can come back near where it started, so
	# count the largest swing over the window, not just the end point
	var swing: Array = before.map(func(_v): return 0.0)
	var t_end := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < t_end:
		await process_frame
		for i in guards.size():
			swing[i] = maxf(swing[i], absf(guards[i].rig.aim_yaw - before[i]))
	var moved := 0
	for i in guards.size():
		if swing[i] > 0.015:
			moved += 1
	print("    %d / %d guards moved while paused, swings %s" % [moved, guards.size(), str(swing.map(func(v): return snappedf(v, 0.01)))])
	check(moved == guards.size(), "every guard idles on the title screen")
	check(absf(main.player.rig.aim_yaw - p_before) > 0.05, "the operator idles too")
	var g = guards[0]
	check(g.rig.process_mode == Node.PROCESS_MODE_ALWAYS, "guard bodies animate through the pause")
	hud._deploy()
	await process_frame
	check(not paused, "deploy unpauses")
	check(g.rig.process_mode == Node.PROCESS_MODE_INHERIT and main.player.rig.process_mode == Node.PROCESS_MODE_INHERIT, "deploy hands the bodies back to the game")
	print("TITLE: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
