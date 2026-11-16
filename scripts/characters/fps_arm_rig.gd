extends Node3D
## Retarget the supplied FPS skin to the existing SoldierRig action timelines.
## Hand targets are palm centres; canonical Y follows fingers, Z faces the palm.
## No AnimationPlayer competes with IK. Rest lengths/skin binds never change live.
const ASSET := "res://assets/thirdparty/fps_arms/fps_arms.glb"
## Measured skin-to-gun contact; regenerate with tools/fit_hand_contacts.py.
const Contacts = preload("res://scripts/characters/fps_hand_contacts.gd")
const FINGERS := ["Index", "Middle", "Ring", "Little", "Thumb"]
const ELBOW_SWING := 0.85        # share of the wrist-straightening elbow swing applied
const ELBOW_SWING_MAX := 3.1     # radians either side of the authored elbow pole
const RELOAD_RELAX := 0.6        # how far the magazine-grabbing hand relaxes its wrist
const ELBOW_HANG := 0.5         # elbow bend direction keeps at least this much "down"
const FOREARM_ROLL := 0.85      # share of the hand's roll the forearm carries
# Relaxed wrist tilt toward the little finger (degrees) the arm aims for: a shooting
# hand on a pistol grip sits about 20 degrees ulnar; the support hand nearer straight.
const NATURAL_ULNAR := {"L": 8.0, "R": 20.0}
const SHOULDER_FOLLOW := 0.6    # share of the straight-forearm shoulder move applied
const SHOULDER_MAX := 0.10       # metres the shoulder may drift from its eye anchor
const CLOSED_CURL := [1.08, 1.25, 0.75]
const GRIP_CURL := [0.28, 1.50, 0.90]
const THUMB_CURL := [0.38, 0.55, 0.42]
const TRIGGER_CURL := [0.45, 1.15, 0.60]
# Finger-pad contacts measured in weapon space from the trigger meshes.
const TRIGGERS := {
	"hk33": Vector3(0.004, -0.014, -0.058), "aug_a1": Vector3(0.004, 0.004, -0.049),
	"scar_h": Vector3(0.004, 0.030, -0.054), "as_val": Vector3(0.004, 0.032, -0.061),
	"uar10": Vector3(0.004, 0.033, -0.057), "l96a1": Vector3(0.004, 0.045, -0.053),
	"mosin": Vector3(0.004, -0.023, -0.069), "marlin": Vector3(0.004, -0.020, -0.048),
	"mgp7": Vector3(0.004, 0.025, -0.061), "gepard": Vector3(0.004, 0.020, -0.058),
	"p90": Vector3(0.004, 0.020, -0.057), "g17": Vector3(0.004, 0.021, -0.057),
	"zc57": Vector3(0.004, 0.025, -0.049), "vp9": Vector3(0.004, 0.009, -0.052),
}

