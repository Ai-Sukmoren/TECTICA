extends SceneTree
## Cost per call of the pieces of a zombie's tick, the rig animation and the
## HUD draw, with 28 infected hunting the player on WAREHOUSE (needs a window).
##   godot --path . -s res://tests/perf/micro_costs.gd
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func t_us(c: Callable, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		c.call()
	return float(Time.get_ticks_usec() - t0) / n

func run() -> void:
	Settings.ensure()
	Settings.v.vsync = false
	Settings.v.window_mode = 0
	root.size = Vector2i(1600, 900)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "warehouse"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(60)
	var main = current_scene
	var d = main.director
	d.wave = 14
	d.active = true
	d.to_spawn = 0
	d.timer = 9999.0
	main.player.set("god_mode", true)
	main.player.health = 100000.0
	main.player.global_position = Vector3(2.0, 0.05, 30)
	var spawned := 0
	for tries in 400:
		if spawned >= 28:
			break
		if d._spawn_one():
			spawned += 1
	await frames(240)
	var zs: Array = main.enemies.filter(func(e): return is_instance_valid(e) and not e.is_dead and e.kind != "bat" and e.kind != "dog")
	var z = zs[0]
	var dt := 1.0 / 120.0
	var res := {}
	res["zombie _physics_process"] = t_us(func(): z._physics_process(dt), 400)
	res["  move_with (move_and_slide)"] = t_us(func(): z.move_with(Vector3(0.5, 0, 0.5), dt), 400)
	res["  nav.get_next_path_position"] = t_us(func(): z.nav.get_next_path_position(), 400)
	res["  _separation"] = t_us(func(): z._separation(), 400)
	res["  _sync_rig"] = t_us(func(): z._sync_rig(), 400)
	res["  _clear_melee_path (ray)"] = t_us(func(): z._clear_melee_path(), 400)
	res["  _pick_target"] = t_us(func(): z._pick_target(), 400)
	res["rig _animate (near)"] = t_us(func(): z.rig._animate(1.0 / 120.0), 200)
	res["  _update_legs"] = t_us(func(): z.rig._update_legs(1.0 / 120.0), 200)
	res["  _update_arms"] = t_us(func(): z.rig._update_arms(1.0 / 120.0), 200)
	res["  _update_body"] = t_us(func(): z.rig._update_body(1.0 / 120.0), 200)
	res["  _update_weapon_pose"] = t_us(func(): z.rig._update_weapon_pose(1.0 / 120.0), 200)
	res["  _update_state"] = t_us(func(): z.rig._update_state(1.0 / 120.0), 200)
	res["rig _process (whole)"] = t_us(func(): z.rig._process(1.0 / 120.0), 200)
	var hud = main.hud
	res["hud _process"] = t_us(func(): hud._process(1.0 / 120.0), 200)
	res["player _physics_process"] = t_us(func(): main.player._physics_process(dt), 200)
	res["player _process"] = t_us(func(): main.player._process(1.0 / 120.0), 200)
	for k in res:
		print("[micro] %-34s %7.1f us" % [k, res[k]])
	print("[micro] zombies: %d  (x28 per tick for the AI, per frame for rigs)" % zs.size())
	# HUD draw: time whole frames with the overlay shown vs hidden
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for vis in [true, false, true, false]:
		hud.overlay.visible = vis
		await frames(30)
		var t0 := Time.get_ticks_usec()
		await frames(240)
		print("[micro] frame with hud overlay %-5s %.2f ms" % [str(vis), (Time.get_ticks_usec() - t0) / 240000.0])
	Settings.mark_clean_exit()
	quit(0)
