extends SceneTree
## Frame sequence of zombies dying (shot from the front), close up from the
## side, to judge the death animation (needs a window).
##   godot --path . -s res://tests/previews/zombie_death_preview.gd -- <out_dir> [kind ...]
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var kinds: Array = a.slice(1) if a.size() > 1 else ["walker", "runner", "brute"]
	root.size = Vector2i(640, 480)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("running", false)
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(1.5, 0.05, 40)
	p.aim_yaw = 0.0
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 40.0
	cam.make_current()
	for kind in kinds:
		main.director._spawn_one(String(kind))
		var z = main.enemies[main.enemies.size() - 1]
		z.set_physics_process(true)
		z.global_position = p.global_position + Vector3(0, 0, -4.0)
		z.aim_yaw = PI
		z.reset_physics_interpolation()
		cam.global_position = z.global_position + Vector3(2.3, 0.9, -0.2)
		cam.look_at(z.global_position + Vector3(0, 0.55, -0.5))
		await frames(20)
		var shots: Array = []
		z.apply_damage(z.health + 50.0, z.global_position + Vector3(0, 1.3, 0.2), Vector3(0, 0, -1), p)
		for f in 16:
			await frames(6)   # 0.1 s
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			shots.append(img)
		var sheet := Image.create(640 * 4, 480 * 4, false, Image.FORMAT_RGB8)
		for i in shots.size():
			sheet.blit_rect(shots[i], Rect2i(0, 0, 640, 480), Vector2i((i % 4) * 640, (i / 4) * 480))
		sheet.resize(1600, 1200)
		sheet.save_jpg("%s/death_%s.jpg" % [out, kind], 0.88)
		print("saved death_", kind)
		z.queue_free()
		main.enemies.erase(z)
		await frames(5)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
