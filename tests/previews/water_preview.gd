extends SceneTree
## Wading splash in the forest creek, seen from the bank (needs a window).
##   godot --path . -s res://tests/previews/water_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1600, 900)
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var lv = main.level
	main.player.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("hour", 14.0)
	var i0: int = lv.creek.size() / 4
	var c: Vector2 = lv.creek[i0]
	var along: Vector2 = (lv.creek[i0 + 1] - c).normalized()
	var side := Vector2(-along.y, along.x)
	var feet := Vector3(c.x, -0.35, c.y)
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 40.0
	cam.global_position = feet + Vector3(side.x * 4.5, 1.3, side.y * 4.5)
	cam.look_at(feet + Vector3(0, 0.25, 0))
	cam.make_current()
	await frames(20)
	for k in 3:
		main.player._on_footstep(feet + Vector3(along.x, 0, along.y) * (k * 0.6 - 0.6), 1.0)
		await frames(5)
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/water_splash.jpg", 0.92)
	print("saved ", out + "/water_splash.jpg")
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
