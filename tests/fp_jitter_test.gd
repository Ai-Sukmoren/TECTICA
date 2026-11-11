extends SceneTree
## Measures how far the rendered (interpolated) weapon drifts relative to the
## first-person camera while walking/running and aiming. Should be ~0.
##   godot --headless --path . -s res://tests/fp_jitter_test.gd
var main
var f := 0
var phys := 0
var prev := Vector3.INF
var worst := 0.0
var samples := 0
func _initialize() -> void:
	load("res://scripts/main.gd").saved_mode = "operation"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	Engine.max_fps = 200
func _physics_process(_d: float) -> bool:
	phys += 1
	var p = main.player
	if phys == 2:
		main.hud._deploy()
		for e in main.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
	if phys == 4:
		p.set_first_person(true)
		main.camera_rig.first_person = true
		Input.action_press("aim")
	if phys == 40:
		Input.action_press("move_forward")
		Input.action_press("move_right")
	if phys == 160:
		pass
	if phys == 220:
		worst = 0.0; samples = 0
	if phys == 160:
		print("[walk+aim] frames=%d worst gun-vs-eye frame delta = %.2f mm" % [samples, worst * 1000.0])
		worst = 0.0; samples = 0
		Input.action_release("aim")
		Input.action_press("sprint")
	if phys == 260:
		print("[sprint hip] frames=%d worst gun-vs-eye frame delta = %.2f mm" % [samples, worst * 1000.0])
		print("player moved to ", p.global_position, " speed ", p.velocity.length())
		quit()
	return false
func _process(_d: float) -> bool:
	f += 1
	var p = main.player
	if phys < 70 or p.current_weapon() == null:
		return false
	var cam: Camera3D = main.camera_rig.fp_cam
	var gun: Node3D = p.current_weapon()
	var rel := cam.global_transform.affine_inverse() * gun.get_global_transform_interpolated().origin
	if prev != Vector3.INF:
		worst = maxf(worst, rel.distance_to(prev))
		if phys > 220 and rel.distance_to(prev) > 0.004: print("  jump %.1f mm phys=%d f=%d slide=%.2f sprint=%.2f" % [rel.distance_to(prev)*1000.0, phys, f, p.rig.slide_amt, p.rig.sprint_amt])
		samples += 1
	prev = rel
	return false
