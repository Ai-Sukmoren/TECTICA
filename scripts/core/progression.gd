extends RefCounted
## Player progression, saved per account (user://profiles/<name>/progress.cfg):
##   * operator XP -> level 1..55 -> rank (11 ranks x 5 grades)
##   * weapon XP per gun -> weapon level 1..20 (credits on every level, mastery at 10 / 20)
##   * three daily challenges, the same for every player on a given date
## Gameplay calls the on_* hooks; the HUD drains `pending` for pop-ups.
## All numbers are starting values, not tuned.

const Profile = preload("res://scripts/core/profile.gd")
const Collection = preload("res://scripts/skins/collection.gd")

const MAX_LEVEL := 55
const WEAPON_MAX := 20
const RANKS := ["RECRUIT", "PRIVATE", "SPECIALIST", "CORPORAL", "SERGEANT", "STAFF SERGEANT",
		"LIEUTENANT", "CAPTAIN", "MAJOR", "COLONEL", "GENERAL"]
const GRADES := ["I", "II", "III", "IV", "V"]

const XP_KILL := 50
const XP_HEADSHOT := 25
const XP_KICK := 60
const XP_BOSS := 750
const XP_WAVE := 40           # x wave number
const XP_PVP_KILL := 100
const XP_FLASH := 10
const XP_CHAPTER := 600
const LEVEL_CREDITS := 100
const WEAPON_LEVEL_CREDITS := 75

## Daily challenge pool: id, text (%d = goal), goals by tier, credit + XP reward by tier.
const CHALLENGES := [
	{"id": "kills", "text": "Get %d kills", "goals": [30, 50, 80]},
	{"id": "headshots", "text": "Land %d headshot kills", "goals": [10, 20, 35]},
	{"id": "waves", "text": "Clear %d zombie waves", "goals": [5, 8, 12]},
	{"id": "boss", "text": "Kill %d Juggernaut bosses", "goals": [1, 2, 3]},
	{"id": "kicks", "text": "Dropkick-kill %d enemies", "goals": [3, 5, 8]},
	{"id": "flash", "text": "Blind %d enemies with flashbangs", "goals": [8, 15, 25]},
	{"id": "town_waves", "text": "Clear %d waves on DEAD END", "goals": [3, 6, 10]},
	{"id": "pistol", "text": "Get %d pistol kills", "goals": [10, 20, 30]},
	{"id": "chapter", "text": "Complete %d campaign chapters", "goals": [1, 2, 2]},
]
const REWARD_CR := [250, 400, 650]
const REWARD_XP := [500, 800, 1200]

static var xp := 0
static var weapon_xp: Dictionary = {}     # weapon id -> xp
static var day := ""                       # "YYYY-MM-DD" the challenges belong to
static var daily: Array = []               # [{id, tier, goal, progress, done}]
static var challenges_done := 0
## Pop-ups for the HUD: [text, kind] with kind "level", "weapon", "challenge".
static var pending: Array = []
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		_check_day()
		return
	_loaded = true
	xp = 0
	weapon_xp = {}
	day = ""
	daily = []
	challenges_done = 0
	var cfg := ConfigFile.new()
	if cfg.load(Profile.path("progress.cfg")) == OK:
		xp = int(cfg.get_value("progress", "xp", 0))
		weapon_xp = cfg.get_value("progress", "weapon_xp", {})
		day = String(cfg.get_value("progress", "day", ""))
		daily = cfg.get_value("progress", "daily", [])
		challenges_done = int(cfg.get_value("progress", "challenges_done", 0))
	_check_day()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "xp", xp)
	cfg.set_value("progress", "weapon_xp", weapon_xp)
	cfg.set_value("progress", "day", day)
	cfg.set_value("progress", "daily", daily)
	cfg.set_value("progress", "challenges_done", challenges_done)
	cfg.save(Profile.path("progress.cfg"))


## Forget the cached account (sign-out / switch).
static func reset_cache() -> void:
	_loaded = false
	pending.clear()


# ---------------------------------------------------------------- levels

## XP needed to go from `lvl` to `lvl + 1`.
static func xp_to_next(lvl: int) -> int:
	return 600 + 120 * (lvl - 1)


static func level_of(total: int) -> int:
	var lvl := 1
	var left := total
	while lvl < MAX_LEVEL and left >= xp_to_next(lvl):
		left -= xp_to_next(lvl)
		lvl += 1
	return lvl


static func level() -> int:
	ensure()
	return level_of(xp)


## [xp into the current level, xp needed for the next] (next = 0 at max level).
static func level_progress() -> Array:
	ensure()
	var lvl := 1
	var left := xp
	while lvl < MAX_LEVEL and left >= xp_to_next(lvl):
		left -= xp_to_next(lvl)
		lvl += 1
	return [left, xp_to_next(lvl) if lvl < MAX_LEVEL else 0]


