extends RefCounted
## Shaders + meshes for the forest: ground (grass / dirt road mask), foliage
## with wind sway and top-down see-through fade, wind-blown grass, creek
## water, and the day/night sky.

const M = preload("res://scripts/core/materials.gd")

## Every material that fades around the player in top-down view.
static var fade_materials: Array = []


static func _noise(freq: float, seed_value: int, size: int = 256) -> NoiseTexture2D:
	return M.noise_texture([Color.BLACK, Color.WHITE], [0.0, 1.0], freq, seed_value, false, false, size)


# ------------------------------------------------------------------ ground

const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
// mask: r = dirt road, g = trodden, b = creek mud, a = forest floor (under canopy)
uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D noise_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float map_size = 200.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	vec4 m = texture(mask, p / map_size + 0.5);
	float macro = texture(noise_a, p * 0.0045 + 0.11).r;    // big meadow patches
	float n1 = texture(noise_a, p * 0.014).r;
	float n2 = texture(noise_b, p * 0.21).r;
	float n3 = texture(noise_a, p * 0.09 + 0.37).r;
	float fine = texture(noise_b, p * 1.1 + 0.5).r;           // grass clumps
	float grain = texture(noise_a, p * 3.3).r;                // pebbles / needles

	// meadow: lush and dry patches, damp moss, sparse clumps
	vec3 grass = mix(vec3(0.05, 0.125, 0.028), vec3(0.14, 0.25, 0.05), n1);
	grass = mix(grass, vec3(0.34, 0.31, 0.12), smoothstep(0.5, 0.82, macro) * 0.38 + smoothstep(0.62, 0.9, n2) * 0.18);
	grass = mix(grass, vec3(0.04, 0.09, 0.035), smoothstep(0.58, 0.86, n3) * 0.45);
	grass *= 0.74 + 0.46 * fine;
	// blade streaks: two stretched noise lookups read as mown / lying grass up close
	float blade = texture(noise_b, p * vec2(7.0, 1.9)).r * texture(noise_b, p.yx * vec2(6.3, 2.2) + 0.41).r;
	grass *= 0.62 + 1.5 * blade;

	// forest floor: pine needles, leaf litter and moss under the canopy
	vec3 litter = mix(vec3(0.15, 0.1, 0.055), vec3(0.27, 0.19, 0.1), n2);
	litter = mix(litter, vec3(0.08, 0.11, 0.045), smoothstep(0.52, 0.8, n3) * 0.55);
	litter *= 0.72 + 0.5 * grain;
	float forest = smoothstep(0.15, 0.75, m.a + (n3 - 0.5) * 0.45);

	// compacted dirt road with gravel and darker damp patches
	vec3 dirt = mix(vec3(0.34, 0.27, 0.19), vec3(0.22, 0.17, 0.12), n2);
	dirt *= 0.84 + 0.28 * grain;
	dirt = mix(dirt, vec3(0.46, 0.44, 0.4), step(0.8, grain) * 0.45);
	vec3 mud = mix(vec3(0.1, 0.08, 0.055), vec3(0.16, 0.12, 0.08), n2);

	float d = smoothstep(0.3, 0.7, clamp(m.r + (n2 - 0.5) * 0.45, 0.0, 1.0));
	float trod = smoothstep(0.25, 0.75, clamp(m.g + (n3 - 0.5) * 0.5, 0.0, 1.0));
	float wet = smoothstep(0.2, 0.8, m.b);
	float puddle = smoothstep(0.7, 0.78, n3) * smoothstep(0.75, 0.95, m.r) * (1.0 - wet);

	vec3 col = mix(grass, litter, forest);
	// scattered wildflowers in open meadow (white clover / yellow buttercup)
	float fl = texture(noise_a, p * 5.3 + 0.7).r;
	float flower = smoothstep(0.80, 0.84, fl) * (1.0 - forest) * smoothstep(0.35, 0.6, n1);
	col = mix(col, mix(vec3(0.85, 0.84, 0.72), vec3(0.9, 0.72, 0.12), step(0.5, n2)), flower * 0.8);
	col = mix(col, mix(col, dirt, 0.6), trod);
	col = mix(col, dirt, d);
	col = mix(col, mud, wet);
	col *= 1.0 - puddle * 0.45;
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.96, 0.85, d), 0.35, max(wet * 0.6, puddle));
	vec3 nA = texture(nrm, p * 0.35).rgb;
	vec3 nB = texture(nrm, p * 1.6 + 0.3).rgb;
	// Blend signed tangent normals, then encode back to texture space.
	vec3 blended = normalize(mix(nA * 2.0 - 1.0, nB * 2.0 - 1.0, 0.45));
	NORMAL_MAP = blended * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.85, 0.15, max(wet, puddle));
	AO = 0.82 + 0.18 * fine;
	AO_LIGHT_AFFECT = 0.4;
}
"""


static func ground_material(mask: Texture2D, map_size: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("mask", mask)
	m.set_shader_parameter("noise_a", _noise(0.02, 11))
	m.set_shader_parameter("noise_b", _noise(0.05, 23))
	m.set_shader_parameter("nrm", M.normal_tex(0.06, 7, 6.0))
	m.set_shader_parameter("map_size", map_size)
	return m


# ------------------------------------------------------------------ foliage / fade

## Shared code: top-down see-through. Fragments above the player's head
## within fade_out of fade_center are screen-door dithered away.
const FADE_FUNCS := """
uniform vec3 fade_center = vec3(0.0, -1000.0, 0.0);
uniform float fade_in = 0.0;
uniform float fade_out = 0.0;
uniform float fade_min_h = 2.1;
// camera position: cut-outs fade to solid far away so distant trees don't shimmer
uniform vec3 view_pos = vec3(0.0, 0.0, 0.0);
varying vec3 wpos;
float dither_hash(vec2 p) { return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453); }
void fade_clip(vec2 fragcoord) {
	if (fade_out > 0.0 && wpos.y > fade_center.y + fade_min_h) {
		float d = length(wpos.xz - fade_center.xz);
		float k = 1.0 - smoothstep(fade_in, fade_out, d);
		if (dither_hash(fragcoord) < k * 0.93) discard;
	}
}
"""

const FOLIAGE_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 base_color : source_color = vec3(0.2, 0.35, 0.12);
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sway = 0.05;
// local-space crown centre: normals are bent away from it so the canopy
// shades like one soft volume instead of hard facets
uniform vec3 crown_center = vec3(0.0, 0.65, 0.0);
uniform float round_normals = 0.0;
uniform float clump_scale = 2.2;
// leaf cut-out: 0 = solid; higher punches more gaps between leaf clusters
uniform float cutout = 0.0;
uniform float leaf_scale = 0.26;
%s
varying vec3 icol;
varying float ao;
varying float edge;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(mix(NORMAL, normalize(VERTEX - crown_center + vec3(0.0001)), round_normals));
	float h = max(VERTEX.y, 0.0);
	float s = sin(TIME * 1.1 + w.x * 0.21 + w.z * 0.17) + 0.4 * sin(TIME * 2.7 + w.z * 0.5);
	VERTEX.x += s * sway * h;
	VERTEX.z += s * sway * 0.6 * h;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	icol = COLOR.rgb;
	ao = COLOR.a;
	edge = UV.x;
}
void fragment() {
	fade_clip(FRAGCOORD.xy);
	if (cutout > 0.0) {
		// gaps between leaf / needle clusters; branch tips (edge = 1) are the most ragged
		float l1 = textureLod(noise, wpos.xz * leaf_scale + wpos.yy * (leaf_scale * 0.83), 1.5).r;
		float l2 = textureLod(noise, wpos.zy * (leaf_scale * 1.7) + 3.7, 1.5).r;
		float near = 1.0 - smoothstep(38.0, 75.0, distance(wpos, view_pos));
		if (l1 * 0.7 + l2 * 0.3 < cutout * mix(0.74, 1.2, edge) * near) discard;
	}
	float n = texture(noise, wpos.xz * 0.35 + vec2(wpos.y * 0.3)).r;
	float n2 = texture(noise, wpos.xy * 1.7 + wpos.zz * 0.9).r;
	// leaf / needle clumps: brighter tufts with dark gaps between them
	float c = texture(noise, wpos.xz * clump_scale + wpos.yy * (clump_scale * 0.7)).r;
	float clump = smoothstep(0.28, 0.72, c);
	vec3 col = base_color * icol * (0.7 + 0.45 * n) * (0.88 + 0.25 * n2);
	col *= mix(0.42, 1.16, clump);
	col = mix(col, col * vec3(1.25, 1.18, 0.7), smoothstep(0.55, 0.9, n) * 0.4);   // sun-bleached clusters
	col *= mix(0.8, 1.12, edge);                                                    // fresh, lighter growth at the tips
	ALBEDO = col;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	BACKLIGHT = base_color * vec3(1.3, 1.5, 0.6) * 0.75 * clump;                    // light glowing through leaves
	AO = mix(0.35, 1.0, ao) * (0.75 + 0.25 * clump);
	AO_LIGHT_AFFECT = 0.55;
}
"""

