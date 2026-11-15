extends SceneTree
## Repeatable performance suite (needs a window). Fixed 1600x900 window, V-sync
## off, no FPS cap, one graphics preset. Every scenario warms up, then samples
## real frame times plus the engine's own counters, and writes one JSON line
## per scenario so runs can be compared before / after a change.
##   godot --path . -s res://tests/perf/perf_suite.gd -- <out.jsonl> [preset 0..3] [scenario...]
## Scenarios: load_forest, forest_fp, forest_td, load_town, town_fp, hotel_fp,
## town_td, combat_hold_fp (28 infected, not firing), combat_fp, combat_td
## (holding fire), switch. Default: all of them.
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Zombie = preload("res://scripts/characters/zombie.gd")

const WARMUP := 90
const SAMPLES := 600

var out_path := "user://perf_suite.jsonl"
var preset := 2
var lines: Array = []


func _initialize() -> void:
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_path = a[0]
	if a.size() > 1:
		preset = int(a[1])
	var only: Array = a.slice(2) if a.size() > 2 else []
	# in memory only (never saved): windowed, V-sync off, no frame cap, so a
	# focus change or settings re-apply cannot cap the run
	Settings.ensure()
	Settings.v.vsync = false
	Settings.v.window_mode = 0
	Settings.v.max_fps = 5
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	load("res://scripts/core/profile.gd").current = "lilin"
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("[perf] adapter: %s  /  %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	for map in ["forest", "town"]:
		var wanted := func(s: String) -> bool: return only.is_empty() or s in only
		var map_scen: Array = ["load_" + map, map + "_fp", map + "_td"]
		if map == "town":
			map_scen.append_array(["hotel_fp", "combat_hold_fp", "combat_fp", "combat_td", "switch"])
		if map_scen.filter(wanted).is_empty():
			continue
		var t0 := Time.get_ticks_usec()
		var main = await _load(map)
		var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
		if wanted.call("load_" + map):
			_emit({"scenario": "load_" + map, "load_ms": snappedf(load_ms, 0.1),
					"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
					"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)})
		for view in ["fp", "td"]:
			if wanted.call("%s_%s" % [map, view]):
				_place(main, Vector3(2.0, 0.05, 30) if map == "town" else main.level.player_spawn, view)
				await _measure(main, "%s_%s" % [map, view], true)
		if map != "town":
			continue
		if wanted.call("hotel_fp"):
			# second floor of Hotel Meridian, looking down the corridor
			_place(main, Vector3(-30.0, main.level.FLOOR_H + 0.35, -20.0), "fp")
			main.player.aim_yaw = -PI * 0.5
			await _measure(main, "hotel_fp", false)
		if wanted.call("combat_fp") or wanted.call("combat_td") or wanted.call("combat_hold_fp"):
			_spawn_wave(main, 28, 10)
			if wanted.call("combat_hold_fp"):
				_place(main, Vector3(2.0, 0.05, 30), "fp")
				await _measure(main, "combat_hold_fp", true, false)
			for view in ["fp", "td"]:
				if wanted.call("combat_" + view):
					_place(main, Vector3(2.0, 0.05, 30), view)
					Input.action_press("fire")
					await _measure(main, "combat_" + view, true, true)
					Input.action_release("fire")
		if wanted.call("switch"):
			_place(main, Vector3(2.0, 0.05, 30), "td")
			await _measure(main, "switch", true, false, 30)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	print("[perf] wrote ", out_path)
	Settings.mark_clean_exit()
	quit(0)


func _load(map: String) -> Node:
	Main.saved_mode = "zombie"
	Main.saved_map = map
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var main = current_scene
	for k in Settings.PRESET_VALUES:
		Settings.v[k] = Settings.PRESET_VALUES[k][preset]
	Settings.v.preset = preset
	main.apply_graphics()
	Engine.max_fps = 0
	await frames(30)
	main.director.timer = 9999.0
	main.player.set("god_mode", true)
	main.player.health = 100000.0
	main.hud.visible = true
	seed(1717)
	return main


func _place(main, pos: Vector3, view: String) -> void:
	var p = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.aim_yaw = 0.0
	p.set_first_person(view == "fp")


## Keeps 28 infected alive near the player, plus a few fresh corpses.
func _spawn_wave(main, alive: int, corpses: int) -> void:
	seed(4242)   # same spawn points, kinds and variants every run
	var d = main.director
	d.wave = 14
	d.active = true
	d.to_spawn = 0
	d.timer = 9999.0
	var spawned := 0
	for tries in 600:
		if spawned >= alive + corpses:
			break
		if d._spawn_one():
			spawned += 1
	var n := 0
	for e in main.enemies:
		if n >= corpses:
			break
		if e is Zombie and not e.is_dead:
			e.die(Vector3.FORWARD)
			n += 1


func _measure(main, scenario: String, sweep: bool, combat: bool = false, switch_every: int = 0) -> void:
	await frames(WARMUP)
	var vp_rid := root.get_viewport_rid()
	var ft: Array[float] = []
	var cpu := 0.0
	var gpu := 0.0
	var draws := 0.0
	var objects := 0.0
	var prims := 0.0
	var phys := 0.0
	var proc := 0.0
	var last := Time.get_ticks_usec()
	for i in SAMPLES:
		var p = main.player
		p.health = 100000.0
		if sweep:
			p.aim_yaw = sin(i * 0.01) * 1.2   # slow pan so the view changes like play
		if combat:
			for w in p.weapons:
				if not w.is_melee():
					w.reserve = 999
		if switch_every > 0 and i % switch_every == 0:
			p.set_first_person(not p.first_person)
		if Engine.max_fps != 0:
			Engine.max_fps = 0
		await process_frame
		var now := Time.get_ticks_usec()
		ft.append((now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var n := float(SAMPLES)
	var sorted := ft.duplicate()
	sorted.sort()
	var total := 0.0
	for x in ft:
		total += x
	var worst: Array = sorted.slice(int(n * 0.99))
	var worst_avg := 0.0
	for x in worst:
		worst_avg += x
	worst_avg /= maxf(worst.size(), 1)
	var alive := 0
	for e in main.enemies:
		if is_instance_valid(e) and not e.is_dead:
			alive += 1
	_emit({
		"scenario": scenario, "preset": Settings.PRESETS[preset],
		"avg_fps": snappedf(1000.0 * n / total, 0.1),
		"avg_ms": snappedf(total / n, 0.01),
		"low1_fps": snappedf(1000.0 / worst_avg, 0.1),
		"p99_ms": snappedf(sorted[int(n * 0.99)], 0.01),
		"max_ms": snappedf(sorted[-1], 0.01),
		"render_cpu_ms": snappedf(cpu / n, 0.01),
		"gpu_ms": snappedf(gpu / n, 0.01),
		"physics_ms": snappedf(phys / n, 0.01),
		"draw_calls": int(draws / n),
		"objects": int(objects / n),
		"primitives_k": int(prims / n / 1000.0),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"zombies_alive": alive,
	})


func _emit(d: Dictionary) -> void:
	var s := JSON.stringify(d)
	lines.append(s)
	print("[perf] ", s)
