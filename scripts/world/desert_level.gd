extends "res://scripts/world/town_level.gd"
## ATOMIC ACRES: a 1950s civil-defence test town on a desert flat, 72 x 72 m.
## Small and fast: Zombie Survival and Deathmatch only.
##   centre   cul-de-sac turning circle: burnt-out station wagon, test dummies
##   west     YELLOW HOUSE, two storeys, front door on the circle
##   east     MINT HOUSE, two storeys, front door on the circle (faces the yellow one)
##   north    fallout shelter, walk-through, sandbags on the roof
##   middle   evacuation bus slewed across the road: breaks the long sightline
##   south    Tequila Zombie Cafe (supply stop + ammo) and the water tower
## Side yards behind both houses are the flanking lanes. Upstairs windows
## overlook the circle. Coordinates: x east, z south (north is -z).

const D_HALF := 36.0
const D_ROAD := 4.0
const CIRCLE_Z := -10.0
const CIRCLE_R := 10.0
const FH := 3.2          # ground storey height to the top of the upstairs floor
const UH := 2.8          # upstairs wall height
const HW := 11.0         # house size along x
const HD := 9.0          # house size along z
const WT := 0.3          # house wall thickness

const CAFE_GLB := "res://assets/thirdparty/tequila_zombie_cafe/tequila_zombie_cafe.glb"
const SIGN_GLB := "res://assets/thirdparty/everything_must_go_sign/everything_must_go_sign.glb"
const CAFE_POS := Vector3(17, 0, 22)
const UFO_GLB := "res://assets/thirdparty/ufo_crash_site/ufo_crash_site.glb"
const UFO_POS := Vector3(17, 0, -29)

## Each house: {"rect": Rect2, "upper": Node3D} (upper storey + roof, hidden
## in the top-down view while the operator is downstairs or behind it).
var _houses: Array = []
var _mat_sand: Material
var _mat_rock: Material
var _mat_shelter: Material
var _flash: ColorRect

## Navigation is identical on every load (fixed seed): bake once, reuse.
static var _desert_nav: NavigationMesh


func build() -> void:
	seed(5195)   # same town every time
	Terrain.clear()
	_mat_wall = Nature.plaster_material(Color(0.74, 0.64, 0.5))
	_mat_wall_trim = M.solid(Color(0.86, 0.84, 0.78), 0.7)
	_mat_crate = M.wood("crate", Color(0.46, 0.4, 0.28))
	_mat_crate_frame = M.wood("crate_frame", Color(0.34, 0.29, 0.2))
	_mat_sandbag = M.fabric("sandbag", Color(0.6, 0.53, 0.38), 4.0)
	_mat_concrete = M.concrete("barrier", Color(0.62, 0.6, 0.55), 0.6)
	_mat_metal = M.painted_metal("metal_grey", Color(0.36, 0.37, 0.36))
	_mat_asphalt = Nature.asphalt_material(2.5)
	_mat_walk = Nature.sidewalk_material(Color(0.62, 0.6, 0.55))
	_mat_line = M.road_paint("line_yellow", Color(0.85, 0.66, 0.15), 0.7)
	_mat_white = M.road_paint("line_white", Color(0.8, 0.79, 0.74), 0.7)
	_mat_brick = Nature.brick_material(Color(0.55, 0.3, 0.2))
	_mat_roof = Nature.roof_material(Color(0.36, 0.22, 0.17))
	Nature.fade_materials = Nature.fade_materials.filter(func(m): return m == _mat_roof)
	_mat_glass_lit = M.emissive("window_lit", Color(1.0, 0.8, 0.5), 1.4)
	_mat_glass_dark = M.solid(Color(0.06, 0.08, 0.1), 0.15, 0.4)
	_mat_fence = M.wood("picket", Color(0.9, 0.88, 0.82))
	_mat_sand = M.matte("desert_sand", Color(0.78, 0.64, 0.45), 0.97)
	_mat_rock = Nature.rock_material(Color(0.62, 0.38, 0.24))
	_mat_shelter = M.concrete("shelter", Color(0.55, 0.54, 0.5), 0.5)
	FX.ground_surface = "dirt"
	Water.clear()

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)

	_build_desert_ground()
	_house(Vector3(-17, 0, CIRCLE_Z), 1.0, Color(0.93, 0.8, 0.42), "YELLOW HOUSE")
	_house(Vector3(17, 0, CIRCLE_Z), -1.0, Color(0.6, 0.85, 0.74), "MINT HOUSE")
	_build_shelter()
	_build_circle_props()
	_build_cafe()
	_build_water_tower()
	_build_ufo_site()
	_build_yards()
	_build_desert_lamps()
	_build_desert_dressing()
	_build_perimeter()
	_define_mode()
	_bake_navigation()
	seed(Time.get_ticks_usec())


# ================================================================ ground

func _build_desert_ground() -> void:
	var g := _body(Vector3.ZERO)
	_box_shape(g, Vector3(D_HALF * 2.4, 1, D_HALF * 2.4), Vector3(0, -0.5, 0))
	_mesh(g, ML.plane(Vector2(D_HALF * 7, D_HALF * 7)), _mat_sand, Vector3.ZERO)
	# the road in from the south, ending in the turning circle
	var road_len := D_HALF - CIRCLE_Z
	_floor_patch(Vector3(0, 0.008, (D_HALF + CIRCLE_Z) * 0.5), Vector2(D_ROAD * 2, road_len), _mat_asphalt)
	var disc := _mesh(self, ML.cylinder(CIRCLE_R, CIRCLE_R, 0.02, 48), _mat_asphalt, Vector3(0, 0.0, CIRCLE_Z))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var kerb := _mesh(self, ML.cylinder(CIRCLE_R + 1.2, CIRCLE_R + 1.2, 0.012, 48), _mat_walk, Vector3(0, -0.002, CIRCLE_Z))
	kerb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a planted island in the middle of the circle
	var island := _mesh(self, ML.cylinder(2.4, 2.6, 0.18, 32), _mat_walk, Vector3(0, 0.09, CIRCLE_Z))
	island.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var z := CIRCLE_Z + CIRCLE_R + 2.0
	while z < D_HALF - 2.0:
		_floor_patch(Vector3(0, 0.012, z), Vector2(0.16, 2.0), _mat_line)
		z += 4.0
	# sand drifting over the asphalt
	for i in 18:
		var p := Vector3(randf_range(-D_ROAD, D_ROAD), 0.014, randf_range(CIRCLE_Z, D_HALF - 2))
		var s := _floor_patch(p, Vector2(randf_range(1.0, 3.0), randf_range(0.6, 1.6)), M.blot("sand_drift", Color(0.6, 0.48, 0.32, 0.35)))
		s.rotation.y = randf() * TAU


