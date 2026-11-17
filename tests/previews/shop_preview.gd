extends SceneTree
## Screenshots the zombie shop: the arcade cabinet it is bought at, the HUD
## between waves, the open shop with points to spend, after buying a gun, and the
## attachment rows for it (needs a window).
##   godot --path . -s res://tests/previews/shop_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(path, 0.88)
	print("saved ", path)

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	root.size = Vector2i(1600, 900)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "tokyo"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var p = main.player
	var dir = main.director
	p.health = 100.0
	dir.wave = 2
	dir.timer = 17.0
	dir.shop.points = 2350
	main.tod.set("hour", 18.2)
	p.set_first_person(true)
	# third person, looking at the arcade from the operator's side
	p.set_first_person(false)
	var cam := Camera3D.new()
	main.add_child(cam)
	var arc = main.arcade
	cam.global_position = arc.global_position + arc.global_transform.basis.z * 2.6 + arc.global_transform.basis.x * 0.9 + Vector3(0, 1.6, 0)
	cam.look_at(arc.global_position + Vector3(0, 1.1, 0))
	cam.make_current()
	main.hud.visible = false
	await frames(30)
	await shot(out + "/shop_arcade.jpg")
	main.hud.visible = true
	main.camera_rig.snap()
	cam.queue_free()
	p.set_first_person(true)
	p.global_position = arc.global_position + arc.global_transform.basis.z * 1.5
	await frames(40)
	await shot(out + "/shop_hud.jpg")
	main.hud._open_shop()
	main.hud.shop_index = 7
	await frames(20)
	await shot(out + "/shop_open.jpg")
	dir.shop.buy("gun_m700", p)
	main.hud._shop_msg = "BOUGHT  ·  REMINGTON 700  ·  -2300 PTS"
	main.hud._shop_msg_t = 2.0
	main.hud.shop_index = 4
	await frames(20)
	await shot(out + "/shop_bought.jpg")
	main.hud.shop_index = 9
	await frames(20)
	await shot(out + "/shop_attachments.jpg")
	# FIT TO switched to the pistol: its attachments, one picked on the turntable
	dir.shop.fit_to = String(p.weapons[1].id)
	var rows: Array = main.hud._shop_rows_now()
	for i in rows.size():
		if String(rows[i].id) == "fit_to":
			main.hud.shop_index = i + 1
	main.hud._shop_follow = true
	await frames(20)
	await shot(out + "/shop_fit_pistol.jpg")
	main.hud._close_shop()
	await frames(30)
	await shot(out + "/shop_after.jpg")
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