# Each model has its own palm offsets, hand pitch, support roll and finger curl.
# Offsets are relative to the weapon's existing Grip/Support markers, in metres.
# [right offset, left offset, right pitch, support roll, right curl, left curl]
const PROFILES := {
	"hk33": [Vector3(0.026, -0.008, 0.025), Vector3(-0.020, -0.024, 0.012), -0.62, 0.10, 1.12, 1.02],
	"aug_a1": [Vector3(0.027, -0.010, 0.022), Vector3(-0.024, -0.018, 0.014), -0.65, 0.72, 1.08, 1.18],
	"scar_h": [Vector3(0.029, -0.012, 0.028), Vector3(-0.023, -0.029, 0.015), -0.58, 0.08, 1.06, 0.96],
	"as_val": [Vector3(0.025, -0.008, 0.024), Vector3(-0.021, -0.022, 0.014), -0.60, 0.16, 1.15, 1.08],
	"uar10": [Vector3(0.028, -0.010, 0.025), Vector3(-0.022, -0.027, 0.018), -0.62, 0.12, 1.10, 1.00],
	"l96a1": [Vector3(0.030, 0.008, 0.045), Vector3(-0.022, -0.030, 0.020), -0.54, 0.06, 1.02, 0.94],
	"mosin": [Vector3(0.028, 0.000, 0.032), Vector3(-0.021, -0.026, 0.016), -0.34, 0.04, 0.98, 1.06],
	"marlin": [Vector3(0.027, -0.006, 0.026), Vector3(-0.022, -0.025, 0.014), -0.40, 0.10, 1.04, 1.10],
	"mgp7": [Vector3(0.025, -0.010, 0.024), Vector3(-0.022, -0.030, 0.016), -0.64, 0.66, 1.16, 1.20],
	"gepard": [Vector3(0.024, -0.008, 0.023), Vector3(-0.020, -0.024, 0.012), -0.60, 0.18, 1.18, 1.14],
	"p90": [Vector3(0.025, -0.008, 0.022), Vector3(-0.023, -0.020, 0.020), -0.46, 0.45, 1.08, 1.12],
	"g17": [Vector3(0.024, -0.006, 0.022), Vector3(-0.010, -0.006, 0.018), -0.64, 0.00, 1.18, 1.12],
	"zc57": [Vector3(0.026, -0.008, 0.020), Vector3(-0.012, -0.006, 0.016), -0.58, 0.00, 1.12, 1.08],
	"vp9": [Vector3(0.025, -0.008, 0.024), Vector3(-0.011, -0.005, 0.020), -0.62, 0.00, 1.15, 1.10],
	"knife_combat": [Vector3(0.022, -0.010, 0.018), Vector3.ZERO, -0.70, 0.0, 1.24, 0.25],
	"karambit": [Vector3(0.020, -0.005, 0.015), Vector3.ZERO, -0.65, 0.0, 1.28, 0.28],
	"butterfly": [Vector3(0.021, -0.008, 0.016), Vector3.ZERO, -0.68, 0.0, 1.22, 0.26],
}

var rig: Node3D
var skel: Skeleton3D
var meshes: Array[MeshInstance3D] = []
var chains: Array[Dictionary] = []
var rest: Array[Transform3D] = []
var local_rest: Array[Transform3D] = []
var poses: Array[Transform3D] = []
var fingers := {}
var curls := {}
var profile: Array = PROFILES.hk33
# {"shift": [L, R] palm offsets in weapon space, "curl": [[5 L], [5 R]]}; a curl
# below zero (trigger finger, nothing to grip) keeps the profile's amount.
var contact: Dictionary = {}
var _last_reload := -1.0
var _last_left := Transform3D.IDENTITY
var _return_from := Transform3D.IDENTITY
var _return_time := 1.0

static func frame(direction: Vector3, normal: Vector3) -> Basis:
	var y := direction.normalized()
	var z := normal - y * normal.dot(y)
	if z.length_squared() < 0.000001:
		z = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP)
	z = z.normalized()
	return Basis(y.cross(z).normalized(), y, z)

