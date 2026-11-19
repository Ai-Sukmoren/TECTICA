extends SceneTree
## Gunsmith speed and SCAR-H iron sights (weapon_model.gd fit memo, weapon.gd ads_offset):
## a remembered fit places every part exactly where a fresh fit does, a rebuild
## of an already-seen configuration is fast, and the SCAR-H sight line runs over
## the tip of its front post (it used to sit 1.4 cm low, so the gun aimed high).
##   godot --headless --path . -s res://tests/gunsmith_speed_test.gd
const Weapon = preload("res://scripts/weapons/weapon.gd")
const WM = preload("res://scripts/weapons/weapon_model.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

## Every mesh's transform under the gun (in build order, rounded to 0.1 mm): its whole layout.
func layout(w: Node3D) -> Array:
	var out: Array = []
	for n in w.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		var xf: Transform3D = w.global_transform.affine_inverse() * m.global_transform
		out.append(str((xf.origin * 10000.0).round()) + str(xf.basis.get_scale().snappedf(0.001)))
	return out

func build(id: String, att: Dictionary) -> Node3D:
	var w = Weapon.new()
	w.setup(id, att)
	root.add_child(w)
	return w

func run() -> void:
	await process_frame
	# ---------------------------------------------------------------- memo matches a fresh fit
	var configs := [["scar_h", {"optic": "holo", "underbarrel": "laser"}], ["hk33", {"optic": "reddot", "rail": "rail"}],
			["mgp7", {"optic": "acog", "muzzle": "suppressor"}], ["g17", {"optic": "minidot"}]]
	var same := true
	for c in configs:
		if not Data.WEAPONS.has(c[0]):
			continue
		var att: Dictionary = {}
		for k in c[1]:
			if (Data.WEAPONS[c[0]].options.get(k, []) as Array).has(c[1][k]):
				att[k] = c[1][k]
		WM._fit_memo.clear()
		var a := build(c[0], att)
		var la := layout(a)
		var ia: Dictionary = a.get_meta("iron_info")
		var b := build(c[0], att)   # every fit now comes from the memo
		var lb := layout(b)
		var ib: Dictionary = b.get_meta("iron_info")
		if la != lb or not ia.y == ib.y or not ia.rear_z == ib.rear_z:
			same = false
			print("    differs: %s" % c[0])
		a.free()
		b.free()
	check(same, "a remembered fit puts every part exactly where a fresh fit does")
	# ---------------------------------------------------------------- rebuild speed
	var att2 := {"optic": "holo", "muzzle": "suppressor", "underbarrel": "laser"}
	build("scar_h", att2).free()
	var t0 := Time.get_ticks_usec()
	for i in 10:
		build("scar_h", att2).free()
	var ms := float(Time.get_ticks_usec() - t0) / 10000.0
	print("  SCAR-H with three attachments, rebuilt: %.1f ms" % ms)
	check(ms < 8.0, "rebuilding a configuration the gunsmith has shown is fast")
	# ---------------------------------------------------------------- SCAR-H iron sight line
	var s := build("scar_h", {})
	var info: Dictionary = s.get_meta("iron_info")
	var post := -INF   # top of the front sight post, on the centreline
	for n in s.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		var xf: Transform3D = s.global_transform.affine_inverse() * m.global_transform
		for v in m.mesh.get_faces():
			var p: Vector3 = xf * v
			if absf(p.x) < 0.02 and p.z > -0.43 and p.z < -0.38:
				post = maxf(post, p.y)
	var gap := post - float(info.y)
	print("  SCAR-H sight line %.3f m, front post tip %.3f m (%.1f mm above the line)" % [info.y, post, gap * 1000.0])
	check(gap > 0.0 and gap < 0.012, "the SCAR-H sight line runs just under the tip of its front post")
	check(is_equal_approx(s.ads_offset.y, -float(info.y)), "aiming puts that sight line on the camera's axis")
	s.free()
	print("GUNSMITH SPEED: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
