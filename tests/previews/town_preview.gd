extends SceneTree
## Renders three views of the DEAD END town map (needs a window, not --headless).
##   godot --path . -s res://tests/previews/town_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(960, 540)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	main.tod.set("hour", 19.6)
	main.camera_rig.set_process(false)
	main.camera_rig.set_physics_process(false)
	main.hud.visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var shots := [
		[Vector3(0, 70, 55), Vector3(0, 0, -2), "overview"],
		[Vector3(7, 2.2, 16), Vector3(-2, 1.2, -6), "street"],
		[Vector3(26, 3.0, 2), Vector3(17, 1.5, -16), "gas_station"],
	]
	for s in shots:
		cam.global_position = s[0]
		cam.look_at(s[1])
		cam.make_current()
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/town_" + String(s[2]) + ".jpg", 0.85)
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
