extends SceneTree
## Every gun in one finish, built and skinned by the game's own Weapon code, in a labelled grid.
## godot --path . --resolution 1920x1440 -s res://tests/previews/skin_all_guns_preview.gd -- out.png [finish] [first] [count]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var finish: String = a[1] if a.size() > 1 else "carbon_mythic"
	var ids: Array = Data.WEAPONS.keys().filter(func(k): return not (k in ["knife_combat", "karambit", "butterfly"]))
	var first := int(a[2]) if a.size() > 2 else 0
	var count := int(a[3]) if a.size() > 3 else ids.size()
	ids = ids.slice(first, first + count)
	root.size = Vector2i(1920, 1080)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.14, 0.16)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.9
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 60, 0)
	sun.light_energy = 1.7
	scene.add_child(sun)
	var cols := int(a[4]) if a.size() > 4 else 3
	var rows := int(ceil(ids.size() / float(cols)))
	var cw := 1.0
	var rh := 0.6
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * rh + 0.1
	scene.add_child(cam)
	cam.current = true
	# looking at the guns' right side (+X), the grid in the camera's view plane (Z = across, Y = down)
	cam.look_at_from_position(Vector3(5, -(rows - 1) * rh * 0.5, -(cols - 1) * cw * 0.5), Vector3(0, -(rows - 1) * rh * 0.5, -(cols - 1) * cw * 0.5), Vector3.UP)
	for i in ids.size():
		var gid: String = ids[i]
		var w = Weapon.new()
		w.setup(gid, {})
		scene.add_child(w)
		var aabb := AABB()
		var first_box := true
		for n in w.find_children("*", "MeshInstance3D", true, false):
			if not (n as MeshInstance3D).is_visible_in_tree() or (n as MeshInstance3D).mesh == null or String(n.get_meta("skin_part", "")) != "" or not n.has_meta("pack4"): continue   # frame on the gun body
			var bb: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
			aabb = bb if first_box else aabb.merge(bb)
			first_box = false
		var c := aabb.get_center()
		var k := minf(1.0, (cw * 0.85) / maxf(aabb.size.z, 0.01))
		w.scale = Vector3.ONE * k
		w.position = Vector3(0, -(i / cols) * rh, -(i % cols) * cw) - c * k + Vector3(0, 0.03, 0)
		w.apply_skin(finish)
		var l := Label3D.new()
		l.text = gid
		l.font_size = 40
		l.pixel_size = 0.0022
		l.modulate = Color(1, 1, 1, 0.85)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0.5, -(i / cols) * rh - rh * 0.40, -(i % cols) * cw)
		scene.add_child(l)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
