extends SceneTree
## Forest map at eye level: four directions from several spots across the map,
## to spot stray or untextured geometry (needs a window).
##   godot --path . -s res://tests/previews/forest_ground_preview.gd -- <out_dir>
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
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(120)
	var main = current_scene
	main.player.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("hour", 13.0)
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.far = 1000.0
	cam.fov = 60.0
	cam.fov = 75.0
	root.size = Vector2i(800, 450)
	var spots := [Vector3(0, 0, 0), Vector3(-45, 0, -30), Vector3(45, 0, -30), Vector3(-60, 0, 40), Vector3(60, 0, 40), Vector3(0, 0, 70), Vector3(85, 0, 0), Vector3(-85, 0, 0)]
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var i := 0
	for sp in spots:
		var q := PhysicsRayQueryParameters3D.create(sp + Vector3(0, 80, 0), sp + Vector3(0, -40, 0))
		var hit := space.intersect_ray(q)
		var ground: float = hit.position.y if not hit.is_empty() else 0.0
		for k in 4:
			var a := k * PI * 0.5
			cam.global_position = Vector3(sp.x, ground + 1.7, sp.z)
			cam.look_at(cam.global_position + Vector3(sin(a), -0.05, cos(a)))
			cam.make_current()
			await frames(12)
			await snap("%s/g_%02d.jpg" % [out, i])
			i += 1
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
