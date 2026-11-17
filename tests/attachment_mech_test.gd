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
	var base := Data.compute("mgp7", {})
	var sup := Data.compute("mgp7", {"muzzle": "suppressor"})
	var heavy := Data.compute("mgp7", {"muzzle": "heavy_suppressor"})
	var hollow := Data.compute("mgp7", {"magazine": "hollow"})
	var holo := Data.compute("mgp7", {"optic": "holo"})
	var dot := Data.compute("mgp7", {"optic": "reddot"})
	check(float(holo.zoom) > float(dot.zoom) and float(dot.zoom) > float(base.zoom), "holo zooms more than the red dot, which zooms more than irons")
	check(bool(heavy.suppressed) and float(heavy.noise_radius) < float(sup.noise_radius), "heavy suppressor is quieter than the suppressor")
	check(float(Data.compute("mgp7", {"muzzle": "flash_hider"}).flash) < float(base.flash), "flash hider dims the flash")
	check(float(hollow.damage) > float(base.damage) and bool(hollow.get("hollow", false)), "hollow points hit harder")
	check(bool(Data.compute("as_val", {"underbarrel": "laser"}).laser), "the AS VAL takes the PEQ-2 laser")
	check(Data.sanitize("mgp7", {"optic": "acog"}).optic == "iron", "removed attachments fall back to the default")
	check(bool(Data.compute("g17", {"muzzle": "suppressor"}).suppressed), "the Glock takes a suppressor")

	# live: dual mag reload times alternate
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "warehouse"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	p.set_loadout([["hk33", {"magazine": "dual"}], ["knife_combat", {}]])
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
	p.set_loadout([["hk33", {"magazine": "standard"}], ["knife_combat", {}]])
	z.max_health = 10000.0
	z.health = 10000.0
	z.apply_damage(100.0, hit, dir, p)
	var plain: float = 10000.0 - z.health
	p.set_loadout([["hk33", {"magazine": "hollow"}], ["knife_combat", {}]])
	z.health = 10000.0
	z.apply_damage(100.0, hit, dir, p)
	var hp: float = 10000.0 - z.health
	print("    armour plate: standard %.1f, hollow %.1f" % [plain, hp])
	check(plain < 100.0 and is_equal_approx(hp, plain * 0.5), "hollow points do half to armour plates")

	print("ATTACH MECH: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
