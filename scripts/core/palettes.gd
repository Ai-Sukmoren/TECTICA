extends RefCounted
## Uniform / gear colour schemes for soldiers.

const M = preload("res://scripts/core/materials.gd")


## Special-forces operator: woodland multicam, ranger-green plate carrier,
## coyote gear and a tan helmet.
static func player() -> Dictionary:
	return {
		"camo": M.camo("camo_multicam", [Color(0.47, 0.43, 0.32), Color(0.33, 0.35, 0.23),
				Color(0.58, 0.53, 0.4), Color(0.24, 0.2, 0.15)], 3.5),
		"vest": M.fabric("vest_ranger", Color(0.21, 0.23, 0.17)),
		"gear": M.fabric("gear_coyote", Color(0.43, 0.36, 0.26)),
		"helmet": M.solid(Color(0.42, 0.38, 0.29), 0.75),
		"detail": M.solid(Color(0.14, 0.14, 0.12), 0.6, 0.2),
		"skin": M.solid(Color(0.76, 0.58, 0.47), 0.7),
		"face": M.fabric("balaclava_olive", Color(0.16, 0.17, 0.13)),
		"gloves": M.solid(Color(0.24, 0.21, 0.16), 0.8),
		"boots": M.solid(Color(0.3, 0.24, 0.17), 0.75),
		"headgear": "helmet",
		"goggles": true,
	}


## Infected soldiers: rotting skin, blood-stained torn uniforms, glowing eyes.
static func zombie(variant: int) -> Dictionary:
	var skins := [Color(0.42, 0.5, 0.38), Color(0.5, 0.48, 0.4), Color(0.36, 0.42, 0.36)]
	var skin: Color = skins[variant % 3]
	var heads := ["none", "helmet", "none", "beanie"]
	return {
		"camo": M.camo("camo_rot_%d" % (variant % 2), [Color(0.26, 0.25, 0.2), Color(0.18, 0.17, 0.14),
				Color(0.34, 0.06, 0.05) if variant % 2 == 0 else Color(0.32, 0.29, 0.22), Color(0.12, 0.1, 0.08)], 2.5),
		"vest": M.fabric("zvest_%d" % (variant % 2), Color(0.16, 0.15, 0.12)),
		"gear": M.fabric("zgear", Color(0.2, 0.17, 0.13)),
		"helmet": M.solid(Color(0.3, 0.26, 0.2), 0.8),
		"detail": M.solid(Color(0.12, 0.1, 0.08), 0.8),
		"skin": M.solid(skin, 0.75),
		"face": M.solid(skin.darkened(0.1), 0.75),
		"gloves": M.solid(skin.darkened(0.15), 0.8),
		"boots": M.solid(Color(0.15, 0.12, 0.1), 0.7),
		"headgear": heads[variant % heads.size()],
		"goggles": false,
		"eyes": true,
	}


## Hostile militia with a few loadout variations.
static func enemy(variant: int) -> Dictionary:
	var camos := [
		["camo_wood", [Color(0.34, 0.37, 0.23), Color(0.22, 0.24, 0.15), Color(0.45, 0.41, 0.28), Color(0.15, 0.14, 0.1)]],
		["camo_desert", [Color(0.66, 0.58, 0.42), Color(0.5, 0.42, 0.3), Color(0.74, 0.67, 0.52), Color(0.38, 0.3, 0.22)]],
		["camo_flora", [Color(0.3, 0.33, 0.25), Color(0.42, 0.44, 0.33), Color(0.2, 0.21, 0.16), Color(0.5, 0.45, 0.33)]],
	]
	var c: Array = camos[variant % camos.size()]
	var heads := ["helmet", "cap", "helmet", "beanie"]
	var vests := [Color(0.42, 0.38, 0.27), Color(0.26, 0.28, 0.19), Color(0.33, 0.3, 0.24)]
	var helmets := [Color(0.3, 0.32, 0.22), Color(0.48, 0.43, 0.32), Color(0.24, 0.25, 0.2)]
	return {
		"camo": M.camo(c[0], c[1], 3.0),
		"vest": M.fabric("vest_%d" % (variant % 3), vests[variant % 3]),
		"gear": M.fabric("gear_%d" % (variant % 3), vests[variant % 3].darkened(0.25)),
		"helmet": M.solid(helmets[variant % 3], 0.65),
		"detail": M.solid(Color(0.15, 0.15, 0.13), 0.6, 0.2),
		"skin": M.solid([Color(0.72, 0.55, 0.43), Color(0.55, 0.4, 0.3), Color(0.8, 0.64, 0.52)][variant % 3], 0.7),
		"face": M.solid([Color(0.72, 0.55, 0.43), Color(0.55, 0.4, 0.3), Color(0.8, 0.64, 0.52)][variant % 3], 0.7),
		"gloves": M.solid(Color(0.2, 0.18, 0.14), 0.8),
		"boots": M.solid(Color(0.2, 0.15, 0.1), 0.6),
		"headgear": heads[variant % heads.size()],
		"goggles": variant % 2 == 0,
	}
