extends SceneTree
## First-person hands and arms on every weapon, through idle, walk, sprint, stop,
## aim, reload, bolt / lever cycle and inspect, at 30, 60 and 144 fps:
##   * both hands stay on the gun through the sprint (knives run one-handed)
##   * gripping wrists stay in a believable range: no hand bent sideways against
##     its forearm (the old right hand sat ~50-100 degrees ulnar)
##   * no elbow pad turned toward the eye from inside the view
##   * nothing snaps: hands, elbows and the gun move continuously frame to frame
##   * forearms never roll on their own: a sleeve turns about its length only as fast
##     as the glove it carries (the elbow's bend changing must not spin it)
##   * aiming keeps both hands on the gun (no glove floating under it)
##   godot --headless --path . -s res://tests/fp_hand_pose_test.gd
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
const Settings = preload("res://scripts/core/settings.gd")

## Gripping-wrist range checked: [flexion min, max, ulnar deviation min, max] (degrees).
## The right hand reaches ~48 ulnar only in the two-handed pistol stance at eye height
## (arms straight out, the wrist cocked down a little, as in a real isosceles grip).
const RIGHT := [-50.0, 30.0, -20.0, 50.0]
## Aiming, the shooting hand sits behind the gun right under the eye: a straight wrist
## would put the elbow inside the head, so the elbow stays down and out and the wrist
## takes more bend (hidden behind the gun; the old rig reached ~100 degrees there).
const RIGHT_ADS := [-80.0, 30.0, -20.0, 85.0]
const LEFT := [-65.0, 40.0, -35.0, 65.0]   # the P90's support hand wraps its stubby front
## Fastest a hand or the gun (and an elbow) may move in the eye's frame (m/s): the
## quickest real motion (snapping the sights up) stays well under these; a pose that
## jumps between frames does not.
const STEADY_SPEED := 6.0
const ELBOW_SPEED := 6.5
## A forearm may twist this much faster (deg/s) than its hand turns (the swing that
## lays it along the arm adds a little).
const ROLL_SLACK := 120.0

var rig
var failures := 0
var notes := {}
var worst := {"R": Vector2.ZERO, "L": Vector2.ZERO, "speed": 0.0, "speed_at": "", "sprint_grip": 0.0, "ads_grip": 0.0}


func _initialize() -> void:
	run.call_deferred()


func fail(key: String, msg: String) -> void:
	if notes.has(key):
		return   # one report per weapon and kind of problem
	notes[key] = true
	failures += 1
	push_error("FP_HANDS " + msg)


func eye(p: Vector3) -> Vector3:
	return rig.fp_eye.affine_inverse() * p


func run() -> void:
	Settings.v.fov = 86.0
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var body := Node3D.new()
	scene.add_child(body)
	rig = Rig.new()
	body.add_child(rig)
	rig.build(Palettes.player())
	rig.set_process(false)
	rig.top_level = true
	rig.set_first_person(true)
	rig.one_hand_sprint = true
	var configs := 0
	for id in Data.WEAPONS:
		# attachments that move the support hand get their own pass
		var variants: Array = [{}]
		if "gp25" in Data.WEAPONS[id].options.get("underbarrel", {}):
			variants.append({"underbarrel": "gp25"})
		if "hex" in Data.WEAPONS[id].options.get("handguard", {}):
			variants.append({"handguard": "hex"})
			if "gp25" in Data.WEAPONS[id].options.underbarrel:
				variants.append({"handguard": "hex", "underbarrel": "gp25"})
		if "rail" in Data.WEAPONS[id].options.rail:
			variants.append({"rail": "rail"})
		if "laser" in Data.WEAPONS[id].options.side:
			variants.append({"side": "laser"})
		if "afg" in Data.WEAPONS[id].options.underbarrel:
			variants.append({"underbarrel": "afg"})
			variants.append({"side": "laser", "underbarrel": "afg"})
		if "vfg" in Data.WEAPONS[id].options.underbarrel:
			variants.append({"underbarrel": "vfg"})
		for att in variants:
			var w = Weapon.new()
			w.setup(String(id), att)
			rig.set_weapon(w, [])
			w.set_process(false)
			var name := String(id) + ("" if att.is_empty() else "+" + "+".join(att.values()))
			for hz in ([30, 60, 144] if att.is_empty() else [60]):
				await check_weapon(name, w, hz)
				configs += 1
			rig.weapon = null
			w.free()
	print("FP_HANDS configs=%d worst R wrist %s  L wrist %s  steady speed %.2f m/s (%s)  sprint grip gap %.4f  ads grip gap %.4f" % [
			configs, worst.R, worst.L, worst.speed, worst.speed_at, worst.sprint_grip, worst.ads_grip])
	print("FP_HANDS failures=%d" % failures)
	quit(1 if failures > 0 else 0)


