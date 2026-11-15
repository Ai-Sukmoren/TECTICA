extends RefCounted
## Operator outfits (character skins): alternative uniform palettes for the
## player's procedural body. Bought once with credits in the Armory, shown to
## other players in multiplayer. Prices are starting values, not tuned.

const M = preload("res://scripts/core/materials.gd")
const Profile = preload("res://scripts/core/profile.gd")

const DEFAULT := "multicam"
## Same rarity colours / names as weapon skins (skins.gd).
## MYTHIC (4) outfits are admin exclusive, like mythic weapon skins: never sold.
const RARITY_NAMES := ["STANDARD", "RARE", "EPIC", "LEGENDARY", "MYTHIC"]
const RARITY_COLORS := [Color(0.7, 0.72, 0.75), Color(0.3, 0.6, 1.0), Color(0.75, 0.35, 1.0), Color(1.0, 0.72, 0.2), Color(1.0, 0.16, 0.26)]

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
	"carbon": {"name": "CARBON PHANTOM", "rarity": 4, "price": 0, "admin": true,
		"desc": "All-black carbon-weave suit, lacquered carbon plates and helmet.",
		"camo": [Color(0.05, 0.05, 0.06), Color(0.16, 0.17, 0.19), Color(0.03, 0.03, 0.035), Color(0.1, 0.1, 0.12)],
		"vest": Color(0.08, 0.085, 0.1), "gear": Color(0.06, 0.06, 0.07), "helmet": Color(0.1, 0.105, 0.12),
		"face": Color(0.03, 0.03, 0.035), "gloves": Color(0.05, 0.05, 0.055), "boots": Color(0.06, 0.06, 0.065), "headgear": "helmet",
		"goggles": true, "carbon": true},
	# built from the operator reference art: faceted olive fatigues with rolled
	# sleeves, tan plate carrier and pouches, black mask, tan-framed goggles,
	# tan shemagh, olive knee pads, brown boots. Free for everyone.
	"recon": {"name": "RECON", "rarity": 0, "price": 0, "desc": "Faceted olive fatigues, tan plate carrier, mask and goggles.",
		"camo": [Color(0.3, 0.31, 0.21), Color(0.22, 0.23, 0.16), Color(0.37, 0.37, 0.26), Color(0.16, 0.17, 0.12)],
		"vest": Color(0.5, 0.42, 0.29), "gear": Color(0.56, 0.47, 0.33), "helmet": Color(0.27, 0.28, 0.19),
		"face": Color(0.05, 0.05, 0.055), "gloves": Color(0.09, 0.09, 0.085), "boots": Color(0.27, 0.2, 0.14), "headgear": "helmet",
		"goggles": true, "facet": true, "sleeves": "rolled", "wrap": Color(0.58, 0.5, 0.36),
		"pads": Color(0.27, 0.28, 0.2), "goggle_frame": Color(0.55, 0.47, 0.33)},
	# one player only: "owners" are that player's account names (any case);
	# nobody else, admin included, sees or wears it
	"kitty": {"name": "MYTHIC KITTY", "rarity": 4, "price": 0, "admin": true, "owners": ["turain"],
		"desc": "Pastel pink camo, pearl plates and glowing pink and red bows.",
		"camo": [Color(1.0, 0.66, 0.8), Color(0.99, 0.86, 0.92), Color(0.97, 0.45, 0.66), Color(1.0, 0.97, 0.98)],
		"vest": Color(0.99, 0.94, 0.96), "gear": Color(1.0, 0.4, 0.68), "helmet": Color(1.0, 0.58, 0.76),
		"face": Color(0.99, 0.9, 0.94), "gloves": Color(1.0, 0.78, 0.87), "boots": Color(0.95, 0.9, 0.93), "headgear": "helmet",
		"goggles": true, "pearl": true, "glow": Color(1.0, 0.35, 0.7), "trim": Color(0.95, 0.05, 0.2)},
}


static func is_admin(id: String) -> bool:
	return bool(OUTFITS.get(id, {}).get("admin", false))


## Outfits the signed-in account can see: reserved ones only for their owner.
static func ids() -> Array:
	return OUTFITS.keys().filter(func(id): return owner_of(id) == "" or is_mine(id))


## Display name of the account an outfit is reserved for, or "".
static func owner_of(id: String) -> String:
	var o: Array = OUTFITS.get(id, {}).get("owners", [])
	return String(o[0]).to_lower() if not o.is_empty() else ""


static func is_mine(id: String) -> bool:
	return Profile.current.strip_edges().to_lower() in OUTFITS.get(id, {}).get("owners", [])


