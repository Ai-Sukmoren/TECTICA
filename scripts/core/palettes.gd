extends RefCounted
## Uniform / gear colour schemes for soldiers.

const M = preload("res://scripts/core/materials.gd")


## The operator in an outfit (character skin, see outfits.gd).
static func outfit(id: String) -> Dictionary:
	return preload("res://scripts/skins/outfits.gd").palette(id)


## Standalone previews use the same base outfit as a new player.
static func player() -> Dictionary:
	return outfit("multicam")


## Infected soldiers: rotting skin, blood-stained torn uniforms, glowing eyes.
static func zombie(variant: int) -> Dictionary:
	var skins := [Color(0.42, 0.5, 0.38), Color(0.5, 0.48, 0.4), Color(0.36, 0.42, 0.36)]
	var skin: Color = skins[variant % 3]
	var heads := ["none", "helmet", "none", "beanie"]
	return {
		"task_force_kit": true,
		"camo": M.camo("camo_rot_%d" % (variant % 2), [Color(0.26, 0.25, 0.2), Color(0.18, 0.17, 0.14),
				Color(0.34, 0.06, 0.05) if variant % 2 == 0 else Color(0.32, 0.29, 0.22), Color(0.12, 0.1, 0.08)], 2.5),
		"vest": M.fabric("zvest_%d" % (variant % 2), Color(0.16, 0.15, 0.12)),
		"gear": M.fabric("zgear", Color(0.2, 0.17, 0.13)),
		"helmet": M.matte("helmet_zombie", Color(0.3, 0.26, 0.2), 0.85),
		"detail": M.solid(Color(0.12, 0.1, 0.08), 0.8),
		"skin": M.solid(skin, 0.75),
		"face": M.solid(skin.darkened(0.1), 0.75),
		"gloves": M.solid(skin.darkened(0.15), 0.8),
		"boots": M.leather("boots_zombie", Color(0.15, 0.12, 0.1)),
		"headgear": heads[variant % heads.size()],
		"goggles": false,
		"eyes": true,
	}.merged({
		"shirt": M.camo("zombie_task_force_shirt", [Color("#aaa697"), Color("#9a9584"), Color("#6a5244"), Color("#b3afa0")], 1.2),
		"trousers": M.matte("zombie_task_force_trousers", Color("#2f3536"), 0.92),
		"undershirt": M.matte("zombie_task_force_sleeves", Color("#20262a"), 0.92),
	} if variant % 3 == 0 else {}, true)


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
		"task_force_kit": true,
		"camo": M.camo(c[0], c[1], 3.0),
		"vest": M.fabric("vest_%d" % (variant % 3), vests[variant % 3]),
		"gear": M.fabric("gear_%d" % (variant % 3), vests[variant % 3].darkened(0.25)),
		"helmet": M.matte("helmet_enemy_%d" % (variant % 3), helmets[variant % 3], 0.7),
		"detail": M.solid(Color(0.15, 0.15, 0.13), 0.6, 0.2),
		"skin": M.solid([Color(0.72, 0.55, 0.43), Color(0.55, 0.4, 0.3), Color(0.8, 0.64, 0.52)][variant % 3], 0.7),
		"face": M.solid([Color(0.72, 0.55, 0.43), Color(0.55, 0.4, 0.3), Color(0.8, 0.64, 0.52)][variant % 3], 0.7),
		"gloves": M.fabric("gloves_enemy", Color(0.2, 0.18, 0.14), 12.0),
		"boots": M.leather("boots_enemy", Color(0.2, 0.15, 0.1)),
		"headgear": heads[variant % heads.size()],
		"goggles": variant % 2 == 0,
		"mask": true,
		"visor": M.painted_metal("militia_visor", Color("#be5642")),
	}
