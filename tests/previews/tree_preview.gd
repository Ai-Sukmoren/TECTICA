extends SceneTree
## Close looks at the forest vegetation / a town car from a free camera.
##   godot --path . -s res://tests/previews/tree_preview.gd -- <out_dir> <tag> [map] [x y z tx ty tz]...
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var tag: String = a[1]
	var map: String = a[2] if a.size() > 2 else "forest"
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = map
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	for k in Settings.PRESET_VALUES:
		Settings.v[k] = Settings.PRESET_VALUES[k][2]
	main.apply_graphics()
	main.hud.visible = false
	main.director.timer = 9999.0
	main.player.health = 100000.0
	main.tod.set("hour", 14.0)
	get_nodes_in_group("camera_rig")[0].override = true
	var cam := Camera3D.new()
	cam.fov = 60
	root.add_child(cam)
	var shots: Array = []
	var i := 3
	while i + 5 < a.size():
		shots.append([Vector3(float(a[i]), float(a[i + 1]), float(a[i + 2])), Vector3(float(a[i + 3]), float(a[i + 4]), float(a[i + 5]))])
		i += 6
	var n := 0
	for s in shots:
		cam.global_position = s[0]
		cam.look_at(s[1])
		for f in 40:
			cam.make_current()
			load("res://scripts/world/nature.gd").set_view(cam.global_position)
			await process_frame
		await RenderingServer.frame_post_draw
		var f := "%s/%s_%d.jpg" % [out, tag, n]
		root.get_texture().get_image().save_jpg(f, 0.9)
		print("saved ", f)
		n += 1
	Settings.mark_clean_exit()
	quit(0)
