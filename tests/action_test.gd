extends SceneTree
## Every semi / full-auto gun with a moving slide or bolt runs it back on a
## shot and returns; a pistol's slide locks back on its last round. A skin
## paints the attachments too but leaves optic glass and reticles alone.
##   godot --headless --path . -s res://tests/action_test.gd
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	for id in Data.PRIMARIES + Data.SECONDARIES:
		var w = Weapon.new()
		root.add_child(w)
		w.setup(id)
		if String(w.stats.cycle) != "":
			print("  %-7s manual action (%s), cycled by the rig" % [id, w.stats.cycle])
			w.free()
			continue
		if w.bolt == null:
			print("  %-7s no moving slide / bolt in its model" % id)
			w.free()
			continue
		w._kick_action()
		var peak := 0.0
		for i in 12:
			w._update_blowback(0.01)
			peak = maxf(peak, w.bolt.position.z)
		print("  %-7s travel %.3f m, rests at %.4f" % [id, peak, w.bolt.position.z])
		check(peak > w.blowback * 0.8 and absf(w.bolt.position.z) < 0.001, "%s action runs back and returns" % id)
		if w.is_pistol():
			w.ammo = 0
			w._kick_action()
			for i in 12:
				w._update_blowback(0.01)
			check(w.bolt.position.z > w.blowback * 0.9, "%s slide locks back when empty" % id)
			w.ammo = 5
			w._update_blowback(0.01)
			check(absf(w.bolt.position.z) < 0.001, "%s slide closes after a reload" % id)
		w.free()
	# skins: the gun's skin leaves the attachments alone; an attachment given its own finish takes it,
	# and glass and reticles keep their own look
	var Skins = load("res://scripts/skins/skins.gd")
	var finish: String = Skins.FINISHES.keys()[1]
	var sk = Weapon.new()
	root.add_child(sk)
	sk.setup("as_val", {"optic": "reddot", "underbarrel": "laser"})
	Skins.apply(sk._model_root, finish, [])
	var untouched := true
	for n in sk.find_children("*", "MeshInstance3D", true, false):
		if String((n as MeshInstance3D).get_parent().name).begins_with("Att_"):
			for s2 in (n as MeshInstance3D).mesh.get_surface_count():
				var cur2 = (n as MeshInstance3D).get_surface_override_material(s2)
				untouched = untouched and not (cur2 is ShaderMaterial and (cur2 as ShaderMaterial).shader == Skins.finish_shader())
	check(untouched, "the gun's skin leaves the attachments in their factory look")
	Skins.apply(sk._model_root, finish, [], {"optic": finish, "underbarrel": finish, "side": finish})
	var painted := 0
	var glass_kept := 0
	var glow_kept := 0
	for n in sk.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not String(mi.get_parent().name).begins_with("Att_"):
			continue
		for s2 in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s2)
			var cur := mi.get_surface_override_material(s2)
			var nm := src.resource_name if src != null else ""
			if nm == "glass":
				glass_kept += 1 if cur != null and (cur as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0
			elif src is BaseMaterial3D and (src as BaseMaterial3D).emission_enabled:
				glow_kept += 1 if cur == null else 0
			elif cur != null:
				painted += 1
	print("  skin %s on attachments: painted %d, glass kept %d, reticles kept %d" % [finish, painted, glass_kept, glow_kept])
	check(painted >= 2 and glass_kept >= 1 and glow_kept >= 1, "a part skin paints the attachments but keeps glass clear and the reticle lit")
	sk.free()
	print("ACTION: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
