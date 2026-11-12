extends SceneTree
## Renders a preview PNG of the Quaternius base characters with a few hair
## combos. Needs a window (not --headless):
##   godot --path . -s res://tools/preview_models.gd -- <out.png>

const DIR := "res://assets/thirdparty/quaternius_base_characters/"
const LOOKS := [
	["Superhero_Male_FullBody", "Hair_Buzzed", "Hair_Beard", "Eyebrows_Regular"],
	["Superhero_Male_FullBody", "Hair_SimpleParted", "Eyebrows_Regular"],
	["Superhero_Female_FullBody", "Hair_Long", "Eyebrows_Female"],
	["Superhero_Female_FullBody", "Hair_Buns", "Eyebrows_Female"],
	["Superhero_Female_FullBody", "Hair_BuzzedFemale", "Eyebrows_Female"],
]


func _initialize() -> void:
	var out := "user://model_preview.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	get_root().size = Vector2i(1600, 900)
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
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.31, 0.33)
	floor.material_override = fm
	world.add_child(floor)

	var spacing := 1.1
	var x0 := -spacing * (LOOKS.size() - 1) * 0.5
	for i in LOOKS.size():
		var holder := Node3D.new()
		holder.position = Vector3(x0 + i * spacing, 0, 0)
		world.add_child(holder)
		for part in LOOKS[i]:
			var ps := load(DIR + part + ".gltf") as PackedScene
			if ps == null:
				push_error("could not load " + part)
				continue
			holder.add_child(ps.instantiate())

	var cam := Camera3D.new()
	cam.fov = 34.0
	world.add_child(cam)
	cam.transform = Transform3D.IDENTITY.looking_at(Vector3(0, 0.95, 0) - Vector3(0, 1.15, 6.4)).translated(Vector3(0, 1.15, 6.4))
	cam.current = true

	for f in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(out)
	print("saved ", ProjectSettings.globalize_path(out))
	quit()
