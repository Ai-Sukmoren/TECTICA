extends SceneTree
## CPU frame cost per subsystem (each switched off in turn vs baseline), 28 zombies.
##   godot --headless --path . -s res://tests/perf_split.gd
## Headless Godot sleeps 6.9 ms per frame unless low_processor_usage_mode_sleep_usec = 0.
const Main = preload("res://scripts/main.gd")
const Zombie = preload("res://scripts/characters/zombie.gd")

func _initialize() -> void:
	call_deferred("run")

func measure(main, secs: float) -> float:
	var frames := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(secs * 1_000_000):
		await process_frame
		frames += 1
		main.player.health = 100000.0
	return secs * 1000.0 / frames

func set_proc(nodes: Array, on: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.set_process(on)
			n.set_physics_process(on)

func run() -> void:
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	OS.low_processor_usage_mode_sleep_usec = 0
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var d = main.director
	d.wave = 14
	d.active = true
	d.to_spawn = 0
	d.timer = 999.0
	main.player.health = 100000.0
	var spawned := 0
	for tries in 400:
		if spawned >= 28:
			break
		if d._spawn_one():
			spawned += 1
	for i in 60: await physics_frame
	var zs: Array = main.enemies.filter(func(e): return is_instance_valid(e) and not e.is_dead)
	var rigs: Array = zs.map(func(z): return z.rig)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	OS.low_processor_usage_mode_sleep_usec = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("[split] max_fps now %d" % Engine.max_fps)
	var base: float = await measure(main, 3.0)
	print("[split] baseline            %.2f ms  (%d zombies)" % [base, zs.size()])
	var groups := {
		"zombie rigs (anim)": rigs,
		"zombie AI+move": zs,
		"hud": [main.hud],
		"player+weapon": [main.player] + main.player.weapons,
		"level/tod/postfx/main": [main.level, main.tod, main.post_fx, main, main.camera_rig, main.music, main.net],
	}
	for k in groups:
		set_proc(groups[k], false)
		if k == "hud":
			main.hud.overlay.visible = false
		var t: float = await measure(main, 2.5)
		set_proc(groups[k], true)
		if k == "hud":
			main.hud.overlay.visible = true
		print("[split] without %-22s %.2f ms  (saves %.2f)" % [k, t, base - t])
	PhysicsServer3D.set_active(false)
	print("[split] physics server off          %.2f ms" % await measure(main, 2.5))
	PhysicsServer3D.set_active(true)
	NavigationServer3D.set_active(false)
	print("[split] navigation server off       %.2f ms" % await measure(main, 2.5))
	NavigationServer3D.set_active(true)
	var f0 := Engine.get_physics_frames()
	var p0 := Engine.get_process_frames()
	await measure(main, 2.0)
	print("[split] physics ticks per frame %.2f" % (float(Engine.get_physics_frames() - f0) / float(Engine.get_process_frames() - p0)))
	print("[split] objects %d  nodes %d  physics pairs %d  islands %d  active %d" % [Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT), Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)])
	quit(0)
