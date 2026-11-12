extends SceneTree
## M84 flashbang: a burst in front of a target blinds it, a far one does not,
## the player gets the white-out, and throwing uses up a flashbang.
##   godot --headless --path . -s res://tests/flashbang_test.gd
const Main = preload("res://scripts/main.gd")
const Grenade = preload("res://scripts/weapons/grenade.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func burst(main: Node, pos: Vector3) -> void:
	var g = Grenade.new()
	g.kind = "flash"
	main.add_child(g)
	g.global_position = pos
	g.freeze = true
	g.explode()

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
	var near = main.enemies[0]
	var far = main.enemies[1]
	near.global_position = p.global_position + Vector3(30, 0, 0)
	far.global_position = p.global_position + Vector3(30, 0, 40)
	await physics_frame
	near.aim_yaw = 0.0   # looking toward -Z
	burst(main, near.global_position + Vector3(0, 1.0, -2.0))
	await physics_frame
	print("  near blind_t %.2f, far blind_t %.2f" % [near.blind_t, far.blind_t])
	check(near.blind_t > 1.0, "close burst in view blinds the target")
	check(far.blind_t <= 0.0, "burst 40 m away does nothing")
	p.aim_yaw = 0.0
	burst(main, p.global_position + Vector3(0, 1.0, -2.5))
	await physics_frame
	check(p.blind_t > 1.0, "player is blinded by a burst in front")
	var before: int = p.flashbangs
	p.flashbangs = maxi(before, 1)
	before = p.flashbangs
	Input.action_press("flashbang")
	for i in 3: await physics_frame
	Input.action_release("flashbang")
	for i in 3: await physics_frame
	print("  flashbangs %d -> %d" % [before, p.flashbangs])
	check(p.flashbangs == before - 1, "throwing uses one flashbang")
	print("FLASHBANG: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
