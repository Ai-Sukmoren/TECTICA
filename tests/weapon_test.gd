extends SceneTree
## Builds every weapon with every attachment option and fires it.
##   godot --headless --path . -s res://tests/weapon_test.gd
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
var main
var f := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
func _physics_process(_d: float) -> bool:
	f += 1
	if f == 2:
		main.hud._deploy()
	if f == 10:
		var p = main.player
		var built := 0
		for id in Data.PRIMARIES + Data.SECONDARIES:
			var w: Dictionary = Data.WEAPONS[id]
			for slot in Data.SLOTS:
				for opt in w.options[slot]:
					var att: Dictionary = w.defaults.duplicate()
					att[slot] = opt
					p.set_loadout([[id, att], ["mk23", {}]])
					var wp = p.current_weapon()
					var o: Vector3 = wp.ads_offset
					assert(is_finite(o.x) and o.y < 0.0 and o.z < 0.0, "bad ads offset %s %s" % [id, att])
					wp.cooldown = 0.0
					var r = p.try_fire(p.global_position + Vector3(0, 1.3, -10))
					built += 1
		print("[weapons] built+fired %d weapon/attachment configs OK" % built)
		for id in Data.PRIMARIES + Data.SECONDARIES:
			var s := Data.compute(id, Data.WEAPONS[id].defaults)
			print("  %-8s dmg %5.1f x%d  rpm %4d  mag %3d  recoil %.2f  mob %.2f  ads %.2f  zoom %.1f" % [id, s.damage, s.pellets, s.rpm, s.mag, s.recoil, s.mobility, s.ads_speed, s.zoom])
		var a := Data.compute("m4a1", {"muzzle": "compensator", "underbarrel": "vgrip", "stock": "heavy", "magazine": "drum"})
		print("  m4a1 comp+vgrip+heavy+drum: recoil %.3f (base 0.85)  mag %d  reload %.2f" % [a.recoil, a.mag, a.reload])
		var b := Data.compute("m4a1", {"muzzle": "suppressor"})
		print("  m4a1 suppressor: suppressed=%s noise %.1f sound %s" % [b.suppressed, b.noise_radius, b.sound])
	if f == 30:
		return true
	return false
