extends SceneTree
## Zombie Survival under load, in a real window: for growing crowds of live
## infected hunting the player, the average FPS, 1% low FPS, worst frame and
## memory, plus the worst frame while a new wave's zombies arrive.
##   godot --path . -s res://tests/perf/zombie_stress.gd -- [counts e.g. 12,28,45] [secs]
const Main = preload("res://scripts/main.gd")
const Zombie = preload("res://scripts/characters/zombie.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

## Frame times (ms) over `secs` seconds.
var phys_ms := 0.0
var proc_ms := 0.0
var ticks := 0.0
func sample(main, secs: float) -> Array:
	var out: Array = []
	phys_ms = 0.0
	proc_ms = 0.0
	var p0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	var last := t0
	while last - t0 < int(secs * 1_000_000):
		await process_frame
		var now := Time.get_ticks_usec()
		out.append(float(now - last) / 1000.0)
		last = now
		phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		main.player.health = 100000.0
	phys_ms /= out.size()
	proc_ms /= out.size()
	ticks = float(Engine.get_physics_frames() - p0) / out.size()
	return out

func report(tag: String, ft: Array) -> void:
	var s := ft.duplicate()
	s.sort()
	var total := 0.0
	for f in s:
		total += f
	var worst1: Array = s.slice(int(s.size() * 0.99))
	var w := 0.0
	for f in worst1:
		w += f
	w /= maxf(1.0, worst1.size())
	print("[zstress] %-26s avg %5.1f fps  1%% low %5.1f fps  worst %5.1f ms  mem %d MB" % [tag,
			1000.0 * s.size() / total, 1000.0 / w, s[s.size() - 1], int(OS.get_static_memory_usage() / 1048576)])

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280, 720)
	var args := OS.get_cmdline_user_args()
	var counts: Array = []
	for c in (args[0] if args.size() > 0 else "12,28,45").split(","):
		counts.append(int(c))
	var secs := float(args[1]) if args.size() > 1 else 5.0
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.quick_restart = true
	Main._new_player_checked = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var d = main.director
	d.wave = 14
	d.active = true
	d.to_spawn = 0
	d.timer = 999.0
	main.player.set("god_mode", true)
	for n in counts:
		# a new wave's arrivals: the worst frame while 8 zombies spawn in a burst
		var spike := 0.0
		var alive := 0
		for e in main.enemies:
			if is_instance_valid(e) and e is Zombie and not e.is_dead:
				alive += 1
		while alive < n:
			var t := Time.get_ticks_usec()
			var made := 0
			for tries in 40:
				if made >= mini(8, n - alive):
					break
				if d._spawn_one():
					made += 1
			alive += made
			await process_frame
			spike = maxf(spike, float(Time.get_ticks_usec() - t) / 1000.0)
			if made == 0:
				break
		await frames(60)
		var ft := await sample(main, secs)
		report("%d alive" % alive, ft)
		print("[zstress] %-26s physics %.1f ms (%.2f ticks/frame)  process %.1f ms  map %s" % ["", phys_ms, ticks, proc_ms, Main.saved_map])
		print("[zstress] %-26s wave-burst worst frame %.1f ms" % ["%d alive" % alive, spike])
	if "split" in args:
		var zs: Array = main.enemies.filter(func(e): return is_instance_valid(e) and e is Zombie and not e.is_dead)
		var tests := {
			"no zombie-zombie collide": func(on): for z in zs: z.collision_mask = (1 | 2 | 4) if on else (1 | 2),
			"hidden rig anim off": func(on): for z in zs: z.rig.set_process(on),
			"AI+move off": func(on): for z in zs: z.set_physics_process(on),
		}
		await physics_frame
		var t_step := 0.0
		var t_slide := 0.0
		var t_unperch := 0.0
		for rep in 20:
			await physics_frame
			for z in zs:
				var a := Time.get_ticks_usec()
				z._step_up(1.0 / 120.0)
				var b := Time.get_ticks_usec()
				z.move_and_slide()
				var c := Time.get_ticks_usec()
				z._unperch(1.0 / 120.0)
				t_unperch += Time.get_ticks_usec() - c
				t_step += b - a
				t_slide += c - b
		var nn := 20.0 * zs.size()
		print("[zstress] per zombie per tick: _step_up %.1f us  move_and_slide %.1f us  _unperch %.1f us" % [t_step / nn, t_slide / nn, t_unperch / nn])
		for k in tests:
			tests[k].call(false)
			await frames(30)
			var ft2 := await sample(main, 3.0)
			tests[k].call(true)
			report(k, ft2)
			print("[zstress] %-26s physics %.1f ms (%.2f ticks)  process %.1f ms" % ["", phys_ms, ticks, proc_ms])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
