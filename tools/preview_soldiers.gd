extends SceneTree
## Renders player-style soldiers in several rig states (idle, aim, crouch,
## sprint, reload) to check the skinned model follows the procedural rig.
## Needs a window:  godot --path . -s res://tools/preview_soldiers.gd -- <out.png> [fp]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://soldiers.png"
	get_root().size = Vector2i(1920, 1080)
	var world := Node3D.new()
	get_root().add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.19)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position.y = -0.5
	floor.add_child(cs)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fmi.mesh = pm
	floor.add_child(fmi)
	world.add_child(floor)

	# [label, setup callable]
	var states := ["idle", "aim", "crouch", "sprint", "reload", "turned"]
	var rigs: Array = []
	# bare soldiers (Player.setup_player needs the whole game running)
	var Soldier = load("res://scripts/characters/soldier.gd")
	var Palettes = load("res://scripts/core/palettes.gd")
	for i in states.size():
		var s = Soldier.new()
		world.add_child(s)
		s.position = Vector3((i - (states.size() - 1) * 0.5) * 1.3, 0, 0)
		s.setup_soldier(Palettes.player(), ["akm"], 0, 0, PI if states[i] == "turned" else 0.0)
		s.use_character_model(Color.WHITE if i % 2 == 0 else Color(1.25, 1.05, 0.72))
		rigs.append(s)
	for f in 5:
		await process_frame
	for i in states.size():
		var r = rigs[i].rig
		match states[i]:
			"aim": r.aim_target = 1.0
			"crouch": r.crouch_target = 1.0
			"sprint":
				r.sprint_target = 1.0
				r.move_velocity = Vector3(0, 0, -5.5)
			"reload": r.play_reload(3.0, true)
	var cam := Camera3D.new()
	cam.fov = 34.0
	world.add_child(cam)
	var front := args.has("front")
	if args.has("curlneg"):
		load("res://scripts/characters/model_skin.gd").curl_sign = -1.0
	var close := -1
	for a in args:
		if a.begins_with("close"):
			close = int(a.substr(5))
	var eye := Vector3(1.2, 1.6, -4.0) if front else Vector3(2.5, 1.9, 7.5)
	if args.has("rig"):
		for s in rigs:
			for mi in s.rig._body_meshes:
				mi.visible = true
				mi.transparency = 0.55
	var look := Vector3(0, 0.95, 0)
	if close >= 0:
		var c: Vector3 = rigs[close].position
		look = c + Vector3(0, 1.0, 0)
		eye = c + Vector3(0.55, 1.35, -1.5)
	cam.transform = Transform3D.IDENTITY.looking_at(look - eye).translated(eye)
	cam.current = true
	for f in 50:
		for i in states.size():
			if states[i] == "sprint":
				rigs[i].rig.move_velocity = Vector3(0, 0, -5.5)
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
