extends SceneTree
## Renders three views of the NEIGHBOURHOOD city map (needs a window, not --headless).
##   godot --path . -s res://tests/previews/town_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(960, 540)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "city"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	main.tod.set("hour", 13.0)
	main.camera_rig.set_process(false)
	main.camera_rig.set_physics_process(false)
	main.hud.visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var args := OS.get_cmdline_user_args()
	var span: float = float(args[1]) if args.size() > 1 else 60.0
	var shots := [
		[Vector3(0, span * 1.25, 0.1), Vector3(0, 0, 0), "top"],
		[Vector3(span * 0.35, span * 0.22, span * 0.35), Vector3(0, 0, 0), "oblique"],
		[Vector3(0, 1.6, 0), Vector3(0, 1.6, -10), "street"],
	]
	for s in shots:
		cam.global_position = s[0]
		if String(s[2]) == "street":
			cam.global_position = main.player.global_position + Vector3(0, 1.6, 0)
			cam.look_at(cam.global_position + Vector3(0, 0, -10))
			cam.make_current()
			for i in 20: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(out + "/city_street.jpg", 0.85)
			continue
		cam.look_at(s[1])
		cam.make_current()
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/city_" + String(s[2]) + ".jpg", 0.85)
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
