extends SceneTree
## How each knife sits in the hand: first-person idle and a third-person
## close-up. Needs a window.
##   godot --path . -s res://tests/previews/knife_hold_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 999.0
	main.hud.visible = false
	p.global_position = Vector3(0, 0.05, 30)
	p.aim_yaw = 0.0
	for knife in ["knife_combat", "karambit", "butterfly"]:
		p.set_loadout([["m4a1", {}], ["mk23", {}], [knife, {}]])
		p.weapon_index = 2
		p._equip_current()
		p.set_first_person(true)
		main.camera_rig.first_person = true
		for i in 60: await physics_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/hold_%s_fp.jpg" % knife, 0.85)
		p.set_first_person(false)
		main.camera_rig.first_person = false
		main.camera_rig.override = true
		var cam := Camera3D.new()
		main.add_child(cam)
		cam.fov = 30.0
		cam.make_current()
		for i in 20: await process_frame
		# close-ups aimed at the right hand: from the front-right and from the side
		var hand: Vector3 = p.rig.hands[1].global_position
		var fwd := Vector3(-sin(p.aim_yaw), 0, -cos(p.aim_yaw))
		var right := Vector3(-fwd.z, 0, fwd.x)
		for view in [["front", fwd * 0.75 + right * 0.35 + Vector3.UP * 0.12], ["side", right * 0.8 + Vector3.UP * 0.05], ["full", -fwd * 2.2 + right * 0.9 + Vector3.UP * 0.1]]:
			cam.global_position = hand + (view[1] as Vector3)
			cam.look_at(hand + Vector3.UP * (0.05 if view[0] != "full" else -0.25))
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(out + "/hold_%s_tp_%s.jpg" % [knife, view[0]], 0.85)
		cam.queue_free()
		main.camera_rig.override = false
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
