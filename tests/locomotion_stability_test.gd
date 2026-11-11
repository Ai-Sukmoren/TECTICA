extends SceneTree
## Rendered regression for gait-independent first-person camera and weapon poses.
var main
var elapsed := 0.0
var stage := -1
var samples := 0
var previous_weapon := Transform3D.IDENTITY
var previous_eye := Vector3.ZERO
var worst_position := 0.0
var worst_angle := 0.0
var worst_eye := 0.0
var failed := false
const STATES := ["walk", "sprint", "moving ADS"]
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	RenderingServer.frame_post_draw.connect(_after_draw)
func _process(delta: float) -> bool:
	if stage == -1:
		main.start_first_person = true
		main.hud._deploy()
		main.player.set_physics_process(false)
		main.player.set_process_input(false)
		for enemy in main.enemies:
			enemy.set_physics_process(false)
		stage = 0
	elapsed += delta
	var rig = main.player.rig
	rig.move_velocity = Vector3(0, 0, -7.0 if stage == 1 else -2.3)
	rig.sprint_target = 1.0 if stage == 1 else 0.0
	rig.aim_target = 1.0 if stage == 2 else 0.0
	return false
func _after_draw() -> void:
	if stage < 0 or elapsed < 2.0:
		return
	var rig = main.player.rig
	var camera = main.camera_rig.fp_cam
	var weapon: Transform3D = camera.global_transform.affine_inverse() * rig.weapon_anchor.global_transform
	var eye: Vector3 = camera.global_position - rig.global_position
	if samples > 0:
		worst_position = maxf(worst_position, weapon.origin.distance_to(previous_weapon.origin))
		worst_angle = maxf(worst_angle, weapon.basis.get_rotation_quaternion().angle_to(previous_weapon.basis.get_rotation_quaternion()))
		worst_eye = maxf(worst_eye, eye.distance_to(previous_eye))
	previous_weapon = weapon
	previous_eye = eye
	samples += 1
	if elapsed < 3.0:
		return
	# Starting tolerances: 0.1 mm translation / 0.001 rad rotation between
	# settled frames. Larger drift fails and requires fixing pose-space mixing.
	var passed := worst_position < 0.0001 and worst_eye < 0.0001 and worst_angle < 0.001
	print("STEADY ", STATES[stage], " samples=", samples, " weapon=", worst_position, " eye=", worst_eye, " angle=", worst_angle, " PASS=", passed)
	failed = failed or not passed
	stage += 1
	if stage == STATES.size():
		RenderingServer.frame_post_draw.disconnect(_after_draw)
		quit(1 if failed else 0)
		return
	elapsed = 0.0
	samples = 0
	worst_position = 0.0
	worst_angle = 0.0
	worst_eye = 0.0
