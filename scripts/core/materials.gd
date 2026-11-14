extends RefCounted
## Procedural, cached material factory (camo, fabric, concrete, wood, metal, FX).

static var _cache: Dictionary = {}


## Scanned PBR maps (ambientCG, CC0) in assets/pbr: "<set>_<map>", map =
## color | detail | normal | rough | ao. `detail` is the colour map's luminance
## normalised to 0.75, for tinting with any albedo colour. Null if missing.
static func pbr(tex_name: String) -> Texture2D:
	var key := "pbr_" + tex_name
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/pbr/%s.jpg" % tex_name
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_cache[key] = t
	return t


## Gives a triplanar material a scanned surface: real normal map, roughness
## map and (optionally) the luminance detail as albedo, tinted by `color`.
## `tile` = metres per texture repeat. Returns false if the set is missing.
static func _scan(m: StandardMaterial3D, set_name: String, tile: float, bump: float, rough: float, color = null) -> bool:
	var n := pbr(set_name + "_normal")
	if n == null:
		return false
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.normal_enabled = true
	m.normal_texture = n
	m.normal_scale = bump
	m.roughness = rough
	m.roughness_texture = pbr(set_name + "_rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var ao := pbr(set_name + "_ao")
	if ao != null:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.3
	if color != null:
		var c: Color = color
		m.albedo_texture = pbr(set_name + "_detail")
		m.albedo_color = Color(c.r / 0.72, c.g / 0.72, c.b / 0.72)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return true


static func solid(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "solid_%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[key] = m
	return m


static func noise_texture(colors: Array, offsets: Array, frequency: float, seed_value: int,
		cellular: bool = false, constant: bool = false, size: int = 256) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	else:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_octaves = 4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	if constant:
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.color_ramp = g
	return t


## Tileable bump normal map generated from noise.
static func normal_tex(frequency: float, seed_value: int, strength: float, cellular: bool = false) -> NoiseTexture2D:
	var key := "nrm_%.3f_%d_%.2f_%s" % [frequency, seed_value, strength, cellular]
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
	else:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_octaves = 5
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = strength
	t.noise = n
	_cache[key] = t
	return t


static func _add_normal(m: StandardMaterial3D, frequency: float, strength: float, scale: float = 0.8, cellular: bool = false) -> void:
	m.normal_enabled = true
	m.normal_texture = normal_tex(frequency, 7, strength, cellular)
	m.normal_scale = scale


## Blotchy military camouflage (4 colours, hard edges).
static func camo(key: String, colors: Array, scale: float = 3.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_texture(colors, [0.0, 0.42, 0.56, 0.7], 0.0055, absi(hash(key)) % 9999, false, true, 1024)
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	_add_normal(m, 0.09, 3.0, 0.5)
	# printed cloth: the weave rides on top of the pattern as a detail layer
	if pbr("fabric_normal") != null:
		# big soft folds from the noise normal; the thread-level weave is a
		# detail layer on its own UV so it stays fine whatever the pattern size
		m.normal_scale = 0.35
		m.detail_enabled = true
		m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		m.detail_albedo = pbr("fabric_detail")
		m.detail_normal = pbr("fabric_normal")
		m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
		m.uv2_triplanar = true
		m.uv2_scale = Vector3.ONE * 11.0
		m.albedo_color = Color(1.3, 1.3, 1.3)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.rim_enabled = true
	m.rim = 0.06
	m.rim_tint = 0.6
	_cache[key] = m
	return m


## Nylon / cordura fabric with subtle weave noise.
static func fabric(key: String, color: Color, scale: float = 6.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_texture([color.darkened(0.25), color, color.lightened(0.12)], [0.0, 0.5, 1.0],
			0.08, absi(hash(key)) % 9999)
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	_add_normal(m, 0.18, 2.5, 0.6)
	_scan(m, "fabric", 0.1, 1.0, 1.0, color)
	_cache[key] = m
	return m


static func concrete(key: String, color: Color, scale: float = 0.35) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_texture([color.darkened(0.3), color, color.lightened(0.1), color.darkened(0.12)],
			[0.0, 0.45, 0.7, 1.0], 0.03, absi(hash(key)) % 9999)
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	_add_normal(m, 0.05, 6.0, 1.0)
	if _scan(m, "concrete", 1.6, 1.0, 1.0, color):
		m.uv1_world_triplanar = true
	_cache[key] = m
	return m


static func wood(key: String, color: Color) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_texture([color.darkened(0.35), color, color.lightened(0.08), color.darkened(0.15)],
			[0.0, 0.4, 0.65, 1.0], 0.05, absi(hash(key)) % 9999)
	m.roughness = 0.85
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.6, 3.0, 0.6)
	_add_normal(m, 0.06, 5.0, 0.9)
	_scan(m, "bark" if ("bark" in key or key == "log") else "planks", 0.9, 1.0, 1.0, color)
	_cache[key] = m
	return m


static func painted_metal(key: String, color: Color) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var rust := Color(0.35, 0.2, 0.12)
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_texture([rust, color.darkened(0.2), color, color.lightened(0.05)],
			[0.0, 0.12, 0.5, 1.0], 0.04, absi(hash(key)) % 9999)
	m.roughness = 0.58
	m.roughness_texture = noise_texture([Color(0.35, 0.35, 0.35), Color.WHITE], [0.0, 1.0], 0.035, 31)
	m.metallic = 0.45
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.4
	_add_normal(m, 0.08, 3.5, 0.7)
	# brushed / scratched steel under the paint: streaky roughness and fine scratches
	if pbr("metal_normal") != null:
		m.normal_texture = pbr("metal_normal")
		m.normal_scale = 0.8
		m.roughness_texture = pbr("metal_detail")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 0.75
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## Unshaded additive glow for flashes, tracers, sparks.
static func glow(color: Color, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	return m


static func emissive(key: String, color: Color, energy: float = 2.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


static func floor_grid(key: String, base: Color, line: Color, strength: float = 0.35) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.17, 0.19, 0.22);
uniform vec3 line_color : source_color = vec3(0.3, 0.33, 0.37);
uniform float line_strength = 0.35;
uniform sampler2D noise_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float puddles = 0.6;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float grid(vec2 p) {
	vec2 w = max(fwidth(p), vec2(1e-4));
	vec2 g = abs(fract(p - 0.5) - 0.5) / w;
	return 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
}
void fragment() {
	vec2 p = world_pos.xz;
	float minor = grid(p) * 0.12;
	float major = grid(p / 4.0);
	float n = texture(noise_tex, p * 0.035).r;
	float n2 = texture(noise_tex, p * 0.31).r;
	vec3 col = base_color * (0.78 + 0.36 * n) * (0.9 + 0.14 * n2);
	col = mix(col, line_color, max(minor, major) * line_strength * 0.45);
	float wet = smoothstep(0.6, 0.66, texture(noise_tex, p * 0.018 + vec2(0.37, 0.71)).r) * puddles;
	col *= mix(1.0, 0.55, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.82 - 0.25 * n, 0.04, wet);
	SPECULAR = mix(0.35, 0.6, wet);
	NORMAL_MAP = mix(texture(normal_tex, p * 0.45).rgb, vec3(0.5, 0.5, 1.0), wet);
	NORMAL_MAP_DEPTH = 0.45;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("line_color", line)
	m.set_shader_parameter("line_strength", strength)
	var nt := NoiseTexture2D.new()
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	var n := FastNoiseLite.new()
	n.frequency = 0.012
	n.fractal_octaves = 5
	n.seed = absi(hash(key)) % 9999
	nt.noise = n
	m.set_shader_parameter("noise_tex", nt)
	m.set_shader_parameter("normal_tex", normal_tex(0.06, 3, 5.0))
	_cache[key] = m
	return m


static func hazard_stripes() -> ShaderMaterial:
	if _cache.has("hazard"):
		return _cache["hazard"]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
void fragment() {
	float s = step(0.5, fract((UV.x * 8.0 + UV.y * 2.0)));
	ALBEDO = mix(vec3(0.04), vec3(0.78, 0.6, 0.08), s);
	ROUGHNESS = 0.7;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache["hazard"] = m
	return m


## Soft dark radial blot used for bullet holes, blood and stains.
static func blot(key: String, color: Color) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([color, Color(color, color.a * 0.7), Color(color, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## Matte painted / moulded surface (helmets, plastics, hard gear): subtle tone
## variation and a fine micro-normal, so it catches light without looking glossy.
static func matte(key: String, color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_texture([color.darkened(0.14), color, color.lightened(0.05)], [0.0, 0.5, 1.0],
			0.06, absi(hash(key)) % 9999)
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 8.0
	_add_normal(m, 0.3, 1.6, 0.3)
	_cache[key] = m
	return m


## Worn leather / rubber (boots, slings, straps): creased, mid roughness.
static func leather(key: String, color: Color) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_texture([color.darkened(0.3), color, color.lightened(0.1), color.darkened(0.1)],
			[0.0, 0.45, 0.7, 1.0], 0.07, absi(hash(key)) % 9999)
	m.roughness = 0.62
	m.roughness_texture = noise_texture([Color(0.6, 0.6, 0.6), Color.WHITE], [0.0, 1.0], 0.12, 77)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 9.0
	_add_normal(m, 0.12, 3.0, 0.5)
	_cache[key] = m
	return m


## Automotive paint: metallic flake under a clear coat, with roughness variation.
static func car_paint(key: String, color: Color) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	# automotive paint: an even base coat with faint road film, metallic flake
	# underneath and a hard, glossy clear coat on top
	var m := StandardMaterial3D.new()
	m.albedo_texture = noise_texture([color.darkened(0.1), color, color.lightened(0.03), color.darkened(0.05)],
			[0.0, 0.35, 0.65, 1.0], 0.03, absi(hash(key)) % 9999)
	m.metallic = 0.35
	m.roughness = 0.42
	m.roughness_texture = noise_texture([Color(0.72, 0.72, 0.72), Color.WHITE], [0.0, 1.0], 0.06, 41 + absi(hash(key)) % 97)
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.07
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5
	_cache[key] = m
	return m


## Tinted safety glass: near-black body, mirror-sharp reflections of the sky.
static func car_glass() -> StandardMaterial3D:
	if _cache.has("car_glass"):
		return _cache["car_glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.026, 0.03)
	m.roughness = 0.04
	m.metallic = 0.0
	m.metallic_specular = 0.9
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.02
	_cache["car_glass"] = m
	return m


## Road / floor paint that has flaked and scuffed: the surface below shows
## through the gaps (alpha scissor, world-space so every stripe matches).
static func road_paint(key: String, color: Color, cover: float = 0.68) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var gone := 1.0 - cover
	m.albedo_texture = noise_texture([Color(color, 0.0), Color(color, 0.0), Color(color.darkened(0.2), 1.0), Color(color, 1.0)],
			[0.0, gone * 0.9, gone * 1.1, 1.0], 0.16, absi(hash(key)) % 9999)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.78
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5
	_cache[key] = m
	return m


static var _weave_tex: Array = []


## 2x2 twill carbon weave: [albedo, normal] textures, built once.
static func _carbon_textures() -> Array:
	if not _weave_tex.is_empty():
		return _weave_tex
	var n := 128
	var tows := 8.0
	var alb := Image.create(n, n, false, Image.FORMAT_RGB8)
	var hgt := PackedFloat32Array()
	hgt.resize(n * n)
	for y in n:
		for x in n:
			var u := x * tows / n
			var v := y * tows / n
			var cx := floorf(u)
			var cy := floorf(v)
			var warp := fposmod(cx + cy, 4.0) < 2.0
			var across := (u - cx) if warp else (v - cy)
			var along := (v - cy) if warp else (u - cx)
			var tow := sin(across * PI)
			var fil := 0.88 + 0.12 * sin(along * 50.0 + across * 2.0)
			var lum := tow * fil * (0.6 if warp else 1.0)
			alb.set_pixel(x, y, Color(0.04, 0.042, 0.048).lerp(Color(0.2, 0.21, 0.235), lum))
			hgt[y * n + x] = tow * (0.8 if warp else 1.0)
	var nrm := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var dx := hgt[y * n + (x + 1) % n] - hgt[y * n + (x - 1 + n) % n]
			var dy := hgt[((y + 1) % n) * n + x] - hgt[((y - 1 + n) % n) * n + x]
			var nv := Vector3(-dx * 2.0, -dy * 2.0, 1.0).normalized()
			nrm.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5))
	alb.generate_mipmaps()
	nrm.generate_mipmaps()
	_weave_tex = [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(nrm)]
	return _weave_tex


## Carbon fibre. `gloss` true: lacquered armour plates (clear coat, low
## roughness); false: carbon-weave fabric for the suit (satin).
static func carbon_fiber(key: String, gloss: bool, scale: float = 12.0) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var tex := _carbon_textures()
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex[0]
	m.normal_enabled = true
	m.normal_texture = tex[1]
	m.normal_scale = 0.7 if gloss else 0.9
	m.roughness = 0.22 if gloss else 0.55
	m.metallic = 0.3 if gloss else 0.1
	if gloss:
		m.clearcoat_enabled = true
		m.clearcoat = 0.8
		m.clearcoat_roughness = 0.05
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m
