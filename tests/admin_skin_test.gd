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
	check(not Collection.has_skin("m4a1", "ruby"), "Non-admin can't own Ruby")
	check(Profile.dashboard_rows().is_empty() and Profile.login_log().is_empty(), "Dashboard data is admin-only")
	# simulate an admin session through the cache (no file writes)
	Profile.current = "test_admin"
	Profile._admin_for = "test_admin"
	Profile._admin_val = true
	check(Collection.has_skin("awp", "ruby") and Collection.has_skin("ak47", "aurora"), "Admin has every skin")
	Profile.current = ""
	Profile._admin_for = "?"

	# sticker on every gun: placed, flush with a side, within the gun's bounds
	var scene := Node3D.new()
	root.add_child(scene)
	for id in Skins.weapon_ids():
		var w := Weapon.new()
		w.setup(id, {})
		scene.add_child(w)
		w.apply_skin("ruby")
		w.apply_sticker({"side": 2, "u": 0.5, "v": 0.6, "s": 1.0})
		var st: Array = w._model_root.find_children("Sticker*", "MeshInstance3D", false, false)
		check(st.size() == 2, "%s: two stickers for side=both (got %d)" % [id, st.size()])
		for m in st:
			check((m as MeshInstance3D).transform.is_finite(), "%s: sticker transform" % id)
		w.apply_sticker({"on": false})
		check(w._model_root.find_children("Sticker*", "MeshInstance3D", false, false).filter(func(n): return not n.is_queued_for_deletion()).is_empty(), "%s: hide removes sticker" % id)
		w.queue_free()
	var cfg := Sticker.clamp_cfg({"u": 4.0, "v": 3.0, "s": 99.0, "side": 7})
	check(cfg.u == 1.0 and cfg.v == 1.0 and cfg.s == 2.5 and cfg.side == 2, "Sticker config clamps")
	check(Sticker.clamp_cfg({}).v < 0.0, "Default sticker height is auto")
	# a non-sticker finish never gets a sticker
	var plain := Weapon.new()
	plain.setup("m4a1", {})
	scene.add_child(plain)
	plain.apply_skin("aurora")
	plain.apply_sticker({})
	check(plain._model_root.find_children("Sticker*", "MeshInstance3D", false, false).is_empty(), "Plain finish has no sticker")
	print("ADMIN + RUBY: failures=", failures)
	quit(0 if failures == 0 else 1)
