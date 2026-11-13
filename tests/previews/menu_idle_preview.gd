extends SceneTree
## Two frames of the title-screen operator a few seconds apart (needs a window):
## they must differ, i.e. the character is animating while the menu is paused.
##   godot --path . -s res://tests/previews/menu_idle_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 40: await process_frame
	var hud = current_scene.hud
	var cam = hud.menu_cam
	var yaws: Array = []
	for k in 2:
		cam.shot = 0
		cam.t = 3.0
		await create_timer(0.3 if k == 0 else 3.2, true, false, true).timeout
		cam.shot = 0
		cam.t = 3.0
		await process_frame
		await RenderingServer.frame_post_draw
		yaws.append(current_scene.player.rig.aim_yaw)
		root.get_texture().get_image().save_jpg(out + "/menu_idle_%d.jpg" % k, 0.85)
	print("[idle] rig yaw %.3f -> %.3f  paused=%s" % [yaws[0], yaws[1], paused])
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
