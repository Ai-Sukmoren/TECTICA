extends "res://tests/previews/fps_rig_fit_preview.gd"
## Gun grip diagnostics for the operator glove: for every gun held at the hip in first person, a close side view of
## the firing hand and of the support hand, and where each weapon grip marker sits in its hand's own space (the
## glove's curled fingers form a channel centred about (-0.005 * side, 0, -0.068) in front of the palm heel).
## godot --path . -s res://tests/previews/grip_diag.gd -- <out> [ids...]
var side_cam: Camera3D

func shoot(path: String, hand: Node3D, from_side: float) -> void:
	var h := hand.global_position
	var e: Transform3D = rig.fp_eye
	side_cam.global_position = h + e.basis.x * 0.26 * from_side + e.basis.y * 0.05 + e.basis.z * 0.04
	side_cam.look_at(h, e.basis.y)
	side_cam.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(640, 480)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.55, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.environment.ambient_light_energy = 0.9
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	scene.add_child(sun)
	cam = Camera3D.new(); cam.near = 0.02; scene.add_child(cam)
	side_cam = Camera3D.new(); side_cam.near = 0.01; side_cam.fov = 45; scene.add_child(side_cam)
	var ids: Array = args.slice(1) if args.size() > 1 else Data.PRIMARIES + Data.SMGS + Data.SECONDARIES
	for id in ids:
		rig = Rig.new()
		scene.add_child(rig)
		rig.build(Palettes.player())
		rig.set_process(false)
		rig.set_first_person(true)
		var w := Weapon.new()
		w.setup(id)
		rig.set_weapon(w, [])
		w.set_process(false)
		for i in 90:
			rig._animate(1.0 / 60.0)
		for k in 2:
			var hand: Node3D = rig.hands[1 - k]
			var marker: Node3D = w.grip if k == 0 else w.support
			var palm: Node3D = w.palm_grip if k == 0 else w.palm_support
			var inv := hand.global_transform.affine_inverse()
			print("GRIP %-8s %s marker_in_hand=%s palm_socket_in_hand=%s" % [id, "right" if k == 0 else "left ",
					(inv * marker.global_position).snapped(Vector3.ONE * 0.001),
					(inv * palm.global_position).snapped(Vector3.ONE * 0.001)])
			await shoot(out.path_join("%s_%s.png" % [id, "R" if k == 0 else "L"]), hand, 1.0 if k == 0 else -1.0)
		rig.free()
	quit()