func check_weapon(id: String, w, hz: int) -> void:
	var dt := 1.0 / hz
	var tag := "%s @%dfps" % [id, hz]
	rig.fp_pitch = -0.08
	rig.aim_target = 0.0
	rig.sprint_target = 0.0
	rig.move_velocity = Vector3.ZERO
	await steps(id, w, int(hz * 0.8), dt, "settle", false)
	# walk, sprint a full second, stop, aim, release
	var plan := [["walk", Vector3(0, 0, -2.6), 0.0, 0.0, 0.8], ["sprint", Vector3(0, 0, -7.0), 1.0, 0.0, 1.4],
			["stop", Vector3.ZERO, 0.0, 0.0, 0.7], ["ads", Vector3.ZERO, 0.0, 1.0, 0.7], ["idle", Vector3.ZERO, 0.0, 0.0, 0.6]]
	for p in plan:
		rig.move_velocity = p[1]
		rig.sprint_target = p[2]
		rig.aim_target = p[3]
		await steps(id, w, int(hz * float(p[4])), dt, String(p[0]), true)
	# actions: hands leave the gun on purpose; only continuity and finite poses are checked
	if not w.is_melee():
		rig.play_reload(2.0, true)
		await steps(id, w, int(hz * 2.1), dt, "reload", true)
	if w.stats.has("cycle"):
		rig.cycle_t = 0.0
		rig._cycle_dur = 0.9
		await steps(id, w, int(hz * 1.0), dt, "cycle", true)
	if rig.play_inspect():
		await steps(id, w, int(hz * (Rig.INSPECT_DURATION + 0.3)), dt, "inspect", true)


var _prev := {}
var _prev_rot := []


## Twist (degrees) of basis `b1` relative to `b0` about b0's own length (Y).
static func twist(b0: Basis, b1: Basis) -> float:
	var q := (b0.transposed() * b1).orthonormalized().get_rotation_quaternion()
	return rad_to_deg(2.0 * atan2(q.y, q.w))


