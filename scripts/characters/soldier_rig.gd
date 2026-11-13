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
const ModelSkin = preload("res://scripts/characters/model_skin.gd")

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
		"ready": [Vector3(0.09, -0.07, -0.25), Vector3(-0.34, 0.14, 0.06)],
		"aim": [Vector3(0.08, 0.075, -0.24), Vector3(0.0, 0.0, 0.0)],
		"sprint": [Vector3(0.05, -0.03, -0.25), Vector3(0.78, 0.42, -0.35)],
		"sprint_1h": [Vector3(0.27, -0.23, -0.2), Vector3(-0.42, 0.04, 0.12)],
		"reload": [Vector3(0.07, -0.03, -0.3), Vector3(0.22, 0.38, 0.6)],
		"lower": [Vector3(0.2, -0.32, -0.12), Vector3(-1.15, 0.2, 0.0)],
		"vault": [Vector3(0.26, 0.12, -0.08), Vector3(1.1, -0.35, -0.7)],
	},
	"knife": {
		"ready": [Vector3(0.16, -0.06, -0.34), Vector3(-0.15, 0.18, -0.12)],
		"aim": [Vector3(0.16, -0.06, -0.34), Vector3(-0.15, 0.18, -0.12)],
		"sprint": [Vector3(0.2, -0.24, -0.18), Vector3(-0.45, 0.1, 0.0)],
		"sprint_1h": [Vector3(0.24, -0.26, -0.16), Vector3(-0.5, 0.1, 0.1)],
		"reload": [Vector3(0.16, -0.06, -0.34), Vector3(-0.15, 0.18, -0.12)],
		"lower": [Vector3(0.2, -0.34, -0.06), Vector3(-1.2, 0.0, 0.0)],
		"vault": [Vector3(0.24, 0.0, -0.12), Vector3(0.5, -0.3, -0.4)],
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
## "sprint": carried across the body, muzzle low and canted (rifle), or
## tucked down by the chest (pistol).
const FP_POSES := {
	"rifle": {"hip": [Vector3(0.16, -0.2, -0.34), Vector3(0.04, 0.06, 0.04)], "aim": [Vector3(0.0, -0.15, -0.19), Vector3.ZERO],
			"sprint": [Vector3(0.1, -0.245, -0.31), Vector3(-0.38, 0.74, 0.55)]},
	"knife": {"hip": [Vector3(0.16, -0.21, -0.3), Vector3(-0.05, 0.3, -0.2)], "aim": [Vector3(0.16, -0.21, -0.3), Vector3(-0.05, 0.3, -0.2)],
			"sprint": [Vector3(0.19, -0.27, -0.28), Vector3(-0.45, 0.25, 0.1)]},
	"pistol": {"hip": [Vector3(0.13, -0.15, -0.36), Vector3(0.03, 0.05, 0.0)], "aim": [Vector3(0.0, -0.077, -0.4), Vector3.ZERO],
			"sprint": [Vector3(0.14, -0.22, -0.31), Vector3(-0.62, 0.32, 0.28)]},
}
## First-person gait motion on the gun: [side sway, footfall dip, roll, pitch]
## at a walk and at a full sprint.
const FP_GAIT_WALK := [0.006, 0.007, 0.018, 0.012]
const FP_GAIT_SPRINT := [0.028, 0.03, 0.075, 0.05]

# ---- inputs, written by the owning character every frame ----
var move_velocity := Vector3.ZERO
var aim_yaw := 0.0
var crouch_target := 0.0
var aim_target := 0.0
var sprint_target := 0.0
var air_target := 0.0
## dropkick timeline (0..1, -1 = idle): tip back flat, tuck both knees, both legs out, recover
var kick_t := -1.0
var _kick_dur := 0.56
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
## Cosmetic only: combat/movement can interrupt at any point with no lockout.
var inspect_t := -1.0
## Starting duration: two readable holds in 2.6 s. Regression checks require
## completion at every tested frame rate; shorten if the holds feel sluggish.
const INSPECT_DURATION := 2.6
var death_t := -1.0
var _death_dir := Vector3.FORWARD
var _death_hip := HIP_STAND
## Random roll onto one side as the body lands (radians), and which knee stays bent.
var _death_roll := 0.0
var _death_knee := 0
## Falling backwards (shot from the front): the spine relaxes back instead of curling.
var _death_back := true

# nodes
var pivot: Node3D
var hips: Node3D
var spine: Node3D
var chest: Node3D
var head: Node3D
## Detachable helmet (null when the palette has no helmet or it was knocked off).
var helmet_node: Node3D
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
## Skinned model that copies this rig's pose (null = procedural body is drawn).
var model_skin: ModelSkin
var _body_meshes: Array[MeshInstance3D] = []


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
	_mesh(chest, ML.rbox(Vector3(0.07, 0.11, 0.08)), p.get("ifak", M.solid(Color(0.45, 0.08, 0.06), 0.8)), Vector3(0.205, -0.02, 0.07))
	# assault backpack with bedroll and side pouches
	_mesh(chest, ML.rbox(Vector3(0.31, 0.38, 0.17)), gear, Vector3(0, 0.1, 0.25))
	_mesh(chest, ML.rbox(Vector3(0.24, 0.16, 0.04)), vest, Vector3(0, 0.03, 0.345))
	_mesh(chest, ML.capsule(0.07, 0.36), p.get("bedroll", M.fabric("bedroll", Color(0.25, 0.27, 0.2))), Vector3(0, 0.33, 0.23), Vector3(0, 0, PI * 0.5))
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
	_build_details(p)


## Second pass of gear detail shared by every soldier: webbing, pads, cuffs,
## boot shaping and belt kit. Purely visual (no new joints).
func _build_details(p: Dictionary) -> void:
	var vest: Material = p.vest
	var gear: Material = p.gear
	var detail: Material = p.detail
	var strap := M.fabric("webbing_strap", Color(0.13, 0.13, 0.11), 9.0)
	# plate carrier: MOLLE webbing on the cummerbund, padded shoulder straps, drag handle
	for side in [-1, 1]:
		for i in 3:
			_mesh(chest, ML.rbox(Vector3(0.012, 0.014, 0.2)), strap, Vector3(side * 0.212, -0.02 - i * 0.04, 0.0))
		_mesh(chest, ML.rbox(Vector3(0.095, 0.03, 0.16)), vest, Vector3(side * 0.125, 0.268, 0.0))
		_mesh(chest, ML.rbox(Vector3(0.03, 0.2, 0.014)), strap, Vector3(side * 0.12, 0.13, -0.17))
	for i in 2:
		_mesh(chest, ML.rbox(Vector3(0.3, 0.014, 0.012)), strap, Vector3(0, 0.2 + i * 0.045, -0.169))
	_mesh(chest, ML.rbox(Vector3(0.11, 0.022, 0.03)), strap, Vector3(0, 0.275, 0.135))
	# shemagh / neck wrap: hides the neck seam and softens the silhouette
	var wrap: Material = p.get("wrap", M.fabric("neck_wrap", Color(0.34, 0.33, 0.25), 7.0))
	_mesh(chest, ML.cylinder(0.07, 0.092, 0.075, 14), wrap, Vector3(0, 0.305, 0.0))
	_mesh(chest, ML.sphere(0.06, false, 10), wrap, Vector3(0.0, 0.285, -0.075), Vector3.ZERO, Vector3(1.5, 0.75, 0.7))
	# arms: rounded elbow pads, glove cuffs, wrist GPS on the support arm
	for i in 2:
		_mesh(elbows[i], ML.sphere(0.052, false, 10), detail, Vector3(0, -0.012, -0.05), Vector3.ZERO, Vector3(1.0, 1.25, 0.55))
		_mesh(elbows[i], ML.cylinder(0.06, 0.064, 0.055, 12), p.gloves, Vector3(0, -FOREARM + 0.035, 0))
		_mesh(hands[i], ML.rbox(Vector3(0.076, 0.03, 0.06)), detail, Vector3(0, -0.02, -0.03))
	_mesh(elbows[0], ML.rbox(Vector3(0.052, 0.04, 0.016)), M.solid(Color(0.05, 0.06, 0.06), 0.25, 0.4), Vector3(0, -0.2, -0.058))
	_mesh(elbows[0], ML.rbox(Vector3(0.036, 0.026, 0.004)), M.emissive("wrist_gps", Color(0.2, 0.9, 0.5), 0.9), Vector3(0, -0.2, -0.068))
	# legs: knee caps, pocket flaps, boot collars and toe caps
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_mesh(shins[i], ML.sphere(0.07, false, 10), detail, Vector3(0, -0.035, -0.062), Vector3.ZERO, Vector3(0.95, 1.2, 0.55))
		_mesh(shins[i], ML.cylinder(0.078, 0.084, 0.07, 12), p.boots, Vector3(0, -SHIN + 0.075, 0))
		_mesh(thighs[i], ML.rbox(Vector3(0.022, 0.014, 0.125)), strap, Vector3(side * 0.112, -0.185, 0))
		_mesh(thighs[i], ML.cylinder(0.094, 0.094, 0.02, 12), strap, Vector3(0, -0.11, 0))
		_mesh(feet[i], ML.sphere(0.062, false, 10), p.boots, Vector3(0, -0.032, -0.165), Vector3.ZERO, Vector3(0.95, 0.78, 1.0))
		_mesh(feet[i], ML.rbox(Vector3(0.09, 0.012, 0.07)), strap, Vector3(0, 0.02, -0.07))
	# belt kit: dump pouch, knife, magazine pouch
	_mesh(hips, ML.rbox(Vector3(0.1, 0.14, 0.075)), gear, Vector3(-0.1, -0.035, 0.155))
	_mesh(hips, ML.rbox(Vector3(0.03, 0.17, 0.028)), detail, Vector3(0.195, -0.075, 0.02))
	_mesh(hips, ML.rbox(Vector3(0.022, 0.05, 0.022)), M.solid(Color(0.3, 0.3, 0.3), 0.3, 0.8), Vector3(0.195, 0.03, 0.02))
	_mesh(hips, ML.rbox(Vector3(0.06, 0.11, 0.035)), gear, Vector3(0.1, -0.01, -0.145))


func _build_headgear(h: Node3D, p: Dictionary) -> void:
	var detail: Material = p.detail
	match String(p.headgear):
		"helmet":
			var hm: Material = p.helmet
			var hg := h
			h = _node(hg, "Helmet", Vector3.ZERO)
			helmet_node = h
			_mesh(h, ML.sphere(0.145, true, 20), hm, Vector3(0, 0.015, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
			_mesh(h, ML.cylinder(0.147, 0.15, 0.04, 20), hm, Vector3(0, 0.0, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
			_mesh(h, ML.rbox(Vector3(0.055, 0.045, 0.03)), detail, Vector3(0, 0.08, -0.16))
			for side in [-1, 1]:
				_mesh(h, ML.rbox(Vector3(0.022, 0.03, 0.15)), detail, Vector3(side * 0.142, 0.03, 0))
				_mesh(h, ML.cylinder(0.05, 0.05, 0.045, 12), detail, Vector3(side * 0.115, -0.02, 0.0), Vector3(0, 0, PI * 0.5))
			_mesh(h, ML.rbox(Vector3(0.08, 0.05, 0.035)), detail, Vector3(0, 0.07, 0.16))
			_mesh(h, ML.rbox(Vector3(0.2, 0.012, 0.012)), detail, Vector3(0, 0.1, -0.02))
			# chin strap + cup, boom microphone, side velcro patches
			var web := M.fabric("webbing_strap", Color(0.13, 0.13, 0.11), 9.0)
			for side in [-1, 1]:
				_mesh(h, ML.rbox(Vector3(0.01, 0.115, 0.018)), web, Vector3(side * 0.092, -0.065, -0.035), Vector3(-0.35, 0, 0))
				_mesh(h, ML.rbox(Vector3(0.006, 0.04, 0.05)), M.solid(Color(0.25, 0.27, 0.2), 0.9), Vector3(side * 0.148, 0.075, 0.045))
			_mesh(h, ML.rbox(Vector3(0.07, 0.018, 0.03)), web, Vector3(0, -0.118, -0.062))
			_mesh(h, ML.cylinder(0.004, 0.004, 0.11, 6), detail, Vector3(-0.105, -0.06, -0.06), Vector3(1.25, 0, 0.25))
			_mesh(h, ML.sphere(0.012, false, 8), detail, Vector3(-0.075, -0.075, -0.108))
			if p.get("nvg", false):
				# flip-up binocular night vision on the shroud
				_mesh(h, ML.rbox(Vector3(0.03, 0.06, 0.03)), detail, Vector3(0, 0.115, -0.165))
				for sx in [-1, 1]:
					_mesh(h, ML.cylinder(0.021, 0.024, 0.085, 12), detail, Vector3(sx * 0.03, 0.175, -0.15), Vector3(0.5, 0, 0))
					_mesh(h, ML.cylinder(0.019, 0.019, 0.006, 12), M.solid(Color(0.1, 0.25, 0.18), 0.1, 0.6), Vector3(sx * 0.03, 0.212, -0.129), Vector3(0.5, 0, 0))
			h = hg
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

## Swaps the procedural body for a skinned character model (see model_skin.gd).
## The rig keeps animating invisibly and the model copies its pose; guns,
## the hand magazine and grenade stay on the rig's (invisible) hands.
func use_model(path: String, tint: Color = Color.WHITE, hide_meshes: Array = []) -> bool:
	var s := ModelSkin.new()
	s.name = "ModelSkin"
	s.process_priority = 50   # after this rig animates
	add_child(s)
	if not s.setup(self, path, tint, hide_meshes):
		s.queue_free()
		return false
	model_skin = s
	_body_meshes.clear()
	for n in pivot.find_children("*", "MeshInstance3D", true, false):
		if _is_gear(n):
			continue
		_body_meshes.append(n)
	_apply_model_visibility()
	return true


## Fuses the static meshes that share a bone and a material into one mesh, so
## a body draws ~35 parts instead of ~100 (and as many fewer shadow passes).
## Bones keep animating: only meshes that never move relative to their bone
## are merged. Merged meshes are cached, since most bodies share geometry.
static var _merge_cache := {}

func merge_static_parts(exclude: Array = []) -> int:
	var groups := {}
	for n in pivot.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi in exclude or _is_gear(mi) or mi.get_child_count() > 0 or not mi.visible:
			continue
		if mi.mesh == null or mi.mesh.get_surface_count() != 1 or mi.material_override == null or mi.material_overlay != null:
			continue
		var key := "%d|%d|%d" % [mi.get_parent().get_instance_id(), mi.material_override.get_instance_id(), mi.cast_shadow]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	var removed := 0
	for key in groups:
		var parts: Array = groups[key]
		if parts.size() < 2:
			continue
		var first := parts[0] as MeshInstance3D
		var parent := first.get_parent()
		var sig := ""
		for mi in parts:
			sig += "%d%s;" % [mi.mesh.get_instance_id(), mi.transform]
		var h := sig.hash()
		var mesh: Mesh = _merge_cache.get(h)
		if mesh == null:
			var st := SurfaceTool.new()
			for mi in parts:
				st.append_from(mi.mesh, 0, mi.transform)
			mesh = st.commit()
			if _merge_cache.size() > 400:
				_merge_cache.clear()
			_merge_cache[h] = mesh
		var merged := MeshInstance3D.new()
		merged.name = "Merged"
		merged.mesh = mesh
		merged.material_override = first.material_override
		merged.cast_shadow = first.cast_shadow
		# the fused mesh fades at the farthest range of its parts (0 = never)
		var fade := 0.0
		for mi in parts:
			if mi.visibility_range_end <= 0.0:
				fade = 0.0
				break
			fade = maxf(fade, mi.visibility_range_end)
		merged.visibility_range_end = fade
		merged.layers = first.layers
		merged.gi_mode = first.gi_mode
		parent.add_child(merged)
		for mi in parts:
			parent.remove_child(mi)
			mi.queue_free()
			removed += 1
		removed -= 1
	return removed


## Guns, the hand magazine and the grenade are not part of the body.
func _is_gear(n: Node) -> bool:
	if n == _grenade_mesh:
		return true
	var p := n.get_parent()
	while p != null and p != self:
		if p is Weapon or p == hand_mag:
			return true
		p = p.get_parent()
	return false


func _apply_model_visibility() -> void:
	if model_skin == null:
		return
	model_skin.set_first_person(fp_mode)
	var arm_roots: Array = shoulders
	for mi in _body_meshes:
		if not is_instance_valid(mi):
			continue
		var on_arm := false
		for sh in arm_roots:
			if (sh as Node).is_ancestor_of(mi):
				on_arm = true
				break
		# first person keeps the rig's arms (they hold the gun up to the eye)
		mi.visible = fp_mode and on_arm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
	_apply_model_visibility()


## Shot-off limb: every mesh from `bone` down is copied onto a tumbling
## physics body and hidden on the rig; a dark stump caps the joint. The rig
## keeps animating the (now invisible) bones, so nothing else changes.
func sever(bone: Node3D, dir: Vector3) -> void:
	if bone == null or not is_inside_tree() or bone.has_meta("severed"):
		return
	bone.set_meta("severed", true)
	var meshes: Array = bone.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return
	var xf := bone.global_transform
	var inv := xf.affine_inverse()
	var body := RigidBody3D.new()
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.DEBRIS
	body.mass = 3.0
	body.angular_damp = 1.5
	body.linear_damp = 0.4
	var box := AABB()
	var first := true
	for n in meshes:
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = mi.material_override
		copy.transform = inv * mi.global_transform
		body.add_child(copy)
		var a: AABB = copy.transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
		mi.visible = false
	if first:
		body.free()
		return
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(minf(box.size.x, box.size.z) * 0.5, 0.04, 0.12)
	cap.height = maxf(box.size.y, cap.radius * 2.0 + 0.01)
	cs.shape = cap
	cs.position = box.get_center()
	body.add_child(cs)
	get_tree().current_scene.add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	body.reset_physics_interpolation()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	body.linear_velocity = flat * randf_range(1.5, 3.0) + Vector3.UP * randf_range(1.2, 2.4)
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 9.0
	# bloody stump where the limb was
	var stump := MeshInstance3D.new()
	stump.mesh = ML.sphere(0.055, false, 10)
	stump.material_override = M.solid(Color(0.32, 0.03, 0.03), 0.35)
	bone.get_parent().add_child(stump)
	stump.position = bone.position
	stump.scale = Vector3(1.0, 0.7, 1.0)
	get_tree().create_timer(14.0).timeout.connect(func():
		if is_instance_valid(body):
			body.queue_free())


## Knocks the helmet off: it tumbles away as debris and despawns.
func drop_helmet(dir: Vector3) -> void:
	if helmet_node == null or not is_inside_tree():
		return
	var hn := helmet_node
	helmet_node = null
	var xf := hn.global_transform
	var body := RigidBody3D.new()
	body.collision_layer = 8    # Layers.DEBRIS
	body.collision_mask = 1 | 8
	body.mass = 1.2
	body.angular_damp = 1.0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.13
	cs.shape = sh
	body.add_child(cs)
	var root := get_tree().current_scene
	hn.get_parent().remove_child(hn)
	body.add_child(hn)
	hn.transform = Transform3D.IDENTITY
	for n in hn.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(n as MeshInstance3D).visible = true   # hidden while worn when a model skin is used
	root.add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	body.reset_physics_interpolation()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	body.linear_velocity = flat * randf_range(2.5, 4.0) + Vector3.UP * randf_range(2.5, 3.5)
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 10.0
	get_tree().create_timer(12.0).timeout.connect(func():
		if is_instance_valid(body):
			body.queue_free())


func snap_yaw(yaw: float) -> void:
	aim_yaw = yaw
	lower_yaw = yaw


func set_weapon(active: Weapon, others: Array) -> void:
	cancel_inspect()
	weapon = active
	cycle_t = -1.0
	_pump_base = active.pump.position if active.pump != null else Vector3.ZERO
	_attach(active, weapon_anchor)
	for w in others:
		_attach(w, _knife_slot() if w.is_melee() else (thigh_slot if w.is_pistol() else back_slot))
	for c in hand_mag.get_children():
		c.queue_free()
	if active.mag_node:
		var copy := active.mag_node.duplicate() as Node3D
		copy.position = Vector3.ZERO
		hand_mag.add_child(copy)
	hand_mag.visible = false


## Sheath on the front-left of the vest, blade down.
var knife_slot: Node3D


func _knife_slot() -> Node3D:
	if knife_slot == null:
		knife_slot = _node(chest, "KnifeSlot", Vector3(-0.15, -0.02, -0.16))
		knife_slot.rotation = Vector3(PI, 0.0, 0.15)   # blade (up in the hand) points down in the sheath
	return knife_slot


func _attach(n: Node3D, parent: Node3D) -> void:
	if n.get_parent() == null:
		parent.add_child(n)
	elif n.get_parent() != parent:
		n.reparent(parent, false)
	n.transform = Transform3D.IDENTITY
	n.reset_physics_interpolation()


func add_recoil(strength: float) -> void:
	cancel_inspect()
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
	cancel_inspect()
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
	cancel_inspect()
	switch_t = 0.0
	_switch_dur = duration


## Side vault: left hand plants on `plant` (world), legs tuck to the right.
func play_vault(duration: float, obstacle_top: float, plant: Vector3) -> void:
	cancel_inspect()
	vault_t = 0.0
	_vault_dur = maxf(duration, 0.2)
	_vault_peak = maxf(obstacle_top - 0.42, 0.18)
	_vault_plant = plant
	cancel_reload()


func play_kick(duration: float) -> void:
	cancel_inspect()
	kick_t = 0.0
	_kick_dur = maxf(duration, 0.2)
	cancel_reload()


## Whole-body weight of the kick pose (eases in and out).
func _kick_w() -> float:
	if kick_t < 0.0:
		return 0.0
	return smoothstep(0.0, 0.14, kick_t) * (1.0 - smoothstep(0.76, 1.0, kick_t))


## 0 = knee chambered, 1 = leg fully extended (the strike).
func _kick_ext() -> float:
	if kick_t < 0.0:
		return 0.0
	return smoothstep(0.16, 0.32, kick_t) * (1.0 - smoothstep(0.6, 0.82, kick_t))


func play_attack(duration: float) -> void:
	attack_t = 0.0
	_attack_dur = maxf(duration, 0.2)


func play_throw(duration: float) -> void:
	cancel_inspect()
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
	cancel_inspect()
	dead = true
	death_t = 0.0
	vault_t = -1.0
	_death_hip = hips.position.y
	var d := Vector3(dir.x, 0, dir.z)
	_death_dir = d.normalized() if d.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	_death_roll = randf_range(0.25, 0.6) * (1.0 if randf() < 0.5 else -1.0)
	_death_knee = randi() % 2
	var facing := -chest.global_transform.basis.z
	_death_back = Vector3(facing.x, 0, facing.z).normalized().dot(_death_dir) < 0.0
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

## AI bodies animate less often when far away or off screen (set by
## soldier.optimize_detail). The body still follows its physics position
## every frame; only the pose updates are spread out.
var lod_enabled := false
var _lod_acc := 0.0
var _lod_phase := randi() % 12
static var _lod_cam: Camera3D
static var _lod_cam_frame := -1
const LOD_NEAR := 18.0     # full rate inside this distance
const LOD_MID := 35.0      # every 2nd frame up to here, every 3rd beyond
const LOD_HIDDEN := 40.0   # off screen: every 4th frame, every 6th beyond this


func _lod_interval() -> int:
	var f := Engine.get_process_frames()
	if f != _lod_cam_frame:
		_lod_cam_frame = f
		_lod_cam = get_viewport().get_camera_3d()
	if _lod_cam == null:
		return 1
	var p := global_position
	var d := _lod_cam.global_position.distance_to(p)
	if d < LOD_NEAR:
		return 1
	if not _lod_cam.is_position_in_frustum(p + Vector3.UP):
		return 4 if d < LOD_HIDDEN else 6
	return 2 if d < LOD_MID else 3


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
	if lod_enabled:
		_lod_acc += delta
		var every := _lod_interval()
		if every > 1 and (Engine.get_process_frames() + _lod_phase) % every != 0:
			return
		delta = _lod_acc
		_lod_acc = 0.0
	# Preserve elapsed animation time at low FPS; small integration steps keep
	# recoil and hit springs stable without slowing reloads, vaults or deaths.
	var elapsed := minf(delta, 0.25)
	# at most 3 sub-steps: when the game is already slow, extra animation
	# passes on every body would only make the next frame slower still
	var steps := clampi(int(ceil(elapsed * 60.0)), 1, 3)
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
	if kick_t >= 0.0:
		kick_t += delta / _kick_dur
		if kick_t >= 1.0:
			kick_t = -1.0
			_hit_vel.x -= 1.1  # absorb the landing
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
	aim_amt = lerpf(aim_amt, aim_target, 1.0 - exp(-16.0 * ads_speed * delta))
	slide_amt = lerpf(slide_amt, slide_target, 1.0 - exp(-(14.0 if slide_target > slide_amt else 6.0) * delta))
	# Starting value: match ADS response on sprint exit so the gun is ready
	# within 0.2 s (residual < 5%); increase exit rate if that check fails.
	var sprint_rate := 16.0 if sprint_target < sprint_amt else 7.0
	sprint_amt = lerpf(sprint_amt, sprint_target, 1.0 - exp(-sprint_rate * delta))
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
	# dropkick: the whole body tips back until it lies flat in the air (like
	# sleeping on its back), rotating around the hips and riding a little higher
	var dk := _kick_w()
	if dk > 0.0:
		var hc := Vector3(0, HIP_STAND, 0)
		var tip := Basis(lb * Vector3.RIGHT, 1.25 * dk)
		pivot.transform = Transform3D(tip, Vector3(0, lift + 0.22 * dk, 0) + hc - tip * hc)
	else:
		pivot.transform = Transform3D(Basis.IDENTITY, Vector3(0, lift, 0))

	# hips: walking rises at mid-stance, running compresses at mid-stance
	var bob_amp := lerpf(0.022, 0.06, run) * m
	var bob := cos(2.0 * (phase - PI * stance)) * lerpf(1.0, -1.0, run)
	var hip_h := lerpf(HIP_STAND, HIP_CROUCH, crouch_amt) + bob * bob_amp - bob_amp - 0.05 * run
	if turning:
		hip_h -= 0.012 * (0.5 - 0.5 * cos(phase * 2.0))
	hip_h -= 0.24 * v_tuck + 0.14 * v_land
	hip_h += 0.07 * _kick_w()
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
	pitch = lerpf(pitch, lerpf(-0.5, -0.25, _kick_ext()), _kick_w())   # chin tucked toward the target
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


## Knife slash, alternating forehand and backhand.
var slash_t := -1.0
var _slash_dur := 0.45
var _slash_side := 1.0
## Blade bites in: the swing holds at contact for a moment and jolts.
var _slash_hold := 0.0
var _slash_jolt := 0.0


func play_slash(duration: float) -> void:
	cancel_inspect()
	slash_t = 0.0
	_slash_dur = clampf(duration * 0.85, 0.3, 0.6)
	_slash_side = -_slash_side
	_slash_hold = 0.0
	_slash_jolt = 0.0


## The slash connected: hold the blade at contact and shake it (heavier on a kill).
func slash_impact(heavy: bool) -> void:
	if slash_t < 0.0:
		return
	slash_t = maxf(slash_t, 0.16)   # make sure the blade is through the centre
	_slash_hold = 0.075 if heavy else 0.05
	_slash_jolt = 1.0 if heavy else 0.7


## Snap back across the body, an accelerating cut that lunges through the
## centre, follow-through past it, then recover. Damage lands on the click, so
## the wind-up is kept very short and the blade crosses the centre almost at
## once. Offsets are in the pose's parent space (chest, or eye in first person).
func _slash_pose(base: Transform3D, u: float) -> Transform3D:
	var s := _slash_side
	var wind := Transform3D(Basis.from_euler(Vector3(-0.5, s * 1.2, s * 0.85)), Vector3(s * 0.21, 0.1, 0.1))
	var cut := Transform3D(Basis.from_euler(Vector3(0.12, -s * 0.15, -s * 0.2)), Vector3(-s * 0.02, -0.02, -0.27))
	var through := Transform3D(Basis.from_euler(Vector3(0.45, -s * 1.15, -s * 0.8)), Vector3(-s * 0.25, -0.11, -0.12))
	var off: Transform3D
	if u < 0.06:
		var k := 1.0 - pow(1.0 - u / 0.06, 2.0)                 # snap out to the wind-up
		off = Transform3D.IDENTITY.interpolate_with(wind, k)
	elif u < 0.17:
		off = wind.interpolate_with(cut, pow((u - 0.06) / 0.11, 2.2))   # accelerating cut
	elif u < 0.34:
		off = cut.interpolate_with(through, 1.0 - pow(1.0 - (u - 0.17) / 0.17, 3.0))   # follow-through
	else:
		off = through
	if _slash_jolt > 0.0:
		var j := _slash_jolt * 0.05
		off = off * Transform3D(Basis.from_euler(Vector3(randf_range(-j, j), randf_range(-j, j), randf_range(-j, j) * 2.0)), Vector3.ZERO)
	var w := 1.0 - smoothstep(0.34, 1.0, u)
	var t := Transform3D(Basis.IDENTITY, off.origin * w) * base
	return Transform3D(t.basis * Basis.IDENTITY.slerp(off.basis, w), t.origin)


func play_inspect() -> bool:
	if weapon == null or dead or inspect_t >= 0.0 or reload_t >= 0.0 or switch_t >= 0.0 \
			or throw_t >= 0.0 or vault_t >= 0.0 or kick_t >= 0.0 or cycle_t >= 0.0 \
			or aim_target > 0.0 or sprint_target > 0.0 or slide_target > 0.0:
		return false
	inspect_t = 0.0
	return true


func cancel_inspect() -> void:
	if inspect_t < 0.0:
		return
	inspect_t = -1.0
	# Update the muzzle immediately, before the same physics tick can fire.
	if weapon != null and is_inside_tree():
		_update_weapon_pose(0.0)
		_update_arms(0.0)


## Lift, hold the receiver side, roll to show the opposite side, return.
## The hand targets remain attached to the gun; the eye never follows it.
## Starting pose offsets: both receiver sides must stay inside the camera,
## with positive eye-space clearance. Reduce angles if long guns clip hands.
## Inspect keys: [t, position, euler]. The rest pose is the first and last
## key; between them the gun is shown right side, rolled to the left side,
## then tipped up to check the underside. Pairs of close keys keep it
## drifting instead of freezing in place. Positions are eye-relative.
const INSPECT_KEYS := {
	"rifle": [
		[0.13, Vector3(0.160, -0.100, -0.396), Vector3(0.1, 1.05, -0.3)],
		[0.3, Vector3(0.172, -0.088, -0.410), Vector3(0.05, 1.18, -0.38)],
		[0.45, Vector3(-0.056, -0.068, -0.396), Vector3(0.18, -0.95, 0.34)],
		[0.6, Vector3(-0.080, -0.080, -0.410), Vector3(0.13, -1.06, 0.42)],
		[0.72, Vector3(0.06, -0.12, -0.42), Vector3(0.12, 0.3, 1.1)],
		[0.85, Vector3(0.07, -0.115, -0.41), Vector3(0.08, 0.22, 1.0)],
	],
	"pistol": [
		[0.13, Vector3(0.056, -0.084, -0.288), Vector3(0.08, 1.1, -0.25)],
		[0.3, Vector3(0.064, -0.076, -0.302), Vector3(0.02, 1.22, -0.32)],
		[0.45, Vector3(-0.024, -0.076, -0.302), Vector3(0.12, -1.05, 0.28)],
		[0.6, Vector3(-0.036, -0.084, -0.310), Vector3(0.08, -1.16, 0.36)],
		[0.72, Vector3(0.024, -0.116, -0.259), Vector3(-0.7, 0.1, 1.2)],
		[0.85, Vector3(0.032, -0.108, -0.252), Vector3(-0.62, 0.05, 1.05)],
	],
	"knife": [
		[0.14, Vector3(0.056, -0.100, -0.259), Vector3(0.1, 0.95, 0.15)],
		[0.5, Vector3(0.040, -0.084, -0.266), Vector3(-0.05, 0.6, 0.05)],
		[0.78, Vector3(0.024, -0.092, -0.259), Vector3(0.15, -0.4, -0.25)],
		[0.88, Vector3(0.040, -0.100, -0.252), Vector3(0.05, 0.15, -0.15)],
	],
}


func _inspect_pose(kind: String, base: Transform3D) -> Transform3D:
	var keys: Array = INSPECT_KEYS.get(kind, INSPECT_KEYS.rifle)
	var lift := Vector3.ZERO if fp_mode else Vector3(-0.03, 0.15, 0.2)
	var times: Array = [0.0]
	var poses: Array = [base]
	for k in keys:
		times.append(float(k[0]))
		poses.append(Transform3D(Basis.from_euler(k[2]), (k[1] as Vector3) + lift))
	times.append(1.0)
	poses.append(base)
	var t := clampf(inspect_t, 0.0, 1.0)
	var i := 0
	while i < times.size() - 2 and t > float(times[i + 1]):
		i += 1
	var u := (t - float(times[i])) / maxf(float(times[i + 1]) - float(times[i]), 0.001)
	u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)   # smootherstep: no snap at the keys
	var xf: Transform3D = (poses[i] as Transform3D).interpolate_with(poses[i + 1], u)
	# a breath of hand sway while it is held up
	var held := smoothstep(0.05, 0.15, t) * (1.0 - smoothstep(0.88, 0.98, t))
	xf.origin += Vector3(sin(t * 9.0) * 0.004, sin(t * 7.0 + 1.0) * 0.003, 0.0) * held
	return xf


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

	var kind := "knife" if weapon.is_melee() else ("pistol" if weapon.is_pistol() else "rifle")
	var xf := _weapon_pose(kind, "ready").interpolate_with(_weapon_pose(kind, "aim"), aim_amt)
	if fp_mode:
		var fp: Dictionary = FP_POSES[kind]
		var hip := Transform3D(Basis.from_euler(fp.hip[1]), fp.hip[0])
		var ads := Transform3D(Basis.from_euler(fp.aim[1]), fp.aim[0]) if kind == "knife" else Transform3D(Basis.IDENTITY, weapon.ads_offset)
		xf = hip.interpolate_with(ads, aim_amt)
	if inspect_t >= 0.0:
		if aim_target > 0.0 or sprint_target > 0.0 or slide_target > 0.0:
			inspect_t = -1.0
		else:
			inspect_t += delta / INSPECT_DURATION
			if inspect_t >= 1.0:
				inspect_t = -1.0
			else:
				xf = _inspect_pose(kind, xf)
				weapon.inspect_motion(inspect_t)
	if inspect_t < 0.0:
		weapon.inspect_motion(-1.0)
	if fp_mode:
		var fs: Array = FP_POSES[kind].sprint
		xf = xf.interpolate_with(Transform3D(Basis.from_euler(fs[1]), fs[0]), sprint_amt * (1.0 - aim_amt))
		xf = _fp_gait(xf)
	else:
		xf = xf.interpolate_with(_weapon_pose(kind, "sprint_1h" if _one_hand_run() else "sprint"), sprint_amt * (1.0 - aim_amt))
	# third person only: first person keeps the gun gait-independent of the eye
	if not fp_mode and not _one_hand_run() and kind == "rifle":
		# two-handed carry across the chest: the rifle rides the torso's
		# counter-rotation, rocks with each stride and punches a little
		# forward and back with the arms
		var cw := sprint_amt * (1.0 - aim_amt) * move_blend * (1.0 - slide_amt)
		var s := sin(phase)
		var c2 := cos(phase)
		xf.origin += Vector3(s * 0.035, absf(c2) * 0.025 - 0.0125, c2 * 0.03) * cw
		xf = Transform3D(Basis(Vector3.UP, -s * 0.16 * cw) * Basis(Vector3.BACK, s * 0.1 * cw), Vector3.ZERO) * xf
	if _one_hand_run() and not fp_mode:
		# right arm swings forward with the left leg (counter to the free left arm)
		var sw_w := sprint_amt * (1.0 - aim_amt) * move_blend * (1.0 - slide_amt)
		var f := cos(phase)
		xf.origin += Vector3(0.0, maxf(f, 0.0) * 0.04, -f * 0.09) * sw_w
		xf = xf * Transform3D(Basis(Vector3.RIGHT, f * 0.18 * sw_w), Vector3.ZERO)

	if slash_t >= 0.0:
		_slash_jolt = maxf(_slash_jolt - delta * 9.0, 0.0)
		if _slash_hold > 0.0:
			_slash_hold -= delta
		else:
			slash_t += delta / _slash_dur
		if slash_t >= 1.0:
			slash_t = -1.0
		else:
			xf = _slash_pose(xf, slash_t)
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


## First person: the gun sways a figure-8 in time with the stride and dips
## on every footfall; more at a run, almost nothing while aiming.
func _fp_gait(xf: Transform3D) -> Transform3D:
	var m := move_blend * (1.0 - slide_amt) * (1.0 - air_amt)
	if m < 0.01:
		return xf
	var w := m * lerpf(1.0, 0.12, aim_amt)
	var g: Array = []
	for i in 4:
		g.append(lerpf(float(FP_GAIT_WALK[i]), float(FP_GAIT_SPRINT[i]), sprint_amt) * w)
	var side := sin(phase)                    # one sway per stride
	var dip := absf(sin(phase))               # down on each footfall
	var lag := sin(phase * 2.0 - 0.6)         # the gun trails the body a little
	xf.origin += Vector3(side * g[0], -dip * g[1] + lag * g[1] * 0.25, 0.0)
	return xf * Transform3D(Basis.from_euler(Vector3(-lag * g[3], side * g[3] * 0.6, side * g[2])), Vector3.ZERO)


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
		var kw := _kick_w()
		local = local.lerp(air_pose, air_amt * (1.0 - kw))
		if kw > 0.0:
			# dropkick: both knees tuck to the chest, then both legs shoot out
			# together, feet side by side (the pivot has tipped the body back)
			var ke := _kick_ext()
			var tucked := Vector3(side * 0.12, ANKLE_H + 0.55, -0.28)
			var shot := Vector3(side * 0.11, ANKLE_H + 0.1, -0.3)
			local = local.lerp(tucked.lerp(shot, ke), kw)
		# slide: lead (left) leg extended along the floor, trailing leg folded under
		var slide_pose := Vector3(-0.07, ANKLE_H, -0.68) if i == 0 else Vector3(0.17, ANKLE_H + 0.03, 0.12)
		local = local.lerp(slide_pose, slide_amt)
		var target := gx * (lb * local)
		var pole := gx.basis * (lb * Vector3(side * 0.15 + 0.6 * v_tuck, 0.0, -1.0)).normalized()
		_solve_ik(thighs[i], shins[i], THIGH, SHIN, target, pole)
		var foot: Node3D = feet[i]
		var foot_pitch := toe * m
		foot_pitch += 0.9 * _kick_ext() * _kick_w()   # both soles lead into the target
		foot.global_transform = Transform3D(gx.basis * lb * Basis(Vector3.RIGHT, foot_pitch), foot.global_position)


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
	if _one_hand_run() and reload_t < 0.0 and throw_t < 0.0 and vault_t < 0.0:
		free_want = sprint_amt * (1.0 - aim_amt) * (1.0 - slide_amt)
	var kwa := _kick_w()
	if kwa > 0.0 or weapon.is_melee():
		free_want = 1.0   # kicking, or a knife in one hand: the left arm is free
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
	if kwa > 0.0 and not fp_mode:
		# free arm flung out wide for balance while lying flat in the air
		l_pos = l_pos.lerp(chest.global_transform * Vector3(-0.52, 0.08, 0.05), kwa)
	# A long gun's handguard sits further from the left shoulder than the arm
	# reaches. Real shooters roll the shoulder forward (and blade the torso):
	# the shoulder follows the hand by up to 13 cm in third person, and as far
	# as needed in first person, where the shoulders are off-screen.
	_reach_shoulder(0, l_pos, 0.13)
	_reach_shoulder(1, r_xf.origin, 0.06)
	_solve_ik(shoulders[1], elbows[1], UPPER_ARM, FOREARM, r_xf.origin, (cb * r_pole).normalized())
	_set_basis(hands[1], r_xf.basis)
	_solve_ik(shoulders[0], elbows[0], UPPER_ARM, FOREARM, l_pos, (cb * l_pole).normalized())
	if _free_arm > 0.001:
		l_basis = l_basis.orthonormalized().slerp(elbows[0].global_transform.basis.orthonormalized(), _free_arm)
	_set_basis(hands[0], l_basis)


## Sprinting with the gun in the right hand only and the left arm pumping:
## pistols and knives always; long guns only in first person (where the left
## hand swings up into view). A third-person rifle stays in both hands,
## carried across the chest like a real operator runs with it.
func _one_hand_run() -> bool:
	if not one_hand_sprint or weapon == null:
		return false
	return fp_mode or weapon.is_pistol() or weapon.is_melee()


func _reach_shoulder(i: int, target: Vector3, tp_limit: float) -> void:
	var sh: Node3D = shoulders[i]
	var to := target - sh.global_position
	var excess := to.length() - (UPPER_ARM + FOREARM - 0.004)
	if excess <= 0.0:
		return
	var move := excess if fp_mode else minf(excess, tp_limit)
	sh.global_position += to.normalized() * move


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
	if t < 0.4:
		var buckle := smoothstep(0.0, 0.36, t)
		hips.position.y = lerpf(_death_hip, lerpf(_death_hip, 0.5, 0.75), buckle)
		move_blend = lerpf(move_blend, 0.0, 1.0 - exp(-12.0 * delta))
		_update_legs(delta)
	else:
		# phase 2b: as the body goes over, the legs go limp and straighten out
		# with it (no kneeling corpse with its thighs in the air)
		var ext := smoothstep(0.4, 0.85, t)
		hips.position.y = lerpf(lerpf(_death_hip, 0.5, 0.75), _death_hip, ext)
		var k := 1.0 - exp(-9.0 * delta)
		for i in thighs.size():
			var side := -1.0 if i == 0 else 1.0
			var thigh_rest := Basis.from_euler(Vector3(0.1 + 0.12 * i, 0.0, side * 0.07))
			(thighs[i] as Node3D).basis = (thighs[i] as Node3D).basis.slerp(thigh_rest, k)
			var bend := -0.75 if i == _death_knee else -0.1   # one knee stays bent
			var thigh_lift := 0.45 if i == _death_knee else 0.0
			(thighs[i] as Node3D).basis = (thighs[i] as Node3D).basis.slerp(Basis.from_euler(Vector3(thigh_lift, 0.0, 0.0)) * thigh_rest, k)
			(shins[i] as Node3D).basis = (shins[i] as Node3D).basis.slerp(Basis.from_euler(Vector3(bend, 0.0, 0.0)), k)
			(feet[i] as Node3D).basis = (feet[i] as Node3D).basis.slerp(Basis.from_euler(Vector3(0.35, 0.0, side * 0.2)), k)
	# phase 2: body topples in the direction of the killing shot
	var f := clampf((t - 0.18) / 0.62, 0.0, 1.0)
	var fall := f * f
	if t > 0.8:
		fall = 1.0 + sin(clampf((t - 0.8) / 0.22, 0.0, 1.0) * PI) * 0.04
	var axis := Vector3.UP.cross(_death_dir).normalized()
	# topple, and roll part-way onto one side as it goes down
	pivot.transform = Transform3D(Basis(axis, fall * 1.5) * Basis(Vector3.UP, _death_roll * minf(fall, 1.0)), Vector3(0, 0.1 * minf(fall, 1.0), 0))
	# slump torso and head, limp arms
	var slump := smoothstep(0.0, 0.9, t)
	# Preserve the existing 60 Hz response at every render frequency.
	var slump_blend := 1.0 - pow(1.0 - slump * 0.15, delta * 60.0)
	if _death_back:
		# on its back: torso flat, head lolls to one side
		spine.basis = spine.basis.slerp(Basis.from_euler(Vector3(0.12, 0.15, 0.1)), slump_blend)
		head.basis = head.basis.slerp(Basis.from_euler(Vector3(0.2, 0.7 * signf(_death_roll), 0.25)), slump_blend)
	else:
		spine.basis = spine.basis.slerp(Basis.from_euler(Vector3(-0.35, 0.2, 0.15)), slump_blend)
		head.basis = head.basis.slerp(Basis.from_euler(Vector3(-0.5, 0.4, 0.3)), slump_blend)
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
