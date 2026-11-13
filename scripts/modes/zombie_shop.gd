extends RefCounted
## Zombie Survival economy: every operator starts the run with only a pistol
## and a knife, earns points by hitting and killing infected, and spends them
## in the shop between waves (B) on a primary, ammo, healing, grenades, gun
## upgrades and perks. Each peer runs its own wallet for its own operator;
## a new loadout is sent to the others as a "loadout" event.
##
## Points: hit 10, kill 60, headshot kill +40, wave cleared 100 + 50 x wave.
## Prices below are starting values, not tuned.

const Data = preload("res://scripts/weapons/weapon_data.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Collection = preload("res://scripts/skins/collection.gd")

const START_POINTS := 500
const HIT_POINTS := 10
const KILL_POINTS := 60
const HEADSHOT_POINTS := 40
const MAX_UPGRADE := 3

## Primary weapons for sale, cheapest first.
const GUNS := [
	["mp7", 1000], ["m870", 1250], ["mgp7", 1400], ["ak47", 1600],
	["m4a1", 1800], ["as_val", 2000], ["awp", 2200], ["m249", 3000],
]
## id -> [name, price, description]
const PERKS := {
	"tough": ["JUGGERNAUT VEST", 2500, "+50 MAX HEALTH, FASTER REGEN"],
	"quick": ["QUICK HANDS", 1500, "RELOAD 40% FASTER"],
	"rapid": ["RAPID FIRE", 2000, "FIRE RATE +25%"],
}

var points := START_POINTS
var earned := 0
var spent := 0
## Primary bought this run ("" = pistol only).
var primary := ""
## weapon id -> upgrade level 1..MAX_UPGRADE
var upgrades := {}
var perks := {}


## The weapon list an operator starts a zombie run with: the class pistol
## and the knife, no primary.
static func starting_specs() -> Array:
	var full: Array = Loadout.weapon_list()
	return [full[1], full[2]]


func earn(amount: int) -> void:
	points += amount
	earned += amount


func on_hit(killed: bool, headshot: bool) -> int:
	var gain := HIT_POINTS
	if killed:
		gain = KILL_POINTS + (HEADSHOT_POINTS if headshot else 0)
	earn(gain)
	return gain


func wave_bonus(wave: int) -> int:
	var b := 100 + 50 * wave
	earn(b)
	return b


func upgrade_price(level: int) -> int:
	return 1500 * (level + 1)


## Weapon specs for this operator: [primary?, pistol, knife].
func specs() -> Array:
	var base := starting_specs()
	if primary == "":
		return base
	return [_primary_spec(primary)] + base


## The player's own attachments / skin when they bought their class primary,
## the weapon's defaults otherwise.
func _primary_spec(id: String) -> Array:
	var full: Array = Loadout.weapon_list()
	if String(full[0][0]) == id:
		return full[0]
	return [id, Data.sanitize(id, {}), Collection.skin_for(id), Collection.sticker_for(id), ""]


## Shop rows for the HUD: {id, section, label, desc, price, ok, note}.
func items(p) -> Array:
	var out: Array = []
	var w = p.current_weapon() if p != null and not p.weapons.is_empty() else null
	# supplies
	out.append(_row("ammo", "SUPPLIES", "AMMO REFILL", "EVERY GUN TO FULL RESERVE", 300, true))
	out.append(_row("heal", "SUPPLIES", "MEDKIT", "HEAL TO FULL", 400, p != null and p.health < p.max_health - 0.5))
	out.append(_row("frag", "SUPPLIES", "FRAG GRENADES x2", "CARRY UP TO 5", 350, p != null and p.grenades < 5))
	out.append(_row("flash", "SUPPLIES", "FLASHBANG", "CARRY UP TO 3", 250, p != null and p.flashbangs < 3))
	# upgrade the gun in hand
	if w != null and not w.is_melee():
		var lv := int(upgrades.get(String(w.id), 0))
		if lv < MAX_UPGRADE:
			out.append(_row("upgrade", "UPGRADE", "UPGRADE %s TO MK %s" % [String(w.stats.name), _roman(lv + 1)],
					"+30% DAMAGE, +25% MAGAZINE PER LEVEL", upgrade_price(lv), true))
		else:
			out.append(_row("upgrade", "UPGRADE", "%s  MK %s" % [String(w.stats.name), _roman(lv)], "FULLY UPGRADED", 0, false, "MAX"))
	# perks
	for id in PERKS:
		var pk: Array = PERKS[id]
		var have := perks.has(id)
		out.append(_row("perk_" + id, "PERKS", String(pk[0]), String(pk[2]), int(pk[1]), not have, "OWNED" if have else ""))
	# primaries
	for g in GUNS:
		var gid: String = g[0]
		var st: Dictionary = Data.WEAPONS[gid]
		var have := primary == gid
		var desc := "%s  ·  DMG %d  ·  %d RPM" % [String(st.category), int(st.damage), int(st.rpm)]
		if primary != "" and not have:
			desc += "  ·  REPLACES " + String(Data.WEAPONS[primary].name)
		out.append(_row("gun_" + gid, "WEAPONS", String(st.name), desc, int(g[1]), not have, "EQUIPPED" if have else ""))
	return out


func _row(id: String, section: String, label: String, desc: String, price: int, ok: bool, note: String = "") -> Dictionary:
	return {"id": id, "section": section, "label": label, "desc": desc, "price": price,
			"ok": ok and points >= price, "note": note, "afford": points >= price}


static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV"][clampi(n, 0, 4)]


## Buys one row for operator p. Returns a feed line ("" = nothing happened).
func buy(id: String, p) -> String:
	var row: Dictionary = {}
	for r in items(p):
		if r.id == id:
			row = r
	if row.is_empty() or not bool(row.ok):
		return ""
	points -= int(row.price)
	spent += int(row.price)
	match id:
		"ammo":
			for w in p.weapons:
				if not w.is_melee():
					w.reserve = maxi(w.reserve, int(w.stats.reserve))
					w.ammo = maxi(w.ammo, int(w.stats.mag))
		"heal":
			p.health = p.max_health
		"frag":
			p.grenades = mini(p.grenades + 2, 5)
		"flash":
			p.flashbangs = mini(p.flashbangs + 1, 3)
		"upgrade":
			var w = p.current_weapon()
			upgrades[String(w.id)] = int(upgrades.get(String(w.id), 0)) + 1
			apply_mods(p)
			w.ammo = int(w.stats.mag)
		_:
			if id.begins_with("perk_"):
				perks[id.substr(5)] = true
				apply_mods(p)
				if id == "perk_tough":
					p.health = p.max_health
			elif id.begins_with("gun_"):
				_equip_primary(id.substr(4), p)
	return "BOUGHT  ·  %s  ·  -%d PTS" % [String(row.label), int(row.price)]


## Swaps in a new primary, keeping the pistol's ammo, and tells the others.
func _equip_primary(gid: String, p) -> void:
	if primary != "":
		upgrades.erase(primary)   # the old gun's upgrades leave with it
	var keep := {}
	for w in p.weapons:
		keep[String(w.id)] = [w.ammo, w.reserve]
	primary = gid
	p.set_loadout(specs())
	for w in p.weapons:
		if keep.has(String(w.id)):
			w.ammo = int(keep[w.id][0])
			w.reserve = int(keep[w.id][1])
	apply_mods(p)
	p.weapon_index = 0
	p._equip_current()
	sync(p)


## Recomputes every weapon's stats from scratch, then applies upgrades and
## perks (so buying twice never stacks a multiplier on itself).
func apply_mods(p) -> void:
	if p == null:
		return
	for w in p.weapons:
		if w.is_melee():
			continue
		var ammo: int = w.ammo
		w.stats = Data.compute(String(w.id), w.attachments)
		var lv := int(upgrades.get(String(w.id), 0))
		if lv > 0:
			w.stats.damage = float(w.stats.damage) * (1.0 + 0.3 * lv)
			w.stats.mag = int(round(float(w.stats.mag) * (1.0 + 0.25 * lv)))
		if perks.has("quick"):
			w.stats.reload = float(w.stats.reload) * 0.6
			w.stats.reload_empty = float(w.stats.reload_empty) * 0.6
		if perks.has("rapid"):
			w.stats.rpm = float(w.stats.rpm) * 1.25
		w.ammo = mini(ammo, int(w.stats.mag))
	p.max_health = 150.0 if perks.has("tough") else 100.0
	p.regen_cap = 105.0 if perks.has("tough") else 70.0


## Weapon level shown on the HUD ("" when not upgraded).
func upgrade_tag(weapon_id: String) -> String:
	var lv := int(upgrades.get(weapon_id, 0))
	return "" if lv == 0 else "MK " + _roman(lv)


## Other players see the new gun (and late joiners get it from the roster).
func sync(p) -> void:
	var Player = preload("res://scripts/characters/player.gd")
	Player.zombie_specs = specs()
	var Net = preload("res://scripts/net/net.gd")
	if Net.active and Net.sync:
		var pack: Array = Player.net_loadout()
		Net.sync.send_event(p, "loadout", [pack])
		if Net.is_server():
			Net.roster[1] = {"name": Net.default_name(), "loadout": pack}
