extends RefCounted
## Weapon skin catalogue: finishes, rarities, supply packs and the procedural
## finish shader. Every finish works on every gun.
## A finish recolours a gun's receiver / metal parts and, a little darker,
## its polymer / wood furniture; optics glass, lenses and lasers are kept.

const Data = preload("res://scripts/weapons/weapon_data.gd")

## MYTHIC is admin-only: it never drops from packs (pack odds cover the first five).
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, MYTHIC }

const RARITY_NAMES := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY", "MYTHIC"]
const RARITY_COLORS := [Color(0.72, 0.74, 0.77), Color(0.42, 0.86, 0.46), Color(0.32, 0.62, 1.0),
		Color(0.74, 0.42, 1.0), Color(1.0, 0.78, 0.25), Color(1.0, 0.16, 0.26)]
## credits refunded for a duplicate
const DUP_REFUND := [15, 30, 70, 180, 500, 0]

## pattern ids understood by FINISH_SHADER
enum P { SOLID, CAMO, DIGITAL, TIGER, SPLINTER, CARBON, HEX, DAMASCUS, NEON, CRACKS, CIRCUIT, GOLD, SCALES, AURORA, VOID, RUBY, TEXTURE, CARBON_X }

## id -> name, rarity, pattern, 4 colours, metallic, roughness, scale, emission, animated
const FINISHES := {
	# --- common: plain cerakote / anodised finishes
	"cerakote_tan": {"name": "Desert Cerakote", "r": 0, "p": P.SOLID, "c": [Color(0.55, 0.47, 0.34)], "m": 0.15, "ro": 0.62},
	"ranger_green": {"name": "Ranger Green", "r": 0, "p": P.SOLID, "c": [Color(0.25, 0.28, 0.18)], "m": 0.15, "ro": 0.62},
	"gunmetal": {"name": "Gunmetal", "r": 0, "p": P.SOLID, "c": [Color(0.34, 0.36, 0.39)], "m": 0.75, "ro": 0.32},
	"arctic": {"name": "Arctic White", "r": 0, "p": P.SOLID, "c": [Color(0.82, 0.83, 0.84)], "m": 0.1, "ro": 0.55},
	# --- uncommon: field camouflage
	"woodland": {"name": "Woodland", "r": 1, "p": P.CAMO, "s": 20.0,
			"c": [Color(0.33, 0.37, 0.22), Color(0.23, 0.26, 0.15), Color(0.42, 0.33, 0.21), Color(0.09, 0.09, 0.07)]},
	"urban_digital": {"name": "Urban Digital", "r": 1, "p": P.DIGITAL, "s": 11.0,
			"c": [Color(0.6, 0.62, 0.64), Color(0.4, 0.42, 0.45), Color(0.24, 0.25, 0.27), Color(0.78, 0.79, 0.8)]},
	"jungle_tiger": {"name": "Jungle Tiger", "r": 1, "p": P.TIGER, "s": 16.0,
			"c": [Color(0.38, 0.42, 0.22), Color(0.07, 0.08, 0.05), Color(0.5, 0.48, 0.3)]},
	"desert_splinter": {"name": "Desert Splinter", "r": 1, "p": P.SPLINTER, "s": 10.0,
			"c": [Color(0.66, 0.57, 0.41), Color(0.5, 0.42, 0.29), Color(0.36, 0.3, 0.21), Color(0.74, 0.67, 0.52)]},
	# --- rare: premium materials
	"carbon_weave": {"name": "Carbon Weave", "r": 2, "p": P.CARBON, "s": 7.0, "m": 0.35, "ro": 0.22,
			"c": [Color(0.05, 0.05, 0.06), Color(0.2, 0.21, 0.23)]},
	"hex_plate": {"name": "Hex Plate", "r": 2, "p": P.HEX, "s": 7.0, "m": 0.7, "ro": 0.3,
			"c": [Color(0.24, 0.33, 0.42), Color(0.07, 0.09, 0.12), Color(0.45, 0.58, 0.7)]},
	"damascus": {"name": "Damascus Steel", "r": 2, "p": P.DAMASCUS, "s": 18.0, "m": 0.95, "ro": 0.24,
			"c": [Color(0.62, 0.62, 0.64), Color(0.22, 0.22, 0.24)]},
	"crimson_tiger": {"name": "Crimson Tiger", "r": 2, "p": P.TIGER, "s": 16.0, "m": 0.3, "ro": 0.35,
			"c": [Color(0.62, 0.08, 0.06), Color(0.05, 0.03, 0.03), Color(0.85, 0.2, 0.1)]},
	# --- epic: glowing, animated
	"neon_tide": {"name": "Neon Tide", "r": 3, "p": P.NEON, "s": 12.0, "m": 0.4, "ro": 0.25, "e": 3.0, "a": 1.0,
			"c": [Color(0.04, 0.05, 0.12), Color(0.0, 0.95, 1.0), Color(1.0, 0.15, 0.85)]},
	"blood_moon": {"name": "Blood Moon", "r": 3, "p": P.CRACKS, "s": 12.0, "m": 0.2, "ro": 0.3, "e": 4.0, "a": 1.0,
			"c": [Color(0.06, 0.02, 0.02), Color(0.28, 0.05, 0.04), Color(1.0, 0.12, 0.05)]},
	"overclock": {"name": "Overclock", "r": 3, "p": P.CIRCUIT, "s": 16.0, "m": 0.5, "ro": 0.3, "e": 3.5, "a": 1.0,
			"c": [Color(0.03, 0.04, 0.035), Color(0.15, 1.0, 0.45), Color(0.09, 0.12, 0.1)]},
	# --- legendary
	"gilded_royale": {"name": "Gilded Royale", "r": 4, "p": P.GOLD, "s": 12.0, "m": 1.0, "ro": 0.2,
			"c": [Color(1.0, 0.76, 0.32), Color(0.45, 0.28, 0.08), Color(0.08, 0.06, 0.05)]},
	"dragon_scale": {"name": "Dragon Scale", "r": 4, "p": P.SCALES, "s": 18.0, "m": 0.8, "ro": 0.25, "e": 0.6,
			"c": [Color(0.04, 0.32, 0.26), Color(0.15, 0.85, 0.6), Color(1.0, 0.75, 0.25)]},
	"aurora": {"name": "Aurora", "r": 4, "p": P.AURORA, "s": 12.0, "m": 0.5, "ro": 0.2, "e": 2.5, "a": 1.0,
			"c": [Color(0.1, 0.9, 0.6), Color(0.3, 0.4, 1.0), Color(0.95, 0.3, 0.9)]},
	"event_horizon": {"name": "Event Horizon", "r": 4, "p": P.VOID, "s": 8.0, "m": 0.3, "ro": 0.18, "e": 5.0, "a": 1.0,
			"c": [Color(0.01, 0.01, 0.02), Color(0.75, 0.55, 1.0), Color(0.25, 0.1, 0.45)]},
	# --- mythic, admin exclusive: never in packs
	"ruby": {"name": "Mythic Ruby", "r": 5, "p": P.RUBY, "s": 9.0, "m": 0.6, "ro": 0.03, "e": 1.6, "a": 1.0, "admin": true, "sticker": "patch_02",
			"c": [Color(0.3, 0.0, 0.02), Color(0.78, 0.0, 0.05), Color(1.0, 0.22, 0.3)]},
	"carbon_mythic": {"name": "Mythic Carbon", "r": Rarity.MYTHIC, "p": P.CARBON_X, "s": 9.0, "m": 0.4, "ro": 0.16, "e": 1.5, "a": 1.0, "admin": true,
			"c": [Color(0.022, 0.023, 0.027), Color(0.17, 0.18, 0.21), Color(1.0, 0.1, 0.18)]},
	"mythicskin": {"name": "mythicskin", "r": Rarity.MYTHIC, "p": P.TEXTURE, "s": 6.0, "m": 0.1, "ro": 0.4, "admin": true,
			"c": [Color(1.0, 1.0, 1.0)], "texture": preload("res://assets/skins/mythicskin.png")},
}

