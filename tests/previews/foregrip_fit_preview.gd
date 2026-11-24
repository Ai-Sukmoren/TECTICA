extends SceneTree
## The angled foregrip on every gun that takes it, close from the right side (no hands), so its length can be
## judged against the handguard. Prints each grip's front and rear against the handguard's underside.
##   godot --path . -s res://tests/previews/foregrip_fit_preview.gd -- <out.jpg> [afg|vfg] [ids...]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const TILE := Vector2i(480, 270)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var kind := "afg"
	var ids: Array = []
	for a in args.slice(1):
		if String(a) in ["afg", "vfg"]:
			kind = String(a)
		else:
			ids.append(a)
	if ids.is_empty():
		for id in Data.WEAPONS:
			if kind in Data.WEAPONS[id].options.underbarrel:
				ids.append(id)
	root.size = TILE
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 1.0
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 70, 0)
	scene.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.3
	cam.near = 0.01
	scene.add_child(cam)
	cam.current = true
	var cols := 3
	var sheet := Image.create(TILE.x * cols, TILE.y * ((ids.size() + cols - 1) / cols), false, Image.FORMAT_RGB8)
	for i in ids.size():
		var w = Weapon.new()
		scene.add_child(w)
		w.setup(String(ids[i]), Data.sanitize(String(ids[i]), {"underbarrel": kind}))
		w.set_process(false)
		await process_frame
		var g := w.find_child("Att_" + kind, true, false) as Node3D
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for n in g.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			lo = lo.min(a.position)
			hi = hi.max(a.end)
		var c := (lo + hi) * 0.5
		cam.global_position = c + Vector3(1.0, 0.03, 0)
		cam.look_at(c + Vector3(0, 0.03, 0), Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % cols) * TILE.x, (i / cols) * TILE.y))
		print("  %-13s grip length %.1f cm" % [ids[i], (hi.z - lo.z) * 100.0])
		w.queue_free()
		await process_frame
	sheet.save_jpg(out, 0.9)
	quit(0)
