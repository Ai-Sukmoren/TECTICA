extends SceneTree
## Flying kick from the side: a running jump into a kick on an infected, with
## two more beside it caught by the shockwave. Saves numbered frames for a clip
## (needs a window).
##   godot --path . -s res://tests/previews/flying_kick_preview.gd -- <out_dir>
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
	root.size = Vector2i(1280, 720)
	Engine.max_fps = 60
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
	main.tod.set("hour", 15.0)
	seed(7)
	for k in 3:
		main.director._spawn_one("walker")
	await physics_frame
	var zs: Array = main.enemies.slice(0, 3)
	var spots := [Vector3(2.0, 0.05, 25.6), Vector3(3.5, 0.05, 25.0), Vector3(0.6, 0.05, 25.1)]
	for i in 3:
		zs[i].set("player", null)
		zs[i].health = 500.0
		zs[i].global_position = spots[i]
		zs[i].aim_yaw = 0.0
	p.global_position = Vector3(2.0, 0.05, 33.0)
	p.aim_yaw = 0.0
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 42.0
	cam.global_position = Vector3(9.5, 1.6, 28.5)
	cam.look_at(Vector3(2.0, 1.0, 28.0))
	cam.make_current()
	await frames(20)
	var f := 0
	# run up, jump, kick in the air
	for i in 150:
		p.health = 100000.0
		if i < 32:
			p.sprinting = true
			p.velocity.x = 0.0
			p.velocity.z = -6.6
		if i == 32:
			p.jump_request = p.JUMP_SPEED
		if i == 40:
			p._start_kick(Vector3(0, 0, -1), true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg("%s/fk_%03d.jpg" % [out, f], 0.9)
		f += 1
	print("frames ", f)
	Settings.mark_clean_exit()
	quit(0)
