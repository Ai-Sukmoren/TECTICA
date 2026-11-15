extends SceneTree
## Polyart zombies walking, running and attacking: a strip of frames across
## each cycle, seen from the side. Needs a window.
##   godot --path . -s res://tests/previews/zombie_anim_preview.gd -- <out_dir>
const Zombie = preload("res://scripts/characters/zombie.gd")
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	main.director.timer = 999.0
	main.hud.hide()
	main.player.rig.hide()
	main.camera_rig.set_process(false)
	for z in get_nodes_in_group("zombies"):
		z.queue_free()
	var base: Vector3 = main.player.global_position + Vector3(0, 0, -11)
	# zombies turn to face the player: put them side-on by moving the player away along +X
	main.player.global_position = base + Vector3(40, 0, 0)
	main.player.set_physics_process(false)
	var zs: Array = []
	var modes := ["walk", "run", "attack"]
	for i in 3:
		var z := Zombie.new()
		z.skin_id = "polyart"
		main.add_child(z)
		z.global_position = base + Vector3((i - 1) * 2.2, 0, 0)
		z.init_zombie(main.player, "walker", 100000, 2, 0, i)
		z.set_physics_process(false)
		z.aim_yaw = -PI * 0.5   # face along +X, side-on to the camera
		z.rig.snap_yaw(z.aim_yaw)
		var label := Label3D.new()
		label.text = modes[i].to_upper()
		label.position = Vector3(0, 2.3, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		z.add_child(label)
		zs.append(z)
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.global_position = base + Vector3(0, 1.3, 6.5)
	cam.look_at(base + Vector3(0, 0.95, 0))
	cam.fov = 50
	cam.current = true
	for k in 6:
		for f in 9:
			await process_frame
			zs[0].rig.move_velocity = Vector3(1.6, 0, 0)
			zs[0].rig.sprint_target = 0.0
			zs[1].rig.move_velocity = Vector3(5.0, 0, 0)
			zs[1].rig.sprint_target = 1.0
			zs[2].rig.move_velocity = Vector3.ZERO
		if k % 3 == 0:
			zs[2].play_attack_anim(0.9)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/zombie_%d.jpg" % k, 0.85)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
