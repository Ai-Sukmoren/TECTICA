extends SceneTree
## Lists every mesh and surface of a built gun: its skin part, material, colour and surface area, so the skin
## can be limited to the body. godot --headless --path . -s res://tests/previews/gun_surfaces_probe.gd -- <gun>...
const Weapon = preload("res://scripts/weapons/weapon.gd")

func _initialize() -> void:
	run.call_deferred()

func area(mesh: Mesh, s: int, xf: Transform3D) -> float:
	var arr := mesh.surface_get_arrays(s)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx = arr[Mesh.ARRAY_INDEX]
	var tot := 0.0
	if idx == null or idx.size() == 0:
		for i in range(0, v.size() - 2, 3):
			tot += ((xf * v[i + 1]) - (xf * v[i])).cross((xf * v[i + 2]) - (xf * v[i])).length() * .5
	else:
		for i in range(0, idx.size() - 2, 3):
			tot += ((xf * v[idx[i + 1]]) - (xf * v[idx[i]])).cross((xf * v[idx[i + 2]]) - (xf * v[idx[i]])).length() * .5
	return tot

func run() -> void:
	for gid in OS.get_cmdline_user_args():
		await probe(gid)
	quit()

func probe(gid: String) -> void:
	var w = Weapon.new()
	root.add_child(w)
	w.setup(gid, {})
	await process_frame
	for node in w.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var m = mi.get_surface_override_material(s)
			if m == null: m = mi.material_override
			if m == null: m = mi.mesh.surface_get_material(s)
			var col := ""
			if m is BaseMaterial3D:
				col = str((m as BaseMaterial3D).albedo_color) + (" tex" if (m as BaseMaterial3D).albedo_texture else "")
			print("MESH %s %s part=%s pack4=%s override=%s surf %d mat=%s %s area=%.4f" % [gid, mi.name, mi.get_meta("skin_part", ""), mi.has_meta("pack4"), mi.material_override != null, s,
				(m.resource_name if m else "null"), col, area(mi.mesh, s, xf)])
	w.queue_free()
	await process_frame
