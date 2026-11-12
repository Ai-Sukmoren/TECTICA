extends Node3D
## Procedural, non-humanoid infected bodies (zombie dog, bat). The owning
## zombie keeps its humanoid rig hidden for the shared logic; this node draws
## and animates the creature from the parent's velocity / attack / death.

const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")

## Bats hover this high above their (ground-level) body origin.
const BAT_HOVER := 1.75

var kind := "dog"
var attack_t := 0.0
var _attack_len := 0.8
var _phase := 0.0
var _dead_t := -1.0
var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _tail: Node3D


func build(p_kind: String) -> void:
	kind = p_kind
	_phase = randf() * TAU
	if kind == "bat":
		_build_bat()
	else:
		_build_dog()


func play_attack(t: float) -> void:
	attack_t = t
	_attack_len = maxf(t, 0.05)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _build_dog() -> void:
	var hide := M.solid(Color(0.24, 0.21, 0.17), 0.95)
	var raw := M.solid(Color(0.45, 0.12, 0.1), 0.6)
	var bone := M.solid(Color(0.78, 0.74, 0.62), 0.7)
	var eye := M.emissive("zombie_eye", Color(1.0, 0.75, 0.2), 6.0)
	_body = _pivot(self, Vector3(0, 0.56, 0))
	_mesh(_body, ML.rbox(Vector3(0.3, 0.3, 0.72)), hide, Vector3.ZERO)
	_mesh(_body, ML.rbox(Vector3(0.24, 0.22, 0.3)), raw, Vector3(0.05, -0.02, 0.02))   # torn flank
	for i in 4:
		_mesh(_body, ML.rbox(Vector3(0.012, 0.16, 0.02)), bone, Vector3(0.155, 0.0, -0.1 + i * 0.07))
	_head = _pivot(_body, Vector3(0, 0.12, -0.4))
	_mesh(_head, ML.rbox(Vector3(0.2, 0.19, 0.22)), hide, Vector3(0, 0, -0.05))
	_mesh(_head, ML.rbox(Vector3(0.12, 0.1, 0.2)), hide, Vector3(0, -0.03, -0.24))
	_mesh(_head, ML.rbox(Vector3(0.1, 0.03, 0.17)), raw, Vector3(0, -0.095, -0.22))      # jaw
	for sx in [-1.0, 1.0]:
		_mesh(_head, ML.rbox(Vector3(0.05, 0.1, 0.03)), hide, Vector3(sx * 0.07, 0.12, 0.0), Vector3(0.3, 0, sx * 0.25))
		var e := _mesh(_head, ML.sphere(0.018, false, 6), eye, Vector3(sx * 0.055, 0.03, -0.165))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for k in 2:
			_mesh(_head, ML.cylinder(0.0, 0.008, 0.035, 4), bone, Vector3(sx * (0.02 + k * 0.022), -0.08, -0.31), Vector3(PI, 0, 0))
	for corner in [Vector3(-0.1, -0.1, -0.26), Vector3(0.1, -0.1, -0.26), Vector3(-0.1, -0.1, 0.27), Vector3(0.1, -0.1, 0.27)]:
		var leg := _pivot(_body, corner)
		_mesh(leg, ML.cylinder(0.035, 0.045, 0.26, 6), hide, Vector3(0, -0.13, 0))
		_mesh(leg, ML.cylinder(0.025, 0.035, 0.22, 6), hide, Vector3(0, -0.36, 0.02))
		_legs.append(leg)
	_tail = _pivot(_body, Vector3(0, 0.08, 0.36))
	_mesh(_tail, ML.cylinder(0.015, 0.03, 0.3, 5), hide, Vector3(0, 0.0, 0.14), Vector3(PI * 0.5 + 0.5, 0, 0))


