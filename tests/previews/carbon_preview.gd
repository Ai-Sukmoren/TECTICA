extends SceneTree
## Carbon Phantom outfit + Mythic Carbon gun skin (admin account; needs a window):
## the Armory outfit tab, the operator wearing it with a carbon M4 (third
## person front, back, first person), and a dusk shot for the glowing trims.
##   godot --path . -s res://tests/previews/carbon_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Outfits = preload("res://scripts/skins/outfits.gd")
const Collection = preload("res://scripts/skins/collection.gd")

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
	load("res://scripts/core/profile.gd").current = "admin"
	Collection.ensure()
	var old_outfit: String = Collection.outfit
	Collection.outfit = "carbon"
	# armory outfit tab
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	change_scene_to_file("res://scenes/main.tscn")
	await frames(60)
	var arm = current_scene.hud.armory
	arm.open()
	arm.tab = 2
	arm.outfit_i = Outfits.ids().find("carbon")
	await frames(50)
	await snap(out + "/carbon_armory.jpg")
	arm.close()
	# in game
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	p.set_loadout([["m4a1", {"optic": "reddot"}, "carbon_mythic"], ["mk23", {}, "carbon_mythic"], ["knife_combat", {}]])
	p.global_position = Vector3(2.0, 0.05, 30)
	p.aim_yaw = 0.0
	for hour in [13.5, 19.2]:
		main.tod.set("hour", hour)
		var tag := "day" if hour < 15.0 else "dusk"
		main.camera_rig.override = true
		var cam := Camera3D.new()
		main.add_child(cam)
		cam.fov = 32.0
		for view in [["front", Vector3(1.2, 1.5, -2.6)], ["back", Vector3(-1.4, 1.7, 2.4)]]:
			cam.global_position = p.global_position + (view[1] as Vector3)
			cam.look_at(p.global_position + Vector3(0, 1.15, 0))
			cam.make_current()
			await frames(30)
			await snap("%s/carbon_%s_%s.jpg" % [out, tag, view[0]])
		cam.queue_free()
		main.camera_rig.override = false
		p.set_first_person(true)
		p.fp_pitch = -0.04
		await frames(40)
		await snap("%s/carbon_%s_fp.jpg" % [out, tag])
		p.set_first_person(false)
	Collection.outfit = old_outfit
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
