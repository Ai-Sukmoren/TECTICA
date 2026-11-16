extends SceneTree
## Worst wrist angles (degrees, relative to the arm model's rest pose) per weapon and
## action: flexion (+ toward palm), deviation (+ toward thumb), twist. Human comfort
## is roughly flex -60..70, deviation -30..20; twist should stay small.
## godot --headless --path . -s res://tools/wrist_angles.gd
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
var rig

func _initialize() -> void:
	run.call_deferred()

## Wrist angles in degrees: flexion (+ toward palm), radial deviation (+ toward thumb),
## twist of the hand about the forearm relative to the rest pose.
func wrist(side: int) -> Vector3:
	var skin = rig.fp_arm_rig
	return _angles(side, skin.poses) - _angles(side, skin.rest)

func _angles(side: int, poses: Array) -> Vector3:
	var skin = rig.fp_arm_rig
	var c: Dictionary = skin.chains[side]
	var s := "L" if side == 0 else "R"
	var h: Transform3D = poses[c.h]
	var l: Transform3D = poses[c.l]
	var hf: Basis = (h.basis * (skin.rest[c.h] as Transform3D).basis.inverse() * (c.frame as Basis)).orthonormalized()
	var f := (h.origin - l.origin).normalized()
	var fh := hf.inverse() * f
	var flex := rad_to_deg(atan2(-fh.z, fh.y))
	var thumb: Vector3 = poses[skin.skel.find_bone("Thumb 3." + s)].origin - h.origin
	var tsign := signf(thumb.dot(hf.x))
	var dev := rad_to_deg(atan2(-fh.x * tsign, fh.y))
	# twist: hand roll relative to the forearm bone about the forearm axis
	var tw := _roll(l.basis, h.basis, f)
	return Vector3(flex, dev, tw)

func _roll(a: Basis, b: Basis, axis: Vector3) -> float:
	var ax := a.x - axis * a.x.dot(axis)
	var bx := b.x - axis * b.x.dot(axis)
	return rad_to_deg(ax.signed_angle_to(bx, axis))

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	rig = Rig.new()
	scene.add_child(rig)
	rig.build(Palettes.player())
	rig.set_process(false)
	rig.set_first_person(true)
	print("weapon        state      L flex   dev  twist |  R flex   dev  twist")
	for id in Data.PRIMARIES + Data.SMGS + Data.SECONDARIES + Data.KNIVES:
		var w = Weapon.new()
		w.setup(id)
		rig.set_weapon(w, [])
		w.set_process(false)
		rig.one_hand_sprint = true
		var states := {}
		for st in ["idle", "ads", "reload", "inspect", "sprint"]:
			rig.aim_target = 1.0 if st == "ads" else 0.0
			rig.sprint_target = 1.0 if st == "sprint" else 0.0
			if st == "reload" and not w.is_melee():
				rig.play_reload(2.0, true)
			if st == "inspect":
				rig.play_inspect()
			var worst := [Vector3.ZERO, Vector3.ZERO]
			for n in 120:
				rig._animate(1.0 / 60.0)
				if st in ["idle", "ads", "sprint"] and n < 100:
					continue
				for sd in 2:
					var a := wrist(sd)
					for k in 3:
						if absf(a[k]) > absf(worst[sd][k]):
							worst[sd][k] = a[k]
			print("%-12s  %-8s  %6.0f %5.0f %6.0f | %6.0f %5.0f %6.0f" % [id, st, worst[0].x, worst[0].y, worst[0].z, worst[1].x, worst[1].y, worst[1].z])
			rig.cancel_reload()
			rig.cancel_inspect()
			rig.sprint_target = 0.0
			rig.aim_target = 0.0
			for n in 60:
				rig._animate(1.0 / 60.0)
		rig.weapon = null
		w.free()
	quit()
