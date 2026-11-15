extends SceneTree
## Forest map from the air: straight down plus four oblique corners, to spot
## stray or untextured geometry (needs a window).
##   godot --path . -s res://tests/previews/forest_overview_preview.gd -- <out_dir>
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
	root.size = Vector2i(1600, 900)
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(120)
	var main = current_scene
	main.player.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("hour", 13.0)
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.far = 1000.0
	cam.fov = 60.0
	var c: Vector3 = main.player.global_position
	var shots := [["top", Vector3(c.x, 140, c.z + 0.01), Vector3(c.x, 0, c.z)]]
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		shots.append(["corner%d" % k, c + Vector3(cos(a) * 70.0, 45.0, sin(a) * 70.0), c])
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.FORWARD if s[0] == "top" else Vector3.UP)
		cam.make_current()
		await frames(30)
		await snap("%s/forest_%s.jpg" % [out, s[0]])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
