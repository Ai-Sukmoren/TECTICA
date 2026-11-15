extends SceneTree
## GP-25 under-barrel launcher: fitted on the HK33, fires a 40 mm round from its
## muzzle that explodes on impact, uses a round, reloads, and stops when empty.
##   godot --headless --path . -s res://tests/launcher_test.gd
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	load("res://scripts/core/profile.gd").current = "launcher_test"
	check(Data.sanitize("hk33", {"underbarrel": "gp25"}).rail == "rail", "the GP-25 puts the rail on")
	check(bool(Data.compute("hk33", {"underbarrel": "gp25"}).launcher), "HK33 + GP-25 has a launcher")
	check(not bool(Data.compute("hk33", {}).launcher), "plain HK33 has none")
	Main.saved_mode = "zombie"; Main.saved_map = "town"; Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var m = current_scene
	var p = m.player
	p.health = 1.0e9
	m.director.timer = 9999.0
	p.set_loadout([["hk33", {"underbarrel": "gp25"}], ["knife_combat", {}]])
	for i in 30: await physics_frame
	var w = p.current_weapon()
	check(w.launcher != null, "the GP-25 has a muzzle marker")
	check(p.launcher_rounds == p.LAUNCHER_MAX, "starts with %d rounds (%d)" % [p.LAUNCHER_MAX, p.launcher_rounds])
	var before: int = get_nodes_in_group("grenades").size()
	var target: Vector3 = p.global_position + Vector3(0, 1.0, -25.0)
	check(p.fire_launcher(target), "fires")
	var rounds: Array = get_nodes_in_group("grenades").filter(func(g): return g.kind == "vog")
	check(rounds.size() == 1 and get_nodes_in_group("grenades").size() == before + 1, "one 40 mm round in flight")
	check(p.launcher_rounds == p.LAUNCHER_MAX - 1, "a round is used")
	check(not p.fire_launcher(target), "cannot fire again while reloading")
	var g = rounds[0] if not rounds.is_empty() else null
	var start: Vector3 = g.global_position if g else Vector3.ZERO
	var exploded := false
	for i in 240:
		await physics_frame
		if not is_instance_valid(g):
			exploded = true
			break
	check(exploded, "the round explodes on impact (within 4 s)")
	for i in 120: await physics_frame
	p.launcher_rounds = 0
	check(not p.fire_launcher(target), "cannot fire when empty")
	p.set_loadout([["hk33", {}], ["knife_combat", {}]])
	for i in 10: await physics_frame
	p.launcher_rounds = 3
	check(not p.fire_launcher(target), "cannot fire without a GP-25")
	print("LAUNCHER: failures=%d" % failures)
	quit(0 if failures == 0 else 1)
