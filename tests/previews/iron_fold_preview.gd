extends SceneTree
## Side close-ups of the flip-up irons: standing (iron sights) and folded (an optic fitted), one row per gun.
##   godot --path . -s res://tests/previews/iron_fold_preview.gd -- <out_dir>
const Weapon = preload("res://scripts/weapons/weapon.gd")

const GUNS := ["aug_a4", "bren_2", "scar_sc", "honey_badger", "pdr_c", "mcx_spear"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	root.size = Vector2i(960, 540)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.86, 0.9)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	for rot in [Vector3(-35, 25, 0), Vector3(-10, -150, 0)]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = rot
		world.add_child(l)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.make_current()
	for id in GUNS:
		for optic in ["iron", "reflex"]:
			var w := Weapon.new()
			w.setup(id, {"optic": optic})
			world.add_child(w)
			var box := AABB()
			var first := true
			for n in w.find_children("*", "MeshInstance3D", true, false):
				var a: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
				box = a if first else box.merge(a)
				first = false
			var c := box.get_center()
			cam.position = c + Vector3(-1.0, 0.18, 0.0) * box.size.z * 1.25
			cam.look_at(c + Vector3(0, box.size.y * 0.15, 0))
			for i in 6:
				await process_frame
			root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [id, optic]))
			w.queue_free()
			await process_frame
	quit()
