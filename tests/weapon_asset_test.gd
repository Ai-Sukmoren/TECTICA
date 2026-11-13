extends SceneTree
## Structural regression for every gun and every permitted attachment option.
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var failures := 0
var checked := 0
var worst_meshes := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for id in Data.PRIMARIES + Data.SECONDARIES:
		var defaults: Dictionary = Data.WEAPONS[id].defaults
		for slot in Data.SLOTS:
			for option in Data.WEAPONS[id].options[slot]:
				var att := defaults.duplicate()
				att[slot] = option
				_validate(id, att, "%s/%s/%s" % [id, slot, option])
	_pack_units("mgp7")
	_pack_units("zc57")
	print("WEAPON ASSETS configurations=%d worst_meshes=%d failures=%d" % [checked, worst_meshes, failures])
	quit(1 if failures else 0)

## Asset-pack guns: every part in metres with an unscaled node, or skin
## patterns (computed in mesh space) come out the wrong size. The ZC57 is
## modelled in centimetres and once showed every skin as fine static.
func _pack_units(id: String) -> void:
	var weapon := Weapon.new()
	weapon.setup(id, {})
	root.add_child(weapon)
	var parts := 0
	var stack: Array = [weapon]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and n.has_meta("pack4"):
			parts += 1
			var sc: Vector3 = (n as MeshInstance3D).transform.basis.get_scale()
			_check(sc.is_equal_approx(Vector3.ONE), "%s pack part has unit scale (%s)" % [id, sc])
			_check((n as MeshInstance3D).mesh.get_aabb().size.length() < 1.0, "%s pack part is in metres" % id)
	_check(parts > 3, id + " has asset-pack parts")
	print("  %s: %d pack parts checked" % [id, parts])
	weapon.free()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _validate(id: String, att: Dictionary, label: String) -> void:
	var weapon := Weapon.new()
	weapon.setup(id, att)
	root.add_child(weapon)
	checked += 1
	for marker in [weapon.grip, weapon.support, weapon.muzzle, weapon.mag_node, weapon.mag_well, weapon.charge, weapon.eject]:
		_check(is_instance_valid(marker) and marker.is_inside_tree() and marker.global_transform.is_finite(), label + " marker")
	_check(weapon.ads_offset.is_finite() and weapon.ads_offset.y < 0.0 and weapon.ads_offset.z < 0.0, label + " ADS")
	var pending: Array[Node] = [weapon]
	var meshes := 0
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		pending.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh != null:
			meshes += 1
			_check(node.global_transform.is_finite(), label + " finite transform")
			var bounds: AABB = node.get_aabb()
			_check(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.length() > 0.0, label + " mesh bounds")
	_check(meshes > 0, label + " has geometry")
	worst_meshes = maxi(worst_meshes, meshes)
	# Animation and FX anchors must remain live after a finish is applied.
	weapon.apply_skin("gunmetal")
	_check(weapon.skin == "gunmetal", label + " finish applied")
	_check(is_instance_valid(weapon.muzzle), label + " finish preserves muzzle")
	weapon.free()