func setup(owner_rig: Node3D) -> bool:
	rig = owner_rig
	if not ResourceLoader.exists(ASSET):
		return false
	var model := (load(ASSET) as PackedScene).instantiate()
	add_child(model)
	skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return false
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).active = false
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2.0
		mi.visibility_range_end = 0.0
		var material := mi.get_active_material(0).duplicate() as BaseMaterial3D
		if material != null:
			# The shadow-only world body has different arm proportions. Its contact
			# shadows must not dither across the first-person skin.
			material.disable_receive_shadows = true
			mi.material_override = material
		meshes.append(mi)
	for b in skel.get_bone_count():
		rest.append(skel.get_bone_global_rest(b))
		local_rest.append(skel.get_bone_rest(b))
		poses.append(rest[b])
	for side in ["L", "R"]:
		var u := skel.find_bone("Upper Arm." + side)
		var l := skel.find_bone("Forearm." + side)
		var h := skel.find_bone("Hand." + side)
		if mini(u, mini(l, h)) < 0:
			return false
		var mid := skel.find_bone("Middle 3." + side)
		var normal := Vector3.RIGHT if side == "L" else Vector3.LEFT
		var hf := frame(rest[mid].origin - rest[h].origin, normal)
		chains.append({"u": u, "l": l, "h": h,
			"a": rest[u].origin.distance_to(rest[l].origin), "b": rest[l].origin.distance_to(rest[h].origin),
			"frame": hf, "palm": hf.inverse() * (rest[mid].origin - rest[h].origin) * 0.52,
			# The natural forearm direction in the canonical hand frame: the modelled
			# straight wrist, tilted toward the little finger by the side's natural
			# deviation (rotating about the palm normal, toward the thumb side).
			"forearm": Basis(Vector3.BACK, -_thumb_side(hf, rest[h].origin, side) * deg_to_rad(NATURAL_ULNAR[side])) \
				* (hf.inverse() * (rest[h].origin - rest[l].origin).normalized())})
		for f in ["Index", "Middle", "Ring", "Little", "Thumb"]:
			for j in 3:
				var b := skel.find_bone("%s %d.%s" % [f, 3 - j, side])
				var axis := (rest[b].basis * Vector3.UP).cross(normal).normalized()
				fingers[b] = [0 if side == "L" else 1, f, j, rest[b].basis.inverse() * axis]
				curls[b] = 0.0
	return true

## +1 when the thumb lies on the hand frame's +X side, else -1.
func _thumb_side(hf: Basis, wrist: Vector3, side: String) -> float:
	var thumb := rest[skel.find_bone("Thumb 3." + side)].origin - wrist
	return 1.0 if thumb.dot(hf.x) >= 0.0 else -1.0

func select_weapon(weapon: Node3D) -> void:
	profile = PROFILES.get(String(weapon.stats.model), PROFILES.hk33)
	contact = Contacts.DATA.get(contact_key(weapon), {})
	_last_reload = -1.0
	_return_time = 1.0

## Attachments that change the surface under a hand get their own contact fit.
static func contact_key(weapon: Node3D) -> String:
	var key := String(weapon.stats.model)
	if weapon.attachments.get("underbarrel", "") == "gp25":
		key += "+gp25"
	if weapon.attachments.get("handguard", "") == "hex":
		key += "+hex"
	return key

func settle_left(target: Transform3D, delta: float) -> Transform3D:
	var relative: Transform3D = rig.fp_eye.affine_inverse() * target
	if _last_reload >= 0.0 and _last_reload < 0.94 and rig.reload_t < 0.0:
		_return_from = _last_left
		_return_time = 0.0
	_return_time = minf(1.0, _return_time + delta / 0.16)
	if _return_time < 1.0:
		relative = _return_from.interpolate_with(relative, smoothstep(0.0, 1.0, _return_time))
	_last_left = relative
	_last_reload = rig.reload_t
	return rig.fp_eye * relative

func grip_transform(weapon: Node3D, side: int, source: Transform3D) -> Transform3D:
	var wb := weapon.global_basis.orthonormalized()
	var p: Vector3 = profile[0 if side == 1 else 1]
	var hf: Basis
	if side == 1:
		p.y += 0.010 if not weapon.is_melee() else 0.0
		hf = frame(Vector3(0, float(profile[2]) * 0.25, -1.0), Vector3.LEFT)
	elif weapon.is_pistol():
		p += Vector3(-0.012, 0.012, -0.027)
		hf = frame(Vector3(0, -0.12, -1.0), Vector3.RIGHT)
	elif String(weapon.stats.model) == "aug_a1" and weapon.launcher == null:
		# The AUG's vertical foregrip: fingers stack down the grip, palm on its left side.
		p = Vector3(-0.027, -0.013, 0.026)
		hf = frame(Vector3(0.0, -0.14, -1.0), Vector3.RIGHT)
	else:
		# Palm cups the underside; fingertips rise on the far side of the tube.
		p += Vector3(0.013, -0.007, 0.008)
		hf = frame(Vector3(0.90, -0.30, -0.30), Vector3(0.25, 1.0, 0))
	var origin := Vector3.ZERO
	if contact.has("shift"):
		origin = wb * (contact.shift[side] as Vector3)   # measured in weapon space
	# Melee Grip markers already carry the reverse-grip / blade orientation.
	if weapon.is_melee() and side == 1:
		wb = source.basis.orthonormalized()
	return Transform3D(wb * hf, source.origin + wb * p + origin)

