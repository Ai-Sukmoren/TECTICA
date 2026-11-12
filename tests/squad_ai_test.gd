extends SceneTree
## Squad tactics: with the player hidden, one guard flanks (and only one),
## squadmates lay down suppressive fire, and a badly hurt guard falls back.
##   godot --headless --path . -s res://tests/squad_ai_test.gd
const Main = preload("res://scripts/main.gd")
const Enemy = preload("res://scripts/characters/enemy.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	# a squad of 4 near each other, all in combat, player last seen 3 s ago
	var squad: Array = []
	for e in main.enemies:
		if e is Enemy and not e.is_dead:
			squad.append(e)
		if squad.size() >= 4:
			break
	var base: Vector3 = squad[0].global_position
	var threat: Vector3 = base + Vector3(14, 0, 0)
	threat = NavigationServer3D.map_get_closest_point(main.get_world_3d().navigation_map, threat)
	p.global_position = threat + Vector3(0, 0.2, 0)
	for i in squad.size():
		var e = squad[i]
		e.global_position = NavigationServer3D.map_get_closest_point(main.get_world_3d().navigation_map, base + Vector3(0, 0, i * 2.0))
		e.state = Enemy.State.COMBAT
		e.last_known = threat
		e.player = p
	await physics_frame
	# hide the player from everyone for the test
	var flankers := 0
	var started_at := {}
	var fired_while_hidden := 0
	for f in 900:   # ~7.5 s at 120 Hz
		for e in squad:
			if e.is_dead:
				continue
			e.sees_player = false
			e.time_since_seen = 3.0
			e.last_known = threat
			e.set("_perceive_timer", 999.0)
		await physics_frame
		if f % 120 == 0:
			var st := []
			for e in squad:
				st.append("%s/%s/fc%.1f/hp%d" % [Enemy.State.keys()[e.state], Enemy.Phase.keys()[e.phase], e._flank_check, int(e.health)])
			print("  t=%d %s" % [f / 120, st])
		var n := 0
		for e in squad:
			if e.phase == Enemy.Phase.FLANK:
				n += 1
				if not started_at.has(e):
					started_at[e] = e.global_position
		flankers = maxi(flankers, n)
		if Enemy._flanker != null:
			for e in squad:
				if e != Enemy._flanker and e._burst_left > 0:
					fired_while_hidden += 1
	check(flankers == 1, "exactly one squad member flanks (max at once = %d)" % flankers)
	var moved := 0.0
	for e in started_at:
		moved = maxf(moved, e.global_position.distance_to(started_at[e]))
	print("  flanker ran %.1f m" % moved)
	check(moved > 3.0, "the flanker actually moves around")
	check(fired_while_hidden > 0, "squadmates lay down suppressive fire")
	# fall back when badly hurt
	var w = squad[squad.size() - 1]
	if Enemy._flanker == w:
		w = squad[0]
	w.health = w.max_health * 0.4
	var before = w.cover
	w.apply_damage(w.max_health * 0.1, w.global_position + Vector3.UP, Vector3.LEFT, p)
	check(w._fell_back, "a badly hurt guard decides to fall back")
	print("SQUAD: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
