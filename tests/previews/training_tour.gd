extends SceneTree
## Plays the whole training course at a watchable pace for a video (Movie Maker):
## each step's instruction stays on screen a moment before it is done, and the
## kill house is fought for real. Prints "TOUR <frame> <step id>" at each step.
##   godot --windowed --resolution 1600x900 --fixed-fps 60 --write-movie out.avi --path . -s res://tests/previews/training_tour.gd
const Main = preload("res://scripts/main.gd")
const Layers = preload("res://scripts/core/layers.gd")
var main
var tr
var _last := ""


func _initialize() -> void:
	run.call_deferred()


func p():
	return main.player


func frames(n: int) -> void:
	for i in n:
		await physics_frame
		_mark()


func _mark() -> void:
	var id := String(tr.current().get("id", "done")) if not tr.finished else "done"
	if id != _last:
		_last = id
		print("TOUR %d %s" % [Engine.get_frames_drawn(), id])


func release_all() -> void:
	for a in ["move_forward", "sprint", "aim", "fire", "crouch", "vault", "kick", "look_right", "look_left", "reload",
			"peek_left", "peek_right", "weapon_3", "weapon_1", "grenade"]:
		Input.action_release(a)


## Waits until the gun is free (no reload, swap or throw in progress).
func ready() -> void:
	for i in 600:
		if p().can_act():
			break
		await frames(1)


func tap(action: String) -> void:
	Input.action_press(action)
	await frames(3)
	Input.action_release(action)
	await frames(1)


func face(at: Vector3, height := 1.3) -> void:
	var eye: Vector3 = p().global_position + Vector3(0, 1.6, 0)
	var d := at + Vector3(0, height, 0) - eye
	var want := atan2(-d.x, -d.z)
	p().aim_yaw = lerp_angle(p().aim_yaw, want, 0.2)
	p().fp_pitch = lerpf(p().fp_pitch, atan2(d.y, Vector2(d.x, d.z).length()), 0.2)


func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Walks (or sprints) through the points; stops at the last one.
func go(points: Array, sprint := false, until := Callable()) -> void:
	for pt in points:
		Input.action_press("move_forward")
		if sprint:
			Input.action_press("sprint")
		for i in 60 * 12:
			face(pt, 1.6)
			await frames(1)
			if flat(p().global_position, pt) < 0.7 or (until.is_valid() and until.call()):
				break
		if until.is_valid() and until.call():
			break
	release_all()


func wait_step_change(limit := 6.0) -> void:
	var s0: int = tr.step
	for i in int(limit * 60):
		await frames(1)
		if tr.step != s0 or tr.finished:
			break


func shoot(target: Node, aim := true, limit := 8.0) -> void:
	if aim:
		Input.action_press("aim")
	for i in 20:
		face(target.global_position)
		await frames(1)
	for i in int(limit * 60):
		face(target.global_position)
		if i % 8 == 0:
			Input.action_press("fire")   # tapped: semi-auto guns fire once per press
		elif i % 8 == 4:
			Input.action_release("fire")
		var w = p().current_weapon()
		if w.ammo == 0:
			w.ammo = int(w.stats.mag)
		await frames(1)
		if target.is_dead:
			break
	release_all()


func run() -> void:
	load("res://scripts/core/profile.gd").current = "training_tour"
	var Campaign = load("res://scripts/modes/campaign.gd")
	Campaign.load_progress()
	Campaign.completed.erase("training")
	Campaign.save_progress()
	Main.saved_mode = "training"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30:
		await process_frame
	main = current_scene
	tr = main.training
	await frames(30)
	p().health = 100000.0
	p().max_health = 100000.0
	await frames(150)   # the briefing types out

	# look
	await frames(60)
	Input.action_press("look_right")
	await wait_step_change(8.0)
	release_all()
	for i in 50:
		p().aim_yaw = lerp_angle(p().aim_yaw, 0.0, 0.1)
		await frames(1)
	await frames(50)
	await go([main.level.walk_marker])
	await frames(70)
	await go([main.level.sprint_marker], true)
	await frames(70)
	await go([Vector3(0, 0, main.level.vault_z - 3.0)], true, func(): return tr._id() != "vault")
	await frames(80)
	await tap("crouch")
	await frames(80)
	await tap("crouch")
	await frames(20)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await frames(40)
	Input.action_press("crouch")
	await frames(70)
	release_all()
	await frames(60)
	await go([main.level.firing_line])
	await frames(60)
	await shoot(tr._near, false)
	await frames(70)
	for e in tr._far:
		await shoot(e)
		await frames(20)
	await frames(60)
	await tap("reload")
	await frames(150)
	await ready()
	await tap("peek_left")
	await frames(40)
	await tap("peek_right")
	await frames(60)
	await ready()
	await tap("weapon_3")
	await frames(90)
	for i in 40:
		face(tr._grenade.global_position, 1.4)
		await frames(1)
	await ready()
	await tap("grenade")
	await wait_step_change(6.0)
	await frames(60)
	await ready()
	await tap("weapon_1")
	await frames(50)
	for i in 30:
		face(Vector3(1.0, 0, -30))
		await frames(1)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await frames(35)
	Input.action_press("kick")
	await wait_step_change(3.0)
	release_all()
	await frames(70)
	# up the lane between the target plates, then over the second wall with bullet time
	await go([Vector3(1.0, 0, -28), Vector3(1.0, 0, -37), Vector3(0, 0, main.level.bullet_z + 4.0)])
	await frames(40)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 60 * 6:
		face(Vector3(0, 0, main.level.bullet_z - 8.0), 1.6)
		if p().vaulting:
			Input.action_press("aim")
		await frames(1)
		if tr._id() != "bullet":
			break
	release_all()
	await frames(60)
	# kill house: hold the doorway, shoot what shows, then push in
	await go([main.level.house_door + Vector3(0, 0, 2.0)])
	var hostiles: Array = main.enemies.filter(func(e): return not e.dummy)
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var pushes := [Vector3(0, 0, -55), Vector3(-1.5, 0, -57.5), Vector3(-4, 0, -60), Vector3(-4.5, 0, -64), Vector3(0, 0, -66)]
	var push_i := 0
	for i in 60 * 40:
		var alive: Array = hostiles.filter(func(e): return is_instance_valid(e) and not e.is_dead)
		if alive.is_empty():
			break
		var seen = null
		for e in alive:
			var q := PhysicsRayQueryParameters3D.create(p().global_position + Vector3(0, 1.6, 0), e.global_position + Vector3(0, 1.3, 0), Layers.WORLD)
			if space.intersect_ray(q).is_empty():
				seen = e
				break
		if seen != null:
			Input.action_release("move_forward")
			await shoot(seen, true, 3.0)
		else:
			var pt: Vector3 = pushes[mini(push_i, pushes.size() - 1)]
			Input.action_press("move_forward")
			face(pt, 1.6)
			await frames(1)
			if flat(p().global_position, pt) < 0.8:
				push_i += 1
	release_all()
	await frames(240)   # TRAINING COMPLETE
	print("TOUR %d end finished=%s" % [Engine.get_frames_drawn(), str(tr.finished)])
	quit()
