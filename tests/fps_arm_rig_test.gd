extends SceneTree
## Source skin, all weapons/attachments, action contact, cancellation, FPS/TP.
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
var failures := 0
var samples := 0
var worst_contact := 0.0
var worst_length := 0.0
var worst_trigger := 0.0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FPS_ARMS " + label)

func sample(rig, label: String) -> void:
	var skin = rig.fp_arm_rig
	for i in 2:
		var c: Dictionary = skin.chains[i]
		var u: Transform3D = skin.poses[c.u]
		var l: Transform3D = skin.poses[c.l]
		var h: Transform3D = skin.poses[c.h]
		check(u.is_finite() and l.is_finite() and h.is_finite(), label + " finite bones")
		var length_error := maxf(absf(u.origin.distance_to(l.origin) - float(c.a)), absf(l.origin.distance_to(h.origin) - float(c.b)))
		worst_length = maxf(worst_length, length_error)
		check(length_error < 0.0001, label + " fixed bone lengths")
		var hand_frame: Basis = h.basis * (skin.rest[c.h] as Transform3D).basis.inverse() * (c.frame as Basis)
		var palm: Vector3 = skin.skel.global_transform * (h.origin + hand_frame * (c.palm as Vector3))
		var error: float = palm.distance_to(rig.hands[i].global_position)
		worst_contact = maxf(worst_contact, error)
		check(error < 0.001, label + " mesh palm follows IK target (%.4f)" % error)
		check(absf(h.basis.determinant() - 1.0) < 0.001, label + " no mirrored or scaled wrist")
	if rig.inspect_t > 0.14 and rig.inspect_t < 0.88 and not rig.weapon.is_melee():
		var inv: Transform3D = rig.fp_eye.affine_inverse()
		check((inv * rig.hands[0].global_position).x < (inv * rig.hands[1].global_position).x, label + " inspect hands stay ordered")
		check((inv * rig.elbows[0].global_position).x < (inv * rig.elbows[1].global_position).x, label + " inspect elbows stay ordered")
	var model := String(rig.weapon.stats.model)
	if skin.TRIGGERS.has(model):
		var grip: Transform3D = skin.grip_transform(rig.weapon, 1, rig.weapon.grip.global_transform)
		if rig.hands[1].global_position.distance_to(grip.origin) < 0.011:
			var distal: Transform3D = skin.poses[skin.skel.find_bone("Index 1.R")]
			var tip: Vector3 = skin.skel.global_transform * (distal * Vector3(0,0.016,0))
			var target: Vector3 = rig.weapon.global_transform * skin.TRIGGERS[model]
			var gap := tip.distance_to(target)
			worst_trigger = maxf(worst_trigger, gap)
			check(gap < 0.004, label + " index pad on trigger %.4f" % gap)
	samples += 1

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var rig = Rig.new()
	scene.add_child(rig)
	rig.build(Palettes.player())
	rig.set_process(false)
	check(rig.fp_arm_rig == null, "no skinned-arm cost in top-down")
	rig.set_first_person(true)
	var skin = rig.fp_arm_rig
	check(skin != null and skin.skel.get_bone_count() == 39, "supplied 39-bone deform rig loaded")
	if skin == null:
		quit(1)
		return
	for mi in skin.meshes:
		for s in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(s)
			var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			for v in a[Mesh.ARRAY_VERTEX].size():
				var total := 0.0
				for k in 4:
					var ix: int = v * 4 + k
					total += weights[ix]
					check(weights[ix] >= 0.0 and bones[ix] < mi.skin.get_bind_count(), "valid skin influence")
				check(absf(total - 1.0) < 0.001, "normalized skin weights")
	var configs := 0
	for id in Data.WEAPONS:
		var variants: Array = [{}]
		if "gp25" in Data.WEAPONS[id].options.underbarrel:
			variants.append({"underbarrel": "gp25"})
		if "hex" in Data.WEAPONS[id].options.handguard:
			variants.append({"handguard": "hex"})
		for attachments in variants:
			var w = Weapon.new()
			w.setup(id, attachments)
			rig.set_weapon(w, [])
			w.set_process(false)
			check(skin.PROFILES.has(w.stats.model), id + " explicit grip profile")
			check(skin.Contacts.DATA.has(skin.contact_key(w)), id + " %s has measured hand contact (run tools/fit_hand_contacts.py)" % skin.contact_key(w))
			var ammo: int = w.ammo
			for hz in [30, 60, 144]:
				var dt: float = 1.0 / hz
				rig.aim_target = 0
				rig.sprint_target = 0
				rig.one_hand_sprint = true
				for n in hz:
					rig._animate(dt)
				# Idle, recoil, ADS and sprint at three update rates.
				for action in ["idle", "walk", "fire", "ads", "sprint"]:
					rig.move_velocity = Vector3(0.4, 0, -2.7) if action == "walk" else Vector3.ZERO
					rig.aim_target = 1.0 if action == "ads" else 0.0
					rig.sprint_target = 1.0 if action == "sprint" else 0.0
					if action == "fire":
						rig.add_recoil(0.05)
					for n in hz:
						rig._animate(dt)
						sample(rig, id + " " + action)
					rig.aim_target = 0
					rig.sprint_target = 0
				for n in hz:
					rig._animate(dt)
				rig.play_inspect()
				for n in int(hz * Rig.INSPECT_DURATION) + 1:
					rig._animate(dt)
					sample(rig, id + " inspect")
				rig.cancel_inspect()
				for empty in ([] if w.is_melee() else [false, true]):
					rig.play_reload(2.0, empty)
					for n in hz * 2 + 1:
						rig._animate(dt)
						sample(rig, id + " reload")
					rig.cancel_reload()
				if w.stats.has("cycle"):
					rig.cycle_t = 0.0
					rig._cycle_dur = 1.0
					for n in hz + 1:
						rig._animate(dt)
						sample(rig, id + " cycle")
					rig.cycle_t = -1.0
			# Interrupted reload returns smoothly, without abandoning the hand pose.
			if not w.is_melee():
				rig.play_reload(2.0, false)
				for n in 50:
					rig._animate(1.0 / 60.0)
				var before: Vector3 = rig.hands[0].global_position
				rig.cancel_reload()
				rig._animate(1.0 / 60.0)
				check(before.distance_to(rig.hands[0].global_position) < 0.04, id + " interrupted reload blends")
			for n in 30:
				rig._animate(1.0 / 60.0)
			check(w.ammo == ammo, id + " arm animation never changes ammo")
			rig.set_first_person(false)
			check(not skin.visible, id + " supplied arms hidden in top-down")
			rig._animate(1.0 / 60.0)
			rig.set_first_person(true)
			rig.weapon = null
			w.free()
			configs += 1
		print("FPS_ARMS tested ", id)
	rig.shoulders[0].visible = false
	rig.shoulders[1].visible = false
	skin.pose(1.0 / 60.0)
	check(not skin.visible, "scope hides the new skin with the existing shoulders")
	rig.shoulders[0].visible = true
	rig.shoulders[1].visible = true
	skin.pose(1.0 / 60.0)
	check(skin.visible, "scope exit restores the new skin")
	print("FPS_ARMS configs=%d samples=%d max_palm_error=%.6f max_length_error=%.6f max_trigger_error=%.6f failures=%d" % [configs, samples, worst_contact, worst_length, worst_trigger, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
