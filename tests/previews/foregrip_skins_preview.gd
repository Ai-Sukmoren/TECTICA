extends SceneTree
## The angled foregrip painted with several finishes (its own attachment finish, the rest of the gun left as it is),
## on the SCAR-SC, seen close from the right and below.
##   godot --path . -s res://tests/previews/foregrip_skins_preview.gd -- <out.jpg> [finishes...]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const TILE := Vector2i(480, 320)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var finishes: Array = args.slice(1) if args.size() > 1 else ["", "cerakote_tan", "woodland", "carbon_weave", "neon_tide", "gilded_royale", "dragon_scale", "aurora"]
	root.size = TILE
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.18, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.7
	env.environment.glow_enabled = true
	scene.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.6
	scene.add_child(key)
	var cam := Camera3D.new()
	cam.fov = 24.0
	scene.add_child(cam)
	cam.current = true
	var cols := 4
	var sheet := Image.create(TILE.x * cols, TILE.y * ((finishes.size() + cols - 1) / cols), false, Image.FORMAT_RGB8)
	for i in finishes.size():
		var w = Weapon.new()
		scene.add_child(w)
		w.setup("scar_sc", Data.sanitize("scar_sc", {"underbarrel": "afg"}))
		w.set_process(false)
		w.apply_skin("", {"underbarrel": String(finishes[i])} if String(finishes[i]) != "" else {})
		await process_frame
		var g := w.find_child("Att_afg", true, false) as Node3D
		var c: Vector3 = g.global_position + Vector3(0, -0.02, 0)
		cam.global_position = c + Vector3(0.3, -0.12, 0.16)
		cam.look_at(c, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % cols) * TILE.x, (i / cols) * TILE.y))
		print("  %s" % (finishes[i] if finishes[i] != "" else "factory"))
		w.queue_free()
		await process_frame
	sheet.save_jpg(out, 0.9)
	quit(0)
