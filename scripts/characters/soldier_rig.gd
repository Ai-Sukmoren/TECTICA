extends Node3D
## Procedural military soldier.
##
## Builds a segmented, fully geared operator (helmet, plate carrier, pouches,
## backpack, knee/elbow pads, boots, gloves) and animates it entirely in code:
##   * Locomotion blend space driven by local velocity: idle breathing, walk,
##     strafe, backpedal, tactical jog, sprint, crouch walk, turn-in-place.
##   * Independent facing: legs follow movement, torso follows the aim with a
##     twist distributed over spine and chest.
##   * Two-bone IK for both legs (procedural foot placement / gait cycle) and
##     both arms (hands locked to weapon grip and handguard).
##   * Acceleration / deceleration lean, stride-coupled hip bob and sway.
##   * Layered weapon poses (low ready, aim, high-port sprint, reload, lowered)
##     with spring recoil, keyframed reload hand paths, weapon switching,
##     hit-reaction springs and a procedural death fall.

const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const FX = preload("res://scripts/fx/fx.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Layers = preload("res://scripts/core/layers.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")

signal footstep(pos: Vector3, intensity: float)
signal throw_release

const HIP_STAND := 0.93
const HIP_CROUCH := 0.6
const THIGH := 0.45
const SHIN := 0.43
const ANKLE_H := 0.088
const UPPER_ARM := 0.3
const FOREARM := 0.285
const HIP_HALF := 0.1

## Weapon poses relative to the chest: [position, euler(pitch, yaw, roll)].
const POSES := {
	"rifle": {
		"ready": [Vector3(0.13, -0.07, -0.25), Vector3(-0.34, 0.14, 0.06)],
		"aim": [Vector3(0.11, 0.075, -0.24), Vector3(0.0, 0.0, 0.0)],
		"sprint": [Vector3(0.05, 0.02, -0.24), Vector3(0.95, 0.42, -0.35)],
		"sprint_1h": [Vector3(0.27, -0.23, -0.2), Vector3(-0.42, 0.04, 0.12)],
		"reload": [Vector3(0.07, -0.03, -0.3), Vector3(0.22, 0.38, 0.6)],
		"lower": [Vector3(0.2, -0.32, -0.12), Vector3(-1.15, 0.2, 0.0)],
		"vault": [Vector3(0.26, 0.12, -0.08), Vector3(1.1, -0.35, -0.7)],
	},
	"pistol": {
		"ready": [Vector3(0.06, -0.08, -0.3), Vector3(-0.55, 0.05, 0.0)],
		"aim": [Vector3(0.04, 0.1, -0.45), Vector3(0.0, 0.0, 0.0)],
		"sprint": [Vector3(0.13, -0.14, -0.16), Vector3(-1.05, 0.0, 0.0)],
		"sprint_1h": [Vector3(0.25, -0.24, -0.2), Vector3(-0.6, 0.0, 0.08)],
		"reload": [Vector3(0.02, -0.02, -0.32), Vector3(0.5, 0.25, 0.45)],
		"lower": [Vector3(0.18, -0.34, -0.08), Vector3(-1.3, 0.0, 0.0)],
		"vault": [Vector3(0.22, 0.02, -0.12), Vector3(0.6, -0.3, -0.5)],
	},
}

## First-person weapon poses relative to the eye camera.
const FP_POSES := {
	"rifle": {"hip": [Vector3(0.16, -0.2, -0.34), Vector3(0.04, 0.06, 0.04)], "aim": [Vector3(0.0, -0.15, -0.19), Vector3.ZERO]},
	"pistol": {"hip": [Vector3(0.13, -0.15, -0.36), Vector3(0.03, 0.05, 0.0)], "aim": [Vector3(0.0, -0.077, -0.4), Vector3.ZERO]},
}

# ---- inputs, written by the owning character every frame ----
var move_velocity := Vector3.ZERO
var aim_yaw := 0.0
var crouch_target := 0.0
var aim_target := 0.0
var sprint_target := 0.0
var air_target := 0.0
var air_amt := 0.0
var lean_target := 0.0
var fp_mode := false
## Third-person sprint: carry the gun one-handed in the right hand and pump
## the free left arm with the stride.
var one_hand_sprint := false
var _free_arm := 0.0
## Infected: hunched lurching gait, reaching arms, claw attacks.
var zombie := false
var zombie_kind := "walker"
var _render_scale := Vector3.ONE
var throw_t := -1.0
var _throw_dur := 0.7
var _throw_released := false
var _grenade_mesh: MeshInstance3D
var _prev_u := [0.0, 0.0]
var slide_target := 0.0
var slide_amt := 0.0
var ads_speed := 1.0
var cycle_t := -1.0
var _cycle_dur := 0.6
var _cycle_cased := false
var _pump_base := Vector3.ZERO
var attack_t := -1.0
var _attack_dur := 0.8
var fp_pitch := 0.0
## Eye camera transform for first person (world space, physics frame).
var fp_eye := Transform3D.IDENTITY
var _eye_smooth := Vector3(0, 1.66, -0.09)

# ---- smoothed animation state ----
var lean_amt := 0.0
var vault_t := -1.0
var _vault_dur := 0.6
var _vault_peak := 0.5
var _vault_plant := Vector3.ZERO
var _prev_aim_yaw := 0.0
var _sway_yaw := 0.0
var _sway_yaw_v := 0.0
var crouch_amt := 0.0
var aim_amt := 0.0
var sprint_amt := 0.0
var move_blend := 0.0
var lower_yaw := 0.0
var phase := 0.0
var cadence := 0.0
var speed := 0.0
var local_move := Vector2.ZERO
var twist := 0.0
var turning := false
var dead := false
var locomotion_state := "IDLE"

var _prev_vel := Vector3.ZERO
var _visual_velocity := Vector3.ZERO
var _acc_smooth := Vector3.ZERO
var _time := 0.0

# springs
var _recoil_pos := 0.0
var _recoil_pos_v := 0.0
var _recoil_rot := 0.0
var _recoil_rot_v := 0.0
var _recoil_yaw := 0.0
var _recoil_yaw_v := 0.0
var _hit_off := Vector2.ZERO
var _hit_vel := Vector2.ZERO

# action layers
var reload_t := -1.0
var _reload_dur := 1.0
var _reload_empty := false
var _reload_ev := {}
var switch_t := -1.0
var _switch_dur := 0.7
var death_t := -1.0
var _death_dir := Vector3.FORWARD
var _death_hip := HIP_STAND

# nodes
var pivot: Node3D
var hips: Node3D
var spine: Node3D
var chest: Node3D
var head: Node3D
var thighs: Array = []
var shins: Array = []
var feet: Array = []
var shoulders: Array = []
var elbows: Array = []
var hands: Array = []
var weapon_anchor: Node3D
var back_slot: Node3D
var thigh_slot: Node3D
var hand_mag: Node3D
var weapon: Weapon
var palette: Dictionary


# =====================================================================
#  BUILD
# =====================================================================

func build(p: Dictionary) -> void:
	palette = p
	var camo: Material = p.camo
	var vest: Material = p.vest
	var gear: Material = p.gear
	var detail: Material = p.detail

	pivot = _node(self, "Pivot", Vector3.ZERO)
	hips = _node(pivot, "Hips", Vector3(0, HIP_STAND, 0))

	# --- pelvis & belt ---
	_mesh(hips, ML.capsule(0.125, 0.36), camo, Vector3(0, -0.02, 0), Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.8))
	_mesh(hips, ML.rbox(Vector3(0.37, 0.07, 0.26)), gear, Vector3(0, 0.06, 0))
	_mesh(hips, ML.rbox(Vector3(0.05, 0.045, 0.02)), detail, Vector3(0, 0.06, -0.135))
	_mesh(hips, ML.rbox(Vector3(0.15, 0.12, 0.08)), gear, Vector3(0.06, -0.01, 0.16))
	_mesh(hips, ML.rbox(Vector3(0.06, 0.1, 0.06)), gear, Vector3(-0.17, 0.0, 0.08))

	# --- legs ---
	for side in [-1, 1]:
		var thigh := _node(hips, "Thigh", Vector3(side * HIP_HALF, -0.03, 0))
		_mesh(thigh, ML.capsule(0.09, 0.52), camo, Vector3(0, -THIGH * 0.5, 0))
		_mesh(thigh, ML.rbox(Vector3(0.05, 0.15, 0.12)), camo, Vector3(side * 0.085, -0.25, 0))
		var shin := _node(thigh, "Shin", Vector3(0, -THIGH, 0))
		_mesh(shin, ML.capsule(0.07, 0.46), camo, Vector3(0, -SHIN * 0.5, 0))
		_mesh(shin, ML.rbox(Vector3(0.115, 0.13, 0.06)), detail, Vector3(0, -0.035, -0.07))
		var foot := _node(shin, "Foot", Vector3(0, -SHIN, 0))
		_mesh(foot, ML.rbox(Vector3(0.115, 0.1, 0.28)), p.boots, Vector3(0, -0.035, -0.055))
		_mesh(foot, ML.rbox(Vector3(0.125, 0.025, 0.3)), M.solid(Color(0.05, 0.05, 0.05), 0.9), Vector3(0, -0.075, -0.055))
		_mesh(foot, ML.cylinder(0.074, 0.078, 0.15, 12), p.boots, Vector3(0, 0.04, 0))
		thighs.append(thigh)
		shins.append(shin)
		feet.append(foot)

	# thigh holster on the right leg
	thigh_slot = _node(thighs[1], "HolsterSlot", Vector3(0.125, -0.13, 0.0))
	thigh_slot.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	_mesh(thighs[1], ML.rbox(Vector3(0.05, 0.2, 0.11)), gear, Vector3(0.115, -0.17, 0.0))

	# --- spine / torso ---
	spine = _node(hips, "Spine", Vector3(0, 0.08, 0))
	_mesh(spine, ML.capsule(0.135, 0.34), camo, Vector3(0, 0.09, 0), Vector3.ZERO, Vector3(1.15, 1, 0.8))
	chest = _node(spine, "Chest", Vector3(0, 0.22, 0))
	_mesh(chest, ML.capsule(0.165, 0.46), camo, Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1.2, 1, 0.78))

	# plate carrier: front/back plates, cummerbund, shoulder straps
	_mesh(chest, ML.rbox(Vector3(0.36, 0.34, 0.08)), vest, Vector3(0, 0.07, -0.125))
	_mesh(chest, ML.rbox(Vector3(0.37, 0.36, 0.08)), vest, Vector3(0, 0.08, 0.125))
	_mesh(chest, ML.rbox(Vector3(0.41, 0.14, 0.27)), vest, Vector3(0, -0.06, 0))
	for side in [-1, 1]:
		_mesh(chest, ML.rbox(Vector3(0.075, 0.035, 0.27)), vest, Vector3(side * 0.12, 0.255, 0))
	# triple rifle-mag pouch + admin pouch + flaps
	for i in 3:
		var x := -0.09 + i * 0.09
		_mesh(chest, ML.rbox(Vector3(0.075, 0.13, 0.055)), gear, Vector3(x, 0.0, -0.19))
		_mesh(chest, ML.rbox(Vector3(0.078, 0.035, 0.06)), vest, Vector3(x, 0.07, -0.19))
	_mesh(chest, ML.rbox(Vector3(0.2, 0.08, 0.035)), gear, Vector3(0, 0.17, -0.175))
	# radio pouch + antenna, IFAK
	_mesh(chest, ML.rbox(Vector3(0.07, 0.15, 0.08)), gear, Vector3(-0.205, 0.0, 0.08))
	_mesh(chest, ML.cylinder(0.005, 0.005, 0.36, 6), detail, Vector3(-0.215, 0.24, 0.1), Vector3(0.15, 0, 0.12))
	_mesh(chest, ML.rbox(Vector3(0.07, 0.11, 0.08)), M.solid(Color(0.45, 0.08, 0.06), 0.8), Vector3(0.205, -0.02, 0.07))
	# assault backpack with bedroll and side pouches
	_mesh(chest, ML.rbox(Vector3(0.31, 0.38, 0.17)), gear, Vector3(0, 0.1, 0.25))
	_mesh(chest, ML.rbox(Vector3(0.24, 0.16, 0.04)), vest, Vector3(0, 0.03, 0.345))
	_mesh(chest, ML.capsule(0.07, 0.36), M.fabric("bedroll", Color(0.25, 0.27, 0.2)), Vector3(0, 0.33, 0.23), Vector3(0, 0, PI * 0.5))
	for side in [-1, 1]:
		_mesh(chest, ML.rbox(Vector3(0.06, 0.18, 0.11)), vest, Vector3(side * 0.185, 0.06, 0.25))

	# --- neck & head ---
	_mesh(chest, ML.cylinder(0.055, 0.06, 0.12, 12), p.face, Vector3(0, 0.33, 0))
	head = _node(chest, "Head", Vector3(0, 0.42, 0))
	_mesh(head, ML.sphere(0.105), p.face, Vector3.ZERO, Vector3.ZERO, Vector3(0.88, 1.05, 0.98))
	_build_headgear(head, p)

	# --- arms ---
	for side in [-1, 1]:
		var sh := _node(chest, "Shoulder", Vector3(side * 0.2, 0.21, 0))
		_mesh(sh, ML.sphere(0.078, false, 12), camo, Vector3.ZERO)
		_mesh(sh, ML.capsule(0.063, 0.34), camo, Vector3(0, -UPPER_ARM * 0.5, 0))
		_mesh(sh, ML.rbox(Vector3(0.012, 0.07, 0.07)), gear, Vector3(side * 0.06, -0.09, 0))
		var el := _node(sh, "Elbow", Vector3(0, -UPPER_ARM, 0))
		_mesh(el, ML.capsule(0.055, 0.31), camo, Vector3(0, -FOREARM * 0.5, 0))
		_mesh(el, ML.rbox(Vector3(0.085, 0.085, 0.05)), detail, Vector3(0, -0.01, -0.05))
		var hand := _node(el, "Hand", Vector3(0, -FOREARM, 0))
		_mesh(hand, ML.rbox(Vector3(0.072, 0.095, 0.1)), p.gloves, Vector3.ZERO)
		_mesh(hand, ML.rbox(Vector3(0.06, 0.03, 0.11)), p.gloves, Vector3(0, 0.05, -0.02))
		shoulders.append(sh)
		elbows.append(el)
		hands.append(hand)

	# --- weapon mounting points ---
	weapon_anchor = _node(chest, "WeaponAnchor", Vector3.ZERO)
	back_slot = _node(chest, "BackSlot", Vector3(0.0, 0.12, 0.36))
	back_slot.basis = Basis(Vector3.BACK, 0.65) * Basis(Vector3.RIGHT, PI * 0.5)
	hand_mag = _node(hands[0], "HandMag", Vector3(0, -0.04, 0))
	_grenade_mesh = _mesh(hands[1], ML.sphere(0.042, false, 10), M.painted_metal("grenade", Color(0.25, 0.3, 0.2)), Vector3(0, -0.05, -0.03))
	_grenade_mesh.visible = false