## Sticker textures that finishes can carry (placement is per gun, see collection.gd).
const STICKERS := {"patch_02": "res://assets/stickers/patch_02.png"}

## Supply packs: 5 skins each, odds per rarity (percent), guaranteed minimum
## rarity on the last card, price in credits, foil colours.
const PACKS := [
	{"id": "recruit", "name": "RECRUIT CRATE", "price": 250, "cards": 5, "odds": [62.0, 26.0, 9.0, 2.5, 0.5], "guarantee": -1,
			"tag": "FIELD-ISSUE FINISHES", "colors": [Color(0.32, 0.36, 0.24), Color(0.6, 0.55, 0.38)]},
	{"id": "operator", "name": "OPERATOR CASE", "price": 600, "cards": 5, "odds": [40.0, 32.0, 18.0, 8.0, 2.0], "guarantee": 2,
			"tag": "1 RARE OR BETTER GUARANTEED", "colors": [Color(0.12, 0.22, 0.42), Color(0.35, 0.62, 1.0)]},
	{"id": "blackops", "name": "BLACK OPS CACHE", "price": 1500, "cards": 5, "odds": [15.0, 30.0, 30.0, 18.0, 7.0], "guarantee": 3,
			"tag": "1 EPIC OR BETTER GUARANTEED", "colors": [Color(0.08, 0.06, 0.1), Color(1.0, 0.75, 0.25)]},
]