func reload_basis(weapon: Node3D, t: float, held: Basis) -> Basis:
	var wb := weapon.global_basis.orthonormalized()
	var grasp := wb * frame(Vector3(0.35, 0.7, -0.4), Vector3.RIGHT)
	var w := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.78, 1.0, t))
	if rig._reload_empty and weapon.bolt_action.is_empty():
		var rack := smoothstep(0.70, 0.76, t) * (1.0 - smoothstep(0.90, 1.0, t))
		grasp = grasp.slerp(wb * frame(Vector3.RIGHT, Vector3.DOWN), rack)
	return held.slerp(grasp, w)

func pose(delta: float) -> void:
	# Player already hides the procedural shoulders for a full-screen scope.
	# Follow that visibility contract so the new skin cannot cover the scope.
	visible = rig.fp_mode and (rig.shoulders[0].visible or rig.shoulders[1].visible)
	if skel == null or rig.weapon == null or not visible:
		return
	var inv := skel.global_transform.affine_inverse()
	for b in poses.size():
		poses[b] = rest[b]
	for i in 2:
		var c: Dictionary = chains[i]
		var target: Transform3D = rig.hands[i].global_transform
		var hf := (inv.basis * target.basis).orthonormalized()
		var wrist: Vector3 = inv * target.origin - hf * (c.palm as Vector3)
		var shoulder: Vector3 = inv * rig.shoulders[i].global_position
		var pole: Vector3 = inv * rig.elbows[i].global_position
		if i == 0:
			# A hand that lets go of the gun (sprint pump, knife, the magazine grab) relaxes
			# in line with its arm instead of keeping the handguard grip's wrist angle.
			var relax: float = rig._free_arm
			if rig.reload_t >= 0.0:
				var t: float = rig.reload_t
				relax = maxf(relax, RELOAD_RELAX * smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.78, 1.0, t)))
			if relax > 0.001:
				var natural: Vector3 = hf * (c.forearm as Vector3)
				var relaxed := Basis(Quaternion(natural, (wrist - shoulder).normalized())) * hf
				hf = hf.slerp(relaxed.orthonormalized(), relax).orthonormalized()
				wrist = inv * target.origin - hf * (c.palm as Vector3)
		var a: float = c.a
		var b: float = c.b
		# The off-screen shoulder follows the gun the way a shooter's does: toward the
		# point that lets the forearm run straight into the hand (limited, so the upper
		# arm never swings into view).
		var neutral: Vector3 = hf * (c.forearm as Vector3)
		var ideal_elbow := wrist - neutral * b
		var follow := (ideal_elbow + (shoulder - ideal_elbow).normalized() * a - shoulder) * SHOULDER_FOLLOW
		shoulder += follow.limit_length(SHOULDER_MAX)
		var to := wrist - shoulder
		var length := to.length()
		var dir := to.normalized() if length > 0.00001 else Vector3.FORWARD
		# Translate the off-screen shoulder rather than stretch the skin or lose grip.
		var reach := (a + b) * 0.985
		if length > reach:
			shoulder += dir * (length - reach)
		var d := clampf(length, absf(a - b) + 0.001, reach)
		var bend := pole - shoulder - dir * (pole - shoulder).dot(dir)
		if bend.length_squared() < 0.000001:
			bend = inv.basis * rig.fp_eye.basis * Vector3(-1.0 if i == 0 else 1.0, -1.0, 0.3)
			bend -= dir * bend.dot(dir)
		bend = bend.normalized()
		# Swing the elbow round the shoulder-wrist line until the forearm points the way
		# the hand's own (straight-wrist) forearm would. The hand never moves, so grips
		# hold; the wrist stops kinking. Closed form: smooth frame to frame.
		var across := neutral - dir * neutral.dot(dir)
		var swing_w := clampf(across.length() / 0.3, 0.0, 1.0) * ELBOW_SWING
		if swing_w > 0.0:
			var other := dir.cross(bend)
			var swing := clampf(atan2(-across.dot(other), -across.dot(bend)), -ELBOW_SWING_MAX, ELBOW_SWING_MAX) * swing_w
			# Elbows hang: keep the swing inside the arc where the elbow points at least
			# ELBOW_HANG down (view space), so no upper arm swings out into the view.
			var down: Vector3 = (inv.basis * rig.fp_eye.basis * Vector3.DOWN).normalized()
			var p := bend.dot(down)
			var q := other.dot(down)
			var r := sqrt(p * p + q * q)
			if r > ELBOW_HANG:
				var centre := atan2(q, p)
				var half := acos(ELBOW_HANG / r)
				swing = centre + clampf(wrapf(swing - centre, -PI, PI), -half, half)
			else:
				swing = atan2(q, p)   # cannot hang that low: hang as low as possible
			bend = bend.rotated(dir, swing)
		var along := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
		var elbow := shoulder + dir * (a * along) + bend * (a * sqrt(maxf(0, 1.0 - along * along)))
		wrist = shoulder + dir * d
		var normal: Vector3 = Vector3.RIGHT if i == 0 else Vector3.LEFT
		var elbow_normal: Vector3 = (inv.basis * rig.fp_eye.basis * normal).normalized()
		var ub := _limb_basis(c.u, rest[c.l].origin - rest[c.u].origin, normal, elbow - shoulder, elbow_normal)
		# Pronation happens along the forearm, not in the wrist: the forearm takes most of
		# the hand's roll so the wrist skin does not wring.
		var forearm_normal := elbow_normal.slerp(hf.z, FOREARM_ROLL)
		var lb := _limb_basis(c.l, rest[c.h].origin - rest[c.l].origin, normal, wrist - elbow, forearm_normal)
		poses[c.u] = Transform3D(ub, shoulder)
		poses[c.l] = Transform3D(lb, elbow)
		poses[c.h] = Transform3D(hf * (c.frame as Basis).transposed() * rest[c.h].basis, wrist)
	# Bones are imported parent-first. Only fingers need their hierarchical FK.
	for b in poses.size():
		if fingers.has(b):
			var f: Array = fingers[b]
			var value := _finger_curl(f[0], f[1], f[2])
			curls[b] = lerpf(float(curls[b]), value, 1.0 - exp(-22.0 * delta))
			var opposition := Basis.IDENTITY
			if f[1] == "Thumb" and f[2] == 0:
				var cf: Basis = chains[f[0]].frame
				var wanted := cf.y * 0.9 + cf.x * (0.15 if f[0] == 1 else -0.15) + cf.z * 0.1
				if f[0] == 0 and not rig.weapon.is_pistol():
					wanted = -cf.x * 0.9 + cf.y * 0.4 + cf.z * 0.12
				opposition = Basis(Quaternion(Vector3.UP, (rest[b].basis.inverse() * wanted).normalized()))
				if f[0] == 0:
					opposition = opposition.slerp(Basis.IDENTITY, rig._free_arm)
			var curl: float = curls[b]
			if f[1] == "Thumb" and f[0] == 0:
				curl *= 0.22
			poses[b] = poses[skel.get_bone_parent(b)] * local_rest[b] * Transform3D(opposition * Basis(f[3], curl), Vector3.ZERO)
	_fit_trigger(inv)
	for b in poses.size():
		var parent := skel.get_bone_parent(b)
		var local := poses[parent].affine_inverse() * poses[b] if parent >= 0 else poses[b]
		skel.set_bone_pose_position(b, local.origin)
		skel.set_bone_pose_rotation(b, local.basis.orthonormalized().get_rotation_quaternion())

