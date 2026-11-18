extends SceneTree
## Ruby finish, sticker placement and admin gating. Read-only: never writes
## user://accounts.cfg or any profile file.
const Skins = preload("res://scripts/skins/skins.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Sticker = preload("res://scripts/skins/sticker.gd")

var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)


## Parts of `w` with a sticker printed on them.
func printed(w) -> int:
	var n := 0
	for m in w._model_root.find_children("*", "MeshInstance3D", true, false):
		if Sticker._prints(m) and (m as MeshInstance3D).get_instance_shader_parameter("stk_a") != Vector4.ZERO:
			n += 1
	return n


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# packs never drop admin finishes; the public catalogue hides them
	check(Skins.rarity_of("ruby") == Skins.Rarity.MYTHIC and Skins.RARITY_NAMES[5] == "MYTHIC", "Ruby is MYTHIC")
	for r in 6:
		check(not ("ruby" in Skins.finishes_of(r)), "Ruby must not be in pack pools")
	check(not ("ruby" in Skins.finish_ids()), "Ruby hidden from public catalogue")
	check("ruby" in Skins.finish_ids(true), "Ruby listed for admin")
	# signed-out / non-admin: no ruby, no dashboard data
	Profile.current = ""
	Collection._loaded = true
	check(not Collection.has_skin("hk33", "ruby"), "Non-admin can't own Ruby")
	check(Profile.dashboard_rows().is_empty() and Profile.login_log().is_empty(), "Dashboard data is admin-only")
	# simulate an admin session through the cache (no file writes)
	Profile.current = "test_admin"
	Profile._admin_for = "test_admin"
	Profile._admin_val = true
	check(Collection.has_skin("uar10", "ruby") and Collection.has_skin("aug_a1", "aurora"), "Admin has every skin")
	Profile.current = ""
	Profile._admin_for = "?"

	# sticker printed through the finish on every gun: each skinned part carries the
	# same rectangle and its own transform into gun space; hiding clears it
	var scene := Node3D.new()
	root.add_child(scene)
	var art := Sticker.texture("patch_02") != null
	for id in Skins.weapon_ids():
		var w := Weapon.new()
		w.setup(id, {})
		scene.add_child(w)
		w.apply_skin("ruby")
		w.apply_sticker({"side": 2, "u": 0.5, "v": 0.6, "s": 1.0})
		check(w._model_root.find_children("Sticker*", "MeshInstance3D", false, false).is_empty(), "%s: no flat sticker quads" % id)
		var printing := 0
		var a0 = null
		for n in w._model_root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if not Sticker._prints(mi):
				continue
			printing += 1
			var a: Vector4 = mi.get_instance_shader_parameter("stk_a")
			check(a.is_finite() and a.z > 0.0 and a.w > 0.0, "%s: sticker rectangle on %s" % [id, mi.name])
			check(a0 == null or a == a0, "%s: one rectangle across every part" % id)
			a0 = a
			# the part's rows map its own vertices into gun space
			var c := mi.mesh.get_aabb().get_center()
			var v := Vector4(c.x, c.y, c.z, 1.0)
			var g := Vector3((mi.get_instance_shader_parameter("stk_r0") as Vector4).dot(v), (mi.get_instance_shader_parameter("stk_r1") as Vector4).dot(v), (mi.get_instance_shader_parameter("stk_r2") as Vector4).dot(v))
			check(g.distance_to(Sticker._rel(mi, w._model_root) * c) < 0.0005, "%s: %s gun-space transform" % [id, mi.name])
		if art:
			check(printing > 0, "%s: sticker printed on the gun" % id)
			# a full wrap covers the whole side of the gun
			var b := Sticker.bounds(w._model_root)
			var r := Sticker.rect(w._model_root, "patch_02", {"s": 1.0})
			check(float(r[2]) >= b.size.z - 0.001 and float(r[3]) >= b.size.y - 0.001, "%s: full wrap covers the gun" % id)
		w.apply_sticker({"on": false})
		for n in w._model_root.find_children("*", "MeshInstance3D", true, false):
			if Sticker._prints(n):
				check((n as MeshInstance3D).get_instance_shader_parameter("stk_a") == Vector4.ZERO, "%s: hide removes sticker" % id)
		w.queue_free()
	var cfg := Sticker.clamp_cfg({"u": 4.0, "v": 3.0, "s": 99.0, "side": 7})
	check(cfg.u == 1.0 and cfg.v == 1.0 and cfg.s == Sticker.S_MAX and cfg.side == 2, "Sticker config clamps")
	check(Sticker.clamp_cfg({}).v < 0.0 and Sticker.clamp_cfg({}).s == 1.0, "Default sticker is a full wrap at auto height")
	# a finish without its own sticker prints none, unless the placement names one
	# (admins put the sticker on any skin); the factory look never prints one
	var plain := Weapon.new()
	plain.setup("hk33", {})
	scene.add_child(plain)
	plain.apply_skin("aurora")
	plain.apply_sticker({})
	check(printed(plain) == 0, "Plain finish has no sticker")
	if art:
		plain.apply_sticker({"id": "patch_02"})
		check(printed(plain) > 0, "A named sticker prints on any skin")
		plain.apply_sticker({"id": "nonsense"})
		check(printed(plain) == 0, "An unknown sticker name prints nothing")
		plain.apply_skin("")
		plain.apply_sticker({"id": "patch_02"})
		check(printed(plain) == 0, "The factory look takes no sticker")
	# who gets to: admins on every skin (it starts hidden there), others only on Ruby
	Profile.current = "test_admin"
	Profile._admin_for = "test_admin"
	Profile._admin_val = true
	var a := Collection.sticker_for("hk33", "aurora")
	check(String(a.get("id", "")) == Skins.DEFAULT_STICKER and not bool(a.on), "Admin: any skin can take the sticker, hidden until placed")
	check(not Collection.sticker_for("hk33", "ruby").has("id") and bool(Collection.sticker_for("hk33", "ruby").on), "Ruby keeps its own sticker, shown")
	check(not Collection.sticker_for("hk33", "").has("id"), "No sticker on the factory look")
	Profile.current = "someone"
	Profile._admin_for = "someone"
	Profile._admin_val = false
	check(not Collection.sticker_for("hk33", "aurora").has("id"), "Non-admins can't put the sticker on other skins")
	Profile.current = ""
	Profile._admin_for = "?"
	print("ADMIN + RUBY: failures=", failures)
	quit(0 if failures == 0 else 1)