const SOLID_FADE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_color : source_color = vec3(0.4, 0.3, 0.2);
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float noise_scale = 1.5;
uniform float roughness = 0.85;
// > 0: overlapping shingle / canvas rows per metre of height
uniform float rows = 0.0;
%s
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	fade_clip(FRAGCOORD.xy);
	float n = texture(noise, (wpos.xz + wpos.yy) * noise_scale).r;
	vec3 col = base_color * (0.75 + 0.45 * n);
	if (rows > 0.0) {
		float r = wpos.y * rows;
		float row = floor(r);
		float along = (abs(NORMAL.x) > abs(NORMAL.z) ? wpos.z : wpos.x) * 2.6 + row * 0.37;
		float tile = fract(sin(dot(vec2(row, floor(along)), vec2(12.9898, 78.233))) * 43758.5453);
		col *= 0.78 + 0.34 * tile;                                   // every shingle weathers differently
		col *= mix(0.55, 1.0, smoothstep(0.0, 0.16, fract(r)));      // shadow under each overlapping row
		col *= mix(0.7, 1.0, smoothstep(0.0, 0.06, fract(along)));   // gaps between shingles
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
}
"""


static func foliage_material(color: Color, sway: float = 0.05) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = FOLIAGE_SHADER % FADE_FUNCS
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("noise", _noise(0.08, 31))
	m.set_shader_parameter("sway", sway)
	fade_materials.append(m)
	return m


## Foliage whose normals are rounded around a local crown `center`.
## `cut` > 0 punches leaf gaps (see FOLIAGE_SHADER).
static func canopy_material(color: Color, sway: float, center: Vector3, round_amt: float = 0.6, clump: float = 2.2,
		cut: float = 0.0, leaf: float = 0.26) -> ShaderMaterial:
	var m := foliage_material(color, sway)
	m.set_shader_parameter("cutout", cut)
	m.set_shader_parameter("leaf_scale", leaf)
	m.set_shader_parameter("crown_center", center)
	m.set_shader_parameter("round_normals", round_amt)
	m.set_shader_parameter("clump_scale", clump)
	return m


## Roofs, tents and tower tops: solid but see-through around the player.
static func fade_material(color: Color, noise_scale: float = 1.5, roughness: float = 0.85) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SOLID_FADE_SHADER % FADE_FUNCS
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("noise", _noise(0.06, 41))
	m.set_shader_parameter("noise_scale", noise_scale)
	m.set_shader_parameter("roughness", roughness)
	fade_materials.append(m)
	return m


## Shingled roof (fades around the player like fade_material).
static func roof_material(color: Color) -> ShaderMaterial:
	var m := fade_material(color, 2.5, 0.9)
	m.set_shader_parameter("rows", 3.2)
	return m


## Camera position for distance-based effects (leaf cut-outs).
static func set_view(pos: Vector3) -> void:
	for m in fade_materials:
		if is_instance_valid(m):
			m.set_shader_parameter("view_pos", pos)


static func set_fade(center: Vector3, r_in: float, r_out: float) -> void:
	for m in fade_materials:
		if is_instance_valid(m):
			m.set_shader_parameter("fade_center", center)
			m.set_shader_parameter("fade_in", r_in)
			m.set_shader_parameter("fade_out", r_out)


# ------------------------------------------------------------------ grass

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 tip : source_color = vec3(0.3, 0.47, 0.1);
uniform vec3 dry_tip : source_color = vec3(0.6, 0.53, 0.24);
uniform vec3 root : source_color = vec3(0.08, 0.16, 0.035);
varying float hgt;
varying float dry;
varying vec3 icol;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hgt = clamp(VERTEX.y / 0.5, 0.0, 1.0);
	float gust = 0.6 + 0.4 * sin(TIME * 0.6 + w.x * 0.05 + w.z * 0.03);
	float s = (sin(TIME * 1.8 + w.x * 0.4 + w.z * 0.3) * 0.07 + sin(TIME * 4.1 + w.x * 1.3) * 0.015) * gust;
	VERTEX.x += s * hgt * hgt;
	VERTEX.z += s * 0.5 * hgt * hgt;
	// patches of dry, straw-coloured grass
	vec2 q = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	dry = smoothstep(0.2, 0.9, 0.5 + 0.35 * sin(q.x * 0.071 + 1.3) * sin(q.y * 0.057 - 0.4) + 0.25 * sin(q.x * 0.21 + q.y * 0.17));
	icol = COLOR.rgb;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec3 t = mix(tip, dry_tip, dry * 0.7);
	ALBEDO = mix(root, t, smoothstep(0.0, 0.85, hgt)) * icol;
	ROUGHNESS = 0.7;
	SPECULAR = 0.35;
	BACKLIGHT = vec3(0.36, 0.44, 0.1) * hgt;
	AO = mix(0.72, 1.0, hgt);
	AO_LIGHT_AFFECT = 0.6;
}
"""


