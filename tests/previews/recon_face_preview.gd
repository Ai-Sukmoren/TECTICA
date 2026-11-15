extends SceneTree
## Recon outfit head and chest close-up from eye level (needs a window).
##   godot --path . -s res://tests/previews/recon_face_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Collection = preload("res://scripts/skins/collection.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1200, 900)
	load("res://scripts/core/profile.gd").current = "lilin"
	Collection.ensure()
	var old_outfit: String = Collection.outfit
	Collection.outfit = "recon"
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
	cam.fov = 30.0
	var shots := [["head", Vector3(0.5, 1.6, -1.5), 1.55], ["body", Vector3(0.6, 1.2, -3.2), 0.95]]
	for s in shots:
		cam.global_position = p.global_position + (s[1] as Vector3)
		cam.look_at(p.global_position + Vector3(0, s[2], 0))
		cam.make_current()
		await frames(30)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg("%s/recon_%s.jpg" % [out, s[0]], 0.92)
	Collection.outfit = old_outfit
	print("done")
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
