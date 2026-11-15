extends RefCounted
## Weapon, attachment and class definitions.
## Spread is in degrees, times in seconds. Attachment modifiers multiply the
## base stat of the same name (e.g. "recoil": 0.8 = 20 % less recoil); boolean
## modifiers override. "mag" multiplies magazine capacity.

const SLOTS := ["optic", "muzzle", "handguard", "rail", "underbarrel", "magazine", "stock"]
const SLOT_NAMES := {"optic": "OPTIC", "muzzle": "MUZZLE", "handguard": "HANDGUARD", "rail": "RAIL", "underbarrel": "UNDERBARREL", "magazine": "MAGAZINE", "stock": "STOCK"}

const ATTACHMENTS := {
	"optic": {
		"iron": {"name": "Iron Sights", "ads_speed": 1.08},
		"reddot": {"name": "Red Dot", "zoom": 1.15, "spread_aim": 0.92},
		"holo": {"name": "Holographic", "zoom": 1.2, "spread_aim": 0.9},
		# the rest of the low-poly collimator set: a micro dot, an open reflex, a compact holo
		"micro_dot": {"name": "Micro Red Dot", "zoom": 1.1, "spread_aim": 0.93, "ads_speed": 1.04},
		"reflex": {"name": "Open Reflex", "zoom": 1.1, "spread_aim": 0.94, "ads_speed": 1.03},
		"uh1_holo": {"name": "UH-1 Holographic", "zoom": 1.25, "spread_aim": 0.88, "ads_speed": 0.97},
		# sights built into the gun's own model (no extra part is drawn)
		# the AUG's own 1.5x: a hollow tube on the model, so it is seen through the
		# scope overlay with the AUG's black ring reticle
		"builtin_15x": {"name": "Built-in 1.5x", "zoom": 1.5, "spread_aim": 0.85, "overlay": true, "ring": true},
		"builtin_scope": {"name": "Built-in 4x Scope", "zoom": 3.2, "spread_aim": 0.6, "ads_speed": 0.85, "range": 1.2, "scope": true},
	},
	"muzzle": {
		"none": {"name": "Standard Barrel"},
		"integral": {"name": "Integral Suppressor"},
		"suppressor": {"name": "Suppressor", "noise_radius": 0.3, "damage": 0.92, "range": 0.9, "suppressed": true, "flash": 0.3},
		"flash_hider": {"name": "Flash Hider", "recoil": 0.9, "flash": 0.35},
		"brake": {"name": "Muzzle Brake", "recoil": 0.6, "noise_radius": 1.3, "shake": 1.4},
		"heavy_suppressor": {"name": "Heavy Suppressor", "noise_radius": 0.15, "damage": 0.88, "range": 0.85, "suppressed": true, "flash": 0.15, "ads_speed": 0.9, "mobility": 0.97},
	},
	"handguard": {
		"standard": {"name": "Standard Handguard"},
		# a lighter hexagonal aluminium tube in place of the gun's own handguard
		"hex": {"name": "Hex Handguard", "mobility": 1.02, "ads_speed": 1.03},
	},
	# a rail adapter under the handguard (or a pistol's frame); underbarrel parts mount on it
	"rail": {
		"none": {"name": "No Rail"},
		"rail": {"name": "Rail Mount"},
	},
	"underbarrel": {
		"none": {"name": "None"},
		"laser": {"name": "Laser Sight", "spread_hip": 0.62, "laser": true},
		# GP-25 under-barrel grenade launcher: 40 mm rounds on the launcher key
		"gp25": {"name": "GP-25 Launcher", "launcher": true, "mobility": 0.94, "ads_speed": 0.92},
	},
	"magazine": {
		"standard": {"name": "Standard Mag"},
		"extended": {"name": "Extended Mag", "mag": 1.5, "reload": 1.15, "reload_empty": 1.15, "mobility": 0.98},
		"drum": {"name": "Drum Mag", "mag": 2.0, "reload": 1.4, "reload_empty": 1.4, "mobility": 0.94, "ads_speed": 0.88},
		"fast": {"name": "Fast Mag", "reload": 0.72, "reload_empty": 0.72},
		# armor-piercing: headshots punch straight through helmets
		"ap": {"name": "AP Rounds", "pierce": true, "damage": 0.9, "mag": 0.8},
		# hollow points: hit harder, but flatten on armour (armoured infected plates, helmets)
		"hollow": {"name": "Hollow Points", "damage": 1.2, "hollow": true},
		# two mags taped together: every second reload just flips to the other one
		"dual": {"name": "Taped Dual Mag", "dual": true, "mobility": 0.98, "ads_speed": 0.95},
	},
	"stock": {
		"standard": {"name": "Standard Stock"},
	},
}