static func grass_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## One tuft: a clump of thin, curved, tapered blades of mixed height.
static func grass_tuft_mesh(seed_value: int = 5) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.2
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face)) * rng.randf_range(0.016, 0.03)
		var h := rng.randf_range(0.16, 0.46)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.04, 0.22) * h * 2.0
		var mid := base + lean * 0.3 + Vector3(0, h * 0.55, 0)
		var tip := base + lean + Vector3(0, h, 0)
		var shade := rng.randf_range(0.78, 1.15)
		st.set_color(Color(shade, shade, shade * rng.randf_range(0.9, 1.05)))
		st.set_normal(Vector3.UP)
		for v in [base - side, base + side, mid + side * 0.7, base - side, mid + side * 0.7, mid - side * 0.7,
				mid - side * 0.7, mid + side * 0.7, tip]:
			st.add_vertex(v)
	return st.commit()


## Fern: a rosette of arching, tapered fronds (uses the grass material).
static func fern_mesh(seed_value: int = 21) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 8:
		var a := TAU * i / 8.0 + rng.randf_range(-0.25, 0.25)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-sin(a), 0, cos(a))
		var ln := rng.randf_range(0.38, 0.6)
		var arch := rng.randf_range(0.22, 0.36)
		var shade := rng.randf_range(0.6, 0.9)
		st.set_color(Color(shade * 0.75, shade, shade * 0.6))
		st.set_normal(Vector3.UP)
		var prev_c := Vector3.ZERO
		var prev_w := 0.0
		for k in range(1, 6):
			var t := k / 5.0
			var c := dir * ln * t + Vector3.UP * arch * sin(t * PI * 0.85)
			var w := 0.085 * sin(t * PI) + 0.004
			for v in [prev_c - side * prev_w, prev_c + side * prev_w, c + side * w,
					prev_c - side * prev_w, c + side * w, c - side * w]:
				st.add_vertex(v)
			prev_c = c
			prev_w = w
	return st.commit()


