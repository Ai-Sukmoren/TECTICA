extends SceneTree
## Side view of guns whose attachments and magazine wear their own skins.
## godot --path . -s res://tests/previews/part_skins_preview.gd -- out.png
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Skins = preload("res://scripts/skins/skins.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.055, 0.075, 0.10)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -60, 0)
	sun.light_energy = 1.5
	scene.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	scene.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(1.9, 0.25, 0.0), Vector3(0, 0.0, 0), Vector3.UP)
	var rows := [
		["hk33", {"handguard": "hex", "underbarrel": "gp25", "muzzle": Data.WEAPONS.hk33.options.muzzle[-1]}, "gilded_royale",
				{"magazine": "neon_tide", "handguard": "carbon_weave", "underbarrel": Skins.FACTORY, "muzzle": "dragon_scale"}],
		["as_val", {"optic": Data.WEAPONS.as_val.options.optic[-1], "underbarrel": "laser"}, "woodland",
				{"magazine": "blood_moon", "optic": "gunmetal", "rail": "arctic"}],
		["g17", {"muzzle": "suppressor", "underbarrel": "laser"}, "",
				{"magazine": "aurora", "muzzle": "damascus"}],
	]
	var y := 0.32
	for r in rows:
		var w = Weapon.new()
		w.setup(r[0], r[1])
		scene.add_child(w)
		w.position = Vector3(0, y, 0.15 if w.is_pistol() else 0.0)
		w.apply_skin(r[2], r[3])
		y -= 0.32
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
