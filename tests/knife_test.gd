extends SceneTree
## Knives: the melee slot (key 3), slash hits in front, backstab bonus,
## no hits out of reach or through walls, all three models build, the
## inspect flourishes move the parts, and the loadout keeps the choice.
##   godot --headless --path . -s res://tests/knife_test.gd
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Layers = preload("res://scripts/core/layers.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func ticks(n: int) -> void:
	for i in n: await physics_frame

## A fresh zombie `dist` m in front of the player, facing it (or away).
func zombie(main, dist: float, facing_away: bool) -> Node:
	var p = main.player
	main.director._spawn_one("brute")
	var z = main.enemies[main.enemies.size() - 1]
	z.max_health = 1000.0
	z.health = 1000.0
	z.set_physics_process(false)    # hold still for the test
	var fwd := Vector3(-sin(p.aim_yaw), 0, -cos(p.aim_yaw))
	z.global_position = p.global_position + fwd * dist
	z.aim_yaw = p.aim_yaw if facing_away else wrapf(p.aim_yaw + PI, -PI, PI)
	await ticks(2)
	return z

func slash_at(p, z) -> void:
	p.current_weapon().cooldown = 0.0
	p.try_fire(z.global_position + Vector3.UP * 1.2)
	await ticks(2)

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 999.0
	p.global_position = Vector3(0, 0.05, 30)
	p.aim_yaw = 0.0
	await ticks(10)

	check(p.weapons.size() == 3 and p.weapons[2].is_melee(), "loadout carries a knife in slot 3 (%s)" % p.weapons[2].id)
	Input.action_press("weapon_3")
	await ticks(2)
	Input.action_release("weapon_3")
	await ticks(Engine.physics_ticks_per_second)
	check(p.current_weapon().is_melee(), "key 3 draws the knife")
	var dmg := float(p.current_weapon().stats.damage)

	var z = await zombie(main, 1.3, false)
	await slash_at(p, z)
	print("    front slash: %.0f damage" % (1000.0 - z.health))
	check(is_equal_approx(1000.0 - z.health, dmg), "slash in front deals %.0f" % dmg)
	check(p.rig.slash_t >= 0.0, "slash animation plays")
	z.queue_free()
	main.enemies.erase(z)

	z = await zombie(main, 1.3, true)
	await slash_at(p, z)
	print("    backstab: %.0f damage" % (1000.0 - z.health))
	check(1000.0 - z.health >= dmg * 2.9, "a hit from behind is a backstab (x%.1f)" % float(p.current_weapon().stats.backstab))
	z.queue_free()
	main.enemies.erase(z)

	z = await zombie(main, 3.5, false)
	await slash_at(p, z)
	check(is_equal_approx(z.health, 1000.0), "nothing out of reach is hit")
	z.global_position = p.global_position + Vector3(0, 0, -1.6)
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3, 3, 0.2)
	cs.shape = bs
	wall.add_child(cs)
	main.add_child(wall)
	wall.global_position = p.global_position + Vector3(0, 1.5, -0.8)
	await ticks(3)
	await slash_at(p, z)
	check(is_equal_approx(z.health, 1000.0), "no hits through a wall")
	wall.queue_free()

	# models and inspect flourishes
	for id in Data.KNIVES:
		var w := Weapon.new()
		root.add_child(w)
		w.setup(id, {})
		var meshes := w.find_children("*", "MeshInstance3D", true, false).size()
		w.inspect_motion(0.42)   # mid-flourish (0.5 lands the karambit on a full turn)
		var moved := false
		if w._spin != null and not w._spin.transform.is_equal_approx(Transform3D.IDENTITY):
			moved = true
		for h in w._handles:
			if h != null and absf(h.rotation.x) > 0.1:
				moved = true
		w.inspect_motion(-1.0)
		var reset: bool = w._spin.transform.is_equal_approx(Transform3D.IDENTITY)
		check(meshes >= 6 and moved and reset, "%s builds (%d parts) and its inspect moves, then resets" % [id, meshes])
		w.queue_free()

	var keep: String = Loadout.knife
	Loadout.cycle_knife(1)
	var picked: String = Loadout.knife
	Loadout.save()
	Loadout._loaded = false
	Loadout.ensure()
	check(Loadout.knife == picked and picked != keep, "knife choice is saved (%s)" % picked)
	Loadout.knife = keep
	Loadout.save()
	print("KNIFE: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
