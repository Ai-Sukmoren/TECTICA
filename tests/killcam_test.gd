extends SceneTree
## Kill cam: dying to a zombie starts it on the killer with the right card,
## the normal camera returns afterwards, it can be skipped, and the setting
## turns it off.
##   godot --headless --path . -s res://tests/killcam_test.gd
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func load_world() -> Node:
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	main.director.timer = 999.0
	return main

func kill_player(main, kind: String) -> Node:
	var d = main.director
	d._spawn_one(kind)
	var z = main.enemies[main.enemies.size() - 1]
	z.global_position = main.player.global_position + Vector3(0, 0, -6)
	await physics_frame
	main.player.apply_damage(99999.0, main.player.global_position + Vector3.UP, Vector3.FORWARD, z)
	await process_frame
	return z

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Settings.ensure()
	var keep: bool = bool(Settings.v.get("killcam", true))
	Settings.v.killcam = true
	var main = await load_world()
	var z = await kill_player(main, "boss")
	check(main.player.is_dead, "player died")
	check(main.killcam_active(), "kill cam starts")
	check(get_root().get_viewport().get_camera_3d() == main.killcam, "kill cam owns the screen")
	check(String(main.killcam.info.name) == "JUGGERNAUT", "card names the killer (%s)" % main.killcam.info.name)
	check(float(main.killcam.info.dist) > 4.0 and float(main.killcam.info.dist) < 8.0, "card shows the distance (%.1f m)" % main.killcam.info.dist)
	await create_timer(1.0, true, false, true).timeout   # past the fly-over, whatever the frame rate
	var to_killer: float = main.killcam.global_position.distance_to(z.global_position)
	check(to_killer < 12.0, "camera flew to the killer (%.1f m away)" % to_killer)
	await create_timer(3.4, true, false, true).timeout
	await process_frame
	check(not main.killcam_active(), "kill cam ends by itself")
	check(get_root().get_viewport().get_camera_3d() == main.camera_rig.active_camera(), "normal camera is back")
	check(not main.camera_rig.override, "camera rig in control again")
	check(is_equal_approx(Engine.time_scale, 1.0), "slow motion ended")

	# skip
	main = await load_world()
	await kill_player(main, "runner")
	check(main.killcam_active() and String(main.killcam.info.name) == "RUNNER", "kill cam on a runner")
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	main.hud._unhandled_input(ev)
	await process_frame
	check(not main.killcam_active(), "Space/Enter skips it")

	# setting off
	Settings.v.killcam = false
	main = await load_world()
	await kill_player(main, "walker")
	check(main.player.is_dead and not main.killcam_active(), "KILL CAM setting off disables it")

	Settings.v.killcam = keep
	Settings.save()
	print("KILLCAM: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
