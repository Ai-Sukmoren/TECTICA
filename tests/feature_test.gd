extends SceneTree
## Headless test for grenades (player + AI), footstep hearing, regen, settings, grading.
##   godot --headless --path . -s res://tests/feature_test.gd
const Settings = preload("res://scripts/core/settings.gd")
var main
var f := 0
var target
var enemy_thrown := false
func _initialize() -> void:
	load("res://scripts/main.gd").saved_mode = "operation"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
func _physics_process(_d: float) -> bool:
	f += 1
	var p = main.player
	if f == 2:
		main.hud._deploy()
	if f == 5:
		# 1) player grenade onto a guard standing 8 m away in the open
		target = main.enemies[0]
		for e in main.enemies:
			if e != target:
				e.process_mode = Node.PROCESS_MODE_DISABLED
		target.process_mode = Node.PROCESS_MODE_DISABLED
		target.global_position = Vector3(0, 0, 10)
		p.global_position = Vector3(0, 0, 18)
		print("[nade] grenades=", p.grenades, " thrown=", p.throw_grenade(Vector3(0, 0, 10)))
	if f == 5 + 60 * 4:
		print("[nade] target hp=%.0f dead=%s" % [target.health, target.is_dead])
		print("[nade] player hp=%.0f (8 m away, should be unhurt)" % p.health)
		# 2) footsteps: sprinting past a patrolling guard makes him suspicious
		var g = main.enemies[5]
		g.process_mode = Node.PROCESS_MODE_INHERIT
		p.global_position = g.global_position + Vector3(7, 0, 0)
		g.aim_yaw = 0.0
		p.sprinting = true
		p._on_footstep(p.global_position, 1.0)
		print("[steps] guard state after sprint footstep at 7 m: ", g.state, " (1 = SUSPICIOUS)")
		p.sprinting = false
		g.process_mode = Node.PROCESS_MODE_DISABLED
		# 3) regen
		p.health = 40.0
		p.since_damage = 0.0
	if f == 5 + 60 * 4 + 60 * 9:
		print("[regen] hp after 9 s =%.0f (starts after 5 s at 7/s)" % p.health)
		# 4) enemy grenade AI: hidden player recently seen within range
		var e = main.enemies[3]
		e.process_mode = Node.PROCESS_MODE_INHERIT
		p.global_position = e.global_position + Vector3(0, 0, 10)
		e._enter_combat(false)
		e.sees_player = false
		e.time_since_seen = 2.0
		e.last_known = p.global_position
		e._squad_grenade_t = -100.0
		var tries := 0
		while not enemy_thrown and tries < 60:
			tries += 1
			e.throwing = 0.0
			e.reload_timer = 0.0
			e._try_grenade()
			enemy_thrown = e.grenades == 0
		print("[ai-nade] enemy threw grenade: ", enemy_thrown, " after ", tries, " checks")
	if f == 5 + 60 * 4 + 60 * 9 + 60 * 4:
		print("[ai-nade] player hp after enemy frag landed nearby: %.0f" % p.health)
		# 5) settings round trip
		var orig_sens = Settings.v.sensitivity
		Settings.v.sensitivity = 1.7
		Settings.save()
		Settings.v.sensitivity = 1.0
		Settings._loaded = false
		Settings.ensure()
		print("[settings] sensitivity persisted: ", Settings.v.sensitivity)
		Settings.v.sensitivity = orig_sens
		Settings.save()
		# 6) grade
		main.elapsed = 200.0
		p.shots_fired = 40
		p.shots_hit = 30
		main.headshot_kills = 4
		main.damage_taken = 60.0
		main._grade_mission()
		print("[grade] score=", main.mission_score, " grade=", main.grade)
		return true
	return false
