extends SceneTree
## Zombie Survival shop: the run starts with pistol + knife, hits and kills
## earn points, the shop opens only between waves and sells a primary, ammo,
## healing, grenades, gun upgrades and perks; purchases survive going down.
##   godot --headless --path . -s res://tests/zombie_shop_test.gd
const Main = preload("res://scripts/main.gd")
const Shop = preload("res://scripts/modes/zombie_shop.gd")
const Player = preload("res://scripts/characters/player.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var p = main.player
	var dir = main.director
	var shop = dir.shop
	dir.timer = 999.0

	# --- start: pistol and knife only
	var ids: Array = p.weapons.map(func(w): return String(w.id))
	print("  starting weapons: ", ids)
	check(p.weapons.size() == 2, "zombie run starts with two weapons")
	check(p.weapons[0].is_pistol() and p.weapons[1].is_melee(), "a pistol and a knife")
	check(shop.points == Shop.START_POINTS, "starting points")

	# --- the shop is open between waves, closed during one
	check(main.hud._shop_available(), "shop available before the first wave")
	dir.active = true
	check(not main.hud._shop_available(), "no shop during a wave")
	dir.active = false

	# --- points
	var before: int = shop.points
	shop.on_hit(false, false)
	shop.on_hit(true, false)
	shop.on_hit(true, true)
	check(shop.points - before == Shop.HIT_POINTS + Shop.KILL_POINTS + Shop.KILL_POINTS + Shop.HEADSHOT_POINTS, "hit / kill / headshot points")
	var wb: int = shop.wave_bonus(3)
	check(wb == 250, "wave 3 bonus is 250")

	# --- can't afford, then buy a primary
	shop.points = 100
	check(shop.buy("gun_mp7", p) == "", "a gun you can't afford is refused")
	check(p.weapons.size() == 2, "nothing changed")
	shop.points = 5000
	var pistol_reserve: int = p.weapons[0].reserve
	check(shop.buy("gun_mp7", p) != "", "buys the MP7")
	ids = p.weapons.map(func(w): return String(w.id))
	print("  after buying: ", ids)
	check(p.weapons.size() == 3 and String(p.weapons[0].id) == "mp7", "MP7 is the primary")
	check(p.weapon_index == 0, "the new gun is in hand")
	check(p.weapons[1].reserve == pistol_reserve, "the pistol keeps its ammo")
	check(shop.points == 4000, "price taken")
	check(shop.buy("gun_mp7", p) == "", "can't buy the same gun twice")
	check(Player.zombie_specs.size() == 3, "net loadout carries the new gun")

	# --- upgrade the gun in hand
	var dmg0 := float(p.weapons[0].stats.damage)
	var mag0 := int(p.weapons[0].stats.mag)
	shop.points = 20000
	check(shop.buy("upgrade", p) != "", "upgrade to MK I")
	check(is_equal_approx(float(p.weapons[0].stats.damage), dmg0 * 1.3), "MK I: +30% damage")
	check(int(p.weapons[0].stats.mag) > mag0, "MK I: bigger magazine")
	shop.buy("upgrade", p)
	shop.buy("upgrade", p)
	check(shop.upgrade_tag("mp7") == "MK III", "upgrades stop at MK III")
	var pts_before: int = shop.points
	check(shop.buy("upgrade", p) == "" and shop.points == pts_before, "no fourth upgrade")
	check(is_equal_approx(float(p.weapons[0].stats.damage), dmg0 * 1.9), "MK III: +90% damage, no compounding")

	# --- perks
	var rl := float(p.weapons[0].stats.reload)
	shop.buy("perk_quick", p)
	check(is_equal_approx(float(p.weapons[0].stats.reload), rl * 0.6), "quick hands: faster reload")
	check(is_equal_approx(float(p.weapons[0].stats.damage), dmg0 * 1.9), "perks keep the upgrade damage")
	shop.buy("perk_tough", p)
	check(p.max_health == 150.0 and p.health == 150.0, "juggernaut vest: 150 max health")
	var rpm := float(p.weapons[0].stats.rpm)
	shop.buy("perk_rapid", p)
	check(is_equal_approx(float(p.weapons[0].stats.rpm), rpm * 1.25), "rapid fire: +25% rpm")

	# --- supplies
	p.weapons[0].reserve = 0
	shop.buy("ammo", p)
	check(p.weapons[0].reserve >= int(p.weapons[0].stats.reserve), "ammo refill")
	p.grenades = 4
	shop.buy("frag", p)
	check(p.grenades == 5, "frags cap at 5")
	p.health = 20.0
	shop.buy("heal", p)
	check(p.health == p.max_health, "medkit heals to full")

	# --- buying a new primary replaces the old one and drops its upgrades
	shop.buy("gun_ak47", p)
	check(String(p.weapons[0].id) == "ak47" and p.weapons.size() == 3, "AK-47 replaces the MP7")
	check(shop.upgrade_tag("mp7") == "" and shop.upgrade_tag("ak47") == "", "old upgrades are gone, new gun starts at MK 0")
	check(is_equal_approx(float(p.weapons[0].stats.reload), float(load("res://scripts/weapons/weapon_data.gd").compute("ak47", p.weapons[0].attachments).reload) * 0.6), "perks apply to the new gun")

	# --- wave end pays out, and the operator keeps everything after respawning
	var pts: int = shop.points
	dir.wave = 2
	dir.apply_wave_end()
	check(shop.points == pts + 200, "wave 2 cleared pays 200 points")
	main.respawn_local(p.global_position, 0.0)
	await process_frame
	var p2 = main.player
	ids = p2.weapons.map(func(w): return String(w.id))
	print("  after respawn: ", ids)
	check(p2 != p and String(p2.weapons[0].id) == "ak47", "respawned operator keeps the bought gun")
	check(p2.max_health == 150.0, "and the perks")

	# --- HUD panel opens, lists rows and closes
	main.hud._open_shop()
	check(main.hud.shop_open and dir.shop_open, "shop panel opens")
	check(main.hud._shop_rows_now().size() > 10, "shop lists its rows")
	var t0: float = dir.timer
	for i in 30: await physics_frame
	check(dir.timer == t0, "solo: break clock stops while shopping")
	main.hud._close_shop()
	check(not main.hud.shop_open, "shop panel closes")

	# --- other modes are untouched
	check(not Player.zombie_specs.is_empty(), "zombie specs set during the run")

	print("SHOP: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(failures)
