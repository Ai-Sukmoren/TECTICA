extends SceneTree
## Three guns: every class carries a rifle, an SMG and a pistol (plus the
## knife); keys 1-4 pick them in that order; zombie runs still start with the
## pistol and knife; the gunsmith edits the SMG; an old save without an SMG
## gets the class default.
##   godot --headless --path . -s res://tests/smg_slot_test.gd
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/core/profile.gd").current = "smg_slot_test"
	# an old save: primary + secondary only
	var cfg := ConfigFile.new()
	cfg.set_value("main", "class", 0)
	cfg.set_value("class0_primary", "id", "hk33")
	cfg.set_value("class0_secondary", "id", "zc57")
	cfg.save(load("res://scripts/core/profile.gd").path("loadout.cfg"))
	Loadout._loaded = false
	Loadout.ensure()
	var c := Loadout.current()
	check(String(c.secondary.id) == "zc57" and String(c.smg.id) in Data.SMGS, "old save keeps its pistol and gets the class SMG (%s)" % c.smg.id)
	for i in Data.CLASSES.size():
		var cl: Dictionary = Data.CLASSES[i]
		check(Data.SMGS.has(String(cl.smg[0])) and Data.PRIMARIES.has(String(cl.primary[0])) and Data.SECONDARIES.has(String(cl.secondary[0])),
				"%s: rifle %s, SMG %s, pistol %s" % [cl.name, cl.primary[0], cl.smg[0], cl.secondary[0]])
	var list := Loadout.weapon_list()
	check(list.size() == 4 and Data.SMGS.has(String(list[1][0])) and String(list[3][0]) in Data.KNIVES, "loadout is rifle, SMG, pistol, knife")
	check(not Data.PRIMARIES.has("mgp7") and Data.SMGS.has("gepard"), "MGP7 and Gepard are SMGs")
	var zs: Array = load("res://scripts/modes/zombie_shop.gd").starting_specs()
	check(zs.size() == 2 and Data.SECONDARIES.has(String(zs[0][0])) and String(zs[1][0]) in Data.KNIVES, "zombie runs start with pistol and knife")
	# in game: keys 1-4
	Main.saved_mode = "pvp"
	Main.saved_map = "warehouse"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var p = current_scene.player
	check(p.weapons.size() == 4, "the operator carries four weapons")
	var picks := []
	for role in ["primary", "smg", "pistol", "knife"]:
		picks.append(String(p.weapons[p._slot(role)].id))
	print("  keys 1-4 -> ", picks)
	check(Data.PRIMARIES.has(picks[0]) and Data.SMGS.has(picks[1]) and Data.SECONDARIES.has(picks[2]) and Data.KNIVES.has(picks[3]), "keys 1-4: rifle, SMG, pistol, knife")
	check(InputMap.has_action("weapon_4"), "key 4 is bound")
	var gs = current_scene.hud.gunsmith
	gs._build_rows()
	var smg_rows: Array = gs._rows.filter(func(r): return r.get("s", "") == "smg")
	check(smg_rows.size() >= 3, "gunsmith has SMG rows (%d)" % smg_rows.size())
	print("SMG SLOT: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
