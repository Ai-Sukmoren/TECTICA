extends SceneTree
## Renders the TOKYO map (overview, the play area, the kerb ramp, the wall) and the
## Remington 700 side-on, bare and with its bolt open. Needs a window.
##   godot --path . -s res://tests/previews/tokyo_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")

func _initialize() -> void:
	call_deferred("run")

func snap(out: String, name: String) -> void:
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/tokyo_" + name + ".jpg", 0.88)

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "tokyo_preview"
	Main.saved_mode = "zombie"
	Main.saved_map = "tokyo"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	main.tod.set("hour", 15.0)
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
		[Vector3(-34, 36, 34), Vector3(0, 4, 0), "overview"],
		[Vector3(34, 30, -30), Vector3(0, 4, 0), "overview_ne"],
		[Vector3(-16, 5.5, 18), Vector3(-8, 4, 0), "plaza"],
		[Vector3(-14, 5.3, 16.5), Vector3(-10.5, 3.2, 13.2), "ramp"],
		[Vector3(-6, 5.0, 18), Vector3(-6, 6, -6), "road"],
		[Vector3(-12, 5.0, -2), Vector3(-19, 6, 10), "wall"],
	]
	for s in shots:
		cam.global_position = s[0]
		cam.look_at(s[1])
		cam.make_current()
		await snap(out, String(s[2]))
	# the Remington 700 on a stand: bare, then with the bolt open
	cam.fov = 30.0
	var w = Weapon.new()
	main.add_child(w)
	w.setup("m700", {})
	w.global_position = Vector3(-14, 5.0, 8)
	w.rotation = Vector3(0, PI * 0.5, 0)
	cam.global_position = Vector3(-13.95, 5.05, 10.3)
	cam.look_at(Vector3(-13.95, 5.05, 8))
	cam.make_current()
	await snap(out, "m700")
	w.setup("m700", {"muzzle": "suppressor", "underbarrel": "laser"})
	await snap(out, "m700_att")
	quit()
