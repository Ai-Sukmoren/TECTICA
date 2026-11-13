extends SceneTree
## Newer attachments: stat changes apply, the taped dual mag makes every
## second reload fast, and hollow points do less to armoured plates.
##   godot --headless --path . -s res://tests/attachment_mech_test.gd
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func ticks(n: int) -> void:
	for i in n:
		await physics_frame

func run() -> void:
	var base := Data.compute("m4a1", {})
	var t := {
		"prism": Data.compute("m4a1", {"optic": "prism"}),
		"heavy": Data.compute("m4a1", {"muzzle": "heavy_suppressor"}),
		"boost": Data.compute("m4a1", {"muzzle": "booster"}),
		"stubby": Data.compute("m4a1", {"underbarrel": "stubby"}),
		"nogrip": Data.compute("m4a1", {"underbarrel": "none"}),
		"hand": Data.compute("m4a1", {"underbarrel": "handstop"}),
		"hollow": Data.compute("m4a1", {"magazine": "hollow"}),
		"fold": Data.compute("m4a1", {"stock": "folding"}),
	}
	var holo := Data.compute("m4a1", {"optic": "holo"})
	var acog := Data.compute("m4a1", {"optic": "acog"})
	check(float(t.prism.zoom) > float(holo.zoom) and float(t.prism.zoom) < float(acog.zoom), "prism zoom sits between holo and ACOG")
	check(bool(t.heavy.suppressed) and float(t.heavy.noise_radius) < float(Data.compute("m4a1", {"muzzle": "suppressor"}).noise_radius), "heavy suppressor is quieter than the suppressor")
	check(float(t.boost.rpm) > float(base.rpm) and float(t.boost.recoil) > float(base.recoil), "booster: faster, more recoil")
	check(float(t.stubby.recoil) < float(t.nogrip.recoil) and float(t.stubby.ads_speed) > float(base.ads_speed), "stubby grip: less recoil than no grip, faster aim than the vertical grip")
	check(float(t.hand.ads_speed) > float(base.ads_speed) and float(t.hand.spread_move) < float(base.spread_move), "handstop: faster ADS, steadier moving")
	check(float(t.hollow.damage) > float(base.damage) and bool(t.hollow.get("hollow", false)), "hollow points hit harder")
	check(float(t.fold.ads_speed) > float(base.ads_speed) and float(t.fold.mobility) > float(base.mobility) and float(t.fold.recoil) > float(base.recoil), "folding stock: fast, mobile, kicks")
	var mini := Data.compute("mk23", {"optic": "minidot"})
	check(String(mini.attachments.optic) == "minidot", "pistols take the mini red dot")
	check(Data.sanitize("mgp7", {"optic": "acog"}).optic == "acog", "MGP7 now takes an ACOG")

	# live: dual mag reload times alternate
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	p.set_loadout([["m4a1", {"magazine": "dual"}], ["knife_combat", {}]])
	await ticks(30)
	var durs: Array = []
	for n in 4:
		var w = p.current_weapon()
		w.ammo = 5
		w.reserve = 300
		p.start_reload()
		durs.append(p.reload_duration)
		await ticks(int(p.reload_duration * Engine.physics_ticks_per_second) + 10)
	print("    dual mag reloads: ", durs)
	check(durs[0] < durs[1] * 0.6 and durs[2] < durs[3] * 0.6 and is_equal_approx(durs[1], durs[3]), "every second reload is fast")

	# hollow points against an armoured infected's front plate
	main.director._spawn_one("armored")
	var z = main.enemies[main.enemies.size() - 1]
	z.set_physics_process(false)
	z.global_position = p.global_position + Vector3(0, 0, -3)
	z.aim_yaw = PI   # facing +z, toward the player
	await ticks(2)
	var hit: Vector3 = z.global_position + Vector3(0, 1.0, 0.2)
	var dir := Vector3(0, 0, -1)
	p.set_loadout([["m4a1", {"magazine": "standard"}], ["knife_combat", {}]])
	z.max_health = 10000.0
	z.health = 10000.0
	z.apply_damage(100.0, hit, dir, p)
	var plain: float = 10000.0 - z.health
	p.set_loadout([["m4a1", {"magazine": "hollow"}], ["knife_combat", {}]])
	z.health = 10000.0
	z.apply_damage(100.0, hit, dir, p)
	var hp: float = 10000.0 - z.health
	print("    armour plate: standard %.1f, hollow %.1f" % [plain, hp])
	check(plain < 100.0 and is_equal_approx(hp, plain * 0.5), "hollow points do half to armour plates")

	print("ATTACH MECH: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
