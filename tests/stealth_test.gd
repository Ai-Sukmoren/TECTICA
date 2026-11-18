extends SceneTree
## Stealth system (stealth.gd, enemy.gd awareness ladder, player.gd takedowns /
## bodies / decoys) on the Chapter 1 map, one guard or a small group at a time on
## the open landing pad, everyone else parked far away and frozen.
##   godot --headless --path . -s res://tests/stealth_test.gd
const Main = preload("res://scripts/main.gd")
const Enemy = preload("res://scripts/characters/enemy.gd")
const Stealth = preload("res://scripts/stealth/stealth.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Layers = preload("res://scripts/core/layers.gd")
var failures := 0
var main
var p
var guards: Array = []
const PAD := Vector3(0, 0, 86)   # chapter 1 landing pad: flat and open

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func step(seconds: float) -> void:
	var n := int(ceil(seconds * Engine.physics_ticks_per_second))
	for i in n:
		await physics_frame

## Every guard frozen far away; returns `n` of them reset and placed on the pad.
func stage(n: int) -> Array:
	Stealth.reset()
	for e in main.enemies:
		e.set_physics_process(false)
		e.global_position = Vector3(400, 0, -400)
	var out: Array = []
	for e in guards:
		if out.size() >= n:
			break
		if e.is_dead:
			continue
		e.set_physics_process(true)
		e.state = Enemy.State.PATROL
		e.awareness = 0.0
		e.sees_player = false
		e.time_since_seen = 99.0
		e.patrol = []
		e.grabbed = false
		e._body_target = null
		e.set("_perceive_timer", 0.0)
		out.append(e)
	return out

func place(e, pos: Vector3, facing: Vector3) -> void:
	e.global_position = pos
	e.home_pos = pos
	e.aim_yaw = atan2(-facing.x, -facing.z)
	e.home_yaw = e.aim_yaw
	e.velocity = Vector3.ZERO

func wall(at: Vector3, width: float) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 3.0, 0.4)
	cs.shape = sh
	b.add_child(cs)
	main.add_child(b)
	b.global_position = at + Vector3(0, 1.5, 0)
	return b

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90:
		await process_frame
	main = current_scene
	p = main.player
	p.health = 1.0e6
	p.max_health = 1.0e6
	main.level.night = 0.0
	for e in main.enemies:
		if e is Enemy:
			guards.append(e)
	print("guards: %d" % guards.size())

	# ---------------------------------------------------------------- 1. gradual detection
	var g = stage(1)[0]
	p.global_position = PAD
	place(g, PAD + Vector3(0, 0, -14), Vector3(0, 0, 1))
	await step(0.3)
	check(g.sees_player and g.state != Enemy.State.COMBAT and g.awareness < 0.6, "seen at 14 m: no instant detection after 0.3 s (aw %.2f)" % g.awareness)
	var states := {}
	for i in 600:
		await physics_frame
		states[int(g.state)] = true
		if g.state == Enemy.State.COMBAT:
			break
	check(states.has(Enemy.State.SUSPICIOUS) and g.state == Enemy.State.COMBAT, "suspicion builds through SUSPICIOUS before COMBAT %s" % [states.keys()])

	# ---------------------------------------------------------------- 2. exposure
	var still_crouched := 0.0
	var sprinting := 0.0
	p.velocity = Vector3.ZERO
	p.crouching = true
	still_crouched = Stealth.exposure(main.level, p)
	p.crouching = false
	p.sprinting = true
	p.velocity = Vector3(7, 0, 0)
	sprinting = Stealth.exposure(main.level, p)
	p.sprinting = false
	p.velocity = Vector3.ZERO
	check(sprinting > still_crouched * 3.0, "sprinting is far more eye-catching than holding still crouched (%.2f vs %.2f)" % [sprinting, still_crouched])
	main.level.night = 1.0
	var dark := Stealth.exposure(main.level, p)
	main.level.night = 0.0
	check(dark < Stealth.exposure(main.level, p) * 0.6, "darkness hides the operator")

	# ---------------------------------------------------------------- 3. walls block sight and muffle sound
	g = stage(1)[0]
	p.global_position = PAD
	place(g, PAD + Vector3(0, 0, -6), Vector3(0, 0, 1))
	var w := wall(PAD + Vector3(0, 0, -3), 6.0)
	await step(2.0)
	check(not g.sees_player and g.awareness == 0.0, "no detection through a wall at 6 m")
	Stealth.emit_sound(main, PAD, 5.0, "footstep", p)
	await step(0.1)
	check(g.state == Enemy.State.PATROL, "a footstep (5 m) behind a wall at 6 m is muffled away")
	w.queue_free()
	await physics_frame
	g = stage(1)[0]
	place(g, PAD + Vector3(0, 0, -4), Vector3(0, 0, -1))   # facing away
	Stealth.emit_sound(main, PAD, 5.0, "footstep", p)
	p.global_position = PAD + Vector3(40, 0, 40)   # and then gone: nothing to see when he turns
	await step(0.1)
	check(g.state == Enemy.State.SUSPICIOUS, "the same footstep in the open at 4 m makes him suspicious")
	await step(2.0)
	check(g.state == Enemy.State.INVESTIGATE, "he goes to check it out")

	# ---------------------------------------------------------------- 4. gunfire: alerted, not omniscient
	var plain: Dictionary = Data.compute("mgp7", {})
	var supp: Dictionary = Data.compute("mgp7", {"muzzle": "suppressor"})
	check(float(supp.noise_radius) < float(plain.noise_radius) * 0.5 and float(supp.noise_radius) > 0.0,
			"a suppressor cuts the noise but doesn't silence it (%.0f m vs %.0f m)" % [supp.noise_radius, plain.noise_radius])
	g = stage(1)[0]
	place(g, PAD + Vector3(0, 0, -20), Vector3(0, 0, -1))
	p.global_position = PAD
	Stealth.emit_sound(main, PAD, float(plain.noise_radius), "gunshot", p)
	await step(0.1)
	check(g.state == Enemy.State.ALERTED, "gunfire 20 m away: ALERTED, not straight into combat")
	check(g.last_known.distance_to(PAD) < 5.0 and Stealth.alert >= 1.0, "he heads for a guess near the shot and the area goes on alert")
	g = stage(1)[0]
	place(g, PAD + Vector3(0, 0, -12), Vector3(0, 0, -1))
	Stealth.emit_sound(main, PAD, float(supp.noise_radius), "suppressed", p)
	await step(0.1)
	check(g.state == Enemy.State.PATROL, "a suppressed shot is out of earshot at 12 m")
	place(g, PAD + Vector3(0, 0, -7), Vector3(0, 0, -1))
	Stealth.emit_sound(main, PAD, float(supp.noise_radius), "suppressed", p)
	p.global_position = PAD + Vector3(40, 0, 40)
	await step(0.1)
	check(g.state == Enemy.State.INVESTIGATE, "a suppressed shot 7 m away: he only goes to check it out (state %d)" % g.state)

	# ---------------------------------------------------------------- 5. decoy lures a guard off his post
	g = stage(1)[0]
	place(g, PAD + Vector3(0, 0, -6), Vector3(0, 0, -1))
	p.global_position = PAD + Vector3(0, 0, 8)
	var lure := PAD + Vector3(9, 0, -6)
	Stealth.emit_sound(main, lure, 16.0, "distraction", p)
	var d0: float = g.global_position.distance_to(lure)
	await step(5.0)
	check(g.state in [Enemy.State.SUSPICIOUS, Enemy.State.INVESTIGATE] and g.global_position.distance_to(lure) < d0 - 3.0,
			"a decoy draws him toward it (%.1f m -> %.1f m)" % [d0, g.global_position.distance_to(lure)])

	# ---------------------------------------------------------------- 6. takedown rules
	g = stage(1)[0]
	place(g, PAD, Vector3(0, 0, -1))
	p.global_position = PAD + Vector3(0, 0, 1.2)       # right behind him
	await step(0.2)
	check(Stealth.can_takedown(p, g), "takedown from behind an unaware guard")
	p.global_position = PAD + Vector3(0, 0, -1.2)      # in front
	check(not Stealth.can_takedown(p, g), "no takedown from the front")
	p.global_position = PAD + Vector3(0, 0, 2.6)       # too far
	check(not Stealth.can_takedown(p, g), "no takedown from 2.6 m")
	p.global_position = PAD + Vector3(0, 0, 1.2)
	w = wall(PAD + Vector3(0, 0, 0.55), 3.0)
	await physics_frame
	check(not Stealth.can_takedown(p, g), "no takedown through a wall")
	w.queue_free()
	await physics_frame
	g.state = Enemy.State.COMBAT
	check(not Stealth.can_takedown(p, g), "no takedown on a guard who is fighting")

	# ---------------------------------------------------------------- 7. non-lethal takedown, a witness
	var two := stage(2)
	g = two[0]
	var witness = two[1]
	place(g, PAD, Vector3(0, 0, -1))
	place(witness, PAD + Vector3(-10, 0, 0), Vector3(1, 0, 0))   # looking at the spot
	p.global_position = PAD + Vector3(0, 0, 1.2)
	await step(0.2)
	p._start_takedown(g, false)
	check(g.grabbed, "the guard is held")
	await step(0.35)
	var gap: float = Vector2(p.global_position.x - g.global_position.x, p.global_position.z - g.global_position.z).length()
	var gfwd := Vector3(-sin(g.aim_yaw), 0, -cos(g.aim_yaw))
	check(absf(gap - 0.72) < 0.1 and gfwd.dot((p.global_position - g.global_position).normalized()) < -0.8,
			"the operator is aligned right behind him (%.2f m)" % gap)
	await step(Main.Player.TD_TIME_KO)
	check(g.is_dead and g.get_meta("knocked_out", false), "knocked out (non-lethal)")
	check(witness.state in [Enemy.State.ALERTED, Enemy.State.COMBAT, Enemy.State.SEARCH], "a guard who saw it reacts (state %d)" % witness.state)

	# ---------------------------------------------------------------- 8. lethal takedown
	g = stage(1)[0]
	place(g, PAD, Vector3(0, 0, -1))
	p.global_position = PAD + Vector3(0, 0, 1.2)
	await step(0.2)
	p._start_takedown(g, true)
	await step(Main.Player.TD_TIME_KILL + 0.2)
	check(g.is_dead and not g.get_meta("knocked_out", false), "lethal takedown kills")
	check(not p.is_taking_down(), "the operator is free again afterwards")

	# ---------------------------------------------------------------- 9. bodies are found and called in
	var body = g
	var three := stage(2)
	var finder = three[0]
	var ally = three[1]
	body.global_position = PAD
	place(finder, PAD + Vector3(0, 0, -10), Vector3(0, 0, 1))      # facing the body
	place(ally, PAD + Vector3(-14, 0, -12), Vector3(0, 0, -1))      # facing away, in radio range
	p.global_position = PAD + Vector3(30, 0, 30)
	await step(1.0)
	check(finder.state == Enemy.State.INVESTIGATE and finder._body_target == body, "a guard spots the body and goes over")
	for i in 900:
		await physics_frame
		if Stealth.bodies_found > 0:
			break
	await step(0.2)
	check(Stealth.bodies_found == 1 and Stealth.known_bodies.has(body.get_instance_id()), "he inspects it and calls it in")
	check(finder.state == Enemy.State.SEARCH, "then searches the area")
	check(ally.state in [Enemy.State.ALERTED, Enemy.State.SEARCH], "a squadmate on the radio moves in (state %d)" % ally.state)
	check(Stealth.alert >= 1.0 and Stealth.alert_floor >= 1.0, "the area stays on alert (alert %.1f, floor %.1f)" % [Stealth.alert, Stealth.alert_floor])
	check(Stealth.open_bodies(self, main.level).is_empty() or not Stealth.open_bodies(self, main.level).has(body), "a found body is remembered, not re-reported")

	# ---------------------------------------------------------------- 10. hidden bodies stay hidden
	var bush := Vector3.INF
	for x in range(-60, 61, 2):
		for z in range(-60, 61, 2):
			var q := Vector3(x, 0, z)
			if main.level.concealment(q) >= 0.8:
				bush = q
				break
		if bush != Vector3.INF:
			break
	check(bush != Vector3.INF, "found a bush to hide a body in")
	if bush != Vector3.INF:
		var corpse = null
		for e in guards:
			if e.is_dead and e != body:
				corpse = e
		corpse.global_position = bush
		Stealth.known_bodies.erase(corpse.get_instance_id())
		check(Stealth.body_hidden(main.level, corpse), "a body in a bush counts as hidden")
		check(not Stealth.open_bodies(self, main.level).has(corpse), "hidden bodies aren't discoverable")
		corpse.set_meta("dragged", true)
		check(not Stealth.body_hidden(main.level, corpse), "a body being dragged is never hidden")
		corpse.remove_meta("dragged")

	# ---------------------------------------------------------------- 11. coordinated search
	var squad := stage(3)
	Stealth.raise_alert(2.0, 1.0)   # what sets a search off: a fight that went quiet
	for i in squad.size():
		place(squad[i], PAD + Vector3(i * 2.0, 0, -5), Vector3(0, 0, -1))
		squad[i].last_known = PAD
		squad[i]._enter_search()
	await step(0.3)
	var spots: Array = Stealth.claims().values()
	var apart := spots.size() == 3
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if (spots[i] as Vector3).distance_to(spots[j]) < Stealth.CLAIM_GAP:
				apart = false
	check(apart, "three searchers check three different spots %s" % [spots])
	var g0 = squad[0]
	g0._search_left = 0.05
	await step(0.2)
	await step(0.1)
	check(g0.state == Enemy.State.PATROL and Stealth.alert >= 1.0 and g0.aiming,
			"search over: back on a cautious patrol, weapon up (state %d, alert %.1f)" % [g0.state, Stealth.alert])

	# ---------------------------------------------------------------- 12. breaking contact
	g = stage(1)[0]
	place(g, PAD + Vector3(0, 0, -10), Vector3(0, 0, 1))
	p.global_position = PAD
	g.player = p
	g.last_known = PAD
	g._enter_combat(false)
	p.global_position = PAD + Vector3(60, 0, 40)   # gone, out of sight
	await step(8.5)
	check(g.state == Enemy.State.SEARCH, "losing the operator for 7 s turns a fight into a search (state %d)" % g.state)
	check(g._search_center.distance_to(PAD) < 6.0, "the search starts from the last known spot, not where the operator is now")

	# ---------------------------------------------------------------- 13. performance
	for e in main.enemies:
		if not e.is_dead:
			e.set_physics_process(true)
	var alive := 0
	for e in main.enemies:
		if not e.is_dead:
			alive += 1
	var t0 := Time.get_ticks_usec()
	for i in 20:
		for e in main.enemies:
			if not e.is_dead and e is Enemy:
				e.set("_perceive_timer", 0.0)
				e.set("_body_check", 0.0)
				e._perceive(0.016)
	var per := float(Time.get_ticks_usec() - t0) / 20.0 / 1000.0
	print("  perception for %d guards (sight + bodies, all forced at once): %.2f ms" % [alive, per])
	check(per < 6.0, "perception stays cheap with every guard checking at once")

	print("STEALTH: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
