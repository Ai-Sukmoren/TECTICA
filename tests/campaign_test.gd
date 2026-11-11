extends SceneTree
## Headless campaign run-through: builds the forest, then completes every
## objective of a chapter by teleporting / killing / holding interact.
##   godot --headless --path . -s res://tests/campaign_test.gd -- ch1
##   godot --headless --path . -s res://tests/campaign_test.gd -- ch2
var main
var f := 0
var ch := "ch1"
var t0 := 0
var last_step := -1
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		ch = args[0]
	t0 = Time.get_ticks_msec()
	load("res://scripts/main.gd").saved_mode = ch
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	print("[build] %s scene ready in %d ms" % [ch, Time.get_ticks_msec() - t0])
func _physics_process(_d: float) -> bool:
	f += 1
	var p = main.player
	var cp = main.campaign
	if f == 2:
		var nm: NavigationMesh = main.level.nav_region.navigation_mesh
		print("[world] enemies=%d nav_polys=%d cover=%d destructibles=%d hour=%s night=%.2f" % [main.enemies.size(), nm.get_polygon_count(),
				main.level.cover_points.size(), get_nodes_in_group("destructibles").size(), main.tod.clock_string(), main.tod.night])
		main.hud._deploy()
		for e in main.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		print("[ch] objectives: ", cp.objectives.map(func(o): return o.text))
	if f < 5 or main.game_over:
		if main.game_over and f % 60 == 0:
			print("[done] game_over victory=%s grade=%s score=%d hour=%s" % [main.victory, main.grade, main.mission_score, main.tod.clock_string()])
			quit()
		return false
	if cp.step != last_step:
		last_step = cp.step
		print("[step %d] %s  (t=%.1fs)" % [cp.step, cp.objective_text(), f / 60.0])
		Input.action_release("interact")
	var o: Dictionary = cp.current()
	if o.is_empty():
		return false
	match String(o.kind):
		"reach", "hold":
			if f % 30 == 0:
				p.global_position = (o.pos as Vector3) + Vector3(0.5, 0, 0.5)
			p.health = 100.0
		"clear":
			for e in main.enemies:
				if not e.is_dead and e.get_meta("group") == o.group:
					e.apply_damage(999.0, e.global_position + Vector3.UP, Vector3.FORWARD, p)
		"interact", "charge":
			if cp.charge_t < 0.0:
				var ip: Dictionary = main.level.interact_points[o.id]
				p.global_position = ip.pos
				Input.action_press("interact")
			else:
				Input.action_release("interact")
				p.global_position = (main.level.interact_points[o.id].pos as Vector3) + Vector3(0, 0, 25)
				p.health = 100.0
	if f > 60 * 200:
		print("[fail] timed out at step ", cp.step)
		quit()
	return false
