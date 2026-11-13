extends RefCounted
## Weapon, attachment and class definitions.
## Spread is in degrees, times in seconds. Attachment modifiers multiply the
## base stat of the same name (e.g. "recoil": 0.8 = 20 % less recoil); boolean
## modifiers override. "mag" multiplies magazine capacity.

const SLOTS := ["optic", "muzzle", "underbarrel", "magazine", "stock"]
const SLOT_NAMES := {"optic": "OPTIC", "muzzle": "MUZZLE", "underbarrel": "UNDERBARREL", "magazine": "MAGAZINE", "stock": "STOCK"}

const ATTACHMENTS := {
	"optic": {
		"iron": {"name": "Iron Sights", "ads_speed": 1.08},
		"reddot": {"name": "Red Dot", "zoom": 1.15, "spread_aim": 0.92},
		"holo": {"name": "Holographic", "zoom": 1.2, "spread_aim": 0.9},
		"acog": {"name": "ACOG 4x", "zoom": 2.6, "spread_aim": 0.7, "ads_speed": 0.85, "range": 1.15},
		"scope": {"name": "Sniper Scope 8x", "zoom": 5.5, "spread_aim": 0.5, "ads_speed": 0.7, "range": 1.3, "scope": true},
	},
	"muzzle": {
		"none": {"name": "Standard Barrel"},
		"integral": {"name": "Integral Suppressor"},
		"suppressor": {"name": "Suppressor", "noise_radius": 0.3, "damage": 0.92, "range": 0.9, "suppressed": true, "flash": 0.3},
		"compensator": {"name": "Compensator", "recoil": 0.72, "spread_hip": 1.1},
		"flash_hider": {"name": "Flash Hider", "recoil": 0.9, "flash": 0.35},
		"brake": {"name": "Muzzle Brake", "recoil": 0.6, "noise_radius": 1.3, "shake": 1.4},
		"choke": {"name": "Full Choke", "spread_hip": 0.65, "spread_aim": 0.6, "range": 1.25},
	},
	"underbarrel": {
		"none": {"name": "None"},
		"vgrip": {"name": "Vertical Grip", "recoil": 0.82, "spread_move": 0.85},
		"agrip": {"name": "Angled Grip", "ads_speed": 1.25, "recoil": 0.92},
		"laser": {"name": "Laser Sight", "spread_hip": 0.62, "laser": true},
		"bipod": {"name": "Bipod", "recoil_crouch": 0.45, "spread_aim": 0.9, "mobility": 0.96},
	},
	"magazine": {
		"standard": {"name": "Standard Mag"},
		"extended": {"name": "Extended Mag", "mag": 1.5, "reload": 1.15, "reload_empty": 1.15, "mobility": 0.98},
		"drum": {"name": "Drum Mag", "mag": 2.0, "reload": 1.4, "reload_empty": 1.4, "mobility": 0.94, "ads_speed": 0.88},
		"fast": {"name": "Fast Mag", "reload": 0.72, "reload_empty": 0.72},
		# armor-piercing: headshots punch straight through helmets
		"ap": {"name": "AP Rounds", "pierce": true, "damage": 0.9, "mag": 0.8},
	},
	"stock": {
		"standard": {"name": "Standard Stock"},
		"light": {"name": "Lightweight Stock", "mobility": 1.06, "ads_speed": 1.2, "recoil": 1.12},
		"heavy": {"name": "Heavy Stock", "recoil": 0.8, "spread_aim": 0.88, "mobility": 0.95, "ads_speed": 0.9},
	},
}

const _ALL_OPTICS := ["iron", "reddot", "holo", "acog", "scope"]
const _RIFLE_MUZZLES := ["none", "suppressor", "compensator", "flash_hider", "brake"]

