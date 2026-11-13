extends SceneTree
## First-person frames across a stride: walking, sprinting (rifle and pistol)
## and aiming while walking. Needs a window.
##   godot --path . -s res://tests/previews/fp_run_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(out: String, tag: String, n: int, gap: int) -> void:
	for k in n:
		for i in gap: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/fprun_%s_%d.jpg" % [tag, k], 0.8)

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
	p.set_loadout([["m4a1", {}], ["mk23", {}]])
	for i in 30: await physics_frame
	for kind in ["rifle", "pistol"]:
		if kind == "pistol":
			p.switch_to(1)
			for i in 60: await physics_frame
		for mode in ["walk", "sprint", "aimwalk"]:
			p.global_position = Vector3(0, 0.05, 40)
			p.aim_yaw = PI   # face south down the empty road
			p.velocity = Vector3.ZERO
			for i in 10: await physics_frame
			Input.action_press("move_forward", 0.55 if mode == "walk" else 1.0)
			if mode == "sprint":
				Input.action_press("sprint")
			if mode == "aimwalk":
				Input.action_press("aim")
			for i in 45: await physics_frame
			await frames(out, "%s_%s" % [kind, mode], 4, 6)
			for a in ["move_forward", "sprint", "aim"]:
				Input.action_release(a)
			for i in 40: await physics_frame
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
