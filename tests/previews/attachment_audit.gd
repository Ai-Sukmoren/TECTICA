extends SceneTree
## Attachment fit audit: one sheet per gun, every option of every slot
## (one slot per row), seen from the side and from above. Needs a window.
##   godot --path . -s res://tests/previews/attachment_audit.gd -- <out_dir> [gun ids...]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.append(k)
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).visible:
			var a: AABB = (c as MeshInstance3D).global_transform * (c as MeshInstance3D).mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
	return box

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var guns: Array = a.slice(1) if a.size() > 1 else Data.PRIMARIES + Data.SECONDARIES
	root.size = Vector2i(2400, 1500)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 25, 0)
	key.light_energy = 1.3
	world.add_child(key)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	cam.make_current()
	for id in guns:
		var opts: Dictionary = Data.WEAPONS[id].options
		var defaults: Dictionary = Data.WEAPONS[id].defaults
		var rows: Array = []
		for slot in Data.SLOTS:
			rows.append([slot, opts[slot]])
		var cols := 0
		for r in rows:
			cols = maxi(cols, (r[1] as Array).size())
		# measure the gun once
		var probe := Weapon.new()
		world.add_child(probe)
		probe.setup(String(id), defaults)
		probe.rotation.y = PI * 0.5
		await frames(1)
		var gb := _bounds(probe)
		probe.queue_free()
		var length := maxf(gb.size.x, 0.25) * 1.35
		var height := maxf(gb.size.y, 0.12) * 1.9
		for view in ["side", "top"]:
			var nodes: Array = []
			for ri in rows.size():
				var slot: String = rows[ri][0]
				var options: Array = rows[ri][1]
				for ci in options.size():
					var att := defaults.duplicate()
					att[slot] = options[ci]
					var w := Weapon.new()
					world.add_child(w)
					w.setup(String(id), att)
					var pos := Vector3((ci - (cols - 1) * 0.5) * length, -(ri - (rows.size() - 1) * 0.5) * height, 0)
					w.position = pos
					w.rotation = Vector3(0, PI * 0.5, 0) if view == "side" else Vector3(PI * 0.5, PI * 0.5, 0)
					nodes.append(w)
					var lbl := Label3D.new()
					lbl.text = "%s: %s" % [slot, options[ci]]
					lbl.font_size = 22
					lbl.pixel_size = length / 900.0
					lbl.modulate = Color(0.05, 0.05, 0.06)
					lbl.outline_size = 0
					lbl.position = pos + Vector3(0, -height * 0.42, 0.5)
					world.add_child(lbl)
					nodes.append(lbl)
			cam.size = maxf(rows.size() * height, cols * length * 1500.0 / 2400.0) * 1.02
			cam.position = Vector3(0, 0, 4)
			await frames(12)
			await RenderingServer.frame_post_draw
			var f := "%s/fit_%s_%s.jpg" % [out, id, view]
			root.get_texture().get_image().save_jpg(f, 0.9)
			print("saved ", f)
			for n in nodes:
				n.queue_free()
			await frames(2)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
