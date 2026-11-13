extends SceneTree
## Night vision at midnight: each map with it off and on, first person and
## top-down (needs a window).
##   godot --path . -s res://tests/previews/nvg_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

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
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	for map in ["town", "forest"]:
		Main.saved_mode = "zombie"
		Main.saved_map = map
		Main.quick_restart = true
		Main.saved_first_person = true
		change_scene_to_file("res://scenes/main.tscn")
		await frames(90)
		var main = current_scene
		var p = main.player
		p.health = 100000.0
		main.director.timer = 9999.0
		main.tod.set("running", false)
		main.tod.set("hour", 0.5)
		p.set_flashlight(false)
		p.flashlight_manual = true
		if map == "town":
			p.global_position = Vector3(-30.0, 0.05, -30.0)   # backyards, away from the street lamps
			p.aim_yaw = 0.6
		for view in ["fp", "td"]:
			p.set_first_person(view == "fp")
			for on in [false, true]:
				p.nvg_on = on
				await frames(50)
				await snap("%s/nvg_%s_%s_%s.jpg" % [out, map, view, "on" if on else "off"])
		if map == "town":
			# a lit street: lamps should glow, not white the screen out
			p.global_position = Vector3(6.0, 0.05, 20.0)
			p.aim_yaw = 0.0
			p.set_first_person(true)
			p.nvg_on = true
			await frames(50)
			await snap(out + "/nvg_town_street_on.jpg")
		p.nvg_on = false
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