## Wildflower: thin stem with a small crossed blossom. Vertex colour marks
## stem (dark) vs petals (white) so the instance colour tints the blossom.
static func flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var h := 0.3
	st.set_color(Color(0.16, 0.3, 0.08))
	for v in [Vector3(-0.006, 0, 0), Vector3(0.006, 0, 0), Vector3(0.006, h, 0), Vector3(-0.006, 0, 0), Vector3(0.006, h, 0), Vector3(-0.006, h, 0)]:
		st.add_vertex(v)
	st.set_color(Color(1, 1, 1))
	var r := 0.032
	var top := Vector3(0, h + 0.012, 0)
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		for v in [top, Vector3(cos(a0) * r, h, sin(a0) * r), Vector3(cos(a1) * r, h, sin(a1) * r)]:
			st.add_vertex(v)
	return st.commit()


static func flower_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	m.backlight_enabled = true
	m.backlight = Color(0.3, 0.3, 0.25)
	return m


# ------------------------------------------------------------------ trees

## Adds a triangle whose front face (Godot: clockwise) faces `out`.
## `ea/eb/ec` = edge factor per vertex (0 trunk side .. 1 branch tip), stored in UV.x.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, ca: Color, cb: Color, cc: Color,
		ea: float = 0.5, eb: float = 0.5, ec: float = 0.5) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(out) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
		var te := eb
		eb = ec
		ec = te
		n = -n
	n = -n.normalized()
	st.set_normal(n)
	st.set_color(ca)
	st.set_uv(Vector2(ea, 0.0))
	st.add_vertex(a)
	st.set_color(cb)
	st.set_uv(Vector2(eb, 0.0))
	st.add_vertex(b)
	st.set_color(cc)
	st.set_uv(Vector2(ec, 0.0))
	st.add_vertex(c)


