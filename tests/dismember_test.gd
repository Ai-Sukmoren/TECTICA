extends SceneTree
## Dismemberment: shooting a limb enough takes it off while the zombie lives;
## a lost leg drops it to a crawl; severed parts stop taking hits.
##   godot --headless --path . -s res://tests/dismember_test.gd
const Main = preload("res://scripts/main.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shoot(p, from: Vector3, at: Vector3) -> Dictionary:
	var w = p.current_weapon()
	w.cooldown = 0.0
	w.ammo = 30
	w.bloom = 0.0
	return w.fire(p, from, at, 0.0)

func debris_count(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is RigidBody3D:
			n += 1
	return n

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
	main.director.timer = 9999.0
	p.set_loadout([["m4a1", {"optic": "iron"}], ["knife_combat", {}]])
	p.global_position = Vector3(0, 0.05, 40)
	main.director._spawn_one("walker")
	var z = main.enemies[main.enemies.size() - 1]
	z.set_physics_process(false)
	z.global_position = Vector3(0, 0.05, 34)
	z.aim_yaw = 0.0
	z.max_health = 300.0
	z.health = 300.0
	z.reset_physics_interpolation()
	await frames(30)
	var debris0 := debris_count(main)

	# --- an arm: shoot the forearm until it comes off
	var shots := 0
	while not z.severed.has("arm0") and shots < 20:
		var fa: Vector3 = (z.rig.elbows[0].global_position + z.rig.hands[0].global_position) * 0.5
		shoot(p, Vector3(fa.x, fa.y, 40), fa)
		shots += 1
		await frames(2)
	print("    forearm shots to sever: %d, health left %.0f" % [shots, z.health])
	check(z.severed.get("arm0", "") == "lower", "the forearm comes off at the elbow")
	check(not z.is_dead, "the zombie is still alive without it")
	var names: Array = z.hit_shapes().map(func(s): return String(s[0]) + str(s[4]) if s.size() > 4 else String(s[0]))
	check(not ("forearm0" in names) and ("upper_arm0" in names), "the lost forearm no longer takes hits, the upper arm still does")
	check(debris_count(main) > debris0, "the forearm drops as a physics piece")

	# --- a leg: shoot the thigh until it comes off
	z.health = 300.0
	var speed0: float = z.move_speed
	shots = 0
	while not z.severed.has("leg1") and shots < 25:
		var th: Vector3 = (z.rig.thighs[1].global_position + z.rig.shins[1].global_position) * 0.5
		shoot(p, Vector3(th.x, th.y, 40), th)
		shots += 1
		await frames(2)
	print("    thigh shots to sever: %d" % shots)
	check(z.severed.get("leg1", "") == "upper", "the leg comes off at the hip")
	check(not z.is_dead and z.rig.zombie_kind == "crawler" and z.crouching, "with a leg gone it goes down and crawls")
	check(z.move_speed < speed0 + 0.001 and z.move_speed <= 1.15, "crawling is slower")

	# --- bosses keep their limbs
	main.director._spawn_one("boss")
	var b = main.enemies[main.enemies.size() - 1]
	b.set_physics_process(false)
	b.global_position = Vector3(3, 0.05, 30)
	await frames(10)
	for i in 6:
		var arm: Vector3 = (b.rig.elbows[0].global_position + b.rig.hands[0].global_position) * 0.5
		b.health = b.max_health
		shoot(p, Vector3(arm.x, arm.y, 40), arm)
	check(b.severed.is_empty(), "bosses can't be dismembered")

	print("DISMEMBER: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
