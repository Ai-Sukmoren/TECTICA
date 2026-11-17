extends SceneTree
## The gunsmith opens from the pause menu in the campaign and PvP (and their
## co-op sessions and Zombie Survival; closing it solo re-issues the
## loadout. Never writes the loadout file: the test restores what it changed.
##   godot --headless --path . -s res://tests/gunsmith_match_test.gd
const Main = preload("res://scripts/main.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func start(mode: String, map: String) -> Node:
	Main.saved_mode = mode
	Main.saved_map = map
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	return current_scene

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	for m in [["ch1", "forest", true], ["pvp", "warehouse", true], ["zombie", "tokyo", true]]:
		var main = await start(m[0], m[1])
		var hud = main.hud
		var items: Array = hud._pause_items()
		check(("GUNSMITH" in items) == m[2], "%s: gunsmith %s in the pause menu" % [m[0], "listed" if m[2] else "not listed"])
		if not m[2]:
			continue
		paused = true
		hud._pause_activate(items.find("GUNSMITH"))
		check(hud.gunsmith.is_open, "%s: GUNSMITH opens the gunsmith" % m[0])
		var specs_before: Array = main.player.weapons.map(func(w): return w.id)
		if m[0] == "ch1":
			# solo: a pick changes the gun in hand at once, before the gunsmith closes
			var gs = hud.gunsmith
			gs._build_rows()
			var row: int = gs._rows.find({"t": "weapon", "s": "primary"})
			var before := String(main.player.weapons[0].id)
			gs._change(row, 1)
			await process_frame
			var live := String(main.player.weapons[0].id)
			check(row >= 0 and live != before, "%s: a gunsmith pick changes the gun in hand live (%s -> %s)" % [m[0], before, live])
			gs._change(row, -1)
			await process_frame
		hud.gunsmith.close()
		hud._gunsmith_closed_in_match()
		await process_frame
		check(not hud.gunsmith.is_open and main.player.weapons.size() == specs_before.size(), "%s: closing re-issues the loadout" % m[0])
		paused = false
	print("gunsmith_match_test: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
