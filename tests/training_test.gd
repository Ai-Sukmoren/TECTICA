extends SceneTree
## The training course played through with the real controls, step by step:
##  - THE RANGE builds: targets in clear view of the firing line, both low walls vaultable, targets that never move or fire;
##  - every step finishes from its own input (look, walk, sprint, vault, crouch, slide, the range, reload, peek,
##    switch, grenade, dropkick, bullet time over the second wall) and shows the operator's keys;
##  - going down in the kill house puts the operator back up at the last station, the run goes on;
##  - clearing the kill house ends the course: victory, the first-time credit bonus, marked done.
##   godot --headless --fixed-fps 60 --path . -s res://tests/training_test.gd
const Main = preload("res://scripts/main.gd")
const Layers = preload("res://scripts/core/layers.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Campaign = preload("res://scripts/modes/campaign.gd")
const Settings = preload("res://scripts/core/settings.gd")
var failures := 0
var main
var tr
var dummy_shots := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


func _initialize() -> void:
	run.call_deferred()


func p():
	return main.player


func release_all() -> void:
	for a in ["move_forward", "sprint", "aim", "fire", "crouch", "vault", "kick", "look_right", "reload", "peek_left", "peek_right",
			"weapon_3", "grenade"]:
		Input.action_release(a)


## Holds `actions` until the training step moves on (or `limit` seconds pass); true if it moved on.
func hold_until_next(actions: Array, limit: float, each_frame: Callable = Callable()) -> bool:
	var s0: int = tr.step
	for a in actions:
		Input.action_press(a)
	var ok := false
	for i in int(limit * 60.0):
		if each_frame.is_valid():
			each_frame.call()
		await physics_frame
		if tr.step != s0 or tr.finished:
			ok = true
			break
	release_all()
	await physics_frame
	return ok


## A key tapped for one frame.
func tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame


## First-person look at a point.
func look_at_point(at: Vector3) -> void:
	var eye: Vector3 = p().global_position + Vector3(0, 1.6, 0)
	var d := at - eye
	p().aim_yaw = atan2(-d.x, -d.z)
	p().fp_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func vault_at_wall() -> void:
	if not Input.is_action_pressed("vault") and p()._find_vault(Vector3.FORWARD) != null:
		Input.action_press("vault")


func step_name() -> String:
	return String(tr.current().get("id", "done"))


func expect_step(id: String) -> void:
	check(step_name() == id, "now on step '%s' (%s)" % [id, step_name()])


func run() -> void:
	load("res://scripts/core/profile.gd").current = "training_test"
	Campaign.load_progress()
	Campaign.completed.erase("training")   # a fresh first run on the test account
	Campaign.save_progress()
	Main.saved_mode = "training"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	main = current_scene
	tr = main.training
	check(main.mode == "training" and tr != null, "the training mode loads with its course")
	check(main.level.get_script() == preload("res://scripts/world/training_level.gd"), "on THE RANGE map")
	var nm: NavigationMesh = main.level.nav_region.navigation_mesh
	check(nm.get_polygon_count() > 0, "the course has navigation (%d polygons)" % nm.get_polygon_count())
	var dummies: Array = main.enemies.filter(func(e): return e.dummy)
	check(dummies.size() == 5 and main.enemies.size() == 5, "five targets stand on the course, no hostiles yet (%d)" % main.enemies.size())
	for e in dummies:
		e.fired.connect(func(_s, _w, _r): dummy_shots += 1)

	# targets in clear view from the firing line
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var eye: Vector3 = main.level.firing_line + Vector3(0, 1.6, 0)
	for e in [tr._near] + tr._far:
		var q := PhysicsRayQueryParameters3D.create(eye, e.global_position + Vector3(0, 1.2, 0), Layers.WORLD)
		check(space.intersect_ray(q).is_empty(), "target at %s is in clear view from the firing line" % str(e.global_position))
	# both low walls take a vault
	var pl = p()
	var start_pos: Vector3 = pl.global_position
	for z in [main.level.vault_z, main.level.bullet_z]:
		pl.global_position = Vector3(0.5, 0.02, z + 1.2)
		await physics_frame
		await physics_frame
		check(pl._find_vault(Vector3.FORWARD) != null, "the low wall at z %.0f can be vaulted" % z)
	pl.global_position = start_pos
	pl.velocity = Vector3.ZERO
	pl.aim_yaw = 0.0
	await physics_frame
	check(main.get("_deployed") == true, "deployed")
	check(pl.first_person, "in first person")
	var how: String = tr.how_text()
	check(not how.contains("{"), "the hints show real keys, not action names ('%s')" % how)

	# ---- the steps, played with the controls
	var target_pos: Array = dummies.map(func(e): return e.global_position)
	expect_step("look")
	check(await hold_until_next(["look_right"], 6.0), "looking around finishes LOOK AROUND")
	p().aim_yaw = 0.0
	p().fp_pitch = 0.0
	expect_step("walk")
	var walk_how: String = tr.how_text()
	check(walk_how.contains("[W]") or walk_how.contains("["), "the walk hint names the movement keys ('%s')" % walk_how)
	check(await hold_until_next(["move_forward"], 10.0), "walking to the marker finishes WALK")
	expect_step("sprint")
	check(await hold_until_next(["move_forward", "sprint"], 8.0), "sprinting to the next marker finishes SPRINT")
	expect_step("vault")
	var saved_auto_vault: bool = Settings.v.auto_vault
	var vault_key := InputEventKey.new()
	vault_key.physical_keycode = KEY_K
	Settings.Controls._set_kbm("vault", [vault_key])
	Settings.v.auto_vault = false
	check(tr.how_text() == "[K] AT THE WALL", "manual vault hint uses the remapped key")
	pl.using_pad = true
	check(tr.how_text() == "A AT THE WALL", "manual vault hint uses A on gamepad")
	Settings.v.auto_vault = true
	check(tr.how_text() == "A AT THE WALL, OR SPRINT INTO IT", "gamepad hint offers sprint vault with Auto Vault on")
	pl.using_pad = false
	check(tr.how_text() == "[K] AT THE WALL, OR SPRINT INTO IT", "keyboard hint offers sprint vault with Auto Vault on")
	Settings.v.auto_vault = not OS.get_cmdline_user_args().has("manual-vault")
	check(await hold_until_next(["move_forward", "sprint"], 8.0, func():
		p().aim_yaw = 0.0
		if not Settings.v.auto_vault:
			vault_at_wall()), "crossing the first wall finishes VAULT")
	for i in 30:
		await physics_frame
	expect_step("crouch")
	await tap("crouch")
	await physics_frame
	check(step_name() == "slide", "pressing crouch finishes CROUCH")
	await tap("crouch")   # stand up again
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 40:
		await physics_frame
	check(await hold_until_next(["crouch", "move_forward", "sprint"], 1.0), "sprint + crouch slides and finishes SLIDE")
	for i in 60:
		await physics_frame
	expect_step("range")
	check(await hold_until_next(["move_forward"], 10.0, func(): p().aim_yaw = atan2(-(0.0 - p().global_position.x), -(main.level.firing_line.z - p().global_position.z))),
			"walking to the firing line finishes the range walk")
	expect_step("fire")
	p().health = 100000.0
	p().max_health = 100000.0
	check(await hold_until_next(["fire"], 8.0, func(): look_at_point(tr._near.global_position + Vector3(0, 1.3, 0))), "shooting the near target finishes FIRE")
	expect_step("ads")
	for e in tr._far:
		var dead := func(): return e.is_dead
		Input.action_press("aim")
		Input.action_press("fire")
		for i in 60 * 10:
			look_at_point(e.global_position + Vector3(0, 1.3, 0))
			var w = p().current_weapon()
			if w.ammo == 0:
				w.ammo = int(w.stats.mag)
			await physics_frame
			if dead.call():
				break
		release_all()
	await physics_frame
	check(step_name() == "reload", "hitting both far targets finishes AIM DOWN SIGHTS")
	await tap("reload")
	check(step_name() == "peek", "pressing reload finishes RELOAD")
	await tap("peek_left")
	await tap("peek_right")
	check(step_name() == "switch", "peeking both ways finishes PEEK")
	for i in 600:   # a switch waits for the reload to finish
		if p().can_act():
			break
		await physics_frame
	await tap("weapon_3")
	for i in 60:
		await physics_frame
		if step_name() != "switch":
			break
	check(step_name() == "grenade", "switching weapons finishes SWITCH")
	for i in 120:   # the gun swap finishes before a throw
		if p().can_act():
			break
		await physics_frame
	check(await hold_until_next(["grenade"], 8.0, func(): look_at_point(tr._grenade.global_position + Vector3(0, 1.0, 0))), "throwing a grenade finishes GRENADE")
	expect_step("kick")
	p().aim_yaw = 0.0
	p().fp_pitch = 0.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 30:
		await physics_frame
	check(await hold_until_next(["kick", "move_forward", "sprint"], 2.0), "sprint + kick finishes DROPKICK")
	for i in 60:
		await physics_frame
	expect_step("bullet")
	Settings.v.auto_vault = false
	check(tr.how_text().begins_with("[K] AT THE WALL") and tr.how_text().contains("MID-VAULT"),
			"bullet time hint teaches a manual vault followed by aiming")
	p().global_position = Vector3(0, 0.05, main.level.bullet_z + 6.0)
	p().velocity = Vector3.ZERO
	p().aim_yaw = 0.0
	p().fp_pitch = 0.0
	for i in 10:
		await physics_frame
	var saw_bt := [false]
	check(await hold_until_next(["move_forward", "sprint"], 8.0, func():
		p().aim_yaw = 0.0
		if p().vaulting:
			Input.action_press("aim")
		else:
			vault_at_wall()
		saw_bt[0] = saw_bt[0] or p().bullet_time), "manually vaulting the second wall and aiming finishes BULLET TIME")
	Settings.v.auto_vault = saved_auto_vault
	check(saw_bt[0], "bullet time actually started during it")
	expect_step("live")
	for i in 30:
		await physics_frame
	var hostiles: Array = main.enemies.filter(func(e): return not e.dummy)
	check(hostiles.size() == 3, "three hostiles in the kill house (%d)" % hostiles.size())
	if hostiles.is_empty():
		print("training_test failures=%d" % failures)
		quit(1)
		return

	# going down: back up at the last station, no game over
	var old = p()
	old.max_health = 100.0
	old.health = 100.0
	old.apply_damage(9999.0, old.global_position + Vector3.UP, Vector3.FORWARD, hostiles[0])
	for i in 30:
		await physics_frame
	check(old.is_dead and not main.game_over, "going down does not end the run")
	for i in 60 * 12:   # the kill cam slows the game; the countdown runs in game time
		await physics_frame
		if p() != old:
			break
	for i in 10:
		await physics_frame
	check(p() != old and not p().is_dead, "the operator is back up after a few seconds")
	check(p().global_position.distance_to(tr._checkpoint) < 1.5, "at the last station reached")
	check(step_name() == "live", "still on the kill house step")

	# clearing the kill house ends the course
	var credits0: int = Collection.credits
	for e in hostiles:
		e.apply_damage(9999.0, e.global_position + Vector3.UP, Vector3.FORWARD, p())
	for i in 30:
		await physics_frame
	check(tr.finished and main.game_over and main.victory, "clearing the kill house finishes the course")
	check(Collection.credits == credits0 + tr.REWARD, "first finish pays the bonus (+%d CR)" % (Collection.credits - credits0))
	check(Campaign.completed.get("training", "") == "DONE", "the course is marked done")
	check(main.hud._mode_label("training").contains("DONE"), "the title menu shows it done")

	# targets stood still and never fired
	var moved := 0
	for i in dummies.size():
		var e = dummies[i]
		if is_instance_valid(e) and not e.is_dead and e.global_position.distance_to(target_pos[i]) > 0.05:
			moved += 1
	check(moved == 0 and dummy_shots == 0, "targets never moved or fired (moved %d, shots %d)" % [moved, dummy_shots])

	print("training_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
