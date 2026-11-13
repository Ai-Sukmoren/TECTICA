extends "res://scripts/world/level.gd"
## DEAD END: an abandoned crossroads town, 124 x 124 m, flat. Zombie Survival
## and Deathmatch only (the campaign lives in the forest).
##   centre      police barricade ring at the intersection (zombie stronghold)
##   north-east  gas station canopy + walk-through shop
##   north-west  three houses with backyard fences
##   south-west  diner and parking lot
##   south-east  truck yard: shed, containers, crates
## Roads run north-south (|x| < 5) and east-west (|z| < 5).
## Coordinates: x east, z south (north is -z).

const Nature = preload("res://scripts/world/nature.gd")
const Terrain = preload("res://scripts/world/terrain.gd")

const HALF := 62.0
const ROAD := 5.0
const WALK := 7.0

# interface shared with the forest map (time of day, HUD, AI read these)
var mode := "zombie"
var night := 0.0
var outpost_powered := true
var lamp_lights: Array = []
var fireflies: Array = []
var interact_points: Dictionary = {}
var pvp_spawns: Array = []

## Building footprints (Rect2 in x/z), kept clear of spawns.
var _blocked: Array = []
var _mat_asphalt: Material
var _mat_walk: Material
var _mat_lot: Material
var _mat_line: Material
var _mat_white: Material
var _mat_brick: Material
var _mat_siding: Material
var _mat_roof: Material
var _mat_glass_lit: Material
var _mat_glass_dark: Material
var _mat_fence: Material
var skyline_mat: ShaderMaterial

## Navigation is identical on every load (fixed seed): bake once, reuse.
static var _nav_cache: NavigationMesh


func build() -> void:
	seed(4242)   # same town every time
	Terrain.clear()
	_mat_wall = Nature.plaster_material(Color(0.47, 0.45, 0.41))
	_mat_wall_trim = M.solid(Color(0.18, 0.18, 0.19), 0.8)
	_mat_crate = M.wood("crate", Color(0.46, 0.4, 0.28))
	_mat_crate_frame = M.wood("crate_frame", Color(0.34, 0.29, 0.2))
	_mat_sandbag = M.fabric("sandbag", Color(0.52, 0.47, 0.36), 4.0)
	_mat_concrete = M.concrete("barrier", Color(0.58, 0.57, 0.54), 0.6)
	_mat_metal = M.painted_metal("metal_grey", Color(0.3, 0.32, 0.33))
	_mat_asphalt = Nature.asphalt_material(2.5)
	_mat_walk = Nature.sidewalk_material(Color(0.44, 0.44, 0.42))
	_mat_lot = Nature.ground_material(_lot_mask(), HALF * 2.6)
	_mat_line = M.road_paint("line_yellow", Color(0.8, 0.6, 0.12), 0.84)
	_mat_white = M.road_paint("line_white", Color(0.74, 0.73, 0.68), 0.8)
	_mat_brick = Nature.brick_material(Color(0.5, 0.25, 0.17))
	_mat_siding = Nature.siding_material(Color(0.58, 0.6, 0.52))
	_mat_roof = Nature.roof_material(Color(0.2, 0.18, 0.17))
	Nature.fade_materials = Nature.fade_materials.filter(func(m): return m == _mat_roof)
	_mat_glass_lit = M.emissive("window_lit", Color(1.0, 0.78, 0.45), 1.6)
	_mat_glass_dark = M.solid(Color(0.06, 0.08, 0.1), 0.15, 0.4)
	_mat_fence = M.wood("fence", Color(0.36, 0.3, 0.22))

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)

	_build_ground()
	_build_barricade()
	_build_gas_station()
	_build_houses()
	_build_diner()
	_build_truck_yard()
	_build_street_props()
	_build_lamps()
	_build_weeds()
	_build_boundary()
	_define_mode()
	_bake_navigation()
	seed(Time.get_ticks_usec())


func ground_y(_x: float, _z: float) -> float:
	return 0.0


