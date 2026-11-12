extends SceneTree
## Operator outfits: every palette builds, buying/wearing with credits, the
## outfit travels with the network loadout, and the Armory tab previews it.
## Restores the account's credits and outfits afterwards.
##   godot --headless --path . -s res://tests/outfit_test.gd
const Main = preload("res://scripts/main.gd")
const Outfits = preload("res://scripts/skins/outfits.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Player = preload("res://scripts/characters/player.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	Collection.ensure()
	var keep := [Collection.credits, Collection.outfits_owned.duplicate(), Collection.outfit]

	var keys := ["camo", "vest", "gear", "helmet", "detail", "skin", "face", "gloves", "boots", "headgear"]
	var bad := 0
	for id in Outfits.ids():
		var pal := Outfits.palette(id)
		for k in keys:
			if not pal.has(k) or pal[k] == null:
				bad += 1
	check(bad == 0, "all %d outfit palettes are complete" % Outfits.ids().size())
	check(Collection.has_outfit(Outfits.DEFAULT), "default outfit is always owned")

	Collection.outfits_owned = []
	Collection.credits = 100
	check(Collection.buy_outfit("arctic") == "NOT ENOUGH CREDITS", "buying without credits fails")
	check(not Collection.has_outfit("arctic"), "outfit stays locked")
	check(not Collection.wear_outfit("arctic"), "cannot wear a locked outfit")
	Collection.credits = 5000
	check(Collection.buy_outfit("arctic") == "", "buying with credits works")
	check(Collection.credits == 5000 - int(Outfits.info("arctic").price), "price is deducted")
	check(Collection.wear_outfit("arctic") and Collection.outfit == "arctic", "bought outfit can be worn")

	var nl: Array = Player.net_loadout()
	check(nl[-1] is Dictionary and String(nl[-1].outfit) == "arctic", "network loadout carries the outfit")
	var remote = main.add_remote_player(77, {"name": "BUDDY", "loadout": nl}, main.player.global_position + Vector3(3, 0, 0), 0.0)
	await process_frame
	check(remote.outfit == "arctic", "remote operator wears the sender's outfit")
	check(remote.weapons.size() == nl.size() - 1, "outfit entry is not built as a weapon (%d guns)" % remote.weapons.size())
	main.remove_remote_player(77)

	var arm = main.hud.armory
	arm.open()
	arm.tab = 2
	arm.outfit_i = Outfits.ids().find("neon")
	for i in 3: await process_frame
	var rigs: Array = arm._pivot.get_children().filter(func(n): return n.get("hips") != null)
	check(rigs.size() == 1, "armory OUTFITS tab shows a 3D operator")
	arm.close()

	Collection.credits = int(keep[0])
	Collection.outfits_owned = keep[1]
	Collection.outfit = String(keep[2])
	Collection.save()
	print("OUTFIT: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
