extends SceneTree
## Weapon light fit on every gun, without the game running: the real rig holding the gun at the first-person
## eye, the light placed by the player's own mount code. Top row of each gun: from the right; bottom: the eye view.
##   godot --path . -s res://tests/previews/torch_fit_preview.gd -- <out.jpg> [ids...]
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
const Player = preload("res://scripts/characters/player.gd")
const TILE := Vector2i(480, 300)

func _initialize() -> void:
	run.call_deferred()

func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var ids: Array = args.slice(1) if args.size() > 1 else Data.PRIMARIES + Data.SECONDARIES
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
	cam.near = 0.02
	scene.add_child(cam)
	cam.current = true
	var mount: Player = Player.new()   # only its mount maths is used
	var glb: PackedScene = load(Player.TORCH_GLB)
	var sheet := Image.create(TILE.x * ids.size(), TILE.y * 2, false, Image.FORMAT_RGB8)
	for i in ids.size():
		var rig = Rig.new()
		scene.add_child(rig)
		rig.build(Palettes.player())
		rig.set_process(false)
		rig.set_first_person(true)
		var w = Weapon.new()
		w.setup(ids[i])
		rig.set_weapon(w, [])
		w.set_process(false)
		rig.fp_pitch = 0
		for k in 100:
			rig._animate(1.0 / 60.0)
		# the light, exactly as player.gd places it
		var torch := Node3D.new()
		rig.weapon_anchor.add_child(torch)
		var model: Node3D = glb.instantiate()
		torch.add_child(model)
		var mt: Transform3D = mount._torch_mount(w)
		var m: Vector3 = mt.origin
		torch.transform = mt
		torch.scale = Vector3.ONE * (Player.PISTOL_LIGHT if w.is_pistol() else 1.0)
		Player.place_torch_model(model)
		var t: Transform3D = w.global_transform
		var mid: Vector3 = t * m
		cam.fov = 28.0
		cam.global_position = t * (m + Vector3(0.45, 0.0, 0.0))
		cam.look_at(mid, t.basis.y)
		sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i(i * TILE.x, 0))
		cam.fov = 86.0
		cam.global_transform = rig.fp_eye
		sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i(i * TILE.x, TILE.y))
		print("  %-7s light at %s" % [ids[i], str(m.snapped(Vector3.ONE * 0.001))])
		rig.visible = false
		rig.queue_free()
	mount.free()
	sheet.save_jpg(out, 0.88)
	print("saved ", out)
	quit()
