extends SceneTree
## Headless Zombie Survival test: invulnerable bot fights waves; also measures
## first-person camera bob while walking.
##   godot --headless --path . -s res://tests/zombie_test.gd
var main
var f := 0
var eye_min := 99.0
var eye_max := -99.0
var head_min := 99.0
var head_max := -99.0
var last_wave := 0

func _initialize() -> void:
	load("res://scripts/main.gd").saved_mode = "zombie"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _physics_process(_d: float) -> bool:
	f += 1
	var p = main.player
	if f == 2:
		main.hud._deploy()
		p.set_first_person(true)
		Input.action_press("move_forward")
	if f > 60 and f < 240:
		var ey: float = p.rig.fp_eye.origin.y
		var hy: float = p.rig.head.global_position.y
		eye_min = minf(eye_min, ey); eye_max = maxf(eye_max, ey)
		head_min = minf(head_min, hy); head_max = maxf(head_max, hy)
	if f == 240:
		Input.action_release("move_forward")
		print("[bob] fp eye y range=%.3f m   (raw head y range=%.3f m)" % [eye_max - eye_min, head_max - head_min])
		p.set_first_person(false)
		p.global_position = Vector3(0, 0, -3)
	if f > 240:
		p.health = 100.0
		var best = null
		var bd := 25.0
		for e in main.enemies:
			if is_instance_valid(e) and not e.is_dead:
				var d: float = e.global_position.distance_to(p.global_position)
				if d < bd:
					bd = d
					best = e
		if best != null:
			var t: Vector3 = best.global_position + Vector3(0, 1.6, 0)
			p.aim_point = t
			p.aim_yaw = atan2(-(t.x - p.global_position.x), -(t.z - p.global_position.z))
			if p.current_weapon().ammo <= 0:
				p.start_reload()
			else:
				p.try_fire(t)
		var dirn = main.director
		if dirn.wave != last_wave:
			last_wave = dirn.wave
			print("[wave] started wave %d  t=%.0fs  to_spawn=%d" % [dirn.wave, f / 60.0, dirn.to_spawn])
		if f % 600 == 0:
			var kinds := {}
			for e in main.enemies:
				if is_instance_valid(e) and not e.is_dead:
					kinds[e.kind] = kinds.get(e.kind, 0) + 1
			print("[stat] t=%.0fs wave=%d active=%s alive=%d remaining=%d kills=%d score=%d reserve=%d kinds=%s" % [f / 60.0, dirn.wave, dirn.active, dirn.alive(), dirn.remaining(), dirn.kills, dirn.score, p.current_weapon().reserve, kinds])
	if f == 6000:
		p.health = 0.0
		p.die(Vector3.FORWARD)
	if f == 6060:
		print("[end] game_over=", main.game_over, " best_wave=", main.director.best_wave, " score=", main.director.score)
		return true
	return false
