extends SceneTree
## Every gun in the asset lineup, side-on in daylight, one picture each, then
## a few with the model attachments fitted (needs a window).
##   godot --path . -s res://tests/previews/lowpoly_guns_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "desert"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	main.tod.set("hour", 13.0)
	main.camera_rig.set_process(false)
	main.camera_rig.set_physics_process(false)
	main.hud.visible = false
	main.director.set_physics_process(false)
	main.player.visible = false
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	var rigs: Array = []
	for id in Data.PRIMARIES + Data.SECONDARIES:
		rigs.append([id, {}, id])
	rigs += [["mgp7", {"optic": "holo", "muzzle": "suppressor", "underbarrel": "laser"}, "att_mgp7"],
			["as_val", {"optic": "reddot", "underbarrel": "laser"}, "att_as_val"],
			["hk33", {"muzzle": "heavy_suppressor"}, "att_hk33"],
			["aug_a1", {"muzzle": "suppressor"}, "att_aug_a1"],
			["g17", {"muzzle": "suppressor"}, "att_g17"],
			["mgp7", {"optic": "reddot", "muzzle": "flash_hider"}, "att_mgp7_dot"]]
	for rg in rigs:
		var id: String = rg[0]
		var w = Weapon.new()
		main.add_child(w)
		w.setup(id, rg[1])
		w.global_position = Vector3(0, 1.4, 30)
		w.rotation = Vector3(0, PI * 0.5, 0)
		var pistol: bool = w.is_pistol()
		var d := 0.95 if pistol else 2.2
		cam.global_position = Vector3(-0.05 if pistol else 0.05, 1.45, 30 + d)
		cam.look_at(Vector3(cam.global_position.x, 1.42, 30))
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/gun_" + String(rg[2]) + ".jpg", 0.88)
		w.queue_free()
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
