extends SceneTree
## Renders guns side-on under studio light, one image per gun with several
## skins, plus mesh-space sizes of asset-pack parts (skin pattern scale
## depends on them). Needs a window.
##   godot --path . -s res://tests/previews/skin_grid_preview.gd -- <out_dir> [gun ids...]
const Weapon = preload("res://scripts/weapons/weapon.gd")

const SKINS := ["", "woodland", "urban_digital", "carbon_weave", "damascus", "gilded_royale", "neon_tide", "mythicskin"]

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var guns: Array = a.slice(1) if a.size() > 1 else ["mgp7", "zc57", "mp7", "mk23"]
	root.size = Vector2i(1600, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.6
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -150, 0)
	fill.light_energy = 0.5
	world.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	cam.make_current()
	for id in guns:
		var cols := 4
		var rows := int(ceil(SKINS.size() / float(cols)))
		var spacing := Vector2(1.0, 0.45)
		var shown: Array = []
		for i in SKINS.size():
			var w := Weapon.new()
			world.add_child(w)
			w.setup(String(id), {})
			if SKINS[i] != "":
				w.apply_skin(SKINS[i])
			var col := i % cols
			var row := i / cols
			w.position = Vector3((col - (cols - 1) * 0.5) * spacing.x, -(row - (rows - 1) * 0.5) * spacing.y, 0)
			w.rotation.y = PI * 0.5   # muzzle (-z) to the left, right side towards the camera
			shown.append(w)
			var lbl := Label3D.new()
			lbl.text = SKINS[i] if SKINS[i] != "" else "(no skin)"
			lbl.font_size = 28
			lbl.pixel_size = 0.0012
			lbl.position = w.position + Vector3(0, -0.17, 0.2)
			world.add_child(lbl)
			shown.append(lbl)
		cam.size = maxf(spacing.y * rows + 0.3, (cols * spacing.x + 0.2) * 9.0 / 16.0)
		cam.position = Vector3(0, 0, 3)
		if id in ["mgp7", "zc57"]:
			_report(shown[0], String(id))
		await frames(20)
		await RenderingServer.frame_post_draw
		var f := "%s/skins_%s.jpg" % [out, id]
		root.get_texture().get_image().save_jpg(f, 0.9)
		print("saved ", f)
		for n in shown:
			n.queue_free()
		await frames(2)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)


## Mesh-space size and node scale of each pack part: the skin shader patterns
## in mesh-local coordinates, so a part modelled in other units or scaled by
## its node gets a pattern that is far too big or too small.
func _report(w: Node, id: String) -> void:
	var stack: Array = [w]
	var n_pack := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and n.has_meta("pack4"):
			n_pack += 1
			var mi := n as MeshInstance3D
			var size := mi.mesh.get_aabb().size
			var sc := mi.global_transform.basis.get_scale()
			if n_pack <= 6:
				print("  %s part %-28s mesh size %s  world scale %s" % [id, mi.mesh.resource_name if mi.mesh.resource_name != "" else String(mi.name), size, sc])
	print("  %s: %d pack parts" % [id, n_pack])
