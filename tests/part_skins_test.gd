extends SceneTree
## Every attachment and the magazine can wear its own skin: parts are tagged by the
## model builder, painted per slot, return to factory, and peer input is sanitised.
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Skins = preload("res://scripts/skins/skins.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("PART_SKINS " + label)

func painted(mi: MeshInstance3D, finish: String) -> bool:
	var mats := [Skins.material(finish, false), Skins.material(finish, true)]
	if mi.material_override in mats:
		return true
	for s in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
		if mi.get_surface_override_material(s) in mats:
			return true
	return false

func part_meshes(w, slot: String) -> Array:
	return w.find_children("*", "MeshInstance3D", true, false).filter(func(m): return String(m.get_meta("skin_part", "")) == slot)

## Meshes a finish can paint (the painter skips glass, glow and shader parts).
func paintable(w, slot: String, finish: String) -> Array:
	return part_meshes(w, slot).filter(func(m): return painted(m, finish))

func run() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	# 1. every gun, fullest attachment set: the parts it has are tagged
	for id in Data.WEAPONS:
		var att := {}
		for slot in Data.SLOTS:
			var opts: Array = Data.WEAPONS[id].options.get(slot, [])
			if not opts.is_empty():
				att[slot] = opts[opts.size() - 1]
		var w = Weapon.new()
		w.setup(id, att)
		root_node.add_child(w)
		var tags := {}
		for mi in w.find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("skin_part"):
				tags[String(mi.get_meta("skin_part"))] = true
		# the Marlin (tube) and Mosin (stripper-fed box) have no detachable magazine
		if not w.is_melee() and not String(w.stats.model) in ["marlin", "mosin", "m700"]:
			check(tags.has("magazine"), id + " magazine is its own skinnable part")
		if String(w.attachments.get("underbarrel", "none")) == "gp25":
			check(tags.has("underbarrel"), id + " GP-25 tagged")
		if String(w.attachments.get("handguard", "standard")) == "hex":
			check(tags.has("handguard"), id + " hex handguard tagged")
		print("PART_SKINS ", id, " parts=", tags.keys())
		w.free()
	# 2. painting per part on a fully kitted HK33
	var w = Weapon.new()
	w.setup("hk33", {"handguard": "hex", "underbarrel": "gp25", "muzzle": Data.WEAPONS.hk33.options.muzzle[-1]})
	root_node.add_child(w)
	var body: Array = w.find_children("*", "MeshInstance3D", true, false).filter(func(m): return not m.has_meta("skin_part"))
	w.apply_skin("gilded_royale", {"magazine": "neon_tide", "underbarrel": Skins.FACTORY})
	check(body.any(func(m): return painted(m, "gilded_royale")), "body wears the gun finish")
	check(not paintable(w, "magazine", "neon_tide").is_empty(), "magazine wears its own finish")
	check(paintable(w, "magazine", "gilded_royale").is_empty(), "magazine not painted with the gun finish")
	check(paintable(w, "underbarrel", "gilded_royale").is_empty(), "factory part keeps its look")
	check(not paintable(w, "handguard", "gilded_royale").is_empty(), "unlisted part follows the gun finish")
	# 3. gun back to factory while the magazine keeps its skin
	w.apply_skin("", {"magazine": "neon_tide"})
	check(not body.any(func(m): return painted(m, "gilded_royale")), "body back to factory")
	check(paintable(w, "handguard", "gilded_royale").is_empty(), "attachments back to factory")
	check(not paintable(w, "magazine", "neon_tide").is_empty(), "magazine skin survives the gun change")
	w.apply_skin("", {})
	check(paintable(w, "magazine", "neon_tide").is_empty(), "magazine back to factory")
	# 4. peer input: unknown slots / finishes never reach the materials
	check(Skins.sanitize_parts({"bogus": "gilded_royale", "magazine": "nope", "optic": 5, "muzzle": "factory"}) == {"muzzle": "factory"}, "sanitised part skins")
	check(Skins.sanitize_parts("not a dictionary") == {}, "non-dictionary part skins dropped")
	w.apply_skin("not_a_finish", {"magazine": "also_not"})
	check(w.skin == "" and w.part_skins.is_empty(), "unknown finishes ignored")
	# 5. the loadout spec carries part skins (memory only: never saves the real armory)
	Collection.ensure()
	var keep: Dictionary = Collection.equipped_parts.duplicate(true)
	Collection.equipped_parts = {"hk33": {"magazine": Skins.FACTORY, "bogus": "gunmetal"}}
	check(Collection.parts_for("hk33") == {"magazine": Skins.FACTORY}, "parts_for keeps valid slots only")
	for spec in Loadout.weapon_list():
		check((spec as Array).size() == 6 and spec[5] is Dictionary, "loadout spec has part skins")
	Collection.equipped_parts = keep
	print("PART_SKINS failures=", failures)
	quit(1 if failures > 0 else 0)
