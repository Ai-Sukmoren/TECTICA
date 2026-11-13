extends SceneTree
## Aiming down sights through given optics (first person, needs a window).
##   godot --path . -s res://tests/previews/ads_preview.gd -- <out_dir> gun:optic [gun:optic...]
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var combos: Array = a.slice(1) if a.size() > 1 else ["m4a1:prism", "mk23:minidot"]
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
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(2.0, 0.05, 30)
	p.aim_yaw = 0.0
	for combo in combos:
		var parts := String(combo).split(":")
		p.set_loadout([[parts[0], {"optic": parts[1]}], ["knife_combat", {}]])
		p.set_first_person(true)
		p.fp_pitch = -0.02
		for aim in [false, true]:
			if aim:
				Input.action_press("aim")
			else:
				Input.action_release("aim")
			await frames(60)
			await RenderingServer.frame_post_draw
			var f := "%s/ads_%s_%s_%s.jpg" % [out, parts[0], parts[1], "ads" if aim else "hip"]
			root.get_texture().get_image().save_jpg(f, 0.9)
			print("saved ", f)
		Input.action_release("aim")
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