## Ground mask for the lots between the buildings (see Nature.GROUND_SHADER:
## r = bare dirt, g = trodden, b = mud, a = leaf litter): dead, weedy lawns,
## a worn strip along the kerbs, bare dirt in the truck yard and forecourt.
func _lot_mask() -> ImageTexture:
	var res := 128
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	var size := HALF * 2.6
	for y in res:
		for x in res:
			var wx := (float(x) / res - 0.5) * size
			var wz := (float(y) / res - 0.5) * size
			var n := 0.5 + 0.5 * sin(wx * 0.21 + sin(wz * 0.13) * 2.0) * cos(wz * 0.17 + sin(wx * 0.09) * 1.5)
			var trod := 0.35 + 0.45 * n
			var road := minf(absf(wx), absf(wz))
			var dirt := clampf(1.0 - (road - WALK) / 2.5, 0.0, 1.0) * 0.6
			if wx > 8.0 and wx < 44.0 and wz > 16.0 and wz < 52.0:
				dirt = maxf(dirt, 0.9)   # truck yard
			elif wx > 8.0 and wx < 30.0 and wz < -8.0 and wz > -28.0:
				dirt = maxf(dirt, 0.7)   # gas station forecourt
			img.set_pixel(x, y, Color(dirt, trod, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


## Weeds through the dead lawns and the odd tuft in the sidewalk joints
## (no collision, fades out at distance).
func _build_weeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var tuft := Nature.grass_tuft_mesh(7)
	var mat := Nature.grass_material()
	mat.set_shader_parameter("tip", Color(0.3, 0.38, 0.14))
	mat.set_shader_parameter("dry_tip", Color(0.58, 0.5, 0.24))
	var chunks := {}
	for i in 26000:
		var x := rng.randf_range(-HALF + 1.0, HALF - 1.0)
		var z := rng.randf_range(-HALF + 1.0, HALF - 1.0)
		var road := minf(absf(x), absf(z))
		if road < WALK - 0.3:
			if road < ROAD + 0.15 or rng.randf() > 0.12:
				continue
		elif not _free(Vector3(x, 0, z), -0.8):
			continue
		var ck := Vector2i(int(floor(x / 16.0)), int(floor(z / 16.0)))
		if not chunks.has(ck):
			chunks[ck] = []
		var s := rng.randf_range(0.6, 1.3)
		chunks[ck].append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.2), s)), Vector3(x, 0.0, z)),
				Color(rng.randf_range(0.8, 1.05), rng.randf_range(0.8, 1.0), rng.randf_range(0.7, 0.95))])
	for ck in chunks:
		var items: Array = chunks[ck]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tuft
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_color(i, items[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 48.0
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)


# ================================================================ ground

func _build_ground() -> void:
	var g := _body(Vector3.ZERO)
	_box_shape(g, Vector3(HALF * 2.6, 1, HALF * 2.6), Vector3(0, -0.5, 0))
	_mesh(g, ML.plane(Vector2(HALF * 2.6, HALF * 2.6)), _mat_lot, Vector3.ZERO)
	# roads, sidewalks, markings (no collision)
	_floor_patch(Vector3(0, 0.004, 0), Vector2(WALK * 2, HALF * 2), _mat_walk)
	_floor_patch(Vector3(0, 0.005, 0), Vector2(HALF * 2, WALK * 2), _mat_walk)
	_floor_patch(Vector3(0, 0.008, 0), Vector2(ROAD * 2, HALF * 2), _mat_asphalt)
	_floor_patch(Vector3(0, 0.009, 0), Vector2(HALF * 2, ROAD * 2), _mat_asphalt)
	var d := 9.0
	while d < HALF - 2.0:
		for s in [-1.0, 1.0]:
			_floor_patch(Vector3(0, 0.012, s * d), Vector2(0.18, 2.2), _mat_line)
			_floor_patch(Vector3(s * d, 0.012, 0), Vector2(2.2, 0.18), _mat_line)
		d += 4.5
	# crosswalks at the intersection
	for i in 7:
		var o := -3.6 + i * 1.2
		_floor_patch(Vector3(o, 0.013, -6.2), Vector2(0.6, 2.0), _mat_white)
		_floor_patch(Vector3(o, 0.013, 6.2), Vector2(0.6, 2.0), _mat_white)
		_floor_patch(Vector3(-6.2, 0.013, o), Vector2(2.0, 0.6), _mat_white)
		_floor_patch(Vector3(6.2, 0.013, o), Vector2(2.0, 0.6), _mat_white)
	# oil stains, debris patches
	for i in 26:
		var p := Vector3(randf_range(-HALF + 4, HALF - 4), 0.014, randf_range(-4.5, 4.5))
		if i % 2 == 1:
			p = Vector3(p.z, 0.014, p.x)
		var s := _floor_patch(p, Vector2.ONE * randf_range(0.8, 2.6), M.blot("oil", Color(0.02, 0.02, 0.02, 0.5)))
		s.rotation.y = randf() * TAU


# ================================================================ buildings

## Axis-aligned shell: four walls with door gaps and lintels, glowing or dark
## windows, a fading roof and an interior light. doors: side -> [offset, width]
## with side in "n" (-z), "s" (+z), "e" (+x), "w" (-x).
func _building(c: Vector3, w: float, d: float, h: float, mat: Material, doors: Dictionary,
		sign_text: String = "", lit: float = 0.5) -> void:
	_blocked.append(Rect2(c.x - w * 0.5 - 1.5, c.z - d * 0.5 - 1.5, w + 3.0, d + 3.0))
	var t := 0.3
	for side in ["n", "s", "e", "w"]:
		var along_x: bool = side in ["n", "s"]
		var length: float = w if along_x else d
		var sgn := -1.0 if side in ["n", "w"] else 1.0
		var gaps: Array = []
		if doors.has(side):
			var dd: Array = doors[side]
			gaps.append([float(dd[0]) - float(dd[1]) * 0.5, float(dd[0]) + float(dd[1]) * 0.5])
		var segs := _segments(-length * 0.5, length * 0.5, gaps)
		for sgm in segs:
			var l: float = sgm[1] - sgm[0]
			if l < 0.05:
				continue
			var mid: float = (sgm[0] + sgm[1]) * 0.5
			var pos := c + (Vector3(mid, 0, sgn * d * 0.5) if along_x else Vector3(sgn * w * 0.5, 0, mid))
			var size := Vector3(l, h, t) if along_x else Vector3(t, h, l)
			var b := solid_box(pos, size, mat)
			_mesh(b, ML.box(size + Vector3(0.06, -h + 0.22, 0.06)), _mat_wall_trim, Vector3(0, 0.11, 0))
			# windows on the outer face, one every ~3 m
			var nwin := int(l / 3.0)
			for i in nwin:
				var wo: float = -l * 0.5 + (i + 0.5) * l / nwin
				var glow := randf() < lit
				var pane := Vector3(1.2, 1.0, 0.04) if along_x else Vector3(0.04, 1.0, 1.2)
				var off := Vector3(wo, 1.55, sgn * (t * 0.5 + 0.02)) if along_x else Vector3(sgn * (t * 0.5 + 0.02), 1.55, wo)
				var nrm := Vector3(0, 0, sgn) if along_x else Vector3(sgn, 0, 0)
				_mesh(b, ML.box(Vector3(1.34, 1.14, 0.05) if along_x else Vector3(0.05, 1.14, 1.34)), _mat_wall_trim, off - nrm * 0.03)
				_mesh(b, ML.box(pane), _mat_glass_lit if glow else _mat_glass_dark, off).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_mesh(b, ML.box(Vector3(1.42, 0.06, 0.14) if along_x else Vector3(0.14, 0.06, 1.42)), _mat_wall_trim, off + Vector3(0, -0.58, 0) + nrm * 0.04)
		for g in gaps:
			# lintel above the doorway
			var gl: float = g[1] - g[0]
			var gm: float = (g[0] + g[1]) * 0.5
			var lp := c + (Vector3(gm, 2.3, sgn * d * 0.5) if along_x else Vector3(sgn * w * 0.5, 2.3, gm))
			_mesh(self, ML.box(Vector3(gl, h - 2.3, t) if along_x else Vector3(t, h - 2.3, gl)), mat, lp + Vector3(0, (h - 2.3) * 0.5, 0))
	# floor + fading roof
	_floor_patch(c + Vector3(0, 0.02, 0), Vector2(w - t, d - t), M.floor_grid("floor_" + str(int(c.x)) + "_" + str(int(c.z)),
			Color(0.24, 0.2, 0.16), Color(0.3, 0.26, 0.2), 0.25))
	var roof := _mesh(self, ML.box(Vector3(w + 0.5, 0.2, d + 0.5)), _mat_roof, c + Vector3(0, h + 0.1, 0))
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mesh(self, ML.box(Vector3(w + 0.7, 0.3, d + 0.7)), _mat_wall_trim, c + Vector3(0, h - 0.05, 0))
	# interior light
	var l3 := OmniLight3D.new()
	l3.position = c + Vector3(0, h - 0.5, 0)
	l3.light_color = Color(1.0, 0.82, 0.6)
	l3.omni_range = maxf(w, d) * 0.7
	l3.omni_attenuation = 1.3
	l3.light_volumetric_fog_energy = 0.3
	add_child(l3)
	lamp_lights.append({"light": l3, "base": 1.5, "group": "interior", "flicker": randf() < 0.3})
	lights.append({"light": l3, "shadow": maxf(w, d) > 11.0})
	if sign_text != "":
		var face := c + Vector3(0, h + 0.75, d * 0.5 + 0.3)
		_mesh(self, ML.box(Vector3(minf(w * 0.7, 9.0), 1.0, 0.15)), M.solid(Color(0.08, 0.08, 0.09), 0.5), face)
		var label := Label3D.new()
		label.text = sign_text
		label.font_size = 96
		label.pixel_size = 0.006
		label.modulate = Color(1.0, 0.35, 0.25)
		label.outline_size = 0
		label.position = face + Vector3(0, 0, 0.09)
		add_child(label)


func _furniture(pos: Vector3, size: Vector3, color: Color, rot: float = 0.0, cover: bool = true) -> void:
	solid_box(pos, size, M.solid(color, 0.8), rot, cover and size.y <= 1.25, "wood").finalize()


func _fence(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var l := dir.length()
	var rot := atan2(dir.x, dir.z) + PI * 0.5
	var body := solid_box((a + b) * 0.5, Vector3(l, 1.15, 0.12), _mat_fence, rot, true, "wood")
	var posts := int(l / 1.6)
	for i in posts + 1:
		_mesh(body, ML.box(Vector3(0.14, 1.3, 0.14)), _mat_wall_trim, Vector3(-l * 0.5 + i * l / maxi(posts, 1), 0.65, 0))
	body.finalize()


func _build_gas_station() -> void:
	var cp := Vector3(18, 0, -16)
	_blocked.append(Rect2(cp.x - 8, cp.z - 6, 16, 12))
	var steel := M.painted_metal("canopy", Color(0.75, 0.75, 0.72))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			solid_box(cp + Vector3(sx * 5.0, 0, sz * 3.2), Vector3(0.4, 4.4, 0.4), steel)
	var canopy := _mesh(self, ML.box(Vector3(13.0, 0.6, 9.0)), steel, cp + Vector3(0, 4.7, 0))
	canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mesh(self, ML.box(Vector3(13.1, 0.3, 9.1)), M.solid(Color(0.75, 0.12, 0.1), 0.5), cp + Vector3(0, 4.5, 0))
	for sx in [-2.4, 2.4]:
		var pump := solid_box(cp + Vector3(sx, 0, 0), Vector3(0.9, 1.7, 0.6), M.painted_metal("pump", Color(0.7, 0.15, 0.12)), 0.0, false, "metal")
		_mesh(pump, ML.box(Vector3(0.5, 0.35, 0.05)), M.emissive("pump_screen", Color(0.3, 0.9, 0.6), 1.2), Vector3(0, 1.3, 0.33))
		_floor_patch(cp + Vector3(sx, 0.02, 0), Vector2(1.6, 4.0), _mat_walk)
		pump.finalize()
	for i in 3:
		var l := OmniLight3D.new()
		l.position = cp + Vector3(-4.0 + i * 4.0, 4.2, 0)
		l.light_color = Color(0.85, 0.92, 1.0)
		l.omni_range = 9.0
		l.light_volumetric_fog_energy = 1.0
		add_child(l)
		lamp_lights.append({"light": l, "base": 2.0, "group": "street", "flicker": i == 2})
		lights.append({"light": l, "shadow": i == 1})
	# shop: door faces the pumps (west) and the street (south)
	_building(Vector3(32, 0, -22), 14.0, 10.0, 3.6, _mat_brick, {"w": [2.0, 2.2], "s": [-3.0, 2.0]}, "GAS & GO", 0.7)
	rack(Vector3(30, 0, -24.5), 0.0, 3.6)
	rack(Vector3(34, 0, -21), 0.0, 3.6)
	_furniture(Vector3(27, 0, -19), Vector3(2.8, 1.0, 0.8), Color(0.3, 0.25, 0.2))
	barrel(Vector3(24, 0, -27), Color(0.75, 0.15, 0.1))
	barrel(Vector3(24.8, 0, -27.6), Color(0.75, 0.15, 0.1))
	_build_house(Vector3(22, 0, -44), 10.0, 9.0, {"s": [0.0, 1.8]})


func _build_house(c: Vector3, w: float, d: float, doors: Dictionary) -> void:
	_building(c, w, d, 3.2, _mat_siding, doors, "", 0.45)
	_furniture(c + Vector3(-w * 0.25, 0, -d * 0.2), Vector3(2.2, 0.85, 0.9), Color(0.3, 0.22, 0.2))   # sofa
	_furniture(c + Vector3(w * 0.22, 0, d * 0.1), Vector3(1.4, 0.78, 1.0), Color(0.42, 0.32, 0.22))   # table
	_furniture(c + Vector3(w * 0.28, 0, -d * 0.28), Vector3(2.0, 0.6, 1.5), Color(0.5, 0.45, 0.42))   # bed


func _build_houses() -> void:
	_build_house(Vector3(-19, 0, -18), 10.0, 9.0, {"s": [1.5, 1.8], "e": [0.0, 1.8]})
	_build_house(Vector3(-35, 0, -18), 10.0, 9.0, {"s": [0.0, 1.8]})
	_build_house(Vector3(-21, 0, -40), 12.0, 10.0, {"s": [-2.0, 1.8], "n": [2.0, 1.8]})
	# backyard fences
	_fence(Vector3(-14, 0, -27), Vector3(-26, 0, -27))
	_fence(Vector3(-30, 0, -27), Vector3(-42, 0, -27))
	_fence(Vector3(-42, 0, -27), Vector3(-42, 0, -46))
	_fence(Vector3(-30, 0, -10), Vector3(-30, 0, -14))
	crate(Vector3(-27, 0, -31), Vector3(1.2, 1.0, 1.2), 0.4)
	barrel(Vector3(-13.5, 0, -30), Color(0.25, 0.3, 0.42))
	vehicle(Vector3(-11, 0, -33), PI * 0.5)


func _build_diner() -> void:
	var c := Vector3(-22, 0, 20)
	_building(c, 16.0, 10.0, 3.8, _mat_brick, {"n": [-3.0, 2.2], "e": [0.0, 2.0]}, "", 0.8)
	var sign_pos := c + Vector3(0, 4.5, -5.3)
	_mesh(self, ML.box(Vector3(8.5, 1.1, 0.15)), M.solid(Color(0.08, 0.08, 0.09), 0.5), sign_pos)
	var label := Label3D.new()
	label.text = "ROUTE 9 DINER"
	label.font_size = 96
	label.pixel_size = 0.0058
	label.modulate = Color(0.35, 0.95, 1.0)
	label.position = sign_pos + Vector3(0, 0, -0.09)
	label.rotation.y = PI
	add_child(label)
	var neon := OmniLight3D.new()
	neon.position = sign_pos + Vector3(0, 0, -1.0)
	neon.light_color = Color(0.35, 0.9, 1.0)
	neon.omni_range = 8.0
	add_child(neon)
	lamp_lights.append({"light": neon, "base": 1.8, "group": "street", "flicker": true})
	# counter + booths
	_furniture(c + Vector3(3.0, 0, 2.5), Vector3(6.0, 1.05, 0.8), Color(0.55, 0.15, 0.12))
	for i in 3:
		var bx := -6.0 + i * 3.0
		_furniture(c + Vector3(bx, 0, -2.6), Vector3(1.6, 0.76, 0.9), Color(0.85, 0.82, 0.75))
		_furniture(c + Vector3(bx, 0, -3.8), Vector3(1.6, 1.0, 0.5), Color(0.6, 0.12, 0.1))
	# parking lot
	_floor_patch(Vector3(-24, 0.006, 36), Vector2(30, 12), _mat_asphalt)
	for i in 7:
		_floor_patch(Vector3(-37 + i * 4.3, 0.012, 36), Vector2(0.12, 5.0), _mat_white)
	_car(Vector3(-33, 0, 36), 0.05, Color(0.2, 0.25, 0.45))
	_car(Vector3(-24.5, 0, 36.4), -0.08, Color(0.6, 0.58, 0.55))
	_car(Vector3(-15.8, 0, 35.6), 0.12, Color(0.5, 0.1, 0.08))
	sandbags(Vector3(-11, 0, 28), 3.0, PI * 0.5)


func _build_truck_yard() -> void:
	_building(Vector3(34, 0, 30), 16.0, 12.0, 5.0, _mat_wall, {"w": [0.0, 4.0], "n": [4.0, 2.0]}, "", 0.3)
	rack(Vector3(36, 0, 26), 0.0, 4.0)
	rack(Vector3(36, 0, 34), 0.0, 4.0)
	crate_stack(Vector3(30, 0, 33))
	crate(Vector3(39, 0, 30), Vector3(1.2, 1.0, 1.2), 0.2)
	container(Vector3(16, 0, 22), 0.0, Color(0.5, 0.22, 0.14))
	container(Vector3(22, 0, 42), PI * 0.5, Color(0.2, 0.3, 0.4))
	container(Vector3(14, 0, 48), PI * 0.5, Color(0.28, 0.36, 0.25))
	_blocked.append(Rect2(12, 17, 8, 12))
	_blocked.append(Rect2(17, 38, 10, 8))
	_blocked.append(Rect2(9, 44, 10, 8))
	vehicle(Vector3(22, 0, 30), 0.1)
	crate_stack(Vector3(12, 0, 34), 0.3)
	crate(Vector3(26, 0, 22), Vector3(1.2, 1.0, 1.2), 0.0)
	crate(Vector3(27.3, 0, 22.4), Vector3(1.0, 0.8, 1.0), 0.5)
	barrel(Vector3(18, 0, 36), Color(0.75, 0.15, 0.1))
	barrel(Vector3(18.7, 0, 36.5), Color(0.25, 0.3, 0.42))
	_fence(Vector3(10, 0, 56), Vector3(44, 0, 56))


## Police barricade ring around the intersection: the zombie stronghold.
func _build_barricade() -> void:
	var r := 8.5
	for i in 12:
		var a := TAU * i / 12.0
		if i % 3 == 0:
			continue   # gaps on the roads in and out
		var p := Vector3(cos(a), 0, sin(a)) * r
		if i % 3 == 1:
			barrier(p, -a + PI * 0.5)
		else:
			sandbags(p, 2.6, -a + PI * 0.5)
	_police_car(Vector3(-3.2, 0, -2.6), 0.6)
	_police_car(Vector3(3.4, 0, 2.2), -2.4)
	crate(Vector3(1.8, 0, -2.2), Vector3(1.2, 1.0, 1.2), 0.3)
	ammo_crates.append(Vector3(-2.0, 0, 2.6))


func _car(p: Vector3, rot: float, paint_col: Color, burning: bool = false) -> void:
	var b := _body(p, rot, "metal")
	_box_shape(b, Vector3(1.9, 1.45, 4.3), Vector3(0, 0.72, 0))
	var paint: Material = M.matte("car_burnt", Color(0.07, 0.065, 0.06), 0.95) if burning else M.car_paint("car_" + paint_col.to_html(), paint_col)
	var trim := M.matte("car_trim", Color(0.05, 0.05, 0.055), 0.6)
	var chrome := M.solid(Color(0.6, 0.62, 0.64), 0.25, 0.9)
	var tire := M.matte("tire", Color(0.05, 0.05, 0.05), 0.92)
	var glass: Material = M.solid(Color(0.12, 0.11, 0.1), 0.9) if burning else _mat_glass_dark
	# body: sills, bonnet, cabin, boot (rounded boxes read as pressed panels)
	_mesh(b, ML.rbox(Vector3(1.85, 0.5, 4.2)), paint, Vector3(0, 0.6, 0))
	_mesh(b, ML.rbox(Vector3(1.8, 0.26, 1.35)), paint, Vector3(0, 0.95, -1.4), Vector3(0.06, 0, 0))
	_mesh(b, ML.rbox(Vector3(1.62, 0.56, 2.05)), paint, Vector3(0, 1.2, 0.22))
	_mesh(b, ML.rbox(Vector3(1.8, 0.28, 1.0)), paint, Vector3(0, 0.95, 1.7))
	# glazing: windscreen, rear window, side glass
	_mesh(b, ML.box(Vector3(1.5, 0.46, 0.05)), glass, Vector3(0, 1.22, -0.84), Vector3(-0.5, 0, 0))
	_mesh(b, ML.box(Vector3(1.5, 0.42, 0.05)), glass, Vector3(0, 1.22, 1.28), Vector3(0.42, 0, 0))
	_mesh(b, ML.box(Vector3(1.66, 0.34, 1.5)), glass, Vector3(0, 1.26, 0.2))
	var lamp: Material = M.emissive("headlamp_dead", Color(0.3, 0.3, 0.28), 0.0) if burning else M.emissive("headlamp", Color(0.9, 0.9, 0.8), 0.15)
	for sx in [-1.0, 1.0]:
		_mesh(b, ML.box(Vector3(0.04, 0.5, 0.012)), trim, Vector3(sx * 0.93, 0.62, -0.25))   # door seams
		_mesh(b, ML.box(Vector3(0.04, 0.5, 0.012)), trim, Vector3(sx * 0.93, 0.62, 0.85))
		_mesh(b, ML.rbox(Vector3(0.1, 0.08, 0.16)), trim, Vector3(sx * 0.98, 1.12, -0.7))      # mirrors
		_mesh(b, ML.box(Vector3(0.36, 0.14, 0.04)), lamp, Vector3(sx * 0.62, 0.82, -2.12))
		_mesh(b, ML.box(Vector3(0.4, 0.12, 0.04)), M.emissive("tail", Color(0.6, 0.05, 0.03), 0.6), Vector3(sx * 0.6, 0.82, 2.12))
	# bumpers + grille
	for sz in [-2.15, 2.15]:
		_mesh(b, ML.rbox(Vector3(1.9, 0.2, 0.14)), trim, Vector3(0, 0.46, sz))
	_mesh(b, ML.box(Vector3(0.7, 0.16, 0.03)), trim, Vector3(0, 0.82, -2.12))
	# wheels with alloy rims
	for sz in [-1.35, 1.35]:
		for sx in [-0.86, 0.86]:
			_mesh(b, ML.cylinder(0.34, 0.34, 0.24, 18), tire, Vector3(sx, 0.34, sz), Vector3(0, 0, PI * 0.5))
			_mesh(b, ML.cylinder(0.2, 0.2, 0.26, 12), chrome, Vector3(sx, 0.34, sz), Vector3(0, 0, PI * 0.5))
	_add_cover(p, Vector3(1.9, 1.45, 4.3), rot, b)
	b.finalize()
	if burning:
		_fire(p + Vector3(0, 1.2, 0))


func _police_car(p: Vector3, rot: float) -> void:
	_car(p, rot, Color(0.08, 0.09, 0.12))
	var bar := _mesh(self, ML.box(Vector3(1.0, 0.12, 0.25)), M.solid(Color(0.1, 0.1, 0.1)), p + Vector3(0, 1.55, 0))
	bar.rotation.y = rot
	for side in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.position = p + Basis(Vector3.UP, rot) * Vector3(side * 0.35, 1.75, 0)
		l.light_color = Color(1.0, 0.1, 0.08) if side < 0 else Color(0.1, 0.3, 1.0)
		l.omni_range = 7.0
		add_child(l)
		lamp_lights.append({"light": l, "base": 1.6, "group": "beacon"})


func _fire(p: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var f := CPUParticles3D.new()
	f.amount = 48
	f.lifetime = 0.9
	f.mesh = quad
	f.material_override = mat
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	f.emission_box_extents = Vector3(0.7, 0.1, 1.4)
	f.direction = Vector3.UP
	f.spread = 15.0
	f.initial_velocity_min = 1.2
	f.initial_velocity_max = 2.4
	f.gravity = Vector3(0, 0.6, 0)
	f.scale_amount_min = 0.6
	f.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.75, 0.3, 0.9), Color(1.0, 0.35, 0.08, 0.6), Color(0.2, 0.1, 0.08, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	f.color_ramp = ramp
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	f.position = p
	add_child(f)
	var l := OmniLight3D.new()
	l.position = p + Vector3(0, 0.6, 0)
	l.light_color = Color(1.0, 0.5, 0.2)
	l.omni_range = 10.0
	add_child(l)
	lamp_lights.append({"light": l, "base": 2.6, "group": "fire", "flicker": true})
	lights.append({"light": l, "shadow": true})


func _build_street_props() -> void:
	# abandoned cars across the lanes
	_car(Vector3(2.8, 0, -24), 0.25, Color(0.35, 0.36, 0.32), true)
	_car(Vector3(-2.6, 0, -38), -0.15, Color(0.55, 0.45, 0.2))
	_car(Vector3(2.2, 0, 22), 2.9, Color(0.25, 0.4, 0.3))
	_car(Vector3(-2.4, 0, 40), 0.4, Color(0.6, 0.6, 0.62))
	_car(Vector3(-26, 0, 2.6), PI * 0.5 + 0.2, Color(0.45, 0.12, 0.1))
	_car(Vector3(30, 0, -2.4), PI * 0.5 - 0.3, Color(0.15, 0.2, 0.35))
	_car(Vector3(46, 0, 1.8), PI * 0.5 + 0.1, Color(0.62, 0.6, 0.5))
	_car(Vector3(-44, 0, -2.0), PI * 0.5, Color(0.3, 0.3, 0.3), true)
	# roadblocks where the roads leave town
	for e in [Vector3(0, 0, -HALF + 6), Vector3(0, 0, HALF - 6), Vector3(-HALF + 6, 0, 0), Vector3(HALF - 6, 0, 0)]:
		var along_x := absf(e.x) > 1.0
		var rot := PI * 0.5 if along_x else 0.0
		container(e, rot + PI * 0.5, Color(0.42, 0.18, 0.12))
		for s in [-1.0, 1.0]:
			var off := Vector3(0, 0, s * 4.5) if along_x else Vector3(s * 4.5, 0, 0)
			barrier(e + off, rot)
		_blocked.append(Rect2(e.x - 6, e.z - 6, 12, 12))
	for p in [Vector3(-9, 0, -12), Vector3(9.5, 0, 12), Vector3(-10, 0, 9), Vector3(12, 0, -9)]:
		barrel(p, Color(0.25, 0.3, 0.42))


func _build_lamps() -> void:
	var pole := M.painted_metal("lamp_pole", Color(0.18, 0.19, 0.2))
	var head := M.emissive("street_bulb", Color(1.0, 0.8, 0.5), 3.0)
	var spots: Array = []
	var d := 14.0
	while d < HALF - 6.0:
		for s in [-1.0, 1.0]:
			spots.append([Vector3(6.2 if s > 0 else -6.2, 0, -d * s), s])
			spots.append([Vector3(-d * s, 0, 6.2 if s > 0 else -6.2), s])
		d += 15.0
	var i := 0
	for sp in spots:
		var p: Vector3 = sp[0]
		var b := solid_box(p, Vector3(0.22, 5.2, 0.22), pole)
		var to_road := Vector3(-signf(p.x), 0, 0) if absf(p.x) > absf(p.z) else Vector3(0, 0, -signf(p.z))
		_mesh(b, ML.box(Vector3(0.12, 0.12, 1.6) if absf(to_road.z) > 0 else Vector3(1.6, 0.12, 0.12)), pole, to_road * 0.8 + Vector3(0, 5.15, 0))
		var bulb := _mesh(b, ML.box(Vector3(0.5, 0.1, 0.3)), head, to_road * 1.5 + Vector3(0, 5.05, 0))
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var broken := i % 5 == 3
		var l := OmniLight3D.new()
		l.position = p + to_road * 1.5 + Vector3(0, 4.8, 0)
		l.light_color = Color(1.0, 0.78, 0.48)
		l.omni_range = 13.0
		l.omni_attenuation = 1.1
		l.light_volumetric_fog_energy = 1.4
		add_child(l)
		lamp_lights.append({"light": l, "base": 2.4, "group": "street", "bulb": bulb, "flicker": broken})
		lights.append({"light": l, "shadow": i % 4 == 0})
		i += 1


func _build_boundary() -> void:
	# perimeter wall
	for s in [-1.0, 1.0]:
		solid_box(Vector3(0, 0, s * HALF), Vector3(HALF * 2 + 0.6, 3.6, 0.6), _mat_wall)
		solid_box(Vector3(s * HALF, 0, 0), Vector3(0.6, 3.6, HALF * 2 + 0.6), _mat_wall)
	# dark skyline beyond the wall
	skyline_mat = Nature.skyline_material()
	var dark: Material = skyline_mat
	for k in 44:
		var side := k % 4
		var t := randf_range(-HALF - 20, HALF + 20)
		var dist := HALF + randf_range(10, 28)
		var p := Vector3(t, 0, -dist) if side == 0 else (Vector3(t, 0, dist) if side == 1 else (Vector3(-dist, 0, t) if side == 2 else Vector3(dist, 0, t)))
		var h := randf_range(8, 26)
		var size := Vector3(randf_range(8, 16), h, randf_range(8, 16))
		var mi := _mesh(self, ML.box(size), dark, p + Vector3(0, h * 0.5, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for wi in 3:
			if randf() < 0.6:
				randf()   # keeps the RNG sequence of the old window placement
				randf()
				if side >= 2:
					randf()


# ================================================================ modes

func _free(p: Vector3, margin: float = 0.0) -> bool:
	if absf(p.x) > HALF - 3 or absf(p.z) > HALF - 3:
		return false
	for r in _blocked:
		if (r as Rect2).grow(margin).has_point(Vector2(p.x, p.z)):
			return false
	return true


func _define_mode() -> void:
	enemy_spawns.clear()
	zombie_spawns.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	if mode == "pvp":
		pvp_spawns = [Vector3(0, 0, 3), Vector3(18, 0, -8), Vector3(-19, 0, -11), Vector3(-22, 0, 28),
				Vector3(28, 0, 14), Vector3(-40, 0, 6), Vector3(42, 0, -8), Vector3(4, 0, -48), Vector3(-6, 0, 50)]
		for i in 200:
			if pvp_spawns.size() >= 24:
				break
			var p := Vector3(rng.randf_range(-HALF + 6, HALF - 6), 0, rng.randf_range(-HALF + 6, HALF - 6))
			if _free(p, 0.5):
				pvp_spawns.append(p)
		player_spawn = pvp_spawns[0]
		ammo_crates.append(Vector3(-11, 0, -8))
		ammo_crates.append(Vector3(11, 0, 9))
		return
	# zombie survival: hold the barricade at the crossroads
	player_spawn = Vector3(0, 0, 1.5)
	player_yaw = 0.0
	for i in 400:
		if zombie_spawns.size() >= 70:
			break
		var a := rng.randf() * TAU
		var q := Vector3(cos(a), 0, sin(a)) * rng.randf_range(18.0, 56.0)
		if _free(q, 0.3):
			zombie_spawns.append(q)
	ammo_crates.append(Vector3(10.5, 0, -10.5))


func _bake_navigation() -> void:
	if _nav_cache != null:
		nav_region.navigation_mesh = _nav_cache.duplicate()
		return
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Layers.WORLD
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nm.filter_baking_aabb = AABB(Vector3(-HALF, -2, -HALF), Vector3(HALF * 2.0, 16, HALF * 2.0))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
	_nav_cache = nm.duplicate()
