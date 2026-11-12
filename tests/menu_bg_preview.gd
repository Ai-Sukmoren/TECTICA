extends SceneTree
## Screenshots each shot of the cinematic title camera (needs a window).
##   godot --path . -s res://tests/menu_bg_preview.gd -- <out_dir> [town]
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie" if args.size() > 1 else "ch1"
	Main.saved_map = "town" if args.size() > 1 else "forest"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 40: await process_frame
	var hud = current_scene.hud
	var cam = hud.menu_cam
	for k in cam.shots.size():
		cam.shot = k
		cam.t = cam.SHOT_TIME * 0.5
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/menubg_%s_%d.jpg" % [Main.saved_map, k], 0.85)
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