func _build_headgear(h: Node3D, p: Dictionary) -> void:
	var detail: Material = p.detail
	match String(p.headgear):
		"helmet":
			var hm: Material = p.helmet
			_mesh(h, ML.sphere(0.145, true, 20), hm, Vector3(0, 0.015, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
			_mesh(h, ML.cylinder(0.147, 0.15, 0.04, 20), hm, Vector3(0, 0.0, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
			_mesh(h, ML.rbox(Vector3(0.055, 0.045, 0.03)), detail, Vector3(0, 0.08, -0.16))
			for side in [-1, 1]:
				_mesh(h, ML.rbox(Vector3(0.022, 0.03, 0.15)), detail, Vector3(side * 0.142, 0.03, 0))
				_mesh(h, ML.cylinder(0.05, 0.05, 0.045, 12), detail, Vector3(side * 0.115, -0.02, 0.0), Vector3(0, 0, PI * 0.5))
			_mesh(h, ML.rbox(Vector3(0.08, 0.05, 0.035)), detail, Vector3(0, 0.07, 0.16))
			_mesh(h, ML.rbox(Vector3(0.2, 0.012, 0.012)), detail, Vector3(0, 0.1, -0.02))
		"cap":
			_mesh(h, ML.cylinder(0.105, 0.112, 0.08, 16), p.camo, Vector3(0, 0.07, 0))
			_mesh(h, ML.rbox(Vector3(0.15, 0.012, 0.09)), p.camo, Vector3(0, 0.035, -0.135))
		"beanie":
			_mesh(h, ML.sphere(0.113, true, 16), M.fabric("beanie", Color(0.12, 0.13, 0.1)), Vector3(0, 0.015, 0), Vector3.ZERO, Vector3(1, 1.15, 1.02))
	if p.get("eyes", false):
		for sx in [-1, 1]:
			var eye := _mesh(h, ML.sphere(0.012, false, 6), M.emissive("zombie_eye", Color(1.0, 0.75, 0.2), 6.0), Vector3(sx * 0.034, 0.02, -0.093))
			eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if p.get("goggles", false):
		_mesh(h, ML.rbox(Vector3(0.16, 0.04, 0.025)), M.solid(Color(0.03, 0.03, 0.03), 0.15, 0.4), Vector3(0, 0.015, -0.097))


func _node(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = n
	node.position = pos
	parent.add_child(node)
	return node


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


# =====================================================================
#  PUBLIC API
# =====================================================================

## Hides the head from the eye camera while keeping its shadow.
func set_first_person(on: bool) -> void:
	fp_mode = on
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for n in head.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = mode
	# Torso, vest, backpack, bedroll and neck sit right at the eye when the
	# body pitches forward (crouch, slide, vault), so in first person they only
	# cast shadows. Arms (under the shoulders) and legs stay visible.
	for parent in [spine, chest]:
		for n in parent.get_children():
			if n is MeshInstance3D:
				(n as MeshInstance3D).cast_shadow = mode


func snap_yaw(yaw: float) -> void:
	aim_yaw = yaw
	lower_yaw = yaw


func set_weapon(active: Weapon, others: Array) -> void:
	weapon = active
	cycle_t = -1.0
	_pump_base = active.pump.position if active.pump != null else Vector3.ZERO
	_attach(active, weapon_anchor)
	for w in others:
		_attach(w, thigh_slot if w.is_pistol() else back_slot)
	for c in hand_mag.get_children():
		c.queue_free()
	if active.mag_node:
		var copy := active.mag_node.duplicate() as Node3D
		copy.position = Vector3.ZERO
		hand_mag.add_child(copy)
	hand_mag.visible = false


func _attach(n: Node3D, parent: Node3D) -> void:
	if n.get_parent() == null:
		parent.add_child(n)
	elif n.get_parent() != parent:
		n.reparent(parent, false)
	n.transform = Transform3D.IDENTITY
	n.reset_physics_interpolation()


func add_recoil(strength: float) -> void:
	_recoil_pos_v += strength * 1.2
	_recoil_rot_v += strength * 9.0
	_recoil_yaw_v += randf_range(-1.0, 1.0) * strength * 4.0


func hit_react(dir: Vector3, strength: float) -> void:
	var ld := Basis(Vector3.UP, lower_yaw).inverse() * dir
	var k := clampf(strength * 0.09, 0.8, 3.5)
	_hit_vel += Vector2(ld.z, -ld.x) * k
	_recoil_rot_v += randf_range(-4.0, 4.0)
	_recoil_yaw_v += randf_range(-4.0, 4.0)


func play_reload(duration: float, empty: bool) -> void:
	reload_t = 0.0
	_reload_dur = maxf(duration, 0.1)
	_reload_empty = empty
	if empty:
		_reload_ev = {"out": 0.2, "pouch": 0.36, "grab": 0.46, "mag_in": 0.62, "bolt": 0.8}
	else:
		_reload_ev = {"out": 0.24, "pouch": 0.42, "grab": 0.52, "mag_in": 0.7, "bolt": 9.0}


func cancel_reload() -> void:
	reload_t = -1.0
	hand_mag.visible = false
	if weapon and weapon.mag_node:
		weapon.mag_node.visible = true


func play_switch(duration: float) -> void:
	switch_t = 0.0
	_switch_dur = duration


## Side vault: left hand plants on `plant` (world), legs tuck to the right.
func play_vault(duration: float, obstacle_top: float, plant: Vector3) -> void:
	vault_t = 0.0
	_vault_dur = maxf(duration, 0.2)
	_vault_peak = maxf(obstacle_top - 0.42, 0.18)
	_vault_plant = plant
	cancel_reload()


func play_attack(duration: float) -> void:
	attack_t = 0.0
	_attack_dur = maxf(duration, 0.2)


func play_throw(duration: float) -> void:
	throw_t = 0.0
	_throw_dur = duration
	_throw_released = false
	_grenade_mesh.visible = true
	cancel_reload()


## Overhand throw path for the right hand (chest space keys).
func _throw_hand(grip_pos: Vector3) -> Vector3:
	var cx := chest.global_transform
	var keys := [[0.0, grip_pos], [0.22, cx * Vector3(0.24, 0.36, 0.2)], [0.42, cx * Vector3(0.1, 0.44, -0.52)],
			[0.66, cx * Vector3(0.14, 0.05, -0.38)], [1.0, grip_pos]]
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if throw_t <= b[0]:
			var u := smoothstep(0.0, 1.0, (throw_t - float(a[0])) / (float(b[0]) - float(a[0])))
			return (a[1] as Vector3).lerp(b[1], u)
	return grip_pos


func is_vaulting() -> bool:
	return vault_t >= 0.0


## Smooth bump weight inside the vault timeline.
func _vw(a: float, b: float, c: float, d: float) -> float:
	if vault_t < 0.0:
		return 0.0
	return smoothstep(a, b, vault_t) * (1.0 - smoothstep(c, d, vault_t))


func play_death(dir: Vector3) -> void:
	if dead:
		return
	dead = true
	death_t = 0.0
	vault_t = -1.0
	_death_hip = hips.position.y
	var d := Vector3(dir.x, 0, dir.z)
	_death_dir = d.normalized() if d.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	cancel_reload()
	_drop_weapon()


func debug_info() -> Dictionary:
	return {
		"state": locomotion_state,
		"speed": speed,
		"direction": rad_to_deg(atan2(local_move.x, -local_move.y)) if speed > 0.05 else 0.0,
		"cadence": cadence,
		"crouch": crouch_amt,
		"aim": aim_amt,
		"blend": move_blend,
		"twist": rad_to_deg(twist),
		"lean": lean_amt,
		"vault": vault_t,
	}


# =====================================================================
#  UPDATE
# =====================================================================

func _process(delta: float) -> void:
	# All procedural rigs update on render frames. Sample the physics body once
	# and keep the complete skeleton outside inherited physics interpolation.
	if not top_level:
		_render_scale = scale
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		top_level = true
	var body := get_parent() as Node3D
	global_transform = body.get_global_transform_interpolated().scaled_local(_render_scale)
	if hips == null:
		return
	# Preserve elapsed animation time at low FPS; small integration steps keep
	# recoil and hit springs stable without slowing reloads, vaults or deaths.
	var elapsed := minf(delta, 0.25)
	var steps := maxi(1, int(ceil(elapsed * 60.0)))
	for step in steps:
		_animate(elapsed / steps)


func _animate(delta: float) -> void:
	_time += delta
	if death_t >= 0.0:
		_update_death(delta)
		return
	if vault_t >= 0.0:
		vault_t += delta / _vault_dur
		if vault_t >= 1.0:
			vault_t = -1.0
			_hit_vel.x -= 1.6  # landing lurch
	if throw_t >= 0.0:
		throw_t += delta / _throw_dur
		if not _throw_released and throw_t >= 0.42:
			_throw_released = true
			_grenade_mesh.visible = false
			throw_release.emit()
		if throw_t >= 1.0:
			throw_t = -1.0
	if attack_t >= 0.0:
		attack_t += delta / _attack_dur
		if attack_t >= 1.0:
			attack_t = -1.0
	_update_state(delta)
	_update_body(delta)
	_update_weapon_pose(delta)
	_update_legs(delta)
	_update_arms(delta)


func _update_state(delta: float) -> void:
	crouch_amt = lerpf(crouch_amt, crouch_target, 1.0 - exp(-9.0 * delta))
	aim_amt = lerpf(aim_amt, aim_target, 1.0 - exp(-12.0 * ads_speed * delta))
	slide_amt = lerpf(slide_amt, slide_target, 1.0 - exp(-(14.0 if slide_target > slide_amt else 6.0) * delta))
	sprint_amt = lerpf(sprint_amt, sprint_target, 1.0 - exp(-7.0 * delta))
	var lt := 0.0 if (vault_t >= 0.0 or sprint_target > 0.5) else lean_target
	lean_amt = lerpf(lean_amt, lt, 1.0 - exp(-9.0 * delta))
	# weapon sway lag from aim angular velocity (critically damped spring)
	var aim_vel := wrapf(aim_yaw - _prev_aim_yaw, -PI, PI) / maxf(delta, 0.0001)
	_prev_aim_yaw = aim_yaw
	_sway_yaw_v += (-120.0 * _sway_yaw - 22.0 * _sway_yaw_v - aim_vel * 1.5) * delta
	_sway_yaw += _sway_yaw_v * delta
	_sway_yaw = clampf(_sway_yaw, -0.35, 0.35)

	# Smooth the physics samples before differentiating them. Otherwise render
	# frames alternate between zero acceleration and a one-tick impulse.
	_visual_velocity = _visual_velocity.lerp(Vector3(move_velocity.x, 0, move_velocity.z), 1.0 - exp(-14.0 * delta))
	var hv := _visual_velocity
	speed = hv.length()
	var acc := (hv - _prev_vel) / maxf(delta, 0.0001)
	_prev_vel = hv
	_acc_smooth = _acc_smooth.lerp(acc.limit_length(40.0), 1.0 - exp(-7.0 * delta))
	move_blend = lerpf(move_blend, clampf(speed / 0.8, 0.0, 1.0), 1.0 - exp(-12.0 * delta))

	# --- independent facing: choose how the legs orient relative to the aim ---
	if speed > 0.3:
		turning = false
		var move_yaw := atan2(-hv.x, -hv.z)
		var rel := wrapf(move_yaw - aim_yaw, -PI, PI)
		var target_rel: float
		if absf(rel) <= deg_to_rad(105.0):
			target_rel = clampf(rel, -0.95, 0.95)
		else:
			target_rel = clampf(wrapf(rel - PI, -PI, PI), -0.95, 0.95)
		lower_yaw = lerp_angle(lower_yaw, aim_yaw + target_rel, 1.0 - exp(-9.0 * delta))
	else:
		if absf(wrapf(aim_yaw - lower_yaw, -PI, PI)) > deg_to_rad(50.0):
			turning = true
		if turning:
			var diff := wrapf(aim_yaw - lower_yaw, -PI, PI)
			lower_yaw += clampf(diff, -5.0 * delta, 5.0 * delta)
			if absf(diff) < deg_to_rad(4.0):
				turning = false

	twist = wrapf(aim_yaw - lower_yaw, -PI, PI)
	var max_twist := deg_to_rad(80.0)
	if absf(twist) > max_twist:
		lower_yaw = wrapf(aim_yaw - signf(twist) * max_twist, -PI, PI)
		twist = signf(twist) * max_twist

	var lv := Basis(Vector3.UP, lower_yaw).inverse() * hv
	local_move = Vector2(lv.x, lv.z)

	# --- gait cycle ---
	if speed > 0.05:
		cadence = lerpf(cadence, (0.85 + speed * 0.2 + crouch_amt * 0.1) * (0.82 if zombie else 1.0), 1.0 - exp(-10.0 * delta))
		phase += cadence * TAU * delta
	elif turning:
		cadence = lerpf(cadence, 1.6, 1.0 - exp(-10.0 * delta))
		phase += cadence * TAU * delta
	else:
		cadence = lerpf(cadence, 0.0, 1.0 - exp(-8.0 * delta))
	phase = fmod(phase, TAU * 64.0)

	# --- readable state name (shown on the HUD) ---
	if turning and speed < 0.3:
		locomotion_state = "TURN IN PLACE"
	elif speed < 0.3:
		locomotion_state = "CROUCH IDLE" if crouch_target > 0.5 else ("AIM IDLE" if aim_target > 0.5 else "IDLE")
	elif crouch_target > 0.5:
		locomotion_state = "CROUCH WALK"
	elif sprint_target > 0.5:
		locomotion_state = "TACTICAL SPRINT"
	elif speed > 3.0:
		locomotion_state = "TACTICAL JOG"
	elif local_move.y > speed * 0.5:
		locomotion_state = "WALK BACKWARD"
	elif absf(local_move.x) > speed * 0.6:
		locomotion_state = "STRAFE " + ("RIGHT" if local_move.x > 0.0 else "LEFT")
	else:
		locomotion_state = "AIM WALK" if aim_target > 0.5 else "WALK"
	if slide_amt > 0.5:
		locomotion_state = "SLIDE"
	if vault_t >= 0.0:
		locomotion_state = "VAULT"
	elif absf(lean_target) > 0.5 and sprint_target < 0.5:
		locomotion_state += "  ·  PEEK " + ("RIGHT" if lean_target > 0.0 else "LEFT")
	if reload_t >= 0.0:
		locomotion_state += " + RELOAD"


func _run_factor() -> float:
	return clampf((speed - 2.0) / 5.0, 0.0, 1.0)


func _update_body(delta: float) -> void:
	var m := move_blend * (1.0 - slide_amt)
	var run := _run_factor()
	var lb := Basis(Vector3.UP, lower_yaw)
	var ab := Basis(Vector3.UP, aim_yaw)
	var stance := lerpf(0.62, 0.4, run)
	var steady := 1.0 - 0.75 * aim_amt

	# vault timeline weights
	var v_any := _vw(0.0, 0.12, 0.85, 1.0)
	var v_tuck := _vw(0.12, 0.38, 0.62, 0.88)
	var v_land := _vw(0.8, 0.9, 0.9, 1.0)
	var lift := 0.0
	if vault_t >= 0.0:
		lift = _vault_peak * pow(sin(PI * clampf((vault_t - 0.04) / 0.86, 0.0, 1.0)), 0.85)
	pivot.position.y = lift

	# hips: walking rises at mid-stance, running compresses at mid-stance
	var bob_amp := lerpf(0.022, 0.06, run) * m
	var bob := cos(2.0 * (phase - PI * stance)) * lerpf(1.0, -1.0, run)
	var hip_h := lerpf(HIP_STAND, HIP_CROUCH, crouch_amt) + bob * bob_amp - bob_amp - 0.05 * run
	if turning:
		hip_h -= 0.012 * (0.5 - 0.5 * cos(phase * 2.0))
	hip_h -= 0.24 * v_tuck + 0.14 * v_land
	hip_h = lerpf(hip_h, 0.42, slide_amt)
	if zombie_kind == "crawler":
		hip_h -= 0.15
	var sway := sin(phase) * lerpf(0.028, 0.012, run) * m
	var gait_yaw := sin(phase) * 0.12 * m * (1.0 - v_any) * steady
	hips.position = lb * Vector3(sway, 0, 0) + ab * Vector3(lean_amt * 0.2, 0, 0) + Vector3(0, hip_h, 0)
	hips.basis = lb * Basis(Vector3.BACK, sin(phase) * 0.045 * m - lean_amt * 0.08) * Basis(Vector3.UP, gait_yaw)

	# lean from velocity, acceleration (accelerate / sudden stop), crouch, sprint
	var la := lb.inverse() * _acc_smooth
	var pitch := (local_move.y * lerpf(0.02, 0.035, run) + la.z * 0.012) * steady
	pitch -= 0.3 * crouch_amt * (1.0 - slide_amt) + 0.1 * sprint_amt
	var roll := (-local_move.x * 0.02 - la.x * 0.008) * steady
	pitch = clampf(pitch, -0.65, 0.3)
	pitch = lerpf(pitch, 0.32, slide_amt)
	roll = clampf(roll, -0.25, 0.25)
	# vault: dive forward over the planted hand, lean onto the left arm
	pitch = lerpf(pitch, -0.55, v_tuck) - 0.2 * v_land
	roll += 0.32 * v_tuck
	if zombie:
		var strike := 0.0
		if attack_t >= 0.0:
			strike = smoothstep(0.3, 0.5, attack_t) * (1.0 - smoothstep(0.7, 1.0, attack_t))
		pitch -= (0.65 if zombie_kind == "crawler" else 0.32) + 0.35 * strike
		roll += sin(phase) * 0.12 * m + sin(_time * 0.7) * 0.05

	# hit reaction / landing spring
	_hit_vel += (-140.0 * _hit_off - 13.0 * _hit_vel) * delta
	_hit_off += _hit_vel * delta
	pitch += _hit_off.x
	roll += _hit_off.y

	# peek: roll around the aim axis (in lower-body space)
	var aim_fwd_axis := Basis(Vector3.UP, twist) * Vector3.BACK
	var breath := sin(_time * 1.6) * 0.018 * (1.0 - m * 0.7)
	spine.basis = Basis(aim_fwd_axis, -lean_amt * 0.36) * Basis.from_euler(Vector3(pitch * 0.5, 0, roll * 0.5)) \
			* Basis(Vector3.UP, twist * 0.45)
	chest.basis = Basis(Vector3.BACK, -lean_amt * 0.24) \
			* Basis.from_euler(Vector3(pitch * 0.5 + breath * steady, 0, roll * 0.5 - sin(phase) * 0.03 * m * steady)) \
			* Basis(Vector3.UP, twist * 0.55 - gait_yaw)
	chest.position.y = 0.22 + breath * 0.15
	head.basis = Basis.from_euler(Vector3(-pitch * 0.7 - 0.12 * aim_amt + 0.04, 0, -roll * 0.6 + lean_amt * 0.3))
	if zombie:
		head.basis = Basis.from_euler(Vector3(-pitch * 0.4 + 0.1, sin(_time * 1.3) * 0.25, 0.3 * sin(_time * 0.9)))
	if fp_mode:
		# Eye follows posture, peek and vault, without locomotion bob.
		var eye_h := lerpf(lerpf(1.66, 1.12, crouch_amt), 0.98, slide_amt) + lift - 0.12 * v_tuck - 0.07 * v_land - absf(lean_amt) * 0.05
		var want := Vector3(lean_amt * 0.45, eye_h, -0.09)
		_eye_smooth = _eye_smooth.lerp(want, 1.0 - exp(-12.0 * delta))
		# Hit/landing springs animate the body, never the player's view.
		# Recoil still changes fp_pitch through the player controller.
		var eb := ab * Basis(Vector3.RIGHT, fp_pitch) * Basis(Vector3.BACK, -lean_amt * 0.2)
		fp_eye = Transform3D(eb, global_transform * (ab * _eye_smooth))


func _pose(kind: String, n: String) -> Transform3D:
	var p: Array = POSES[kind][n]
	return Transform3D(Basis.from_euler(p[1]), p[0])


## First-person actions use eye space throughout, so blending into sprint or
## reload cannot reintroduce the animated chest's gait into the weapon.
func _weapon_pose(kind: String, pose_name: String) -> Transform3D:
	if not fp_mode:
		return _pose(kind, pose_name)
	var fp: Dictionary = FP_POSES[kind]
	var hip := Transform3D(Basis.from_euler(fp.hip[1]), fp.hip[0])
	return hip * _pose(kind, "ready").affine_inverse() * _pose(kind, pose_name)


func _update_weapon_pose(delta: float) -> void:
	if weapon == null:
		return
	var k := 260.0
	var c := 22.0
	_recoil_pos_v += (-k * _recoil_pos - c * _recoil_pos_v) * delta
	_recoil_pos += _recoil_pos_v * delta
	_recoil_rot_v += (-k * _recoil_rot - c * _recoil_rot_v) * delta
	_recoil_rot += _recoil_rot_v * delta
	_recoil_yaw_v += (-k * _recoil_yaw - c * _recoil_yaw_v) * delta
	_recoil_yaw += _recoil_yaw_v * delta

	var kind := "pistol" if weapon.is_pistol() else "rifle"
	var xf := _weapon_pose(kind, "ready").interpolate_with(_weapon_pose(kind, "aim"), aim_amt)
	if fp_mode:
		var fp: Dictionary = FP_POSES[kind]
		var hip := Transform3D(Basis.from_euler(fp.hip[1]), fp.hip[0])
		var ads := Transform3D(Basis.IDENTITY, weapon.ads_offset)
		xf = hip.interpolate_with(ads, aim_amt)
	xf = xf.interpolate_with(_weapon_pose(kind, "sprint_1h" if one_hand_sprint else "sprint"), sprint_amt * (1.0 - aim_amt))
	# third person only: first person keeps the gun gait-independent of the eye
	if one_hand_sprint and not fp_mode:
		# right arm swings forward with the left leg (counter to the free left arm)
		var sw_w := sprint_amt * (1.0 - aim_amt) * move_blend * (1.0 - slide_amt)
		var f := cos(phase)
		xf.origin += Vector3(0.0, maxf(f, 0.0) * 0.04, -f * 0.09) * sw_w
		xf = xf * Transform3D(Basis(Vector3.RIGHT, f * 0.18 * sw_w), Vector3.ZERO)

	if reload_t >= 0.0:
		reload_t += delta / _reload_dur
		var w := smoothstep(0.0, 0.12, reload_t) * (1.0 - smoothstep(0.86, 1.0, reload_t))
		xf = xf.interpolate_with(_weapon_pose(kind, "reload"), w)
	if switch_t >= 0.0:
		switch_t += delta / _switch_dur
		var w2 := smoothstep(0.0, 0.5, switch_t) * (1.0 - smoothstep(0.5, 1.0, switch_t))
		xf = xf.interpolate_with(_weapon_pose(kind, "lower"), w2)
		if switch_t >= 1.0:
			switch_t = -1.0
	xf = xf.interpolate_with(_weapon_pose(kind, "vault"), _vw(0.0, 0.18, 0.75, 0.95))
	xf = xf.interpolate_with(_weapon_pose(kind, "sprint"), slide_amt * (1.0 - aim_amt) * 0.6)
	if throw_t >= 0.0:
		xf = xf.interpolate_with(_weapon_pose(kind, "lower"), smoothstep(0.0, 0.18, throw_t) * (1.0 - smoothstep(0.75, 1.0, throw_t)) * 0.85)
	_update_cycle(delta)
	if cycle_t >= 0.0 and weapon.bolt != null:
		var cw := sin(PI * cycle_t)
		xf = xf * Transform3D(Basis.from_euler(Vector3(0.05 * cw, 0.1 * cw, 0.35 * cw)), Vector3.ZERO)

	# idle sway + gait bob on the gun
	var m := move_blend * (1.0 - slide_amt)
	var steady := 0.0 if fp_mode else 1.0 - aim_amt
	xf.origin.y += (sin(_time * 1.7) * 0.004 * (1.0 - m) + sin(phase * 2.0) * 0.012 * m) * steady
	xf.origin.x += sin(phase) * 0.01 * m * steady
	# turning inertia: the gun trails the aim and cants slightly
	var sw := 0.0 if fp_mode else _sway_yaw * (1.0 - aim_amt)
	xf = Transform3D(Basis.from_euler(Vector3(0, sw * 0.5, sw * 0.6)), Vector3(sw * 0.04, 0, 0)) * xf
	# peek: cant the weapon into the lean
	xf = xf * Transform3D(Basis(Vector3.BACK, -lean_amt * 0.35), Vector3.ZERO)
	# recoil: kick back, muzzle climb, random yaw
	xf = xf * Transform3D(Basis.from_euler(Vector3(_recoil_rot * 0.25, _recoil_yaw * 0.06, 0)),
			Vector3(0, 0, _recoil_pos))
	if fp_mode:
		xf = chest.global_transform.affine_inverse() * fp_eye * xf
	weapon_anchor.transform = xf


func _update_legs(delta: float) -> void:
	air_amt = lerpf(air_amt, air_target, 1.0 - exp(-12.0 * delta))
	var m := move_blend * (1.0 - slide_amt) * (1.0 - air_amt)
	var run := _run_factor()
	var stance := lerpf(0.62, 0.4, run)
	# stride amplitude chosen so the planted foot moves at ground speed (no sliding)
	var amp := clampf(speed * stance / (2.0 * maxf(cadence, 0.5)), 0.0, 0.5)
	var dir := local_move.normalized() if local_move.length() > 0.05 else Vector2.ZERO
	var lift_h := lerpf(0.11, 0.26, run) * m
	if turning:
		lift_h = maxf(lift_h, 0.08)
		amp = maxf(amp, 0.04)
	var v_tuck := _vw(0.1, 0.36, 0.62, 0.9)
	var lb := Basis(Vector3.UP, lower_yaw)
	var gx := pivot.global_transform
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var u := fposmod(phase / TAU + (0.0 if i == 0 else 0.5), 1.0)
		if m > 0.35 and _prev_u[i] > 0.8 and u < 0.2 and vault_t < 0.0 and slide_amt < 0.3:
			footstep.emit(feet[i].global_position, clampf(speed / 7.0, 0.15, 1.0))
		_prev_u[i] = u
		var along := 0.0
		var lift := 0.0
		var toe := 0.0
		if u < stance:
			var s := u / stance
			along = lerpf(amp, -amp, s)
			toe = -0.3 * smoothstep(0.7, 1.0, s)  # heel-off before push
		else:
			var s := (u - stance) / (1.0 - stance)
			along = lerpf(-amp, amp, s * s * (3.0 - 2.0 * s))
			lift = sin(PI * pow(s, 0.8)) * lift_h
			toe = 0.28 * sin(PI * s)
		var off := dir * along * m
		var width := HIP_HALF + 0.02 + 0.04 * crouch_amt
		var local := Vector3(side * width + off.x, ANKLE_H + lift, off.y)
		# relaxed staggered stance when idle (support foot forward), wider stance when peeking
		local.z += (0.07 if i == 1 else -0.05) * (1.0 - m) * (0.4 + 0.6 * maxf(aim_amt, crouch_amt))
		# peek: the foot on the lean side steps out, the other braces
		local.x += side * absf(lean_amt) * 0.08 + lean_amt * (0.2 if side * lean_amt > 0.0 else 0.04)
		# vault: both legs tuck up and swing past the right side of the obstacle
		var tuck := Vector3(0.24 + side * 0.09, ANKLE_H + 0.5, -0.12 + side * 0.08)
		local = local.lerp(tuck, v_tuck)
		# airborne: knees tuck, left leg leads
		var air_pose := Vector3(side * (HIP_HALF + 0.02), ANKLE_H + (0.36 if i == 0 else 0.22), -0.2 if i == 0 else 0.14)
		local = local.lerp(air_pose, air_amt)
		# slide: lead (left) leg extended along the floor, trailing leg folded under
		var slide_pose := Vector3(-0.07, ANKLE_H, -0.68) if i == 0 else Vector3(0.17, ANKLE_H + 0.03, 0.12)
		local = local.lerp(slide_pose, slide_amt)
		var target := gx * (lb * local)
		var pole := gx.basis * (lb * Vector3(side * 0.15 + 0.6 * v_tuck, 0.0, -1.0)).normalized()
		_solve_ik(thighs[i], shins[i], THIGH, SHIN, target, pole)
		var foot: Node3D = feet[i]
		foot.global_transform = Transform3D(gx.basis * lb * Basis(Vector3.RIGHT, toe * m), foot.global_position)


func _update_arms(delta: float) -> void:
	if zombie:
		_update_zombie_arms()
		return
	if weapon == null:
		return
	var cb := chest.global_transform.basis
	# First person: shoulders hang from the eye (like viewmodel arms), so a
	# chest pitched forward by crouch / slide never swings an upper arm across
	# the camera. Third person keeps the anatomical chest shoulders.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		if fp_mode:
			shoulders[i].global_position = fp_eye * Vector3(side * 0.18, -0.22, 0.1)
		else:
			shoulders[i].position = Vector3(side * 0.2, 0.21, 0)
	if fp_mode:
		cb = fp_eye.basis
	var r_xf: Transform3D = weapon.grip.global_transform
	if cycle_t >= 0.0 and weapon.bolt != null:
		var bw := smoothstep(0.0, 0.25, cycle_t) * (1.0 - smoothstep(0.75, 1.0, cycle_t))
		r_xf.origin = r_xf.origin.lerp(weapon.charge.global_position, bw)
	if throw_t >= 0.0:
		r_xf.origin = _throw_hand(r_xf.origin)
	var l_xf: Transform3D = weapon.support.global_transform
	var l_pos := l_xf.origin
	var l_basis := l_xf.basis
	if reload_t >= 0.0:
		_update_reload_events()
		if reload_t >= 0.0:
			l_pos = _reload_left_target(reload_t)
	# vault: left hand reaches for and plants on the obstacle top
	var plant_w := _vw(0.02, 0.2, 0.5, 0.68)
	if plant_w > 0.0:
		var palm := Basis(Vector3.UP, lower_yaw)
		l_pos = l_pos.lerp(_vault_plant + Vector3(0, 0.05, 0), plant_w)
		l_basis = l_basis.slerp(palm, plant_w)
	# one-handed sprint: left hand leaves the handguard and pumps with the stride
	var free_want := 0.0
	if one_hand_sprint and reload_t < 0.0 and throw_t < 0.0 and vault_t < 0.0:
		free_want = sprint_amt * (1.0 - aim_amt) * (1.0 - slide_amt)
	_free_arm = lerpf(_free_arm, free_want, 1.0 - exp(-14.0 * delta))
	var r_pole := Vector3(0.8, -1.0, 0.45).lerp(Vector3(0.35, -0.6, 1.0), _free_arm)
	var l_pole := Vector3(-0.9, -1.0, 0.15 + plant_w * 0.6).lerp(Vector3(-0.3, -0.6, 1.0), _free_arm)
	if _free_arm > 0.001:
		var f := -cos(phase) * move_blend  # left arm forward when the right leg is forward
		var pump := chest.global_transform * Vector3(-0.23, -0.14 + maxf(f, 0.0) * 0.13, -0.05 - f * 0.3)
		if fp_mode:
			# eye-relative but level (ignores view pitch): the hand swings up into
			# the bottom-left of the view at the front of each stride
			var lvl := global_transform.basis * Basis(Vector3.UP, aim_yaw)
			pump = fp_eye.origin + lvl * Vector3(-0.21, -0.5 + maxf(f, 0.0) * 0.3, -0.12 - f * 0.3)
		l_pos = l_pos.lerp(pump, _free_arm)
	_solve_ik(shoulders[1], elbows[1], UPPER_ARM, FOREARM, r_xf.origin, (cb * r_pole).normalized())
	_set_basis(hands[1], r_xf.basis)
	_solve_ik(shoulders[0], elbows[0], UPPER_ARM, FOREARM, l_pos, (cb * l_pole).normalized())
	if _free_arm > 0.001:
		l_basis = l_basis.orthonormalized().slerp(elbows[0].global_transform.basis.orthonormalized(), _free_arm)
	_set_basis(hands[0], l_basis)


## Bolt-action / pump-action cycling after each shot.
func _update_cycle(delta: float) -> void:
	if weapon.cycle_pending > 0.0:
		weapon.cycle_pending -= delta
		if weapon.cycle_pending <= 0.0:
			cycle_t = 0.0
			_cycle_dur = clampf(60.0 / float(weapon.stats.rpm) * 0.7, 0.35, 1.0)
			_cycle_cased = false
			Sfx.play(self, "bolt", weapon.global_position, -4.0)
	if cycle_t < 0.0:
		return
	cycle_t += delta / _cycle_dur
	var w := sin(PI * minf(cycle_t, 1.0))
	if weapon.bolt != null:
		weapon.bolt.position = Vector3(0, 0, 0.075 * w)
	if weapon.pump != null:
		weapon.pump.position = _pump_base + Vector3(0, 0, 0.09 * w)
	if not _cycle_cased and cycle_t > 0.5:
		_cycle_cased = true
		FX.casing(self, weapon.eject.global_position, weapon.global_transform.basis.x, false)
	if cycle_t >= 1.0:
		cycle_t = -1.0
		if weapon.bolt != null:
			weapon.bolt.position = Vector3.ZERO
		if weapon.pump != null:
			weapon.pump.position = _pump_base


func _update_zombie_arms() -> void:
	var cb := chest.global_transform.basis
	var co := chest.global_position
	var wind := 0.0
	var strike := 0.0
	if attack_t >= 0.0:
		wind = smoothstep(0.0, 0.3, attack_t) * (1.0 - smoothstep(0.3, 0.45, attack_t))
		strike = smoothstep(0.3, 0.5, attack_t) * (1.0 - smoothstep(0.75, 1.0, attack_t))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var reach := Vector3(side * 0.2, 0.1 + sin(_time * 2.3 + i * 1.7) * 0.06, -0.52 + sin(_time * 1.7 + i * 2.0) * 0.05)
		if zombie_kind == "crawler" and attack_t < 0.0:
			var crawl_phase := phase + i * PI
			var palm := global_position + Basis(Vector3.UP, aim_yaw) * Vector3(side * 0.25, 0.14 + maxf(sin(crawl_phase), 0.0) * 0.09 * move_blend, -0.36 + cos(crawl_phase) * 0.14 * move_blend)
			_solve_ik(shoulders[i], elbows[i], UPPER_ARM, FOREARM, palm, (cb * Vector3(side, -0.2, 0.3)).normalized())
			_set_basis(hands[i], Basis(Vector3.UP, aim_yaw))
			continue
		reach += Vector3(side * 0.08 * wind, 0.38 * wind - 0.3 * strike, 0.3 * wind - 0.08 * strike)
		_solve_ik(shoulders[i], elbows[i], UPPER_ARM, FOREARM, co + cb * reach, (cb * Vector3(side, -1.0, 0.3)).normalized())
		_set_basis(hands[i], cb * Basis(Vector3.RIGHT, -0.6 + strike))


func _update_reload_events() -> void:
	var t := reload_t
	if t >= 1.0:
		reload_t = -1.0
		hand_mag.visible = false
		weapon.mag_node.visible = true
		return
	var mag: Node3D = weapon.mag_node
	if t >= _reload_ev.out and mag.visible and t < _reload_ev.mag_in:
		mag.visible = false
		Sfx.play(self, "mag_out", mag.global_position, -8.0)
		if _reload_empty:
			FX.dropped_mag(self, mag, mag.global_transform)
		else:
			hand_mag.visible = true
	if t >= _reload_ev.pouch and t < _reload_ev.grab:
		hand_mag.visible = false
	elif t >= _reload_ev.grab and t < _reload_ev.mag_in:
		hand_mag.visible = true
	if t >= _reload_ev.mag_in and not mag.visible:
		mag.visible = true
		hand_mag.visible = false
		Sfx.play(self, "mag_in", mag.global_position, -6.0)
	if t >= _reload_ev.bolt and _reload_ev.bolt < 1.0:
		_reload_ev.bolt = 9.0
		Sfx.play(self, "bolt", weapon.charge.global_position, -6.0)


func _reload_left_target(t: float) -> Vector3:
	var hg: Vector3 = weapon.support.global_position
	var well: Vector3 = weapon.mag_well.global_position
	var pouch := chest.global_transform * Vector3(-0.07, -0.02, -0.25)
	var charge: Vector3 = weapon.charge.global_position
	var keys: Array
	if _reload_empty:
		keys = [[0.0, hg], [0.12, well], [0.2, well], [0.36, pouch], [0.46, pouch], [0.62, well],
				[0.7, well], [0.8, charge], [0.86, charge], [1.0, hg]]
	else:
		keys = [[0.0, hg], [0.14, well], [0.24, well], [0.42, pouch], [0.52, pouch], [0.7, well],
				[0.78, well], [1.0, hg]]
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var u := smoothstep(0.0, 1.0, (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001))
			return (a[1] as Vector3).lerp(b[1], u)
	return hg


# =====================================================================
#  DEATH
# =====================================================================

func _update_death(delta: float) -> void:
	death_t += delta
	var t := death_t
	# phase 1: knees buckle, legs still IK-planted
	if t < 0.45:
		var buckle := smoothstep(0.0, 0.4, t)
		hips.position.y = lerpf(_death_hip, 0.5, buckle)
		move_blend = lerpf(move_blend, 0.0, 1.0 - exp(-12.0 * delta))
		_update_legs(delta)
	# phase 2: body topples in the direction of the killing shot
	var f := clampf((t - 0.18) / 0.62, 0.0, 1.0)
	var fall := f * f
	if t > 0.8:
		fall = 1.0 + sin(clampf((t - 0.8) / 0.22, 0.0, 1.0) * PI) * 0.04
	var axis := Vector3.UP.cross(_death_dir).normalized()
	pivot.transform = Transform3D(Basis(axis, fall * 1.47), Vector3(0, 0.13 * minf(fall, 1.0), 0))
	# slump torso and head, limp arms
	var slump := smoothstep(0.0, 0.9, t)
	spine.basis = spine.basis.slerp(Basis.from_euler(Vector3(-0.35, 0.2, 0.15)), slump * 0.15)
	head.basis = head.basis.slerp(Basis.from_euler(Vector3(-0.5, 0.4, 0.3)), slump * 0.15)
	if t < 1.3:
		var down := pivot.global_transform.basis * Vector3.DOWN
		var cb := chest.global_transform.basis
		for i in 2:
			var side := -1.0 if i == 0 else 1.0
			var target: Vector3 = shoulders[i].global_position + down * 0.5 + cb * Vector3(side * 0.12, 0, -0.08)
			_solve_ik(shoulders[i], elbows[i], UPPER_ARM, FOREARM, target, (cb * Vector3(side, -0.5, 0.6)).normalized())
	if t > 3.0:
		set_process(false)


func _drop_weapon() -> void:
	var w := weapon
	weapon = null
	if w == null or not is_inside_tree():
		return
	var root := get_tree().current_scene
	var body := RigidBody3D.new()
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.06, 0.14, 0.24 if w.is_pistol() else 0.8)
	cs.shape = bs
	cs.position = Vector3(0, 0.04, -0.05 if w.is_pistol() else -0.15)
	body.add_child(cs)
	root.add_child(body)
	body.global_transform = w.global_transform
	w.reparent(body, true)
	body.reset_physics_interpolation()
	body.linear_velocity = _death_dir * randf_range(1.0, 2.2) + Vector3.UP * 1.2
	body.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))


# =====================================================================
#  IK
# =====================================================================

## Analytic two-bone IK in world space. Bones extend along their local -Y,
## and the joint bends toward `pole` (the bone's local -Z faces the pole).
func _solve_ik(upper: Node3D, lower: Node3D, l1: float, l2: float, target: Vector3, pole: Vector3) -> void:
	var a := upper.global_position
	var to := target - a
	var dist := to.length()
	var dir := to / dist if dist > 0.0001 else Vector3.DOWN
	var d := clampf(dist, 0.02, l1 + l2 - 0.001)
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var pole_dir := pole - dir * pole.dot(dir)
	if pole_dir.length_squared() < 1e-6:
		pole_dir = dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	pole_dir = pole_dir.normalized()
	var joint := a + dir * (l1 * cos_a) + pole_dir * (l1 * sqrt(maxf(0.0, 1.0 - cos_a * cos_a)))
	var end := a + dir * d
	upper.global_transform = Transform3D(_basis_from_down(joint - a, pole_dir), a)
	lower.global_transform = Transform3D(_basis_from_down(end - joint, pole_dir), joint)


func _basis_from_down(down: Vector3, front: Vector3) -> Basis:
	var y := -down.normalized()
	var z := -(front - y * front.dot(y))
	if z.length_squared() < 1e-6:
		z = y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


func _set_basis(n: Node3D, b: Basis) -> void:
	n.global_transform = Transform3D(b.orthonormalized(), n.global_position)
