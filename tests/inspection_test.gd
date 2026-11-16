extends SceneTree
## Cosmetic action regression: every weapon, both views, cadence and cancels.
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("[inspect] FAIL " + label)

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var rig = Rig.new()
	scene.add_child(rig)
	rig.build(Palettes.player())
	rig.set_process(false)
	var cases := 0
	for id in Data.PRIMARIES + Data.SECONDARIES:
		var weapon = Weapon.new()
		weapon.setup(id)
		if weapon.grip == null or weapon.support == null:
			check(false, "%s model failed to build" % id)
			weapon.free()
			quit(1)
			return
		rig.set_weapon(weapon, [])
		weapon.set_process(false)
		for fp in [false, true]:
			rig.set_first_person(fp)
			for hz in [30, 60, 144]:
				check(rig.play_inspect(), "%s start" % id)
				check(not rig.play_inspect(), "repeated input does not restart")
				var ammo: int = weapon.ammo
				for i in int(ceil(Rig.INSPECT_DURATION * hz)) + 1:
					rig._animate(1.0 / hz)
					check(rig.weapon_anchor.transform.is_finite(), "%s finite transform" % id)
					var view: Transform3D = rig.fp_eye if fp else rig.chest.global_transform
					if fp:
						var relative: Transform3D = rig.fp_eye.affine_inverse() * rig.weapon_anchor.global_transform
						check(relative.origin.z < -0.15, "%s camera clearance" % id)
					if rig.inspect_t > 0.12 and rig.inspect_t < 0.88 and not weapon.is_melee():
						# the forearms never cross: the support hand stays left of the grip hand
						var lh: Vector3 = view.affine_inverse() * rig.hands[0].global_position
						var rh: Vector3 = view.affine_inverse() * rig.hands[1].global_position
						check(lh.x < rh.x, "%s hands do not cross (fp %s, t %.2f)" % [id, fp, rig.inspect_t])
						# one side only: the gun's left flank faces the viewer the whole time
						var flank: Vector3 = (view.basis.inverse() * weapon.global_transform.basis.x).normalized()
						check(flank.z < 0.0, "%s shows only its left side (fp %s, t %.2f)" % [id, fp, rig.inspect_t])
				check(rig.inspect_t < 0.0, "%s completed at %d Hz" % [id, hz])
				check(weapon.ammo == ammo, "inspection never consumes ammo")
				cases += 1
		for action in ["reload", "switch", "throw", "vault", "kick", "fire", "aim", "sprint", "slide"]:
			check(rig.play_inspect(), "start before " + action)
			rig._animate(0.1)
			match action:
				"reload": rig.play_reload(1.0, false)
				"switch": rig.play_switch(0.4)
				"throw": rig.play_throw(0.7)
				"vault": rig.play_vault(0.6, 0.8, Vector3.ZERO)
				"kick": rig.play_kick(0.56)
				"fire": rig.add_recoil(0.0)
				"aim": rig.aim_target = 1.0
				"sprint": rig.sprint_target = 1.0
				"slide": rig.slide_target = 1.0
			rig._animate(1.0 / 60.0)
			check(rig.inspect_t < 0.0, "%s interrupt by %s" % [id, action])
			rig.cancel_reload()
			rig.switch_t = -1.0
			rig.throw_t = -1.0
			rig.vault_t = -1.0
			rig.kick_t = -1.0
			rig.aim_target = 0.0
			rig.sprint_target = 0.0
			rig.slide_target = 0.0
		# cut short mid-inspect, the gun eases back instead of snapping to the hold
		for i in 120:
			rig._animate(1.0 / 60.0)
		check(rig.play_inspect(), "%s start before the blend-out" % id)
		for i in int(Rig.INSPECT_DURATION * 0.4 * 60.0):
			rig._animate(1.0 / 60.0)
		var held: Vector3 = rig.weapon_anchor.position
		rig.aim_target = 1.0
		rig._animate(1.0 / 60.0)
		var jump: float = rig.weapon_anchor.position.distance_to(held)
		check(jump < 0.03, "%s inspect interrupted without a snap (moved %.3f m in one frame)" % [id, jump])
		rig.aim_target = 0.0
		for i in 60:
			rig._animate(1.0 / 60.0)
		rig.weapon = null
		weapon.free()
	print("[inspect] ", cases, " weapon/view/rate cases; all action interrupts; failures=", failures)
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