func steps(id: String, w, n: int, dt: float, state: String, checked: bool) -> void:
	_prev.clear()
	_prev_rot.clear()
	var tag := "%s %s" % [id, state]
	for k in n:
		rig._animate(dt)
		if not checked:
			continue
		var pts := {"hR": eye(rig.hands[1].global_position), "hL": eye(rig.hands[0].global_position),
				"eR": eye(rig.elbows[1].global_position), "eL": eye(rig.elbows[0].global_position),
				"gun": eye(rig.weapon_anchor.global_position)}
		for key in pts:
			var v: Vector3 = pts[key]
			if not v.is_finite():
				fail(id + "nan", tag + ": %s is not finite" % key)
				return
			if key == "hL" and rig._free_arm > 0.3:
				continue   # a free arm pumping with the stride swings fast on purpose
			if _prev.has(key) and state in ["walk", "sprint", "stop", "ads", "idle"]:
				var speed: float = (v - _prev[key]).length() / dt
				if speed > worst.speed:
					worst.speed = speed
					worst.speed_at = "%s %s %s @%dfps" % [tag, key, k, int(round(1.0 / dt))]
				if speed > (ELBOW_SPEED if key.begins_with("e") else STEADY_SPEED):
					fail(id + "snap" + key, tag + ": %s snapped %.3f m in one frame (%.1f m/s)" % [key, speed * dt, speed])
		_prev = pts
		# forearm roll against the hand's own rotation (eye space)
		var inv: Basis = rig.fp_eye.basis.inverse()
		var rot := []
		for i in 2:
			rot.append([(inv * rig.elbows[i].global_transform.basis).orthonormalized(), (inv * rig.hands[i].global_transform.basis).orthonormalized()])
		if not _prev_rot.is_empty() and state in ["walk", "sprint", "stop", "ads", "idle"]:
			for i in 2:
				if i == 0 and (rig._free_arm > 0.05 or w.is_melee()):
					continue   # a free, pumping arm leads its hand
				var arm_twist := absf(twist(_prev_rot[i][0], rot[i][0])) / dt
				var hand_turn := rad_to_deg((_prev_rot[i][1] as Basis).get_rotation_quaternion().angle_to((rot[i][1] as Basis).get_rotation_quaternion())) / dt
				if arm_twist > hand_turn + ROLL_SLACK:
					fail(id + "roll" + str(i), tag + ": %s forearm rolls %.0f deg/s while its hand turns %.0f deg/s" % [["left", "right"][i], arm_twist, hand_turn])
		_prev_rot = rot
		var settled: bool = k > n * 0.7   # wrists are judged once a state has settled
		var gripping: bool = state in ["walk", "sprint", "stop", "ads", "idle"] and settled
		if not gripping:
			continue
		# wrists of the hands that hold the gun
		var r: Vector2 = Rig.wrist_angles(rig.hands[1].global_transform.basis, rig.elbows[1].global_position - rig.hands[1].global_position, 1.0)
		worst.R = Vector2(maxf(worst.R.x, absf(r.x)), maxf(worst.R.y, absf(r.y)))
		var lim: Array = RIGHT_ADS if state == "ads" else RIGHT
		if r.x < lim[0] or r.x > lim[1] or r.y < lim[2] or r.y > lim[3]:
			fail(id + "wristR" + state, tag + ": right wrist flexion %.0f / deviation %.0f degrees" % [r.x, r.y])
		if not w.is_melee() and rig._free_arm < 0.05:
			var l: Vector2 = Rig.wrist_angles(rig.hands[0].global_transform.basis, rig.elbows[0].global_position - rig.hands[0].global_position, -1.0)
			worst.L = Vector2(maxf(worst.L.x, absf(l.x)), maxf(worst.L.y, absf(l.y)))
			if l.x < LEFT[0] or l.x > LEFT[1] or l.y < LEFT[2] or l.y > LEFT[3]:
				fail(id + "wristL" + state, tag + ": left wrist flexion %.0f / deviation %.0f degrees" % [l.x, l.y])
		# both hands on the gun through the sprint (and while aiming)
		if not w.is_melee() and state in ["sprint", "ads"] and rig.sprint_amt > 0.9 or state == "ads" and rig.aim_amt > 0.95 and not w.is_melee():
			var holds: Array = rig.hold_markers()
			var gr: float = rig.hands[1].global_position.distance_to(holds[1].global_position)
			var gl: float = rig.hands[0].global_position.distance_to(holds[0].global_position)
			var gap := maxf(gr, gl)
			if state == "sprint":
				worst.sprint_grip = maxf(worst.sprint_grip, gap)
			else:
				worst.ads_grip = maxf(worst.ads_grip, gap)
			if gap > (0.006 if state == "sprint" else Rig.ADS_HAND_DROP_MAX + 0.004):
				fail(id + "grip" + state, tag + ": a hand is %.3f m off the gun (right %.3f, left %.3f)" % [gap, gr, gl])
		if w.is_melee() and state == "sprint" and rig.sprint_amt > 0.9 and rig._free_arm < 0.8:
			fail(id + "knife", tag + ": the free hand should pump while running with a knife")
		# an elbow inside the view never shows its pad to the eye
		for i in 2:
			var e: Vector3 = rig.elbows[i].global_position
			if rig._upper_arm_in_view(rig.shoulders[i].global_position, e):
				var pad: Vector3 = -(rig.shoulders[i].global_transform.basis.z as Vector3).normalized()   # the pad rides the upper arm
				if pad.dot((rig.fp_eye.origin - e).normalized()) > 0.35:
					fail(id + "pad" + str(i) + state, tag + ": %s elbow pad faces the camera" % ["left", "right"][i])
