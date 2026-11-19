extends "res://tests/previews/fps_rig_fit_preview.gd"
## Knife first-person diagnostics: stills of one knife through every state, from the eye and from a side camera
## that shows the grip (fingers, thumb, wrist). godot --path . -s res://tests/previews/knife_diag.gd -- <out> [knife_id]
var side_cam: Camera3D
var id := "knife_combat"

func snap(tag: String) -> void:
	var oh = rig._operator_hands[1]
	var hinv: Transform3D = rig.hands[1].global_transform.affine_inverse()
	var g: Transform3D = rig.weapon.grip.global_transform
	var mroot: Transform3D = rig.weapon._model_root.global_transform
	var handle_c: Vector3 = hinv * mroot.origin
	var tilt: Node3D = rig.weapon._model_root.get_node("Tilt")
	var axis: Vector3 = (hinv.basis * tilt.global_transform.basis.z).normalized()
	print("GRIP %s handle_centre_in_hand=%s handle_axis_in_hand=%s" % [tag, handle_c.snapped(Vector3.ONE * 0.001), axis.snapped(Vector3.ONE * 0.01)])
	cam.global_transform = rig.fp_eye
	cam.fov = 86.0
	cam.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s_eye.png" % tag))
	# side view of the hand: from the right, level with the grip
	var h: Vector3 = rig.hands[1].global_position
	side_cam.global_position = h + rig.fp_eye.basis.x * 0.32 + rig.fp_eye.basis.y * 0.04 + rig.fp_eye.basis.z * 0.06
	side_cam.look_at(h, rig.fp_eye.basis.y)
	side_cam.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s_side.png" % tag))

func step(n: int) -> void:
	for i in n:
		rig._animate(1.0 / 60.0)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	if args.size() > 1: id = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(960, 540)
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
	sun.light_energy = 1.5
	scene.add_child(sun)
	cam = Camera3D.new(); cam.near = 0.02; scene.add_child(cam)
	side_cam = Camera3D.new(); side_cam.near = 0.01; side_cam.fov = 40; scene.add_child(side_cam)
	rig = Rig.new()
	scene.add_child(rig)
	rig.build(Palettes.player())
	rig.set_process(false)
	rig.set_first_person(true)
	var w := Weapon.new()
	w.setup(id)
	rig.set_weapon(w, [])
	w.set_process(false)
	step(90)
	await snap("01_idle")
	rig.move_velocity = Vector3(0.4, 0, -2.7)
	step(40)
	await snap("02_walk")
	rig.move_velocity = Vector3(0, 0, -6)
	rig.sprint_target = 1.0
	step(60)
	await snap("03_sprint")
	rig.move_velocity = Vector3.ZERO
	rig.sprint_target = 0.0
	step(60)
	rig.play_slash(0.5)
	var dur: float = rig._slash_dur
	var marks := [0.05, 0.12, 0.2, 0.3, 0.55]
	var t := 0.0
	for k in marks.size():
		while rig.slash_t >= 0.0 and rig.slash_t < marks[k]:
			rig._animate(1.0 / 240.0)
		await snap("04_slash_%d" % k)
	step(60)
	rig.play_inspect()
	for k in [0.14, 0.36, 0.56, 0.78]:
		while rig.inspect_t >= 0.0 and rig.inspect_t < k:
			rig._animate(1.0 / 60.0)
		await snap("05_inspect_%.2f" % k)
	step(120)
	rig.play_switch(0.5)
	step(8)
	await snap("06_draw")
	quit()
