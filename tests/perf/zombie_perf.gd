extends SceneTree
## Late-wave CPU benchmark: Zombie Survival with 28 live zombies hunting the
## player plus 15 fresh corpses. Prints average frame / physics / process time.
##   godot --headless --path . -s res://tests/perf/zombie_perf.gd
const Main = preload("res://scripts/main.gd")
const Zombie = preload("res://scripts/characters/zombie.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		Engine.max_fps = 0   # windowed runs keep the player's own FPS cap
		OS.low_processor_usage_mode_sleep_usec = 0   # else headless sleeps 6.9 ms a frame
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
	main.player.set("god_mode", true)
	main.player.health = 100000.0
	var spawned := 0
	for tries in 400:
		if spawned >= 43:
			break
		if d._spawn_one():
			spawned += 1
	# turn the first 15 into fresh corpses
	var n := 0
	for e in main.enemies:
		if n >= 15:
			break
		if e is Zombie and not e.is_dead:
			e.die(Vector3.FORWARD)
			n += 1
	for i in 30: await physics_frame
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var phys := 0.0
	var proc := 0.0
	while Time.get_ticks_usec() - t0 < 6_000_000:
		await process_frame
		frames += 1
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		main.player.health = 100000.0
	var alive := 0
	var dead := 0
	for e in main.enemies:
		if is_instance_valid(e):
			if e.is_dead: dead += 1
			else: alive += 1
	print("[zperf] alive=%d corpses=%d  frames=%d  avg frame %.2f ms  physics %.2f ms  process %.2f ms" % [alive, dead, frames,
			6000.0 / frames, phys / frames * 1000.0, proc / frames * 1000.0])
	var shot := OS.get_cmdline_user_args()
	if not shot.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot[0])
	quit(0)
