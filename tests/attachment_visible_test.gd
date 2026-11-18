extends SceneTree
## Every attachment of every gun is drawn: building the gun with it adds visible geometry of real size (tagged with
## its slot), with no see-through material; and it stays drawn under every finish, with the sticker on. The Armory
## shows a gun with the attachments the operator carries on it.
##   godot --headless --path . -s res://tests/attachment_visible_test.gd
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Skins = preload("res://scripts/skins/skins.gd")
## options that are the absence of a part (nothing to draw)
const NOTHING := ["none", "standard", "iron", "integral"]
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func build(id: String, att: Dictionary, skin: String = "") -> Node3D:
	var w := Weapon.new()
	root.add_child(w)
	w.setup(id, att)
	if skin != "":
		w.apply_skin(skin, {})
		w.apply_sticker({"on": true})
	return w


## Problems with the drawn meshes of `slot` on gun `w`: [count of visible meshes, problem text or ""].
func slot_meshes(w: Node3D, slot: String) -> Array:
	var n := 0
	var problem := ""
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.get_meta("skin_part", "")) != slot or m.mesh == null:
			continue
		if not m.is_visible_in_tree():
			problem = "%s hidden" % m.name
			continue
		var box := m.get_aabb()
		var sc := m.global_transform.basis.get_scale()
		if box.size.length() * maxf(sc.x, maxf(sc.y, sc.z)) < 0.005:
			problem = "%s has no size" % m.name
			continue
		var mats: Array = []
		if m.material_override != null:
			mats.append(m.material_override)
		else:
			for s in m.mesh.get_surface_count():
				mats.append(m.get_surface_override_material(s) if m.get_surface_override_material(s) != null else m.mesh.surface_get_material(s))
		var seen := false
		for mat in mats:
			if mat == null or not (mat is BaseMaterial3D):
				seen = true
				continue
			var bm := mat as BaseMaterial3D
			if bm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or bm.albedo_color.a > 0.2:
				seen = true
		if not seen:
			problem = "%s is see-through" % m.name
			continue
		n += 1
	return [n, problem]


func run() -> void:
	var finishes: Array = ["", "ruby"]
	for f in Skins.FINISHES:
		if not bool(Skins.FINISHES[f].get("admin", false)):
			finishes.append(f)
			break
	var checked := 0
	var bad: Array = []
	for id in Data.WEAPONS:
		if Data.WEAPONS[id].get("kind", "") == "melee":
			continue
		var opts: Dictionary = Data.WEAPONS[id].options
		for slot in opts:
			for opt in opts[slot]:
				if String(opt) in NOTHING or String(opt).begins_with("builtin"):
					continue   # nothing, or a scope that is part of the gun's own model
				if slot == "magazine" and String(opt) in ["ap", "hollow"]:
					continue   # rounds: the same magazine (or none to see, on a rifle loaded from the top)
				for skin in finishes:
					var w := build(String(id), {slot: opt}, String(skin))
					var r := slot_meshes(w, String(slot))
					checked += 1
					if int(r[0]) == 0:
						bad.append("%s %s=%s (finish '%s'): %s" % [id, slot, opt, skin, String(r[1]) if String(r[1]) != "" else "nothing drawn"])
					w.free()
	print("  %d gun / attachment / finish combinations" % checked)
	# the Armory previews skins and stickers on the gun as the operator carries it (its optic and all)
	load("res://scripts/core/profile.gd").current = "attachment_visible_test"
	var Loadout = load("res://scripts/core/loadout.gd")
	var e: Dictionary = Loadout.current().primary
	if Loadout.attachments_of(String(e.id)) != Data.sanitize(String(e.id), e.att):
		bad.append("the Armory would preview %s without its attachments" % e.id)
	for b in bad:
		print("  FAIL ", b)
	failures = bad.size()
	print("ATTACHMENTS VISIBLE: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
