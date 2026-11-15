extends SceneTree
## A finish close up on a few guns (signed in as Turain so the Kitty finish
## shows; needs a window).
##   godot --path . -s res://tests/previews/kitty_gun_preview.gd -- <out_dir> [finish]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const GUNS := ["hk33", "aug_a1", "uar10", "g17", "knife_combat", "karambit", "butterfly", "marlin"]

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var finish: String = a[1] if a.size() > 1 else "kitty_mythic"
	load("res://scripts/core/profile.gd").current = "turain"
	root.size = Vector2i(1600, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.7
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -150, 0)
	fill.light_energy = 0.5
	world.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.make_current()
	for i in GUNS.size():
		var w := Weapon.new()
		world.add_child(w)
		w.setup(String(GUNS[i]), {})
		w.apply_skin(finish)
		w.apply_sticker({"side": 2})
		w.position = Vector3((i % 2 - 0.5) * 1.15, (1.5 - i / 2) * 0.36, 0)
		w.rotation.y = PI * 0.5
	cam.position = Vector3(0, 0.02, 2.6)
	cam.look_at(Vector3(0, 0, 0))
	await frames(40)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("%s/%s_guns.jpg" % [out, finish], 0.92)
	print("saved ", "%s/%s_guns.jpg" % [out, finish])
	quit(0)
