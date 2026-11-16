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
const ROLL_HAMMER_COCKED := 0.75   # matches WeaponModel.ROLL_HAMMER_COCKED
const Weapon = preload("res://scripts/weapons/weapon.gd")
const ModelSkin = preload("res://scripts/characters/model_skin.gd")
const Body = preload("res://scripts/characters/body_mesh.gd")
const FPSArmRig = preload("res://scripts/characters/fps_arm_rig.gd")

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
## Eye line on the head joint (face features, goggles, glasses).
const EYE_Y := -0.008
## The helmet rides this far above the head joint, its rim over the brows.
const HELMET_LIFT := 0.04

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
var _twirl := 0.0   # current spin angle of a twirled gun (radians)
var _tw_a := false
var _tw_b := false
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
## Starts at a per-rig offset so a squad or a horde never breathes, sways and
## glances in unison (instance id, not randf: the world RNG stays untouched).
var _time := float(get_instance_id() % 997) * 0.37

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
## An interrupted inspect eases back to the held pose over this long (s).
const INSPECT_BLEND_OUT := 0.16
var _inspect_fade := 0.0
var _inspect_last := Transform3D.IDENTITY
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
## The second long gun (rifle + SMG) is slung crossed over the first.
var back_slot_b: Node3D
var thigh_slot: Node3D
var hand_mag: Node3D
var weapon: Weapon
var palette: Dictionary
## Skinned model that copies this rig's pose (null = procedural body is drawn).
var model_skin: ModelSkin
var _body_meshes: Array[MeshInstance3D] = []
var fp_arm_rig: FPSArmRig
var _fp_arm_shadows := {}


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
	_mesh(hips, Body.pelvis(), camo, Vector3.ZERO)
	_mesh(hips, ML.rbox(Vector3(0.37, 0.07, 0.26)), gear, Vector3(0, 0.06, 0))
	_mesh(hips, ML.rbox(Vector3(0.05, 0.045, 0.02)), detail, Vector3(0, 0.06, -0.135))
	_mesh(hips, ML.rbox(Vector3(0.15, 0.12, 0.08)), gear, Vector3(0.06, -0.01, 0.16))
	_mesh(hips, ML.rbox(Vector3(0.06, 0.1, 0.06)), gear, Vector3(-0.17, 0.0, 0.08))

	# --- legs ---
	for side in [-1, 1]:
		var thigh := _node(hips, "Thigh", Vector3(side * HIP_HALF, -0.03, 0))
		_mesh(thigh, Body.thigh(THIGH), camo, Vector3.ZERO)
		_mesh(thigh, ML.rbox(Vector3(0.05, 0.15, 0.12)), camo, Vector3(side * 0.085, -0.25, 0))
		var shin := _node(thigh, "Shin", Vector3(0, -THIGH, 0))
		_mesh(shin, Body.shin(SHIN), camo, Vector3.ZERO)
		_mesh(shin, Body.joint(0.058), camo, Vector3(0, 0.0, 0.004))   # knee: no gap when it bends
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
	_mesh(spine, Body.abdomen(), camo, Vector3.ZERO)
	chest = _node(spine, "Chest", Vector3(0, 0.22, 0))
	_mesh(chest, Body.chest_body(), camo, Vector3.ZERO)

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
	_mesh(chest, Body.neck(), p.face, Vector3.ZERO)
	head = _node(chest, "Head", Vector3(0, 0.42, 0))
	_mesh(head, Body.head(), p.face, Vector3.ZERO)
	_build_face(head, p)
	_build_headgear(head, p)

	# --- arms ---
	for side in [-1, 1]:
		var sh := _node(chest, "Shoulder", Vector3(side * 0.2, 0.21, 0))
		_mesh(sh, Body.upper_arm(UPPER_ARM), camo, Vector3.ZERO)
		_mesh(sh, ML.rbox(Vector3(0.012, 0.07, 0.07)), gear, Vector3(side * 0.06, -0.09, 0))
		var el := _node(sh, "Elbow", Vector3(0, -UPPER_ARM, 0))
		# forearm: a sleeve that tapers to the wrist, bunched cloth at the elbow,
		# a rolled cuff and the glove's wrist strap
		_mesh(el, Body.joint(0.05), camo, Vector3(0, -0.006, 0))   # elbow: no gap when it bends
		if String(p.get("sleeves", "")) == "rolled":
			# sleeve rolled to just below the elbow, bare forearm to the glove
			_mesh(el, Body.forearm(FOREARM, true), p.skin, Vector3.ZERO)
			_mesh(el, ML.cylinder(0.058, 0.06, 0.05, 14), camo, Vector3(0, -0.045, 0))
		else:
			_mesh(el, Body.forearm(FOREARM), camo, Vector3.ZERO)
			for k in 3:
				_mesh(el, ML.cylinder(0.05 - k * 0.003, 0.053 - k * 0.003, 0.014, 14), camo, Vector3(0, -0.05 - k * 0.045, 0), Vector3(0.12 * (k - 1), 0, 0.1 * (1 - k)))
			_mesh(el, ML.cylinder(0.043, 0.045, 0.03, 14), camo, Vector3(0, -0.252, 0))
		_mesh(el, ML.cylinder(0.039, 0.041, 0.032, 14), p.gloves, Vector3(0, -0.272, 0))
		_mesh(el, ML.cylinder(0.042, 0.042, 0.012, 14), detail, Vector3(0, -0.264, 0))
		_mesh(el, ML.rbox(Vector3(0.085, 0.085, 0.05)), detail, Vector3(0, -0.01, -0.05))
		var hand := _node(el, "Hand", Vector3(0, -FOREARM, 0))
		# glove: palm, padded back with a knuckle guard, four curled fingers
		# wrapping the grip and a thumb over the top
		_mesh(hand, ML.rbox(Vector3(0.05, 0.088, 0.088)), p.gloves, Vector3(side * 0.008, 0.0, 0.0))
		_mesh(hand, ML.rbox(Vector3(0.016, 0.07, 0.066)), detail, Vector3(side * 0.037, 0.004, -0.004))
		_mesh(hand, ML.rbox(Vector3(0.02, 0.03, 0.082)), detail, Vector3(side * 0.034, 0.012, -0.05), Vector3(0, side * 0.25, 0))
		for k in 4:
			var fy := 0.032 - k * 0.0215
			var flen := 0.064 - absf(k - 1.2) * 0.006
			# first joint runs forward from the knuckle, second curls across the grip
			_mesh(hand, ML.capsule(0.0105, flen), p.gloves, Vector3(side * 0.02, fy, -0.062), Vector3(PI * 0.5, 0, 0))
			_mesh(hand, ML.capsule(0.01, 0.05), p.gloves, Vector3(-side * 0.004, fy, -0.09), Vector3(0, 0, PI * 0.5))
			_mesh(hand, ML.capsule(0.0095, 0.04), p.gloves, Vector3(-side * 0.03, fy, -0.074), Vector3(PI * 0.5, side * 0.5, 0))
		_mesh(hand, ML.capsule(0.0125, 0.07), p.gloves, Vector3(-side * 0.002, 0.052, -0.03), Vector3(PI * 0.5, -side * 0.5, 0))
		_mesh(hand, ML.sphere(0.017, false, 8), p.gloves, Vector3(side * 0.012, 0.046, 0.006))
		shoulders.append(sh)
		elbows.append(el)
		hands.append(hand)

	# --- weapon mounting points ---
	weapon_anchor = _node(chest, "WeaponAnchor", Vector3.ZERO)
	back_slot = _node(chest, "BackSlot", Vector3(0.0, 0.12, 0.36))
	back_slot.basis = Basis(Vector3.BACK, 0.65) * Basis(Vector3.RIGHT, PI * 0.5)
	back_slot_b = _node(chest, "BackSlotB", Vector3(0.0, 0.1, 0.39))
	back_slot_b.basis = Basis(Vector3.BACK, -0.65) * Basis(Vector3.RIGHT, PI * 0.5)
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
	var pads: Material = p.get("pads", detail)   # knee and elbow pads
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
	# arms: rounded elbow pads, glove cuffs
	for i in 2:
		_mesh(elbows[i], ML.sphere(0.052, false, 10), pads, Vector3(0, -0.012, -0.05), Vector3.ZERO, Vector3(1.0, 1.25, 0.55))
		_mesh(elbows[i], ML.cylinder(0.06, 0.064, 0.055, 12), p.gloves, Vector3(0, -FOREARM + 0.035, 0))
		_mesh(hands[i], ML.rbox(Vector3(0.076, 0.03, 0.06)), detail, Vector3(0, -0.02, -0.03))
	# legs: knee caps, pocket flaps, boot collars and toe caps
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_mesh(shins[i], ML.sphere(0.07, false, 10), pads, Vector3(0, -0.035, -0.062), Vector3.ZERO, Vector3(0.95, 1.2, 0.55))
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
	_build_kit_detail(p)


