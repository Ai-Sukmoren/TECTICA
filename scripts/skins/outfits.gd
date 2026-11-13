extends RefCounted
## Operator outfits (character skins): alternative uniform palettes for the
## player's procedural body. Bought once with credits in the Armory, shown to
## other players in multiplayer. Prices are starting values, not tuned.

const M = preload("res://scripts/core/materials.gd")

const DEFAULT := "multicam"
## Same rarity colours / names as weapon skins (skins.gd).
const RARITY_NAMES := ["STANDARD", "RARE", "EPIC", "LEGENDARY"]
const RARITY_COLORS := [Color(0.7, 0.72, 0.75), Color(0.3, 0.6, 1.0), Color(0.75, 0.35, 1.0), Color(1.0, 0.72, 0.2)]

## id -> look. camo: 4 colours; vest/gear/helmet/gloves/boots/face: colours;
## glow: emissive accent colour on gear (neon outfits); headgear: helmet/cap/beanie/none.
const OUTFITS := {
	"multicam": {"name": "TASK FORCE", "rarity": 0, "price": 0, "desc": "Woodland multicam, ranger-green plate carrier.",
		"camo": [Color(0.47, 0.43, 0.32), Color(0.33, 0.35, 0.23), Color(0.58, 0.53, 0.4), Color(0.24, 0.2, 0.15)],
		"vest": Color(0.21, 0.23, 0.17), "gear": Color(0.43, 0.36, 0.26), "helmet": Color(0.42, 0.38, 0.29),
		"face": Color(0.16, 0.17, 0.13), "gloves": Color(0.24, 0.21, 0.16), "boots": Color(0.3, 0.24, 0.17), "headgear": "helmet", "nvg": true},
	"night_ops": {"name": "NIGHT OPS", "rarity": 0, "price": 800, "desc": "Charcoal fatigues for after dark.",
		"camo": [Color(0.12, 0.12, 0.13), Color(0.18, 0.18, 0.19), Color(0.08, 0.08, 0.09), Color(0.24, 0.24, 0.25)],
		"vest": Color(0.07, 0.07, 0.08), "gear": Color(0.15, 0.15, 0.16), "helmet": Color(0.09, 0.09, 0.1),
		"face": Color(0.05, 0.05, 0.06), "gloves": Color(0.06, 0.06, 0.06), "boots": Color(0.07, 0.07, 0.07), "headgear": "helmet", "nvg": true},
	"desert": {"name": "DESERT RAIDER", "rarity": 0, "price": 1000, "desc": "Sand-and-khaki raid kit with a field cap.",
		"camo": [Color(0.72, 0.62, 0.45), Color(0.58, 0.48, 0.33), Color(0.8, 0.72, 0.56), Color(0.45, 0.36, 0.25)],
		"vest": Color(0.6, 0.52, 0.38), "gear": Color(0.5, 0.42, 0.3), "helmet": Color(0.62, 0.55, 0.4),
		"face": Color(0.66, 0.58, 0.44), "gloves": Color(0.45, 0.37, 0.27), "boots": Color(0.5, 0.4, 0.28), "headgear": "cap"},
	"arctic": {"name": "ARCTIC WOLF", "rarity": 1, "price": 1500, "desc": "Snow camo, white plates, frosted helmet.",
		"camo": [Color(0.86, 0.88, 0.9), Color(0.68, 0.71, 0.75), Color(0.95, 0.96, 0.97), Color(0.5, 0.53, 0.58)],
		"vest": Color(0.8, 0.82, 0.84), "gear": Color(0.55, 0.58, 0.62), "helmet": Color(0.9, 0.91, 0.93),
		"face": Color(0.85, 0.87, 0.89), "gloves": Color(0.3, 0.32, 0.35), "boots": Color(0.25, 0.26, 0.28), "headgear": "helmet", "nvg": true},
	"tiger": {"name": "TIGER STRIPE", "rarity": 1, "price": 1800, "desc": "Jungle tiger stripes and a black beanie.",
		"camo": [Color(0.3, 0.4, 0.18), Color(0.06, 0.07, 0.05), Color(0.45, 0.5, 0.25), Color(0.18, 0.22, 0.1)],
		"vest": Color(0.2, 0.26, 0.13), "gear": Color(0.12, 0.13, 0.09), "helmet": Color(0.08, 0.08, 0.07),
		"face": Color(0.12, 0.14, 0.08), "gloves": Color(0.1, 0.1, 0.08), "boots": Color(0.12, 0.1, 0.08), "headgear": "beanie"},
	"hazmat": {"name": "HAZMAT", "rarity": 2, "price": 3000, "desc": "Biohazard suit for the outbreak zone.",
		"camo": [Color(0.92, 0.76, 0.1), Color(0.85, 0.68, 0.08), Color(0.95, 0.82, 0.2), Color(0.78, 0.6, 0.06)],
		"vest": Color(0.1, 0.1, 0.1), "gear": Color(0.15, 0.15, 0.14), "helmet": Color(0.93, 0.78, 0.12),
		"face": Color(0.06, 0.06, 0.06), "gloves": Color(0.08, 0.08, 0.08), "boots": Color(0.08, 0.08, 0.08), "headgear": "helmet", "goggles": true},
	"crimson": {"name": "CRIMSON CELL", "rarity": 2, "price": 3500, "desc": "Black fatigues, blood-red armour.",
		"camo": [Color(0.1, 0.09, 0.09), Color(0.2, 0.05, 0.05), Color(0.06, 0.06, 0.06), Color(0.3, 0.07, 0.06)],
		"vest": Color(0.45, 0.06, 0.05), "gear": Color(0.12, 0.1, 0.1), "helmet": Color(0.5, 0.07, 0.06),
		"face": Color(0.05, 0.05, 0.05), "gloves": Color(0.06, 0.05, 0.05), "boots": Color(0.07, 0.06, 0.06), "headgear": "helmet", "nvg": true},
	"neon": {"name": "NEON RUNNER", "rarity": 3, "price": 6000, "desc": "Street-tech armour lit in cyan and magenta.",
		"camo": [Color(0.06, 0.06, 0.09), Color(0.1, 0.08, 0.14), Color(0.04, 0.04, 0.06), Color(0.14, 0.1, 0.2)],
		"vest": Color(0.08, 0.08, 0.12), "gear": Color(0.0, 0.85, 1.0), "helmet": Color(0.9, 0.1, 0.75),
		"face": Color(0.04, 0.04, 0.06), "gloves": Color(0.05, 0.05, 0.08), "boots": Color(0.06, 0.06, 0.09), "headgear": "helmet",
		"goggles": true, "glow": Color(0.0, 0.85, 1.0), "glow_helmet": Color(0.95, 0.1, 0.8)},
	"gilded": {"name": "GILDED", "rarity": 3, "price": 9000, "desc": "Polished gold plates. Pure flex.",
		"camo": [Color(0.14, 0.12, 0.1), Color(0.2, 0.17, 0.12), Color(0.1, 0.09, 0.08), Color(0.26, 0.22, 0.15)],
		"vest": Color(0.85, 0.65, 0.2), "gear": Color(0.3, 0.24, 0.12), "helmet": Color(0.9, 0.7, 0.22),
		"face": Color(0.08, 0.07, 0.06), "gloves": Color(0.12, 0.1, 0.08), "boots": Color(0.1, 0.08, 0.06), "headgear": "helmet",
		"goggles": true, "metal": true},
}


