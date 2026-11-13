extends SceneTree
## Screenshot of the MULTIPLAYER menu with join codes (needs a window).
##   godot --path . -s res://tests/previews/mp_menu_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var hud = current_scene.hud
	hud._mp_open()
	hud.mp_row = 3
	preload("res://scripts/net/net.gd").join_ip = "B7AHG"
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/mp_menu.jpg", 0.85)
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
