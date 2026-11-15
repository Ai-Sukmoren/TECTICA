extends "res://scripts/world/level.gd"
## DEAD END: an abandoned crossroads town, 124 x 124 m, flat. Zombie Survival
## and Deathmatch only (the campaign lives in the forest).
##   centre      police barricade ring at the intersection (zombie stronghold)
##   north-east  gas station canopy + walk-through shop
##   north-west  HOTEL MERIDIAN (5 storeys + roof, stairs to every level),
##               triage checkpoint on its forecourt, one house behind it
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
	FX.ground_surface = "stone"
	Water.clear()

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)

	_build_ground()
	_build_barricade()
	_build_hotel()
	_build_gas_station()
	_build_houses()
	_build_diner()
	_build_truck_yard()
	_build_street_props()
	_build_details()
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
				# the same window from indoors: frame, glass, sill
				var inn := off - nrm * (t + 0.04)
				_mesh(b, ML.box(Vector3(1.34, 1.14, 0.05) if along_x else Vector3(0.05, 1.14, 1.34)), _mat_wall_trim, inn + nrm * 0.03)
				_mesh(b, ML.box(pane), _mat_glass_lit if glow else M.car_glass(), inn).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_mesh(b, ML.box(Vector3(1.42, 0.05, 0.16) if along_x else Vector3(0.16, 0.05, 1.42)), _mat_wall_trim, inn + Vector3(0, -0.58, 0) - nrm * 0.05)
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
	_interior_probe(c, Vector3(w - 0.1, h + 0.2, d - 0.1))
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


func _furniture(pos: Vector3, size: Vector3, color: Color, rot: float = 0.0, cover: bool = true, cloth: bool = false) -> void:
	var key := "furn_" + color.to_html(false)
	var mat: Material = M.fabric(key, color, 5.0) if cloth else M.wood(key, color)
	solid_box(pos, size, mat, rot, cover and size.y <= 1.25, "wood").finalize()


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
	_furniture(c + Vector3(-w * 0.25, 0, -d * 0.2), Vector3(2.2, 0.85, 0.9), Color(0.3, 0.22, 0.2), 0.0, true, true)   # sofa
	_furniture(c + Vector3(w * 0.22, 0, d * 0.1), Vector3(1.4, 0.78, 1.0), Color(0.42, 0.32, 0.22))   # table
	_furniture(c + Vector3(w * 0.28, 0, -d * 0.28), Vector3(2.0, 0.6, 1.5), Color(0.5, 0.45, 0.42), 0.0, true, true)   # bed
	for pz in [-0.36, 0.36]:
		_mesh(self, ML.rbox(Vector3(0.42, 0.12, 0.6)), M.fabric("pillow", Color(0.78, 0.76, 0.7), 5.0), c + Vector3(w * 0.28 - 0.7, 0.65, -d * 0.28 + pz))
	# sofa back and arm rests (inside the cover box's footprint)
	var sofa := c + Vector3(-w * 0.25, 0, -d * 0.2)
	var sofa_mat := M.fabric("furn_" + Color(0.3, 0.22, 0.2).to_html(false), Color(0.3, 0.22, 0.2), 5.0)
	_mesh(self, ML.rbox(Vector3(2.2, 0.32, 0.26)), sofa_mat, sofa + Vector3(0, 0.98, -0.32))
	for sx in [-1.0, 1.0]:
		_mesh(self, ML.rbox(Vector3(0.24, 0.2, 0.9)), sofa_mat, sofa + Vector3(sx * 0.98, 0.9, 0))


func _build_houses() -> void:
	# one house survives behind the hotel; the alley between them is tight
	_build_house(Vector3(-21, 0, -41), 12.0, 10.0, {"s": [-2.0, 1.8], "n": [2.0, 1.8]})
	_fence(Vector3(-42, 0, -34), Vector3(-42, 0, -48))
	_fence(Vector3(-42, 0, -48), Vector3(-30, 0, -48))
	crate(Vector3(-36, 0, -38), Vector3(1.2, 1.0, 1.2), 0.4)
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
		_furniture(c + Vector3(bx, 0, -3.8), Vector3(1.6, 1.0, 0.5), Color(0.6, 0.12, 0.1), 0.0, true, true)
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


## Returns the car body; anything mounted on it (light bar, fire) is parented
## to it so it breaks away with the car.
func _car(p: Vector3, rot: float, paint_col: Color, burning: bool = false) -> StaticBody3D:
	var b := _body(p, rot, "metal")
	_box_shape(b, Vector3(1.9, 1.45, 4.3), Vector3(0, 0.72, 0))
	var paint: Material = M.matte("car_burnt", Color(0.07, 0.065, 0.06), 0.95) if burning else M.car_paint("car_" + paint_col.to_html(), paint_col)
	var trim := M.matte("car_trim", Color(0.05, 0.05, 0.055), 0.6)
	var chrome := M.solid(Color(0.6, 0.62, 0.64), 0.25, 0.9)
	var tire := M.matte("tire", Color(0.05, 0.05, 0.05), 0.92)
	var glass: Material = M.solid(Color(0.12, 0.11, 0.1), 0.9) if burning else M.car_glass()
	var cm := _car_meshes()
	_mesh(b, cm.body, paint, Vector3.ZERO)
	_mesh(b, cm.cabin, glass, Vector3.ZERO)
	_mesh(b, cm.roof, paint, Vector3.ZERO)
	# pillars over the glass: A, B, C each side
	for sx in [-1.0, 1.0]:
		_strut(b, Vector3(sx * 0.84, 0.95, -0.93), Vector3(sx * 0.66, 1.4, -0.36), 0.055, paint)
		_strut(b, Vector3(sx * 0.875, 0.95, 0.28), Vector3(sx * 0.675, 1.4, 0.28), 0.06, trim)
		_strut(b, Vector3(sx * 0.85, 0.96, 1.48), Vector3(sx * 0.665, 1.4, 0.92), 0.09, paint)
	var lamp: Material = M.emissive("headlamp_dead", Color(0.3, 0.3, 0.28), 0.0) if burning else M.emissive("headlamp", Color(0.9, 0.9, 0.8), 0.15)
	var alloy := M.solid(Color(0.42, 0.43, 0.45), 0.38, 0.85)
	var arch := M.matte("car_arch", Color(0.012, 0.012, 0.012), 1.0)
	for sx in [-1.0, 1.0]:
		_mesh(b, ML.box(Vector3(0.012, 0.52, 0.012)), trim, Vector3(sx * 0.941, 0.64, -0.3))   # door seams
		_mesh(b, ML.box(Vector3(0.012, 0.52, 0.012)), trim, Vector3(sx * 0.941, 0.64, 0.28))
		_mesh(b, ML.box(Vector3(0.012, 0.52, 0.012)), trim, Vector3(sx * 0.941, 0.64, 0.95))
		_mesh(b, ML.box(Vector3(0.014, 0.02, 0.1)), chrome, Vector3(sx * 0.945, 0.84, -0.1))   # door handles
		_mesh(b, ML.box(Vector3(0.014, 0.02, 0.1)), chrome, Vector3(sx * 0.945, 0.84, 0.5))
		_mesh(b, ML.rbox(Vector3(0.14, 0.09, 0.07)), paint, Vector3(sx * 0.98, 1.02, -0.78))     # mirrors
		_mesh(b, ML.rbox(Vector3(0.4, 0.13, 0.08)), lamp, Vector3(sx * 0.6, 0.7, -2.07))
		_mesh(b, ML.rbox(Vector3(0.42, 0.11, 0.08)), M.emissive("tail", Color(0.6, 0.05, 0.03), 0.6), Vector3(sx * 0.6, 0.76, 2.07))
	# bumpers, grille, number plates
	for sz in [-2.1, 2.1]:
		_mesh(b, ML.rbox(Vector3(1.84, 0.2, 0.16)), trim, Vector3(0, 0.45, sz))
		_mesh(b, ML.box(Vector3(0.44, 0.11, 0.012)), M.solid(Color(0.75, 0.74, 0.68), 0.5), Vector3(0, 0.46, sz + signf(sz) * 0.082))
	_mesh(b, ML.rbox(Vector3(0.74, 0.12, 0.06)), trim, Vector3(0, 0.7, -2.09))
	# wheels: tyre, alloy rim, hub, and the dark arch they sit in
	for sz in [-1.35, 1.35]:
		for sx in [-0.865, 0.865]:
			_mesh(b, ML.cylinder(0.33, 0.33, 0.22, 22), tire, Vector3(sx, 0.33, sz), Vector3(0, 0, PI * 0.5))
			_mesh(b, ML.cylinder(0.215, 0.215, 0.215, 16), trim, Vector3(sx, 0.33, sz), Vector3(0, 0, PI * 0.5))
			for k in 3:   # six-spoke alloy
				_mesh(b, ML.box(Vector3(0.225, 0.41, 0.05)), alloy, Vector3(sx, 0.33, sz), Vector3(k * PI / 3.0 + sz, 0, 0))
			_mesh(b, ML.cylinder(0.06, 0.06, 0.235, 10), alloy, Vector3(sx, 0.33, sz), Vector3(0, 0, PI * 0.5))
			_mesh(b, ML.cylinder(0.41, 0.41, 0.012, 24), arch, Vector3(signf(sx) * 0.943, 0.34, sz), Vector3(0, 0, PI * 0.5))
	_add_cover(p, Vector3(1.9, 1.45, 4.3), rot, b)
	if burning:
		_fire(Vector3(0, 1.2, 0), b)
	b.finalize()
	return b


