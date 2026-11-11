extends RefCounted
## The player's skin collection: credits, owned skins, equipped finish per gun,
## and pack opening. Saved to user://armory.cfg. Credits are earned in play
## (kills, waves, mission grades, PvP) - there is no real-money purchase.

const Skins = preload("res://scripts/skins/skins.gd")

const PATH := "user://armory.cfg"   # per account: Profile.path()
const Profile = preload("res://scripts/core/profile.gd")
const START_CREDITS := 1500

static var credits := START_CREDITS
## "weapon:finish" -> copies pulled
static var owned: Dictionary = {}
## weapon id -> finish id ("" = factory finish)
static var equipped: Dictionary = {}
static var packs_opened := 0
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(Profile.path("armory.cfg")) == OK:
		credits = int(cfg.get_value("armory", "credits", START_CREDITS))
		owned = cfg.get_value("armory", "owned", {})
		equipped = cfg.get_value("armory", "equipped", {})
		packs_opened = int(cfg.get_value("armory", "packs_opened", 0))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("armory", "credits", credits)
	cfg.set_value("armory", "owned", owned)
	cfg.set_value("armory", "equipped", equipped)
	cfg.set_value("armory", "packs_opened", packs_opened)
	cfg.save(Profile.path("armory.cfg"))


static func add_credits(n: int) -> void:
	ensure()
	if n == 0:
		return
	credits = maxi(credits + n, 0)
	save()


static func has_skin(weapon: String, finish: String) -> bool:
	ensure()
	return finish == "" or int(owned.get(Skins.key(weapon, finish), 0)) > 0


static func count(weapon: String, finish: String) -> int:
	ensure()
	return int(owned.get(Skins.key(weapon, finish), 0))


static func owned_for(weapon: String) -> int:
	ensure()
	var n := 0
	for f in Skins.FINISHES:
		if count(weapon, f) > 0:
			n += 1
	return n


static func total_owned() -> int:
	ensure()
	var n := 0
	for k in owned:
		if int(owned[k]) > 0:
			n += 1
	return n


static func skin_for(weapon: String) -> String:
	ensure()
	var f := String(equipped.get(weapon, ""))
	return f if has_skin(weapon, f) else ""


static func equip(weapon: String, finish: String) -> bool:
	ensure()
	if not has_skin(weapon, finish):
		return false
	equipped[weapon] = finish
	save()
	return true


static func _roll_rarity(odds: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for o in odds:
		total += float(o)
	var x := rng.randf() * total
	for i in odds.size():
		x -= float(odds[i])
		if x <= 0.0:
			return i
	return 0


## Buys and opens a pack. Returns its cards, rarest last:
## [{weapon, finish, rarity, new, refund}], or [] if credits are short.
static func open_pack(pack_index: int) -> Array:
	ensure()
	var pack: Dictionary = Skins.PACKS[pack_index]
	if credits < int(pack.price):
		return []
	credits -= int(pack.price)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rarities: Array = []
	for i in int(pack.cards):
		rarities.append(_roll_rarity(pack.odds, rng))
	# guaranteed slot: the best card is at least the pack's minimum rarity
	var g := int(pack.guarantee)
	if g >= 0:
		var best := 0
		for r in rarities:
			best = maxi(best, int(r))
		if best < g:
			var sub: Array = (pack.odds as Array).slice(g)
			rarities[rarities.size() - 1] = g + _roll_rarity(sub, rng)
	rarities.sort()
	var weapons := Skins.weapon_ids()
	var cards: Array = []
	for r in rarities:
		var pool := Skins.finishes_of(int(r))
		var finish: String = pool[rng.randi() % pool.size()]
		var weapon: String = weapons[rng.randi() % weapons.size()]
		var k := Skins.key(weapon, finish)
		var is_new := int(owned.get(k, 0)) == 0
		owned[k] = int(owned.get(k, 0)) + 1
		var refund := 0 if is_new else int(Skins.DUP_REFUND[int(r)])
		credits += refund
		cards.append({"weapon": weapon, "finish": finish, "rarity": int(r), "new": is_new, "refund": refund})
	packs_opened += 1
	save()
	return cards
