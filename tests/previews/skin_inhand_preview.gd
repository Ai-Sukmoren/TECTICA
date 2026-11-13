extends SceneTree
## Skinned guns in the operator's hands: first person, third person close-up,
## and first person again after a reload (the magazine is swapped). Needs a window.
##   godot --path . -s res://tests/previews/skin_inhand_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(path, 0.88)
	print("saved ", path)

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(2.0, 0.05, 30)
	p.aim_yaw = 0.0
	for gun in ["mgp7", "zc57", "mp7"]:
		for skin in ["woodland", "gilded_royale"]:
			p.set_loadout([[gun, {}, skin], ["knife_combat", {}]])
			p.set_first_person(true)
			p.fp_pitch = -0.05
			await frames(40)
			await snap("%s/inhand_%s_%s_fp.jpg" % [out, gun, skin])
			# third person close-up
			p.set_first_person(false)
			main.camera_rig.override = true
			var cam := Camera3D.new()
			main.add_child(cam)
			cam.fov = 35.0
			cam.global_position = p.global_position + Vector3(1.1, 1.55, -0.6)
			cam.look_at(p.global_position + Vector3(0.05, 1.3, -0.35))
			cam.make_current()
			await frames(20)
			await snap("%s/inhand_%s_%s_tp.jpg" % [out, gun, skin])
			cam.queue_free()
			main.camera_rig.override = false
			# reload: the magazine is pulled and a fresh one inserted
			p.set_first_person(true)
			p.current_weapon().ammo = 0
			p.start_reload()
			await frames(int(p.reload_duration * 60.0) + 20)
			await snap("%s/inhand_%s_%s_reloaded.jpg" % [out, gun, skin])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
