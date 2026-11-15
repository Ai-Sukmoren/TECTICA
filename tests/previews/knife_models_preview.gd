extends SceneTree
## The model knives side-on (needs a window); the butterfly also half-flipped.
##   godot --path . -s res://tests/previews/knife_models_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")

func _initialize() -> void:
	call_deferred("run")

func snap(out: String, n: String) -> void:
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/knife_" + n + ".jpg", 0.88)

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(960, 540)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "desert"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	main.tod.set("hour", 13.0)
	main.camera_rig.set_process(false)
	main.hud.visible = false
	main.director.set_physics_process(false)
	main.player.visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 25.0
	for id in ["karambit", "butterfly"]:
		var w = Weapon.new()
		main.add_child(w)
		w.setup(id)
		w.global_position = Vector3(0, 1.4, 30)
		w.rotation = Vector3(0, PI * 0.5, 0)
		cam.global_position = Vector3(0, 1.45, 30.75)
		cam.look_at(Vector3(0, 1.45, 30))
		await snap(out, id)
		if w._handles.size() == 2 and w._handles[0] != null:
			w._handles[0].rotation.x = PI * 0.5
			w._handles[1].rotation.x = -PI * 0.5
			await snap(out, id + "_flip")
		w.queue_free()
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
