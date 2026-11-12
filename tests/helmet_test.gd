extends SceneTree
## Real hitscan shots at helmeted heads: a normal round knocks the helmet off
## (a debris body appears, the target survives); a sniper round kills through it.
const Zombie = preload("res://scripts/characters/zombie.gd")
const Player = preload("res://scripts/characters/player.gd")

class Target extends Node3D:
	var is_dead := false
	var team := 0

var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
	print(("  ok   " if ok else "  FAIL ") + label)


func _initialize() -> void:
	call_deferred("run")


func _flying_helmets(scene: Node) -> int:
	var n := 0
	for ch in scene.get_children():
		if ch is RigidBody3D and ch.find_child("Helmet", true, false) != null:
			n += 1
	return n


func _shoot(shooter, weapon_id: String, z) -> Dictionary:
	shooter.set_loadout([[weapon_id, {}]])
	var w = shooter.current_weapon()
	await physics_frame
	var head: Vector3 = z.global_position + Vector3(0, z.head_height() - 0.02, 0)
	var origin: Vector3 = head + Vector3(0, 0, 4.0)
	return w.fire(shooter, origin, head, 0.0)


func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var target := Target.new()
	scene.add_child(target)
	target.position = Vector3(0, 0, 10)
	var shooter := Player.new()
	scene.add_child(shooter)
	shooter.position = Vector3(5, 0, 5)
	shooter.setup_player(0.0, [["m4a1", {}]], false, "")
	shooter.set_physics_process(false)

	var z := Zombie.new()
	scene.add_child(z)
	z.init_zombie(target, "armored", 100.0, 0.0, 10.0, 0)
	z.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(z.helmet_on, "armored zombie spawns with a helmet")
	var res: Dictionary = await _shoot(shooter, "m4a1", z)
	check(res.hit == z, "M4 shot hits the zombie")
	check(not z.helmet_on, "M4 headshot knocks the helmet off")
	check(not z.is_dead and z.health > 90.0, "helmet saved it (hp %.1f)" % z.health)
	check(_flying_helmets(scene) == 1, "helmet flies off as debris")
	check(z.rig.helmet_node == null and z.rig.head.find_child("Helmet", true, false) == null, "helmet gone from the head")
	res = await _shoot(shooter, "m4a1", z)
	check(res.headshot, "second shot is a real headshot")

	var z2 := Zombie.new()
	scene.add_child(z2)
	z2.position = Vector3(3, 0, 0)
	z2.init_zombie(target, "armored", 100.0, 0.0, 10.0, 0)
	z2.set_physics_process(false)
	await physics_frame
	await physics_frame
	res = await _shoot(shooter, "awp", z2)
	check(z2.is_dead, "AWP headshot kills through the helmet")
	check(not z2.helmet_on and _flying_helmets(scene) == 2, "pierced helmet still flies off")
	print("HELMET: failures=", failures)
	quit(0 if failures == 0 else 1)