var _car_mesh_cache := {}

## Saloon body as smooth lofted skins (built once): the lower body from nose
## to tail, the glasshouse, and the roof panel.
func _car_meshes() -> Dictionary:
	if not _car_mesh_cache.is_empty():
		return _car_mesh_cache
	# station: z, underside y, top y, half width
	var st := [[-2.14, 0.42, 0.6, 0.7], [-2.08, 0.32, 0.74, 0.86], [-1.9, 0.27, 0.84, 0.92], [-1.4, 0.26, 0.9, 0.94],
			[-0.9, 0.26, 0.95, 0.94], [0.0, 0.26, 0.96, 0.94], [1.3, 0.26, 0.97, 0.94], [1.8, 0.27, 0.94, 0.93],
			[2.02, 0.3, 0.9, 0.9], [2.1, 0.34, 0.8, 0.84], [2.14, 0.42, 0.66, 0.7]]
	var rings: Array = []
	for s in st:
		var z: float = s[0]
		var yb: float = s[1]
		var yt: float = s[2]
		var w: float = s[3]
		var ys := yt - minf(0.15, (yt - yb) * 0.4)
		rings.append([Vector3(-w * 0.9, yb, z), Vector3(-w, yb + 0.07, z), Vector3(-w, ys, z), Vector3(-w * 0.975, yt - 0.045, z),
				Vector3(-w * 0.88, yt - 0.008, z), Vector3(-w * 0.45, yt + 0.018, z), Vector3(0, yt + 0.025, z), Vector3(w * 0.45, yt + 0.018, z),
				Vector3(w * 0.88, yt - 0.008, z), Vector3(w * 0.975, yt - 0.045, z), Vector3(w, ys, z), Vector3(w, yb + 0.07, z), Vector3(w * 0.9, yb, z)])
	_car_mesh_cache.body = _loft(rings)
	# glasshouse: z, top y, half width at the belt, half width at the roof
	var gh := [[-0.97, 0.99, 0.86, 0.84], [-0.36, 1.4, 0.875, 0.66], [0.28, 1.42, 0.88, 0.68], [0.92, 1.4, 0.875, 0.67], [1.52, 1.0, 0.86, 0.84]]
	rings = []
	var roof: Array = []
	for s in gh:
		var z: float = s[0]
		var yt: float = s[1]
		var wb: float = s[2]
		var wt: float = s[3]
		rings.append([Vector3(-wb, 0.93, z), Vector3(-wt, yt - 0.04, z), Vector3(-wt * 0.86, yt, z), Vector3(0, yt + 0.022, z),
				Vector3(wt * 0.86, yt, z), Vector3(wt, yt - 0.04, z), Vector3(wb, 0.93, z)])
		if yt > 1.3:
			var e: float = 0.04 if absf(z - 0.28) > 0.1 else 0.0
			var zz := z + signf(z - 0.28) * e
			roof.append([Vector3(-wt - 0.012, yt - 0.06, zz), Vector3(-wt * 0.86, yt + 0.01, zz), Vector3(0, yt + 0.033, zz), Vector3(wt * 0.86, yt + 0.01, zz),
					Vector3(wt + 0.012, yt - 0.06, zz), Vector3(wt * 0.8, yt - 0.03, zz), Vector3(0, yt - 0.01, zz), Vector3(-wt * 0.8, yt - 0.03, zz)])
	_car_mesh_cache.cabin = _loft(rings)
	_car_mesh_cache.roof = _loft(roof)
	return _car_mesh_cache


