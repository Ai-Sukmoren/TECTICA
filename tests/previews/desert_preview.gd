extends SceneTree
## Renders the ATOMIC ACRES desert map, the Tequila Zombie Cafe, the boss-wave
## test flash and the MARLIN 1895 (lever shut and open). Needs a window.
##   godot --path . -s res://tests/previews/desert_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")

func _initialize() -> void:
	call_deferred("run")

func snap(out: String, name: String) -> void:
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/desert_" + name + ".jpg", 0.88)

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "desert"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	main.tod.set("hour", 17.2)
	main.camera_rig.set_process(false)
	main.camera_rig.set_physics_process(false)
	main.hud.visible = false
	main.director.set_physics_process(false)
	main.player.visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 62.0
	var shots := [
		[Vector3(0, 46, 40), Vector3(0, 0, -6), "overview"],
		[Vector3(-3, 1.7, 14), Vector3(0, 1.4, -12), "cul_de_sac"],
		[Vector3(-12.6, 4.9, -10.5), Vector3(8, 1.0, -9), "upstairs_window"],
		[Vector3(4, 2.4, 15), Vector3(16, 2.6, 22), "cafe"],
		[Vector3(7.5, 1.7, 17.5), Vector3(11, 1.5, 18.6), "sale_sign"],
		[Vector3(-4, 2.0, -18), Vector3(0, 1.4, -29), "shelter"],
		[Vector3(9, 3.2, -19), Vector3(17, 0.8, -29), "ufo_site"],
	]
	for s in shots:
		cam.global_position = s[0]
		cam.look_at(s[1])
		cam.make_current()
		await snap(out, String(s[2]))
	# boss wave: the test shot, a moment after it goes off
	cam.global_position = Vector3(-3, 1.7, 14)
	cam.look_at(Vector3(0, 3, -12))
	main.level.test_flash()
	for i in 4: await process_frame
	main.level._flash.set_meta("t", 1.2)
	await snap(out, "test_flash")
	main.level._flash.set_meta("t", 99.0)
	# the Marlin on a stand, lever shut and lever open
	main.tod.set("hour", 13.0)
	var w = Weapon.new()
	main.add_child(w)
	w.setup("marlin")
	w.global_position = Vector3(0, 1.4, 30)
	w.rotation = Vector3(0, PI * 0.5, 0)
	cam.fov = 30.0
	cam.global_position = Vector3(0.05, 1.48, 31.9)
	cam.look_at(Vector3(0.05, 1.42, 30))
	await snap(out, "marlin")
	if w.lever != null:
		w.lever.rotation.x = 0.9
		w.bolt.position = Vector3(0, 0, 0.075)
		await snap(out, "marlin_lever_open")
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