## Pine crown, unit height (0..1): eight whorls of drooping, ragged branch
## skirts with a darker hollow underside. Vertex alpha carries occlusion.
static func pine_crown_mesh(seed_value: int = 3) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := 12
	var seg := 16
	for t in tiers:
		var f := float(t) / float(tiers - 1)
		var base_y := lerpf(0.17, 0.88, f)
		var height := lerpf(0.2, 0.12, f)
		var rad := lerpf(0.44, 0.06, pow(f, 0.85)) * rng.randf_range(0.86, 1.1)
		var apex := Vector3(rng.randf_range(-0.012, 0.012), base_y + height, rng.randf_range(-0.012, 0.012))
		var under := Vector3(0, base_y + height * 0.4, 0)
		var rot := rng.randf() * TAU
		var ring: Array = []
		for i in seg:
			var a := rot + TAU * i / seg
			# alternate long branch tips and short gaps for a ragged silhouette
			var rr := rad * (rng.randf_range(0.95, 1.18) if i % 2 == 0 else rng.randf_range(0.66, 0.84))
			var droop := rr * rng.randf_range(0.1, 0.28)
			ring.append(Vector3(cos(a) * rr, base_y - droop, sin(a) * rr))
		var occ := lerpf(0.55, 1.0, f)   # lower whorls sit in the shade of the upper ones
		var c_apex := Color(1.0, 1.0, 1.0, occ * 0.8)
		var c_tip := Color(1.05, 1.05, 0.95, occ)
		var c_under := Color(0.55, 0.55, 0.55, occ * 0.35)
		for i in seg:
			var p0: Vector3 = ring[i]
			var p1: Vector3 = ring[(i + 1) % seg]
			var mid := (p0 + p1) * 0.5
			var side := Vector3(mid.x, 0.0, mid.z).normalized()
			_tri(st, p0, p1, apex, side + Vector3.UP * 0.6, c_tip, c_tip, c_apex, 1.0, 1.0, 0.0)
			_tri(st, p0, p1, under, side - Vector3.UP * 0.8, c_tip, c_tip, c_under, 1.0, 1.0, 0.25)
	return st.commit()


## Appends `src` transformed by `xf`, pushing each vertex away from `center`
## by 3D noise for a lumpy, leafy outline. Shared positions move together,
## so seams stay closed. Vertex alpha = occlusion (dark low / inside).
static func _lumpy(st: SurfaceTool, src: PrimitiveMesh, xf: Transform3D, center: Vector3, amount: float, noise: FastNoiseLite, shade_low: float) -> void:
	var arr := src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var moved := PackedVector3Array()
	var cols := PackedColorArray()
	moved.resize(verts.size())
	cols.resize(verts.size())
	for i in verts.size():
		var v: Vector3 = xf * verts[i]
		var dir := v - center
		var l := maxf(dir.length(), 0.0001)
		dir /= l
		v += dir * noise.get_noise_3dv(v * 9.0) * amount
		moved[i] = v
		var up := clampf((v.y - center.y) / 0.35 * 0.5 + 0.5, 0.0, 1.0)
		cols[i] = Color(1, 1, 1, lerpf(shade_low, 1.0, up))
	for k in range(0, idx.size(), 3):
		var a := moved[idx[k]]
		var b := moved[idx[k + 1]]
		var c := moved[idx[k + 2]]
		_tri(st, a, b, c, (a + b + c) / 3.0 - center, cols[idx[k]], cols[idx[k + 1]], cols[idx[k + 2]])


static func _leaf_noise(seed_value: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = 0.35
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 3
	return n


## Broadleaf crown: a lumpy cluster of leafy masses around y 0.5..1.
static func broad_crown_mesh(seed_value: int = 4) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := _leaf_noise(seed_value)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.72, 0)
	var blobs := [[Vector3(0, 0.72, 0), 0.3], [Vector3(0.17, 0.63, 0.06), 0.22], [Vector3(-0.16, 0.66, -0.07), 0.23],
			[Vector3(0.04, 0.86, -0.12), 0.2], [Vector3(-0.06, 0.6, 0.18), 0.2], [Vector3(0.1, 0.84, 0.13), 0.18]]
	for i in 8:
		var a := rng.randf() * TAU
		var e := rng.randf_range(-0.3, 0.8)
		var d := Vector3(cos(a) * cos(e), sin(e) * 0.7, sin(a) * cos(e)) * rng.randf_range(0.2, 0.3)
		blobs.append([center + d, rng.randf_range(0.11, 0.16)])
	for b in blobs:
		var s := SphereMesh.new()
		s.radius = b[1]
		s.height = float(b[1]) * 1.7
		s.radial_segments = 10
		s.rings = 6
		_lumpy(st, s, Transform3D(Basis.IDENTITY, b[0]), center, 0.09, noise, 0.4)
	return st.commit()


