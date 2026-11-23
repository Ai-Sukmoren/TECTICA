extends SceneTree
## The infected bodies a match builds as waves arrive: Zombie Survival through the real loading flow, then 8 arrivals per wave,
## one at a time as the director spawns them. Per wave: the worst arrival frame, split into arrivals that had to build
## a new skinned body and ones whose body was already built, and how many new bodies were built.
##   godot --path . -s res://tests/perf/wave_bake.gd -- [waves e.g. 1,2,3,4,5,6,8,10,14]
const Main = preload("res://scripts/main.gd")
const Zombie = preload("res://scripts/characters/zombie.gd")
const Rig = preload("res://scripts/characters/soldier_rig.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280, 720)
	var args := OS.get_cmdline_user_args()
	var waves: Array = []
	for w in (args[0] if args.size() > 0 else "1,2,3,4,5,6,8,10,14").split(","):
		waves.append(int(w))
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.quick_restart = true
	Main._new_player_checked = true
	var t0 := Time.get_ticks_msec()
	change_scene_to_file("res://scenes/main.tscn")
	# time to control: the first frame the player can act after the loading screen is gone
	var main = null
	while true:
		await process_frame
		main = current_scene
		if main != null and main.get("player") != null and main.process_mode != Node.PROCESS_MODE_DISABLED \
				and root.get_node_or_null("ZombieWarmup") == null and main.get_node_or_null("ZombieWarmup") == null:
			break
	print("[wbake] to control %d ms   bodies built at start %d" % [Time.get_ticks_msec() - t0, Rig._bake_cache.size()])
	await frames(60)
	var d = main.director
	d.active = true
	d.to_spawn = 0
	d.timer = 999.0
	main.player.set("god_mode", true)
	var total_worst := 0.0
	for w in waves:
		d.wave = w
		var before: int = Rig._bake_cache.size()
		var worst := 0.0
		var worst_new := 0.0   # worst arrival that had to build a new body
		var worst_old := 0.0   # worst arrival whose body was already built
		var made := 0
		for arrival in 8:
			var had: int = Rig._bake_cache.size()
			var a_worst := 0.0
			var last := Time.get_ticks_usec()
			for tries in 10:
				if d._spawn_one():
					made += 1
					break
			# the arrival frame and the next few (a body waiting for its turn is built on a later frame)
			for i in 6:
				await process_frame
				var now := Time.get_ticks_usec()
				a_worst = maxf(a_worst, float(now - last) / 1000.0)
				last = now
			if Rig._bake_cache.size() > had:
				worst_new = maxf(worst_new, a_worst)
			else:
				worst_old = maxf(worst_old, a_worst)
			worst = maxf(worst, a_worst)
			await frames(20)
			main.player.health = 100000.0
		total_worst = maxf(total_worst, worst)
		print("[wbake] wave %2d  %d arrivals  new bodies %2d  worst arrival %5.1f ms (new body %5.1f, cached %5.1f)" % [
				w, made, Rig._bake_cache.size() - before, worst, worst_new, worst_old])
		for e in main.enemies.duplicate():
			if is_instance_valid(e) and e is Zombie:
				main.enemies.erase(e)
				e.queue_free()
		await frames(10)
	print("[wbake] worst arrival frame %.1f ms   bodies built %d" % [total_worst, Rig._bake_cache.size()])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
