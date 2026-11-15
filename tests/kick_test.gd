extends SceneTree
## Dropkick: a lethal kick must launch the body; a non-lethal one shoves it
## and plays the slow-mo, which must return to normal speed. Flying kick (V in
## a running jump): needs the jump speed, hits for double damage and its
## shockwave shoves a second infected standing beside the target.
##   godot --headless --path . -s res://tests/kick_test.gd
const Main = preload("res://scripts/main.gd")
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
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 999.0
	for k in 2:
		main.director._spawn_one()
	await physics_frame
	var a = main.enemies[0]
	var b = main.enemies[1]
	for z in [a, b]:
		z.set("player", null)
	a.global_position = p.global_position + Vector3(0, 0, -1.6)
	b.global_position = p.global_position + Vector3(6, 0, 6)
	a.health = 10.0       # this kick kills
	b.health = 500.0
	await physics_frame
	var start: Vector3 = a.global_position
	a.take_kick(45.0, a.global_position + Vector3.UP, Vector3.FORWARD, p, Vector3.FORWARD * 14.5 + Vector3.UP * 4.2)
	check(a.is_dead, "lethal kick kills")
	for i in 30: await physics_frame
	var flown: float = Vector2(a.global_position.x - start.x, a.global_position.z - start.z).length()
	print("  body flew %.2f m" % flown)
	check(flown > 1.5, "killed body is launched by the kick")
	var bstart: Vector3 = b.global_position
	b.take_kick(45.0, b.global_position + Vector3.UP, Vector3.RIGHT, p, Vector3.RIGHT * 14.5 + Vector3.UP * 4.2)
	for i in 20: await physics_frame
	check(not b.is_dead and b.global_position.distance_to(bstart) > 1.0, "non-lethal kick shoves the target")
	main.hud.slowmo(0.3, 0.2)
	check(is_equal_approx(Engine.time_scale, 0.3), "slow-mo engages")
	await create_timer(0.6, true, false, true).timeout
	check(is_equal_approx(Engine.time_scale, 1.0), "slow-mo returns to normal speed")
	await _flying_kick(main)
	print("KICK: failures=%d" % failures)
	quit(1 if failures > 0 else 0)


func _flying_kick(main) -> void:
	var p = main.player
	Engine.time_scale = 1.0
	for e in main.enemies:
		if is_instance_valid(e):
			e.queue_free()
	main.enemies.clear()
	await physics_frame
	for k in 2:
		main.director._spawn_one("walker")
	await physics_frame
	var tgt = main.enemies[0]
	var side = main.enemies[1]
	for z in [tgt, side]:
		z.set("player", null)
		z.health = 500.0
	# running jump towards -z, the target ahead and a second infected beside it
	p.global_position = Vector3(2.0, 1.2, 30.0)
	tgt.global_position = Vector3(2.0, 0.05, 28.3)
	side.global_position = Vector3(3.6, 0.05, 28.0)
	await physics_frame
	var side_start: Vector3 = side.global_position
	p.velocity = Vector3(0, 1.0, -1.0)
	p.air_time = 0.2
	check(Vector2(p.velocity.x, p.velocity.z).length() < p.AIR_KICK_MIN_SPEED, "a standing hop is too slow for a flying kick")
	p.velocity = Vector3(0, 2.0, -6.5)
	p._start_kick(Vector3(0, 0, -1), true)
	check(p.kicking and p.flying_kick and p.kick_damage == p.AIR_KICK_DAMAGE, "running jump + kick starts a flying kick")
	var hp0: float = tgt.health
	for i in 40:
		await physics_frame
		if not p.kicking:
			break
	check(is_equal_approx(hp0 - tgt.health, p.AIR_KICK_DAMAGE) or tgt.is_dead, "flying kick deals %d damage (dealt %.0f)" % [int(p.AIR_KICK_DAMAGE), hp0 - tgt.health])
	check(p.AIR_KICK_DAMAGE >= p.KICK_DAMAGE * 2.0, "flying kick hits at least twice as hard as the dropkick")
	await create_timer(0.7, true, false, true).timeout   # past the slow-mo
	for i in 20: await physics_frame
	var moved: float = Vector2(side.global_position.x - side_start.x, side.global_position.z - side_start.z).length()
	print("  bystander shoved %.2f m" % moved)
	check(moved > 0.5 and not side.is_dead and side.health == 500.0, "shockwave shoves the infected beside the target without damage")
	Engine.time_scale = 1.0