## Rock: a noise-displaced, flat-shaded sphere with a flat buried base.
static func rock_mesh(seed_value: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	noise.fractal_octaves = 3
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 14
	s.rings = 8
	var arr := s.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var moved := PackedVector3Array()
	moved.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		v *= 1.0 + noise.get_noise_3dv(v * 2.0) * 0.35 + noise.get_noise_3dv(v * 7.0) * 0.08
		v.y = maxf(v.y, -0.12)
		moved[i] = v
	for k in range(0, idx.size(), 3):
		var a := moved[idx[k]]
		var b := moved[idx[k + 1]]
		var c := moved[idx[k + 2]]
		_tri(st, a, b, c, (a + b + c) / 3.0, Color.WHITE, Color.WHITE, Color.WHITE)
	return st.commit()


const ROCK_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 stone : source_color = vec3(0.42, 0.42, 0.39);
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 an = abs(wnrm);
	vec2 uv = an.y > 0.6 ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	float n = texture(noise, uv * 0.45).r;
	float n2 = texture(noise, uv * 2.3 + 0.4).r;
	float n3 = texture(noise, uv * 7.0).r;
	vec3 rock = stone * mix(0.65, 1.15, n) * (0.82 + 0.3 * n3);
	rock = mix(rock, rock * vec3(0.85, 0.8, 0.7), smoothstep(0.55, 0.8, n2) * 0.5);
	rock = mix(rock, vec3(0.75, 0.75, 0.66), step(0.86, n3) * 0.35);
	float moss = smoothstep(0.35, 0.8, wnrm.y + (n2 - 0.5) * 0.7);
	moss *= 1.0 - smoothstep(0.9, 1.6, wpos.y) * 0.6;
	vec3 moss_col = mix(vec3(0.07, 0.12, 0.035), vec3(0.17, 0.22, 0.07), n3);
	ALBEDO = mix(rock, moss_col, moss * 0.85);
	ROUGHNESS = mix(0.78, 0.97, moss);
	AO = smoothstep(-0.05, 0.35, wpos.y) * 0.5 + 0.5;
	AO_LIGHT_AFFECT = 0.5;
	NORMAL_MAP = texture(nrm, uv * 0.9).rgb;
	NORMAL_MAP_DEPTH = 1.2;
}
"""


static func rock_material(color: Color = Color(0.42, 0.42, 0.39)) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = ROCK_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise", _noise(0.05, 57))
	m.set_shader_parameter("nrm", M.normal_tex(0.09, 13, 8.0))
	m.set_shader_parameter("stone", color)
	return m


static func trunk_mesh() -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.45
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 7
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	return c


static func bush_mesh(seed_value: int = 9) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := _leaf_noise(seed_value)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0.35, 0)
	for i in 7:
		var s := SphereMesh.new()
		s.radius = rng.randf_range(0.26, 0.46)
		s.height = s.radius * 1.5
		s.radial_segments = 9
		s.rings = 5
		var off := Vector3(rng.randf_range(-0.4, 0.4), 0.28 + rng.randf() * 0.2, rng.randf_range(-0.4, 0.4))
		_lumpy(st, s, Transform3D(Basis.IDENTITY, off), center, 0.12, noise, 0.3)
	return st.commit()


# ------------------------------------------------------------------ building materials

## Shared: world-space UVs on the dominant face (u across, v up; top faces use xz).
const FACE_UV := """
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
vec2 face_uv() {
	vec3 an = abs(wn);
	return an.y > 0.6 ? wp.xz : (an.x > an.z ? vec2(wp.z, wp.y) : vec2(wp.x, wp.y));
}
float hash1(float x) { return fract(sin(x * 91.7) * 43758.5453); }
"""

## Sawn timber: individual boards with their own tone, long grain, knots and dark seams.
const PLANK_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 base_color : source_color = vec3(0.42, 0.32, 0.22);
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float board = 0.19;
%s
void fragment() {
	vec2 uv = face_uv();
	float bi = floor(uv.x / board);
	float bf = fract(uv.x / board);
	float h = hash1(bi);
	float grain = texture(noise, vec2(uv.x * 1.1 + h * 7.0, uv.y * 0.11)).r;
	float knots = texture(noise, uv * 0.55 + h * 3.0).r;
	vec3 col = base_color * (0.7 + 0.45 * h) * (0.72 + 0.56 * grain);
	col = mix(col, col * 0.4, smoothstep(0.76, 0.85, knots) * 0.55);
	col = mix(col, col * vec3(0.8, 0.85, 0.8), smoothstep(0.55, 0.9, texture(noise, uv * 0.07).r) * 0.35);   // grey weathering
	float seam = smoothstep(0.0, 0.04, bf) * smoothstep(0.0, 0.04, 1.0 - bf);
	col *= mix(0.3, 1.0, seam);
	ALBEDO = col;
	ROUGHNESS = 0.86;
	SPECULAR = 0.25;
	AO = mix(0.55, 1.0, seam);
	AO_LIGHT_AFFECT = 0.5;
}
"""

