extends SceneTree
## Renders the dropkick at four points of its timeline, side view (needs a GPU):
##   godot --path . -s res://tests/dropkick_preview.gd -- <out_dir>
const Player = preload("res://scripts/characters/player.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.max_fps = 30
	var out := OS.get_cmdline_user_args()[0]
	root.size = Vector2i(900, 600)
	var scene := Node3D.new(); root.add_child(scene); current_scene = scene
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.5, 0.55)
	env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = 0.6
	scene.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation = Vector3(-0.7, 0.4, 0); scene.add_child(sun)
	var ground := MeshInstance3D.new(); ground.mesh = PlaneMesh.new(); ground.mesh.size = Vector2(20, 20); scene.add_child(ground)
	var p := Player.new()
	scene.add_child(p)
	p.setup_player(0.0, [["m4a1", {}]], false, "")
	p.set_physics_process(false)
	p.set_process(false)
	p.set_process_input(false)
	p.set_process_unhandled_input(false)
	p.rig.snap_yaw(0.0)
	var cam := Camera3D.new(); scene.add_child(cam)
	for k in 20: await process_frame
	var fwd := p.rig.global_transform.basis * (Basis(Vector3.UP, p.rig.lower_yaw) * Vector3.FORWARD); var side := fwd.cross(Vector3.UP).normalized(); print("fwd ", fwd); cam.position = p.global_position + Vector3(0, 1.0, 0) + side * 4.5 + fwd * 0.5; cam.look_at(p.global_position + Vector3(0, 0.9, 0) + fwd * 0.5); cam.fov = 50; cam.current = true
	for c in root.find_children("*", "Camera3D", true, false):
		if c != cam:
			print("other cam ", c.get_path()); c.current = false; c.set_process(false); c.get_parent().set_process(false)
	for k in 20: await process_frame
	for t in [0.12, 0.3, 0.45, 0.85]:
		p.rig.play_kick(1000.0)
		p.rig.kick_t = t
		for k in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("dropkick_%02d.png" % int(t * 100)))
	quit(0)
