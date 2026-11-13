extends SceneTree
## Screenshot of the CONTROLS settings tab (needs a window).
##   godot --path . -s res://tests/previews/controls_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var hud = current_scene.hud
	hud.settings_open = true
	hud._settings_set_tab(Settings.TABS.find("CONTROLS"))
	hud.settings_row = 10
	hud._binding = "reload"
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/controls.jpg", 0.85)
	hud._binding = ""
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
