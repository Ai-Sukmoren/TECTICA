extends SceneTree
## Isolated, bounded GPU review of every weapon. No map, AI or saved settings.
## --script res://tests/previews/weapon_studio.gd -- <absolute-output-directory>
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var scene: Node3D
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 30
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_4X
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.045, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.8, 1.0)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world := WorldEnvironment.new()
	world.environment = environment
	scene.add_child(world)
	for settings in [[Vector3(-40, -35, 0), 2.6, Color(1.0, 0.91, 0.8)], [Vector3(20, 140, 0), 1.8, Color(0.6, 0.78, 1.0)]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = settings[0]
		light.light_energy = settings[1]
		light.light_color = settings[2]
		scene.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	scene.add_child(camera)
	var args := OS.get_cmdline_user_args()
	var output := args[0] if args.size() else OS.get_user_data_dir().path_join("weapon-review")
	DirAccess.make_dir_recursive_absolute(output)
	for id in Data.PRIMARIES + Data.SECONDARIES:
		for variant in ["factory", "custom"]:
			var att: Dictionary = Data.WEAPONS[id].defaults.duplicate()
			if variant == "custom":
				for slot in Data.SLOTS:
					var choices: Array = Data.WEAPONS[id].options[slot]
					att[slot] = choices.back()
			var weapon := Weapon.new()
			weapon.setup(id, att)
			scene.add_child(weapon)
			if weapon.has_method("apply_charm"):
				weapon.apply_charm("dog_tags")
			var bounds := _bounds(weapon)
			var center := bounds.get_center()
			camera.size = maxf(0.28, maxf(bounds.size.z, bounds.size.y) * 0.8)
			camera.position = center + Vector3(1.5, 0.65, 0.65)
			camera.look_at(center)
			for frame in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := output.path_join("%s-%s.png" % [id, variant])
			var error := root.get_texture().get_image().save_png(path)
			print("STUDIO ", id, " ", variant, " ", error_string(error))
			weapon.queue_free()
			await process_frame
	quit()

func _bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var item := pending.pop_back() as Node
		if item is MeshInstance3D and item.mesh != null:
			var box: AABB = item.global_transform * item.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		pending.append_array(item.get_children())
	return bounds
