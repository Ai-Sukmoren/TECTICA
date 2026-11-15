extends SceneTree
## Whole-frame cost of 28 infected in a real window, split by switching each
## part off in turn: drawing their bodies, animating them, their AI / movement,
## their physics bodies, and the HUD. Needs a window.
##   godot --path . -s res://tests/perf/combat_split.gd
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func measure(main, n: int = 480) -> Array:
	await frames(40)
	var t0 := Time.get_ticks_usec()
	var phys := 0.0
	var p0 := Engine.get_physics_frames()
	for i in n:
		if Engine.max_fps != 0:
			Engine.max_fps = 0
		main.player.health = 100000.0
		main.player.aim_yaw = sin(i * 0.01) * 1.2
		await process_frame
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return [(Time.get_ticks_usec() - t0) / 1000.0 / n, phys / n, float(Engine.get_physics_frames() - p0) / n]

func run() -> void:
	Settings.ensure()
	Settings.v.vsync = false
	Settings.v.window_mode = 0
	Settings.v.max_fps = 5
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(60)
	var main = current_scene
	var d = main.director
	d.wave = 14
	d.active = true
	d.to_spawn = 0
	d.timer = 9999.0
	main.player.set("god_mode", true)
	main.player.global_position = Vector3(2.0, 0.05, 30)
	var spawned := 0
	for tries in 400:
		if spawned >= 28:
			break
		if d._spawn_one():
			spawned += 1
	await frames(120)
	var zs: Array = main.enemies.filter(func(e): return is_instance_valid(e) and not e.is_dead)
	var base: Array = await measure(main)
	print("[csplit] baseline              %.2f ms frame  (physics %.2f ms, %.2f ticks/frame, %d zombies)" % [base[0], base[1], base[2], zs.size()])
	var tests := {
		"zombie bodies hidden": func(on): for z in zs: z.rig.visible = on,
		"zombie animation off": func(on): for z in zs: z.rig.set_process(on),
		"zombie AI+move off": func(on): for z in zs: z.set_physics_process(on),
		"hud overlay hidden": func(on): main.hud.overlay.visible = on,
	}
	for k in tests:
		tests[k].call(false)
		var r: Array = await measure(main)
		tests[k].call(true)
		print("[csplit] %-22s %.2f ms frame  (saves %.2f)  physics %.2f ms" % [k, r[0], base[0] - r[0], r[1]])
	for z in zs:
		z.rig.visible = false
		z.rig.set_process(false)
		z.set_physics_process(false)
	var none: Array = await measure(main)
	print("[csplit] all zombie work off    %.2f ms frame  (saves %.2f)" % [none[0], base[0] - none[0]])
	Settings.mark_clean_exit()
	quit(0)
