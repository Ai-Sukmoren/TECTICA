extends SceneTree
## Renders the asset-pack-4 props in a row to a PNG (needs a GPU):
##   godot --path . -s res://tests/previews/pack_props_preview.gd -- <out.png>
const PP = preload("res://scripts/core/pack_props.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Engine.max_fps = 30
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://pack4.png"
	root.size = Vector2i(1280, 640)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.32, 0.35)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	scene.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 4.2)
	cam.rotation.x = -0.3
	scene.add_child(cam)
	var row := [["sandbag", 0.3], ["fuel_barrel", 0.9], ["fuel_barrel_wreck", 0.65], ["metal_ammo_box", 0.3],
			["ammo_box", 0.25], ["medkit", 0.35], ["radio", 0.45], ["canteen", 0.25], ["m67", 0.25]]
	var x := -3.2
	for e in row:
		PP.add(scene, e[0], Vector3(x, 0, 0), 0.4, e[1])
		x += 0.8
	PP.add(scene, "sandbag_wall", Vector3(0, 0, -1.6), 0.0, 0.0, Vector3(4.0, 0, 0))
	for i in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("[preview] saved ", out)
	quit()
