extends SceneTree
## Radar crops at a few headings in Dead End and the forest, for comparing
## radar drawing changes (needs a window).
##   godot --path . -s res://tests/previews/radar_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	Settings.ensure()
	Settings.v.window_mode = 0
	root.size = Vector2i(1600, 900)
	load("res://scripts/core/profile.gd").current = "lilin"
	for map in ["town", "forest"]:
		Main.saved_mode = "zombie"
		Main.saved_map = map
		Main.quick_restart = true
		Main.saved_first_person = true
		change_scene_to_file("res://scenes/main.tscn")
		await frames(90)
		var main = current_scene
		main.director.timer = 9999.0
		var p = main.player
		p.health = 100000.0
		p.global_position = Vector3(2.0, 0.05, 30) if map == "town" else main.level.player_spawn
		for yaw in [0.0, 0.7, 2.0, -2.6]:
			p.aim_yaw = yaw
			await frames(6)
			await RenderingServer.frame_post_draw
			var img: Image = root.get_texture().get_image()
			img.get_region(Rect2i(1600 - 128 - 110, 900 - 140 - 110, 220, 220)).save_png("%s/radar_%s_%d.png" % [out, map, int(yaw * 10)])
	print("done")
	Settings.mark_clean_exit()
	quit(0)