static func ids() -> Array:
	return OUTFITS.keys()


static func exists(id: String) -> bool:
	return OUTFITS.has(id)


static func info(id: String) -> Dictionary:
	return OUTFITS.get(id, OUTFITS[DEFAULT])


## Soldier palette (see palettes.gd) for an outfit.
static func palette(id: String) -> Dictionary:
	if not OUTFITS.has(id):
		id = DEFAULT
	var o: Dictionary = OUTFITS[id]
	var metal := bool(o.get("metal", false))
	var glow = o.get("glow")
	var glow_helmet = o.get("glow_helmet")
	var gear: Material = M.emissive("outfit_glow_" + id, glow, 2.2) if glow != null else M.fabric("outfit_gear_" + id, o.gear)
	var helmet: Material
	if glow_helmet != null:
		helmet = M.emissive("outfit_helmet_" + id, glow_helmet, 1.6)
	elif metal:
		helmet = M.solid(o.helmet, 0.25, 0.9)
	else:
		helmet = M.matte("outfit_helmet_" + id, o.helmet, 0.72)
	return {
		"camo": M.camo("outfit_camo_" + id, o.camo, 3.5),
		"vest": M.solid(o.vest, 0.3, 0.9) if metal else M.fabric("outfit_vest_" + id, o.vest),
		"gear": gear,
		"helmet": helmet,
		"detail": M.solid(Color(0.14, 0.14, 0.12), 0.6, 0.2),
		"skin": M.solid(Color(0.76, 0.58, 0.47), 0.7),
		"face": M.fabric("outfit_face_" + id, o.face),
		"gloves": M.fabric("outfit_gloves_" + id, o.gloves, 12.0),
		"boots": M.leather("outfit_boots_" + id, o.boots),
		"headgear": String(o.get("headgear", "helmet")),
		"goggles": bool(o.get("goggles", true)),
		"nvg": bool(o.get("nvg", false)),
	}
