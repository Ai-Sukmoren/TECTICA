extends SceneTree
## Bots use cover on the model maps (WAREHOUSE, BACKROOMS, TOKYO), which have no hand-placed cover:
##  - the map finds cover spots along its navigation edge: low cover, and wall corners with a sidestep to peek from;
##  - every spot is on the navigation mesh and hides a crouched body from a threat on its far side;
##  - a bot under fire runs to cover, crouches behind it, and comes up / steps out to shoot;
##  - a deathmatch bot that is not under fire any more leaves cover and goes back on the attack.
##   godot --headless --path . -s res://tests/bot_cover_test.gd [-- map ...]
const Main = preload("res://scripts/main.gd")
const Net = preload("res://scripts/net/net.gd")
const Enemy = preload("res://scripts/characters/enemy.gd")
const ModelLevel = preload("res://scripts/world/model_level.gd")
const Transition = preload("res://scripts/ui/transition.gd")
var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	load("res://scripts/core/profile.gd").current = "bot_cover_test"
	var maps: Array = OS.get_cmdline_user_args()
	if maps.is_empty():
		maps = ModelLevel.CONFIGS.keys()
	check(Net.host("pvp", 17902, false) == OK, "a local match against bots starts")
	for id in maps:
		await audit(String(id))
	Net.leave()
	print("BOT COVER: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)


func audit(id: String) -> void:
	print(id.to_upper())
	Main.saved_mode = "pvp"
	Main.saved_map = id
	Main.saved_tdm = true
	Main.saved_bots = 1
	Main.saved_quality = 0
	Main.quick_restart = true
	change_scene_to_file("res://scenes/loading.tscn")
	var deadline := Time.get_ticks_msec() + 20000
	var main
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var loaded = current_scene
		if loaded != null and loaded.get_script() == Main and loaded.get("_deployed") and not Transition.is_loading():
			main = loaded
			break
	check(main != null, "the match deploys through the loading screen")
	if main == null:
		return
	var lv = main.level
	var p = main.player
	p.health = 100000.0
	p.max_health = 100000.0
	check(lv._cover_validated, "cover is found while the map loads (not in the first fire fight)")
	lv._validate_cover()
	var spots: Array = lv.cover_points.filter(func(c): return c.valid)
	var corners := spots.filter(func(c): return (c.get("peek", Vector3.ZERO) as Vector3) != Vector3.ZERO).size()
	print("    %d cover spots (%d low, %d corners), %d on the navigation mesh" % [lv.cover_points.size(), spots.size() - corners, corners, spots.size()])
	check(spots.size() >= 25, "%s has cover for the bots (%d spots)" % [id, spots.size()])
	check(corners > 0 and spots.size() - corners > 0, "both low cover and corners to peek from")
	# each spot hides a crouched body from a threat 10 m out on the obstacle's side
	var hidden := 0
	for c in spots:
		var threat: Vector3 = (c.pos as Vector3) - (c.normal as Vector3) * 10.0
		if lv.is_covered(c.pos, threat):
			hidden += 1
	check(hidden >= spots.size() * 0.9, "spots hide a crouched body from the far side (%d of %d)" % [hidden, spots.size()])

	# a bot in a fire fight: pick a spot with a clear line from the bot's start to the threat
	var e = null
	for x in main.enemies:
		if x is Enemy and not x.is_dead and x.team != p.team:
			e = x
	check(e != null, "an enemy bot is in the match")
	if e == null:
		return
	var map: RID = main.get_world_3d().navigation_map
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var tried := 0
	var took_cover := false
	var crouched := false
	var peeked := false
	var fired_from_cover := [false]
	e.fired.connect(func(_soldier, _weapon, _result):
		if e.cover != null and e.phase == Enemy.Phase.PEEKING:
			fired_from_cover[0] = true)
	for c in spots:
		if tried >= 6 or (took_cover and crouched and peeked and fired_from_cover[0]):
			break
		var cp: Vector3 = c.pos
		# the operator 9-12 m out past the obstacle, standing on the navigation mesh, in sight of the peek spot
		var threat := NavigationServer3D.map_get_closest_point(map, cp - (c.normal as Vector3) * 10.0)
		if threat.distance_to(cp) < 7.0 or absf(threat.y - cp.y) > 1.0:
			continue
		var peek: Vector3 = cp + (c.get("peek", Vector3.ZERO) as Vector3)
		var q := PhysicsRayQueryParameters3D.create(peek + Vector3.UP * 1.5, threat + Vector3.UP * 1.3, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		# the bot starts 4 m to the side of the spot, on the same floor
		var start := NavigationServer3D.map_get_closest_point(map, cp + (c.normal as Vector3) * 3.0)
		if absf(start.y - cp.y) > 0.6:
			continue
		tried += 1
		for o in lv.cover_points:
			o.taken = null
		p.global_position = threat + Vector3.UP * 0.1
		p.velocity = Vector3.ZERO
		e.global_position = start + Vector3.UP * 0.1
		e.velocity = Vector3.ZERO
		e.health = e.max_health
		e.player = p
		e.last_known = threat
		e.state = Enemy.State.COMBAT
		e.phase = Enemy.Phase.MOVING
		e.cover = null
		e.set("_cover_timer", 0.0)
		e.set("_flank_check", 999.0)
		var reached := false
		for f in 720:   # 6 s at 120 Hz, under fire all along
			e.set("_flank_check", 999.0)
			e.since_damage = 0.0
			await physics_frame
			p.health = p.max_health
			if e.cover == null:
				continue
			var at: Vector3 = e.cover.pos
			if e.phase == Enemy.Phase.HIDDEN and Vector2(e.global_position.x - at.x, e.global_position.z - at.z).length() < 0.6:
				reached = true
				if e.crouching:
					crouched = true
			if reached and e.phase == Enemy.Phase.PEEKING and not e.crouching:
				var want: Vector3 = at + (e.cover.get("peek", Vector3.ZERO) as Vector3)
				if Vector2(e.global_position.x - want.x, e.global_position.z - want.z).length() < 0.35:
					peeked = true
			if reached and crouched and peeked and fired_from_cover[0]:
				break
		took_cover = took_cover or reached
	print("    took cover %s · crouched %s · peeked %s · fired %s (%d setups)" % [took_cover, crouched, peeked, fired_from_cover[0], tried])
	check(took_cover, "a bot under fire runs to a cover spot")
	check(crouched, "and crouches behind it")
	check(peeked, "then comes up or steps out past the corner to fire")
	check(fired_from_cover[0], "and fires from cover")

	# Hold ammo steady while recent damage wears off. The AI treats a low
	# magazine or a reload as a separate reason to stay in cover.
	check(e.cover != null, "the bot begins the quiet phase in cover")
	if e.cover == null:
		return
	e._cancel_reload()
	var left := false
	for f in 600:
		var weapon = e.current_weapon()
		weapon.ammo = int(weapon.stats.mag)
		await physics_frame
		p.health = p.max_health
		if e.cover == null and e.phase == Enemy.Phase.OPEN and e.state == Enemy.State.COMBAT:
			left = true
			break
	if not left:
		print("    quiet phase ended: state=%s phase=%s since_damage=%.2f reload=%.2f ammo=%d" %
				[e.state, e.phase, e.since_damage, e.reload_timer, e.current_weapon().ammo])
	check(left, "once it is quiet again the deathmatch bot leaves cover to fight")