## Skins a row of closed rings (equal point counts) with smooth normals and capped ends.
func _loft(rings: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = rings[0].size()
	for r in rings:
		for p in r:
			st.add_vertex(p)
	for i in rings.size() - 1:
		for k in n:
			var a := i * n + k
			var c := i * n + (k + 1) % n
			st.add_index(a)
			st.add_index(c)
			st.add_index(a + n)
			st.add_index(c)
			st.add_index(c + n)
			st.add_index(a + n)
	var base := rings.size() * n
	for e in 2:
		var ring: Array = rings[0 if e == 0 else rings.size() - 1]
		var cen := Vector3.ZERO
		for p in ring:
			cen += p
		st.add_vertex(cen / n)
		var off := 0 if e == 0 else (rings.size() - 1) * n
		for k in n:
			var a := off + k
			var c := off + (k + 1) % n
			if e == 0:
				st.add_index(base); st.add_index(c); st.add_index(a)
			else:
				st.add_index(base + 1); st.add_index(a); st.add_index(c)
	st.generate_normals()
	return st.commit()


## Thin bar from `a` to `c` (pillars, rails).
func _strut(parent: Node3D, a: Vector3, c: Vector3, thick: float, mat: Material) -> MeshInstance3D:
	var mi := _mesh(parent, ML.box(Vector3(thick, thick * 0.6, a.distance_to(c))), mat, (a + c) * 0.5)
	mi.basis = Basis.looking_at(c - a, Vector3.RIGHT if absf((c - a).normalized().y) > 0.95 else Vector3.UP)
	return mi


func _police_car(p: Vector3, rot: float) -> void:
	var b := _car(p, rot, Color(0.08, 0.09, 0.12))
	# light bar and beacons ride on the car body, so they go when it is destroyed
	_mesh(b, ML.box(Vector3(1.0, 0.12, 0.25)), M.solid(Color(0.1, 0.1, 0.1)), Vector3(0, 1.47, 0.28))
	for side in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(side * 0.35, 1.75, 0.28)
		l.light_color = Color(1.0, 0.1, 0.08) if side < 0 else Color(0.1, 0.3, 1.0)
		l.omni_range = 7.0
		b.add_child(l)
		lamp_lights.append({"light": l, "base": 1.6, "group": "beacon"})


## Fire at `p`, local to `parent` (the level by default).
func _fire(p: Vector3, parent: Node3D = null) -> void:
	if parent == null:
		parent = self
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
	parent.add_child(f)
	var l := OmniLight3D.new()
	l.position = p + Vector3(0, 0.6, 0)
	l.light_color = Color(1.0, 0.5, 0.2)
	l.omni_range = 10.0
	parent.add_child(l)
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
	nm.filter_baking_aabb = AABB(Vector3(-HALF, -2, -HALF), Vector3(HALF * 2.0, 30, HALF * 2.0))   # up to the hotel roof
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
	_nav_cache = nm.duplicate()
# ================================================================ HOTEL MERIDIAN
# Five storeys plus a walkable roof, north-west block. Footprint x -36..-14,
# z -30..-14. A switchback stair in the north-east corner links every level:
# flight A (west lane) climbs north to a half landing, flight B (east lane)
# climbs back south to the next floor. Each storey lives in its own node so
# the levels above the operator can be hidden in the top-down view.

const HOTEL_X0 := -36.0
const HOTEL_X1 := -14.0
const HOTEL_Z0 := -30.0
const HOTEL_Z1 := -14.0
const HOTEL_FLOORS := 5
const FLOOR_H := 3.6
const SLAB := 0.3
const EXT_T := 0.4
# stairwell: lanes run z -27.8..-22.8, half landing z -29.6..-27.8
const STAIR_X0 := -18.0
const STAIR_Z_TOP := -27.8
const STAIR_Z_BOT := -22.8
const LANE_A := -17.15
const LANE_B := -15.25

var _storeys: Array = []            # Node3D per storey; index HOTEL_FLOORS = roof
var _hotel_rect := Rect2(HOTEL_X0, HOTEL_Z0, HOTEL_X1 - HOTEL_X0, HOTEL_Z1 - HOTEL_Z0)
var _mat_hotel: Material
var _mat_hotel_in: Material
var _mat_slab: Material
var _mat_stair: Material
var _mat_tread: Material
var _mat_carpet: Material


func hotel_roof_y() -> float:
	return HOTEL_FLOORS * FLOOR_H


func _build_hotel() -> void:
	_blocked.append(_hotel_rect.grow(2.5))
	_mat_hotel = M.concrete("hotel_ext", Color(0.5, 0.43, 0.36), 0.6)
	_mat_hotel_in = M.solid(Color(0.6, 0.56, 0.48), 0.9)
	_mat_slab = M.concrete("hotel_slab", Color(0.36, 0.36, 0.37), 0.5)
	_mat_stair = M.concrete("hotel_stair", Color(0.3, 0.3, 0.31), 0.7)
	_mat_tread = M.solid(Color(0.16, 0.16, 0.17), 0.8)
	_mat_carpet = M.fabric("hotel_carpet", Color(0.34, 0.1, 0.1), 3.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	for k in HOTEL_FLOORS + 1:
		var bodies := nav_region.get_child_count()
		var extras := get_child_count()
		var rects := map_rects.size()
		var covers := cover_points.size()
		if k < HOTEL_FLOORS:
			_hotel_storey(k, rng)
		else:
			_hotel_roof()
		var moved: Array = nav_region.get_children().slice(bodies) + get_children().slice(extras)
		var st := Node3D.new()
		st.name = "HotelStorey%d" % k
		nav_region.add_child(st)
		for n in moved:
			(n as Node).reparent(st, true)
		_storeys.append(st)
		if k > 0:
			# the radar and ground cover only describe street level
			map_rects.resize(rects)
			cover_points.resize(covers)
	_hotel_exterior()


## A straight wall from `origin` along +x or +z. gaps = [[from, to]] doorways
## (lintel above 2.25 m). windows: sill + lintel + pillars with open frames.
func _wall_run(origin: Vector3, along_x: bool, length: float, h: float, thick: float, mat: Material,
		gaps: Array = [], windows: bool = false) -> void:
	var dir := Vector3.RIGHT if along_x else Vector3.BACK
	var cuts: Array = gaps.duplicate()
	cuts.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for seg in _segments(0.0, length, cuts):
		var a: float = seg[0]
		var b: float = seg[1]
		var l := b - a
		if l < 0.08:
			continue
		if windows and l >= 2.8:
			_wall_piece_at(origin + dir * (a + l * 0.5), along_x, l, 1.0, thick, mat)
			_wall_piece_at(origin + dir * (a + l * 0.5) + Vector3.UP * 2.3, along_x, l, h - 2.3, thick, mat)
			var bays := maxi(1, int(l / 3.0))
			var bay := l / bays
			var pw := bay - 2.0
			for i in bays + 1:
				var c := a + i * bay
				var lo := maxf(a, c - pw * 0.5)
				var hi := minf(b, c + pw * 0.5)
				if hi - lo > 0.05:
					_wall_piece_at(origin + dir * ((lo + hi) * 0.5) + Vector3.UP * 1.0, along_x, hi - lo, 1.3, thick, mat)
		else:
			_wall_piece_at(origin + dir * (a + l * 0.5), along_x, l, h, thick, mat)
	for g in cuts:
		var gl: float = float(g[1]) - float(g[0])
		if h > 2.3:
			_wall_piece_at(origin + dir * (float(g[0]) + gl * 0.5) + Vector3.UP * 2.25, along_x, gl, h - 2.25, thick, mat)


func _wall_piece_at(bottom_centre: Vector3, along_x: bool, l: float, h: float, thick: float, mat: Material) -> void:
	solid_box(bottom_centre, Vector3(l, h, thick) if along_x else Vector3(thick, h, l), mat)


func _hotel_slab(y: float) -> void:
	# two pieces leave the stairwell open
	solid_box(Vector3((HOTEL_X0 + STAIR_X0 - 0.2) * 0.5, y - SLAB, (HOTEL_Z0 + HOTEL_Z1) * 0.5),
			Vector3(STAIR_X0 - 0.2 - HOTEL_X0, SLAB, HOTEL_Z1 - HOTEL_Z0), _mat_slab)
	solid_box(Vector3((STAIR_X0 - 0.2 + HOTEL_X1) * 0.5, y - SLAB, (STAIR_Z_BOT + HOTEL_Z1) * 0.5),
			Vector3(HOTEL_X1 - STAIR_X0 + 0.2, SLAB, HOTEL_Z1 - STAIR_Z_BOT), _mat_slab)


## One flight: 5 m run, half a storey rise. north = climbs toward -z.
func _flight(y_bottom: float, lane_x: float, north: bool) -> void:
	var run := STAIR_Z_BOT - STAIR_Z_TOP
	var rise := FLOOR_H * 0.5
	var length := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var b := _body(Vector3(lane_x, y_bottom + rise * 0.5 - 0.125 / cos(ang), (STAIR_Z_TOP + STAIR_Z_BOT) * 0.5))
	b.rotation.x = ang if north else -ang
	_box_shape(b, Vector3(1.7, 0.25, length), Vector3.ZERO)
	_mesh(b, ML.box(Vector3(1.7, 0.25, length)), _mat_stair, Vector3.ZERO)
	for i in 10:
		var tread := _mesh(b, ML.box(Vector3(1.7, 0.03, 0.2)), _mat_tread, Vector3(0, 0.14, -length * 0.5 + (i + 0.5) * length / 10.0))
		tread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _hotel_stairs(y: float, wall_h: float) -> void:
	_flight(y, LANE_A, true)
	_flight(y + FLOOR_H * 0.5, LANE_B, false)
	# half landing against the north wall
	solid_box(Vector3((STAIR_X0 + HOTEL_X1 - EXT_T) * 0.5, y + FLOOR_H * 0.5 - 0.25, (HOTEL_Z0 + EXT_T + STAIR_Z_TOP) * 0.5),
			Vector3(HOTEL_X1 - EXT_T - STAIR_X0, 0.25, STAIR_Z_TOP - HOTEL_Z0 - EXT_T), _mat_stair)
	# wall between the lanes and the stairwell's west wall
	_wall_run(Vector3((LANE_A + LANE_B) * 0.5, y, STAIR_Z_TOP), false, STAIR_Z_BOT - STAIR_Z_TOP, wall_h, 0.15, _mat_hotel_in)
	_wall_run(Vector3(STAIR_X0 - 0.1, y, HOTEL_Z0 + EXT_T), false, STAIR_Z_BOT - HOTEL_Z0 - EXT_T, wall_h, 0.2, _mat_hotel_in)


func _hotel_light(pos: Vector3, energy: float, rng_range: float, flicker: bool = false, col: Color = Color(1.0, 0.84, 0.62)) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.omni_range = rng_range
	l.omni_attenuation = 1.3
	l.light_volumetric_fog_energy = 0.2
	add_child(l)
	lamp_lights.append({"light": l, "base": energy, "group": "interior", "flicker": flicker})
	lights.append({"light": l, "shadow": false})
	var fixture := _mesh(self, ML.box(Vector3(0.7, 0.05, 0.22)), M.emissive("hotel_lamp", col, 2.4), pos + Vector3(0, 0.22, 0))
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _hotel_furnish_room(x0: float, x1: float, z0: float, z1: float, y: float, rng: RandomNumberGenerator, low: bool) -> void:
	var cx := (x0 + x1) * 0.5
	var back := z0 + 0.9 if z0 < -22.0 else z1 - 0.9     # the wall away from the corridor
	var wood := Color(0.36, 0.26, 0.18)
	# bed against the outer wall, wardrobe in a corner, table near the door
	_furniture(Vector3(cx + rng.randf_range(-0.6, 0.6), y, back), Vector3(2.0, 0.55, 1.5), Color(0.55, 0.5, 0.46), rng.randf_range(-0.08, 0.08), low)
	if rng.randf() < 0.75:
		_furniture(Vector3(x0 + 0.75, y, back + (1.6 if z0 < -22.0 else -1.6)), Vector3(1.0, 2.0, 0.55), wood, PI * 0.5, false)
	if rng.randf() < 0.7:
		var tz := (z1 - 1.5) if z0 < -22.0 else (z0 + 1.5)
		_furniture(Vector3(x1 - 1.3, y, tz), Vector3(1.1, 0.76, 0.8), wood, rng.randf_range(-0.5, 0.5), low)


func _hotel_storey(k: int, rng: RandomNumberGenerator) -> void:
	var y := k * FLOOR_H
	var wall_h := FLOOR_H - SLAB
	var inner_x0 := HOTEL_X0 + EXT_T
	var inner_z0 := HOTEL_Z0 + EXT_T
	var inner_z1 := HOTEL_Z1 - EXT_T
	var low := k == 0
	if k > 0:
		_hotel_slab(y)
		var carpet := _floor_patch(Vector3((HOTEL_X0 + STAIR_X0) * 0.5, y + 0.012, -22.0), Vector2(STAIR_X0 - HOTEL_X0 - 0.9, 2.2), _mat_carpet)
		carpet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_floor_patch(Vector3((HOTEL_X0 + HOTEL_X1) * 0.5, 0.02, (HOTEL_Z0 + HOTEL_Z1) * 0.5), Vector2(HOTEL_X1 - HOTEL_X0 - 0.8, HOTEL_Z1 - HOTEL_Z0 - 0.8),
				M.floor_grid("hotel_lobby", Color(0.3, 0.27, 0.22), Color(0.4, 0.36, 0.28), 0.35))
		_floor_patch(Vector3(-23.5, 0.03, -17.5), Vector2(3.0, 6.0), _mat_carpet)
	# outer walls with open window frames; lobby doors on the ground floor
	_wall_run(Vector3(HOTEL_X0, y, HOTEL_Z1 - EXT_T * 0.5), true, HOTEL_X1 - HOTEL_X0, wall_h, EXT_T, _mat_hotel, [[10.9, 14.1]] if k == 0 else [], true)
	_wall_run(Vector3(HOTEL_X0, y, HOTEL_Z0 + EXT_T * 0.5), true, HOTEL_X1 - HOTEL_X0, wall_h, EXT_T, _mat_hotel, [], true)
	_wall_run(Vector3(HOTEL_X0 + EXT_T * 0.5, y, inner_z0), false, inner_z1 - inner_z0, wall_h, EXT_T, _mat_hotel, [], true)
	_wall_run(Vector3(HOTEL_X1 - EXT_T * 0.5, y, inner_z0), false, inner_z1 - inner_z0, wall_h, EXT_T, _mat_hotel, [[11.2, 13.0]] if k == 0 else [], true)
	_hotel_stairs(y, wall_h)
	# rooms north of the corridor (every storey)
	var n_len := STAIR_X0 - 0.2 - inner_x0
	_wall_run(Vector3(inner_x0, y, -23.2), true, n_len, wall_h, 0.2, _mat_hotel_in, [[2.3, 3.7], [7.9, 9.3], [13.7, 15.1]])
	for x in [-30.0, -24.0]:
		_wall_run(Vector3(x, y, inner_z0), false, -23.3 - inner_z0, wall_h, 0.2, _mat_hotel_in)
	var north_rooms := [[inner_x0, -30.1], [-29.9, -24.1], [-23.9, STAIR_X0 - 0.3]]
	for r in north_rooms:
		_hotel_furnish_room(r[0], r[1], inner_z0, -23.3, y, rng, low)
	# corridor + stair lights, a few lit rooms
	_hotel_light(Vector3(-27.5, y + wall_h - 0.35, -22.0), 1.5, 11.0, rng.randf() < 0.35)
	_hotel_light(Vector3(-16.2, y + wall_h - 0.35, -22.0), 1.3, 8.0, rng.randf() < 0.25)
	_hotel_light(Vector3(north_rooms[rng.randi() % 3][0] + 2.8, y + wall_h - 0.35, -26.6), 1.2, 7.0)
	if k == 0:
		# lobby: reception, seating, luggage
		solid_box(Vector3(-31.0, 0, -18.4), Vector3(4.4, 1.1, 0.9), M.wood("reception", Color(0.3, 0.2, 0.13)), 0.0, true, "wood").finalize()
		_furniture(Vector3(-27.0, 0, -15.6), Vector3(2.2, 0.8, 0.9), Color(0.4, 0.12, 0.12))
		_furniture(Vector3(-18.6, 0, -16.6), Vector3(0.9, 0.8, 2.2), Color(0.4, 0.12, 0.12), 0.0)
		_furniture(Vector3(-20.6, 0, -19.0), Vector3(1.2, 0.5, 0.8), Color(0.2, 0.16, 0.12), 0.3)
		crate(Vector3(-34.2, 0, -15.6), Vector3(1.0, 0.8, 1.0), 0.2)
		_hotel_light(Vector3(-25.0, wall_h - 0.35, -17.5), 1.8, 10.0)
		var desk_sign := Label3D.new()
		desk_sign.text = "RECEPTION"
		desk_sign.font_size = 64
		desk_sign.pixel_size = 0.005
		desk_sign.modulate = Color(1.0, 0.82, 0.5)
		desk_sign.position = Vector3(-31.0, 2.6, -20.65)
		add_child(desk_sign)
	elif k == HOTEL_FLOORS - 1:
		# top floor lounge: open plan with a bar
		solid_box(Vector3(-31.5, y, -16.2), Vector3(6.0, 1.1, 0.8), M.wood("bar", Color(0.22, 0.14, 0.1)), 0.0, false, "wood").finalize()
		for i in 4:
			_furniture(Vector3(-27.0 + i * 3.4, y, -18.4 + (i % 2) * 1.6), Vector3(1.1, 0.76, 1.1), Color(0.3, 0.22, 0.16), i * 0.4, false)
		_hotel_light(Vector3(-27.0, y + wall_h - 0.35, -17.4), 1.6, 10.0, false, Color(1.0, 0.6, 0.75))
		_hotel_light(Vector3(-18.0, y + wall_h - 0.35, -17.4), 1.4, 8.0, false, Color(0.6, 0.8, 1.0))
	else:
		# guest rooms south of the corridor
		var s_len := HOTEL_X1 - EXT_T - inner_x0
		_wall_run(Vector3(inner_x0, y, -20.8), true, s_len, wall_h, 0.2, _mat_hotel_in, [[2.3, 3.7], [7.9, 9.3], [13.4, 14.8], [18.2, 19.6]])
		for x in [-30.0, -24.0, -19.0]:
			_wall_run(Vector3(x, y, -20.7), false, inner_z1 + 20.7, wall_h, 0.2, _mat_hotel_in)
		var south_rooms := [[inner_x0, -30.1], [-29.9, -24.1], [-23.9, -19.1], [-18.9, HOTEL_X1 - EXT_T]]
		for r in south_rooms:
			_hotel_furnish_room(r[0], r[1], -20.7, inner_z1, y, rng, false)
		_hotel_light(Vector3(south_rooms[rng.randi() % 4][0] + 2.5, y + wall_h - 0.35, -17.6), 1.2, 7.0)
		if rng.randf() < 0.6:
			# a hasty barricade in the corridor
			_furniture(Vector3(rng.randf_range(-33.0, -22.0), y, -22.0), Vector3(1.6, 0.9, 0.7), Color(0.32, 0.24, 0.17), rng.randf_range(-0.6, 0.6), false)


func _hotel_roof() -> void:
	var y := hotel_roof_y()
	_hotel_slab(y)
	# parapet (the stairhead walls stand in for it in the north-east corner)
	var p := M.concrete("hotel_parapet", Color(0.42, 0.4, 0.38), 0.6)
	_wall_run(Vector3(HOTEL_X0, y, HOTEL_Z1 - EXT_T * 0.5), true, HOTEL_X1 - HOTEL_X0, 1.1, EXT_T, p)
	_wall_run(Vector3(HOTEL_X0 + EXT_T * 0.5, y, HOTEL_Z0), false, HOTEL_Z1 - HOTEL_Z0, 1.1, EXT_T, p)
	_wall_run(Vector3(HOTEL_X0, y, HOTEL_Z0 + EXT_T * 0.5), true, STAIR_X0 - 0.2 - HOTEL_X0, 1.1, EXT_T, p)
	_wall_run(Vector3(HOTEL_X1 - EXT_T * 0.5, y, STAIR_Z_BOT), false, HOTEL_Z1 - STAIR_Z_BOT, 1.1, EXT_T, p)
	# stairhead: three walls and a cap, open to the south
	var bh := 2.7
	_wall_run(Vector3(STAIR_X0 - 0.1, y, HOTEL_Z0), false, STAIR_Z_BOT - HOTEL_Z0, bh, 0.2, _mat_hotel)
	_wall_run(Vector3(STAIR_X0 - 0.2, y, HOTEL_Z0 + EXT_T * 0.5), true, HOTEL_X1 - STAIR_X0 + 0.2, bh, EXT_T, _mat_hotel)
	_wall_run(Vector3(HOTEL_X1 - EXT_T * 0.5, y, HOTEL_Z0), false, STAIR_Z_BOT - HOTEL_Z0, bh, EXT_T, _mat_hotel)
	solid_box(Vector3((STAIR_X0 - 0.3 + HOTEL_X1) * 0.5, y + bh, (HOTEL_Z0 + STAIR_Z_BOT + 0.3) * 0.5),
			Vector3(HOTEL_X1 - STAIR_X0 + 0.3, 0.25, STAIR_Z_BOT + 0.3 - HOTEL_Z0), _mat_slab)
	_hotel_light(Vector3(-16.2, y + 2.2, -24.0), 1.4, 7.0, true, Color(1.0, 0.5, 0.35))
	# water tank on a frame
	var steel := M.painted_metal("roof_steel", Color(0.34, 0.36, 0.38))
	var tank := solid_box(Vector3(-32.0, y, -26.0), Vector3(2.8, 1.2, 2.8), steel)
	_mesh(tank, ML.cylinder(1.5, 1.5, 2.6, 18), M.painted_metal("water_tank", Color(0.5, 0.42, 0.34)), Vector3(0, 2.5, 0))
	_mesh(tank, ML.cylinder(0.2, 1.55, 0.6, 18), M.painted_metal("water_tank", Color(0.5, 0.42, 0.34)), Vector3(0, 4.1, 0))
	# air conditioning units, vents
	for a in [Vector3(-26.0, y, -27.6), Vector3(-22.6, y, -27.6), Vector3(-33.6, y, -19.0)]:
		var ac := solid_box(a, Vector3(1.8, 1.05, 1.1), steel)
		_mesh(ac, ML.cylinder(0.42, 0.42, 0.06, 14), _mat_tread, Vector3(0, 1.08, 0))
	# sniper nest over the crossroads + the reward for the climb
	sandbags(Vector3(-16.2, y, -15.4), 3.0, 0.0)
	sandbags(Vector3(-14.9, y, -17.0), 2.4, PI * 0.5)
	crate(Vector3(-20.0, y, -15.6), Vector3(1.0, 0.8, 1.0), 0.3)
	ammo_crates.append(Vector3(-18.6, y, -18.4))
	# antenna mast with a beacon
	_mesh(self, ML.cylinder(0.05, 0.09, 7.0, 8), steel, Vector3(-34.6, y + 3.5, -28.6))
	for h in [2.2, 4.4]:
		_mesh(self, ML.box(Vector3(1.6, 0.05, 0.05)), steel, Vector3(-34.6, y + h, -28.6))
	var beacon := OmniLight3D.new()
	beacon.position = Vector3(-34.6, y + 7.1, -28.6)
	beacon.light_color = Color(1.0, 0.1, 0.08)
	beacon.omni_range = 9.0
	add_child(beacon)
	var bulb := _mesh(self, ML.sphere(0.14, false, 8), M.emissive("beacon_red", Color(1.0, 0.1, 0.05), 4.0), Vector3(-34.6, y + 7.05, -28.6))
	lamp_lights.append({"light": beacon, "base": 3.0, "group": "beacon", "bulb": bulb, "blink": true})


func _hotel_exterior() -> void:
	var top := hotel_roof_y()
	# entrance awning on posts
	var red := M.fabric("awning", Color(0.5, 0.08, 0.08), 2.0)
	var awning := _mesh(self, ML.box(Vector3(4.6, 0.18, 2.6)), red, Vector3(-23.5, 2.95, HOTEL_Z1 + 1.2))
	awning.rotation.x = 0.08
	for sx in [-2.1, 2.1]:
		solid_box(Vector3(-23.5 + sx, 0, HOTEL_Z1 + 2.3), Vector3(0.14, 2.85, 0.14), _mat_wall_trim)
	# name over the door
	var board := _mesh(self, ML.box(Vector3(9.0, 1.0, 0.16)), M.solid(Color(0.06, 0.06, 0.07), 0.5), Vector3(-23.5, 4.3, HOTEL_Z1 + 0.1))
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var name_label := Label3D.new()
	name_label.text = "HOTEL  MERIDIAN"
	name_label.font_size = 110
	name_label.pixel_size = 0.0058
	name_label.modulate = Color(1.0, 0.25, 0.7)
	name_label.position = Vector3(-23.5, 4.3, HOTEL_Z1 + 0.2)
	add_child(name_label)
	# vertical neon blade on the corner facing the crossroads
	var blade := _mesh(self, ML.box(Vector3(0.45, 8.5, 1.5)), M.solid(Color(0.06, 0.06, 0.07), 0.5), Vector3(HOTEL_X1 + 0.35, 9.5, HOTEL_Z1 - 1.4))
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var letters := "HOTEL"
	for i in letters.length():
		for side in [-1.0, 1.0]:
			var ch := Label3D.new()
			ch.text = letters[i]
			ch.font_size = 150
			ch.pixel_size = 0.0075
			ch.modulate = Color(1.0, 0.25, 0.7)
			ch.position = Vector3(HOTEL_X1 + 0.35, 12.7 - i * 1.55, HOTEL_Z1 - 1.4 + side * 0.77)
			ch.rotation.y = 0.0 if side > 0 else PI
			add_child(ch)
	var neon := OmniLight3D.new()
	neon.position = Vector3(HOTEL_X1 + 1.6, 9.5, HOTEL_Z1 - 0.2)
	neon.light_color = Color(1.0, 0.25, 0.7)
	neon.omni_range = 12.0
	add_child(neon)
	lamp_lights.append({"light": neon, "base": 2.2, "group": "street", "flicker": true})
	# cornice, floor bands, drain pipes, wall-mounted AC boxes
	var trim := _mat_wall_trim
	_mesh(self, ML.box(Vector3(HOTEL_X1 - HOTEL_X0 + 0.5, 0.25, HOTEL_Z1 - HOTEL_Z0 + 0.5)), trim, Vector3((HOTEL_X0 + HOTEL_X1) * 0.5, top + 0.02, (HOTEL_Z0 + HOTEL_Z1) * 0.5)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in range(1, HOTEL_FLOORS):
		var by := k * FLOOR_H - SLAB * 0.5
		for z in [HOTEL_Z0 - 0.04, HOTEL_Z1 + 0.04]:
			_mesh(self, ML.box(Vector3(HOTEL_X1 - HOTEL_X0 + 0.1, 0.22, 0.06)), trim, Vector3((HOTEL_X0 + HOTEL_X1) * 0.5, by, z)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for x in [HOTEL_X0 - 0.04, HOTEL_X1 + 0.04]:
			_mesh(self, ML.box(Vector3(0.06, 0.22, HOTEL_Z1 - HOTEL_Z0 + 0.1)), trim, Vector3(x, by, (HOTEL_Z0 + HOTEL_Z1) * 0.5)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pipe := M.painted_metal("drain_pipe", Color(0.2, 0.2, 0.21))
	for c in [Vector3(HOTEL_X0 - 0.12, 0, HOTEL_Z1 - 0.6), Vector3(HOTEL_X1 + 0.12, 0, HOTEL_Z0 + 0.6), Vector3(HOTEL_X0 + 0.6, 0, HOTEL_Z0 - 0.12)]:
		_mesh(self, ML.cylinder(0.07, 0.07, top, 8), pipe, c + Vector3(0, top * 0.5, 0))
	var acm := M.painted_metal("wall_ac", Color(0.6, 0.6, 0.58))
	for k in range(1, HOTEL_FLOORS):
		_mesh(self, ML.box(Vector3(0.9, 0.5, 0.4)), acm, Vector3(-33.0 + (k % 3) * 6.0, k * FLOOR_H + 0.45, HOTEL_Z0 - 0.22))
		_mesh(self, ML.box(Vector3(0.4, 0.5, 0.9)), acm, Vector3(HOTEL_X0 - 0.22, k * FLOOR_H + 0.45, -27.0 + (k % 2) * 7.5))


## Top-down view: hide the storeys above the operator while they are inside,
## and the upper storeys when the building stands between camera and operator.
func _process(_delta: float) -> void:
	if _storeys.is_empty():
		return
	var main := get_parent()
	var p = main.get("player") if main != null else null
	var limit := _storeys.size()
	var top_down: bool = p != null and is_instance_valid(p) and not bool(p.get("first_person")) \
			and not (main.has_method("killcam_active") and main.killcam_active())
	if top_down:
		var pos: Vector3 = p.global_position
		var cam := get_viewport().get_camera_3d()
		if _hotel_rect.grow(0.4).has_point(Vector2(pos.x, pos.z)):
			limit = clampi(int(floor((pos.y + 0.6) / FLOOR_H)), 0, HOTEL_FLOORS) + 1
		elif cam != null:
			var upper := AABB(Vector3(HOTEL_X0, FLOOR_H, HOTEL_Z0), Vector3(HOTEL_X1 - HOTEL_X0, hotel_roof_y() + 3.0 - FLOOR_H, HOTEL_Z1 - HOTEL_Z0))
			if upper.intersects_segment(cam.global_position, pos + Vector3.UP * 1.2):
				limit = 1
	for k in _storeys.size():
		var show: bool = k < limit
		if (_storeys[k] as Node3D).visible != show:
			(_storeys[k] as Node3D).visible = show


# ================================================================ street detail

func _dumpster(p: Vector3, rot: float) -> void:
	var b := solid_box(p, Vector3(2.0, 1.25, 1.1), M.painted_metal("dumpster", Color(0.14, 0.3, 0.2)), rot, true, "metal")
	_mesh(b, ML.box(Vector3(2.06, 0.08, 1.16)), _mat_wall_trim, Vector3(0, 1.27, 0), Vector3(0.12, 0, 0))
	b.finalize()


func _bench(p: Vector3, rot: float) -> void:
	var b := solid_box(p, Vector3(1.7, 0.45, 0.5), _mat_fence, rot, false, "wood")
	_mesh(b, ML.box(Vector3(1.7, 0.5, 0.08)), _mat_fence, Vector3(0, 0.72, -0.22))
	b.finalize()


func _road_sign(p: Vector3, rot: float, text: String, col: Color = Color(0.95, 0.75, 0.1)) -> void:
	var b := solid_box(p, Vector3(0.1, 2.3, 0.1), _mat_metal, rot)
	var plate := _mesh(b, ML.box(Vector3(1.25, 1.25, 0.04)), M.solid(col, 0.6), Vector3(0, 2.6, 0), Vector3(0, 0, PI * 0.25))
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = text
		label.font_size = 56
		label.pixel_size = 0.0052
		label.modulate = Color(0.05, 0.05, 0.05)
		label.outline_size = 0
		label.position = Vector3(0, 2.6, 0.03 * side)
		label.rotation.y = 0.0 if side > 0 else PI
		b.add_child(label)


func _traffic_light(p: Vector3, rot: float) -> void:
	var b := solid_box(p, Vector3(0.16, 4.8, 0.16), _mat_metal, rot)
	_mesh(b, ML.box(Vector3(0.1, 0.1, 2.6)), _mat_metal, Vector3(0, 4.7, -1.3))
	var head := _mesh(b, ML.box(Vector3(0.34, 1.0, 0.3)), M.solid(Color(0.07, 0.07, 0.07), 0.6), Vector3(0, 4.3, -2.5))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lamp := _mesh(b, ML.sphere(0.1, false, 8), M.emissive("signal_amber", Color(1.0, 0.6, 0.05), 3.0), Vector3(0, 4.3, -2.34))
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for dy in [0.3, -0.3]:
		_mesh(b, ML.sphere(0.1, false, 8), M.solid(Color(0.12, 0.1, 0.1), 0.4), Vector3(0, 4.3 + dy, -2.34)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _bus(p: Vector3, rot: float) -> void:
	var b := _body(p, rot)
	_box_shape(b, Vector3(2.6, 3.0, 11.0), Vector3(0, 1.5, 0))
	var paint := M.painted_metal("bus", Color(0.62, 0.5, 0.12))
	_mesh(b, ML.box(Vector3(2.55, 2.5, 10.9)), paint, Vector3(0, 1.75, 0))
	_mesh(b, ML.box(Vector3(2.6, 0.9, 10.2)), _mat_glass_dark, Vector3(0, 2.25, 0))
	_mesh(b, ML.box(Vector3(2.3, 1.0, 0.06)), _mat_glass_dark, Vector3(0, 2.2, -5.46))
	_mesh(b, ML.box(Vector3(2.58, 0.28, 10.95)), M.solid(Color(0.75, 0.75, 0.72), 0.6), Vector3(0, 1.45, 0))
	var tire := M.solid(Color(0.06, 0.06, 0.06), 0.9)
	for sz in [-3.6, 3.4]:
		for sx in [-1.2, 1.2]:
			_mesh(b, ML.cylinder(0.5, 0.5, 0.3, 14), tire, Vector3(sx, 0.5, sz), Vector3(0, 0, PI * 0.5))
	var dest := Label3D.new()
	dest.text = "9  EVACUATION"
	dest.font_size = 72
	dest.pixel_size = 0.005
	dest.modulate = Color(1.0, 0.6, 0.1)
	dest.position = Vector3(0, 2.85, -5.5)
	dest.rotation.y = PI
	b.add_child(dest)
	_add_cover(p, Vector3(2.6, 3.0, 11.0), rot, b)


func _tent(p: Vector3, rot: float) -> void:
	var canvas := M.fabric("triage_canvas", Color(0.7, 0.7, 0.64), 2.0)
	var b := _body(p, rot)
	# two side walls and a back; the front stays open
	for sx in [-1.9, 1.9]:
		_box_shape(b, Vector3(0.12, 2.0, 3.6), Vector3(sx, 1.0, 0))
		_mesh(b, ML.box(Vector3(0.08, 2.0, 3.6)), canvas, Vector3(sx, 1.0, 0))
	_box_shape(b, Vector3(3.8, 2.0, 0.12), Vector3(0, 1.0, -1.8))
	_mesh(b, ML.box(Vector3(3.8, 2.0, 0.08)), canvas, Vector3(0, 1.0, -1.8))
	for sx in [-1.0, 1.0]:
		_mesh(b, ML.box(Vector3(2.15, 0.07, 3.7)), canvas, Vector3(sx * 0.97, 2.42, 0), Vector3(0, 0, -sx * 0.42))
	var cross := M.emissive("red_cross", Color(0.85, 0.08, 0.06), 0.8)
	_mesh(b, ML.box(Vector3(0.9, 0.26, 0.03)), cross, Vector3(0, 1.5, -1.73))
	_mesh(b, ML.box(Vector3(0.26, 0.9, 0.03)), cross, Vector3(0, 1.5, -1.73))
	# cot inside
	_mesh(b, ML.box(Vector3(0.8, 0.35, 1.9)), M.solid(Color(0.3, 0.34, 0.28), 0.9), Vector3(-0.9, 0.2, -0.5))


func _build_details() -> void:
	# crossroads: signals on each corner
	_traffic_light(Vector3(7.6, 0, 7.6), 0.0)
	_traffic_light(Vector3(-7.6, 0, -7.6), PI)
	_traffic_light(Vector3(7.6, 0, -7.6), PI * 0.5)
	_traffic_light(Vector3(-7.6, 0, 7.6), -PI * 0.5)
	# wrecked evacuation bus and the stop it never left
	_bus(Vector3(-35.0, 0, 2.7), PI * 0.5 + 0.1)
	_blocked.append(Rect2(-41.5, 0.5, 13.0, 5.0))
	var shelter := solid_box(Vector3(-33.0, 0, 8.6), Vector3(3.4, 2.3, 0.1), _mat_glass_dark)
	_mesh(shelter, ML.box(Vector3(3.6, 0.1, 1.5)), _mat_metal, Vector3(0, 2.35, -0.6))
	for sx in [-1.65, 1.65]:
		_mesh(shelter, ML.box(Vector3(0.08, 2.3, 0.08)), _mat_metal, Vector3(sx, 1.15, -1.25))
	_bench(Vector3(-33.0, 0, 8.1), 0.0)
	# benches, dumpsters, hydrants
	_bench(Vector3(9.5, 0, -8.2), 0.0)
	_bench(Vector3(-9.2, 0, 30.0), PI * 0.5)
	_dumpster(Vector3(-30.0, 0, -32.6), 0.05)
	_dumpster(Vector3(-19.0, 0, -32.8), -0.1)
	_dumpster(Vector3(-32.4, 0, 22.0), PI * 0.5)
	_dumpster(Vector3(40.6, 0, -20.0), PI * 0.5)
	_dumpster(Vector3(8.8, 0, 40.0), 0.2)
	var hyd := M.painted_metal("hydrant", Color(0.7, 0.1, 0.08))
	for h in [Vector3(7.7, 0, -10.5), Vector3(-7.7, 0, 11.0), Vector3(-7.7, 0, -34.0), Vector3(7.7, 0, 30.0)]:
		_mesh(self, ML.cylinder(0.13, 0.16, 0.6, 10), hyd, h + Vector3(0, 0.3, 0))
		_mesh(self, ML.sphere(0.15, false, 8), hyd, h + Vector3(0, 0.62, 0))
		_mesh(self, ML.cylinder(0.06, 0.06, 0.42, 8), hyd, h + Vector3(0, 0.42, 0), Vector3(0, 0, PI * 0.5))
	# trash and debris
	var bag := M.solid(Color(0.05, 0.05, 0.06), 0.5)
	for i in 22:
		var t := Vector3(randf_range(-HALF + 6, HALF - 6), 0, randf_range(-HALF + 6, HALF - 6))
		if not _free(t, 0.2) or (absf(t.x) < ROAD and absf(t.z) < ROAD):
			continue
		_mesh(self, ML.sphere(randf_range(0.22, 0.38), false, 8), bag, t + Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1.0, 0.75, 1.1)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# dead-end signs at every roadblock
	_road_sign(Vector3(5.6, 0, -HALF + 11.5), 0.0, "DEAD\nEND")
	_road_sign(Vector3(-5.6, 0, HALF - 11.5), PI, "DEAD\nEND")
	_road_sign(Vector3(-HALF + 11.5, 0, -5.6), PI * 0.5, "DEAD\nEND")
	_road_sign(Vector3(HALF - 11.5, 0, 5.6), -PI * 0.5, "DEAD\nEND")
	# billboard over the truck yard
	for sx in [-3.2, 3.2]:
		solid_box(Vector3(46.0, 0, 14.0 + sx), Vector3(0.3, 6.0, 0.3), _mat_metal)
	var panel := _mesh(self, ML.box(Vector3(0.2, 3.6, 8.4)), M.solid(Color(0.82, 0.8, 0.72), 0.7), Vector3(46.0, 6.6, 14.0))
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ad := Label3D.new()
	ad.text = "EVACUATION POINT\nROUTE 9 NORTH  -  STAY CALM"
	ad.font_size = 96
	ad.pixel_size = 0.0075
	ad.modulate = Color(0.1, 0.16, 0.3)
	ad.outline_size = 0
	ad.position = Vector3(45.88, 6.9, 14.0)
	ad.rotation.y = -PI * 0.5
	add_child(ad)
	var scrawl := Label3D.new()
	scrawl.text = "NO ONE CAME"
	scrawl.font_size = 120
	scrawl.pixel_size = 0.008
	scrawl.modulate = Color(0.7, 0.05, 0.04)
	scrawl.outline_size = 0
	scrawl.position = Vector3(45.87, 5.7, 14.6)
	scrawl.rotation = Vector3(0, -PI * 0.5, 0.08)
	add_child(scrawl)
	# triage checkpoint in front of the hotel
	_tent(Vector3(-32.0, 0, -10.6), 0.0)
	_tent(Vector3(-27.4, 0, -10.6), 0.0)
	_blocked.append(Rect2(-34.5, -13.0, 9.6, 5.0))
	sandbags(Vector3(-27.0, 0, -7.9), 2.6, 0.0)
	sandbags(Vector3(-19.8, 0, -8.6), 2.6, 0.15)
	barrier(Vector3(-16.0, 0, -9.4), 0.0)
	crate(Vector3(-20.6, 0, -11.6), Vector3(1.0, 0.8, 1.0), 0.4)
	var stand := solid_box(Vector3(-17.4, 0, -11.8), Vector3(0.12, 3.2, 0.12), _mat_metal)
	var flood_head := _mesh(stand, ML.box(Vector3(0.7, 0.4, 0.2)), M.emissive("floodlight", Color(0.85, 0.92, 1.0), 3.5), Vector3(0, 3.3, 0))
	flood_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flood := OmniLight3D.new()
	flood.position = Vector3(-18.0, 3.2, -11.4)
	flood.light_color = Color(0.85, 0.92, 1.0)
	flood.omni_range = 11.0
	add_child(flood)
	lamp_lights.append({"light": flood, "base": 2.4, "group": "street", "bulb": flood_head})
	lights.append({"light": flood, "shadow": true})
	# power line along the north edge
	var pole_mat := M.wood("power_pole", Color(0.26, 0.2, 0.15))
	var prev := Vector3.ZERO
	for i in 6:
		var pp := Vector3(-50.0 + i * 20.0, 0, -54.0)
		solid_box(pp, Vector3(0.3, 8.0, 0.3), pole_mat)
		_mesh(self, ML.box(Vector3(0.14, 0.14, 2.4)), pole_mat, pp + Vector3(0, 7.5, 0))
		if i > 0:
			for off in [-1.0, 1.0]:
				var wire := _mesh(self, ML.box(Vector3(20.0, 0.03, 0.03)), _mat_tread, (pp + prev) * 0.5 + Vector3(0, 7.45, off))
				wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		prev = pp
