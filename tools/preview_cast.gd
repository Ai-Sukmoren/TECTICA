extends SceneTree
## Renders the whole human cast side by side, facing the camera: the default
## operator, every outfit and the militia variants, so a change to the
## procedural body can be checked on everyone at once.
## Needs a window:  godot --path . -s res://tools/preview_cast.gd -- <out.png> [head<N>]
##   head<N>: close-up of the N-th character's head and chest.

const CAST := [
	["player"], ["outfit", "night_ops"], ["outfit", "desert"], ["outfit", "arctic"],
	["outfit", "tiger"], ["outfit", "crimson"], ["outfit", "recon"],
	["enemy", 0], ["enemy", 1], ["enemy", 2], ["enemy", 3],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://cast.png"
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
	sun.rotation_degrees = Vector3(-35, 160, 0)   # from the front, over the camera's shoulder
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fmi.mesh = pm
	world.add_child(fmi)

	var Soldier = load("res://scripts/characters/soldier.gd")
	var Palettes = load("res://scripts/core/palettes.gd")
	var rigs: Array = []
	for i in CAST.size():
		var c: Array = CAST[i]
		var pal: Dictionary
		match String(c[0]):
			"player": pal = Palettes.player()
			"outfit": pal = Palettes.outfit(String(c[1]))
			_: pal = Palettes.enemy(int(c[1]))
		var s = Soldier.new()
		world.add_child(s)
		s.position = Vector3((i - (CAST.size() - 1) * 0.5) * 1.0, 0, 0)
		s.setup_soldier(pal, ["akm"], 0, 0, 0.0)
		rigs.append(s)
	for f in 60:
		await process_frame

	var cam := Camera3D.new()
	world.add_child(cam)
	var eye := Vector3(0, 1.3, -9.5)
	var look := Vector3(0, 0.95, 0)
	cam.fov = 60.0
	for a in args:
		if a.begins_with("head"):
			var hp: Vector3 = rigs[int(a.substr(4))].rig.head.global_position
			look = hp + Vector3(0, -0.12, 0)
			eye = hp + Vector3(0.22, 0.02, -0.9)
			cam.fov = 30.0
	cam.transform = Transform3D.IDENTITY.looking_at(look - eye).translated(eye)
	cam.current = true
	for f in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