## "ADMIN ONLY" / "TURAIN EXCLUSIVE" style label for a locked outfit.
static func exclusive_label(id: String, word: String) -> String:
	return (owner_of(id).to_upper() if owner_of(id) != "" else "ADMIN") + " " + word


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
	var pearl := bool(o.get("pearl", false))
	if pearl:   # glossy lacquered plates with a pearly sheen
		helmet = _pearl("outfit_pearl_helmet_" + id, o.helmet)
	var carbon := bool(o.get("carbon", false))
	if carbon:
		helmet = M.carbon_fiber("outfit_carbon_plate", true, 22.0)
	var detail: Material = M.solid(Color(0.14, 0.14, 0.12), 0.6, 0.2)
	if o.has("trim"):
		detail = M.emissive("outfit_trim_" + id, o.trim, 0.55)
	elif carbon:
		detail = M.carbon_fiber("outfit_carbon_plate", true, 22.0)
	var extra := {}
	if o.has("sleeves"):
		extra["sleeves"] = String(o.sleeves)
	if o.has("pads"):
		extra["pads"] = M.matte("outfit_pads_" + id, o.pads, 0.8)
	if o.has("goggle_frame"):
		extra["goggle_frame"] = M.matte("outfit_goggle_" + id, o.goggle_frame, 0.75)
	var camo_mat: Material = M.camo("outfit_camo_" + id, o.camo, 3.5)
	if bool(o.get("facet", false)):
		camo_mat = _facet("outfit_facet_" + id, o.camo)
	var out := {
		"camo": M.carbon_fiber("outfit_carbon_suit", false, 28.0) if carbon else camo_mat,
		"vest": M.carbon_fiber("outfit_carbon_plate", true, 22.0) if carbon else (_pearl("outfit_pearl_vest_" + id, o.vest) if pearl else (M.solid(o.vest, 0.3, 0.9) if metal else M.fabric("outfit_vest_" + id, o.vest))),
		"gear": gear,
		"helmet": helmet,
		"detail": detail,
		"ifak": M.carbon_fiber("outfit_carbon_plate", true, 22.0) if carbon else M.solid(Color(0.45, 0.08, 0.06), 0.8),
		"bedroll": M.carbon_fiber("outfit_carbon_suit", false, 28.0) if carbon else M.fabric("bedroll", Color(0.25, 0.27, 0.2)),
		"wrap": M.fabric("outfit_wrap_" + id, Color(0.05, 0.05, 0.06), 7.0) if carbon else (M.fabric("outfit_wrap_" + id, o.wrap, 7.0) if o.has("wrap") else M.fabric("neck_wrap", Color(0.34, 0.33, 0.25), 7.0)),
		"skin": M.solid(Color(0.76, 0.58, 0.47), 0.7),
		"face": M.fabric("outfit_face_" + id, o.face),
		"mask": true,   # every outfit wears a balaclava in its face colour
		"gloves": M.fabric("outfit_gloves_" + id, o.gloves, 12.0),
		"boots": M.leather("outfit_boots_" + id, o.boots),
		"headgear": String(o.get("headgear", "helmet")),
		"goggles": bool(o.get("goggles", true)),
		"nvg": bool(o.get("nvg", false)),
	}
	out.merge(extra)
	return out


static var _pearls: Dictionary = {}


## Shiny lacquered plate: low roughness, a little metal, clear coat and a pink rim sheen.
static func _pearl(key: String, color: Color) -> StandardMaterial3D:
	if _pearls.has(key):
		return _pearls[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.45
	m.roughness = 0.12
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.03
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.8
	_pearls[key] = m
	return m


const FACET_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 c0 : source_color;
uniform vec3 c1 : source_color;
uniform vec3 c2 : source_color;
uniform vec3 c3 : source_color;
uniform float scale = 9.0;
varying vec3 lp;
varying vec3 ln;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() { lp = VERTEX; ln = NORMAL; }

void fragment() {
	// low-poly cloth: a skewed triangle grid on the dominant face of each part,
	// every triangle one flat tone
	vec3 an = abs(ln);
	vec2 uv = (an.x > an.y && an.x > an.z) ? lp.zy : ((an.y > an.z) ? lp.xz : lp.xy);
	vec2 p = uv * scale;
	p.x += p.y * 0.5;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float tri = step(f.x, f.y);
	float h = hash(cell * 2.0 + vec2(tri, 7.0));
	vec3 col = h < 0.34 ? c0 : (h < 0.6 ? c1 : (h < 0.84 ? c2 : c3));
	ALBEDO = col * (0.92 + 0.16 * hash(cell + tri * 3.1));
	ROUGHNESS = 0.9;
}
"""

static var _facets: Dictionary = {}


## Faceted, low-poly-look cloth in four tones.
static func _facet(key: String, colors: Array) -> ShaderMaterial:
	if _facets.has(key):
		return _facets[key]
	var sh := Shader.new()
	sh.code = FACET_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	for i in 4:
		m.set_shader_parameter("c%d" % i, colors[i])
	_facets[key] = m
	return m
