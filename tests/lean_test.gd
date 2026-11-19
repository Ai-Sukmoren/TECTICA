extends SceneTree
## Guards lean out round cover to peek (enemy.gd _choose_lean_side / _lean /
## hit_part): they pick a clear side, the eye moves with the lean, and the
## leaned-out head can be shot while the pillar still stops rounds aimed at it.
##   godot --headless --path . -s res://tests/lean_test.gd
const Main = preload("res://scripts/main.gd")
const Enemy = preload("res://scripts/characters/enemy.gd")
const Layers = preload("res://scripts/core/layers.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	Main.quick_restart = true
	Main._new_player_checked = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90:
		await process_frame
	var main = current_scene
	var p = main.player
	p.health = 1.0e6
	var g = null
	for e in main.enemies:
		e.set_physics_process(false)
		e.global_position = Vector3(400, 0, -400)
		if g == null and e is Enemy:
			g = e
	var pad: Vector3 = main.level.lz_south
	# a tall pillar between the guard and the threat
	var pillar := StaticBody3D.new()
	pillar.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.55, 3.2, 0.55)   # about a pine trunk
	cs.shape = bs
	pillar.add_child(cs)
	main.add_child(pillar)
	pillar.global_position = pad + Vector3(0, 1.6, -1.2)
	var threat := pad + Vector3(0, 0, -14)
	p.global_position = threat
	g.global_position = pad
	g.aim_yaw = 0.0
	g.player = p
	g.cover = null
	g.reset_physics_interpolation()
	await frames(3)
	check(not g._can_see(p), "behind the pillar he can't see the threat")
	var side: float = g._choose_lean_side(threat)
	check(side != 0.0, "round a pillar he finds a side to lean out from (%d)" % side)
	for i in 40:
		g._lean(side)
		await physics_frame
	check(absf(g.rig.lean_amt) > 0.8 and g._peek_off.length() > 0.35, "he leans out (%.2f m)" % g._peek_off.length())
	check(g._can_see(p), "leaning, he sees past the pillar")
	# the operator fires at the leaned-out head, then at the middle of the pillar
	var head: Vector3 = g.global_position + g._peek_off + Vector3(0, g.head_height() - 0.05, 0)
	var origin: Vector3 = threat + Vector3(0, 1.5, 0)
	var w = p.current_weapon()
	w.ammo = 30
	w.cooldown = 0.0
	var hp0: float = g.health
	var r: Dictionary = w.fire(p, origin, head, 0.0)
	check(r.hit == g and g.health < hp0, "a shot at the leaned-out head hits him")
	g.health = g.max_health
	w.cooldown = 0.0
	var r2: Dictionary = w.fire(p, origin, pad + Vector3(0, 1.2, 0), 0.0)
	check(r2.hit != g and g.health == g.max_health, "a shot into the pillar doesn't reach the body behind it")
	for i in 120:   # the lean eases back
		g._lean(0.0)
		await physics_frame
	check(g._peek_off == Vector3.ZERO and g._lean_zone.collision_layer == 0, "back upright: no lean, no extra hit zone")
	print("LEAN: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
