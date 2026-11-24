extends SceneTree
## Weapon visual / mechanism regression:
## - every optic sits flush on its gun's top rail (no float, no sinking in)
## - the add-on rail never runs into a magazine, trigger guard or grip
## - guns with their own accessory rail (SCAR-H, Glock 17, ZC57) get no add-on rail
## - no part is left in the flat white of palette-named materials; the L96A1's
##   loose cartridge is gone
## - turn-bolt rifles (L96A1, Mosin) lift, draw, push and lower the bolt on its
##   axis, with the right hand on the handle, and each has its own stroke
## - an empty reload works the action: a rifle's carrier is drawn back and let
##   go, a pistol's locked slide closes before the reload ends
##   godot --headless --path . -s res://tests/weapon_polish_test.gd
const Model = preload("res://scripts/weapons/weapon_model.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func _box(f: PackedVector3Array) -> AABB:
	var a := AABB(f[0], Vector3.ZERO)
	for v in f:
		a = a.expand(v)
	return a

func run() -> void:
	for id in Data.PRIMARIES + Data.SMGS + Data.SECONDARIES:
		var w: Dictionary = Data.WEAPONS[id]
		var model := String(w.model)
		# optics flush on the rail
		for o in w.options.optic:
			if not Model.LP_OPTICS.has(o):
				continue
			var r: Node3D = Model.build(model, Data.sanitize(id, {"optic": o})).root
			var mount: Node3D = r.find_child("OpticMount", true, false)
			var of := Model._faces_of(mount)
			var ob := _box(of)
			var base_y := mount.position.y + ob.position.y
			var top := Model._top_under(Model.Probe.new(Model._faces_of(r, mount)), mount.position.z + ob.position.z, mount.position.z + ob.end.z)
			# a gun's own sight from its model (the MCX's EOTech) clamps round the rail: its jaws reach down the
			# rail's sides, so its lowest point may sit up to 12 mm below the rail's top, never above it
			var factory := mount.find_children("*", "Node3D", true, false).any(func(n): return n.has_meta("factory_part"))
			var ok := (base_y - top) < 0.003 and (base_y - top) > -0.012 if factory else absf(base_y - top) < 0.003
			check(ok, "%s %s sits on the rail (gap %+.1f mm)" % [id, o, (base_y - top) * 1000.0])
			r.free()
		# the add-on rail clears everything under the gun
		var with_rail: bool = "rail" in w.options.rail
		if with_rail or w.options.underbarrel.size() > 1:
			var bottom: String = w.options.underbarrel[-1]
			var r2: Node3D = Model.build(model, Data.sanitize(id, {"rail": "rail", "underbarrel": bottom})).root
			var rail: Node3D = r2.find_child("Att_rail", true, false)
			check((rail != null) == with_rail, "%s %s add-on rail" % [id, "gets the" if with_rail else "keeps its own rail: no"])
			if rail != null:
				var rb := Model._holder_box(rail)   # in the mount's space
				var at := (rail.get_parent() as Node3D).position
				var faces := Model._faces_of(r2, rail.get_parent())   # the gun alone, not the rail or the laser under it
				# the rail's own top surface (it tilts to follow a sloped handguard), in the gun's space
				var rail_faces := PackedVector3Array()
				for v in Model._faces_of(rail.get_parent()):
					rail_faces.append(Transform3D(Basis.IDENTITY, at) * v)
				var worst := INF
				for k in 9:
					# along the bar (its clamp posts at the ends sink into the gun on purpose)
					var z := at.z + lerpf(rb.position.z + rb.size.z * 0.2, rb.end.z - rb.size.z * 0.2, k / 8.0)
					var rail_top := Model._top_in(rail_faces, z)
					if is_finite(rail_top):
						worst = minf(worst, Model._bottom_in(faces, z) - rail_top)
				check(worst > -0.0025, "%s rail does not run into the gun (%+.1f mm)" % [id, worst * 1000.0])
			r2.free()
		# no flat-white palette parts, no stray cartridge
		var r3: Node3D = Model.build(model, w.defaults).root
		var white := []
		for n in r3.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat == null:
					continue
				if mat.resource_name == "blt":
					white.append("cartridge")
				elif mat.resource_name in ["1w", "1g"] and mi.get_surface_override_material(s) == null:
					white.append(mat.resource_name)
		check(white.is_empty(), "%s has no flat-white or stray parts %s" % [id, white])
		r3.free()

	# --- turn-bolt cycle on the rig
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var rig = Rig.new()
	scene.add_child(rig)
	rig.build(Palettes.player())
	rig.set_process(false)
	var strokes := {}
	for id in ["l96a1", "mosin"]:
		var wpn = Weapon.new()
		wpn.setup(id)
		rig.set_weapon(wpn, [])
		wpn.set_process(false)
		rig.set_first_person(true)
		for i in 30:
			rig._animate(1.0 / 60.0)
		check(wpn.bolt_action.size() == 2, "%s is a turn-bolt rifle" % id)
		wpn.cycle_pending = 0.001
		var max_turn := 0.0
		var max_back := 0.0
		var hand_gap := INF
		var t := 0
		while t < 200 and (rig.cycle_t >= 0.0 or t < 3):
			rig._animate(1.0 / 60.0)
			max_turn = maxf(max_turn, wpn.bolt.rotation.z)
			max_back = maxf(max_back, wpn.bolt.position.z - wpn.bolt_rest.z)
			if rig.cycle_t > Rig.BOLT_LIFT and rig.cycle_t < Rig.BOLT_FWD:
				hand_gap = minf(hand_gap, rig.hands[1].global_position.distance_to(wpn.charge.global_position))
			t += 1
		check(absf(max_turn - float(wpn.bolt_action[0])) < 0.02, "%s handle lifts %.0f deg" % [id, rad_to_deg(max_turn)])
		check(absf(max_back - float(wpn.bolt_action[1])) < 0.003, "%s bolt draws back %.0f mm" % [id, max_back * 1000.0])
		check(wpn.bolt.position.distance_to(wpn.bolt_rest) < 0.001 and absf(wpn.bolt.rotation.z) < 0.001, "%s bolt closes and locks" % id)
		check(hand_gap < 0.07, "%s right hand works the handle (%.0f mm off)" % [id, hand_gap * 1000.0])
		strokes[id] = [max_turn, max_back]
		rig.weapon = null
		wpn.free()
	check(strokes.mosin[0] > strokes.l96a1[0] + 0.3 and strokes.mosin[1] > strokes.l96a1[1], "Mosin and L96A1 strokes differ")

	# --- empty reloads work the action
	for id in ["hk33", "g17"]:
		var wpn = Weapon.new()
		wpn.setup(id)
		rig.set_weapon(wpn, [])
		wpn.set_process(false)   # stepped by hand below, in step with the rig
		if wpn.is_pistol():
			wpn.ammo = 1
			wpn._kick_action()
			wpn.ammo = 0
			for i in 20:
				wpn._process(1.0 / 60.0)
			check(wpn.bolt.position.z > wpn.blowback * 0.9, "%s slide locked back on empty" % id)
		else:
			wpn.ammo = 0
		rig.play_reload(2.0, true)
		var peak := 0.0
		var closed_at := -1.0
		for i in 130:
			rig._animate(1.0 / 60.0)
			wpn._process(1.0 / 60.0)
			if rig.reload_t >= 0.0:
				peak = maxf(peak, wpn.bolt.position.z)
				if closed_at < 0.0 and rig.reload_t > 0.84 and wpn.bolt.position.z < 0.002:
					closed_at = rig.reload_t
		check(peak > wpn.blowback * 1.1, "%s action drawn back by hand (%.0f mm)" % [id, peak * 1000.0])
		check(closed_at > 0.0 and closed_at < 1.0, "%s action closes before the reload ends (t %.2f)" % [id, closed_at])
		rig.weapon = null
		wpn.free()
	scene.queue_free()
	await process_frame
	print("WEAPON POLISH: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