# ================================================================ houses

## A straight wall between two world points on one axis; gaps are [from, to]
## measured from `a` toward `b`.
func _wall_ab(a: Vector3, b: Vector3, h: float, mat: Material, gaps: Array = [], windows: bool = false) -> void:
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var length := absf(b.x - a.x) if along_x else absf(b.z - a.z)
	var reversed := (b.x < a.x) if along_x else (b.z < a.z)
	var origin := b if reversed else a
	var cuts: Array = []
	for g in gaps:
		cuts.append([length - float(g[1]), length - float(g[0])] if reversed else [float(g[0]), float(g[1])])
	_wall_run(origin, along_x, length, h, WT, mat, cuts, windows)


## Two-storey house. s = +1: front door faces east (+x), s = -1: faces west.
## Local u runs toward the front, v along z (mirrored with s, so both houses
## are the same plan turned 180 degrees). A straight stair along the back wall.
func _house(c: Vector3, s: float, paint: Color, label: String) -> void:
	var rect := Rect2(c.x - HW * 0.5, c.z - HD * 0.5, HW, HD)
	_blocked.append(rect.grow(1.5))
	var siding := Nature.siding_material(paint)
	var inner := M.solid(paint.lerp(Color(0.92, 0.9, 0.84), 0.6), 0.9)
	var at := func(u: float, v: float, y: float = 0.0) -> Vector3: return c + Vector3(s * u, y, s * v)
	var hu := HW * 0.5
	var hv := HD * 0.5
	var stair_u0 := -hu + WT * 0.5          # inside of the back wall
	var stair_u1 := stair_u0 + 1.7
	var stair_v_bot := 2.5                  # foot of the stair
	var stair_v_top := -2.5                 # top landing edge
	# ---- ground storey
	var bodies := nav_region.get_child_count()
	var extras := get_child_count()
	_wall_ab(at.call(hu, -hv), at.call(hu, hv), FH, siding, [[hv - 0.9, hv + 0.9]], true)                 # front, door in the middle
	_wall_ab(at.call(-hu, -hv), at.call(-hu, hv), FH, siding, [[hv + 2.7, hv + 4.3]], true)                # back door beside the stair foot
	_wall_ab(at.call(-hu, -hv), at.call(hu, -hv), FH, siding, [], true)
	_wall_ab(at.call(-hu, hv), at.call(hu, hv), FH, siding, [], true)
	_floor_patch(c + Vector3(0, 0.02, 0), Vector2(HW - WT, HD - WT), M.floor_grid("house_floor", Color(0.42, 0.3, 0.2), Color(0.5, 0.36, 0.24), 0.2))
	# porch step and awning over the front door
	solid_box(at.call(hu + 0.9, 0.0), Vector3(1.6, 0.18, 2.4), _mat_walk)
	_mesh(self, ML.box(Vector3(1.6, 0.1, 2.6)), _mat_wall_trim, at.call(hu + 0.85, 0.0, 2.55))
	# downstairs furniture: sofa, kitchen counter, dinner table with dummies
	_furniture(at.call(hu - 2.6, -2.6), Vector3(0.9, 0.85, 2.2), Color(0.55, 0.22, 0.2), 0.0, true, true)
	_furniture(at.call(-hu + 3.6, 3.6), Vector3(3.2, 0.95, 0.7), Color(0.85, 0.85, 0.8))
	_furniture(at.call(0.8, 2.0), Vector3(1.6, 0.76, 1.0), Color(0.5, 0.36, 0.22))
	_mannequin(at.call(0.8, 3.0), PI if s > 0 else 0.0, true)
	_mannequin(at.call(hu - 2.0, -1.2), -PI * 0.5 * s, false)
	# stair: one straight flight from the back door up to the landing
	_stair(at.call((stair_u0 + stair_u1) * 0.5, stair_v_bot), at.call((stair_u0 + stair_u1) * 0.5, stair_v_top), 1.6)
	_interior_probe(c + Vector3(0, FH * 0.5, 0), Vector3(HW - 0.1, FH, HD - 0.1))
	_house_light(c + Vector3(0, FH - 0.4, 0), HW * 0.7)
	_move_into(_storey_node(label + "_ground"), bodies, extras)
	# ---- upper storey (hidden in top-down while below it)
	bodies = nav_region.get_child_count()
	extras = get_child_count()
	var rects := map_rects.size()
	var covers := cover_points.size()
	# floor slab around the stairwell
	var slab_t := 0.25
	var wu0 := -hu + WT * 0.5
	var wu1 := hu - WT * 0.5
	var wv0 := -hv + WT * 0.5
	var wv1 := hv - WT * 0.5
	_slab(at.call(stair_u1, wv0), at.call(wu1, wv1), FH, slab_t, inner)                   # the room
	_slab(at.call(wu0, wv0), at.call(stair_u1, stair_v_top), FH, slab_t, inner)            # landing
	_slab(at.call(wu0, stair_v_bot), at.call(stair_u1, wv1), FH, slab_t, inner)           # over the stair foot
	# railing along the stairwell
	_wall_ab(at.call(stair_u1 + 0.08, stair_v_top, FH), at.call(stair_u1 + 0.08, stair_v_bot, FH), 1.0, _mat_wall_trim)
	# upstairs walls: every side has windows; the front ones overlook the circle
	_wall_ab(at.call(hu, -hv, FH), at.call(hu, hv, FH), UH, siding, [], true)
	_wall_ab(at.call(-hu, -hv, FH), at.call(-hu, hv, FH), UH, siding, [], true)
	_wall_ab(at.call(-hu, -hv, FH), at.call(hu, -hv, FH), UH, siding, [], true)
	_wall_ab(at.call(-hu, hv, FH), at.call(hu, hv, FH), UH, siding, [], true)
	_furniture(at.call(hu - 2.2, 2.6, FH), Vector3(2.0, 0.6, 1.5), Color(0.75, 0.72, 0.66), 0.0, true, true)   # bed
	_furniture(at.call(1.0, -hv + 0.6, FH), Vector3(1.2, 1.0, 0.6), Color(0.45, 0.33, 0.22))                  # dresser
	_mannequin(at.call(hu - 1.0, -1.5, FH), PI * 0.5 * s, false)   # watching the street
	# gable roof, ridge along z
	var roof := MeshInstance3D.new()
	roof.mesh = _gable_mesh(HW + 0.8, HD + 0.8, 1.9)
	roof.material_override = _mat_roof
	roof.position = c + Vector3(0, FH + UH, 0)
	add_child(roof)
	_mesh(self, ML.box(Vector3(HW + 0.5, 0.18, HD + 0.5)), _mat_wall_trim, c + Vector3(0, FH + UH - 0.05, 0))
	_house_light(c + Vector3(0, FH + UH - 0.4, 0), HW * 0.6)
	var upper := _storey_node(label + "_upper")
	_move_into(upper, bodies, extras)
	# the radar and ground cover only describe street level
	map_rects.resize(rects)
	cover_points.resize(covers)
	_houses.append({"rect": rect, "upper": upper})
	# house name on the mailbox by the road
	var mb := solid_box(at.call(hu + 4.0, -hv + 1.0), Vector3(0.14, 1.0, 0.14), _mat_metal)
	_mesh(mb, ML.rbox(Vector3(0.28, 0.24, 0.46)), M.painted_metal("mailbox", paint.darkened(0.25)), Vector3(0, 1.1, 0))


