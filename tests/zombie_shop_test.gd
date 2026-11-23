extends SceneTree
## Zombie Survival shop: the run starts with a bare pistol + knife, hits and
## kills earn points, the shop opens only between waves at the arcade cabinet and
## sells a primary, ammo, healing, grenades, gun upgrades, perks and attachments
## for the gun in hand (bought guns come bare); purchases survive going down.
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
	Main.saved_map = "warehouse"
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
	var D = load("res://scripts/weapons/weapon_data.gd")
	var pid := String(p.weapons[0].id)
	check(p.weapons[0].attachments == D.sanitize(pid, {}), "the starting pistol is bare")

	# --- the shop opens only at the arcade, between waves
	var arcade = main.arcade
	check(arcade != null and arcade.placed, "an arcade cabinet stands on the map")
	print("  arcade at ", arcade.global_position, ", spawn ", p.global_position, ", %.1f m apart" % arcade.global_position.distance_to(p.global_position))
	check(absf(arcade.global_position.y - p.global_position.y) < 0.8, "the arcade stands on the operator's floor")
	p.global_position = arcade.global_position + Vector3(30, 0, 0)
	check(not main.hud._shop_available(), "no shop away from the arcade")
	p.global_position = arcade.global_position + arcade.global_transform.basis.z * 1.4
	check(main.hud._shop_available(), "shop available at the arcade before the first wave")
	check(p._interact_context(), "at the arcade F opens the shop, not the camera view / a reload")
	var away: Vector3 = p.global_position
	p.global_position = arcade.global_position + Vector3(30, 0, 0)
	check(not p._interact_context(), "away from the arcade F toggles the view again")
	p.global_position = away
	dir.active = true
	check(not main.hud._shop_available(), "no shop during a wave")
	check(not p._interact_context(), "during a wave F is the view toggle again")
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
	check(shop.buy("gun_marlin", p) == "", "a gun you can't afford is refused")
	check(p.weapons.size() == 2, "nothing changed")
	shop.points = 5000
	var pistol_reserve: int = p.weapons[0].reserve
	check(shop.buy("gun_marlin", p) != "", "buys the Marlin")
	ids = p.weapons.map(func(w): return String(w.id))
	print("  after buying: ", ids)
	check(p.weapons.size() == 3 and String(p.weapons[0].id) == "marlin", "the Marlin is the primary")
	check(p.weapons[0].attachments == D.sanitize("marlin", {}), "a bought gun comes bare")
	check(p.weapon_index == 0, "the new gun is in hand")
	check(p.weapons[1].reserve == pistol_reserve, "the pistol keeps its ammo")
	check(shop.points == 5000 - 1500, "price taken")
	check(shop.buy("gun_marlin", p) == "", "can't buy the same gun twice")
	check(Player.zombie_specs.size() == 3, "net loadout carries the new gun")

	# --- upgrade the rifle
	var dmg0 := float(p.weapons[0].stats.damage)
	var mag0 := int(p.weapons[0].stats.mag)
	shop.points = 20000
	check(shop.buy("upgrade:marlin", p) != "", "upgrade to MK I")
	check(is_equal_approx(float(p.weapons[0].stats.damage), dmg0 * 1.3), "MK I: +30% damage")
	check(int(p.weapons[0].stats.mag) > mag0, "MK I: bigger magazine")
	shop.buy("upgrade:marlin", p)
	shop.buy("upgrade:marlin", p)
	check(shop.upgrade_tag("marlin") == "MK III", "upgrades stop at MK III")
	var pts_before: int = shop.points
	check(shop.buy("upgrade:marlin", p) == "" and shop.points == pts_before, "no fourth upgrade")
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
	var res0 := int(p.weapons[0].stats.reserve)
	shop.buy("perk_mule", p)
	check(int(p.weapons[0].stats.reserve) == int(round(res0 * 1.6)), "ammo bandolier: +60% reserve capacity")
	check(p.weapons[0].reserve >= int(p.weapons[0].stats.reserve), "ammo bandolier fills the bigger reserve")
	shop.apply_mods(p)
	check(int(p.weapons[0].stats.reserve) == int(round(res0 * 1.6)), "bandolier does not stack on re-apply")

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
	shop.buy("gun_aug_a1", p)
	check(String(p.weapons[0].id) == "aug_a1" and p.weapons.size() == 3, "AUG A1 replaces the Marlin")
	check(shop.upgrade_tag("marlin") == "" and shop.upgrade_tag("aug_a1") == "", "old upgrades are gone, new gun starts at MK 0")
	check(is_equal_approx(float(p.weapons[0].stats.reload), float(load("res://scripts/weapons/weapon_data.gd").compute("aug_a1", p.weapons[0].attachments).reload) * 0.6), "perks apply to the new gun")

	# --- attachments for the gun in hand, for this run
	shop.points = 5000
	var att_rows: Array = shop.items(p).filter(func(r): return String(r.id).begins_with("att_"))
	print("  attachment rows for the AUG: ", att_rows.size())
	check(att_rows.size() >= 5, "the shop lists attachments for the gun in hand")
	var pts_a: int = shop.points
	var aug_ammo: int = p.weapons[0].ammo
	check(shop.buy("att_aug_a1:muzzle:suppressor", p) != "", "buys a suppressor")
	check(String(p.weapons[0].attachments.muzzle) == "suppressor" and bool(p.weapons[0].stats.suppressed), "the suppressor is on the AUG")
	check(shop.points == pts_a - Shop.ATT_PRICES.muzzle, "attachment price taken")
	check(p.weapons[0].ammo == aug_ammo, "the gun keeps its ammo")
	check(is_equal_approx(float(p.weapons[0].stats.reload), float(D.compute("aug_a1", p.weapons[0].attachments).reload) * 0.6), "perks still apply")
	check(shop.buy("att_aug_a1:muzzle:suppressor", p) == "", "can't buy a fitted attachment again")
	check(shop.buy("att_aug_a1:underbarrel:laser", p) != "" and String(p.weapons[0].attachments.underbarrel) == "laser", "a laser fits")
	check(String(p.weapons[0].attachments.rail) == "none", "on the AUG without a rail (it clamps to the barrel)")
	check(String(p.weapons[0].attachments.muzzle) == "suppressor", "earlier attachments stay")

	# --- an SMG adds the third gun, in its own slot next to the rifle
	shop.points = 5000
	check(shop.buy("smg_mgp7", p) != "", "buys the MGP7 SMG")
	ids = p.weapons.map(func(w): return String(w.id))
	print("  after the SMG: ", ids)
	check(p.weapons.size() == 4 and String(p.weapons[0].id) == "aug_a1" and String(p.weapons[1].id) == "mgp7", "rifle, SMG, pistol, knife")
	check(p.weapon_index == 1, "the SMG is in hand")
	check(Player.zombie_specs.size() == 4, "net loadout carries the SMG")
	shop.buy("smg_gepard", p)
	check(p.weapons.size() == 4 and String(p.weapons[1].id) == "gepard", "the Gepard replaces the MGP7")

	# --- every gun carried has its upgrade; attachments go on the gun picked in FIT TO
	var up_ids: Array = shop.items(p).filter(func(r): return String(r.id).begins_with("upgrade:")).map(func(r): return String(r.id).substr(8))
	var pistol_id := String(p.weapons[2].id)
	check(up_ids.size() == 3 and "aug_a1" in up_ids and "gepard" in up_ids and pistol_id in up_ids, "an upgrade row for every gun carried %s" % [up_ids])
	var rifle_dmg := float(p.weapons[0].stats.damage)
	var in_hand: int = p.weapon_index
	shop.points = 20000
	check(shop.buy("upgrade:" + pistol_id, p) != "" and shop.upgrade_tag(pistol_id) == "MK I", "upgrades the pistol without holding it")
	check(is_equal_approx(float(p.weapons[0].stats.damage), rifle_dmg), "the rifle is untouched")
	shop.fit_to = ""
	check(String(shop.fit_gun(p).id) == String(p.current_weapon().id), "FIT TO starts on the gun in hand")
	shop.fit_to = "aug_a1"
	var order: Array = []
	for k in 3:
		shop.cycle_fit(p, 1)
		order.append(String(shop.fit_gun(p).id))
	check(order == ["gepard", pistol_id, "aug_a1"], "FIT TO cycles through every gun carried %s" % [order])
	shop.fit_to = pistol_id
	var prows: Array = shop.items(p).filter(func(r): return String(r.id).begins_with("att_" + pistol_id + ":"))
	check(not prows.is_empty() and shop.items(p).filter(func(r): return String(r.id).begins_with("att_aug_a1:")).is_empty(), "the attachment rows follow the gun picked")
	var buy_id := String(prows[0].id)
	var part := buy_id.substr(4).split(":")
	check(shop.buy(buy_id, p) != "", "buys %s for the pistol" % buy_id)
	check(String(p.weapons[2].attachments[part[1]]) == part[2], "it goes on the pistol")
	check(p.weapon_index == in_hand and String(p.weapons[0].attachments.muzzle) == "suppressor", "the gun in hand stays in hand and keeps its own attachments")

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
	check(p2 != p and String(p2.weapons[0].id) == "aug_a1", "respawned operator keeps the bought gun")
	check(String(p2.weapons[0].attachments.muzzle) == "suppressor", "and its attachments")
	check(p2.max_health == 150.0, "and the perks")

	# --- HUD panel opens, lists rows and closes
	main.hud._open_shop()
	check(main.hud.shop_open and dir.shop_open, "shop panel opens")
	check(main.hud._shop_rows_now().size() > 10, "shop lists its rows")
	var t0: float = dir.timer
	for i in 30: await physics_frame
	check(dir.timer == t0, "solo: break clock stops while shopping")
	check(Player.input_blocked, "the open shop blocks operator input")
	dir._begin_wave()
	main.hud._process(0.0)
	check(not main.hud.shop_open and not dir.shop_open, "starting a wave closes the shop")
	check(not Player.input_blocked, "closing the shop on wave start restores input in the same HUD update")

	# --- other modes are untouched
	check(not Player.zombie_specs.is_empty(), "zombie specs set during the run")

	print("SHOP: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(failures)