## Cast concrete: formwork panel lines, tie holes, rain streaks and blotchy curing.
const CONCRETE_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 base_color : source_color = vec3(0.5, 0.5, 0.48);
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable;
%s
void fragment() {
	vec2 uv = face_uv();
	bool wall = abs(wn.y) <= 0.6;
	float n = texture(noise, uv * 0.16).r;
	float fine = texture(noise, uv * 1.5).r;
	vec3 col = base_color * (0.78 + 0.34 * n) * (0.9 + 0.2 * fine);
	vec2 pg = uv / vec2(1.25, 0.62);
	vec2 pf = fract(pg);
	float line = min(min(pf.x, 1.0 - pf.x) * 1.25, min(pf.y, 1.0 - pf.y) * 0.62);
	col *= mix(0.68, 1.0, smoothstep(0.0, 0.014, line));
	float tie = length((pf - vec2(0.12, 0.5)) * vec2(1.25, 0.62));
	col *= mix(0.55, 1.0, smoothstep(0.018, 0.03, tie));
	if (wall) {
		float streak = texture(noise, vec2(uv.x * 0.9, uv.y * 0.045)).r;
		col *= 1.0 - smoothstep(0.55, 0.8, streak) * 0.25;
	}
	ALBEDO = col;
	ROUGHNESS = 0.93;
	SPECULAR = 0.2;
}
"""

## HESCO bastion: tan geotextile behind galvanised weld mesh, gravel fill on top.
const HESCO_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 base_color : source_color = vec3(0.52, 0.47, 0.35);
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable;
%s
void fragment() {
	vec2 uv = face_uv();
	float n = texture(noise, uv * 0.45).r;
	float fine = texture(noise, uv * 2.6).r;
	if (wn.y > 0.6) {
		// open top: packed earth and gravel
		vec3 dirt = mix(vec3(0.3, 0.25, 0.18), vec3(0.45, 0.4, 0.31), n) * (0.75 + 0.5 * fine);
		ALBEDO = mix(dirt, vec3(0.55, 0.54, 0.5), step(0.72, fine) * 0.6);
		ROUGHNESS = 0.97;
	} else {
		// bulging, wrinkled fabric
		vec3 col = base_color * (0.74 + 0.4 * n) * (0.92 + 0.16 * fine);
		col *= mix(0.8, 1.05, smoothstep(0.0, 0.5, fract(uv.y / 0.72)));     // sag shadow per course
		vec2 g = fract(uv / 0.076);
		float wx = 1.0 - smoothstep(0.0, 0.085, min(g.x, 1.0 - g.x));
		float wy = 1.0 - smoothstep(0.0, 0.085, min(g.y, 1.0 - g.y));
		float wire = max(wx, wy);
		ALBEDO = mix(col, vec3(0.34, 0.36, 0.36), wire * 0.8);
		METALLIC = wire * 0.7;
		ROUGHNESS = mix(0.95, 0.45, wire);
	}
}
"""


static func _face_material(code: String, color: Color, noise_seed: int) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code % FACE_UV
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("noise", _noise(0.05, noise_seed))
	return m


static func plank_material(color: Color, board: float = 0.19) -> ShaderMaterial:
	var m := _face_material(PLANK_SHADER, color, 61)
	m.set_shader_parameter("board", board)
	return m


static func concrete_material(color: Color) -> ShaderMaterial:
	return _face_material(CONCRETE_SHADER, color, 67)


static func hesco_material(color: Color = Color(0.52, 0.47, 0.35)) -> ShaderMaterial:
	return _face_material(HESCO_SHADER, color, 73)


# ------------------------------------------------------------------ far hills

