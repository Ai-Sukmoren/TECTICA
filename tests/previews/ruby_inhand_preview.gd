extends SceneTree
## Mythic Ruby with its 02 patch in the operator's hands: first person by day
## and at dusk, and a third-person close-up (needs a window).
##   godot --path . -s res://tests/previews/ruby_inhand_preview.gd -- <out_dir> [gun]
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

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
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var gun: String = a[1] if a.size() > 1 else "ak47"
	Settings.ensure()
	Settings.v.window_mode = 0
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
	p.global_position = Vector3(2.0, 0.05, 30)
	p.aim_yaw = 0.0
	p.set_loadout([[gun, {}, "ruby", {"side": 2, "u": 0.5, "v": 0.6, "s": 1.0}], ["knife_combat", {}]])
	for hour in [13.0, 19.4]:
		main.tod.set("hour", hour)
		p.set_first_person(true)
		p.fp_pitch = -0.05
		await frames(50)
		await snap("%s/ruby_%s_fp_%s.jpg" % [out, gun, "day" if hour < 15.0 else "dusk"])
	main.tod.set("hour", 13.0)
	p.set_first_person(false)
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 32.0
	cam.global_position = p.global_position + Vector3(1.1, 1.55, -0.6)
	cam.look_at(p.global_position + Vector3(0.05, 1.3, -0.35))
	cam.make_current()
	await frames(30)
	await snap("%s/ruby_%s_tp.jpg" % [out, gun])
	Settings.mark_clean_exit()
	quit(0)
