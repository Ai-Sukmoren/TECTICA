extends SceneTree
## First-person frames through the inspect animation for a rifle, a pistol
## and each knife, plus a knife slash. Needs a window.
##   godot --path . -s res://tests/previews/inspect_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/insp_%s.jpg" % name, 0.82)

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 999.0
	main.hud.visible = false
	p.global_position = Vector3(0, 0.05, 30)
	p.aim_yaw = 0.0
	for knife in ["knife_combat", "karambit", "butterfly"]:
		p.set_loadout([["m4a1", {}], ["mk23", {}], [knife, {}]])
		for i in 20: await physics_frame
		var slots := [2] if knife != "knife_combat" else [0, 1, 2]
		for slot in slots:
			p.switch_to(slot)
			for i in 70: await physics_frame
			var id: String = p.current_weapon().id
			p.rig.play_inspect()
			var marks := [0.2, 0.4, 0.55, 0.78]
			var k := 0
			while p.rig.inspect_t >= 0.0 and k < marks.size():
				await process_frame
				if p.rig.inspect_t >= marks[k]:
					await shot(out, "%s_%d" % [id, k])
					k += 1
			for i in 40: await physics_frame
		if knife == "knife_combat":
			# slash: forehand then backhand
			for n in 2:
				p.current_weapon().cooldown = 0.0
				p.try_fire(p.global_position + Vector3(0, 1.2, -3))
				for i in 6: await process_frame
				await shot(out, "slash_%d" % n)
				for i in 40: await physics_frame
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
