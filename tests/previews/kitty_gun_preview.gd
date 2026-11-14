extends SceneTree
## Mythic Kitty finish close up on a few guns (signed in as Turain; needs a window).
##   godot --path . -s res://tests/previews/kitty_gun_preview.gd -- <out_dir>
const Weapon = preload("res://scripts/weapons/weapon.gd")
const GUNS := ["m4a1", "ak47", "awp", "mk23"]

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
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
		w.apply_skin("kitty_mythic")
		w.position = Vector3((i % 2 - 0.5) * 1.15, (0.5 - i / 2) * 0.5, 0)
		w.rotation.y = PI * 0.5
	cam.position = Vector3(0, 0.02, 2.6)
	cam.look_at(Vector3(0, 0, 0))
	await frames(40)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/kitty_guns.jpg", 0.92)
	print("saved ", out + "/kitty_guns.jpg")
	quit(0)
