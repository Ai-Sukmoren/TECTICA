extends "res://tests/perf/perf_suite.gd"
## Whole-frame cost of a 28-infected fight on WAREHOUSE in a real window, split by switching each part off in turn:
## drawing the bodies, animating them, their AI / movement, the HUD, the player's own update, and holding fire
## (shots, tracers, impacts, casings). Needs a window.
##   godot --path . -s res://tests/perf/combat_split.gd -- [zombies]

## Zombie body shadows off / back to what each part had.
func _shadows(z, on: bool) -> void:
	for m in z.rig.find_children("*", "MeshInstance3D", true, false):
		if on:
			m.cast_shadow = m.get_meta("cs", m.cast_shadow)
		else:
			m.set_meta("cs", m.cast_shadow)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func measure_split(main, n: int = 480) -> Array:
	await frames(40)
	var t0 := Time.get_ticks_usec()
	var phys := 0.0
	var proc := 0.0
	var p0 := Engine.get_physics_frames()
	for i in n:
		if Engine.max_fps != 0:
			Engine.max_fps = 0
		main.player.health = 100000.0
		main.player.aim_yaw = sin(i * 0.01) * 1.2
		for w in main.player.weapons:
			if not w.is_melee():
				w.reserve = 999
		await process_frame
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	return [(Time.get_ticks_usec() - t0) / 1000.0 / n, phys / n, float(Engine.get_physics_frames() - p0) / n, proc / n]


func run() -> void:
	Settings.ensure()
	Settings.v.vsync = false
	Settings.v.window_mode = 0
	Settings.v.max_fps = 5
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var count := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 28
	var main = await _load("warehouse")
	_spawn_wave(main, count, 0)
	_place(main, main.level.player_spawn, "fp")
	await frames(120)
	var zs: Array = main.enemies.filter(func(e): return is_instance_valid(e) and not e.is_dead)
	Input.action_press("fire")
	var base: Array = await measure_split(main)
	print("[csplit] baseline (firing)      %.2f ms frame  (physics %.2f ms/tick, %.2f ticks/frame, process %.2f ms, %d zombies)" % [base[0], base[1], base[2], base[3], zs.size()])
	var tests := {
		"not firing": func(on): (Input.action_press("fire") if on else Input.action_release("fire")),
		"zombie bodies hidden": func(on): for z in zs: z.rig.visible = on,
		"zombie shadows off": func(on): for z in zs: _shadows(z, on),
		"zombie animation off": func(on): for z in zs: z.rig.set_process(on),
		"zombie AI+move off": func(on): for z in zs: z.set_physics_process(on),
		"hud overlay hidden": func(on): main.hud.overlay.visible = on,
		"player update off": func(on): main.player.set_physics_process(on),
	}
	for k in tests:
		tests[k].call(false)
		var r: Array = await measure_split(main)
		tests[k].call(true)
		print("[csplit] %-22s %.2f ms frame  (saves %.2f)  physics %.2f ms/tick  process %.2f ms" % [k, r[0], base[0] - r[0], r[1], r[3]])
	Input.action_release("fire")
	Settings.mark_clean_exit()
	quit(0)
