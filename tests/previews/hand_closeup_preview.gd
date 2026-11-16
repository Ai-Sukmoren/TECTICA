extends SceneTree
## Close-ups of each hand on the gun at idle, from the left, right and below.`n## godot --path . -s res://tests/previews/hand_closeup_preview.gd -- out_dir ids...
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
var cam: Camera3D

func _initialize() -> void:
	run.call_deferred()

func snap(path: String, at: Vector3, from: Vector3) -> void:
	cam.look_at_from_position(from, at, Vector3.UP if absf((at - from).normalized().y) < 0.95 else Vector3.FORWARD)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(800, 600)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.055, 0.075, 0.10)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	cam = Camera3D.new()
	cam.near = 0.01
	cam.fov = 40
	scene.add_child(cam)
	cam.current = true
	for id in args.slice(1):
		var rig = Rig.new()
		scene.add_child(rig)
		rig.build(Palettes.player())
		rig.set_process(false)
		rig.set_first_person(true)
		var w = Weapon.new()
		w.setup(id)
		rig.set_weapon(w, [])
		w.set_process(false)
		rig.aim_target = 0.0
		rig.sprint_target = 0.0
		rig._free_arm = 0
		rig.fp_pitch = 0
		for i in 100:
			rig._animate(1.0 / 60.0)
		var wb: Basis = w.global_basis.orthonormalized()
		for i in 2:
			var tag := "L" if i == 0 else "R"
			var at: Vector3 = rig.hands[i].global_position
			# weapon local: +X right, +Y up, -Z muzzle
			await snap("%s/%s_%s_left.png" % [out, id, tag], at, at + wb * Vector3(-0.32, 0.04, 0))
			await snap("%s/%s_%s_right.png" % [out, id, tag], at, at + wb * Vector3(0.32, 0.04, 0))
			await snap("%s/%s_%s_below.png" % [out, id, tag], at, at + wb * Vector3(0.05, -0.32, 0.02))
			await snap("%s/%s_%s_lowleft.png" % [out, id, tag], at, at + wb * Vector3(-0.22, -0.22, -0.08))
			cam.fov = 14.0
			await snap("%s/%s_%s_eye.png" % [out, id, tag], at, rig.fp_eye.origin)
			cam.fov = 40.0
		print("CLOSEUP ", id)
		rig.weapon = null
		w.free()
		rig.queue_free()
		await process_frame
	quit()
