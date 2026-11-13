extends SceneTree
## Renders gameplay in whatever renderer the engine was started with, to check
## the browser (Compatibility / OpenGL) path. Needs a window.
##   godot --rendering-method gl_compatibility --path . -s res://tests/compat_preview.gd -- <out_dir> [town]
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town" if args.size() > 1 else "forest"
	Main.quick_restart = true
	var t0 := Time.get_ticks_msec()
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	print("[compat] renderer=%s driver=%s load=%d ms" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), Time.get_ticks_msec() - t0])
	main.director.timer = 999.0
	for k in 6: main.director._spawn_one()
	for z in main.enemies:
		z.global_position = main.player.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-9, -4))
	for i in 60: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/compat_%s.jpg" % Main.saved_map, 0.85)
	var frames := 0
	var t := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t < 2_000_000:
		await process_frame
		frames += 1
	print("[compat] %.0f fps, draw calls %d, objects %d" % [frames / 2.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
