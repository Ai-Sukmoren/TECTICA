extends RefCounted
## Zombie Survival economy: every operator starts the run with only a pistol
## and a knife, earns points by hitting and killing infected, and spends them
## in the shop between waves (B), building up to three guns like the other
## modes (a rifle and an SMG next to the pistol), plus ammo, healing,
## grenades, gun upgrades, perks and attachments. Every gun is bare (its own
## sights, standard parts): attachments for the gun in hand are bought here and
## last for the run. Each peer runs its own wallet for its own operator;
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

## Rifles for sale (the primary slot), cheapest first.
const GUNS := [
	["marlin", 1500], ["mosin", 1600], ["hk33", 1700], ["aug_a1", 1900],
	["as_val", 2000], ["scar_h", 2200], ["m700", 2300], ["uar10", 2400], ["l96a1", 2600],
]
## Attachment prices by slot (the rail comes free with an underbarrel part).
const ATT_PRICES := {"optic": 600, "muzzle": 500, "handguard": 350, "underbarrel": 550, "magazine": 450, "stock": 400}
## SMGs for sale (their own slot, carried alongside the rifle).
const SMG_GUNS := [["mgp7", 1100], ["gepard", 1300], ["p90", 1500]]
## id -> [name, price, description]
const PERKS := {
	"tough": ["JUGGERNAUT VEST", 2500, "+50 MAX HEALTH, FASTER REGEN"],
	"quick": ["QUICK HANDS", 1500, "RELOAD 40% FASTER"],
	"rapid": ["RAPID FIRE", 2000, "FIRE RATE +25%"],
	"mule": ["AMMO BANDOLIER", 1500, "CARRY 60% MORE RESERVE AMMO, FILLED ON PURCHASE"],
}
## Reserve ammo multiplier from the AMMO BANDOLIER perk. Every refill (shop,
## ammo crates) fills up to the raised reserve.
const MULE_RESERVE := 1.6

var points := START_POINTS
var earned := 0
var spent := 0
## Rifle bought this run ("" = none yet).
var primary := ""
## SMG bought this run ("" = none yet).
var smg := ""
## weapon id -> upgrade level 1..MAX_UPGRADE
var upgrades := {}
## weapon id -> {slot: option} attachments bought this run
var attach := {}
## the gun the ATTACHMENTS rows fit to (a weapon id the operator carries; "" or one not carried = the gun in hand)
var fit_to := ""
var perks := {}


## The weapon list an operator starts a zombie run with: the class pistol
## (bare) and the knife, no primary.
static func starting_specs() -> Array:
	var full: Array = Loadout.weapon_list()
	return [_bare(full[2], {}), full[3]]   # [rifle, SMG, pistol, knife] -> pistol and knife


## A weapon spec with its attachments replaced: the gun's defaults plus `extra`
## (skin, sticker, charm and part skins stay the player's own).
static func _bare(spec: Array, extra: Dictionary) -> Array:
	var out := spec.duplicate(true)
	out[1] = Data.sanitize(String(out[0]), extra)
	return out


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


## Weapon specs for this operator: [rifle?, SMG?, pistol, knife].
func specs() -> Array:
	var out: Array = []
	if primary != "":
		out.append(_primary_spec(primary))
	if smg != "":
		out.append(_smg_spec(smg))
	var start := starting_specs()
	start[0] = _bare(start[0], attach.get(String(start[0][0]), {}))
	return out + start


## The player's own SMG attachments / skin when they bought their class SMG.
func _smg_spec(id: String) -> Array:
	var full: Array = Loadout.weapon_list()
	if String(full[1][0]) == id:
		return _bare(full[1], attach.get(id, {}))
	return [id, Data.sanitize(id, attach.get(id, {})), Collection.skin_for(id), Collection.sticker_for(id), "", Collection.parts_for(id)]


## The player's own attachments / skin when they bought their class primary,
## the weapon's defaults otherwise.
func _primary_spec(id: String) -> Array:
	var full: Array = Loadout.weapon_list()
	if String(full[0][0]) == id:
		return _bare(full[0], attach.get(id, {}))
	return [id, Data.sanitize(id, attach.get(id, {})), Collection.skin_for(id), Collection.sticker_for(id), "", Collection.parts_for(id)]


## Shop rows for the HUD: {id, section, label, desc, price, ok, note}.
func items(p) -> Array:
	var out: Array = []
	# supplies
	out.append(_row("ammo", "SUPPLIES", "AMMO REFILL", "EVERY GUN TO FULL RESERVE", 300, true))
	out.append(_row("heal", "SUPPLIES", "MEDKIT", "HEAL TO FULL", 400, p != null and p.health < p.max_health - 0.5))
	out.append(_row("frag", "SUPPLIES", "FRAG GRENADES x2", "CARRY UP TO 5", 350, p != null and p.grenades < 5))
	out.append(_row("flash", "SUPPLIES", "FLASHBANG", "CARRY UP TO 3", 250, p != null and p.flashbangs < 3))
	# upgrades: one row for every gun carried ("upgrade:<id>")
	for g in guns(p):
		var lv := int(upgrades.get(String(g.id), 0))
		if lv < MAX_UPGRADE:
			out.append(_row("upgrade:" + String(g.id), "UPGRADE", "UPGRADE %s TO MK %s" % [String(g.stats.name), _roman(lv + 1)],
					"+30% DAMAGE, +25% MAGAZINE PER LEVEL", upgrade_price(lv), true))
		else:
			out.append(_row("upgrade:" + String(g.id), "UPGRADE", "%s  MK %s" % [String(g.stats.name), _roman(lv)], "FULLY UPGRADED", 0, false, "MAX"))
	# attachments for the gun picked in the FIT TO row
	var fit = fit_gun(p)
	if fit != null:
		var n := guns(p).size()
		out.append(_row("fit_to", "ATTACHMENTS", "FIT TO  ◀  %s  ▶" % String(fit.stats.name) if n > 1 else "FIT TO  %s" % String(fit.stats.name),
				"A / D OR CLICK: THE GUN THESE ATTACHMENTS GO ON  ·  %d GUNS CARRIED" % n, 0, n > 1, "PICK" if n > 1 else "ONLY GUN"))
		out += _attachment_rows(fit)
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
	# SMGs: a second gun slot
	for g in SMG_GUNS:
		var gid: String = g[0]
		var st: Dictionary = Data.WEAPONS[gid]
		var have := smg == gid
		var desc := "%s  ·  DMG %d  ·  %d RPM" % [String(st.category), int(st.damage), int(st.rpm)]
		desc += ("  ·  REPLACES " + String(Data.WEAPONS[smg].name)) if smg != "" and not have else "  ·  ADDS A GUN SLOT"
		out.append(_row("smg_" + gid, "SMGS", String(st.name), desc, int(g[1]), not have, "EQUIPPED" if have else ""))
	return out


