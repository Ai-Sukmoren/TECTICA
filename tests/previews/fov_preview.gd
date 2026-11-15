extends SceneTree
## First-person and top-down views at given FOVs, for comparing defaults
## (needs a window).
##   godot --path . -s res://tests/previews/fov_preview.gd -- <out_dir> fp_fov,td_fov [fp_fov,td_fov...]
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var pairs: Array = a.slice(1) if a.size() > 1 else ["78,38", "86,44"]
	Settings.ensure()
	Settings.v.window_mode = 0
	root.size = Vector2i(1600, 900)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	main.director.timer = 9999.0
	var p = main.player
	p.health = 100000.0
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(2.0, 0.05, 30)
	for pair in pairs:
		var f := String(pair).split(",")
		Settings.v.fov = float(f[0])
		Settings.v.tactical_fov = float(f[1])
		main.apply_graphics()
		for view in ["fp", "td"]:
			p.aim_yaw = 0.0
			p.set_first_person(view == "fp")
			await frames(50)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg("%s/fov_%s_%s.jpg" % [out, view, f[0] if view == "fp" else f[1]], 0.9)
	print("done")
	Settings.mark_clean_exit()
	quit(0)
