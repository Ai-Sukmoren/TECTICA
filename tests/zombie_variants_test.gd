extends SceneTree
const Zombie = preload("res://scripts/characters/zombie.gd")
const Types = preload("res://scripts/characters/zombie_types.gd")
class Target extends Node3D:
	var is_dead := false
	var team := 0
var scene: Node3D
var target: Target
var failures := 0
func _initialize():
	call_deferred("run")
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func spawn(kind: String):
	var z := Zombie.new()
	scene.add_child(z)
	z.init_zombie(target, kind, 100.0, 2.0, 10.0, 0)
	z.set_physics_process(false)
	z.rig.set_process(false)
	return z
func run():
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	target = Target.new()
	scene.add_child(target)
	target.position = Vector3(0,0,-8)
	for wave in range(1, 9):
		var seen := {}
		for i in 1000:
			var kind := Types.pick(wave, i / 1000.0)
			seen[kind] = true
			check(wave >= int(Types.UNLOCKS.get(kind, 1)), "Premature unlock")
		if wave >= 6: check(seen.size() == 6, "Missing type in late waves")
	var crawler = spawn("crawler")
	check(crawler.crouching and crawler._shape.height < crawler.STAND_HEIGHT, "Crawler collision height")
	var armored = spawn("armored")
	armored.apply_damage(20, Vector3(0,1.1,0), Vector3.BACK, target)
	check(is_equal_approx(armored.health,92), "Front armor failed")
	armored.apply_damage(20, Vector3(0,1.1,0), Vector3.FORWARD, target)
	check(is_equal_approx(armored.health,72), "Back weak point failed")
	armored.apply_damage(10, Vector3(0,1.8,0), Vector3.BACK, target)
	check(is_equal_approx(armored.health,47), "Headshot armor bypass failed")
	var rage = spawn("berserker")
	rage.apply_damage(60, Vector3(0,1.1,0), Vector3.BACK, target)
	check(rage.enraged, "Rage threshold failed")
	var puppet = spawn("berserker")
	puppet.puppet = true
	puppet.net_target(Vector3.ZERO,Vector3.ZERO,0.0,8,0,0.0,0.0)
	check(puppet.enraged, "Puppet rage flag failed")
	for fps in [15,30,60,144]:
		var z = spawn("walker")
		z.rig.play_attack(0.8)
		var elapsed := 0.0
		while elapsed < 0.4 - 0.00001:
			var dt := minf(1.0 / fps, 0.4 - elapsed)
			z.rig._process(dt)
			elapsed += dt
		check(absf(z.rig.attack_t - 0.5) < 0.001, "Attack timing varies with FPS: %d" % fps)
		check(z.rig.chest.global_transform.is_finite(), "Invalid animation transform")
		z.queue_free()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 0.3)
	col.shape = box
	wall.add_child(col)
	scene.add_child(wall)
	wall.position = Vector3(0, 1, -1)
	await physics_frame
	await physics_frame
	check(not crawler._clear_melee_path(), "Melee must not pass through walls")
	print("VARIANTS + ANIMATION: failures=",failures)
	quit(0 if failures == 0 else 1)
