extends SceneTree
## Exports what tools/fit_hand_contacts.py needs to fit the FPS hands to each gun:
## the gun's triangles, each palm (centre + facing) and every finger's joints over a
## sweep of curl amounts, all in weapon space, with the contact fit switched off.
## godot --headless --path . -s res://tools/probe_hand_contact.gd -- out.json
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
const CURLS := 33          # curl amounts 0.0 .. 1.6
const TIP := 0.018         # distal bone length past its head (no tail bone)

func _initialize() -> void:
	run.call_deferred()

func v3(p: Vector3) -> Array:
	return [p.x, p.y, p.z]

## Skin depth around the hand bones, from the bind-pose mesh.
func skin_depth(skin) -> Dictionary:
	var palm := [0.0, 0.0]
	var finger := [[], []]
	for mi in skin.meshes:
		var sk: Skin = mi.skin
		for s in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(s)
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			for v in verts.size():
				var k := 0
				for j in 4:
					if weights[v * 4 + j] > weights[v * 4 + k]:
						k = j
				var bind: int = bones[v * 4 + k]
				var bone: int = sk.get_bind_bone(bind) if sk.get_bind_bone(bind) >= 0 else skin.skel.find_bone(sk.get_bind_name(bind))
				var p: Vector3 = skin.rest[bone] * sk.get_bind_pose(bind) * verts[v]
				for i in 2:
					var c: Dictionary = skin.chains[i]
					var hf: Basis = c.frame
					var centre: Vector3 = skin.rest[c.h].origin + hf * (c.palm as Vector3)
					var rel := p - centre
					if bone == c.h and Vector2(rel.dot(hf.x), rel.dot(hf.y)).length() < 0.015:
						palm[i] = maxf(palm[i], rel.dot(hf.z))
					var side := "L" if i == 0 else "R"
					var m2: int = skin.skel.find_bone("Middle 2." + side)
					var m1: int = skin.skel.find_bone("Middle 1." + side)
					if bone == m2:
						var a0: Vector3 = skin.rest[m2].origin
						var axis: Vector3 = skin.rest[m1].origin - a0
						var t := clampf((p - a0).dot(axis) / axis.length_squared(), 0.0, 1.0)
						finger[i].append(p.distance_to(a0 + axis * t))
	var radius := []
	for i in 2:
		var r: Array = finger[i]
		r.sort()
		radius.append(r[int(r.size() * 0.75)] if not r.is_empty() else 0.009)
	return {"palm": palm, "finger": radius}

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var rig = Rig.new()
	root.add_child(rig)
	rig.build(Palettes.player())
	rig.set_process(false)
	rig.set_first_person(true)
	var skin = rig.fp_arm_rig
	var all := {"skin": skin_depth(skin), "guns": {}}
	for id in Data.WEAPONS:
		var variants: Array = [{}]
		if "gp25" in Data.WEAPONS[id].options.underbarrel:
			variants.append({"underbarrel": "gp25"})
		if "hex" in Data.WEAPONS[id].options.handguard:
			variants.append({"handguard": "hex"})
		for attachments in variants:
			var w = Weapon.new()
			w.setup(id, attachments)
			rig.set_weapon(w, [])
			w.set_process(false)
			var key: String = skin.contact_key(w)
			if all.guns.has(key):
				rig.weapon = null
				w.free()
				continue
			var zero := {"shift": [Vector3.ZERO, Vector3.ZERO], "curl": [[-1.0, -1.0, -1.0, -1.0, -1.0], [-1.0, -1.0, -1.0, -1.0, -1.0]]}
			skin.contact = zero
			rig.aim_target = 0.0
			rig.sprint_target = 0.0
			for i in 120:
				rig._animate(1.0 / 60.0)
			var inv: Transform3D = w.global_transform.affine_inverse()
			var to_w: Transform3D = inv * skin.skel.global_transform
			var sides := []
			for i in 2:
				var hand: Transform3D = rig.hands[i].global_transform
				sides.append({"palm": v3(inv * hand.origin), "normal": v3((inv.basis * hand.basis.z).normalized())})
			var sweep := []
			for n in CURLS:
				var s := 1.6 * n / (CURLS - 1)
				skin.contact = {"shift": zero.shift, "curl": [[s, s, s, s, s], [s, s, s, s, s]]}
				skin.pose(100.0)
				var hands := []
				for side in ["L", "R"]:
					var fingers := []
					for f in skin.FINGERS:
						var pts := []
						for j in [3, 2, 1]:
							pts.append(v3(to_w * skin.poses[skin.skel.find_bone("%s %d.%s" % [f, j, side])].origin))
						pts.append(v3(to_w * (skin.poses[skin.skel.find_bone("%s 1.%s" % [f, side])] * Vector3(0, TIP, 0))))
						fingers.append(pts)
					hands.append(fingers)
				sweep.append({"curl": s, "hands": hands})
			var tris := []
			for mi in w.find_children("*", "MeshInstance3D", true, false):
				if not mi.is_visible_in_tree() or mi.mesh == null:
					continue
				var m: Transform3D = inv * mi.global_transform
				for f in mi.mesh.get_faces():
					tris.append(v3(m * f))
			var model := String(w.stats.model)
			all.guns[key] = {"model": model, "melee": w.is_melee(), "pistol": w.is_pistol(), "sides": sides, "sweep": sweep, "faces": tris,
				"trigger": v3(skin.TRIGGERS[model]) if skin.TRIGGERS.has(model) else null}
			skin.contact = {}
			print("PROBE ", key, " faces=", tris.size() / 3)
			rig.weapon = null
			w.free()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(all))
	f.close()
	rig.free()
	quit()
