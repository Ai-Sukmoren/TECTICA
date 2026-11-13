extends SceneTree
## Zombie hitboxes follow the body: shots beside the body miss (and fly on
## to whatever is behind), the visible head is the headshot zone, and empty
## space where a standing head would be is not.
##   godot --headless --path . -s res://tests/zombie_hitbox_test.gd
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

func zombie(main, pos: Vector3, kind: String = "walker") -> Node:
	main.director._spawn_one(kind)
	var z = main.enemies[main.enemies.size() - 1]
	z.set_physics_process(false)
	z.global_position = pos
	z.aim_yaw = 0.0          # faces -z, toward the shooter
	z.max_health = 100000.0
	z.health = 100000.0
	z.reset_physics_interpolation()
	return z

## Fires the player's rifle from `from` at `at` with no spread.
func shoot(p, from: Vector3, at: Vector3) -> Dictionary:
	var w = p.current_weapon()
	w.cooldown = 0.0
	w.ammo = 30
	w.bloom = 0.0
	return w.fire(p, from, at, 0.0)

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
	var z = zombie(main, Vector3(0, 0.05, 34))
	await frames(30)   # let the rig settle into its lurching pose
	var from := Vector3(0, 1.3, 40)
	var hc: Vector3 = z._head_center()
	var chest: Vector3 = z.rig.chest.global_position
	print("    head centre y %.2f (standing-head rule threshold y %.2f)" % [hc.y - z.global_position.y, z.head_height() - 0.14])

	# 1. between the knees: inside the old movement capsule, but no body there
	var gap := Vector3(z.global_position.x, z.global_position.y + 0.32, z.global_position.z)
	var legs := Vector3.ZERO
	for sh in z.hit_shapes():
		if String(sh[0]) in ["thigh", "shin"]:
			legs += (sh[1] as Vector3) + (sh[2] as Vector3)
	gap.x = legs.x / 8.0
	var part: Dictionary = z.hit_part(Vector3(gap.x, gap.y, 40), Vector3(0, 0, -1))
	print("    shot between the knees touches: ", part)
	var r := shoot(p, Vector3(gap.x, gap.y, 40), gap)
	check(part.is_empty() and r.hit != z, "a shot between the knees misses (it used to hit the capsule)")
	# 1b. a reaching hand beyond the old 32 cm capsule now counts
	var hand: Vector3 = z.rig.hands[0].global_position
	var reach: float = Vector2(hand.x - z.global_position.x, hand.z - z.global_position.z).length()
	r = shoot(p, Vector3(hand.x, hand.y, 40), hand)
	print("    hand is %.2f m from the body axis" % reach)
	check(r.hit == z, "a shot at the reaching hand hits")
	# 2. the visible head
	r = shoot(p, from, hc)
	check(r.hit == z and r.headshot, "a shot at the visible head is a headshot")
	# 3. where a standing head would be, but this one is hunched forward
	var ghost := Vector3(hc.x, z.global_position.y + z.head_height() - 0.02, hc.z + 0.22)
	r = shoot(p, ghost + Vector3(6.0, 0, 0), ghost)   # sideways: never crosses the real head
	check(not (r.hit == z and r.headshot), "empty air behind the hunched head is not a headshot")
	# 4. centre mass
	r = shoot(p, from, chest)
	check(r.hit == z and not r.headshot, "a chest shot is a body hit")
	# 5. a shot between the first zombie's knees flies on and hits the one behind
	var z2 = zombie(main, Vector3(gap.x, 0.05, 30))
	await frames(10)
	r = shoot(p, Vector3(gap.x, gap.y + 0.5, 40), Vector3(gap.x, gap.y + 0.5, 30))
	var r2 = shoot(p, Vector3(gap.x, gap.y, 40), Vector3(gap.x, gap.y, 29))
	print("    shot between the first one's knees hit: ", r2.hit.name if r2.hit != null else "nothing")
	check(r2.hit == z2, "a shot through the gap flies on to the zombie behind")

	print("HITBOX: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
