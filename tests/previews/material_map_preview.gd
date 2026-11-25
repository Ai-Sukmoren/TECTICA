extends SceneTree
## Colours each material of a gun's body a flat colour and prints the key, to see which part each material is.
## godot --path . -s res://tests/previews/material_map_preview.gd -- out.png <gun>...
const Weapon = preload("res://scripts/weapons/weapon.gd")
const KEY := [Color.RED, Color.LIME, Color.DODGER_BLUE, Color.YELLOW, Color.MAGENTA, Color.CYAN, Color.ORANGE, Color.WHITE]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var a := OS.get_cmdline_user_args()
	root.size = Vector2i(1920, 1080)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.14, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 1.2
	scene.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var guns: Array = a.slice(1)
	cam.size = guns.size() * 0.45
	scene.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(5, -(guns.size() - 1) * 0.225, 0), Vector3(0, -(guns.size() - 1) * 0.225, 0), Vector3.UP)
	for i in guns.size():
		var w = Weapon.new()
		w.setup(guns[i], {})
		scene.add_child(w)
		w.position = Vector3(0, -i * 0.45, 0.2)
		var names := {}
		for n in w.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or String(mi.get_meta("skin_part", "")) != "": continue
			for s in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(s)
				var nm := String(m.resource_name) if m else "?"
				if not names.has(nm): names[nm] = KEY[names.size() % KEY.size()]
				var fm := StandardMaterial3D.new(); fm.albedo_color = names[nm]; fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.set_surface_override_material(s, fm)
		var txt := String(guns[i]) + ":"
		for nm in names: txt += "  " + nm + "=" + str(KEY.find(names[nm]))
		print("KEY ", txt)
		var l := Label3D.new(); l.text = txt; l.font_size = 28; l.pixel_size = 0.0016; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0.3, -i * 0.45 + 0.17, -0.6); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		scene.add_child(l)
	for f in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(a[0])
	quit()
