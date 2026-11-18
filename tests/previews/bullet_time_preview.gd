extends SceneTree
## FOCUS meter and bullet time on screen (first person, needs a window): the HUD at rest, then mid-jump in bullet time.
##   godot --path . -s res://tests/previews/bullet_time_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")


func _initialize() -> void:
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(path, 0.9)
	print("saved ", path)


func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "tokyo"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(120)
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	p.set_first_person(true)
	p.fp_pitch = -0.05
	p.focus = 0.8
	await frames(30)
	await shot(out + "/focus_meter.jpg")
	Input.action_press("vault")
	await frames(3)
	Input.action_release("vault")
	await frames(8)
	Input.action_press("aim")
	for i in 40:
		await process_frame
		if p.bullet_time and Engine.time_scale < 0.45:
			break
	await frames(6)
	await shot(out + "/bullet_time.jpg")
	Input.action_release("aim")
	quit(0)