func _build_bat() -> void:
	var fur := M.solid(Color(0.13, 0.1, 0.1), 0.95)
	var skin := M.solid(Color(0.3, 0.14, 0.14), 0.7)
	var eye := M.emissive("bat_eye", Color(1.0, 0.25, 0.1), 7.0)
	_body = _pivot(self, Vector3(0, BAT_HOVER, 0))
	_mesh(_body, ML.sphere(0.1, false, 10), fur, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 0.85, 1.3))
	_head = _pivot(_body, Vector3(0, 0.03, -0.13))
	_mesh(_head, ML.sphere(0.065, false, 8), fur, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		_mesh(_head, ML.cylinder(0.0, 0.03, 0.09, 4), skin, Vector3(sx * 0.035, 0.07, 0.01), Vector3(0, 0, -sx * 0.3))
		var e := _mesh(_head, ML.sphere(0.013, false, 6), eye, Vector3(sx * 0.025, 0.01, -0.055))
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var wing := _pivot(_body, Vector3(sx * 0.07, 0.02, 0))
		_mesh(wing, ML.rbox(Vector3(0.24, 0.012, 0.2)), skin, Vector3(sx * 0.13, 0, 0.02))
		_mesh(wing, ML.rbox(Vector3(0.16, 0.01, 0.14)), skin, Vector3(sx * 0.32, 0, 0.05), Vector3(0, sx * 0.25, 0))
		_mesh(wing, ML.cylinder(0.008, 0.008, 0.4, 4), fur, Vector3(sx * 0.2, 0.006, -0.07), Vector3(0, 0, PI * 0.5))
		_wings.append(wing)


func _process(delta: float) -> void:
	var z = get_parent()
	if z == null or _body == null:
		return
	if bool(z.is_dead):
		if _dead_t < 0.0:
			_dead_t = 0.0
		_dead_t += delta
		_animate_death(delta)
		return
	var v: Vector3 = z.velocity
	var spd := Vector2(v.x, v.z).length()
	# The body is modelled facing -Z. Face the way it is actually moving (nav
	# paths bend around cover); when standing / attacking, face its target.
	var yaw := atan2(-v.x, -v.z) if spd > 0.6 and attack_t <= 0.0 else float(z.aim_yaw)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-12.0 * delta))
	attack_t = maxf(attack_t - delta, 0.0)
	var strike := sin(clampf(1.0 - attack_t / _attack_len, 0.0, 1.0) * PI) if attack_t > 0.0 else 0.0
	if kind == "bat":
		_phase += delta * (22.0 + spd * 2.0)
		var flap := sin(_phase)
		for i in _wings.size():
			var sx := -1.0 if i == 0 else 1.0
			_wings[i].rotation = Vector3(0, 0, sx * (0.15 + flap * 0.85))
		_body.position = Vector3(sin(_phase * 0.09) * 0.12, BAT_HOVER + sin(_phase * 0.13) * 0.12 - strike * 0.35, -strike * 0.4)
		_body.rotation = Vector3(-0.15 - strike * 0.6, 0, sin(_phase * 0.07) * 0.25)
	else:
		_phase += delta * (2.0 + spd * 3.2)
		var amp := clampf(spd / 4.0, 0.0, 1.0) * 0.75
		var offs := [0.0, PI, PI * 0.6, PI * 1.6]   # gallop-ish gait
		for i in _legs.size():
			_legs[i].rotation.x = sin(_phase + offs[i]) * amp
		_body.position = Vector3(0, 0.56 + absf(sin(_phase)) * 0.05 * amp, -strike * 0.35)
		_body.rotation.x = sin(_phase * 2.0) * 0.06 * amp + strike * 0.25
		_head.rotation.x = -0.15 - strike * 0.5 + sin(_phase * 2.0) * 0.08
		_tail.rotation.y = sin(_phase * 1.5) * 0.4


func _animate_death(delta: float) -> void:
	var k := clampf(_dead_t / 0.45, 0.0, 1.0)
	if kind == "bat":
		_body.position.y = lerpf(_body.position.y, 0.08, 1.0 - exp(-10.0 * delta))
		_body.rotation.z = lerpf(_body.rotation.z, PI, k)
		for w in _wings:
			w.rotation.z = lerpf(w.rotation.z, 0.0, k)
	else:
		_body.rotation.z = lerpf(0.0, PI * 0.5, k)
		_body.position.y = lerpf(0.56, 0.18, k)
		for l in _legs:
			l.rotation.x = lerpf(l.rotation.x, 0.3, k)