const WEAPONS := {
	"m4a1": {
		"name": "M4A1", "category": "ASSAULT RIFLE", "kind": "rifle", "model": "m4",
		"mag": 30, "reserve": 180, "rpm": 800, "auto": true, "pellets": 1,
		"damage": 31.0, "range": 80.0, "falloff_start": 35.0,
		"spread_hip": 3.0, "spread_aim": 0.6, "spread_move": 2.4,
		"bloom_add": 0.3, "bloom_max": 3.0, "bloom_recover": 6.0,
		"recoil": 0.85, "reload": 2.1, "reload_empty": 2.6,
		"suppressed": false, "noise_radius": 34.0, "shake": 0.1, "sound": "shot_rifle", "volume": -4.0,
		"mobility": 1.0, "ads_speed": 1.0,
		"options": {"optic": _ALL_OPTICS, "muzzle": _RIFLE_MUZZLES, "underbarrel": ["none", "vgrip", "agrip", "laser"],
				"magazine": ["standard", "extended", "drum", "fast", "ap"], "stock": ["standard", "light", "heavy"]},
		"defaults": {"optic": "reddot", "muzzle": "none", "underbarrel": "vgrip", "magazine": "standard", "stock": "standard"},
	},
	"ak47": {
		"name": "AK-47", "category": "ASSAULT RIFLE", "kind": "rifle", "model": "akm",
		"mag": 30, "reserve": 180, "rpm": 600, "auto": true, "pellets": 1,
		"damage": 38.0, "range": 75.0, "falloff_start": 30.0,
		"spread_hip": 3.6, "spread_aim": 0.8, "spread_move": 2.8,
		"bloom_add": 0.45, "bloom_max": 3.5, "bloom_recover": 5.0,
		"recoil": 1.25, "reload": 2.5, "reload_empty": 3.0,
		"suppressed": false, "noise_radius": 38.0, "shake": 0.13, "sound": "shot_loud", "volume": -3.0,
		"mobility": 0.97, "ads_speed": 0.95,
		"options": {"optic": _ALL_OPTICS, "muzzle": _RIFLE_MUZZLES, "underbarrel": ["none", "vgrip", "agrip", "laser"],
				"magazine": ["standard", "extended", "drum", "fast", "ap"], "stock": ["standard", "light", "heavy"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"as_val": {
		"name": "AS VAL", "category": "ASSAULT RIFLE", "kind": "rifle", "model": "as_val",
		"mag": 30, "reserve": 150, "rpm": 900, "auto": true, "pellets": 1,
		"damage": 34.0, "range": 70.0, "falloff_start": 28.0,
		"spread_hip": 3.2, "spread_aim": 0.6, "spread_move": 2.6,
		"bloom_add": 0.32, "bloom_max": 3.0, "bloom_recover": 6.0,
		"recoil": 0.75, "reload": 2.2, "reload_empty": 2.8,
		"suppressed": true, "noise_radius": 11.0, "shake": 0.11, "sound": "shot_suppressed", "volume": -2.0,
		"mobility": 1.02, "ads_speed": 1.05, "flash": 0.4,
		"options": {"optic": ["iron", "reddot", "holo", "acog"], "muzzle": ["integral"], "underbarrel": ["none", "vgrip", "agrip", "laser"],
				"magazine": ["standard", "extended", "fast", "ap"], "stock": ["standard", "light", "heavy"]},
		"defaults": {"optic": "reddot", "muzzle": "integral", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"mp7": {
		"name": "MP7", "category": "SMG", "kind": "rifle", "model": "mp7",
		"mag": 40, "reserve": 200, "rpm": 950, "auto": true, "pellets": 1,
		"damage": 22.0, "range": 50.0, "falloff_start": 18.0,
		"spread_hip": 2.6, "spread_aim": 0.9, "spread_move": 1.4,
		"bloom_add": 0.25, "bloom_max": 2.5, "bloom_recover": 8.0,
		"recoil": 0.55, "reload": 1.9, "reload_empty": 2.3,
		"suppressed": false, "noise_radius": 30.0, "shake": 0.07, "sound": "shot_smg", "volume": -5.0,
		"mobility": 1.1, "ads_speed": 1.3,
		"options": {"optic": ["iron", "reddot", "holo"], "muzzle": _RIFLE_MUZZLES, "underbarrel": ["none", "vgrip", "agrip", "laser"],
				"magazine": ["standard", "extended", "fast", "ap"], "stock": ["standard", "light", "heavy"]},
		"defaults": {"optic": "holo", "muzzle": "suppressor", "underbarrel": "agrip", "magazine": "standard", "stock": "standard"},
	},
	# asset pack 4 (alstraInfinite PPS Shooter Essentials) models
	"mgp7": {
		"name": "MGP7", "category": "SMG", "kind": "rifle", "model": "mgp7",
		"mag": 30, "reserve": 180, "rpm": 820, "auto": true, "pellets": 1,
		"damage": 25.0, "range": 55.0, "falloff_start": 20.0,
		"spread_hip": 2.4, "spread_aim": 0.8, "spread_move": 1.5,
		"bloom_add": 0.25, "bloom_max": 2.6, "bloom_recover": 8.0,
		"recoil": 0.62, "reload": 2.0, "reload_empty": 2.5,
		"suppressed": false, "noise_radius": 30.0, "shake": 0.08, "sound": "shot_smg", "volume": -4.0,
		"mobility": 1.08, "ads_speed": 1.25,
		"options": {"optic": ["iron", "reddot", "holo"], "muzzle": ["none", "suppressor", "compensator", "flash_hider"],
				"underbarrel": ["none", "vgrip", "agrip", "laser"], "magazine": ["standard", "extended", "fast", "ap"], "stock": ["standard"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"awp": {
		"name": "AWP", "category": "SNIPER", "kind": "rifle", "model": "awp",
		"mag": 5, "reserve": 30, "rpm": 42, "auto": false, "pellets": 1,
		"damage": 120.0, "range": 160.0, "falloff_start": 120.0, "pierce": true,
		"spread_hip": 7.0, "spread_aim": 0.05, "spread_move": 6.0,
		"bloom_add": 0.0, "bloom_max": 0.0, "bloom_recover": 10.0,
		"recoil": 3.0, "reload": 3.4, "reload_empty": 3.8,
		"suppressed": false, "noise_radius": 45.0, "shake": 0.35, "sound": "shot_sniper", "volume": 0.0,
		"mobility": 0.86, "ads_speed": 0.7, "cycle": "bolt",
		"options": {"optic": ["scope", "acog", "reddot", "iron"], "muzzle": ["none", "suppressor", "brake"], "underbarrel": ["none", "bipod"],
				"magazine": ["standard", "extended", "fast"], "stock": ["standard", "light", "heavy"]},
		"defaults": {"optic": "scope", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"m870": {
		"name": "M870", "category": "SHOTGUN", "kind": "rifle", "model": "m870",
		"mag": 6, "reserve": 42, "rpm": 75, "auto": false, "pellets": 8,
		"damage": 16.0, "range": 30.0, "falloff_start": 8.0,
		"spread_hip": 5.5, "spread_aim": 4.0, "spread_move": 1.5,
		"bloom_add": 0.0, "bloom_max": 0.0, "bloom_recover": 10.0,
		"recoil": 2.2, "reload": 2.6, "reload_empty": 3.0,
		"suppressed": false, "noise_radius": 40.0, "shake": 0.3, "sound": "shot_shotgun", "volume": -1.0,
		"mobility": 0.98, "ads_speed": 1.0, "cycle": "pump",
		"options": {"optic": ["iron", "reddot", "holo"], "muzzle": ["none", "choke", "brake", "suppressor"], "underbarrel": ["none", "laser"],
				"magazine": ["standard", "extended"], "stock": ["standard", "light", "heavy"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"m249": {
		"name": "M249", "category": "LMG", "kind": "rifle", "model": "m249",
		"mag": 100, "reserve": 300, "rpm": 750, "auto": true, "pellets": 1,
		"damage": 30.0, "range": 85.0, "falloff_start": 40.0,
		"spread_hip": 4.5, "spread_aim": 1.2, "spread_move": 3.5,
		"bloom_add": 0.2, "bloom_max": 4.0, "bloom_recover": 4.0,
		"recoil": 0.9, "reload": 4.6, "reload_empty": 5.2,
		"suppressed": false, "noise_radius": 40.0, "shake": 0.12, "sound": "shot_rifle", "volume": -3.0,
		"mobility": 0.82, "ads_speed": 0.7,
		"options": {"optic": ["iron", "reddot", "holo", "acog"], "muzzle": ["none", "flash_hider", "compensator", "suppressor"],
				"underbarrel": ["bipod", "vgrip", "none"], "magazine": ["standard", "extended", "ap"], "stock": ["standard", "heavy"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "bipod", "magazine": "standard", "stock": "standard"},
	},
	"mk23": {
		"name": "MK23", "category": "PISTOL", "kind": "pistol", "model": "pistol",
		"mag": 12, "reserve": 60, "rpm": 380, "auto": false, "pellets": 1,
		"damage": 44.0, "range": 50.0, "falloff_start": 18.0,
		"spread_hip": 2.2, "spread_aim": 0.8, "spread_move": 1.8,
		"bloom_add": 0.9, "bloom_max": 3.0, "bloom_recover": 7.0,
		"recoil": 1.25, "reload": 1.6, "reload_empty": 1.9,
		"suppressed": false, "noise_radius": 28.0, "shake": 0.16, "sound": "shot_pistol", "volume": -1.0,
		"mobility": 1.05, "ads_speed": 1.3,
		"options": {"optic": ["iron", "reddot"], "muzzle": ["none", "suppressor", "compensator"], "underbarrel": ["none", "laser"],
				"magazine": ["standard", "extended", "fast", "ap"], "stock": ["standard"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"zc57": {
		"name": "ZC57", "category": "PISTOL", "kind": "pistol", "model": "zc57",
		"mag": 15, "reserve": 90, "rpm": 420, "auto": false, "pellets": 1,
		"damage": 34.0, "range": 45.0, "falloff_start": 16.0,
		"spread_hip": 2.0, "spread_aim": 0.7, "spread_move": 1.6,
		"bloom_add": 0.7, "bloom_max": 3.0, "bloom_recover": 7.5,
		"recoil": 0.95, "reload": 1.5, "reload_empty": 1.8,
		"suppressed": false, "noise_radius": 27.0, "shake": 0.12, "sound": "shot_pistol", "volume": -2.0,
		"mobility": 1.06, "ads_speed": 1.35,
		"options": {"optic": ["iron", "reddot"], "muzzle": ["none", "suppressor", "compensator"], "underbarrel": ["none", "laser"],
				"magazine": ["standard", "extended", "fast", "ap"], "stock": ["standard"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"g18": {
		"name": "GLOCK 18", "category": "PISTOL", "kind": "pistol", "model": "g18",
		"mag": 17, "reserve": 102, "rpm": 1100, "auto": true, "pellets": 1,
		"damage": 17.0, "range": 35.0, "falloff_start": 12.0,
		"spread_hip": 3.0, "spread_aim": 1.4, "spread_move": 1.5,
		"bloom_add": 0.35, "bloom_max": 3.5, "bloom_recover": 8.0,
		"recoil": 0.45, "reload": 1.5, "reload_empty": 1.8,
		"suppressed": false, "noise_radius": 26.0, "shake": 0.06, "sound": "shot_pistol", "volume": -4.0,
		"mobility": 1.06, "ads_speed": 1.35,
		"options": {"optic": ["iron", "reddot"], "muzzle": ["none", "suppressor", "compensator"], "underbarrel": ["none", "laser"],
				"magazine": ["standard", "extended", "drum"], "stock": ["standard"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	# ---- knives (melee slot). Starting values: damage per slash, swings per minute,
	# reach in metres, damage multiplier for a hit from behind.
	"knife_combat": {
		"name": "COMBAT KNIFE", "category": "KNIFE", "kind": "melee", "model": "knife_combat", "inspect": "combat",
		"mag": 1, "reserve": 0, "rpm": 75, "auto": true, "pellets": 1,
		"damage": 65.0, "range": 2.10, "falloff_start": 99.0, "backstab": 3.0,
		"spread_hip": 0.0, "spread_aim": 0.0, "spread_move": 0.0,
		"bloom_add": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"recoil": 0.0, "reload": 1.0, "reload_empty": 1.0,
		"suppressed": true, "noise_radius": 3.0, "shake": 0.05, "sound": "knife_swing", "volume": -3.0,
		"mobility": 1.28, "ads_speed": 1.0,
		"options": {"optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none"], "magazine": ["standard"], "stock": ["standard"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"karambit": {
		"name": "KARAMBIT", "category": "KNIFE", "kind": "melee", "model": "karambit", "inspect": "karambit",
		"mag": 1, "reserve": 0, "rpm": 105, "auto": true, "pellets": 1,
		"damage": 48.0, "range": 1.90, "falloff_start": 99.0, "backstab": 3.5,
		"spread_hip": 0.0, "spread_aim": 0.0, "spread_move": 0.0,
		"bloom_add": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"recoil": 0.0, "reload": 1.0, "reload_empty": 1.0,
		"suppressed": true, "noise_radius": 3.0, "shake": 0.05, "sound": "knife_swing", "volume": -4.0,
		"mobility": 1.28, "ads_speed": 1.0,
		"options": {"optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none"], "magazine": ["standard"], "stock": ["standard"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"butterfly": {
		"name": "BUTTERFLY KNIFE", "category": "KNIFE", "kind": "melee", "model": "butterfly", "inspect": "butterfly",
		"mag": 1, "reserve": 0, "rpm": 90, "auto": true, "pellets": 1,
		"damage": 56.0, "range": 2.00, "falloff_start": 99.0, "backstab": 3.2,
		"spread_hip": 0.0, "spread_aim": 0.0, "spread_move": 0.0,
		"bloom_add": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"recoil": 0.0, "reload": 1.0, "reload_empty": 1.0,
		"suppressed": true, "noise_radius": 3.0, "shake": 0.05, "sound": "knife_swing", "volume": -3.5,
		"mobility": 1.28, "ads_speed": 1.0,
		"options": {"optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none"], "magazine": ["standard"], "stock": ["standard"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	# hostile militia weapon (balanced for AI)
	"akm": {
		"name": "AKM", "category": "ASSAULT RIFLE", "kind": "rifle", "model": "akm",
		"mag": 30, "reserve": 240, "rpm": 600, "auto": true, "pellets": 1,
		"damage": 12.0, "range": 70.0, "falloff_start": 25.0,
		"spread_hip": 4.5, "spread_aim": 1.8, "spread_move": 3.0,
		"bloom_add": 0.5, "bloom_max": 4.0, "bloom_recover": 5.0,
		"recoil": 1.1, "reload": 2.6, "reload_empty": 3.1,
		"suppressed": false, "noise_radius": 38.0, "shake": 0.05, "sound": "shot_loud", "volume": -3.0,
		"mobility": 1.0, "ads_speed": 1.0,
		"options": {"optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none"], "magazine": ["standard"], "stock": ["standard"]},
		"defaults": {"optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
}

const PRIMARIES := ["m4a1", "ak47", "as_val", "mp7", "mgp7", "awp", "m870", "m249"]
const SECONDARIES := ["mk23", "g18", "zc57"]
const KNIVES := ["knife_combat", "karambit", "butterfly"]

const CLASSES := [
	{"name": "ASSAULT", "desc": "Balanced rifleman for any range.",
		"primary": ["m4a1", {"optic": "reddot", "muzzle": "compensator", "underbarrel": "vgrip", "magazine": "standard", "stock": "standard"}],
		"secondary": ["mk23", {}]},
	{"name": "RIFLEMAN", "desc": "Hard-hitting AK with magnified optic.",
		"primary": ["ak47", {"optic": "acog", "muzzle": "brake", "underbarrel": "vgrip", "magazine": "extended", "stock": "standard"}],
		"secondary": ["mk23", {}]},
	{"name": "RECON", "desc": "AWP marksman. One shot, one kill.",
		"primary": ["awp", {"optic": "scope", "muzzle": "none", "underbarrel": "bipod", "magazine": "standard", "stock": "heavy"}],
		"secondary": ["mk23", {"muzzle": "suppressor"}]},
	{"name": "CQB", "desc": "Fast, quiet room clearer.",
		"primary": ["mp7", {"optic": "holo", "muzzle": "suppressor", "underbarrel": "agrip", "magazine": "extended", "stock": "light"}],
		"secondary": ["g18", {}]},
	{"name": "BREACHER", "desc": "Pump shotgun for close quarters.",
		"primary": ["m870", {"optic": "reddot", "muzzle": "choke", "underbarrel": "laser", "magazine": "extended", "stock": "standard"}],
		"secondary": ["mk23", {}]},
	{"name": "SUPPORT", "desc": "Belt-fed suppression.",
		"primary": ["m249", {"optic": "holo", "muzzle": "flash_hider", "underbarrel": "bipod", "magazine": "standard", "stock": "heavy"}],
		"secondary": ["mk23", {}]},
	{"name": "SPEC OPS", "desc": "Integrally suppressed AS VAL. Stay unseen.",
		"primary": ["as_val", {"optic": "reddot", "muzzle": "integral", "underbarrel": "none", "magazine": "standard", "stock": "standard"}],
		"secondary": ["mk23", {"muzzle": "suppressor"}]},
]


## Fills in missing slots with the weapon's defaults and drops illegal choices.
static func sanitize(id: String, att: Dictionary) -> Dictionary:
	var w: Dictionary = WEAPONS[id]
	var out := {}
	for slot in SLOTS:
		var opts: Array = w.options[slot]
		var choice: String = att.get(slot, w.defaults[slot])
		out[slot] = choice if choice in opts else String(w.defaults[slot])
	return out


## Final stats for a weapon with attachments applied.
static func compute(id: String, att: Dictionary) -> Dictionary:
	var s: Dictionary = WEAPONS[id].duplicate(true)
	s["zoom"] = 1.0
	s["scope"] = false
	s["laser"] = false
	s["flash"] = float(s.get("flash", 1.0))
	s["recoil_crouch"] = 1.0
	s["cycle"] = String(s.get("cycle", ""))
	s["pierce"] = bool(s.get("pierce", false))
	var a := sanitize(id, att)
	for slot in SLOTS:
		var mods: Dictionary = ATTACHMENTS[slot][a[slot]]
		for key in mods:
			if key == "name":
				continue
			var v = mods[key]
			if v is bool:
				s[key] = v
			elif key == "mag":
				s["mag"] = int(round(float(s["mag"]) * v))
			elif s.has(key) and (s[key] is float or s[key] is int):
				s[key] = float(s[key]) * v
			else:
				s[key] = v
	if s.suppressed:
		s.sound = "shot_suppressed"
	s["attachments"] = a
	return s
