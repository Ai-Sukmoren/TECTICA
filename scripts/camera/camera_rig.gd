extends Node3D
## Tactical overhead camera: smooth follow with aim look-ahead, zoom (mouse
## wheel), 45-degree rotation steps (Q/E) and trauma-based shake.

var target
var aim_source
var pitch_deg := 72.0
var yaw := 0.0
var zoom := 17.0
var cam: Camera3D
var fp_cam: Camera3D
var first_person := false

var _target_yaw := 0.0
var _target_zoom := 17.0
var _trauma := 0.0
var _noise := FastNoiseLite.new()
var _t := 0.0

const ZOOM_MIN := 8.0
const ZOOM_MAX := 30.0


func _ready() -> void:
	add_to_group("camera_rig")
	# Animation runs first; cameras consume that same frame's final eye pose.
	process_priority = 100
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.5
	cam.far = 200.0
	add_child(cam)
	cam.current = true
	fp_cam = Camera3D.new()
	fp_cam.fov = 78.0
	fp_cam.near = 0.04
	fp_cam.far = 200.0
	add_child(fp_cam)
	fp_cam.top_level = true
	_noise.frequency = 2.0


func snap() -> void:
	if target:
		global_position = target.global_position
	_apply()
	reset_physics_interpolation()


func add_shake(amount: float) -> void:
	_trauma = minf(_trauma + amount * float(preload("res://scripts/core/settings.gd").v.shake), 1.0)


func explosion_at(pos: Vector3) -> void:
	if target:
		add_shake(clampf(1.0 - target.global_position.distance_to(pos) / 28.0, 0.0, 1.0) * 0.9)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clampf(_target_zoom - 1.5, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clampf(_target_zoom + 1.5, ZOOM_MIN, ZOOM_MAX)


func _process(delta: float) -> void:
	_t += delta
	if Input.is_action_just_pressed("cam_rot_left"):
		_target_yaw += PI * 0.25
	if Input.is_action_just_pressed("cam_rot_right"):
		_target_yaw -= PI * 0.25
	if Input.is_action_just_pressed("zoom_in"):
		_target_zoom = 11.0 if _target_zoom > 20.0 else (24.0 if _target_zoom > 14.0 else 17.0)
	yaw = lerp_angle(yaw, _target_yaw, 1.0 - exp(-12.0 * delta))
	var extra := 0.0
	if aim_source and not aim_source.is_dead and aim_source.aiming and not first_person:
		extra = (float(aim_source.current_weapon().stats.zoom) - 1.0) * 1.8
	zoom = lerpf(zoom, _target_zoom + extra, 1.0 - exp(-12.0 * delta))

	if target:
		var tp: Vector3 = target.get_global_transform_interpolated().origin
		var desired := tp
		if aim_source and not aim_source.is_dead:
			# look-ahead from the cursor's SCREEN offset (not its world point) so the
			# camera never chases its own movement
			var optic_zoom: float = float(aim_source.current_weapon().stats.zoom)
			var reach: float = (5.0 + (optic_zoom - 1.0) * 2.6) if aim_source.aiming else 2.5
			var off := Vector2.ZERO
			if aim_source.using_pad:
				var ahead: Vector3 = aim_source.aim_point - tp
				ahead.y = 0.0
				off = Vector2(ahead.x, ahead.z).limit_length(12.0) / 12.0
				desired += Vector3(off.x, 0, off.y) * reach
			else:
				var vp := get_viewport()
				var half := vp.get_visible_rect().size * 0.5
				var m := (vp.get_mouse_position() - half) / maxf(half.y, 1.0)
				off = m.limit_length(1.0)
				desired += Basis(Vector3.UP, yaw) * Vector3(off.x, 0, off.y) * reach
			desired += aim_source.peek_offset() * 1.6
		global_position = global_position.lerp(desired, 1.0 - exp(-10.0 * delta))
	_apply()

	# first-person eye camera, driven by the rig's head (with physics interpolation offset)
	var fp_active: bool = first_person and target != null and target.rig != null and target.rig.fp_mode
	if fp_active:
		if not fp_cam.current:
			fp_cam.current = true
		var eye: Transform3D = target.rig.fp_eye
		fp_cam.global_transform = eye
		var zoom_mult: float = lerpf(1.0, float(target.current_weapon().stats.zoom) * 1.35, float(target.rig.aim_amt))
		var want_fov: float = float(preload("res://scripts/core/settings.gd").v.fov) / zoom_mult
		fp_cam.fov = lerpf(fp_cam.fov, want_fov, 1.0 - exp(-12.0 * delta))
	elif not cam.current:
		cam.current = true

	_trauma = maxf(_trauma - delta * 1.8, 0.0)
	var s := _trauma * _trauma
	cam.h_offset = _noise.get_noise_2d(_t * 40.0, 0.0) * 0.35 * s
	cam.v_offset = _noise.get_noise_2d(0.0, _t * 40.0) * 0.35 * s
	cam.rotation.z = _noise.get_noise_2d(_t * 40.0, 100.0) * 0.03 * s
	# Projection offsets shift the entire scene even with a stable eye transform.
	# Keep impact noise on the tactical camera; first person uses actual recoil.
	fp_cam.h_offset = 0.0
	fp_cam.v_offset = 0.0


func _apply() -> void:
	rotation = Vector3(0, yaw, 0)
	var p := deg_to_rad(pitch_deg)
	if cam:
		cam.position = Vector3(0, sin(p) * zoom, cos(p) * zoom)
		cam.rotation = Vector3(-p, 0, cam.rotation.z)


func active_camera() -> Camera3D:
	return fp_cam if fp_cam.current else cam


func screen_pixels_per_meter(viewport_height: float) -> float:
	return viewport_height / (2.0 * zoom * tan(deg_to_rad(cam.fov) * 0.5))
