extends "res://tests/perf/perf_suite.gd"
## The whole player path in one window, measured the way a player meets it (needs a window):
##   boot      engine start to the title menu drawn and taking input (the real launch: loading.tscn -> main)
##   load_*    each map through the real loading screen (Transition.change_map), with the longest frozen frame
##   play_*    first-person play on that map (uncapped, V-sync off)
##   combat    28 infected hunting the player while it fires, on WAREHOUSE
##   switch    cycling weapons every 20 frames
##   gunsmith  opening it, then attachment changes (each change's own cost and the frame that shows it)
##   armory    opening it
##   to_title  leaving the match back to the title menu
## Every result is one JSON line in <out.jsonl>. The run changes attachments and puts every one back, but the
## caller should still back up the save folder (user://) and restore it afterwards.
##   godot --path . -s res://tests/perf/flow_bench.gd -- <out.jsonl> [preset 0..3]
const Transition = preload("res://scripts/ui/transition.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const MAP_ORDER := ["forest", "warehouse", "backrooms", "tokyo"]


func run() -> void:
	var boot_ms := Time.get_ticks_msec()   # engine and autoload start-up, before any game scene
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_path = a[0]
	if a.size() > 1:
		preset = int(a[1])
	Settings.ensure()
	for k in Settings.PRESET_VALUES:
		Settings.v[k] = Settings.PRESET_VALUES[k][preset]
	Settings.v.preset = preset
	Settings.v.vsync = false
	Settings.v.window_mode = 0
	Settings.v.max_fps = 5
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("[perf] adapter: %s" % RenderingServer.get_video_adapter_name())

	# --- boot: the real launch scene, to the title menu
	var t0 := Time.get_ticks_usec()
	change_scene_to_file("res://scenes/loading.tscn")
	var w := await _wait_ready(func(): return _title_ready())
	_emit({"scenario": "boot", "engine_ms": boot_ms, "to_menu_ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1),
			"worst_frame_ms": w.worst, "frames_over_100ms": w.long, "static_mem_mb": _mb(Performance.MEMORY_STATIC)})
	await frames(30)

	# --- every map through the loading screen, then play on it
	for map in MAP_ORDER:
		if not Main.map_available(map):
			continue
		Main.saved_mode = "zombie"
		Main.saved_map = map
		Main.quick_restart = true
		Main.saved_first_person = true
		t0 = Time.get_ticks_usec()
		Transition.change_map(self)
		w = await _wait_ready(func(): return _map_ready(map))
		_emit({"scenario": "load_" + map, "load_ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1),
				"worst_frame_ms": w.worst, "frames_over_100ms": w.long,
				"static_mem_mb": _mb(Performance.MEMORY_STATIC), "video_mem_mb": _mb(Performance.RENDER_VIDEO_MEM_USED)})
		var main = current_scene
		_freeze_match(main)
		_place(main, main.level.player_spawn, "fp")
		await _measure(main, "play_" + map, true)
		if map == "warehouse":
			await _bench_ui(main)
			_spawn_wave(main, 28, 10)
			_place(main, main.level.player_spawn, "fp")
			Input.action_press("fire")
			await _measure(main, "combat", true, true)
			Input.action_release("fire")
			await _bench_switch(main)

	# --- back to the title menu
	t0 = Time.get_ticks_usec()
	current_scene.leave_to_title()
	w = await _wait_ready(func(): return _title_ready())
	_emit({"scenario": "to_title", "ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1),
			"worst_frame_ms": w.worst, "frames_over_100ms": w.long, "static_mem_mb": _mb(Performance.MEMORY_STATIC)})

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	print("[perf] wrote ", out_path)
	Settings.mark_clean_exit()
	quit(0)


func _mb(monitor: int) -> float:
	return snappedf(Performance.get_monitor(monitor) / 1048576.0, 0.1)


func _title_ready() -> bool:
	var m = current_scene
	return m != null and m.get("hud") != null and m.hud.title and not Transition.is_loading()


func _map_ready(map: String) -> bool:
	var m = current_scene
	return m != null and m.get("map_id") == map and m.get("player") != null and not Transition.is_loading()


## Frames until `done` holds (at most 60 s): the longest single frame on the way and how many took over 100 ms.
func _wait_ready(done: Callable) -> Dictionary:
	var worst := 0.0
	var long := 0
	var last := Time.get_ticks_usec()
	var start := last
	while Time.get_ticks_usec() - start < 60_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		worst = maxf(worst, ms)
		if ms > 100.0:
			long += 1
		if done.call():
			break
	return {"worst": snappedf(worst, 0.1), "long": long}


func _freeze_match(main) -> void:
	main.director.timer = 9999.0
	main.player.set("god_mode", true)
	main.player.health = 100000.0
	Engine.max_fps = 0
	seed(1717)


## One frame's wall time around `work` and the frame drawn after it.
func _timed_frame(work: Callable) -> Dictionary:
	await process_frame
	var t0 := Time.get_ticks_usec()
	work.call()
	var call_ms := (Time.get_ticks_usec() - t0) / 1000.0
	await process_frame
	return {"call": call_ms, "frame": (Time.get_ticks_usec() - t0) / 1000.0}


func _bench_ui(main) -> void:
	var hud = main.hud
	var gs = hud.gunsmith
	var r := await _timed_frame(func(): gs.open())
	await frames(20)
	_emit({"scenario": "gunsmith_open", "call_ms": snappedf(r.call, 0.01), "first_frame_ms": snappedf(r.frame, 0.01)})
	gs._build_rows()
	var att_rows: Array = []
	for i in gs._rows.size():
		var row: Dictionary = gs._rows[i]
		if row.t == "att" and row.s == "primary":
			att_rows.append(i)
	# every primary attachment slot stepped forward 3 times and back again: the loadout ends as it started
	var calls: Array[float] = []
	var frames_ms: Array[float] = []
	for dir in [1, -1]:
		for i in att_rows:
			for k in 3:
				r = await _timed_frame(func(): gs._change(i, dir))
				calls.append(r.call)
				frames_ms.append(r.frame)
	gs.is_open = false
	gs.preview.set_active(false)
	_emit({"scenario": "attachment_change", "changes": calls.size(), "avg_call_ms": _avg(calls), "max_call_ms": _max(calls),
			"avg_frame_ms": _avg(frames_ms), "max_frame_ms": _max(frames_ms)})
	await frames(20)
	r = await _timed_frame(func(): hud.armory.open())
	await frames(20)
	_emit({"scenario": "armory_open", "call_ms": snappedf(r.call, 0.01), "first_frame_ms": snappedf(r.frame, 0.01)})
	hud.armory.is_open = false
	await frames(20)


func _bench_switch(main) -> void:
	var p = main.player
	var times: Array[float] = []
	for k in 24:
		var r := await _timed_frame(func(): p.switch_to((p.weapon_index + 1) % p.weapons.size()))
		times.append(r.frame)
		await frames(20)
	_emit({"scenario": "weapon_switch", "switches": times.size(), "avg_frame_ms": _avg(times), "max_frame_ms": _max(times)})


func _avg(v: Array[float]) -> float:
	var s := 0.0
	for x in v:
		s += x
	return snappedf(s / maxf(v.size(), 1), 0.01)


func _max(v: Array[float]) -> float:
	var m := 0.0
	for x in v:
		m = maxf(m, x)
	return snappedf(m, 0.01)
