extends SceneTree
## Rendered regression: moving ADS must keep the weapon aligned to the eye.
var main
var frames := 0
var worst_offset := 0.0
var worst_eye := 0.0
var sampled := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	RenderingServer.frame_post_draw.connect(_after_draw)
func _process(_delta: float) -> bool:
	frames += 1
	if frames > 2400:
		push_error("ADS did not settle within the regression frame budget")
		quit(1)
		return false
	if frames == 2:
		main.start_first_person = true
		main.hud._deploy()
		for enemy in main.enemies:
			enemy.set_physics_process(false)
		Input.action_press("aim")
		Input.action_press("move_forward")
	return false
func _after_draw() -> void:
	if frames < 160:
		return
	var rig = main.player.rig
	if rig.aim_amt < 0.9999:
		return
	sampled += 1
	var camera = main.camera_rig.fp_cam
	var relative: Transform3D = camera.global_transform.affine_inverse() * rig.weapon_anchor.global_transform
	worst_offset = maxf(worst_offset, relative.origin.distance_to(main.player.current_weapon().ads_offset))
	worst_eye = maxf(worst_eye, camera.global_position.distance_to(rig.fp_eye.origin))
	if sampled >= 200:
		RenderingServer.frame_post_draw.disconnect(_after_draw)
		Input.action_release("aim")
		Input.action_release("move_forward")
		print("ADS alignment: max offset=", worst_offset, " eye error=", worst_eye)
		# Starting tolerance: 3 mm, allowing ADS transition convergence.
		# Any greater drift fails and requires correcting pose synchronization.
		var passed := worst_offset < 0.003 and worst_eye < 0.0001
		print("ADS stability: ", "PASS" if passed else "FAIL")
		quit(0 if passed else 1)