static func rank_name(lvl: int) -> String:
	var i := clampi((lvl - 1) / 5, 0, RANKS.size() - 1)
	return "%s %s" % [RANKS[i], GRADES[(lvl - 1) % 5]]


static func add_xp(n: int) -> void:
	ensure()
	if n <= 0:
		return
	var before := level_of(xp)
	xp += n
	var after := level_of(xp)
	if after > before:
		var cr := LEVEL_CREDITS * (after - before)
		Collection.add_credits(cr)
		pending.append(["RANK UP  ·  LEVEL %d  ·  %s  ·  +%d CR" % [after, rank_name(after), cr], "level"])
	save()


# ---------------------------------------------------------------- weapons

static func weapon_xp_to_next(lvl: int) -> int:
	return 500 + 250 * (lvl - 1)


static func weapon_level_of(total: int) -> int:
	var lvl := 1
	var left := total
	while lvl < WEAPON_MAX and left >= weapon_xp_to_next(lvl):
		left -= weapon_xp_to_next(lvl)
		lvl += 1
	return lvl


static func weapon_level(weapon: String) -> int:
	ensure()
	return weapon_level_of(int(weapon_xp.get(weapon, 0)))


static func add_weapon_xp(weapon: String, weapon_name: String, n: int) -> void:
	if weapon == "" or n <= 0:
		return
	var before := weapon_level_of(int(weapon_xp.get(weapon, 0)))
	weapon_xp[weapon] = int(weapon_xp.get(weapon, 0)) + n
	var after := weapon_level_of(int(weapon_xp[weapon]))
	if after > before:
		var cr := WEAPON_LEVEL_CREDITS * (after - before)
		Collection.add_credits(cr)
		var tag := "  ·  MASTERY" if after in [10, WEAPON_MAX] else ""
		pending.append(["%s  LEVEL %d%s  ·  +%d CR" % [weapon_name.to_upper(), after, tag, cr], "weapon"])


# ---------------------------------------------------------------- daily challenges

static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## Three challenges from the pool, picked by the date (same for everyone).
static func roll_daily(date: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("tectica-daily-" + date)
	var pool := range(CHALLENGES.size())
	var out: Array = []
	for k in 3:
		var pick: int = pool.pop_at(rng.randi() % pool.size())
		var tier := rng.randi() % 3
		var c: Dictionary = CHALLENGES[pick]
		out.append({"id": String(c.id), "tier": tier, "goal": int(c.goals[tier]), "progress": 0, "done": false})
	return out


static func _check_day() -> void:
	var t := today()
	if day != t or daily.size() != 3:
		day = t
		daily = roll_daily(t)
		save()


static func challenge_text(ch: Dictionary) -> String:
	for c in CHALLENGES:
		if String(c.id) == String(ch.id):
			return String(c.text) % int(ch.goal)
	return String(ch.id)


static func _bump(id: String, n: int = 1) -> void:
	for ch in daily:
		if String(ch.id) != id or bool(ch.done):
			continue
		ch.progress = mini(int(ch.progress) + n, int(ch.goal))
		if int(ch.progress) >= int(ch.goal):
			ch.done = true
			challenges_done += 1
			var tier := int(ch.tier)
			Collection.add_credits(REWARD_CR[tier])
			pending.append(["CHALLENGE COMPLETE  ·  %s  ·  +%d CR  +%d XP" % [challenge_text(ch).to_upper(), REWARD_CR[tier], REWARD_XP[tier]], "challenge"])
			add_xp(REWARD_XP[tier])


# ---------------------------------------------------------------- gameplay hooks

## The local operator killed something with a gun.
static func on_kill(weapon: String, weapon_name: String, pistol: bool, headshot: bool) -> void:
	ensure()
	_bump("kills")
	if headshot:
		_bump("headshots")
	if pistol:
		_bump("pistol")
	add_weapon_xp(weapon, weapon_name, 100 + (50 if headshot else 0))
	add_xp(XP_KILL + (XP_HEADSHOT if headshot else 0))


static func on_kick_kill() -> void:
	ensure()
	_bump("kills")
	_bump("kicks")
	add_xp(XP_KICK)


static func on_pvp_kill() -> void:
	ensure()
	_bump("kills")
	add_xp(XP_PVP_KILL)


static func on_flash_blind() -> void:
	ensure()
	_bump("flash")
	add_xp(XP_FLASH)


static func on_wave_cleared(wave: int, map_id: String) -> void:
	ensure()
	_bump("waves")
	if map_id == "town":
		_bump("town_waves")
	add_xp(XP_WAVE * wave)


static func on_boss_kill() -> void:
	ensure()
	_bump("boss")
	add_xp(XP_BOSS)


static func on_chapter_complete(grade: String) -> void:
	ensure()
	_bump("chapter")
	add_xp(XP_CHAPTER + int({"S": 600, "A": 400, "B": 200}.get(grade, 0)))
