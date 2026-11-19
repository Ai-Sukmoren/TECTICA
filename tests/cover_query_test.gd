extends SceneTree
## Cover environmental query (level.gd find_cover / route_exposure / _squad_crowding,
## enemy.gd re-grading): routes in the open are graded down, a squad spreads out,
## a guard re-grades when the threat moves, and the query stays cheap.
##   godot --headless --path . -s res://tests/cover_query_test.gd
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
	var lvl = main.level
	var p = main.player
	p.health = 1.0e6
	var guards: Array = []
	for e in main.enemies:
		e.set_physics_process(false)
		if e is Enemy:
			guards.append(e)

	# ---------------------------------------------------------------- route exposure
	var pad: Vector3 = lvl.lz_south
	var threat := pad + Vector3(0, 0, -12)
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30, 3, 0.4)
	cs.shape = bs
	wall.add_child(cs)
	main.add_child(wall)
	wall.global_position = pad + Vector3(0, 1.5, -4)
	await frames(2)
	var g = guards[0]
	g.global_position = pad + Vector3(0, 0, 2)
	var hidden: float = lvl.route_exposure(g, pad + Vector3(8, 0, 1), threat)
	var exposed: float = lvl.route_exposure(g, pad + Vector3(0, 0, -9), threat)
	print("  route exposure: behind the wall %.2f, out in front %.2f" % [hidden, exposed])
	check(hidden < 0.15, "a route that stays behind the wall is graded hidden")
	check(exposed > 0.4, "a route out past the wall is graded exposed")
	wall.queue_free()
	await frames(2)

	# ---------------------------------------------------------------- squad spread
	# a stretch of the map with plenty of cover facing one way: the threat in front of it
	var anchor = null
	var most := 0
	for c in lvl.cover_points:
		if not c.valid:
			continue
		var n := 0
		for o in lvl.cover_points:
			if o.valid and (o.pos as Vector3).distance_to(c.pos) < 12.0 and (o.normal as Vector3).dot(c.normal) > 0.6:
				n += 1
		if n > most:
			most = n
			anchor = c
	var nrm: Vector3 = anchor.normal
	var camp: Vector3 = anchor.pos
	var t2: Vector3 = camp - nrm * 13.0
	var side := Vector3(nrm.z, 0, -nrm.x)
	var squad: Array = []
	for i in 3:
		var e = guards[i + 1]
		e.global_position = camp + nrm * 3.0 + side * (-4.0 + i * 4.0)
		squad.append(e)
	var picks: Array = []
	var fire_ok := true
	for e in squad:
		var c = lvl.find_cover(e, t2)
		if c != null:
			picks.append(c.pos)
			if not lvl.can_fire_from(c, t2):
				# blind cover is only acceptable when nothing he could fire from was in reach
				for o in lvl.cover_points:
					if o == c or not o.valid or (o.taken != null and o.taken != e):
						continue
					var d: float = (o.pos as Vector3).distance_to(e.global_position)
					if d < 16.0 and lvl.is_covered(o.pos, t2) and lvl.can_fire_from(o, t2) 							and (o.pos as Vector3).distance_to(t2) > 5.0 and (o.pos as Vector3).distance_to(t2) < 26.0:
						fire_ok = false
	check(fire_ok, "a guard only settles for blind cover when nothing he could shoot from is in reach")
	var apart := picks.size() >= 2
	for i in picks.size():
		for j in range(i + 1, picks.size()):
			print("  pick gap %.1f m" % (picks[i] as Vector3).distance_to(picks[j]))
			if (picks[i] as Vector3).distance_to(picks[j]) < 1.5:
				apart = false
	check(picks.size() >= 3 and apart, "three guards take three separate spots (%d spots)" % picks.size())
	# the spread rule itself: next to a squadmate's spot costs, far from it doesn't
	var near_cost: float = lvl._squad_crowding(guards[6], (picks[0] as Vector3) + side * 1.5, t2)
	var far_cost: float = lvl._squad_crowding(guards[6], (picks[0] as Vector3) + side * 9.0 + nrm * 4.0, t2)
	check(near_cost > far_cost + 3.0, "crowding a squadmate's spot costs more than a free one (%.1f vs %.1f)" % [near_cost, far_cost])
	for c in lvl.cover_points:
		c.taken = null

	# ---------------------------------------------------------------- live re-grading
	g = guards[4]
	g.set_physics_process(true)
	g.global_position = camp + nrm * 3.0
	g.player = p
	p.global_position = t2
	g.last_known = p.global_position
	g.state = Enemy.State.COMBAT
	g.sees_player = false
	g.time_since_seen = 1.0
	await frames(120)
	var first = g.cover
	var first_threat: Vector3 = g._cover_threat
	print("  fight: cover=%s threat_graded=%s player=%s state=%d phase=%d" % [first != null, first_threat, p.global_position, g.state, g.phase])
	check(first != null and Vector2(first_threat.x - p.global_position.x, first_threat.z - p.global_position.z).length() < 1.0, "in a fight the guard takes graded cover")
	# the threat circles round to his flank
	p.global_position = t2 + side * 14.0
	g.last_known = p.global_position
	for i in 160:
		g.last_known = p.global_position
		g.time_since_seen = 1.0
		await physics_frame
	check(Vector2(g._cover_threat.x - p.global_position.x, g._cover_threat.z - p.global_position.z).length() < 1.0, "when the threat moves he grades the ground again")
	check(g.cover == null or lvl.is_cover_good(g.cover, p.global_position), "and the spot he holds still covers him from the new angle")
	g.set_physics_process(false)

	# ---------------------------------------------------------------- cost
	var t0 := Time.get_ticks_usec()
	for i in 20:
		var c = lvl.find_cover(guards[i % guards.size()], t2)
		if c != null:
			c.taken = null
	var ms := float(Time.get_ticks_usec() - t0) / 20.0 / 1000.0
	print("  one cover query with route checks: %.2f ms" % ms)
	check(ms < 4.0, "a cover query stays cheap")

	print("COVER: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