static func weapon_ids() -> Array:
	return Data.WEAPONS.keys()


static func is_admin_finish(finish: String) -> bool:
	return FINISHES.has(finish) and bool(FINISHES[finish].get("admin", false))


## Finishes shown in the collection; admin-only ones only when `with_admin`.
static func finish_ids(with_admin: bool = false) -> Array:
	var ids: Array = FINISHES.keys().filter(func(f): return with_admin or not is_admin_finish(f))
	ids.sort_custom(func(a, b):
		var ra := int(FINISHES[a].r)
		var rb := int(FINISHES[b].r)
		return ra < rb if ra != rb else String(FINISHES[a].name) < String(FINISHES[b].name))
	return ids


static func finishes_of(rarity: int) -> Array:
	var out: Array = []
	for id in FINISHES:
		if int(FINISHES[id].r) == rarity and not is_admin_finish(id):   # packs never drop admin finishes
			out.append(id)
	return out


static func rarity_of(finish: String) -> int:
	return int(FINISHES[finish].r) if FINISHES.has(finish) else 0


static func finish_name(finish: String) -> String:
	return String(FINISHES[finish].name) if FINISHES.has(finish) else "FACTORY"


static func weapon_name(id: String) -> String:
	return String(Data.WEAPONS[id].name) if Data.WEAPONS.has(id) else id.to_upper()


static func key(weapon: String, finish: String) -> String:
	return weapon + ":" + finish


# ------------------------------------------------------------------ materials

const FINISH_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int pattern = 0;
uniform vec3 c0 : source_color = vec3(0.5);
uniform vec3 c1 : source_color = vec3(0.3);
uniform vec3 c2 : source_color = vec3(0.2);
uniform vec3 c3 : source_color = vec3(0.1);
uniform float metal = 0.3;
uniform float rough = 0.5;
uniform float scale = 6.0;
uniform float emit = 0.0;
uniform float anim = 0.0;
uniform float tint = 1.0;      // furniture parts are drawn a bit darker
uniform sampler2D finish_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 lp;
varying vec3 ln;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.03 + 17.1; a *= 0.5; }
	return v;
}
vec3 hue(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }

void vertex() { lp = VERTEX; ln = NORMAL; }

