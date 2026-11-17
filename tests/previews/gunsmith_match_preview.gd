extends SceneTree
## Campaign pause menu with the GUNSMITH entry, then the gunsmith open mid-match
## (needs a window), and its gun turned by hand and zoomed in.
##   godot --path . -s res://tests/previews/gunsmith_match_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

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
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1600, 900)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var hud = current_scene.hud
	paused = true
	await frames(10)
	await snap(out + "/pause_menu.jpg")
	hud._pause_activate(hud._pause_items().find("GUNSMITH"))
	await frames(30)
	await snap(out + "/gunsmith_in_match.jpg")
	# turned by hand and zoomed in on the action
	var gs = hud.gunsmith
	gs._manual_rotation = true
	gs._pivot.rotation = Vector3(0.25, -2.2, 0)
	gs.zoom = 0.45
	await frames(20)
	await snap(out + "/gunsmith_zoomed.jpg")
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
