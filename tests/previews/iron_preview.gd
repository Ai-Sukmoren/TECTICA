extends SceneTree
## Iron sight fit: per gun (iron sights fitted) the whole gun side-on, then
## close-ups of the rear and front sight. Needs a window.
##   godot --path . -s res://tests/previews/iron_preview.gd -- <out_dir> [tag]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const TILE := Vector2i(360, 200)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var tag: String = args[1] if args.size() > 1 else "now"
	var guns: Array = []
	for id in Data.PRIMARIES + Data.SECONDARIES:
		if "iron" in Data.WEAPONS[id].options.optic:
			guns.append(id)
	root.size = TILE
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.75, 0.77, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 60, 0)
	key.light_energy = 1.2
	world.add_child(key)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	cam.make_current()
	var sheet := Image.create(TILE.x * 3, TILE.y * guns.size(), false, Image.FORMAT_RGB8)
	for gi in guns.size():
		var id: String = guns[gi]
		var att: Dictionary = Data.WEAPONS[id].defaults.duplicate()
		att["optic"] = "iron"
		var w := Weapon.new()
		world.add_child(w)
		w.setup(id, att)
		w.rotation.y = PI * 0.5   # muzzle to the left, right side to the camera
		await frames(2)
		var info: Dictionary = w.get_meta("iron_info", {})
		var b := AABB()
		var first := true
		for n in w.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var a: AABB = (w.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
			b = a if first else b.merge(a)
			first = false
		var sy: float = float(info.get("y", b.end.y - 0.02))
		var rz: float = float(info.get("rear_z", 0.0))
		var fz: float = float(info.get("front_z", b.position.z + 0.05))
		var shots := [
			[Vector3(0, b.get_center().y, b.get_center().z), maxf(b.size.z * 0.62, 0.3)],
			[Vector3(0, sy - 0.015, rz), 0.11],
			[Vector3(0, sy - 0.015, fz), 0.11],
		]
		for si in shots.size():
			var c: Vector3 = w.global_transform * shots[si][0]
			cam.size = float(shots[si][1])
			cam.global_position = c + Vector3(0, 0, -1.0)
			cam.look_at(c)
			await frames(2)
			sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i(si * TILE.x, gi * TILE.y))
		print("  %-6s sight line y %.3f rear z %.3f front z %.3f" % [id, sy, rz, fz])
		w.queue_free()
		await frames(1)
	sheet.save_jpg(out + "/irons_%s.jpg" % tag, 0.9)
	print("saved irons_%s" % tag)
	quit(0)
