extends RefCounted
## Player loadouts: one editable primary + secondary per class, persisted to
## user://loadout.cfg so customisations survive restarts.

const Data = preload("res://scripts/weapons/weapon_data.gd")
const PATH := "user://loadout.cfg"   # per account: Profile.path()
const Profile = preload("res://scripts/core/profile.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Charm = preload("res://scripts/skins/charm.gd")

static var class_index := 0
## The knife carried in every class (melee slot, key 3).
static var knife := "knife_combat"
static var classes: Array = []
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	classes.clear()
	for i in Data.CLASSES.size():
		classes.append(_preset(i))
	var cfg := ConfigFile.new()
	if cfg.load(Profile.path("loadout.cfg")) != OK:
		return
	class_index = clampi(int(cfg.get_value("main", "class", 0)), 0, classes.size() - 1)
	var kn := String(cfg.get_value("main", "knife", "knife_combat"))
	knife = kn if kn in Data.KNIVES else "knife_combat"
	for i in classes.size():
		for slot in ["primary", "secondary"]:
			var sec := "class%d_%s" % [i, slot]
			if not cfg.has_section(sec):
				continue
			var id := String(cfg.get_value(sec, "id", ""))
			var allowed: Array = Data.PRIMARIES if slot == "primary" else Data.SECONDARIES
			if id in allowed:
				var att = cfg.get_value(sec, "att", {})
				classes[i][slot] = {"id": id, "att": Data.sanitize(id, att if att is Dictionary else {}),
						"charm": Charm.sanitize(String(cfg.get_value(sec, "charm", "")))}


static func _preset(i: int) -> Dictionary:
	var c: Dictionary = Data.CLASSES[i]
	return {
		"primary": {"id": c.primary[0], "att": Data.sanitize(c.primary[0], c.primary[1]), "charm": ""},
		"secondary": {"id": c.secondary[0], "att": Data.sanitize(c.secondary[0], c.secondary[1]), "charm": ""},
	}


static func save() -> void:
	ensure()
	var cfg := ConfigFile.new()
	cfg.set_value("main", "class", class_index)
	cfg.set_value("main", "knife", knife)
	for i in classes.size():
		for slot in ["primary", "secondary"]:
			var e: Dictionary = classes[i][slot]
			cfg.set_value("class%d_%s" % [i, slot], "id", e.id)
			cfg.set_value("class%d_%s" % [i, slot], "att", e.att)
			cfg.set_value("class%d_%s" % [i, slot], "charm", Charm.sanitize(String(e.get("charm", ""))))
	cfg.save(Profile.path("loadout.cfg"))


static func current() -> Dictionary:
	ensure()
	return classes[class_index]


static func class_label(i: int = -1) -> String:
	ensure()
	return String(Data.CLASSES[class_index if i < 0 else i].name)


static func class_desc() -> String:
	return String(Data.CLASSES[class_index].desc)


static func cycle_class(dir: int) -> void:
	ensure()
	class_index = posmod(class_index + dir, classes.size())


static func entry(slot: String) -> Dictionary:
	if slot == "knife":
		ensure()
		return {"id": knife, "att": Data.sanitize(knife, {}), "charm": ""}
	return current()[slot]


static func cycle_knife(dir: int) -> void:
	ensure()
	knife = Data.KNIVES[posmod(Data.KNIVES.find(knife) + dir, Data.KNIVES.size())]


static func cycle_weapon(slot: String, dir: int) -> void:
	var list: Array = Data.PRIMARIES if slot == "primary" else Data.SECONDARIES
	var e: Dictionary = entry(slot)
	var idx := list.find(e.id)
	var id: String = list[posmod(idx + dir, list.size())]
	current()[slot] = {"id": id, "att": Data.sanitize(id, {}), "charm": Charm.sanitize(String(e.get("charm", "")))}


static func cycle_charm(slot: String, dir: int) -> void:
	var e := entry(slot)
	var idx := Charm.IDS.find(Charm.sanitize(String(e.get("charm", ""))))
	e.charm = Charm.IDS[posmod(idx + dir, Charm.IDS.size())]


static func cycle_attachment(slot: String, att_slot: String, dir: int) -> void:
	var e: Dictionary = entry(slot)
	var opts: Array = Data.WEAPONS[e.id].options[att_slot]
	var idx := opts.find(e.att[att_slot])
	e.att[att_slot] = opts[posmod(idx + dir, opts.size())]


static func reset_class() -> void:
	ensure()
	classes[class_index] = _preset(class_index)


## [[id, att, skin], ...] for Soldier.setup_soldier / set_loadout (skins are
## part of the spec so other multiplayer peers see them too).
static func weapon_list() -> Array:
	var c := current()
	return [[c.primary.id, c.primary.att, Collection.skin_for(String(c.primary.id)), Collection.sticker_for(String(c.primary.id)), Charm.sanitize(String(c.primary.get("charm", "")))],
			[c.secondary.id, c.secondary.att, Collection.skin_for(String(c.secondary.id)), Collection.sticker_for(String(c.secondary.id)), Charm.sanitize(String(c.secondary.get("charm", "")))],
			[knife, Data.sanitize(knife, {}), Collection.skin_for(knife), {}, ""]]
