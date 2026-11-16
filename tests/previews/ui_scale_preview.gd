extends SceneTree
## Screenshots of the VIDEO settings tab and the HUD at the current window size,
## to check UI SCALE (settings.gd apply_ui_scale).
##   godot --path . --resolution 2560x1440 -s res://tests/previews/ui_scale_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Settings.ensure()
	Settings.v.window_mode = 0
	Settings.apply()
	Main.saved_mode = "zombie"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var tag := "%dx%d" % [root.size.x, root.size.y]
	print("window=", root.size, " factor=", root.content_scale_factor, " canvas=", root.get_visible_rect().size)
	var hud = current_scene.hud
	hud.title = false
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/hud_%s.jpg" % tag, 0.85)
	hud.settings_open = true
	hud._settings_set_tab(Settings.TABS.find("VIDEO"))
	hud.settings_row = 16
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/settings_%s.jpg" % tag, 0.85)
	Settings.mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