func _fit_trigger(inv: Transform3D) -> void:
	var weapon: Node3D = rig.weapon
	var id := String(weapon.stats.model)
	if not TRIGGERS.has(id):
		return
	# Detach naturally while the right hand works a bolt, throws or twirls.
	var grip := grip_transform(weapon, 1, weapon.grip.global_transform)
	var distance: float = rig.hands[1].global_position.distance_to(grip.origin)
	var weight := 1.0 - smoothstep(0.012, 0.045, distance)
	if weight <= 0.0:
		return
	var a := skel.find_bone("Index 3.R")
	var b := skel.find_bone("Index 2.R")
	var c := skel.find_bone("Index 1.R")
	var wb := (inv.basis * weapon.global_basis).orthonormalized()
	var tip: Vector3 = inv * (weapon.global_transform * TRIGGERS[id])
	var distal := wb * Vector3(-0.88, -0.08, 0.46).normalized()
	var tip_length := 0.016
	var target := tip - distal * tip_length
	var start := poses[a].origin
	var l1 := local_rest[b].origin.length()
	var l2 := local_rest[c].origin.length()
	var toward := target - start
	var d := clampf(toward.length(), absf(l1 - l2) + 0.0001, l1 + l2 - 0.0001)
	var dir := toward.normalized()
	var pole := wb * Vector3(0.8, 0.1, -1.0)
	pole = (pole - dir * pole.dot(dir)).normalized()
	var along := clampf((l1*l1 + d*d - l2*l2) / (2*l1*d), -1, 1)
	var middle := start + dir * (l1*along) + pole * (l1*sqrt(maxf(0, 1-along*along)))
	var end := start + dir*d
	var desired := [middle-start, end-middle, distal]
	var origins := [start, middle, end]
	var index := 0
	for bone in [a,b,c]:
		var basis := frame(desired[index], wb * Vector3.UP)
		# Preserve the authored bone roll while aiming its length axis.
		basis = basis * frame(rest[bone].basis.y, Vector3.UP).transposed() * rest[bone].basis
		poses[bone] = poses[bone].interpolate_with(Transform3D(basis, origins[index]), weight)
		index += 1

