extends SceneTree
## Attachment fit: every gun's own surfaces (everything that is not an
## attachment) become collision, then rays from each attachment anchor find
## the surface the attachment should sit against:
##   optic    straight down onto the rail      -> mount base on the rail
##   under    straight up into the handguard   -> mount top on the handguard
##   muzzle   back along the bore              -> device starts at the barrel tip
##   stock    forward into the receiver        -> stock meets the receiver
## Offsets beyond TOL fail (a floating or buried part).
##   godot --headless --path . -s res://tests/attachment_fit_test.gd
const Model = preload("res://scripts/weapons/weapon_model.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const M = preload("res://scripts/core/materials.gd")

const TOL := 0.0035   # 3.5 mm
const ANCHORS := ["MuzzleAt", "UnderAt", "MagAt", "StockAt"]
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _b(model: String, r: Node3D) -> Dictionary:
	Model._mats()
	match model:
		"m4": return Model._m4(r)
		"akm": return Model._ak(r)
		"as_val": return Model._val(r)
		"mp7": return Model._mp7(r)
		"awp": return Model._awp(r)
		"m870": return Model._m870(r)
		"m249": return Model._m249(r)
		"g18": return Model._pistol(r, M.solid(Color(0.13, 0.12, 0.1), 0.7), true)
		"mgp7": return Model._mgp7(r)
		"zc57": return Model._zc57(r)
	return Model._pistol(r, Model._poly, false)

## Collision for every non-attachment mesh of the gun under `root`.
func _collide(root: Node3D) -> void:
	var body := StaticBody3D.new()
	root.add_child(body)
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name) in ANCHORS or n == body:
			continue
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var shape := mi.mesh.create_trimesh_shape()
			if shape == null:
				continue
			shape.backface_collision = true
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			cs.global_transform = mi.global_transform

## Distance along `dir` from `from` to the first surface (INF if none within `reach`).
func _ray(from: Vector3, dir: Vector3, reach: float) -> float:
	var space := get_root().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	q.hit_back_faces = true
	var hit := space.intersect_ray(q)
	return INF if hit.is_empty() else from.distance_to(hit.position)

func _local(n: Node3D, root: Node3D) -> Vector3:
	return root.global_transform.affine_inverse() * n.global_position

func run() -> void:
	var guns: Array = Data.PRIMARIES + Data.SECONDARIES
	var gi := 0
	for id in guns:
		var model := String(Data.WEAPONS[id].model)
		var root := Node3D.new()
		get_root().add_child(root)
		root.position = Vector3(gi * 10.0, 0, 0)   # each gun on its own
		gi += 1
		var b := _b(model, root)
		_collide(root)
		for i in 3:
			await physics_frame
		var o := root.global_position
		print(id)
		# optic: the mount base is 2 mm (x size) below rail_y
		var s := 0.75 if b.get("mini", false) else 1.0
		var base: float = float(b.rail_y) - 0.002 * s
		var top_from := o + Vector3(0, float(b.rail_y) + 0.06, float(b.rail_z))
		var d := _ray(top_from, Vector3.DOWN, 0.2)
		if d < INF:
			var rail_top: float = top_from.y - d - o.y
			var gap := base - rail_top
			print("    optic   %+5.1f mm (rail top %.4f, mount base %.4f)" % [gap * 1000.0, rail_top, base])
			check(gap < TOL and gap > -TOL, "%s optic sits on the rail" % id)
		# underbarrel: the mount's top face is the anchor height
		var ua := _local(b.under_at, root)
		var under_from := o + Vector3(0, ua.y - 0.05, ua.z)
		d = _ray(under_from, Vector3.UP, 0.12)
		if d < INF:
			var bottom: float = under_from.y + d - o.y
			var gap := bottom - ua.y   # > 0: mount hangs below the handguard
			print("    under   %+5.1f mm (handguard bottom %.4f, mount top %.4f)" % [gap * 1000.0, bottom, ua.y])
			check(gap < TOL and gap > -TOL, "%s underbarrel mount touches the handguard" % id)
		# muzzle: the device's rear face is the anchor
		var mz := _local(b.muzzle_at, root)
		# barrels are open tubes, so a ray down the bore flies straight in. Instead,
		# step forward along the bore dropping short vertical rays onto the
		# barrel: the front-most one that still hits it marks the tip.
		var tip := INF
		if Data.WEAPONS[id].options.muzzle == ["integral"]:
			mz.z = INF   # built-in suppressor only: nothing attaches here
		var z := mz.z + 0.04 if mz.z < INF else -INF
		while z > mz.z - 0.04:
			var from := o + Vector3(0, mz.y + 0.03, z)
			var dd := _ray(from, Vector3.DOWN, 0.045)
			if dd < INF:
				tip = z
			z -= 0.0005
		if tip < INF:
			var gap := tip - mz.z   # > 0: device starts in front of the barrel
			print("    muzzle  %+5.1f mm (barrel tip %.4f, device rear %.4f)" % [gap * 1000.0, tip, mz.z])
			check(gap < TOL and gap > -0.012, "%s muzzle device meets the barrel tip" % id)
		# stock
		if String(b.stock_style) != "":
			var sa := _local(b.stock_at, root)
			var stock_from := o + Vector3(0, sa.y, sa.z + 0.06)
			d = _ray(stock_from, Vector3.FORWARD, 0.25)
			if d < INF:
				var back: float = stock_from.z - d - o.z
				var gap := sa.z - back   # > 0: stock starts behind the receiver
				print("    stock   %+5.1f mm (receiver back %.4f, stock front %.4f)" % [gap * 1000.0, back, sa.z])
				check(gap < TOL and gap > -0.03, "%s stock meets the receiver" % id)
		root.queue_free()
	print("FIT: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
