extends SceneTree
## Rendered regression: real walking/sprinting/ADS with repeated impact feedback.
## Unlike pose-only tests, check Camera3D.get_camera_transform() (projection
## offsets included). The original camera fails even with a stable eye pose.
var main
var frame := 0
var moving_frames := 0
var dt := 0.0
var worst_angle := 0.0
var worst_shift := 0.0
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	RenderingServer.frame_post_draw.connect(capture)
func _process(delta):
	Engine.max_fps = 0   # the frame count must not depend on the saved frame cap (settings re-apply it on load)
	dt = delta
	frame += 1
	if frame == 2:
		main.start_first_person = true
		main.hud._deploy()
		main.player.set_process_input(false)
		main.player.global_position = Vector3(30, 0, 18)
		main.player.reset_physics_interpolation()
		for enemy in main.enemies:
			enemy.set_physics_process(false)
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if frame == 140:
		Input.action_release("sprint")
		Input.action_press("aim")
	if frame == 260:
		Input.action_release("aim")
	if frame > 80 and frame % 30 == 0:
		main.camera_rig.add_shake(0.25)
		main.player.rig.hit_react(Vector3(1, 0, 1).normalized(), 0.5)
	return false
func capture():
	if frame < 3: return
	var p = main.player
	var c = main.camera_rig.fp_cam
	if p.velocity.length() > 1.0:
		moving_frames += 1
	var expected := Basis(Vector3.UP, p.aim_yaw) * Basis(Vector3.RIGHT, p.fp_pitch)
	worst_angle = maxf(worst_angle, expected.get_rotation_quaternion().angle_to(c.get_camera_transform().basis.get_rotation_quaternion()))
	worst_shift = maxf(worst_shift, c.get_camera_transform().origin.distance_to(c.global_position))
	if frame == 400:
		RenderingServer.frame_post_draw.disconnect(capture)
		Input.action_release("move_forward")
		print("CAMERA moving frames=", moving_frames, " angular error=", worst_angle, " projection shift=", worst_shift)
		# Starting tolerances: <0.001 radians rotation and <0.1 mm projection
		# shift with fixed look input. Any larger error fails this regression.
		quit(0 if worst_angle < 0.001 and worst_shift < 0.0001 and moving_frames > 250 else 1)