func _storey_node(nm: String) -> Node3D:
	var st := Node3D.new()
	st.name = nm.replace(" ", "")
	nav_region.add_child(st)
	return st


func _move_into(st: Node3D, bodies: int, extras: int) -> void:
	var moved: Array = nav_region.get_children().slice(bodies) + get_children().slice(extras)
	for n in moved:
		if n != st:
			(n as Node).reparent(st, true)


## Floor slab between two corners (any order), top surface at y.
func _slab(a: Vector3, b: Vector3, y: float, t: float, mat: Material) -> void:
	var lo := Vector3(minf(a.x, b.x), 0, minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), 0, maxf(a.z, b.z))
	var size := Vector3(hi.x - lo.x, t, hi.z - lo.z)
	if size.x < 0.05 or size.z < 0.05:
		return
	solid_box(Vector3((lo.x + hi.x) * 0.5, y - t, (lo.z + hi.z) * 0.5), size, mat)


## Straight flight from `bottom` (floor level) to `top` (rises FH), `w` wide.
func _stair(bottom: Vector3, top: Vector3, w: float) -> void:
	var run := Vector2(top.x - bottom.x, top.z - bottom.z).length()
	var length := sqrt(run * run + FH * FH)
	var ang := atan2(FH, run)
	var mid := (bottom + top) * 0.5
	var yaw := atan2(top.x - bottom.x, top.z - bottom.z)
	var b := _body(Vector3(mid.x, FH * 0.5 - 0.125 / cos(ang), mid.z), yaw)
	b.rotation.x = -ang
	_box_shape(b, Vector3(w, 0.25, length), Vector3.ZERO)
	var tread_mat := M.solid(Color(0.32, 0.22, 0.14), 0.8)
	_mesh(b, ML.box(Vector3(w, 0.25, length)), M.wood("stair_wood", Color(0.45, 0.32, 0.2)), Vector3.ZERO)
	for i in 12:
		_mesh(b, ML.box(Vector3(w, 0.03, 0.18)), tread_mat, Vector3(0, 0.14, -length * 0.5 + (i + 0.5) * length / 12.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Gable roof: two slopes and two end triangles, eaves at y = 0, ridge along z.
func _gable_mesh(w: float, d: float, rise: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := w * 0.5
	var hd := d * 0.5
	var l0 := Vector3(-hw, 0, -hd)
	var l1 := Vector3(-hw, 0, hd)
	var r0 := Vector3(hw, 0, -hd)
	var r1 := Vector3(hw, 0, hd)
	var p0 := Vector3(0, rise, -hd)
	var p1 := Vector3(0, rise, hd)
	for t in [[l0, p0, p1], [l0, p1, l1], [r0, r1, p1], [r0, p1, p0], [l0, r0, p0], [l1, p1, r1]]:
		for v in t:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _house_light(p: Vector3, rng_range: float) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = Color(1.0, 0.82, 0.6)
	l.omni_range = rng_range
	l.omni_attenuation = 1.3
	add_child(l)
	lamp_lights.append({"light": l, "base": 1.4, "group": "interior", "flicker": randf() < 0.3})
	lights.append({"light": l, "shadow": false})


## A test-site shop dummy: pale body, painted clothes. Breaks when shot.
func _mannequin(p: Vector3, rot: float, seated: bool) -> void:
	var b := _body(p, rot, "wood")
	var h := 1.25 if seated else 1.8
	_box_shape(b, Vector3(0.5, h, 0.35), Vector3(0, h * 0.5, 0))
	var skin := M.matte("mannequin", Color(0.88, 0.76, 0.62), 0.5)
	var cloth := M.fabric("dummy_" + str(int(p.x * 7.0 + p.z)), Color.from_hsv(randf(), 0.35, 0.75), 5.0)
	var hip := 0.5 if seated else 0.95
	_mesh(b, ML.capsule(0.17, 0.62), cloth, Vector3(0, hip + 0.32, 0))
	_mesh(b, ML.sphere(0.12, false, 14), skin, Vector3(0, hip + 0.78, 0))
	for sx in [-1.0, 1.0]:
		_mesh(b, ML.capsule(0.05, 0.6), skin, Vector3(sx * 0.24, hip + 0.3, 0), Vector3(0, 0, sx * 0.15))
		if seated:
			_mesh(b, ML.capsule(0.07, 0.5), cloth, Vector3(sx * 0.1, hip, -0.22), Vector3(PI * 0.5, 0, 0))
			_mesh(b, ML.capsule(0.06, 0.5), skin, Vector3(sx * 0.1, 0.25, -0.45))
		else:
			_mesh(b, ML.capsule(0.07, 0.95), cloth, Vector3(sx * 0.1, 0.47, 0))
	b.finalize()


# ================================================================ shelter

## Concrete civil-defence shelter: thick walls, a door at each end so it is
## also a covered route between the yards, sandbags on the roof.
func _build_shelter() -> void:
	var c := Vector3(0, 0, -29)
	var w := 10.0
	var d := 5.0
	var h := 2.7
	_blocked.append(Rect2(c.x - w * 0.5 - 1, c.z - d * 0.5 - 1, w + 2, d + 2))
	var t := 0.6
	_wall_run(c + Vector3(-w * 0.5, 0, -d * 0.5), true, w, h, t, _mat_shelter)
	_wall_run(c + Vector3(-w * 0.5, 0, d * 0.5), true, w, h, t, _mat_shelter, [[w * 0.5 - 0.9, w * 0.5 + 0.9]])
	_wall_run(c + Vector3(-w * 0.5, 0, -d * 0.5), false, d, h, t, _mat_shelter, [[d * 0.5 - 0.8, d * 0.5 + 0.8]])
	_wall_run(c + Vector3(w * 0.5, 0, -d * 0.5), false, d, h, t, _mat_shelter, [[d * 0.5 - 0.8, d * 0.5 + 0.8]])
	var roof := _mesh(self, ML.box(Vector3(w + 0.8, 0.45, d + 0.8)), _mat_shelter, c + Vector3(0, h + 0.22, 0))
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_floor_patch(c + Vector3(0, 0.02, 0), Vector2(w - t, d - t), M.floor_grid("shelter_floor", Color(0.3, 0.3, 0.3), Color(0.36, 0.36, 0.36), 0.3))
	for sx in [-3.0, 0.0, 3.0]:
		_mesh(self, ML.rbox(Vector3(2.4, 0.4, 0.8)), _mat_sandbag, c + Vector3(sx, h + 0.65, -1.0))
		_mesh(self, ML.rbox(Vector3(2.4, 0.4, 0.8)), _mat_sandbag, c + Vector3(sx, h + 0.65, 1.1))
	# supplies inside
	rack(c + Vector3(-3.2, 0, -1.6), 0.0, 3.0)
	rack(c + Vector3(3.2, 0, -1.6), 0.0, 3.0)
	crate(c + Vector3(-2.5, 0, 0.9), Vector3(1.0, 0.8, 1.0), 0.2)
	barrel(c + Vector3(3.6, 0, 1.2), Color(0.25, 0.32, 0.25))
	# the yellow-and-black civil-defence sign over the south door
	var face := c + Vector3(0, h + 0.95, d * 0.5 + 0.1)   # stands on the roof edge
	_mesh(self, ML.box(Vector3(3.6, 1.0, 0.08)), M.solid(Color(0.95, 0.78, 0.1), 0.5), face)
	var label := Label3D.new()
	label.text = "FALLOUT SHELTER"
	label.font_size = 80
	label.pixel_size = 0.0055
	label.modulate = Color(0.05, 0.05, 0.05)
	label.outline_size = 0
	label.position = face + Vector3(0, 0, 0.05)
	add_child(label)
	_house_light(c + Vector3(0, h - 0.4, 0), 6.0)


# ================================================================ cul-de-sac

func _build_circle_props() -> void:
	# burnt-out station wagon on the circle, a second car on the far side
	_car(Vector3(4.5, 0, CIRCLE_Z - 3.5), 0.9, Color(0.4, 0.5, 0.45), true)
	_car(Vector3(-5.0, 0, CIRCLE_Z + 4.0), -2.3, Color(0.82, 0.55, 0.45))
	# the bus slewed across the road: no clear lane from the cafe to the shelter
	_bus(Vector3(-0.6, 0, 9.0), PI * 0.5 - 0.35)
	_blocked.append(Rect2(-6.5, 5.0, 12, 8))
	# a crowd of test dummies standing where the blast was meant to land
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		_mannequin(Vector3(cos(a) * 3.4, 0, CIRCLE_Z + sin(a) * 3.4), -a, false)
	sandbags(Vector3(-3.0, 0, 3.0), 2.6, 0.3)
	sandbags(Vector3(3.4, 0, 14.0), 2.6, -0.2)
	barrier(Vector3(6.0, 0, 1.0), 0.4)
	barrier(Vector3(-6.4, 0, 18.0), -0.3)
	_road_sign(Vector3(-5.2, 0, 26.0), PI * 0.25, "TEST\nAREA", Color(0.95, 0.78, 0.1))
	_road_sign(Vector3(5.2, 0, -21.5), 0.0, "DEAD\nEND", Color(0.95, 0.78, 0.1))


# ================================================================ cafe

## Tequila Zombie Cafe (third-party model, local only): the supply stop.
## Front faces west onto the road; the ammo crate sits at its door.
func _build_cafe() -> void:
	var rot := -PI * 0.5
	_blocked.append(Rect2(CAFE_POS.x - 3.0, CAFE_POS.z - 5.0, 8.0, 10.0))
	if ResourceLoader.exists(CAFE_GLB):
		var b := _body(CAFE_POS, rot)
		var inst := (load(CAFE_GLB) as PackedScene).instantiate() as Node3D
		b.add_child(inst)
		_box_shape(b, Vector3(7.86, 7.3, 4.47), Vector3(0.76, 3.65, 0.075))
		# street signs and the vase on its pavement
		_box_shape(b, Vector3(0.4, 3.0, 0.4), Vector3(0.79, 1.5, 3.72))
		_box_shape(b, Vector3(1.3, 0.9, 1.3), Vector3(3.23, 0.45, 3.23))
		_cafe_back()
	else:
		_building(CAFE_POS, 4.5, 8.0, 4.2, _mat_brick, {"w": [0.0, 1.8]}, "", 0.8)
		var lbl := Label3D.new()
		lbl.text = "TEQUILA ZOMBIE CAFE"
		lbl.font_size = 80
		lbl.pixel_size = 0.006
		lbl.modulate = Color(1.0, 0.4, 0.3)
		lbl.position = CAFE_POS + Vector3(-2.45, 3.6, 0)
		lbl.rotation.y = -PI * 0.5
		add_child(lbl)
	# neon glow over the door
	var neon := OmniLight3D.new()
	neon.position = CAFE_POS + Vector3(-3.6, 3.4, 0)
	neon.light_color = Color(1.0, 0.45, 0.6)
	neon.omni_range = 9.0
	add_child(neon)
	lamp_lights.append({"light": neon, "base": 2.0, "group": "street", "flicker": true})
	lights.append({"light": neon, "shadow": false})
	_build_sale_sign(CAFE_POS + Vector3(-6.0, 0, -3.4))
	_dumpster(CAFE_POS + Vector3(1.5, 0, 6.2), 0.0)
	_bench(CAFE_POS + Vector3(-5.2, 0, 3.0), PI * 0.5)


## The cafe model is only its street front: behind it there is nothing. A brick
## block fills its footprint (the collision box) behind the facade, with a flat
## roof, a parapet, a back door and an AC unit, so it reads as a whole building.
func _cafe_back() -> void:
	# footprint in world space (the model faces west, rotated -90 degrees)
	var front_x := CAFE_POS.x - 2.16 + 2.7   # behind the recessed shop and upper windows
	var back_x := CAFE_POS.x + 2.16
	var z0 := CAFE_POS.z + 0.76 - 3.9
	var z1 := CAFE_POS.z + 0.76 + 3.9
	var h := 6.9
	var c := Vector3((front_x + back_x) * 0.5, h * 0.5, (z0 + z1) * 0.5)
	var size := Vector3(back_x - front_x, h, z1 - z0)
	_mesh(self, ML.box(size), _mat_brick, c).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var trim := M.solid(Color(0.3, 0.26, 0.22), 0.8)
	_mesh(self, ML.box(Vector3(size.x + 0.1, 0.12, size.z + 0.1)), M.concrete("cafe_roof", Color(0.32, 0.31, 0.3), 0.6), c + Vector3(0, h * 0.5 + 0.06, 0))
	for e in [[Vector3(back_x, h + 0.3, c.z), Vector3(0.25, 0.6, size.z + 0.25)], [Vector3(c.x, h + 0.3, z0), Vector3(size.x, 0.6, 0.25)], [Vector3(c.x, h + 0.3, z1), Vector3(size.x, 0.6, 0.25)]]:
		_mesh(self, ML.box(e[1]), trim, e[0])
	# back door with a step and a light over it
	_mesh(self, ML.box(Vector3(0.08, 2.1, 1.0)), M.painted_metal("cafe_door", Color(0.25, 0.32, 0.3)), Vector3(back_x + 0.04, 1.05, c.z + 1.2))
	_mesh(self, ML.box(Vector3(0.6, 0.15, 1.4)), M.concrete("cafe_step", Color(0.5, 0.49, 0.47), 0.6), Vector3(back_x + 0.3, 0.07, c.z + 1.2))
	_mesh(self, ML.box(Vector3(0.18, 0.12, 0.3)), M.emissive("cafe_back_lamp", Color(1.0, 0.8, 0.55), 1.5), Vector3(back_x + 0.1, 2.45, c.z + 1.2))
	# AC unit on the back wall and one on the roof
	var ac := M.painted_metal("cafe_ac", Color(0.7, 0.7, 0.68))
	_mesh(self, ML.box(Vector3(0.6, 0.7, 0.9)), ac, Vector3(back_x + 0.32, 3.4, c.z - 1.6))
	_mesh(self, ML.box(Vector3(1.2, 0.8, 1.0)), ac, Vector3(c.x + 0.4, h + 0.4, c.z - 1.0))
	# upper windows on the back so the wall is not blank
	var glass := M.solid(Color(0.12, 0.14, 0.16), 0.2, 0.3)
	for dz in [-2.3, 0.0, 2.3]:
		_mesh(self, ML.box(Vector3(0.06, 1.1, 1.0)), glass, Vector3(back_x + 0.03, 4.9, c.z + dz))
		_mesh(self, ML.box(Vector3(0.1, 0.1, 1.15)), trim, Vector3(back_x + 0.05, 4.3, c.z + dz))


## "EVERYTHING MUST GO" board on two posts by the road, facing west.
func _build_sale_sign(p: Vector3) -> void:
	var b := _body(p)
	_box_shape(b, Vector3(0.2, 2.2, 1.7), Vector3(0, 1.1, 0))
	for sz in [-0.7, 0.7]:
		_mesh(b, ML.box(Vector3(0.1, 2.2, 0.1)), _mat_metal, Vector3(0, 1.1, sz))
	if ResourceLoader.exists(SIGN_GLB):
		var inst := (load(SIGN_GLB) as PackedScene).instantiate() as Node3D
		inst.scale = Vector3.ONE * 0.03
		inst.rotation.y = -PI * 0.5
		inst.position = Vector3(-0.08, 1.45, 0)
		b.add_child(inst)
		# keep the board, drop the rope it hung from in the original scene
		for n in inst.find_children("*", "Node3D", true, false):
			if String(n.name).begins_with("B") or String(n.name).begins_with("Torus"):
				(n as Node3D).visible = false
	else:
		_mesh(b, ML.box(Vector3(0.06, 1.5, 1.5)), M.solid(Color(0.97, 0.95, 0.9), 0.8), Vector3(-0.05, 1.45, 0))
		var lbl := Label3D.new()
		lbl.text = "EVERYTHING\nMUST GO!"
		lbl.font_size = 72
		lbl.pixel_size = 0.005
		lbl.modulate = Color(0.85, 0.25, 0.12)
		lbl.outline_size = 0
		lbl.position = Vector3(-0.09, 1.5, 0)
		lbl.rotation.y = -PI * 0.5
		b.add_child(lbl)


# ================================================================ north-east

## The crash site (third-party model, local only): a saucer down on a strip of
## road, taped off with cones, two police cruisers, a news van and the news
## helicopter overhead. Cars, van and saucer are solid cover.
func _build_ufo_site() -> void:
	if not ResourceLoader.exists(UFO_GLB):
		return
	_blocked.append(Rect2(UFO_POS.x - 11.0, UFO_POS.z - 3.5, 20.0, 7.0))
	var b := _body(UFO_POS)
	b.add_child((load(UFO_GLB) as PackedScene).instantiate())
	# solid footprints measured on the model (x east, z south, from its centre)
	_box_shape(b, Vector3(1.9, 1.5, 4.6), Vector3(-4.5, 0.75, 0.0))     # police cruiser
	_box_shape(b, Vector3(2.6, 1.5, 4.4), Vector3(4.5, 0.75, -0.4))     # police cruiser, slewed
	_box_shape(b, Vector3(5.0, 2.4, 2.0), Vector3(-9.2, 1.2, 0.25))     # news van
	_box_shape(b, Vector3(2.6, 1.2, 2.6), Vector3(-0.4, 0.6, 1.08))     # the saucer
	for c in [Vector3(-4.5, 0, 0.0), Vector3(4.5, 0, -0.4), Vector3(-9.2, 0, 0.25)]:
		_add_cover(UFO_POS + c, Vector3(2.0, 1.4, 4.4), 0.0, b)
	var glow := OmniLight3D.new()   # the saucer's underglow
	glow.position = UFO_POS + Vector3(-0.4, 0.6, 1.08)
	glow.light_color = Color(0.5, 1.0, 0.7)
	glow.omni_range = 7.0
	add_child(glow)
	lamp_lights.append({"light": glow, "base": 1.6, "group": "street", "flicker": true})
	lights.append({"light": glow, "shadow": false})


# ================================================================ south-west

func _build_water_tower() -> void:
	var c := Vector3(-20, 0, 24)
	_blocked.append(Rect2(c.x - 3.5, c.z - 3.5, 7, 7))
	var steel := M.painted_metal("tower_steel", Color(0.82, 0.8, 0.74))
	for sx in [-2.2, 2.2]:
		for sz in [-2.2, 2.2]:
			var leg := solid_box(c + Vector3(sx, 0, sz), Vector3(0.3, 9.0, 0.3), steel)
			leg.rotation.z = -signf(sx) * 0.06
	var tank := _mesh(self, ML.cylinder(3.4, 3.4, 4.0, 28), steel, c + Vector3(0, 11.0, 0))
	tank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mesh(self, ML.cylinder(0.4, 3.6, 1.4, 28), M.painted_metal("tower_cap", Color(0.6, 0.25, 0.18)), c + Vector3(0, 13.7, 0))
	for side in [0.0, PI]:
		var label := Label3D.new()
		label.text = "ATOMIC ACRES"
		label.font_size = 128
		label.pixel_size = 0.009
		label.modulate = Color(0.55, 0.2, 0.15)
		label.outline_size = 0
		label.position = c + Vector3(sin(side) * 3.42, 11.2, cos(side) * 3.42)
		label.rotation.y = side
		add_child(label)
	crate_stack(c + Vector3(4.5, 0, -2.0), 0.3)
	barrel(c + Vector3(-3.8, 0, 3.0), Color(0.7, 0.55, 0.15))
	# an old tank parked out on the range as a test target, sandbagged in
	var panzer_at := Vector3(-22, 0, 12)
	if model_prop("panzer1.glb", panzer_at, 0.6, Vector3(4.01, 1.66, 2.06)):
		_blocked.append(Rect2(panzer_at.x - 3.5, panzer_at.z - 3.5, 7, 7))
		sandbags(panzer_at + Vector3(0, 0, 3.0), 3.0, 0.6)
		sandbags(panzer_at + Vector3(-3.2, 0, -0.8), 2.4, 0.6 + PI * 0.5)


## Picket fences close the back yards; the gaps are the flanking lanes.
func _build_yards() -> void:
	for s in [-1.0, 1.0]:
		var x: float = s * 25.0
		_fence(Vector3(x, 0, -24), Vector3(x, 0, -14))
		_fence(Vector3(x, 0, -6), Vector3(x, 0, 4))
		_fence(Vector3(s * 11.5, 0, 4), Vector3(s * 22.0, 0, 4))
		# clothes line, a shed and the family car in each back yard
		solid_box(Vector3(s * 29, 0, -19), Vector3(2.6, 2.3, 2.0), M.painted_metal("shed", Color(0.6, 0.62, 0.55)), 0.0, false, "metal").finalize()
		# the family car: a Corolla where the model is installed
		if not model_prop("corolla.glb", Vector3(s * 29.5, 0, -2.0), PI * 0.5 + 0.15 * s, Vector3(4.14, 1.38, 1.82)):
			_car(Vector3(s * 29.5, 0, -2.0), 0.15 * s, Color(0.55, 0.65, 0.8) if s < 0 else Color(0.85, 0.75, 0.55))
		for k in 2:
			solid_box(Vector3(s * 28.5, 0, -11.5 + k * 3.5), Vector3(0.08, 2.0, 0.08), _mat_metal)


func _build_desert_lamps() -> void:
	var pole := M.painted_metal("lamp_pole", Color(0.3, 0.3, 0.28))
	var head := M.emissive("street_bulb", Color(1.0, 0.8, 0.5), 3.0)
	var spots := [Vector3(-5.5, 0, 6.0), Vector3(5.5, 0, 20.0), Vector3(-5.5, 0, 30.0)]
	for i in 5:
		var a := TAU * i / 5.0 + 0.6
		spots.append(Vector3(cos(a) * (CIRCLE_R + 1.6), 0, CIRCLE_Z + sin(a) * (CIRCLE_R + 1.6)))
	var i := 0
	for p in spots:
		var b := solid_box(p, Vector3(0.2, 4.8, 0.2), pole)
		var bulb := _mesh(b, ML.sphere(0.22, false, 10), head, Vector3(0, 4.9, 0))
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, 4.6, 0)
		l.light_color = Color(1.0, 0.8, 0.52)
		l.omni_range = 12.0
		l.omni_attenuation = 1.1
		l.light_volumetric_fog_energy = 1.2
		add_child(l)
		lamp_lights.append({"light": l, "base": 2.2, "group": "street", "bulb": bulb, "flicker": i % 4 == 2})
		lights.append({"light": l, "shadow": i % 3 == 0})
		i += 1


## Cacti, rocks and dry tufts across the flat (inside the fence), red mesas beyond.
func _build_desert_dressing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1952
	var cactus := M.matte("cactus", Color(0.3, 0.42, 0.24), 0.8)
	var placed := 0
	for i in 200:
		if placed >= 22:
			break
		var p := Vector3(rng.randf_range(-D_HALF + 3, D_HALF - 3), 0, rng.randf_range(-D_HALF + 3, D_HALF - 3))
		if absf(p.x) < D_ROAD + 2.0 or Vector2(p.x, p.z - CIRCLE_Z).length() < CIRCLE_R + 3.0 or not _free(p, 1.0):
			continue
		if placed % 2 == 0:
			var h := rng.randf_range(1.6, 2.8)
			var b := _body(p, rng.randf() * TAU, "wood")
			_box_shape(b, Vector3(0.36, h, 0.36), Vector3(0, h * 0.5, 0))
			_mesh(b, ML.capsule(0.2, h), cactus, Vector3(0, h * 0.5, 0))
			for sx in [-1.0, 1.0]:
				if rng.randf() < 0.7:
					var ay := rng.randf_range(0.8, h - 0.5)
					_mesh(b, ML.capsule(0.12, 0.5), cactus, Vector3(sx * 0.3, ay, 0), Vector3(0, 0, sx * PI * 0.5))
					_mesh(b, ML.capsule(0.12, 0.6), cactus, Vector3(sx * 0.5, ay + 0.3, 0))
			b.finalize()
		else:
			var rock := _mesh(self, Nature.rock_mesh(rng.randi() % 100), _mat_rock, p, Vector3(0, rng.randf() * TAU, 0), Vector3.ONE * rng.randf_range(0.5, 1.1))
			rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		placed += 1
	# dry tufts
	var tuft := Nature.grass_tuft_mesh(11)
	var mat := Nature.grass_material()
	mat.set_shader_parameter("tip", Color(0.62, 0.55, 0.32))
	mat.set_shader_parameter("dry_tip", Color(0.72, 0.62, 0.4))
	mat.set_shader_parameter("root", Color(0.35, 0.3, 0.18))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tuft
	var xfs: Array = []
	for i in 2600:
		var p := Vector3(rng.randf_range(-D_HALF + 1, D_HALF - 1), 0, rng.randf_range(-D_HALF + 1, D_HALF - 1))
		if absf(p.x) < D_ROAD + 0.4 and p.z > CIRCLE_Z:
			continue
		if Vector2(p.x, p.z - CIRCLE_Z).length() < CIRCLE_R + 1.0 or not _free(p, -0.8):
			continue
		var s := rng.randf_range(0.5, 1.0)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 46.0
	add_child(mmi)
	# mesas on the horizon
	for k in 14:
		var a := TAU * k / 14.0 + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(80.0, 120.0)
		var h := rng.randf_range(10.0, 26.0)
		var r := rng.randf_range(14.0, 30.0)
		var mesa := _mesh(self, ML.cylinder(r * 0.8, r, h, 9), _mat_rock, Vector3(cos(a) * dist, h * 0.5 - 0.5, sin(a) * dist), Vector3(0, rng.randf() * TAU, 0))
		mesa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Chain-link test-range fence (solid for movement and bullets) with warning boards.
func _build_perimeter() -> void:
	var post := M.painted_metal("fence_post", Color(0.4, 0.4, 0.38))
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.55, 0.56, 0.55, 0.35)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_mat.metallic = 0.6
	for s in [-1.0, 1.0]:
		var wall_z := solid_box(Vector3(0, 0, s * D_HALF), Vector3(D_HALF * 2 + 0.4, 3.2, 0.2), mesh_mat)
		var wall_x := solid_box(Vector3(s * D_HALF, 0, 0), Vector3(0.2, 3.2, D_HALF * 2 + 0.4), mesh_mat)
		for w in [wall_z, wall_x]:
			for c in w.get_children():
				if c is MeshInstance3D:
					c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var t := -D_HALF
		while t <= D_HALF:
			_mesh(self, ML.box(Vector3(0.12, 3.4, 0.12)), post, Vector3(t, 1.7, s * D_HALF))
			_mesh(self, ML.box(Vector3(0.12, 3.4, 0.12)), post, Vector3(s * D_HALF, 1.7, t))
			t += 4.0
	for p in [Vector3(-14, 0, D_HALF - 0.3), Vector3(14, 0, -D_HALF + 0.3), Vector3(D_HALF - 0.3, 0, 8), Vector3(-D_HALF + 0.3, 0, -8)]:
		var label := Label3D.new()
		label.text = "DANGER\nNUCLEAR TEST AREA"
		label.font_size = 64
		label.pixel_size = 0.006
		label.modulate = Color(0.9, 0.2, 0.12)
		label.position = p + Vector3(0, 2.0, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		add_child(label)


# ================================================================ modes

func _free(p: Vector3, margin: float = 0.0) -> bool:
	if absf(p.x) > D_HALF - 3 or absf(p.z) > D_HALF - 3:
		return false
	for r in _blocked:
		if (r as Rect2).grow(margin).has_point(Vector2(p.x, p.z)):
			return false
	return true


func _define_mode() -> void:
	enemy_spawns.clear()
	zombie_spawns.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1953
	if mode == "pvp":
		pvp_spawns = [Vector3(0, 0, CIRCLE_Z + 6.5), Vector3(-17, 0, CIRCLE_Z), Vector3(17, 0, CIRCLE_Z),
				Vector3(0, 0, -25), Vector3(-8, 0, 24), Vector3(8, 0, 28), Vector3(-28, 0, -20), Vector3(28, 0, 10)]
		for i in 200:
			if pvp_spawns.size() >= 18:
				break
			var p := Vector3(rng.randf_range(-D_HALF + 5, D_HALF - 5), 0, rng.randf_range(-D_HALF + 5, D_HALF - 5))
			if _free(p, 0.5):
				pvp_spawns.append(p)
		player_spawn = pvp_spawns[0]
		ammo_crates.append(Vector3(0, 0, -24.5))
		ammo_crates.append(CAFE_POS + Vector3(-4.0, 0, 2.0))
		return
	# zombie survival: hold the turning circle, resupply at the cafe
	player_spawn = Vector3(0, 0, CIRCLE_Z + 6.0)
	player_yaw = 0.0
	for i in 400:
		if zombie_spawns.size() >= 50:
			break
		var a := rng.randf() * TAU
		var q := Vector3(cos(a) * rng.randf_range(16.0, 32.0), 0, CIRCLE_Z * 0.3 + sin(a) * rng.randf_range(16.0, 32.0))
		if _free(q, 0.3):
			zombie_spawns.append(q)
	ammo_crates.append(CAFE_POS + Vector3(-4.0, 0, 2.0))
	ammo_crates.append(Vector3(0, 0, -24.5))


func _bake_navigation() -> void:
	if _desert_nav != null:
		nav_region.navigation_mesh = _desert_nav.duplicate()
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
	nm.filter_baking_aabb = AABB(Vector3(-D_HALF, -2, -D_HALF), Vector3(D_HALF * 2.0, 10, D_HALF * 2.0))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)
	_desert_nav = nm.duplicate()


## Top-down view: a house's upper storey and roof vanish while the operator
## is downstairs inside it, or stands where they would hide the operator.
func _process(_delta: float) -> void:
	if _flash != null:
		_flash_tick(_delta)
	if _houses.is_empty():
		return
	var main := get_parent()
	var p = main.get("player") if main != null else null
	var top_down: bool = p != null and is_instance_valid(p) and not bool(p.get("first_person")) \
			and not (main.has_method("killcam_active") and main.killcam_active())
	var cam := get_viewport().get_camera_3d()
	for h in _houses:
		var show := true
		if top_down:
			var pos: Vector3 = p.global_position
			var r: Rect2 = h.rect
			if r.grow(0.4).has_point(Vector2(pos.x, pos.z)):
				show = pos.y > FH - 0.6
			elif cam != null:
				var box := AABB(Vector3(r.position.x, FH, r.position.y), Vector3(r.size.x, UH + 2.0, r.size.y))
				show = not box.intersects_segment(cam.global_position, pos + Vector3.UP * 1.2)
		if (h.upper as Node3D).visible != show:
			(h.upper as Node3D).visible = show


# ================================================================ test flash

## Boss waves: the test shot goes off on the horizon. A white-out that fades
## over a few seconds, a low rumble, a shake. Every peer runs it locally.
func test_flash() -> void:
	if _flash == null:
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		_flash = ColorRect.new()
		_flash.color = Color(1.0, 0.98, 0.92, 0.0)
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_flash)
	_flash.set_meta("t", 0.0)
	var main := get_parent()
	var p = main.get("player") if main != null else null
	if p != null and is_instance_valid(p):
		preload("res://scripts/fx/sfx.gd").play(main, "explosion", p.global_position + Vector3(0, 30, -120), 6.0, 0.4)
		var rig = main.get("camera_rig")
		if rig != null and rig.has_method("add_shake"):
			rig.add_shake(0.6)


func _flash_tick(delta: float) -> void:
	if not _flash.has_meta("t"):
		return
	var t: float = float(_flash.get_meta("t")) + delta
	_flash.set_meta("t", t)
	# instant white, hold a beat, fade out over ~3 s
	_flash.color.a = 0.95 if t < 0.25 else clampf(0.95 * (1.0 - (t - 0.25) / 3.0), 0.0, 1.0)
	if t > 3.4:
		_flash.remove_meta("t")
		_flash.color.a = 0.0
