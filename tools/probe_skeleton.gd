extends SceneTree
## Prints skeleton rest data of a character model (for retargeting).
##   godot --headless --path . -s res://tools/probe_skeleton.gd -- <res://model.gltf>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://assets/thirdparty/quaternius_modular_characters/Swat.gltf"
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	get_root().add_child(inst)
	var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skx := (sk as Node3D).global_transform
	print("skeleton global xform: ", skx)
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		print("mesh ", mi.name, " aabb ", mi.get_aabb(), " skin=", mi.skin != null)
	for b in ["Root", "Body", "Hips", "Abdomen", "Torso", "Chest", "Neck", "Head", "Shoulder.R", "UpperArm.R", "LowerArm.R", "Wrist.R",
			"Middle1.R", "UpperLeg.R", "LowerLeg.R", "Foot.R"]:
		var i := sk.find_bone(b)
		if i < 0:
			print(b, " missing")
			continue
		var g := sk.get_bone_global_rest(i)
		var w := skx * g
		print("%-11s world=%s  y_axis=%s  z_axis=%s" % [b, w.origin.snappedf(0.001), (skx.basis * g.basis.y).normalized().snappedf(0.01), (skx.basis * g.basis.z).normalized().snappedf(0.01)])
	quit()
