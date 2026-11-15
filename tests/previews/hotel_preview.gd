extends SceneTree
## Hotel Meridian in Dead End: from the crossroads by day and at dusk, from the
## roof, and inside the stairwell (needs a window).
##   godot --path . -s res://tests/previews/hotel_preview.gd -- <out_dir>
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
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	main.player.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 55.0
	var shots := [
		["day_crossroads", 13.0, Vector3(4, 4, 6), Vector3(-25, 8, -22)],
		["day_corner", 13.0, Vector3(-6, 3, -4), Vector3(-25, 7, -24)],
		["dusk_crossroads", 19.2, Vector3(4, 4, 6), Vector3(-25, 8, -22)],
		["roof", 13.0, Vector3(-30, 19.8, -16), Vector3(0, 12, 10)],
		["stairwell", 13.0, Vector3(-19.5, 5.4, -22.5), Vector3(-16.2, 3.6, -27.5)],
	]
	for s in shots:
		main.tod.set("hour", s[1])
		cam.global_position = s[2]
		cam.look_at(s[3])
		cam.make_current()
		await frames(40)
		await snap("%s/hotel_%s.jpg" % [out, s[0]])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
