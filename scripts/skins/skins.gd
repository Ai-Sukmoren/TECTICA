extends RefCounted
## Weapon skin catalogue: finishes, rarities, supply packs and the procedural
## finish shader. Every finish works on every gun (10 guns x 19 finishes).
## A finish recolours a gun's receiver / metal parts and, a little darker,
## its polymer / wood furniture; optics glass, lenses and lasers are kept.

const Data = preload("res://scripts/weapons/weapon_data.gd")

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]
const RARITY_COLORS := [Color(0.72, 0.74, 0.77), Color(0.42, 0.86, 0.46), Color(0.32, 0.62, 1.0),
		Color(0.74, 0.42, 1.0), Color(1.0, 0.78, 0.25)]
## credits refunded for a duplicate
const DUP_REFUND := [15, 30, 70, 180, 500]

## pattern ids understood by FINISH_SHADER
enum P { SOLID, CAMO, DIGITAL, TIGER, SPLINTER, CARBON, HEX, DAMASCUS, NEON, CRACKS, CIRCUIT, GOLD, SCALES, AURORA, VOID }

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
}

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


static func finish_ids() -> Array:
	var ids: Array = FINISHES.keys()
	ids.sort_custom(func(a, b):
		var ra := int(FINISHES[a].r)
		var rb := int(FINISHES[b].r)
		return ra < rb if ra != rb else String(FINISHES[a].name) < String(FINISHES[b].name))
	return ids


static func finishes_of(rarity: int) -> Array:
	var out: Array = []
	for id in FINISHES:
		if int(FINISHES[id].r) == rarity:
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
	}
	ALBEDO = col * tint;
	METALLIC = m;
	ROUGHNESS = r;
	EMISSION = e;
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
			continue
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled \
					or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
				continue
		else:
			continue   # shader materials (reticles etc.) keep their look
		mi.material_override = mm if mat in metal_mats else fm
