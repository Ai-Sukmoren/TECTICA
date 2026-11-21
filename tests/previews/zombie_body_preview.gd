extends SceneTree
## Zombie bodies side by side (looks check for the skinned crowd body): six infected of different kinds and
## variants frozen mid-stride in front of a fixed camera, plus one with a severed arm and leg.
##   godot --path . -s res://tests/previews/zombie_body_preview.gd -- <out.png>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	seed(7)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"; Main.saved_map = "warehouse"; Main.quick_restart = true; Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	var kinds := ["walker", "runner", "walker", "brute", "walker", "runner", "walker"]
	var zs := []
	for i in kinds.size():
		main.director._spawn_one(kinds[i])
		var z = main.enemies[main.enemies.size() - 1]
		z.set_physics_process(false)
		z.global_position = p.global_position + Vector3(-3.0 + i * 1.0, 0, -4.0)
		z.aim_yaw = 0.0
		z.max_health = 100000.0
		z.health = 100000.0
		z.reset_physics_interpolation()
		zs.append(z)
	for i in 40: await process_frame
	zs[6].sever_limb("arm0", "lower", Vector3.LEFT)
	zs[6].sever_limb("leg1", "upper", Vector3.LEFT)
	for i in 20: await process_frame
	for z in zs:
		z.rig.set_process(false)   # freeze the pose
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 50.0
	cam.make_current()
	cam.global_position = p.global_position + Vector3(0, 1.4, -0.5)
	cam.look_at(p.global_position + Vector3(0, 1.0, -4.0))
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit()
