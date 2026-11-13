extends SceneTree
## Crosshair settings: the settings screen with the live preview, and the
## in-game crosshair in several styles and colours (first person). Needs a window.
##   godot --path . -s res://tests/previews/crosshair_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(path, 0.9)
	print("saved ", path)

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1600, 900)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var hud = main.hud
	main.director.timer = 9999.0
	main.player.health = 100000.0
	main.tod.set("hour", 14.0)
	var saved := Settings.v.duplicate()
	# settings screen, crosshair style row selected
	Settings.v.crosshair = 3
	Settings.v.crosshair_color = 1
	hud.settings_open = true
	hud.settings_tab = 0
	var rows: Array = Settings.rows(0)
	for i in rows.size():
		if String(rows[i][0]) == "crosshair":
			hud.settings_row = i
	await frames(20)
	await snap(out + "/crosshair_settings.jpg")
	hud.settings_open = false
	await frames(5)
	# in game: a few combinations
	for combo in [[1, 1, 1.0], [3, 2, 1.0], [5, 3, 1.2], [6, 0, 1.0], [7, 5, 1.4], [0, 0, 1.0]]:
		Settings.v.crosshair = combo[0]
		Settings.v.crosshair_color = combo[1]
		Settings.v.crosshair_size = combo[2]
		await frames(12)
		await snap("%s/crosshair_%s_%s.jpg" % [out, Settings.CROSSHAIRS[combo[0]].replace(" ", "").replace("+", "_"), Settings.CROSSHAIR_COLORS[combo[1]]])
	for k in saved:
		Settings.v[k] = saved[k]
	Settings.mark_clean_exit()
	quit(0)
