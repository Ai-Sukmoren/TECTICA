extends SceneTree
## Screenshots the MGP7 and ZC57 in the operator's hands: first person (hip
## and aiming), third person, and with a skin, next to the M4A1 / MK23 for
## comparison. Needs a window.
##   godot --path . -s res://tests/pack_gun_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Loadout = preload("res://scripts/core/loadout.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(960, 540)
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
	for spec in [["mgp7", "zc57"], ["mp7", "mk23"]]:
		p.set_loadout([[spec[0], {}], [spec[1], {}]])
		for slot in 2:
			var id: String = spec[slot]
			p.switch_to(slot)
			for i in 50: await physics_frame
			if p.weapon_index != slot:
				p.weapon_index = slot
				p._equip_current()
				for i in 20: await physics_frame
			for aim in [false, true]:
				p.aiming = aim
				for i in 40: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_jpg(out + "/gun_%s_fp_%s.jpg" % [id, "ads" if aim else "hip"], 0.85)
			p.aiming = false
			# third person close-up
			p.set_first_person(false)
			main.camera_rig.first_person = false
			main.camera_rig.override = true
			var cam := Camera3D.new()
			main.add_child(cam)
			cam.fov = 40.0
			var fwd := Vector3(-sin(p.aim_yaw), 0, -cos(p.aim_yaw))
			var right := Vector3(-fwd.z, 0, fwd.x)
			cam.global_position = p.global_position + Vector3.UP * 1.5 + fwd * 0.9 + right * 1.1
			cam.look_at(p.global_position + Vector3.UP * 1.3 + fwd * 0.25)
			cam.make_current()
			for i in 30: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(out + "/gun_%s_tp.jpg" % id, 0.85)
			cam.global_position = p.global_position + Vector3.UP * 3.0 + right * 0.3
			cam.look_at(p.global_position + Vector3.UP * 1.2 + fwd * 0.3)
			for i in 10: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(out + "/gun_%s_top.jpg" % id, 0.85)
			cam.queue_free()
			main.camera_rig.override = false
			p.set_first_person(true)
			main.camera_rig.first_person = true
			for i in 10: await process_frame
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
