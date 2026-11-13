extends SceneTree
## Title screen: the idle operator follows loadout and outfit changes live
## (no deploy needed), keeps idling, and deploys with the new kit.
##   godot --headless --path . -s res://tests/menu_live_look_test.gd
const Main = preload("res://scripts/main.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Outfits = preload("res://scripts/skins/outfits.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout

func gun_ids(p) -> Array:
	return p.weapons.map(func(w): return String(w.id))

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "ch1"
	Main.saved_mode = mode
	Main.saved_map = "town"
	Main.quick_restart = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 40: await process_frame
	var main = current_scene
	var p = main.player
	check(main.hud.title and paused, "title screen, world paused")
	var outfit0 := Collection.outfit
	var class0 := Loadout.class_index
	var guns0 := gun_ids(p)
	var rig0 = p.rig

	# --- outfit
	var other := ""
	for id in Outfits.ids():
		if id != outfit0:
			other = id
			break
	Collection.outfit = other
	await wait(0.6)
	check(p.outfit == other, "operator now wears '%s' (was '%s')" % [other, outfit0])
	check(p.rig != rig0 and is_instance_valid(p.rig), "the body was rebuilt in the new outfit")
	check(p.rig.process_mode == Node.PROCESS_MODE_ALWAYS, "the new body keeps animating through the pause")
	check(p.rig.weapon != null and p.rig.weapon.get_parent() == p.rig.weapon_anchor, "the weapon moved to the new body's hands")
	var y0: float = p.rig.aim_yaw
	await wait(1.5)
	check(absf(p.rig.aim_yaw - y0) > 0.01, "the new body still idles (looks around)")

	# --- loadout (class)
	var tries := 0
	while gun_ids(p) == guns0 and tries < 8:
		Loadout.cycle_class(1)
		await wait(0.6)
		tries += 1
	print("    guns %s -> %s" % [str(guns0), str(gun_ids(p))])
	check(gun_ids(p) != guns0, "changing class swaps the weapons on the operator")
	var want: Array = main.director.shop.specs() if main.director != null else Loadout.weapon_list()
	check(gun_ids(p) == want.map(func(s): return String(s[0])), "operator carries exactly what it would deploy with")

	# --- deploy keeps it
	var rig1 = p.rig
	main.hud._deploy()
	await process_frame
	await process_frame
	check(not paused and p.rig == rig1 and p.rig.process_mode == Node.PROCESS_MODE_INHERIT, "deploy hands the new body back to the game")
	check(p.outfit == other, "deployed in the chosen outfit")

	# restore the profile
	Collection.outfit = outfit0
	while Loadout.class_index != class0:
		Loadout.cycle_class(1)
	print("MENU_LIVE: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
