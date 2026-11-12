extends SceneTree
## Juggernaut boss: spawns on boss waves, slams close targets, charges distant
## ones, is dazed by walls, enrages at half health and pays out on death.
##   godot --headless --path . -s res://tests/boss_test.gd
const Main = preload("res://scripts/main.gd")
const Types = preload("res://scripts/characters/zombie_types.gd")
const Layers = preload("res://scripts/core/layers.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n: await physics_frame

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var p = main.player
	var dir = main.director
	p.max_health = 100000.0
	p.health = 100000.0
	dir.timer = 999.0

	check(Types.is_boss_wave(5) and Types.is_boss_wave(10) and not Types.is_boss_wave(4), "boss waves are every 5th wave")
	var s5: Dictionary = Types.stats("boss", 5)
	var s10: Dictionary = Types.stats("boss", 10)
	print("  boss hp wave 5: %d, wave 10: %d" % [s5.hp, s10.hp])
	check(s5.hp > 1000.0 and s10.hp > s5.hp, "boss health is large and scales")
	var rolled_boss := false
	for i in 2000:
		if Types.pick(5 + i % 20, randf()) == "boss":
			rolled_boss = true
	check(not rolled_boss, "pick() never rolls a boss")

	# boss wave: the wave cannot end before the boss has spawned and died
	dir.wave = 4
	dir._begin_wave()
	check(dir._boss_pending, "wave 5 queues the boss")
	check(dir.remaining() == dir.to_spawn + 1, "remaining() counts the pending boss")
	dir.to_spawn = 0
	dir.timer = 999.0
	await frames(3)
	dir._spawn_cd = 0.0
	for e in main.enemies: if not e.is_dead: e.die(Vector3.FORWARD)
	# force the boss in directly and park it in the open near the player
	dir._boss_pending = false
	dir.active = false   # freeze the director while we drive the boss by hand
	check(dir._spawn_one("boss"), "boss spawns")
	var b = main.enemies[main.enemies.size() - 1]
	check(b.kind == "boss" and b.is_in_group("bosses"), "spawned zombie is the boss")
	check(b.rig.scale.x > 1.5 and b.head_height() > 2.3, "boss is big with a raised head hitbox (head %.2f m)" % b.head_height())
	var start_hp: float = b.max_health
	for e in main.enemies: if e != b and not e.is_dead: e.die(Vector3.FORWARD)

	# --- slam: target 2.5 m away
	b._slam_cd = 0.0
	b._charge_cd = 99.0
	b.global_position = p.global_position + Vector3(0, 0, -2.5)
	await frames(2)
	var hp0: float = p.health
	var p0: Vector3 = p.global_position
	await frames(int((Types.BOSS_SLAM_WINDUP + 0.4) * Engine.physics_ticks_per_second))
	print("  slam: player lost %.1f hp, pushed %.2f m" % [hp0 - p.health, p.global_position.distance_to(p0)])
	check(p.health < hp0, "slam damages the player")
	check(p.global_position.distance_to(p0) > 0.5, "slam knocks the player back")

	# --- charge: target 12 m away in the open
	b._slam_cd = 99.0
	b._charge_cd = 0.0
	b.global_position = p.global_position + Vector3(0, 0, -12.0)
	b.reset_physics_interpolation()
	await frames(2)
	check(b._charge_wind > 0.0, "boss winds up a charge at range")
	var c0: Vector3 = b.global_position
	hp0 = p.health
	await frames(int((Types.BOSS_CHARGE_WINDUP + Types.BOSS_CHARGE_TIME + 0.1) * Engine.physics_ticks_per_second))
	print("  charge: boss moved %.2f m, player lost %.1f hp" % [b.global_position.distance_to(c0), hp0 - p.health])
	check(b.global_position.distance_to(c0) > 5.0, "charge covers ground fast")
	check(p.health < hp0, "a charge that connects hurts the player")

	# --- wall: charge straight into a block placed between them
	await frames(Engine.physics_ticks_per_second * 3 / 2)
	b._charge_cd = 0.0
	b._slam_cd = 99.0
	b.daze = 0.0
	b.global_position = p.global_position + Vector3(0, 0, -14.0)
	b.reset_physics_interpolation()
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var ws := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.6)
	ws.shape = box
	wall.add_child(ws)
	main.add_child(wall)
	wall.global_position = p.global_position + Vector3(0, 2, -8.0)
	await frames(2)
	# the wall hides the player, so aim the charge by hand
	b._charge_wind = 0.0
	b._charge_dir = Vector3(0, 0, 1)
	b._charge_t = Types.BOSS_CHARGE_TIME
	await frames(Engine.physics_ticks_per_second * 3 / 2)
	check(b.daze > 0.0, "charging into a wall dazes the boss")
	var hpd: float = b.health
	b.apply_damage(100.0, b.global_position + Vector3.UP * 1.5, Vector3.FORWARD, p)
	print("  dazed hit took %.1f (x%.1f)" % [hpd - b.health, (hpd - b.health) / 100.0])
	check(hpd - b.health > 120.0, "dazed boss takes extra damage")
	wall.queue_free()

	# --- enrage and death
	b.apply_damage(b.health - start_hp * 0.45, b.global_position + Vector3.UP * 1.5, Vector3.FORWARD, p)
	check(b.enraged, "boss enrages below half health")
	dir._update_boss_frac()
	check(dir.boss_frac > 0.0 and dir.boss_frac < 0.5, "HUD boss fraction tracks health (%.2f)" % dir.boss_frac)
	var score0: int = dir.score
	b.apply_damage(99999.0, b.global_position + Vector3.UP * 1.5, Vector3.FORWARD, p)
	await frames(2)
	dir._update_boss_frac()
	check(b.is_dead, "boss dies")
	check(dir.score >= score0 + Types.BOSS_SCORE, "boss kill pays the bonus score")
	check(dir.boss_frac < 0.0, "boss bar hides after the kill")
	await create_timer(1.2, true, false, true).timeout
	print("BOSS: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