## The guns the operator carries (the knife left out), in slot order.
func guns(p) -> Array:
	if p == null:
		return []
	return p.weapons.filter(func(w): return not w.is_melee())


## The gun the ATTACHMENTS rows fit to: `fit_to` when it is carried, else the gun in hand, else the first gun.
func fit_gun(p):
	var gs := guns(p)
	if gs.is_empty():
		return null
	for g in gs:
		if String(g.id) == fit_to:
			return g
	var w = p.current_weapon()
	return w if w != null and not w.is_melee() else gs[0]


## The FIT TO row: the next (dir 1) or previous (dir -1) gun carried.
func cycle_fit(p, dir: int) -> void:
	var gs := guns(p)
	if gs.is_empty():
		return
	var i := gs.find(fit_gun(p))
	fit_to = String(gs[posmod(i + dir, gs.size())].id)


## One row per attachment the gun can take (its defaults left out): "att_<gun>:<slot>:<option>", FITTED when it is
## on the gun.
func _attachment_rows(w) -> Array:
	var out: Array = []
	var wid := String(w.id)
	var st: Dictionary = Data.WEAPONS[wid]
	var on := Data.sanitize(wid, attach.get(wid, {}))
	for slot in Data.SLOTS:
		if not ATT_PRICES.has(slot):
			continue
		for opt in st.options[slot]:
			if opt == st.defaults[slot]:
				continue
			var fitted := String(on[slot]) == String(opt)
			var label := "%s  ·  %s" % [String(Data.SLOT_NAMES[slot]), String(Data.ATTACHMENTS[slot][opt].name).to_upper()]
			out.append(_row("att_%s:%s:%s" % [wid, slot, opt], "ATTACHMENTS", label,
					"REPLACES " + String(Data.ATTACHMENTS[slot][on[slot]].name).to_upper() if not fitted else "ON THIS GUN",
					int(ATT_PRICES[slot]), not fitted, "FITTED" if fitted else ""))
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
		_:
			if id.begins_with("upgrade:"):
				var gid := id.substr(8)
				upgrades[gid] = int(upgrades.get(gid, 0)) + 1
				apply_mods(p)
				for g in guns(p):
					if String(g.id) == gid:
						g.ammo = int(g.stats.mag)
			elif id.begins_with("perk_"):
				perks[id.substr(5)] = true
				apply_mods(p)
				if id == "perk_tough":
					p.health = p.max_health
				elif id == "perk_mule":
					for w in p.weapons:
						if not w.is_melee():
							w.reserve = maxi(w.reserve, int(w.stats.reserve))
			elif id.begins_with("att_"):
				var part := id.substr(4).split(":")   # gun, slot, option
				var a: Dictionary = attach.get(part[0], {})
				a[part[1]] = part[2]
				attach[part[0]] = a
				reissue(p, p.weapon_index)   # the gun in hand stays in hand
			elif id.begins_with("gun_"):
				_equip_primary(id.substr(4), p)
			elif id.begins_with("smg_"):
				_equip_smg(id.substr(4), p)
	return "BOUGHT  ·  %s  ·  -%d PTS" % [String(row.label), int(row.price)]


## Swaps in a new primary, keeping the pistol's ammo, and tells the others.
## Buys / swaps the SMG slot, keeping the other guns' ammo, then draws the SMG.
func _equip_smg(gid: String, p) -> void:
	if smg != "":
		upgrades.erase(smg)
		attach.erase(smg)
	smg = gid
	reissue(p, 1 if primary != "" else 0)


func _equip_primary(gid: String, p) -> void:
	if primary != "":
		upgrades.erase(primary)   # the old gun's upgrades and attachments leave with it
		attach.erase(primary)
	primary = gid
	reissue(p, 0)


## Hands operator p the shop's current weapon list, keeping every gun's ammo
## (a magazine larger than the new one's is trimmed), draws weapon `index`
## and tells the others.
func reissue(p, index: int) -> void:
	var keep := {}
	for w in p.weapons:
		keep[String(w.id)] = [w.ammo, w.reserve]
	p.set_loadout(specs(), true)   # unchanged guns are kept, not rebuilt
	for w in p.weapons:
		if keep.has(String(w.id)):
			w.ammo = int(keep[w.id][0])
			w.reserve = int(keep[w.id][1])
	apply_mods(p)
	p.weapon_index = clampi(index, 0, p.weapons.size() - 1)
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
		if perks.has("mule"):
			w.stats.reserve = int(round(float(w.stats.reserve) * MULE_RESERVE))
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
