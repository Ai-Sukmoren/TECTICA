extends SceneTree
## Renders every .gltf/.glb in a folder side by side to a PNG, playing an
## animation whose name contains `anim` (default "Idle") when the model has one.
## Needs a window (not --headless):
##   godot --path . -s res://tools/preview_pack.gd -- <res://folder/> <out.png> [anim]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if args.size() > 0 else "res://assets/thirdparty/quaternius_modular_characters/"
	var out := args[1] if args.size() > 1 else "user://pack_preview.png"
	var want := args[2] if args.size() > 2 else "Idle"
	get_root().size = Vector2i(1920, 1080)
	var world := Node3D.new()
	get_root().add_child(world)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.19)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.31, 0.33)
	floor.material_override = fm
	world.add_child(floor)

	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in ["gltf", "glb"]:
			files.append(f)
	files.sort()
	var models: Array[Node3D] = []
	for f in files:
		var ps := load(dir.path_join(f)) as PackedScene
		if ps == null:
			push_error("could not load " + f)
			continue
		var inst := ps.instantiate() as Node3D
		world.add_child(inst)
		models.append(inst)
		var found := inst.find_children("*", "AnimationPlayer", true, false)
		var ap: AnimationPlayer = found[0] if found.size() > 0 else null
		if ap:
			var pick := ""
			for n in ap.get_animation_list():
				if want.to_lower() in String(n).to_lower():
					pick = n
					break
			if pick != "":
				ap.play(pick)
			print(f, " animations: ", ap.get_animation_list().size(), " playing: ", pick)
		else:
			print(f, " has no AnimationPlayer")

	# two rows if there are many
	var per_row := mini(models.size(), 6)
	var spacing := 1.25
	for i in models.size():
		var row := i / per_row
		var col := i % per_row
		var count := mini(per_row, models.size() - row * per_row)
		models[i].position = Vector3((col - (count - 1) * 0.5) * spacing, 0, -row * 2.2)

	var rows := (models.size() + per_row - 1) / maxi(per_row, 1)
	var cam := Camera3D.new()
	cam.fov = 38.0
	world.add_child(cam)
	var eye := Vector3(0, 2.4 + rows * 0.6, 7.0 + rows * 1.2)
	var target := Vector3(0, 0.9, -(rows - 1) * 1.1)
	cam.transform = Transform3D.IDENTITY.looking_at(target - eye).translated(eye)
	cam.current = true

	for f in 45:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))
	quit()
