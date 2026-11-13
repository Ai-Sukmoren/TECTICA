extends SceneTree
## Studio shot of guns built with the newer attachments (needs a window).
##   godot --path . -s res://tests/previews/attachment_showcase.gd -- <out_dir>
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

const BUILDS := [
	["m4a1", {"optic": "prism", "muzzle": "heavy_suppressor", "underbarrel": "stubby", "magazine": "dual", "stock": "folding"}],
	["ak47", {"optic": "prism", "muzzle": "booster", "underbarrel": "handstop", "magazine": "hollow", "stock": "standard"}],
	["mgp7", {"optic": "prism", "muzzle": "booster", "underbarrel": "handstop", "magazine": "dual"}],
	["mp7", {"optic": "holo", "muzzle": "heavy_suppressor", "underbarrel": "stubby", "magazine": "dual", "stock": "folding"}],
	["mk23", {"optic": "minidot", "muzzle": "heavy_suppressor", "magazine": "dual"}],
	["zc57", {"optic": "minidot", "muzzle": "compensator", "magazine": "hollow"}],
]

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(1800, 1100)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.15, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	for rot in [Vector3(-35, 25, 0), Vector3(-10, -150, 0)]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = rot
		l.light_energy = 1.4 if rot.y > 0 else 0.6
		world.add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.5
	cam.position = Vector3(0, 0, 3)
	world.add_child(cam)
	cam.make_current()
	for i in BUILDS.size():
		var b: Array = BUILDS[i]
		var w := Weapon.new()
		world.add_child(w)
		w.setup(String(b[0]), b[1])
		var col := i % 2
		var row := i / 2
		w.position = Vector3(-0.62 + col * 1.24, 0.46 - row * 0.48, 0)
		w.rotation.y = PI * 0.5
		var att: Dictionary = Data.sanitize(String(b[0]), b[1])
		var names: Array = []
		for slot in Data.SLOTS:
			var opt := String(att[slot])
			if opt in ["iron", "none", "standard", "integral"]:
				continue
			names.append(String(Data.ATTACHMENTS[slot][opt].name))
		var lbl := Label3D.new()
		lbl.text = String(Data.WEAPONS[b[0]].name) + "\n" + "  ·  ".join(names)
		lbl.font_size = 26
		lbl.pixel_size = 0.0011
		lbl.modulate = Color(0.85, 0.87, 0.9)
		lbl.position = w.position + Vector3(0, -0.17, 0.4)
		world.add_child(lbl)
	await frames(20)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/attachment_showcase.jpg", 0.92)
	print("saved showcase")
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
