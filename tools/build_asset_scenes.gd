extends SceneTree
## Wraps imported third-party models in reusable scenes and audits them.
##   godot --headless --path . -s res://tools/build_asset_scenes.gd -- <src_dir> <dest_dir> <kind>
## kind: character | weapon | prop | env
##   character / weapon : Node3D root + model (no collision)
##   prop               : StaticBody3D root + model + one convex shape per mesh
##   env                : StaticBody3D root + model + trimesh shapes (walkable)
## Never overwrites an existing scene. Prints one audit line per model and a summary.

const MODEL_EXT := ["gltf", "glb", "fbx", "obj"]

var made := 0
var skipped := 0
var problems: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		push_error("usage: -- <src_dir> <dest_dir> <kind>")
		quit(1)
		return
	var src: String = a[0]
	var dest: String = a[1]
	var kind: String = a[2]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	var dir := DirAccess.open(src)
	if dir == null:
		push_error("cannot open " + src)
		quit(1)
		return
	var names: Array = []
	for f in dir.get_files():
		if f.get_extension().to_lower() in MODEL_EXT:
			names.append(f)
	names.sort()
	for f in names:
		_build(src.path_join(f), dest, kind)
	print("[scenes] kind=%s made=%d skipped_existing=%d problems=%d" % [kind, made, skipped, problems.size()])
	for p in problems:
		print("[problem] ", p)
	quit(0)


func _audit(root: Node, path: String) -> Dictionary:
	var meshes := 0
	var tris := 0
	var no_mat := 0
	var skeletons := root.find_children("*", "Skeleton3D", true, false).size()
	var anims := 0
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		anims += (ap as AnimationPlayer).get_animation_list().size()
	var aabb := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			problems.append("%s: MeshInstance3D '%s' has no mesh" % [path, m.name])
			continue
		meshes += 1
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			if m.get_active_material(s) == null:
				no_mat += 1
		var b := _global_xf(m, root) * m.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if meshes == 0:
		problems.append("%s: no meshes (broken or empty model)" % path)
	if no_mat > 0:
		problems.append("%s: %d surface(s) without material" % [path, no_mat])
	return {"meshes": meshes, "tris": tris, "skeletons": skeletons, "anims": anims, "size": aabb.size}


func _global_xf(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _build(path: String, dest: String, kind: String) -> void:
	var base := path.get_file().get_basename()
	var out := dest.path_join(base + ".tscn")
	if FileAccess.file_exists(out):
		skipped += 1
		return
	var ps := load(path) as PackedScene
	if ps == null:
		problems.append("%s: failed to load (import error)" % path)
		return
	var model := ps.instantiate()
	var info := _audit(model, path)
	var root: Node3D
	if kind == "prop" or kind == "env":
		root = StaticBody3D.new()
		root.collision_layer = 1   # Layers.WORLD
		root.collision_mask = 0
	else:
		root = Node3D.new()
	root.name = base.validate_node_name()
	model.name = "Model"
	root.add_child(model)
	model.owner = root
	if kind == "prop" or kind == "env":
		var i := 0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var shape: Shape3D = m.mesh.create_trimesh_shape() if kind == "env" else m.mesh.create_convex_shape(true, true)
			if shape == null:
				continue
			var cs := CollisionShape3D.new()
			cs.name = "Col%d" % i
			cs.shape = shape
			cs.transform = _global_xf(m, model) * Transform3D.IDENTITY
			root.add_child(cs)
			cs.owner = root
			i += 1
	root.set_meta("source_model", path)
	root.set_meta("tris", info.tris)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, out)
	if err != OK:
		problems.append("%s: could not save scene (%d)" % [path, err])
	else:
		made += 1
	var sz: Vector3 = info.size
	print("[model] %s  meshes=%d tris=%d skel=%d anims=%d size=%.2fx%.2fx%.2f" % [base, info.meshes, info.tris, info.skeletons, info.anims, sz.x, sz.y, sz.z])
	if sz.length() > 0.0 and (sz.length() > 60.0 or sz.length() < 0.02):
		problems.append("%s: unusual size %s (unit scale?)" % [path, str(sz)])
	root.free()
