extends SceneTree
## Weapon inspect as other players see it (third person), front and side,
## through the animation for a rifle, a pistol and a knife (needs a window).
##   godot --path . -s res://tests/previews/inspect_tp_preview.gd -- <out_dir> [weapon_id...]
const Main = preload("res://scripts/main.gd")
const TIMES := [0.2, 0.36, 0.52, 0.66, 0.78, 0.9]

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(480, 360)
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
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(2.0, 0.05, 30)
	p.aim_yaw = 0.0
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 35.0
	var args := OS.get_cmdline_user_args()
	var specs: Array = [["m4a1", "rifle"], ["mk23", "pistol"], ["knife_combat", "knife"]]
	if args.size() > 1:
		specs = []
		for a in args.slice(1):
			specs.append([a, a])
	for spec in specs:
		p.set_loadout([[spec[0], {}]])
		p.set_first_person(false)
		await frames(30)
		p.aim_yaw = 0.0
		await frames(10)
		var fwd := Vector3(0, 0, -1)
		var right := Vector3(1, 0, 0)
		for view in [["front", fwd * 1.6 + right * 0.35], ["side", right * 1.6 + fwd * 0.3], ["left", -right * 1.6 + fwd * 0.3]]:
			for t in TIMES:
				p.rig.inspect_t = t
				cam.global_position = p.global_position + Vector3(0, 1.45, 0) + view[1]
				cam.look_at(p.global_position + Vector3(0, 1.3, 0))
				cam.make_current()
				await frames(2)
				p.rig.inspect_t = t
				await frames(1)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_jpg("%s/tp_%s_%s_%02d.jpg" % [out, spec[1], view[0], int(t * 100)], 0.9)
		p.rig.inspect_t = -1.0
	print("done")
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