func _limb_basis(bone: int, from: Vector3, hint: Vector3, to: Vector3, normal: Vector3) -> Basis:
	return frame(to, normal) * frame(from, hint).transposed() * rest[bone].basis

func _finger_curl(side: int, finger: String, joint: int) -> float:
	var amount: float = profile[4 if side == 1 else 5]
	if contact.has("curl"):
		var measured: float = contact.curl[side][FINGERS.find(finger)]
		if measured >= 0.0:
			amount = measured
	var values := GRIP_CURL if side == 1 or String(rig.weapon.stats.model) == "aug_a1" else CLOSED_CURL
	if finger == "Thumb":
		values = THUMB_CURL
	elif finger == "Index" and side == 1 and not rig.weapon.is_melee():
		values = TRIGGER_CURL
	# Release / regrasp during the existing action timeline; smooth FK prevents pops.
	if side == 0:
		amount = lerpf(amount, 0.22, rig._free_arm)
		if rig.reload_t >= 0.0:
			var t: float = rig.reload_t
			var open := smoothstep(0.0, 0.07, t) * (1.0 - smoothstep(0.08, 0.16, t))
			open += smoothstep(0.87, 0.92, t) * (1.0 - smoothstep(0.94, 1.0, t))
			amount = lerpf(amount, 0.18, clampf(open, 0.0, 1.0))
	elif rig.cycle_t >= 0.0 and not rig.weapon.bolt_action.is_empty():
		var t: float = rig.cycle_t
		var work := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.79, 0.95, t))
		amount = lerpf(amount, 0.62 if finger == "Index" else 0.9, work)
	return float(values[joint]) * amount
