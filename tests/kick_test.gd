extends SceneTree
## Dropkick: a lethal kick must launch the body; a non-lethal one shoves it
## and plays the slow-mo, which must return to normal speed.
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
	print("KICK: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
