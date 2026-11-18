extends SceneTree
## Every gun that takes a rail, from the side: without it and with it (<out>/<gun>_<none|rail>.png). Needs a window.
## With a gun id: only that gun, with the rail and each underbarrel part it takes (<gun>_ub_<part>.png).
##   godot --path . -s res://tests/previews/rail_sheet.gd -- <out_dir> [gun]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")


func _initialize() -> void:
	run.call_deferred()


func bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		if not (m as MeshInstance3D).is_visible_in_tree() or (m as MeshInstance3D).mesh == null:
			continue
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var only: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	root.size = Vector2i(1200, 480)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.84, 0.87)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.9, 0)
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	cam.make_current()
	for id in Data.WEAPONS:
		var rails: Array = Data.WEAPONS[id].options.get("rail", [])
		if (only == "" and not rails.has("rail")) or (only != "" and id != only):
			continue
		var looks: Array = [["none", {"rail": "none"}], ["rail", {"rail": "rail"}]]
		if only != "":
			looks = Data.WEAPONS[id].options.get("underbarrel", ["none"]).map(func(u): return ["ub_" + String(u), {"rail": "rail" if rails.has("rail") else "none", "underbarrel": u}])
		for look in looks:
			var opt: String = look[0]
			var w := Weapon.new()
			world.add_child(w)
			w.setup(id, look[1])
			await process_frame
			var b := bounds(w)
			var c := b.get_center()
			cam.size = maxf(b.size.z * 0.42, b.size.y * 1.1)
			cam.position = c + Vector3(3.0, 0, 0)
			cam.look_at(c, Vector3.UP)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, id, opt])
			w.free()
		print("RAIL %s" % id)
	quit()