## Third pass, the small things that make kit read as real: seams round the
## plate bag, side-release buckles, pouch snaps, a radio with its PTT cord,
## an ID patch, a steel belt buckle, boot laces and knee-pad straps. Torso
## parts hang straight off the chest (first person hides them there). Most
## are tiny, so AI bodies fade them out with distance (Soldier.optimize_detail).
func _build_kit_detail(p: Dictionary) -> void:
	var seam := _seam_mat()
	var buckle := _buckle_mat()
	var steel := _steel_mat()
	var web := M.fabric("webbing_strap", Color(0.13, 0.13, 0.11), 9.0)
	# plate bag: stitched edges round the front plate
	_mesh(chest, ML.rbox(Vector3(0.34, 0.004, 0.004)), seam, Vector3(0, 0.226, -0.166))
	_mesh(chest, ML.rbox(Vector3(0.34, 0.004, 0.004)), seam, Vector3(0, -0.086, -0.166))
	for side in [-1, 1]:
		_mesh(chest, ML.rbox(Vector3(0.004, 0.3, 0.004)), seam, Vector3(side * 0.168, 0.07, -0.166))
		# cummerbund closes with a side-release buckle, shoulder straps adjust at the chest
		_mesh(chest, ML.rbox(Vector3(0.034, 0.026, 0.01)), buckle, Vector3(side * 0.16, -0.06, -0.14))
		_mesh(chest, ML.rbox(Vector3(0.012, 0.03, 0.012)), buckle, Vector3(side * 0.181, -0.06, -0.14))
		_mesh(chest, ML.rbox(Vector3(0.036, 0.02, 0.009)), buckle, Vector3(side * 0.12, 0.2, -0.18))
	# magazine pouches: snap on each flap, stitched bottom, bungee pull tab
	for i in 3:
		var x := -0.09 + i * 0.09
		_mesh(chest, ML.rbox(Vector3(0.018, 0.012, 0.005)), buckle, Vector3(x, 0.06, -0.222))
		_mesh(chest, ML.rbox(Vector3(0.07, 0.004, 0.004)), seam, Vector3(x, -0.056, -0.218))
		_mesh(chest, ML.rbox(Vector3(0.012, 0.022, 0.004)), web, Vector3(x, 0.042, -0.222))
	# ID patch on the admin pouch
	_mesh(chest, ML.rbox(Vector3(0.08, 0.042, 0.004)), M.fabric("id_patch", Color(0.3, 0.31, 0.24), 14.0), Vector3(0.045, 0.17, -0.194))
	# radio: control knobs, PTT cord up to a button on the left shoulder strap
	_mesh(chest, ML.cylinder(0.009, 0.009, 0.022, 8), buckle, Vector3(-0.214, 0.085, 0.066))
	_mesh(chest, ML.cylinder(0.007, 0.007, 0.016, 8), buckle, Vector3(-0.196, 0.082, 0.094))
	_rod(chest, Vector3(-0.2, 0.08, 0.05), Vector3(-0.15, 0.2, -0.12), 0.005, buckle)
	_rod(chest, Vector3(-0.15, 0.2, -0.12), Vector3(-0.122, 0.17, -0.18), 0.005, buckle)
	_mesh(chest, ML.rbox(Vector3(0.034, 0.042, 0.016)), buckle, Vector3(-0.12, 0.15, -0.186))
	# belt: steel cobra buckle, stitched edges
	_mesh(hips, ML.rbox(Vector3(0.056, 0.036, 0.008)), steel, Vector3(0, 0.06, -0.148))
	_mesh(hips, ML.rbox(Vector3(0.012, 0.03, 0.01)), buckle, Vector3(0, 0.06, -0.152))
	for y in [0.088, 0.032]:
		_mesh(hips, ML.rbox(Vector3(0.3, 0.003, 0.004)), seam, Vector3(0, y, -0.131))
	# legs: knee-pad strap behind the calf, laces and a heel counter on each boot
	var lace := M.solid(Color(0.16, 0.14, 0.11), 0.9)
	for i in 2:
		_mesh(shins[i], ML.cylinder(0.064, 0.064, 0.012, 12), web, Vector3(0, -0.095, 0.012), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
		for k in 3:
			_mesh(feet[i], ML.rbox(Vector3(0.07, 0.005, 0.006)), lace, Vector3(0, 0.026 - k * 0.006, -0.045 - k * 0.026), Vector3(0.25, 0, 0))
		_mesh(feet[i], ML.rbox(Vector3(0.105, 0.05, 0.02)), _rubber_mat(), Vector3(0, -0.045, 0.085))
		# sleeve pocket seam on the upper arm
		var side := -1.0 if i == 0 else 1.0
		_mesh(shoulders[i], ML.rbox(Vector3(0.004, 0.004, 0.07)), seam, Vector3(side * 0.067, -0.056, 0))


func _build_headgear(h: Node3D, p: Dictionary) -> void:
	var detail: Material = p.detail
	match String(p.headgear):
		"helmet":
			var hm: Material = p.helmet
			var hg := h
			h = _node(hg, "Helmet", Vector3(0, HELMET_LIFT, 0))
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
				_mesh(h, ML.rbox(Vector3(0.01, 0.145, 0.018)), web, Vector3(side * 0.092, -0.08, -0.04), Vector3(-0.35, 0, 0))
				_mesh(h, ML.rbox(Vector3(0.014, 0.022, 0.024)), _buckle_mat(), Vector3(side * 0.094, -0.11, -0.055), Vector3(-0.35, 0, 0))
				_mesh(h, ML.rbox(Vector3(0.006, 0.04, 0.05)), M.solid(Color(0.25, 0.27, 0.2), 0.9), Vector3(side * 0.148, 0.075, 0.045))
			_mesh(h, ML.rbox(Vector3(0.07, 0.018, 0.03)), web, Vector3(0, -0.148, -0.07))
			_mesh(h, ML.cylinder(0.004, 0.004, 0.11, 6), detail, Vector3(-0.105, -0.085, -0.06), Vector3(1.25, 0, 0.25))
			_mesh(h, ML.sphere(0.012, false, 8), detail, Vector3(-0.072, -0.088, -0.108))
			# rubber edge trim on the rim and a bungee round the dome
			_mesh(h, ML.cylinder(0.152, 0.154, 0.012, 24), _rubber_mat(), Vector3(0, -0.019, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
			_mesh(h, ML.cylinder(0.142, 0.142, 0.008, 24), web, Vector3(0, 0.048, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
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
			_mesh(h, ML.sphere(0.113, true, 16), M.fabric("beanie", Color(0.12, 0.13, 0.1)), Vector3(0, 0.035, 0), Vector3.ZERO, Vector3(1, 1.0, 1.02))
			_mesh(h, ML.cylinder(0.115, 0.115, 0.03, 16), M.fabric("beanie", Color(0.12, 0.13, 0.1)), Vector3(0, 0.045, 0), Vector3.ZERO, Vector3(1, 1.0, 1.02))   # folded cuff
	if p.get("eyes", false):
		for sx in [-1, 1]:
			var eye := _mesh(h, ML.sphere(0.012, false, 6), M.emissive("zombie_eye", Color(1.0, 0.75, 0.2), 6.0), Vector3(sx * 0.034, 0.02, -0.093))
			eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if p.get("goggles", false):
		if p.has("goggle_frame"):
			# full ballistic goggles: coloured frame, dark lens, strap round the helmet
			var fr: Material = p.goggle_frame
			# worn just under the helmet rim, over the eyes
			_goggles(h, fr, _lens_mat(Color(0.1, 0.11, 0.12)))
		else:
			_goggles(h, _rubber_mat(), _lens_mat(Color(0.14, 0.16, 0.17)))
	elif not p.get("eyes", false) and String(p.headgear) != "none":
		_glasses(h)


## Ballistic goggles on the eye line: frame, lens, side vents and the strap
## running back round the head.
func _goggles(h: Node3D, frame: Material, lens: Material) -> void:
	# open frame (top, bottom, ends) round one wide lens
	for y in [0.022, -0.022]:
		_mesh(h, ML.rbox(Vector3(0.17, 0.013, 0.03)), frame, Vector3(0, EYE_Y + y, -0.1))
	for sx in [-1, 1]:
		_mesh(h, ML.rbox(Vector3(0.014, 0.056, 0.03)), frame, Vector3(sx * 0.079, EYE_Y, -0.1))
	_mesh(h, ML.rbox(Vector3(0.15, 0.036, 0.004)), lens, Vector3(0, EYE_Y, -0.108))
	_mesh(h, ML.rbox(Vector3(0.02, 0.016, 0.01)), frame, Vector3(0, EYE_Y - 0.022, -0.118))   # nose bridge
	var web := M.fabric("webbing_strap", Color(0.13, 0.13, 0.11), 9.0)
	for sx in [-1, 1]:
		_mesh(h, ML.rbox(Vector3(0.014, 0.03, 0.06)), frame, Vector3(sx * 0.088, EYE_Y, -0.072))
		_mesh(h, ML.rbox(Vector3(0.006, 0.006, 0.03)), _rubber_mat(), Vector3(sx * 0.096, EYE_Y + 0.006, -0.072))   # vent
		_mesh(h, ML.rbox(Vector3(0.008, 0.022, 0.12)), web, Vector3(sx * 0.094, EYE_Y + 0.004, 0.02))


## Wrap-around shooting glasses with clear lenses, so the eyes still read.
func _glasses(h: Node3D) -> void:
	var frame := M.solid(Color(0.06, 0.06, 0.065), 0.35)
	var lens := _clear_lens_mat()
	for sx in [-1, 1]:
		_mesh(h, ML.rbox(Vector3(0.042, 0.026, 0.004)), lens, Vector3(sx * 0.031, EYE_Y, -0.108), Vector3(0, sx * 0.28, 0))
		_mesh(h, ML.rbox(Vector3(0.044, 0.005, 0.006)), frame, Vector3(sx * 0.031, EYE_Y + 0.014, -0.108), Vector3(0, sx * 0.28, 0))
		_rod(h, Vector3(sx * 0.054, EYE_Y + 0.01, -0.098), Vector3(sx * 0.088, EYE_Y + 0.004, -0.004), 0.0028, frame)   # temple arm to the ear
	_mesh(h, ML.rbox(Vector3(0.016, 0.006, 0.006)), frame, Vector3(0, EYE_Y + 0.008, -0.112))


## Face on the head joint: eyes in their sockets, lowered brows and a set mouth
## (focused, the look of someone under fire), nose and ears. A balaclava
## (p.mask) shows skin only round the eyes; bare faces can carry a beard.
func _build_face(h: Node3D, p: Dictionary) -> void:
	var face: Material = p.face
	var masked := bool(p.get("mask", false))
	var skin: Material = p.get("skin", face)
	var hair := M.fabric("hair", Color(0.17, 0.125, 0.09), 24.0)
	_mesh(h, Body.nose(), face, Vector3(0, -0.02, -0.098))
	for side in [-1, 1]:
		_mesh(h, ML.rbox(Vector3(0.016, 0.048, 0.03)), face, Vector3(side * 0.088, -0.008, 0.008), Vector3(0, side * 0.2, 0))   # ears
	if p.get("eyes", false):
		return   # infected: glowing eyes come with the headgear pass
	if masked:
		# the balaclava's eye opening
		_mesh(h, ML.sphere(0.5, false, 16), skin, Vector3(0, EYE_Y, -0.018), Vector3.ZERO, Vector3(0.168, 0.036, 0.18))
	var ez := -0.093 if masked else -0.089
	var white := M.solid(Color(0.86, 0.84, 0.8), 0.35)
	var iris := M.solid(Color(0.2, 0.13, 0.08), 0.15)
	var pupil := M.solid(Color(0.02, 0.02, 0.02), 0.05)
	for side in [-1, 1]:
		var x: float = side * 0.033
		_mesh(h, ML.sphere(0.0115, false, 10), white, Vector3(x, EYE_Y, ez), Vector3.ZERO, Vector3(1.0, 0.62, 0.7))
		_mesh(h, ML.sphere(0.0066, false, 10), iris, Vector3(x - side * 0.0015, EYE_Y, ez - 0.0062), Vector3.ZERO, Vector3(1.0, 1.0, 0.45))
		_mesh(h, ML.sphere(0.0028, false, 6), pupil, Vector3(x - side * 0.0015, EYE_Y, ez - 0.0092), Vector3.ZERO, Vector3(1.0, 1.0, 0.4))
		# upper lid over the top of the eye, brow drawn down toward the nose
		_mesh(h, ML.rbox(Vector3(0.028, 0.006, 0.012)), skin if masked else face, Vector3(x, EYE_Y + 0.0062, ez - 0.006), Vector3(0.3, 0, 0))
		if not masked:
			_mesh(h, ML.rbox(Vector3(0.032, 0.0055, 0.01)), hair, Vector3(x, EYE_Y + 0.018, -0.099), Vector3(0.2, 0, side * 0.1))
	if masked:
		return
	# short hair at the sides and back, under whatever is worn on top
	_mesh(h, ML.sphere(0.5, true, 16), hair, Vector3(0, 0.02, 0.012), Vector3.ZERO, Vector3(0.186, 0.18, 0.214))
	var beard := bool(p.get("beard", false))
	if beard:
		_mesh(h, Body.beard(), hair, Vector3.ZERO)
	var lip_z := -0.107 if beard else -0.099
	var lip := M.solid(_color_of(skin).darkened(0.18).lerp(Color(0.5, 0.25, 0.22), 0.2), 0.55)
	_mesh(h, ML.rbox(Vector3(0.032, 0.005, 0.008)), lip, Vector3(0, -0.066, lip_z))
	_mesh(h, ML.rbox(Vector3(0.026, 0.0065, 0.008)), lip, Vector3(0, -0.073, lip_z + 0.002))
	for side in [-1, 1]:
		_mesh(h, ML.rbox(Vector3(0.008, 0.005, 0.007)), lip, Vector3(side * 0.018, -0.069, lip_z + 0.002), Vector3(0, 0, side * 0.4))   # set corners


## Albedo colour of a palette material (white when it is not a plain one).
static func _color_of(m: Material) -> Color:
	return (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color.WHITE


static var _shared_mats := {}

static func _shared(key: String, make: Callable) -> Material:
	if not _shared_mats.has(key):
		_shared_mats[key] = make.call()
	return _shared_mats[key]


## Black polymer: side-release buckles, snaps, PTT button.
static func _buckle_mat() -> Material:
	return M.solid(Color(0.045, 0.045, 0.045), 0.55)


static func _rubber_mat() -> Material:
	return M.solid(Color(0.06, 0.06, 0.06), 0.85)


## Brushed steel: belt buckle, D-rings.
static func _steel_mat() -> Material:
	return M.solid(Color(0.42, 0.42, 0.4), 0.35, 0.85)


## Dark seam / stitch line on fabric.
static func _seam_mat() -> Material:
	return M.solid(Color(0.07, 0.07, 0.06), 0.95)


## Smoked, glossy goggle lens; the eyes show through it.
static func _lens_mat(tint: Color) -> Material:
	return _shared("lens_%s" % tint.to_html(), func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(tint, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.6
		m.roughness = 0.05
		m.rim_enabled = true
		m.rim = 0.4
		return m)


## Clear shooting-glasses lens: lightly tinted, see-through.
static func _clear_lens_mat() -> Material:
	return _shared("lens_clear", func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.6, 0.62, 0.55, 0.28)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.3
		return m)


## A thin cylinder from `a` to `b` (parent space): cables, cords.
func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	var mi := _mesh(parent, ML.cylinder(r, r, d.length(), 6), mat, (a + b) * 0.5)
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(side, up, side.cross(up))
	return mi


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
	var ps := load(path) as PackedScene
	return ps != null and use_model_scene(ps, tint, hide_meshes)


## As use_model(), from a scene already in memory.
func use_model_scene(ps: PackedScene, tint: Color = Color.WHITE, hide_meshes: Array = []) -> bool:
	var s := ModelSkin.new()
	s.name = "ModelSkin"
	s.process_priority = 50   # after this rig animates
	add_child(s)
	if not s.setup_scene(self, ps, tint, hide_meshes):
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
		# first person shows the model's own arms; a model without them keeps the rig's
		mi.visible = fp_mode and on_arm and model_skin.fp_arms.is_empty()
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
	# Only the local first-person operator allocates the supplied skinned arms.
	if on and not zombie and fp_arm_rig == null and ResourceLoader.exists(FPSArmRig.ASSET):
		var arms := FPSArmRig.new()
		arms.name = "FPSArms"
		add_child(arms)
		if arms.setup(self):
			fp_arm_rig = arms
			if weapon != null:
				arms.select_weapon(weapon)
		else:
			arms.queue_free()
	if fp_arm_rig != null:
		fp_arm_rig.visible = on
		if not on:
			hand_mag.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0))
		for sh in shoulders:
			for n in sh.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if _is_gear(mi):
					continue
				if not _fp_arm_shadows.has(mi):
					_fp_arm_shadows[mi] = mi.cast_shadow
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else _fp_arm_shadows[mi]
		if model_skin != null and on:
			for mi in model_skin.fp_arms:
				mi.visible = false


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
		if (not mi.visible and model_skin == null) or mi.mesh == null:   # under a model skin the limb is hidden, not gone
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
	_inspect_fade = 0.0   # the new gun starts from its own pose
	if weapon != null and weapon != active and not weapon.bolt_action.is_empty():
		_set_bolt(0.0)   # a holstered bolt rifle goes away with its bolt closed
	weapon = active
	if fp_arm_rig != null:
		fp_arm_rig.select_weapon(active)
	cycle_t = -1.0
	_pump_base = active.pump.position if active.pump != null else Vector3.ZERO
	_attach(active, weapon_anchor)
	var backs := 0
	for w in others:
		if w.is_melee():
			_attach(w, _knife_slot())
		elif w.is_pistol():
			_attach(w, thigh_slot)
		else:
			_attach(w, back_slot if backs == 0 else back_slot_b)
			backs += 1
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
		# "bolt": the hand lets the charging handle / slide go and it slams home
		_reload_ev = {"out": 0.2, "pouch": 0.36, "grab": 0.46, "mag_in": 0.62, "bolt": 0.84}
	else:
		_reload_ev = {"out": 0.24, "pouch": 0.42, "grab": 0.52, "mag_in": 0.7, "bolt": 9.0}
	if weapon != null and not weapon.bolt_action.is_empty():
		# turn-bolt rifles feed from the top: the bolt is opened first and closed last
		_reload_ev.bolt = 9.0
		_reload_ev.open = 0.05
		_reload_ev.close = 0.9


func cancel_reload() -> void:
	reload_t = -1.0
	hand_mag.visible = false
	if weapon and weapon.mag_node:
		weapon.mag_node.visible = true
	if weapon:
		weapon.drop_action()
		if not weapon.bolt_action.is_empty() and cycle_t < 0.0:
			_set_bolt(0.0)


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
	if fp_mode and fp_arm_rig != null:
		fp_arm_rig.pose(delta)


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
	# the eyes lead a turn (the gun lags it) and wander a little when standing easy
	var look := 0.0 if fp_mode else clampf(-_sway_yaw * 0.9, -0.3, 0.3) + (sin(_time * 0.43) + 0.5 * sin(_time * 1.07 + 1.3)) * 0.07 * (1.0 - m) * (1.0 - aim_amt)
	head.basis = Basis.from_euler(Vector3(-pitch * 0.7 - 0.12 * aim_amt + 0.04, look, -roll * 0.6 + lean_amt * 0.3))
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
	_inspect_fade = 1.0
	# Update the muzzle immediately, before the same physics tick can fire.
	if weapon != null and is_inside_tree():
		_update_weapon_pose(0.0)
		_update_arms(0.0)


## Lift the gun, turn its left side to the eye, look it over, return.
## The hand targets remain attached to the gun; the eye never follows it.
## Inspect keys: [t, position, euler]. The rest pose is the first and last
## key. Only the left side is ever shown: turning the muzzle left keeps the
## support hand on the left and the grip hand on the right, so the forearms
## never cross. The gun turns a modest 45-55 degrees, then tips its muzzle up a
## little and rolls its top toward the eye (sights, optic, action) while the
## same side stays in view. Pairs of close keys keep it drifting instead of
## freezing in place. Positions are eye-relative.
const INSPECT_KEYS := {
	"rifle": [
		[0.14, Vector3(0.150, -0.100, -0.400), Vector3(0.08, 0.85, -0.22)],
		[0.36, Vector3(0.160, -0.092, -0.410), Vector3(0.04, 0.95, -0.30)],
		[0.56, Vector3(0.130, -0.086, -0.420), Vector3(0.18, 0.78, -0.50)],
		[0.78, Vector3(0.135, -0.090, -0.415), Vector3(0.14, 0.82, -0.42)],
	],
	"pistol": [
		[0.14, Vector3(0.056, -0.084, -0.288), Vector3(0.06, 0.95, -0.20)],
		[0.36, Vector3(0.062, -0.078, -0.298), Vector3(0.02, 1.05, -0.28)],
		[0.56, Vector3(0.050, -0.080, -0.292), Vector3(0.16, 0.85, -0.48)],
		[0.78, Vector3(0.052, -0.082, -0.290), Vector3(0.12, 0.90, -0.40)],
	],
	"knife": [
		[0.14, Vector3(0.056, -0.100, -0.259), Vector3(0.1, 0.95, 0.15)],
		[0.5, Vector3(0.040, -0.084, -0.266), Vector3(-0.05, 0.6, 0.05)],
		[0.78, Vector3(0.024, -0.092, -0.259), Vector3(0.15, -0.4, -0.25)],
		[0.88, Vector3(0.040, -0.100, -0.252), Vector3(0.05, 0.15, -0.15)],
	],
}


## Third-person inspect (what other players see): the same one-sided look,
## but chest-relative and held out in front of the vest at chest height, so
## the gun never passes through the body or arms.
const TP_INSPECT_KEYS := {
	"rifle": [
		[0.14, Vector3(0.13, 0.02, -0.46), Vector3(0.08, 0.80, -0.22)],
		[0.36, Vector3(0.14, 0.03, -0.48), Vector3(0.04, 0.90, -0.30)],
		[0.56, Vector3(0.11, 0.04, -0.47), Vector3(0.18, 0.74, -0.50)],
		[0.78, Vector3(0.115, 0.035, -0.47), Vector3(0.14, 0.78, -0.42)],
	],
	"pistol": [
		[0.14, Vector3(0.08, 0.04, -0.42), Vector3(0.06, 0.90, -0.20)],
		[0.36, Vector3(0.09, 0.05, -0.43), Vector3(0.02, 1.00, -0.28)],
		[0.56, Vector3(0.07, 0.05, -0.43), Vector3(0.16, 0.80, -0.48)],
		[0.78, Vector3(0.075, 0.045, -0.43), Vector3(0.12, 0.85, -0.40)],
	],
	# knives: out to the right at arm's length, blade in front of the chest and
	# neck rather than against the vest or the face (karambit spins and
	# butterfly flips play out here too)
	"knife": [
		[0.14, Vector3(0.19, -0.03, -0.52), Vector3(0.1, 0.95, 0.15)],
		[0.5, Vector3(0.17, -0.01, -0.54), Vector3(-0.05, 0.6, 0.05)],
		[0.78, Vector3(0.15, -0.02, -0.52), Vector3(0.15, -0.4, -0.25)],
		[0.88, Vector3(0.17, -0.03, -0.5), Vector3(0.05, 0.15, -0.15)],
	],
}


func _inspect_pose(kind: String, base: Transform3D) -> Transform3D:
	var table: Dictionary = INSPECT_KEYS if fp_mode else TP_INSPECT_KEYS
	var keys: Array = table.get(kind, table.rifle)
	var times: Array = [0.0]
	var poses: Array = [base]
	for k in keys:
		times.append(float(k[0]))
		poses.append(Transform3D(Basis.from_euler(k[2]), k[1] as Vector3))
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
			_inspect_fade = 1.0
		else:
			inspect_t += delta / INSPECT_DURATION
			if inspect_t >= 1.0:
				inspect_t = -1.0
			else:
				xf = _inspect_pose(kind, xf)
				_inspect_last = xf
				weapon.inspect_motion(inspect_t)
	if inspect_t < 0.0:
		weapon.inspect_motion(-1.0)
		if _inspect_fade > 0.0:
			# an inspect cut short (aim, sprint, fire, reload) eases back to the
			# held pose instead of snapping
			_inspect_fade = maxf(_inspect_fade - delta / INSPECT_BLEND_OUT, 0.0)
			xf = xf.interpolate_with(_inspect_last, smoothstep(0.0, 1.0, _inspect_fade))
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
	if cycle_t >= 0.0 and weapon.bolt != null and not weapon.bolt_action.is_empty():
		# turn-bolt: the rifle stays in the shoulder, canted a little toward the
		# working hand and dipped a touch while the bolt is open
		var ct := clampf(cycle_t, 0.0, 1.0)
		var bw := smoothstep(0.02, BOLT_LIFT, ct) * (1.0 - smoothstep(BOLT_DOWN, 1.0, ct))
		xf = xf * Transform3D(Basis.from_euler(Vector3(-0.035 * bw, 0.02 * bw, 0.16 * bw)), Vector3(0, -0.012 * bw, 0.01 * bw))
	elif cycle_t >= 0.0 and weapon.bolt != null:
		var cw := sin(PI * cycle_t)
		xf = xf * Transform3D(Basis.from_euler(Vector3(0.05 * cw, 0.1 * cw, 0.35 * cw)), Vector3.ZERO)
	_twirl = 0.0
	if cycle_t >= 0.0 and weapon.twirl != null:
		# gun twirl. The recoil throws the muzzle up and the wrist lets it keep
		# going: two backward turns around the trigger finger that start fast and
		# slow into the catch, where the muzzle dips past level and springs back.
		# The gun is carried up and turned side-on so the spin reads as a wheel.
		var ct := clampf(cycle_t, 0.0, 1.0)
		var spin_cock: bool = weapon.lever != null
		var su := clampf(ct / 0.8, 0.0, 1.0)
		if spin_cock:
			# one even roll through the middle of the cycle: whips round fast, caught at SPIN_CATCH
			var sp := clampf((ct - 0.1) / (SPIN_CATCH - 0.1), 0.0, 1.0)
			_twirl = TAU * sp * sp * (3.0 - 2.0 * sp)
		else:
			_twirl = TAU * 2.0 * (1.0 - pow(1.0 - su, 2.6))
		var cv := clampf((ct - 0.8) / 0.2, 0.0, 1.0)
		var settle := -0.2 * sin(PI * cv) * (1.0 - cv)
		var show := pow(sin(PI * minf(ct / 0.86, 1.0)), 0.6)
		var fpk := 1.0 if fp_mode else 0.4
		var pv: Vector3 = (weapon.global_transform.affine_inverse() * weapon.twirl.global_transform).origin
		var spin := Basis(Vector3.RIGHT, _twirl)
		if spin_cock:
			# lever-action spin cock: the rifle stays square to the body (no sideways
			# swing) and rolls straight back toward it once round the lever loop,
			# held a little low so the barrel passes clear of the head, then is caught
			var out := smoothstep(0.0, 0.14, ct) * (1.0 - smoothstep(0.8, 1.0, ct))
			# a small forward flick of the wrist starts it; the catch kicks the muzzle up a touch
			var flick := sin(PI * clampf(ct / 0.12, 0.0, 1.0)) * 0.25
			var catch_kick := sin(PI * clampf((ct - SPIN_CATCH) / 0.14, 0.0, 1.0)) * 0.12
			xf = xf * Transform3D(Basis(Vector3.RIGHT, -flick + catch_kick),
					Vector3(0, -0.14 * out, 0.06 * out * fpk)) * Transform3D(spin, pv - spin * pv)
		else:
			xf = xf * Transform3D(Basis.from_euler(Vector3(settle, 0.85 * show * fpk, 0.25 * show)),
					Vector3(-0.08 * show * fpk, 0.07 * show, 0.1 * show * fpk)) * Transform3D(spin, pv - spin * pv)
		if not _tw_a and ct > (0.42 if spin_cock else 0.32):
			_tw_a = true
			Sfx.play(self, "knife_swing", weapon.global_position, -6.0, 0.15)
		if not _tw_b and ct > (SPIN_CATCH if spin_cock else 0.8):
			_tw_b = true
			Sfx.play(self, "bolt", weapon.global_position, -3.0)   # caught, hammers back
	if cycle_t >= 0.0 and weapon.roll != null:
		# rolling block: the muzzle tips up and the gun cants in so the open
		# breech faces the shooter while the thumb works hammer and block
		var rw := smoothstep(0.0, 0.25, cycle_t) * (1.0 - smoothstep(0.8, 1.0, cycle_t)) * (1.0 - aim_amt * 0.6)
		xf = xf * Transform3D(Basis.from_euler(Vector3(0.22 * rw, 0.0, 0.3 * rw)), Vector3(0, 0.03 * rw, (0.15 if fp_mode else 0.04) * rw))

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
	if fp_mode and fp_arm_rig != null:
		r_xf = fp_arm_rig.grip_transform(weapon, 1, r_xf)
	if _twirl != 0.0 and weapon.twirl != null:
		# the hand does not go round with the gun: it stays where the grip would
		# be without the spin, finger through the guard
		var axis: Vector3 = weapon.global_transform.basis.x.normalized()
		var un := Basis(axis, -_twirl)
		var pvw: Vector3 = weapon.twirl.global_position
		r_xf = Transform3D(un * r_xf.basis, pvw + un * (r_xf.origin - pvw))
	if not weapon.bolt_action.is_empty():
		# turn-bolt: the right hand takes the handle (it rides with the bolt as it
		# turns and runs back), after a shot and to open / close it for a reload
		var hw := 0.0
		if cycle_t >= 0.0:
			var ct := clampf(cycle_t, 0.0, 1.0)
			hw = smoothstep(0.0, BOLT_REACH, ct) * (1.0 - smoothstep(BOLT_DOWN, BOLT_RETURN, ct))
		elif reload_t >= 0.0 and _reload_ev.has("open"):
			hw = smoothstep(0.0, 0.05, reload_t) * (1.0 - smoothstep(0.17, 0.25, reload_t)) \
					+ smoothstep(0.72, 0.8, reload_t) * (1.0 - smoothstep(0.94, 1.0, reload_t))
		if hw > 0.0:
			# palm over the knob from above and behind, fingers wrapped round it
			var knob: Vector3 = weapon.charge.global_position
			var wb: Basis = weapon.global_transform.basis.orthonormalized()
			r_xf.origin = r_xf.origin.lerp(knob + wb * Vector3(0.012, 0.018, 0.02), hw)
			var working := wb * Basis.from_euler(Vector3(-0.5, 0.25, -0.6))
			if fp_mode and fp_arm_rig != null:
				working = wb * FPSArmRig.frame(Vector3(-0.4, 0, -1.0), Vector3.DOWN)
			r_xf.basis = r_xf.basis.orthonormalized().slerp(working.orthonormalized(), hw)
	elif cycle_t >= 0.0 and weapon.bolt != null:
		var bw := smoothstep(0.0, 0.25, cycle_t) * (1.0 - smoothstep(0.75, 1.0, cycle_t))
		r_xf.origin = r_xf.origin.lerp(weapon.charge.global_position, bw)
	if throw_t >= 0.0:
		r_xf.origin = _throw_hand(r_xf.origin)
	var l_xf: Transform3D = weapon.support.global_transform
	if fp_mode and fp_arm_rig != null:
		l_xf = fp_arm_rig.grip_transform(weapon, 0, l_xf)
	var l_pos := l_xf.origin
	var l_basis := l_xf.basis
	if cycle_t >= 0.0 and weapon.roll != null:
		# the support hand comes up over the action: thumb on the hammer, then the block
		var tw := smoothstep(0.0, 0.2, cycle_t) * (1.0 - smoothstep(0.82, 1.0, cycle_t))
		var wb: Basis = weapon.global_transform.basis.orthonormalized()
		l_pos = l_pos.lerp(weapon.charge.global_position + wb * Vector3(-0.07, -0.045, 0.03), tw)
	if reload_t >= 0.0:
		_update_reload_events()
		if reload_t >= 0.0:
			l_pos = _reload_left_target(reload_t)
			if fp_mode and fp_arm_rig != null:
				l_basis = fp_arm_rig.reload_basis(weapon, reload_t, l_basis)
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
	if cycle_t >= 0.0 and weapon.twirl != null:
		free_want = 1.0   # the support hand lets go while the gun spins
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
	if fp_mode and fp_arm_rig != null:
		var settled := fp_arm_rig.settle_left(Transform3D(l_basis.orthonormalized(), l_pos), delta)
		l_pos = settled.origin
		l_basis = settled.basis
	# A long gun's handguard sits further from the left shoulder than the arm
	# reaches. Real shooters roll the shoulder forward (and blade the torso):
	# the shoulder follows the hand by up to 13 cm in third person, and as far
	# as needed in first person, where the shoulders are off-screen.
	if fp_mode and fp_arm_rig == null and aim_amt > 0.0 and _free_arm < 0.5 and reload_t < 0.0:
		# aiming in first person, the gloves and cuffs must not rise into the
		# view of the gun: each hand drops just below its hold point as the eye sees it
		var up := fp_eye.basis.y.normalized()
		r_xf.origin -= up * _ads_hand_drop(hands[1], r_xf.basis, r_xf.origin, weapon.grip.global_position, shoulders[1].global_position) * aim_amt
		l_pos -= up * _ads_hand_drop(hands[0], l_basis, l_pos, weapon.support.global_position, shoulders[0].global_position) * aim_amt
	_reach_shoulder(0, l_pos, 0.13)
	_reach_shoulder(1, r_xf.origin, 0.06)
	_solve_ik(shoulders[1], elbows[1], UPPER_ARM, FOREARM, r_xf.origin, (cb * r_pole).normalized())
	_set_basis(hands[1], r_xf.basis)
	_solve_ik(shoulders[0], elbows[0], UPPER_ARM, FOREARM, l_pos, (cb * l_pole).normalized())
	if _free_arm > 0.001:
		var free_basis: Basis = elbows[0].global_transform.basis.orthonormalized()
		if fp_mode and fp_arm_rig != null:
			free_basis = cb * FPSArmRig.frame(Vector3(0.15, -1.0, -0.4), Vector3.RIGHT)
		l_basis = l_basis.orthonormalized().slerp(free_basis, _free_arm)
	_set_basis(hands[0], l_basis)
	if fp_mode and fp_arm_rig != null and hand_mag.visible:
		# HandMag used to inherit the block glove's axes. Keep the magazine upright
		# with the new anatomical palm, meeting its original socket on insertion.
		var wb := weapon.global_transform.basis.orthonormalized()
		hand_mag.global_transform = Transform3D(wb, l_pos + wb * Vector3(0.025, 0.075, -0.025))


## Sprinting with the gun in the right hand only and the left arm pumping:
## pistols and knives always; long guns only in first person (where the left
## hand swings up into view). A third-person rifle stays in both hands,
## carried across the chest like a real operator runs with it.
func _one_hand_run() -> bool:
	if not one_hand_sprint or weapon == null:
		return false
	return fp_mode or weapon.is_pistol() or weapon.is_melee()


## Glove extents in hand space (corners of all its meshes), measured once.
var _hand_box: Array = []
## The wrist cuff's radius: it sits at the hand's origin.
const CUFF_R := 0.065
## How far (0..1) a glove may rise from its hold point toward the sight line while aiming.
const ADS_HAND_RISE := 0.33


## How far (m, along the view's up) a hand placed at `hb`/`at` must drop
## so that no part of the glove, its cuff or the sleeve behind it rises more than
## ADS_HAND_RISE of the way from `hold` up to the sight line, seen from the eye.
func _ads_hand_drop(hand: Node3D, hb: Basis, at: Vector3, hold: Vector3, shoulder: Vector3) -> float:
	if _hand_box.is_empty():
		var box := AABB()
		var first := true
		for n in hand.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var a: AABB = mi.transform * mi.get_aabb()
			box = a if first else box.merge(a)
			first = false
		for k in 8:
			_hand_box.append(box.get_endpoint(k))
	var inv := fp_eye.affine_inverse()
	var h := inv * hold
	if h.z >= -0.01:
		return 0.0
	# the eye sits on the sight line (slope 0): the glove may rise a third of the
	# way from its hold point toward it, staying on the gun's lower part, off the
	# slide / receiver top and the sights
	var slope := h.y / -h.z * (1.0 - ADS_HAND_RISE)
	var pts: Array = []
	for c in _hand_box:
		pts.append(at + hb * (c as Vector3))
	# the glove cuff and the sleeve behind it: rings round the forearm, which runs
	# back toward the shoulder, so seen end-on from the eye they are wide discs
	var up := fp_eye.basis.y.normalized()
	var back := (shoulder - at).normalized()
	for k in [0.0, 0.035, 0.1, 0.18]:
		pts.append(at + back * float(k) + up * CUFF_R)
	var drop := 0.0
	for pt in pts:
		var v: Vector3 = inv * (pt as Vector3)
		if v.z < -0.01:
			drop = maxf(drop, v.y - slope * -v.z)
	return minf(drop, 0.12)


func _reach_shoulder(i: int, target: Vector3, tp_limit: float) -> void:
	var sh: Node3D = shoulders[i]
	var to := target - sh.global_position
	var excess := to.length() - (UPPER_ARM + FOREARM - 0.004)
	if excess <= 0.0:
		return
	var move := excess if fp_mode else minf(excess, tp_limit)
	sh.global_position += to.normalized() * move


## How far a lever-action's lever swings open (radians).
const LEVER_OPEN := 0.9
## Spin cock: where in the cycle (0..1) the rifle completes its roll and is caught.
const SPIN_CATCH := 0.78

## Turn-bolt cycle after a shot, as fractions of the cycle: the hand leaves the
## grip for the handle, lifts it, draws the bolt back (the case flies out at the
## end of the stroke), runs it forward, turns it down, and returns to the grip.
const BOLT_REACH := 0.15
const BOLT_LIFT := 0.29
const BOLT_BACK := 0.47
const BOLT_FWD := 0.66
const BOLT_DOWN := 0.79
const BOLT_RETURN := 0.95


## The turn-bolt stroke (see _set_bolt) at cycle fraction `ct`.
static func _bolt_stroke(ct: float) -> float:
	var s := smoothstep(BOLT_REACH, BOLT_LIFT, ct) + smoothstep(BOLT_LIFT, BOLT_BACK, ct)
	return s - smoothstep(BOLT_BACK + 0.04, BOLT_FWD, ct) - smoothstep(BOLT_FWD, BOLT_DOWN, ct)


## Bolt-action / pump-action / lever-action cycling after each shot.
func _update_cycle(delta: float) -> void:
	var turn_bolt := not weapon.bolt_action.is_empty()
	if weapon.cycle_pending > 0.0:
		weapon.cycle_pending -= delta
		if weapon.cycle_pending <= 0.0:
			cycle_t = 0.0
			_cycle_dur = clampf(60.0 / float(weapon.stats.rpm) * (0.82 if weapon.twirl != null else 0.7), 0.35, 1.1 if turn_bolt else 1.0)
			_cycle_cased = false
			_tw_a = false
			_tw_b = false
			if not turn_bolt:
				Sfx.play(self, "knife_swing" if weapon.twirl != null else "bolt", weapon.global_position, -4.0)
	if cycle_t < 0.0:
		return
	cycle_t += delta / _cycle_dur
	var w := sin(PI * minf(cycle_t, 1.0))
	if turn_bolt:
		var ct := minf(cycle_t, 1.0)
		_set_bolt(_bolt_stroke(ct))
		# unlocking click as the handle comes up, the slam and lock as it goes down
		if not _tw_a and ct > BOLT_REACH + 0.02:
			_tw_a = true
			Sfx.play(self, "bolt", weapon.charge.global_position, -7.0)
		if not _tw_b and ct > BOLT_FWD - 0.02:
			_tw_b = true
			Sfx.play(self, "bolt", weapon.charge.global_position, -3.0)
	elif weapon.bolt != null:
		weapon.bolt.position = Vector3(0, 0, 0.075 * w)
	if weapon.pump != null:
		weapon.pump.position = _pump_base + Vector3(0, 0, 0.09 * w)
	if weapon.lever != null and weapon.twirl != null:
		# spin cock: the lever flies open as the rifle whips round and snaps shut on the catch
		var ct := minf(cycle_t, 1.0)
		var lw := smoothstep(0.12, 0.38, ct) - smoothstep(SPIN_CATCH - 0.1, SPIN_CATCH, ct)
		weapon.lever.rotation.x = LEVER_OPEN * lw
		if weapon.bolt != null:
			weapon.bolt.position = Vector3(0, 0, 0.075 * lw)
	elif weapon.lever != null:
		weapon.lever.rotation.x = LEVER_OPEN * w   # swings down and forward, then back
	if weapon.roll != null:
		# hammer falls at the shot, is thumbed back to full cock, then the block
		# rolls open (case out, round in) and is rolled shut again
		var ct := minf(cycle_t, 1.0)
		weapon.hammer.rotation.x = ROLL_HAMMER_COCKED * smoothstep(0.05, 0.3, ct)
		weapon.roll.rotation.x = 1.25 * (smoothstep(0.3, 0.5, ct) - smoothstep(0.72, 0.92, ct))
	if not _cycle_cased and cycle_t > (BOLT_BACK - 0.03 if turn_bolt else 0.5):
		_cycle_cased = true
		if weapon.twirl == null or weapon.lever != null:   # a break-action keeps its shells until the reload
			FX.casing(self, weapon.eject.global_position, weapon.global_transform.basis.x, false)
	if cycle_t >= 1.0:
		cycle_t = -1.0
		if turn_bolt:
			_set_bolt(0.0)
		elif weapon.bolt != null:
			weapon.bolt.position = Vector3.ZERO
		if weapon.pump != null:
			weapon.pump.position = _pump_base
		if weapon.lever != null:
			weapon.lever.rotation.x = 0.0
		if weapon.roll != null:
			weapon.roll.rotation.x = 0.0
			weapon.hammer.rotation.x = ROLL_HAMMER_COCKED


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
		if _reload_ev.has("open"):
			_set_bolt(0.0)
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
	# empty: the support hand racks the charging handle / slide back and lets it go
	if _reload_empty and weapon.bolt_action.is_empty() and weapon.bolt != null and _reload_ev.bolt < 1.0:
		var rk: Vector2 = _rack_times()
		if t >= rk.x:
			weapon.hold_action(smoothstep(rk.x, rk.y, t))
	if t >= _reload_ev.bolt and _reload_ev.bolt < 1.0:
		_reload_ev.bolt = 9.0
		weapon.release_action()
		Sfx.play(self, "bolt", weapon.charge.global_position, -4.0)
	# turn-bolt: open (lift, draw back) before the rounds go in, close at the end
	if _reload_ev.has("open"):
		var s := 2.0 * smoothstep(0.05, 0.17, t) * (1.0 - smoothstep(0.8, 0.94, t))
		_set_bolt(s)
		if t >= _reload_ev.open:
			_reload_ev.open = 9.0
			Sfx.play(self, "bolt", weapon.charge.global_position, -6.0)
		if t >= _reload_ev.close:
			_reload_ev.close = 9.0
			Sfx.play(self, "bolt", weapon.charge.global_position, -3.0)


## Reload fractions where the support hand takes the charging handle and where
## it has it fully back (it lets go at the "bolt" event just after).
func _rack_times() -> Vector2:
	return Vector2(0.76, 0.81)


## Turn-bolt position for a stroke `s`: 0 closed, 1 handle lifted (bolt
## unlocked), 2 lifted and drawn fully back. Lift turns it on its own axis.
func _set_bolt(s: float) -> void:
	if weapon == null or weapon.bolt == null or weapon.bolt_action.is_empty():
		return
	var turn := clampf(s, 0.0, 1.0)
	var pull := clampf(s - 1.0, 0.0, 1.0)
	weapon.bolt.rotation = Vector3(0, 0, float(weapon.bolt_action[0]) * turn)
	weapon.bolt.position = weapon.bolt_rest + Vector3(0, 0, float(weapon.bolt_action[1]) * pull)


func _reload_left_target(t: float) -> Vector3:
	var hg: Vector3 = weapon.support.global_position
	var well: Vector3 = weapon.mag_well.global_position
	var pouch := chest.global_transform * Vector3(-0.07, -0.02, -0.25)
	var charge: Vector3 = weapon.charge.global_position
	if fp_mode and fp_arm_rig != null:
		hg = fp_arm_rig.grip_transform(weapon, 0, weapon.support.global_transform).origin
		var wb := weapon.global_transform.basis.orthonormalized()
		well += wb * Vector3(-0.025, -0.025, 0.025)
		charge += wb * Vector3(-0.025, 0.018, 0.02)
	var keys: Array
	if _reload_empty and weapon.bolt_action.is_empty():
		# onto the charging handle (or the slide's rear serrations), draw it back
		# the full stroke with the action, let go, then back to the handguard
		var rk := _rack_times()
		var back: Vector3 = weapon.global_transform.basis.z.normalized() * weapon.blowback * 1.3
		keys = [[0.0, hg], [0.12, well], [0.2, well], [0.36, pouch], [0.46, pouch], [0.62, well],
				[0.7, well], [rk.x, charge], [rk.y, charge + back], [0.84, charge + back],
				[0.9, charge + back * 1.4], [1.0, hg]]
	elif _reload_empty:
		keys = [[0.0, hg], [0.12, well], [0.2, well], [0.36, pouch], [0.46, pouch], [0.62, well],
				[0.7, well], [1.0, hg]]
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

## Turns a limb toward `target` by rotation only, keeping its scale: zombie limbs
## are scaled, and Basis.slerp on a scaled basis logs an error every call.
static func _slerp_rot(n: Node3D, target: Basis, k: float) -> void:
	n.quaternion = n.quaternion.slerp(target.get_rotation_quaternion(), k)


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
			_slerp_rot(thighs[i], thigh_rest, k)
			var bend := -0.75 if i == _death_knee else -0.1   # one knee stays bent
			var thigh_lift := 0.45 if i == _death_knee else 0.0
			_slerp_rot(thighs[i], Basis.from_euler(Vector3(thigh_lift, 0.0, 0.0)) * thigh_rest, k)
			_slerp_rot(shins[i], Basis.from_euler(Vector3(bend, 0.0, 0.0)), k)
			_slerp_rot(feet[i], Basis.from_euler(Vector3(0.35, 0.0, side * 0.2)), k)
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
		_slerp_rot(spine, Basis.from_euler(Vector3(0.12, 0.15, 0.1)), slump_blend)
		_slerp_rot(head, Basis.from_euler(Vector3(0.2, 0.7 * signf(_death_roll), 0.25)), slump_blend)
	else:
		_slerp_rot(spine, Basis.from_euler(Vector3(-0.35, 0.2, 0.15)), slump_blend)
		_slerp_rot(head, Basis.from_euler(Vector3(-0.5, 0.4, 0.3)), slump_blend)
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