const _ALL_OPTICS := ["iron", "reddot", "holo", "micro_dot", "reflex", "uh1_holo"]
const _RIFLE_MUZZLES := ["none", "suppressor", "heavy_suppressor", "flash_hider", "brake"]
const _RIFLE_UNDER := ["none", "laser"]
const _PISTOL_OPTICS := ["iron"]

const WEAPONS := {
	"as_val": {
		"name": "AS VAL", "category": "ASSAULT RIFLE", "kind": "rifle", "model": "as_val",
		"mag": 30, "reserve": 150, "rpm": 900, "auto": true, "pellets": 1,
		"damage": 34.0, "range": 70.0, "falloff_start": 28.0,
		"spread_hip": 3.2, "spread_aim": 0.6, "spread_move": 2.6,
		"bloom_add": 0.32, "bloom_max": 3.0, "bloom_recover": 6.0,
		"recoil": 0.75, "reload": 2.2, "reload_empty": 2.8,
		"suppressed": true, "noise_radius": 11.0, "shake": 0.11, "sound": "shot_suppressed", "volume": -2.0,
		"mobility": 1.02, "ads_speed": 1.05, "flash": 0.4,
		"options": {"handguard": ["standard"], "rail": ["none", "rail"], "optic": _ALL_OPTICS, "muzzle": ["integral"], "underbarrel": _RIFLE_UNDER,
				"magazine": ["standard", "extended", "fast", "dual", "ap", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "reddot", "muzzle": "integral", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
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
		"options": {"handguard": ["standard"], "rail": ["none", "rail"], "optic": _ALL_OPTICS, "muzzle": _RIFLE_MUZZLES,
				"underbarrel": _RIFLE_UNDER, "magazine": ["standard", "extended", "fast", "dual", "ap", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	# lever-action rifle: heavy rounds loaded one at a time through the side
	# gate; the lever swings down and back after every shot (SoldierRig._update_cycle)
	"marlin": {
		"name": "MARLIN 1895", "category": "LEVER-ACTION", "kind": "rifle", "model": "marlin",
		"mag": 6, "reserve": 36, "rpm": 70, "auto": false, "pellets": 1,
		"damage": 82.0, "range": 95.0, "falloff_start": 45.0,
		"spread_hip": 3.5, "spread_aim": 0.25, "spread_move": 2.5,
		"bloom_add": 0.0, "bloom_max": 0.0, "bloom_recover": 10.0,
		"recoil": 2.4, "reload": 2.8, "reload_empty": 3.2,
		"suppressed": false, "noise_radius": 42.0, "shake": 0.3, "sound": "shot_sniper", "volume": -1.0,
		"mobility": 0.96, "ads_speed": 1.05, "cycle": "lever",
		"options": {"handguard": ["standard"], "rail": ["none", "rail"], "optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none", "laser"], "magazine": ["standard", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
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
		"options": {"handguard": ["standard"], "rail": ["none", "rail"], "optic": _PISTOL_OPTICS, "muzzle": ["none", "suppressor"], "underbarrel": ["none", "laser"],
				"magazine": ["standard", "extended", "fast", "dual", "ap", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	# 9x21 PDW: the magazine goes up through the pistol grip, 40 rounds
	"gepard": {
		"name": "GEPARD", "category": "SMG", "kind": "rifle", "model": "gepard",
		"mag": 40, "reserve": 200, "rpm": 900, "auto": true, "pellets": 1,
		"damage": 26.0, "range": 55.0, "falloff_start": 20.0,
		"spread_hip": 2.6, "spread_aim": 0.8, "spread_move": 1.6,
		"bloom_add": 0.25, "bloom_max": 2.6, "bloom_recover": 8.0,
		"recoil": 0.7, "reload": 2.2, "reload_empty": 2.7,
		"suppressed": false, "noise_radius": 30.0, "shake": 0.08, "sound": "shot_smg", "volume": -4.0,
		"mobility": 1.07, "ads_speed": 1.2,
		"options": {"handguard": ["standard"], "rail": ["none", "rail"], "optic": _ALL_OPTICS, "muzzle": _RIFLE_MUZZLES, "underbarrel": ["none", "laser"],
				"magazine": ["standard", "extended", "fast", "ap", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	# ---- low-poly asset guns (assets/thirdparty/low_poly_guns, local only)
	"aug_a1": {
		"name": "AUG A1", "category": "ASSAULT RIFLE", "kind": "rifle", "model": "aug_a1",
		"mag": 30, "reserve": 180, "rpm": 700, "auto": true, "pellets": 1,
		"damage": 32.0, "range": 82.0, "falloff_start": 36.0,
		"spread_hip": 2.8, "spread_aim": 0.55, "spread_move": 2.4,
		"bloom_add": 0.3, "bloom_max": 3.0, "bloom_recover": 6.0,
		"recoil": 0.8, "reload": 2.6, "reload_empty": 3.1,
		"suppressed": false, "noise_radius": 34.0, "shake": 0.1, "sound": "shot_rifle", "volume": -4.0,
		"mobility": 0.99, "ads_speed": 0.95,
		"options": {"handguard": ["standard"], "rail": ["none", "rail"], "optic": ["builtin_15x"], "muzzle": _RIFLE_MUZZLES, "underbarrel": ["none", "laser", "gp25"],
				"magazine": ["standard", "extended", "fast", "ap", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "builtin_15x", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"hk33": {
		"name": "HK33", "category": "ASSAULT RIFLE", "kind": "rifle", "model": "hk33",
		"mag": 30, "reserve": 180, "rpm": 750, "auto": true, "pellets": 1,
		"damage": 31.0, "range": 80.0, "falloff_start": 34.0,
		"spread_hip": 3.1, "spread_aim": 0.6, "spread_move": 2.5,
		"bloom_add": 0.32, "bloom_max": 3.2, "bloom_recover": 6.0,
		"recoil": 0.95, "reload": 2.3, "reload_empty": 2.9,
		"suppressed": false, "noise_radius": 36.0, "shake": 0.11, "sound": "shot_rifle", "volume": -4.0,
		"mobility": 0.98, "ads_speed": 0.97,
		"options": {"handguard": ["standard", "hex"], "rail": ["none", "rail"], "optic": ["iron"], "muzzle": _RIFLE_MUZZLES, "underbarrel": ["none", "laser", "gp25"],
				"magazine": ["standard", "extended", "fast", "dual", "ap", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	# 7.62 marksman rifle with its scope built in
	"uar10": {
		"name": "UAR-10", "category": "MARKSMAN", "kind": "rifle", "model": "uar10",
		"mag": 20, "reserve": 100, "rpm": 300, "auto": false, "pellets": 1,
		"damage": 58.0, "range": 130.0, "falloff_start": 80.0, "pierce": true,
		"spread_hip": 4.5, "spread_aim": 0.25, "spread_move": 3.5,
		"bloom_add": 0.6, "bloom_max": 2.5, "bloom_recover": 7.0,
		"recoil": 1.6, "reload": 2.6, "reload_empty": 3.2,
		"suppressed": false, "noise_radius": 42.0, "shake": 0.2, "sound": "shot_loud", "volume": -2.0,
		"mobility": 0.9, "ads_speed": 0.85,
		"options": {"handguard": ["standard", "hex"], "rail": ["none", "rail"], "optic": ["builtin_scope"], "muzzle": _RIFLE_MUZZLES, "underbarrel": ["none", "laser", "gp25"],
				"magazine": ["standard", "extended", "ap", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "builtin_scope", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	"g17": {
		"name": "GLOCK 17", "category": "PISTOL", "kind": "pistol", "model": "g17",
		"mag": 17, "reserve": 102, "rpm": 450, "auto": false, "pellets": 1,
		"damage": 30.0, "range": 45.0, "falloff_start": 16.0,
		"spread_hip": 2.0, "spread_aim": 0.7, "spread_move": 1.6,
		"bloom_add": 0.7, "bloom_max": 3.0, "bloom_recover": 7.5,
		"recoil": 0.9, "reload": 1.5, "reload_empty": 1.8,
		"suppressed": false, "noise_radius": 27.0, "shake": 0.12, "sound": "shot_pistol", "volume": -2.0,
		"mobility": 1.06, "ads_speed": 1.35,
		"options": {"handguard": ["standard"], "rail": ["none", "rail"], "optic": ["iron"], "muzzle": ["none", "suppressor"], "underbarrel": ["none", "laser"],
				"magazine": ["standard", "extended", "fast", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	# B&T VP9: bolt-action pistol with an integral suppressor, five rounds
	"vp9": {
		"name": "B&T VP9", "category": "PISTOL", "kind": "pistol", "model": "vp9",
		"mag": 5, "reserve": 30, "rpm": 50, "auto": false, "pellets": 1,
		"damage": 70.0, "range": 50.0, "falloff_start": 25.0,
		"spread_hip": 2.4, "spread_aim": 0.4, "spread_move": 1.8,
		"bloom_add": 0.0, "bloom_max": 0.0, "bloom_recover": 10.0,
		"recoil": 0.7, "reload": 1.8, "reload_empty": 2.1,
		"suppressed": true, "noise_radius": 6.0, "shake": 0.08, "sound": "shot_suppressed", "volume": -4.0,
		"mobility": 1.05, "ads_speed": 1.25, "flash": 0.2, "cycle": "bolt",
		"options": {"handguard": ["standard"], "rail": ["none", "rail"], "optic": ["iron"], "muzzle": ["integral"], "underbarrel": ["none", "laser"], "magazine": ["standard", "hollow"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "integral", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
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
		"options": {"handguard": ["standard"], "rail": ["none"], "optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none"], "magazine": ["standard"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
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
		"options": {"handguard": ["standard"], "rail": ["none"], "optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none"], "magazine": ["standard"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
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
		"options": {"handguard": ["standard"], "rail": ["none"], "optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none"], "magazine": ["standard"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
	# hostile militia weapon (balanced for AI)
	"akm": {
		"name": "HK33", "category": "ASSAULT RIFLE", "kind": "rifle", "model": "hk33",
		"mag": 30, "reserve": 240, "rpm": 600, "auto": true, "pellets": 1,
		"damage": 12.0, "range": 70.0, "falloff_start": 25.0,
		"spread_hip": 4.5, "spread_aim": 1.8, "spread_move": 3.0,
		"bloom_add": 0.5, "bloom_max": 4.0, "bloom_recover": 5.0,
		"recoil": 1.1, "reload": 2.6, "reload_empty": 3.1,
		"suppressed": false, "noise_radius": 38.0, "shake": 0.05, "sound": "shot_loud", "volume": -3.0,
		"mobility": 1.0, "ads_speed": 1.0,
		"options": {"handguard": ["standard", "hex"], "rail": ["none", "rail"], "optic": ["iron"], "muzzle": ["none"], "underbarrel": ["none", "laser", "gp25"], "magazine": ["standard"], "stock": ["standard"]},
		"defaults": {"handguard": "standard", "rail": "none", "optic": "iron", "muzzle": "none", "underbarrel": "none", "magazine": "standard", "stock": "standard"},
	},
}

const PRIMARIES := ["hk33", "aug_a1", "as_val", "uar10", "marlin"]
## The middle slot: submachine guns.
const SMGS := ["mgp7", "gepard"]
const SECONDARIES := ["g17", "zc57", "vp9"]
const KNIVES := ["knife_combat", "karambit", "butterfly"]

const CLASSES := [
	{"name": "ASSAULT", "desc": "Balanced rifleman for any range.",
		"primary": ["hk33", {"magazine": "standard"}],
		"smg": ["mgp7", {}],
		"secondary": ["g17", {}]},
	{"name": "RIFLEMAN", "desc": "Bullpup AUG with its built-in 1.5x optic.",
		"primary": ["aug_a1", {"magazine": "extended"}],
		"smg": ["gepard", {}],
		"secondary": ["g17", {}]},
	{"name": "RECON", "desc": "UAR-10 marksman rifle with a 4x scope.",
		"primary": ["uar10", {}],
		"smg": ["mgp7", {"muzzle": "suppressor"}],
		"secondary": ["vp9", {}]},
	{"name": "CQB", "desc": "Fast, quiet room clearer.",
		"primary": ["aug_a1", {"muzzle": "suppressor"}],
		"smg": ["gepard", {"optic": "holo", "muzzle": "suppressor", "magazine": "extended"}],
		"secondary": ["zc57", {}]},
	{"name": "FRONTIER", "desc": "Marlin lever-action. Heavy rounds, one at a time.",
		"primary": ["marlin", {}],
		"smg": ["mgp7", {}],
		"secondary": ["g17", {}]},
	{"name": "SUPPORT", "desc": "HK33 with a dual mag for long fights.",
		"primary": ["hk33", {"magazine": "dual"}],
		"smg": ["gepard", {"magazine": "extended"}],
		"secondary": ["g17", {}]},
	{"name": "SPEC OPS", "desc": "Integrally suppressed AS VAL. Stay unseen.",
		"primary": ["as_val", {"optic": "reddot", "muzzle": "integral", "underbarrel": "none", "magazine": "standard", "stock": "standard"}],
		"smg": ["mgp7", {"optic": "reddot", "muzzle": "suppressor"}],
		"secondary": ["vp9", {}]},
]


## Fills in missing slots with the weapon's defaults and drops illegal choices.
static func sanitize(id: String, att: Dictionary) -> Dictionary:
	var w: Dictionary = WEAPONS[id]
	var out := {}
	for slot in SLOTS:
		var opts: Array = w.options[slot]
		var choice: String = att.get(slot, w.defaults[slot])
		out[slot] = choice if choice in opts else String(w.defaults[slot])
	# underbarrel parts mount on the rail: a gun that offers one gets it with them
	# (this also keeps lasers saved before the rail was a slot of its own)
	if out.underbarrel != "none" and "rail" in (w.options.rail as Array):
		out.rail = "rail"
	return out


## Final stats for a weapon with attachments applied.
static func compute(id: String, att: Dictionary) -> Dictionary:
	var s: Dictionary = WEAPONS[id].duplicate(true)
	s["zoom"] = 1.0
	s["scope"] = false
	s["laser"] = false
	s["launcher"] = false
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
