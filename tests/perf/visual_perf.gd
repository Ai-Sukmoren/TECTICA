extends SceneTree
## Rendering cost of both zombie maps in first-person and top-down at the
## HIGH preset: average FPS (uncapped, vsync off) and draw calls per frame.
## Needs a window:  godot --path . -s res://tests/perf/visual_perf.gd
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	root.size = Vector2i(1600, 900)
	var a := OS.get_cmdline_user_args()
	var preset := int(a[0]) if a.size() > 0 else 2   # 0 SAFE, 1 LOW, 2 HIGH, 3 ULTRA
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	load("res://scripts/core/profile.gd").current = "lilin"
	for map in ["forest", "town"]:
		Main.saved_mode = "zombie"
		Main.saved_map = map
		Main.quick_restart = true
		Main.saved_first_person = false
		change_scene_to_file("res://scenes/main.tscn")
		await frames(90)
		var main = current_scene
		for k in Settings.PRESET_VALUES:
			Settings.v[k] = Settings.PRESET_VALUES[k][preset]
		Settings.v.preset = preset
		main.apply_graphics()
		Engine.max_fps = 0
		main.director.timer = 9999.0
		main.player.health = 100000.0
		for view in ["fp", "td"]:
			main.player.set_first_person(view == "fp")
			await frames(60)
			var t0 := Time.get_ticks_usec()
			var n := 240
			await frames(n)
			var dt := (Time.get_ticks_usec() - t0) / 1e6
			var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			print("%s %s: %.0f fps, %d draw calls, %.1fM primitives" % [map, view, n / dt, dc, prims / 1e6])
	Settings.mark_clean_exit()
	quit(0)
