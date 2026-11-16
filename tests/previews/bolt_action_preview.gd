extends SceneTree
## Turn-bolt rifles close up from the right (bolt-handle side), above and behind:
## closed, handle lifted, bolt drawn back. Needs a window.
##   godot --path . -s res://tests/previews/bolt_action_preview.gd -- <out_dir>
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
	Main.saved_map = "town"
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
	for id in ["l96a1", "mosin"]:
		var w = Weapon.new()
		main.add_child(w)
		w.setup(id, Data.WEAPONS[id].defaults)
		w.global_position = Vector3(0, 1.4, 60)
		print("%s bolt rest %s knob %s action %s" % [id, w.bolt_rest, w.charge.position, w.bolt_action])
		for s in [0.0, 1.0, 2.0]:
			w.bolt.rotation = Vector3(0, 0, float(w.bolt_action[0]) * clampf(s, 0, 1))
			w.bolt.position = w.bolt_rest + Vector3(0, 0, float(w.bolt_action[1]) * clampf(s - 1.0, 0, 1))
			var focus: Vector3 = w.global_transform * (w.bolt_rest + Vector3(0, 0, -0.04))
			cam.global_position = focus + Vector3(0.42, 0.16, 0.12)
			cam.look_at(focus)
			for i in 6: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(out + "/bolt_%s_%d.jpg" % [id, int(s)], 0.88)
		w.queue_free()
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
