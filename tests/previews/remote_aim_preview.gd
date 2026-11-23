extends SceneTree
## A remote player's aim pitch on their third-person body (SoldierRig.tp_aim_pitch, fed from the network by
## player.gd): the same rifle aimed down, level and up, seen from the side, with a red line along the barrel.
## Prints each barrel's elevation next to the aim pitch it should match.
##   godot --path . -s res://tests/previews/remote_aim_preview.gd -- <out.jpg>
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
const TILE := Vector2i(420, 420)
const PITCHES := [-0.6, -0.3, 0.0, 0.3, 0.6]

func _initialize() -> void:
	run.call_deferred()

func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	root.size = TILE
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.36, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	var sheet := Image.create(TILE.x * PITCHES.size(), TILE.y, false, Image.FORMAT_RGB8)
	var worst := 0.0
	for i in PITCHES.size():
		var rig = Rig.new()
		scene.add_child(rig)
		rig.build(Palettes.player())
		rig.set_process(false)
		var w = Weapon.new()
		w.setup("hk33")
		rig.set_weapon(w, [])
		w.set_process(false)
		rig.aim_target = 1.0   # aiming down sights, as a player firing in first person mostly is
		rig.tp_aim_pitch = PITCHES[i]
		for k in 120:
			rig._animate(1.0 / 60.0)
		var muz := w.find_child("MuzzleAt", true, false) as Node3D
		var t: Transform3D = muz.global_transform if muz != null else w.global_transform
		var fwd := -t.basis.z.normalized()
		var elev := asin(clampf(fwd.y, -1.0, 1.0))
		worst = maxf(worst, absf(elev - PITCHES[i]))
		print("  aim pitch %+.2f  barrel elevation %+.2f  (off by %.2f rad)" % [PITCHES[i], elev, absf(elev - PITCHES[i])])
		var line := MeshInstance3D.new()
		var im := ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0.1, 0.1)
		im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
		im.surface_add_vertex(t.origin)
		im.surface_add_vertex(t.origin + fwd * 3.0)
		im.surface_end()
		line.mesh = im
		scene.add_child(line)
		var mid: Vector3 = rig.global_position + Vector3(0, 1.3, 0)
		cam.fov = 50.0
		cam.global_position = mid + rig.global_transform.basis.x * 4.2
		cam.look_at(mid, Vector3.UP)
		sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i(i * TILE.x, 0))
		rig.queue_free()
		line.queue_free()
		await process_frame
	print("  worst barrel error %.2f rad" % worst)
	sheet.save_jpg(out, 0.9)
	quit(0)