void fragment() {
	vec3 an = abs(ln);
	vec2 uv = (an.x > an.y && an.x > an.z) ? lp.zy : ((an.y > an.z) ? lp.xz : lp.xy);
	vec2 p = uv * scale;
	float t = TIME * anim;
	vec3 col = c0;
	float m = metal;
	float r = rough;
	vec3 e = vec3(0.0);
	float cc = 0.0;
	switch (pattern) {
		case 0: {  // solid cerakote
			col = c0 * (0.9 + 0.18 * fbm(p * 4.0));
			break;
		}
		case 1: {  // woodland camo
			float f = fbm(p * 0.9);
			float g = fbm(p * 1.8 + 7.0);
			col = f < 0.42 ? c0 : (f < 0.55 ? c1 : (g < 0.5 ? c2 : c3));
			break;
		}
		case 2: {  // digital pixels
			vec2 q = floor(p * 3.0);
			float h = vnoise(q * 0.35) * 0.65 + hash(q) * 0.35;
			col = h < 0.35 ? c0 : (h < 0.55 ? c1 : (h < 0.72 ? c2 : c3));
			break;
		}
		case 3: {  // tiger stripes
			float s = sin(p.x * 2.2 + fbm(p * 0.8) * 6.0);
			col = mix(c0, c2, smoothstep(0.3, 0.9, fbm(p * 2.0)) * 0.35);
			col = s > 0.45 ? c1 : col;
			break;
		}
		case 4: {  // splinter shards
			vec2 q = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p;
			float h = hash(floor(q * vec2(0.9, 2.6)));
			col = h < 0.3 ? c0 : (h < 0.55 ? c1 : (h < 0.8 ? c3 : c2));
			break;
		}
		case 5: {  // carbon weave
			vec2 v = p * 5.0;
			bool odd = mod(floor(v.x) + floor(v.y), 2.0) < 1.0;
			float w = odd ? sin(fract(v.x) * 3.14159) : sin(fract(v.y) * 3.14159);
			col = mix(c0, c1, w * 0.85);
			r = mix(rough + 0.2, rough, w);
			break;
		}
		case 6: {  // hexagonal armour plates
			vec2 q = p * 1.6;
			q.x *= 1.1547;
			q.y += mod(floor(q.x), 2.0) * 0.5;
			vec2 f = abs(fract(q) - 0.5);
			float d = max(f.x * 1.5 + f.y, f.y * 2.0);
			float edge = smoothstep(0.92, 0.98, d);
			col = mix(c0 * (0.85 + 0.3 * hash(floor(q))), c1, edge);
			col = mix(col, c2, smoothstep(0.75, 0.9, d) * (1.0 - edge) * 0.4);
			break;
		}
		case 7: {  // damascus folded steel
			float s = sin(p.y * 5.0 + fbm(p * 1.4) * 7.0 + p.x * 0.8);
			col = mix(c1, c0, smoothstep(-0.25, 0.25, s));
			break;
		}
		case 8: {  // neon tide: flowing bands
			float s = sin(p.x * 1.4 - t * 1.6 + fbm(p * 0.9) * 5.0);
			float band = smoothstep(0.75, 0.97, s);
			vec3 glow = mix(c1, c2, 0.5 + 0.5 * sin(p.y * 0.8 + t));
			col = mix(c0, glow * 0.6, band);
			e = glow * band * emit;
			break;
		}
		case 9: {  // blood moon: dark marble with glowing cracks
			float f = fbm(p * 1.1);
			float crack = 1.0 - smoothstep(0.0, 0.035, abs(f - 0.5));
			col = mix(c0, c1, fbm(p * 3.0));
			e = c2 * crack * emit * (0.7 + 0.3 * sin(t * 2.2 + p.x));
			col = mix(col, c2, crack * 0.6);
			break;
		}
		case 10: {  // overclock: circuit traces with pulses
			vec2 g = p * 1.5;
			vec2 cell = floor(g);
			vec2 f = fract(g);
			float h = hash(cell);
			float line = h < 0.5 ? (1.0 - smoothstep(0.03, 0.07, abs(f.y - 0.5))) : (1.0 - smoothstep(0.03, 0.07, abs(f.x - 0.5)));
			float pad = 1.0 - smoothstep(0.08, 0.13, length(f - 0.5));
			float lit = max(line * step(0.25, hash(cell + 3.1)), pad * step(0.7, h));
			float pulse = 0.5 + 0.5 * sin(t * 3.0 - (cell.x + cell.y) * 0.9);
			col = mix(c0, c2, lit);
			e = c1 * lit * emit * (0.35 + 0.65 * pulse);
			break;
		}
		case 11: {  // gilded: polished gold with engraved scrollwork
			float sc = sin(p.x * 3.0 + sin(p.y * 4.0) * 1.6) * sin(p.y * 3.0 + sin(p.x * 3.5) * 1.6);
			float groove = 1.0 - smoothstep(0.0, 0.08, abs(sc));
			col = mix(c0 * (0.9 + 0.15 * fbm(p * 6.0)), c1, groove * 0.85);
			r = mix(rough, 0.6, groove);
			break;
		}
		case 12: {  // dragon scales, iridescent
			vec2 q = p * vec2(1.4, 2.0);
			q.x += mod(floor(q.y), 2.0) * 0.5;
			vec2 f = fract(q) - vec2(0.5, 0.0);
			float d = length(f * vec2(1.0, 1.1));
			float rim = smoothstep(0.42, 0.52, d);
			float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
			vec3 iri = mix(c0, c1, smoothstep(0.1, 0.5, d) + fres * 0.6);
			col = mix(iri, c2 * 0.8, rim);
			e = c1 * fres * emit;
			break;
		}
		case 13: {  // aurora: drifting colour ribbons
			float h = fbm(p * 0.7 + vec2(t * 0.15, 0.0)) + p.x * 0.05 + t * 0.05;
			vec3 a = mix(c0, c1, 0.5 + 0.5 * sin(h * 6.0));
			a = mix(a, c2, 0.5 + 0.5 * sin(h * 4.0 + 2.0));
			float ribbon = smoothstep(0.3, 0.7, fbm(p * 0.9 - vec2(0.0, t * 0.2)));
			col = mix(vec3(0.02, 0.03, 0.07), a, 0.12 + 0.88 * ribbon);
			e = a * ribbon * emit * 0.5;
			break;
		}
		case 14: {  // event horizon: black with a twinkling starfield
			vec2 q = floor(p * 4.0);
			float h = hash(q);
			float star = step(0.9, h) * (1.0 - smoothstep(0.05, 0.3, length(fract(p * 4.0) - 0.5)));
			float neb = fbm(p * 0.6 + t * 0.03);
			col = mix(c0, c2 * 0.6, smoothstep(0.4, 0.75, neb));
			e = c1 * star * emit * (0.55 + 0.45 * sin(t * 4.0 + h * 60.0)) + c2 * smoothstep(0.45, 0.8, neb) * 0.9;
			break;
		}
		case 15: {  // ruby: cut-gem facets with internal fire and glints
			vec2 g = p * 1.3;
			vec2 cell = floor(g);
			float best = 9.0;
			float second = 9.0;
			vec2 id = cell;
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					vec2 c = cell + vec2(float(x), float(y));
					vec2 o = c + vec2(hash(c), hash(c + 5.3));
					float d = length(g - o);
					if (d < best) { second = best; best = d; id = c; } else if (d < second) { second = d; }
				}
			}
			float facet = hash(id + 1.7);
			float edge = 1.0 - smoothstep(0.0, 0.06, second - best);
			float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
			// sparkles: tiny points near facet edges, not whole faces
			vec2 sp = floor(g * 9.0);
			float spark = step(0.93, hash(sp)) * (1.0 - smoothstep(0.0, 0.35, length(fract(g * 9.0) - 0.5)));
			float glint = spark * pow(max(sin(t * 2.0 + hash(sp + 2.0) * 40.0), 0.0), 6.0) + edge * pow(max(sin(t * 1.1 + facet * 30.0), 0.0), 16.0) * 0.6;
			col = mix(c0, c1, 0.25 + facet * 0.65 + fres * 0.2);
			col = mix(col, c2, edge * 0.12);
			r = rough + edge * 0.05;
			cc = 1.0;   // glossy lacquer over the gem
			float glow = 0.5 + 0.5 * sin(t * 0.8 + facet * 6.28);
			e = c1 * (0.1 + 0.2 * facet * glow + fres * 0.45) * emit + c2 * glint * emit * 2.2;
			break;
		}
		case 16: {  // artwork projected onto the dominant face of each part
			col = texture(finish_texture, p + vec2(0.5)).rgb;
			break;
		}
		case 17: {  // mythic carbon: 2x2 twill under deep lacquer, a light sweep and red hairlines
			vec2 v = p * 6.0;
			vec2 cell = floor(v);
			vec2 f = fract(v);
			// 2x2 twill: tows step over two, under two, shifted one per row
			bool warp = mod(cell.x + cell.y, 4.0) < 2.0;
			float along = warp ? f.y : f.x;
			float across = warp ? f.x : f.y;
			float tow = sin(across * 3.14159);                    // rounded tow profile
			float fil = 0.85 + 0.15 * sin(along * 60.0 + across * 3.0);   // filaments along the tow
			float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
			// the weave catches light differently on warp and weft
			float sheen = warp ? 0.55 : 1.0;
			col = mix(c0, c1, tow * fil * sheen);
			// slow diagonal light sweep across the lacquer
			float sweep = smoothstep(0.92, 1.0, sin((uv.x + uv.y) * 3.0 - t * 1.2));
			col += c1 * sweep * 0.9;
			// thin glowing hairlines between plates
			float line = smoothstep(0.485, 0.496, abs(fract(uv.x * 3.0 + 0.13) - 0.5));   // only at the cell edge
			float pulse = 0.6 + 0.4 * sin(t * 2.0 + uv.y * 4.0);
			col = mix(col, c2 * 0.4, line);
			m = metal * (0.6 + 0.4 * tow);
			r = mix(rough + 0.1, rough, tow);
			cc = 1.0;
			e = c2 * line * pulse * emit + c1 * fres * 0.25 * emit;
			break;
		}
	}
	ALBEDO = col * tint;
	METALLIC = m;
	ROUGHNESS = r;
	EMISSION = e;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.02;
}
"""

static var _shader: Shader
static var _mats: Dictionary = {}


## Shared material for a finish; `furniture` = darker variant for polymer / wood.
static func material(finish: String, furniture: bool) -> ShaderMaterial:
	var k := finish + ("_f" if furniture else "_m")
	if _mats.has(k):
		return _mats[k]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = FINISH_SHADER
	var f: Dictionary = FINISHES[finish]
	var m := ShaderMaterial.new()
	m.shader = _shader
	var c: Array = f.c
	m.set_shader_parameter("pattern", int(f.p))
	m.set_shader_parameter("c0", c[0])
	m.set_shader_parameter("c1", c[1] if c.size() > 1 else (c[0] as Color).darkened(0.3))
	m.set_shader_parameter("c2", c[2] if c.size() > 2 else (c[0] as Color).lightened(0.2))
	m.set_shader_parameter("c3", c[3] if c.size() > 3 else (c[0] as Color).darkened(0.6))
	m.set_shader_parameter("metal", float(f.get("m", 0.3)) * (0.5 if furniture else 1.0))
	m.set_shader_parameter("rough", float(f.get("ro", 0.5)) + (0.12 if furniture else 0.0))
	m.set_shader_parameter("scale", float(f.get("s", 6.0)))
	m.set_shader_parameter("emit", float(f.get("e", 0.0)))
	m.set_shader_parameter("anim", float(f.get("a", 0.0)))
	m.set_shader_parameter("tint", 0.68 if furniture else 1.0)
	if f.has("texture"):
		m.set_shader_parameter("finish_texture", f.texture)
	_mats[k] = m
	return m


## Recolours a built weapon model. Glass, glowing parts and lenses stay as they are.
static func apply(model_root: Node, finish: String, metal_mats: Array) -> void:
	if not FINISHES.has(finish) or model_root == null:
		return
	var mm := material(finish, false)
	var fm := material(finish, true)
	var stack: Array = [model_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var mat := mi.material_override
		if mat == null:
			if mi.has_meta("pack4"):   # textured asset-pack-4 gun parts
				mi.material_override = fm
			continue
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled \
					or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
				continue
		else:
			continue   # shader materials (reticles etc.) keep their look
		mi.material_override = mm if mat in metal_mats else fm
