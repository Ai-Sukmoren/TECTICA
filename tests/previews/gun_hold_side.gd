extends SceneTree
## Each gun held by the soldier rig in first person, seen from its right side on a plain background, with the model's grip, support, mag, muzzle and sight markers drawn as coloured dots
## (yellow grip, cyan support, magenta mag, red muzzle, green sight). Two guns per row.
## An id written as id+kit gets every fitting option it allows: the side-rail laser and the angled foregrip.
##   godot --path . -s res://tests/previews/gun_hold_side.gd -- <out.jpg> <gun ids...>
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const TILE := Vector2i(640, 360)
const MARKS := {"Grip": Color(1, 0.9, 0.1), "Support": Color(0.1, 0.9, 1), "MagAt": Color(1, 0.2, 1),
		"MuzzleAt": Color(1, 0.15, 0.15), "Sight": Color(0.2, 1, 0.3)}

func _initialize() -> void:
	run.call_deferred()

func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func dot(parent: Node3D, at: Vector3, c: Color) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.008
	s.height = 0.016
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mat.no_depth_test = true
	m.material_override = mat
	parent.add_child(m)
	m.global_position = at

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var ids: Array = args.slice(1)
	root.size = TILE
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.environment.ambient_light_energy = 1.0
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 70, 0)
	sun.light_energy = 1.2
	scene.add_child(sun)
	var cam := Camera3D.new()
	cam.near = 0.01
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	scene.add_child(cam)
	cam.current = true
	var sheet := Image.create(TILE.x * 2, TILE.y * ((ids.size() + 1) / 2), false, Image.FORMAT_RGB8)
	for i in ids.size():
		var rig = Rig.new()
		scene.add_child(rig)
		rig.build(Palettes.player())
		rig.set_process(false)
		rig.set_first_person(true)
		var id: String = String(ids[i]).trim_suffix("+kit")
		var att := {}
		if String(ids[i]).ends_with("+kit"):
			att = Data.sanitize(id, {"side": "laser", "underbarrel": "afg"})
		var w = Weapon.new()
		w.setup(id, att)
		rig.set_weapon(w, [])
		w.set_process(false)
		rig.fp_pitch = 0
		for k in 100:
			rig._animate(1.0 / 60.0)
		for n in MARKS:
			var mk := w.find_child(n, true, false) as Node3D
			if mk != null:
				dot(scene, mk.global_position, MARKS[n])
		var t: Transform3D = w.global_transform
		var mid: Vector3 = t * Vector3(0, 0.0, -0.2)
		cam.size = 0.62
		cam.global_position = mid + t.basis.x.normalized() * 2.0
		cam.look_at(mid, t.basis.y.normalized())
		sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i((i % 2) * TILE.x, (i / 2) * TILE.y))
		print("  %-13s grip %s" % [ids[i], str((w.find_child("Grip", true, false) as Node3D).position.snapped(Vector3.ONE * 0.001))])
		rig.queue_free()
		for c in scene.get_children():
			if c is MeshInstance3D:
				c.queue_free()
		await process_frame
	sheet.save_jpg(out, 0.88)
	print("saved ", out)
	quit(0)
