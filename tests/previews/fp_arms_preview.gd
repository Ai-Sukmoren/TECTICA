extends SceneTree
## First-person view of the base character's arms: holding a rifle, aiming it,
## holding a pistol, and looking down at the body. Needs a window.
##   godot --path . -s res://tests/previews/fp_arms_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func shot(out: String, tag: String) -> void:
	for i in 20: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/fparms_%s.jpg" % tag, 0.85)

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
	p.set_loadout([["hk33", {}], ["g17", {}]])
	p.global_position = Vector3(0, 0.05, 40)
	p.aim_yaw = PI
	for i in 40: await physics_frame
	await shot(out, "rifle_hold")
	Input.action_press("aim")
	for i in 30: await physics_frame
	await shot(out, "rifle_aim")
	Input.action_release("aim")
	p.fp_pitch = -1.1
	await shot(out, "look_down")
	p.fp_pitch = -0.08
	p.switch_to(1)
	for i in 60: await physics_frame
	await shot(out, "pistol_hold")
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