const FAR_HILLS_SHADER := """
shader_type spatial;
render_mode diffuse_burley, cull_disabled;
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// forest canopy seen from far away: dark conifer green, mottled crowns,
	// a few lighter broadleaf / clearing patches
	float n = texture(noise, wpos.xz * 0.004).r;
	float c = texture(noise, wpos.xz * 0.05 + wpos.y * 0.02).r;
	vec3 col = mix(vec3(0.05, 0.085, 0.045), vec3(0.11, 0.15, 0.07), n);
	col *= 0.7 + 0.5 * c;
	col = mix(col, vec3(0.2, 0.22, 0.12), smoothstep(0.72, 0.85, n) * 0.5);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""


static func far_hills_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = FAR_HILLS_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise", _noise(0.03, 71))
	return m


# ------------------------------------------------------------------ water

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D flow_noise : filter_linear_mipmap, repeat_enable;
void fragment() {
	// UV.y follows river distance, so ripples flow around bends rather than
	// sliding diagonally across every reach in world space.
	vec2 flow = vec2(UV.x * 2.0, UV.y - TIME * 0.12);
	vec3 a = texture(nrm, flow).rgb * 2.0 - 1.0;
	vec3 b = texture(nrm, flow * vec2(2.1, 1.6) + vec2(0.31, -TIME * 0.035)).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(a + b) * 0.5 + 0.5;
	float edge = min(UV.x, 1.0 - UV.x) * 2.0;
	float depth = smoothstep(0.0, 0.75, edge);
	float flecks = texture(flow_noise, flow * vec2(3.0, 2.0)).r;
	float foam = (1.0 - smoothstep(0.025, 0.18, edge)) * smoothstep(0.52, 0.7, flecks);
	vec3 shallow = vec3(0.16, 0.25, 0.17);
	vec3 deep = vec3(0.015, 0.09, 0.1);
	ALBEDO = mix(mix(shallow, deep, depth), vec3(0.63, 0.67, 0.58), foam * 0.6);
	ROUGHNESS = mix(0.05, 0.3, foam);
	SPECULAR = 0.8;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(ALBEDO, vec3(0.55, 0.68, 0.78), fres * 0.35);   // sky sheen at grazing angles
	NORMAL_MAP_DEPTH = mix(0.12, 0.3, depth);
	ALPHA = smoothstep(0.0, 0.055, edge) * mix(0.38, 0.88, depth);
}
"""


static func water_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("nrm", M.normal_tex(0.08, 3, 4.0))
	m.set_shader_parameter("flow_noise", _noise(0.045, 91))
	return m


# ------------------------------------------------------------------ sky

const SKY_SHADER := """
shader_type sky;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 top_color : source_color = vec3(0.2, 0.35, 0.6);
uniform vec3 horizon_color : source_color = vec3(0.6, 0.65, 0.7);
uniform vec3 ground_color : source_color = vec3(0.1, 0.12, 0.1);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float night = 0.0;
uniform float sun_vis = 1.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(-0.02, 0.45, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));
	float sd = max(dot(d, sun_dir), 0.0);
	col += sun_color * (smoothstep(0.9992, 0.9996, sd) * 12.0 + pow(sd, 10.0) * 0.45 + pow(sd, 3.0) * 0.12) * sun_vis;
	// Two inexpensive noise layers form soft, drifting cloud banks.
	vec2 cloud_uv = d.xz / max(h + 0.15, 0.15) * 0.10 + vec2(TIME * 0.0006, 0.0);
	float broad = texture(cloud_noise, cloud_uv).r;
	float detail = texture(cloud_noise, cloud_uv * 2.7 + 0.31).r;
	float cloud = smoothstep(0.47, 0.67, broad * 0.75 + detail * 0.25);
	cloud *= smoothstep(0.01, 0.18, h) * (1.0 - night * 0.8);
	vec3 cloud_color = mix(horizon_color * 0.85, vec3(0.93, 0.92, 0.87), smoothstep(0.48, 0.75, broad));
	cloud_color = mix(cloud_color, horizon_color * 0.7, night);
	col = mix(col, cloud_color, cloud * 0.85);
	if (h > 0.0 && night > 0.01) {
		vec3 g = floor(d * 260.0);
		float s = h3(g);
		float star = step(0.9972, s) * smoothstep(0.02, 0.3, h);
		col += vec3(0.9, 0.95, 1.0) * star * night * (0.7 + 0.5 * sin(TIME * 2.0 + s * 90.0)) * 1.6;
		float md = dot(d, moon_dir);
		col += vec3(0.9, 0.93, 1.0) * smoothstep(0.99935, 0.9996, md) * night * 3.5;
		col += vec3(0.25, 0.32, 0.5) * pow(max(md, 0.0), 40.0) * night * 0.35;
	}
	COLOR = col;
}
"""


static func sky_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("cloud_noise", _noise(0.018, 83, 512))
	return m
