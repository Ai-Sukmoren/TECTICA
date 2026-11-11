extends "res://scripts/world/level.gd"
## Pinewood valley, 200 x 200 m: dirt roads, a creek with a log bridge,
## dense mixed forest (pines + broadleaf, bushes, rocks, fallen logs, grass),
## the LOGGING CAMP (chapter 1), the RADIO OUTPOST (chapter 2) and two
## helicopter landing zones. Trees and rocks are real cover; bushes conceal.
##
## Coordinates: x east, z south (north is -z).

const Nature = preload("res://scripts/world/nature.gd")
const Terrain = preload("res://scripts/world/terrain.gd")

const HALF := 100.0
const CHUNK := 50.0
const GRASS_CHUNK := 20.0
const TERRAIN_HALF := 130.0   # ground extends past the play area under the tree line
const TERRAIN_STEP := 2.0

var mode := "ch1"            # ch1, ch2, zombie
var night := 0.0             # written by the time-of-day system
var outpost_powered := true

var lz_south := Vector3(0, 0, 86)
var camp := Vector3(30, 0, 22)
var bridge := Vector3.ZERO   # computed from the road / creek crossing
var outpost := Vector3(-30, 0, -56)
var lz_north := Vector3(10, 0, -86)

var roads: Array = []        # Array of PackedVector2Array polylines
var creek := PackedVector2Array()
var clearings: Array = []    # [Vector2 centre, radius, trodden]
var interact_points: Dictionary = {}
## Deathmatch spawn points (open ground spread over the valley).
var pvp_spawns: Array = []
var lamp_lights: Array = []  # {light, base, group}
var fireflies: Array = []
var radio_tower: Node3D
var generator: Node3D

var _tree_grid: Dictionary = {}   # Vector2i -> Array[Vector3(x, z, r)]
var _bush_grid: Dictionary = {}
var _mat_bark: Material
var _mat_rock: Material
var _mat_log: Material
var _mat_plank: Material
var _mat_roof: Material
var _mat_hesco: Material
var _mat_trim: Material      # roof-level timber (fades with the roof)
var _mat_stone: Material     # chimneys (fade with the roof)
var _mat_canvas: Material
## detail vegetation only shown on HIGH / ULTRA
var _dense_nodes: Array = []
var _ground_img: Image
var _ground_tex: ImageTexture


func build() -> void:
	seed(1337)   # same forest every time
	_mat_wall = Nature.concrete_material(Color(0.5, 0.5, 0.47))
	_mat_wall_trim = M.solid(Color(0.2, 0.21, 0.2), 0.8)
	_mat_crate = M.wood("crate", Color(0.46, 0.4, 0.28))
	_mat_crate_frame = M.wood("crate_frame", Color(0.34, 0.29, 0.2))
	_mat_sandbag = M.fabric("sandbag", Color(0.52, 0.47, 0.36), 4.0)
	_mat_concrete = Nature.concrete_material(Color(0.6, 0.6, 0.57))
	_mat_metal = M.painted_metal("metal_grey", Color(0.3, 0.32, 0.33))
	_mat_bark = M.wood("bark", Color(0.27, 0.2, 0.15))
	_mat_rock = Nature.rock_material()
	_mat_log = M.wood("log", Color(0.38, 0.28, 0.18))
	_mat_plank = Nature.plank_material(Color(0.5, 0.37, 0.24))
	_mat_roof = Nature.roof_material(Color(0.27, 0.21, 0.17))
	_mat_hesco = Nature.hesco_material()
	Nature.fade_materials = Nature.fade_materials.filter(func(m): return m == _mat_roof)
	_mat_trim = Nature.fade_material(Color(0.36, 0.26, 0.17), 2.2)
	_mat_stone = Nature.fade_material(Color(0.42, 0.41, 0.38), 1.3, 0.95)
	_mat_canvas = Nature.fade_material(Color(0.33, 0.36, 0.23), 3.0)
	_mat_canvas.set_shader_parameter("rows", 1.1)

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)

	_plan()
	_build_heights()
	_build_ground()
	_build_creek()
	_build_lz(lz_south, false)
	_build_lz(lz_north, true)
	_build_logging_camp()
	_build_outpost()
	_build_ruin(Vector3(-58, 0, 42))
	_build_forest()
	_build_boundary()
	_build_fireflies()
	_define_mode()
	_bake_navigation()
	seed(Time.get_ticks_usec())


# ================================================================ layout plan

func _plan() -> void:
	roads = [
		PackedVector2Array([Vector2(0, 104), Vector2(0, 86), Vector2(5, 66), Vector2(12, 48), Vector2(22, 34), Vector2(30, 22)]),
		PackedVector2Array([Vector2(30, 22), Vector2(18, 12), Vector2(6, 5), Vector2(-3, 0), Vector2(-8, -12),
				Vector2(-16, -28), Vector2(-24, -42), Vector2(-30, -56)]),
		PackedVector2Array([Vector2(-30, -56), Vector2(-22, -70), Vector2(-6, -80), Vector2(10, -86), Vector2(14, -104)]),
	]
	creek = PackedVector2Array([Vector2(-106, 7), Vector2(-70, 1), Vector2(-40, 6), Vector2(-20, 1), Vector2(-5, -4),
			Vector2(20, -9), Vector2(45, -4), Vector2(70, -10), Vector2(106, -5)])
	# Subdivide the centreline before terrain, banks and bridge are built so all
	# systems share the same continuous river path.
	var controls := creek.duplicate()
	creek = PackedVector2Array()
	for i in controls.size() - 1:
		var a := controls[maxi(0, i - 1)]
		var b := controls[i]
		var c := controls[i + 1]
		var d := controls[mini(controls.size() - 1, i + 2)]
		var steps := maxi(2, int(ceil(b.distance_to(c) / 3.0)))
		for j in steps:
			creek.append(b.cubic_interpolate(c, a, d, float(j) / steps))
	creek.append(controls[-1])
	# bridge where road 2 crosses the creek
	var r: PackedVector2Array = roads[1]
	for i in r.size() - 1:
		for j in creek.size() - 1:
			var hit = Geometry2D.segment_intersects_segment(r[i], r[i + 1], creek[j], creek[j + 1])
			if hit != null:
				bridge = Vector3(hit.x, 0, hit.y)
	clearings = [
		[Vector2(lz_south.x, lz_south.z), 13.0, 0.5],
		[Vector2(lz_north.x, lz_north.z), 13.0, 0.5],
		[Vector2(camp.x, camp.z), 23.0, 0.85],
		[Vector2(outpost.x, outpost.z), 25.0, 0.9],
		[Vector2(-58, 42), 10.0, 0.4],
		[Vector2(55, -45), 12.0, 0.1],
		[Vector2(-62, -22), 11.0, 0.1],
		[Vector2(62, 52), 10.0, 0.1],
	]


func _seg_dist(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		var c := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		best = minf(best, c.distance_to(p))
	return best


func road_dist(p: Vector2) -> float:
	var best := INF
	for r in roads:
		best = minf(best, _seg_dist(p, r))
	return best


## Distance from p to the nearest feature that must stay free of trees.
func _open_dist(p: Vector2) -> float:
	var d := road_dist(p) - 3.4
	d = minf(d, _seg_dist(p, creek) - 3.8)
	for c in clearings:
		d = minf(d, p.distance_to(c[0]) - float(c[1]))
	return d


# ================================================================ ground

## Rolling forest hills. Roads, clearings, the creek and every structure sit
## on flat ground; hills rise in the woods between them and climb into ridges
## beyond the map edge.
func _build_heights() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.016
	noise.fractal_octaves = 3
	var n := int(TERRAIN_HALF * 2.0 / TERRAIN_STEP) + 1
	var data := PackedFloat32Array()
	data.resize(n * n)
	for iz in n:
		for ix in n:
			var x := -TERRAIN_HALF + ix * TERRAIN_STEP
			var z := -TERRAIN_HALF + iz * TERRAIN_STEP
			var base := noise.get_noise_2d(x, z) * 0.5 + 0.5
			var mask := smoothstep(3.0, 22.0, _open_dist(Vector2(x, z)))
			var hills := pow(base, 1.25) * 5.5 * mask
			var edge := smoothstep(98.0, TERRAIN_HALF, maxf(absf(x), absf(z))) * (10.0 + 8.0 * base)
			var bank_dist := _seg_dist(Vector2(x, z), creek)
			var bed := -0.48 * (1.0 - smoothstep(0.5, 3.5, bank_dist))
			# Keep the existing bridge crossing level and traversable.
			bed *= smoothstep(2.5, 5.0, Vector2(x, z).distance_to(Vector2(bridge.x, bridge.z)))
			data[iz * n + ix] = hills + edge + bed
	Terrain.set_grid(TERRAIN_HALF, TERRAIN_STEP, n, data)


func ground_y(x: float, z: float) -> float:
	return Terrain.height(x, z)


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, Terrain.height(p.x, p.z), p.z)


func _build_ground() -> void:
	var b := _body(Vector3.ZERO)
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	var tn := Terrain.n
	# heightmap samples are 1 unit apart; scale the shape uniformly by the grid step
	var scaled := PackedFloat32Array()
	scaled.resize(tn * tn)
	for i in tn * tn:
		scaled[i] = Terrain.data[i] / TERRAIN_STEP
	hm.map_width = tn
	hm.map_depth = tn
	hm.map_data = scaled
	cs.shape = hm
	cs.scale = Vector3.ONE * TERRAIN_STEP
	b.add_child(cs)
	# dirt / trodden / mud mask painted from the layout
	var res := 512
	var img := Image.create(res, res, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var px := float(res) / (HALF * 2.0)
	for r in roads:
		for i in r.size() - 1:
			var a: Vector2 = r[i]
			var c: Vector2 = r[i + 1]
			var n := int(a.distance_to(c) / 0.6) + 1
			for k in n + 1:
				_paint(img, a.lerp(c, float(k) / n), 2.9, px, 0, 1.0)
	for c in clearings:
		_paint(img, c[0], float(c[1]) * 0.95, px, 1, float(c[2]))
		_paint(img, c[0], float(c[1]) * 0.45, px, 0, float(c[2]) * 0.6)
	for i in creek.size() - 1:
		var a: Vector2 = creek[i]
		var c: Vector2 = creek[i + 1]
		var n := int(a.distance_to(c) / 0.8) + 1
		for k in n + 1:
			_paint(img, a.lerp(c, float(k) / n), 4.6, px, 2, 1.0)
	var tex := ImageTexture.create_from_image(img)
	_ground_img = img
	_ground_tex = tex
	var mi := MeshInstance3D.new()
	mi.mesh = _terrain_mesh()
	mi.material_override = Nature.ground_material(tex, HALF * 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _terrain_mesh() -> ArrayMesh:
	var n := Terrain.n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var x := -TERRAIN_HALF + ix * TERRAIN_STEP
			var z := -TERRAIN_HALF + iz * TERRAIN_STEP
			st.set_normal(Terrain.normal(x, z))
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, Terrain.data[iz * n + ix], z))
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			# same diagonal as HeightMapShape3D so visuals match collision
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + n)
			st.add_index(i + 1)
			st.add_index(i + n + 1)
			st.add_index(i + n)
	st.generate_tangents()
	return st.commit()


## Soft disc into one channel (max blend).
func _paint(img: Image, c: Vector2, radius: float, px: float, ch: int, value: float) -> void:
	var cx := (c.x + HALF) * px
	var cy := (c.y + HALF) * px
	var r := radius * px
	var x0 := maxi(int(cx - r - 1), 0)
	var x1 := mini(int(cx + r + 1), img.get_width() - 1)
	var y0 := maxi(int(cy - r - 1), 0)
	var y1 := mini(int(cy + r + 1), img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x - cx, y - cy).length() / r
			if d >= 1.0:
				continue
			var v := (1.0 - smoothstep(0.55, 1.0, d)) * value
			var col := img.get_pixel(x, y)
			col[ch] = maxf(col[ch], v)
			img.set_pixel(x, y, col)


# ================================================================ creek + bridge

func _build_creek() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distance_along := 0.0
	var sections: Array = []
	for i in creek.size():
		var center := creek[i]
		if i > 0:
			distance_along += center.distance_to(creek[i - 1])
		var tangent := (creek[mini(i + 1, creek.size() - 1)] - creek[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		var width := 2.6 + 0.24 * sin(distance_along * 0.13) + 0.12 * sin(distance_along * 0.43)
		sections.append({"p": center, "side": side, "width": width, "flow": distance_along})
	for i in sections.size() - 1:
		for lane in 8:
			# Shared cross-sections eliminate overlaps and cracks at river bends.
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var section: Dictionary = sections[i + corner.x]
				var across := float(lane + corner.y) / 8.0
				var point: Vector2 = section.p + section.side * ((across * 2.0 - 1.0) * section.width)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(across, section.flow / 4.0))
				st.add_vertex(Vector3(point.x, 0.025, point.y))
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "RiverSurface"
	mi.mesh = st.commit()
	mi.material_override = Nature.water_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# river stones along the banks
	var stone := ML.sphere(0.5, false, 8)
	for i in 160:
		var t := randf()
		var seg := int(t * (creek.size() - 1))
		var a: Vector2 = creek[seg]
		var c: Vector2 = creek[mini(seg + 1, creek.size() - 1)]
		var p := a.lerp(c, randf())
		var dir := (c - a).normalized()
		var side := Vector2(-dir.y, dir.x) * (2.4 + randf() * 1.6) * (1.0 if randf() < 0.5 else -1.0)
		var q := p + side
		if Vector2(bridge.x, bridge.z).distance_to(q) < 4.0:
			continue
		var s := randf_range(0.25, 0.7)
		_mesh(self, stone, _mat_rock, Vector3(q.x, ground_y(q.x, q.y) + s * 0.15, q.y), Vector3(randf(), randf() * TAU, 0), Vector3(s, s * 0.45, s * 0.8))
	# log bridge across the crossing (visual deck; the creek is wadeable)
	var road_dir := (roads[1][4] as Vector2) - (roads[1][3] as Vector2)
	var yaw := atan2(road_dir.x, road_dir.y)
	var br := Node3D.new()
	br.position = bridge
	br.rotation.y = yaw
	add_child(br)
	for i in 16:
		_mesh(br, ML.cylinder(0.14, 0.14, 4.0, 8), _mat_log, Vector3(0, 0.16, -3.75 + i * 0.5), Vector3(0, 0, PI * 0.5))
	for sx in [-1.0, 1.0]:
		_mesh(br, ML.box(Vector3(0.12, 0.12, 8.4)), _mat_plank, Vector3(sx * 1.9, 0.75, 0))
		for k in 4:
			_mesh(br, ML.box(Vector3(0.12, 0.8, 0.12)), _mat_plank, Vector3(sx * 1.9, 0.4, -3.6 + k * 2.4))


# ================================================================ landing zones

func _build_lz(p: Vector3, flare: bool) -> void:
	var pad := MeshInstance3D.new()
	pad.mesh = ML.cylinder(6.0, 6.0, 0.06, 32)
	pad.material_override = M.concrete("helipad", Color(0.36, 0.37, 0.35), 0.4)
	pad.position = p + Vector3(0, 0.03, 0)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)
	var paint := M.solid(Color(0.9, 0.85, 0.7), 0.8)
	for sx in [-1.0, 1.0]:
		_floor_patch(p + Vector3(sx * 1.2, 0.07, 0), Vector2(0.5, 4.0), paint)
	_floor_patch(p + Vector3(0, 0.07, 0), Vector2(2.4, 0.5), paint)
	for i in 12:
		var a := TAU * i / 12.0
		var l := MeshInstance3D.new()
		l.mesh = ML.box(Vector3(0.15, 0.08, 0.15))
		l.material_override = M.emissive("lz_lamp", Color(1.0, 0.75, 0.3), 2.5)
		l.position = p + Vector3(cos(a) * 6.3, 0.05, sin(a) * 6.3)
		add_child(l)
	# windsock
	var pole := Vector3(p.x + 8.5, 0, p.z - 3.0)
	_mesh(self, ML.cylinder(0.04, 0.05, 4.0, 8), _mat_metal, pole + Vector3(0, 2.0, 0))
	_mesh(self, ML.cylinder(0.12, 0.28, 1.4, 10), M.solid(Color(0.95, 0.45, 0.1), 0.8), pole + Vector3(0.7, 3.8, 0), Vector3(0, 0, PI * 0.5))
	if flare:
		# defensive positions around the extraction pad
		sandbags(p + Vector3(-9, 0, 4), 3.0, 0.9)
		sandbags(p + Vector3(8, 0, 7), 3.0, -0.6)
		sandbags(p + Vector3(-3, 0, 10), 3.0, 0.1)
		crate(p + Vector3(9.5, 0, -4), Vector3(1.2, 1.0, 1.2), 0.3)
		crate_stack(p + Vector3(-10, 0, -5), 0.2)
		barrier(p + Vector3(2, 0, -10), 0.1)


# ================================================================ chapter 1: logging camp

func _wall(origin: Vector3, rot: float, local: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var b := _body(origin + Basis(Vector3.UP, rot) * local, rot)
	_box_shape(b, size, Vector3(0, size.y * 0.5, 0))
	_mesh(b, ML.box(size), mat, Vector3(0, size.y * 0.5, 0))
	return b


## Log cabin: plank walls with a door gap on the south side (local +z),
## gable roof that fades around the player in top-down view.
func _cabin(center: Vector3, w: float, d: float, rot: float, door_w: float = 1.3) -> void:
	var h := 2.5
	var t := 0.24
	var side := (w - door_w) * 0.5
	_wall(center, rot, Vector3(0, 0, -d * 0.5), Vector3(w, h, t), _mat_plank)
	_wall(center, rot, Vector3(-w * 0.5, 0, 0), Vector3(t, h, d), _mat_plank)
	_wall(center, rot, Vector3(w * 0.5, 0, 0), Vector3(t, h, d), _mat_plank)
	_wall(center, rot, Vector3(-w * 0.5 + side * 0.5, 0, d * 0.5), Vector3(side, h, t), _mat_plank)
	_wall(center, rot, Vector3(w * 0.5 - side * 0.5, 0, d * 0.5), Vector3(side, h, t), _mat_plank)
	var root := Node3D.new()
	root.position = center
	root.rotation.y = rot
	add_child(root)
	# horizontal log courses on the outside faces
	for y in range(0, 6):
		for zz in [-d * 0.5 - 0.14, d * 0.5 + 0.14]:
			if zz > 0.0:
				for sx in [-1.0, 1.0]:
					_mesh(root, ML.cylinder(0.13, 0.13, side, 8), _mat_log, Vector3(sx * (w * 0.5 - side * 0.5), 0.2 + y * 0.42, zz), Vector3(0, 0, PI * 0.5))
			else:
				_mesh(root, ML.cylinder(0.13, 0.13, w + 0.3, 8), _mat_log, Vector3(0, 0.2 + y * 0.42, zz), Vector3(0, 0, PI * 0.5))
	# roof: two sloped slabs + ridge
	var pitch := 0.5
	var half_d := d * 0.5 + 0.5
	var slab_len := half_d / cos(pitch)
	for s in [-1.0, 1.0]:
		var slab := MeshInstance3D.new()
		slab.mesh = ML.box(Vector3(w + 0.8, 0.12, slab_len))
		slab.material_override = _mat_roof
		slab.position = Vector3(0, h + tan(pitch) * half_d * 0.5, s * half_d * 0.5)
		slab.rotation.x = s * pitch
		root.add_child(slab)
	_floor_patch(center + Vector3(0, 0.01, 0), Vector2(w - 0.2, d - 0.2), _mat_plank).rotation.y = rot
	_cabin_details(root, w, d, h, door_w, pitch, half_d)
	_room_light(center + Vector3(0, 2.25, 0), rot, maxf(w, d), "interior")


## Everything that turns the box into a cabin: log walls on the gable sides,
## gable ends, ridge beam, eave boards, windows that glow at night, door
## frame + step, chimney and a stone footing. Parts above head height use
## fade materials so they vanish with the roof in top-down view.
func _cabin_details(root: Node3D, w: float, d: float, h: float, door_w: float, pitch: float, half_d: float) -> void:
	var rise := tan(pitch) * half_d
	# log courses on the two side walls, half a course out of step with front / back
	for y in range(0, 6):
		for sx in [-1.0, 1.0]:
			_mesh(root, ML.cylinder(0.13, 0.13, d + 0.56, 10), _mat_log, Vector3(sx * (w * 0.5 + 0.14), 0.41 + y * 0.42 - 0.21, 0), Vector3(PI * 0.5, 0, 0))
	# gable ends
	var gable := SurfaceTool.new()
	gable.begin(Mesh.PRIMITIVE_TRIANGLES)
	gable.set_normal(Vector3.RIGHT)
	for v in [Vector3(0, 0, -half_d), Vector3(0, rise, 0), Vector3(0, 0, half_d)]:
		gable.add_vertex(v)
	var gmesh := gable.commit()
	for sx in [-1.0, 1.0]:
		_mesh(root, gmesh, _mat_trim, Vector3(sx * (w * 0.5 + 0.02), h, 0))
	# ridge beam + eave boards
	_mesh(root, ML.cylinder(0.11, 0.11, w + 1.1, 10), _mat_trim, Vector3(0, h + rise + 0.06, 0), Vector3(0, 0, PI * 0.5))
	for sz in [-1.0, 1.0]:
		_mesh(root, ML.box(Vector3(w + 0.9, 0.18, 0.06)), _mat_trim, Vector3(0, h - 0.02, sz * (half_d + 0.02)))
	# windows on the side walls (warm glass that reads as lit at night)
	var frame := M.solid(Color(0.16, 0.12, 0.09), 0.8)
	var glass := M.emissive("cabin_window", Color(1.0, 0.72, 0.38), 0.55)
	for sx in [-1.0, 1.0]:
		var wx: float = sx * (w * 0.5 + 0.27)
		_mesh(root, ML.box(Vector3(0.08, 0.95, 1.15)), frame, Vector3(wx, 1.45, 0.0))
		_mesh(root, ML.box(Vector3(0.1, 0.74, 0.94)), glass, Vector3(wx, 1.45, 0.0))
		_mesh(root, ML.box(Vector3(0.12, 0.74, 0.05)), frame, Vector3(wx, 1.45, 0.0))
		_mesh(root, ML.box(Vector3(0.12, 0.05, 0.94)), frame, Vector3(wx, 1.45, 0.0))
		_mesh(root, ML.box(Vector3(0.2, 0.06, 1.25)), frame, Vector3(wx + sx * 0.03, 0.95, 0.0))
	# door frame, lintel and a plank step
	for sx in [-1.0, 1.0]:
		_mesh(root, ML.box(Vector3(0.16, 2.2, 0.34)), frame, Vector3(sx * (door_w * 0.5 + 0.06), 1.1, d * 0.5 + 0.02))
	_mesh(root, ML.box(Vector3(door_w + 0.5, 0.2, 0.36)), frame, Vector3(0, 2.25, d * 0.5 + 0.02))
	_mesh(root, ML.box(Vector3(door_w + 0.7, 0.14, 0.8)), _mat_plank, Vector3(0, 0.07, d * 0.5 + 0.55))
	# stone footing
	for sz in [-1.0, 1.0]:
		_mesh(root, ML.box(Vector3(w + 0.7, 0.26, 0.16)), _mat_rock, Vector3(0, 0.1, sz * (d * 0.5 + 0.3)))
	for sx in [-1.0, 1.0]:
		_mesh(root, ML.box(Vector3(0.16, 0.26, d + 0.7)), _mat_rock, Vector3(sx * (w * 0.5 + 0.3), 0.1, 0))
	# fieldstone chimney through the back slope
	_mesh(root, ML.box(Vector3(0.7, h + rise + 0.5, 0.7)), _mat_stone, Vector3(w * 0.28, (h + rise + 0.5) * 0.5, -d * 0.5 - 0.2))
	_mesh(root, ML.box(Vector3(0.86, 0.14, 0.86)), _mat_stone, Vector3(w * 0.28, h + rise + 0.55, -d * 0.5 - 0.2))


func _log_pile(p: Vector3, rot: float, count: int) -> void:
	var b := _body(p, rot, "log")
	var ln := 4.2
	var rows := [[0.0, -0.36], [0.0, 0.0], [0.0, 0.36], [0.31, -0.18], [0.31, 0.18], [0.6, 0.0]]
	var hgt := 0.0
	for i in mini(count, rows.size()):
		var r: Array = rows[i]
		_mesh(b, ML.cylinder(0.19, 0.19, ln, 10), _mat_log, Vector3(0, 0.19 + r[0], r[1]), Vector3(0, 0, PI * 0.5))
		for sx in [-1.0, 1.0]:
			_mesh(b, ML.cylinder(0.17, 0.17, 0.02, 10), M.wood("logend", Color(0.62, 0.5, 0.32)), Vector3(sx * ln * 0.5, 0.19 + r[0], r[1]), Vector3(0, 0, PI * 0.5))
		hgt = maxf(hgt, 0.38 + r[0])
	_box_shape(b, Vector3(ln, hgt, 1.15), Vector3(0, hgt * 0.5, 0))
	if hgt <= 1.25:
		_add_cover(p, Vector3(ln, hgt, 1.15), rot, b)
	b.finalize()


## Shaded ceiling fixtures illuminate rooms even during the day.
func _room_light(pos: Vector3, yaw: float, span: float, group: String, color: Color = Color(1.0, 0.83, 0.62)) -> void:
	var housing := _mesh(self, ML.box(Vector3(0.85, 0.10, 0.28)), _mat_metal, pos, Vector3(0, yaw, 0))
	housing.name = "RoomFixture"
	var bulb := _mesh(self, ML.box(Vector3(0.72, 0.025, 0.20)), M.emissive("room_" + color.to_html(), color, 2.8), pos + Vector3(0, -0.065, 0), Vector3(0, yaw, 0))
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.name = "RoomLight"
	light.position = pos + Vector3(0, -0.22, 0)
	light.light_color = color
	light.light_energy = 2.3
	light.omni_range = span * 0.75 + 1.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = true
	light.light_size = 0.18
	light.light_volumetric_fog_energy = 0.15
	light.distance_fade_enabled = true
	light.distance_fade_begin = 38.0
	light.distance_fade_length = 12.0
	add_child(light)
	lamp_lights.append({"light": light, "base": 2.3, "group": group, "bulb": bulb})
	lights.append({"light": light, "shadow": true})


func _lamp_post(p: Vector3, group: String, color: Color = Color(1.0, 0.78, 0.5)) -> void:
	_mesh(self, ML.cylinder(0.07, 0.09, 3.6, 8), _mat_plank, p + Vector3(0, 1.8, 0))
	_mesh(self, ML.box(Vector3(0.7, 0.06, 0.06)), _mat_plank, p + Vector3(0.3, 3.5, 0))
	var bulb := MeshInstance3D.new()
	bulb.mesh = ML.sphere(0.1, false, 8)
	bulb.material_override = M.emissive("bulb_" + color.to_html(), color, 4.0)
	bulb.position = p + Vector3(0.6, 3.35, 0)
	add_child(bulb)
	var l := OmniLight3D.new()
	l.position = p + Vector3(0.6, 3.2, 0)
	l.light_color = color
	l.omni_range = 11.0
	l.omni_attenuation = 1.3
	l.light_volumetric_fog_energy = 1.5
	add_child(l)
	lamp_lights.append({"light": l, "base": 1.6, "group": group, "bulb": bulb})
	lights.append({"light": l, "shadow": false})


func _campfire(p: Vector3) -> void:
	for i in 9:
		var a := TAU * i / 9.0
		_mesh(self, ML.sphere(0.16, false, 8), _mat_rock, p + Vector3(cos(a) * 0.65, 0.08, sin(a) * 0.65), Vector3.ZERO, Vector3(1, 0.6, 1))
	for i in 4:
		_mesh(self, ML.cylinder(0.07, 0.07, 0.9, 6), _mat_log, p + Vector3(0, 0.12, 0), Vector3(0.3, i * PI * 0.5, PI * 0.5 - 0.35))
	var fire := CPUParticles3D.new()
	fire.amount = 40
	fire.lifetime = 0.9
	fire.mesh = ML.sphere(0.12, false, 6)
	fire.material_override = M.glow(Color(1.0, 0.5, 0.15, 0.85))
	fire.direction = Vector3.UP
	fire.spread = 18.0
	fire.initial_velocity_min = 0.6
	fire.initial_velocity_max = 1.4
	fire.gravity = Vector3(0, 0.5, 0)
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.2
	fire.scale_amount_curve = Curve.new()
	fire.scale_amount_curve.add_point(Vector2(0, 1))
	fire.scale_amount_curve.add_point(Vector2(1, 0))
	fire.position = p + Vector3(0, 0.2, 0)
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fire)
	var l := OmniLight3D.new()
	l.position = p + Vector3(0, 0.9, 0)
	l.light_color = Color(1.0, 0.55, 0.22)
	l.omni_range = 9.0
	l.shadow_enabled = true
	add_child(l)
	lamp_lights.append({"light": l, "base": 2.2, "group": "fire", "flicker": true})
	lights.append({"light": l, "shadow": true})
	# sitting logs
	for a in [0.4, 2.3, 4.2]:
		var q := p + Vector3(cos(a) * 2.4, 0, sin(a) * 2.4)
		_mesh(self, ML.cylinder(0.22, 0.22, 1.6, 8), _mat_log, q + Vector3(0, 0.22, 0), Vector3(0, -a, PI * 0.5))


func _watchtower(p: Vector3, rot: float, searchlight: bool) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = rot
	add_child(root)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh(root, ML.box(Vector3(0.18, 4.6, 0.18)), _mat_plank, Vector3(sx * 1.1, 2.3, sz * 1.1))
			var post := _body(p + Basis(Vector3.UP, rot) * Vector3(sx * 1.1, 0, sz * 1.1), rot)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.22, 4.6, 0.22)
			cs.shape = bs
			cs.position.y = 2.3
			post.add_child(cs)
	_mesh(root, ML.box(Vector3(2.7, 0.14, 2.7)), _mat_plank, Vector3(0, 3.4, 0))
	# cross bracing on every side, and a ladder up the front
	for k in 4:
		var bb := Basis(Vector3.UP, k * PI * 0.5)
		for dz in [-1.0, 1.0]:
			_mesh(root, ML.box(Vector3(0.09, 3.85, 0.07)), _mat_plank, bb * Vector3(0, 1.7, 1.12), Vector3(0, k * PI * 0.5, dz * 0.6))
		_mesh(root, ML.box(Vector3(2.3, 0.1, 0.08)), _mat_plank, bb * Vector3(0, 0.35, 1.12), Vector3(0, k * PI * 0.5, 0))
	for sx in [-1.0, 1.0]:
		_mesh(root, ML.box(Vector3(0.07, 3.5, 0.07)), _mat_plank, Vector3(sx * 0.27, 1.72, 1.36), Vector3(0.09, 0, 0))
	for i in 9:
		_mesh(root, ML.cylinder(0.022, 0.022, 0.54, 8), _mat_log, Vector3(0, 0.35 + i * 0.36, 1.5 - i * 0.033), Vector3(0, 0, PI * 0.5))
	for k in 4:
		var b := Basis(Vector3.UP, k * PI * 0.5)
		_mesh(root, ML.box(Vector3(2.7, 0.9, 0.08)), _mat_plank, b * Vector3(0, 3.9, 1.33), Vector3(0, k * PI * 0.5, 0))
	var roof := MeshInstance3D.new()
	roof.mesh = ML.cylinder(0.0, 2.2, 1.0, 4)
	roof.material_override = _mat_roof
	roof.position = Vector3(0, 5.1, 0)
	roof.rotation.y = PI * 0.25
	root.add_child(roof)
	_room_light(p + Vector3(0, 4.55, 0), rot, 3.0, "interior")
	if searchlight:
		var s := SpotLight3D.new()
		s.position = Vector3(0, 4.3, 0)
		s.spot_range = 34.0
		s.spot_angle = 11.0
		s.light_energy = 6.0
		s.light_color = Color(0.9, 0.95, 1.0)
		s.light_volumetric_fog_energy = 3.0
		s.shadow_enabled = true
		s.rotation.x = -0.32
		root.add_child(s)
		lamp_lights.append({"light": s, "base": 6.0, "group": "outpost", "sweep": true})


func _build_logging_camp() -> void:
	var c := camp
	_cabin(c + Vector3(-9, 0, -8), 7.0, 5.5, 0.2)
	_cabin(c + Vector3(10, 0, -7), 6.0, 5.0, -0.3)
	_cabin(c + Vector3(9, 0, 10), 8.0, 5.0, PI + 0.1)
	# intel laptop inside the main cabin
	var intel_pos := c + Vector3(-9, 0, -8) + Basis(Vector3.UP, 0.2) * Vector3(1.6, 0, -1.2)
	var desk_b := solid_box(intel_pos, Vector3(1.4, 0.76, 0.7), M.wood("table", Color(0.35, 0.27, 0.18)), 0.2, false, "desk")
	_mesh(desk_b, ML.box(Vector3(0.4, 0.02, 0.28)), M.solid(Color(0.1, 0.1, 0.1), 0.4), Vector3(0, 0.78, 0))
	_mesh(desk_b, ML.box(Vector3(0.4, 0.26, 0.02)), M.emissive("laptop", Color(0.3, 0.85, 0.6), 2.0), Vector3(0, 0.92, -0.13), Vector3(-0.25, 0, 0))
	desk_b.finalize()
	interact_points["intel"] = {"pos": intel_pos + Basis(Vector3.UP, 0.2) * Vector3(0, 0, 0.9), "radius": 1.6,
			"label": "DOWNLOAD INTEL", "node": desk_b}
	# sawmill shed: open posts + roof, saw bench, log piles
	var s := c + Vector3(-11, 0, 9)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_wall(s, 0.1, Vector3(sx * 3.8, 0, sz * 2.8), Vector3(0.22, 3.0, 0.22), _mat_plank)
	var shed_roof := MeshInstance3D.new()
	shed_roof.mesh = ML.box(Vector3(8.6, 0.12, 6.6))
	shed_roof.material_override = _mat_roof
	shed_roof.position = s + Vector3(0, 3.05, 0)
	shed_roof.rotation = Vector3(0.12, 0.1, 0)
	add_child(shed_roof)
	_room_light(s + Vector3(0, 2.8, 0), 0.1, 8.0, "interior")
	var bench := solid_box(s + Vector3(0, 0, 0), Vector3(4.0, 0.85, 1.0), _mat_plank, 0.1, true, "wood")
	_mesh(bench, ML.cylinder(0.45, 0.45, 0.03, 20), M.solid(Color(0.6, 0.62, 0.64), 0.3, 0.8), Vector3(0.6, 0.9, 0), Vector3(PI * 0.5, 0, 0))
	bench.finalize()
	_log_pile(c + Vector3(-17, 0, 0), 0.4, 6)
	_log_pile(c + Vector3(0, 0, 15), 0.0, 5)
	_log_pile(c + Vector3(17, 0, 2), 1.4, 6)
	_log_pile(c + Vector3(-4, 0, -16), -0.2, 4)
	_campfire(c)
	vehicle(c + Vector3(-1, 0, -13.5), 1.25)
	crate(c + Vector3(4, 0, -2), Vector3(1.2, 1.0, 1.2), 0.3)
	crate(c + Vector3(-5, 0, 4), Vector3(1.0, 0.8, 1.4), -0.2)
	crate_stack(c + Vector3(15, 0, -13), 0.2)
	crate(c + Vector3(13, 0, -15.5), Vector3(1.2, 1.0, 1.2), 0.1)
	for q in [c + Vector3(17, 0, -10), c + Vector3(17.7, 0, -10.6)]:
		barrel(q, Color(0.55, 0.2, 0.12))
	barrel(c + Vector3(16.6, 0, -11.4), Color(0.28, 0.32, 0.2))
	sandbags(c + Vector3(-5, 0, 17), 3.0, 0.6)
	sandbags(c + Vector3(-15, 0, -12), 2.5, -0.5)
	_watchtower(c + Vector3(-16, 0, -14), 0.3, false)
	for q in [Vector3(-14, 0, 6), Vector3(6, 0, -12), Vector3(14, 0, 8), Vector3(-2, 0, 12)]:
		_lamp_post(c + q, "camp")
	ammo_crates.append(c + Vector3(2, 0, -5))


# ================================================================ chapter 2: radio outpost

func _hesco_line(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var ln := dir.length()
	var rot := atan2(dir.x, dir.z) + PI * 0.5
	var mid := (a + b) * 0.5
	var bdy := _body(mid, rot, "hesco")
	var h := 1.45
	_box_shape(bdy, Vector3(ln, h, 1.1), Vector3(0, h * 0.5, 0))
	var n := maxi(1, int(round(ln / 1.1)))
	var unit := ln / n
	var wire := M.solid(Color(0.25, 0.26, 0.24), 0.6, 0.6)
	for i in n:
		var x := -ln * 0.5 + unit * (i + 0.5)
		_mesh(bdy, ML.box(Vector3(unit - 0.04, h, 1.08)), _mat_hesco, Vector3(x, h * 0.5, 0))
		for sx in [-0.5, 0.5]:
			_mesh(bdy, ML.box(Vector3(0.03, h + 0.02, 1.12)), wire, Vector3(x + sx * unit, h * 0.5, 0))
		_mesh(bdy, ML.box(Vector3(unit, 0.03, 1.12)), wire, Vector3(x, h * 0.66, 0))
	_add_cover(mid, Vector3(ln, h, 1.1), rot, bdy)
	bdy.finalize()


func _tent(p: Vector3, rot: float) -> void:
	var b := _body(p, rot)
	_box_shape(b, Vector3(4.2, 2.2, 3.2), Vector3(0, 1.1, 0))
	var prism := MeshInstance3D.new()
	prism.mesh = ML.cylinder(1.9, 1.9, 4.2, 3)
	prism.material_override = _mat_canvas
	prism.position = Vector3(0, 0.95, 0)
	prism.rotation = Vector3(0, 0, PI * 0.5)
	prism.scale = Vector3(1, 1, 0.9)
	b.add_child(prism)
	# ridge poles, guy ropes with pegs, and a darker door flap
	var rope := M.solid(Color(0.62, 0.58, 0.45), 0.9)
	for sx in [-1.0, 1.0]:
		_mesh(b, ML.cylinder(0.035, 0.035, 2.0, 8), _mat_log, Vector3(sx * 2.12, 1.0, 0))
		for sz in [-1.0, 1.0]:
			_mesh(b, ML.cylinder(0.012, 0.012, 2.75, 6), rope, Vector3(sx * 2.9, 0.98, sz * 0.75), Vector3(sz * 0.36, 0, sx * -0.72))
			_mesh(b, ML.cylinder(0.02, 0.012, 0.26, 6), _mat_log, Vector3(sx * 3.72, 0.08, sz * 1.42), Vector3(0, 0, sx * 0.4))
	_mesh(b, ML.box(Vector3(0.04, 1.5, 1.1)), M.fabric("tent_flap", Color(0.2, 0.22, 0.15), 5.0), Vector3(2.11, 0.75, 0.0))
	_room_light(p + Basis(Vector3.UP, rot) * Vector3(0, 1.9, 1.9), rot, 3.0, "outpost_interior")


func _build_outpost() -> void:
	var o := outpost
	# HESCO perimeter 38 x 34 with a south gate (road in) and north-east gate (road out)
	var hx := 19.0
	var hz := 17.0
	var sw := o + Vector3(-hx, 0, hz)
	var se := o + Vector3(hx, 0, hz)
	var nw := o + Vector3(-hx, 0, -hz)
	var ne := o + Vector3(hx, 0, -hz)
	# gates: south between x = +2 .. +7 (road arrives from the south-east), north-east corner gap
	_hesco_line(sw, o + Vector3(3.0, 0, hz))
	_hesco_line(o + Vector3(10.5, 0, hz), se)
	_hesco_line(se, o + Vector3(hx, 0, -hz + 7.0))
	_hesco_line(nw, sw)
	_hesco_line(nw, o + Vector3(hx - 7.0, 0, -hz))
	_hesco_line(o + Vector3(hx, 0, -hz + 2.0), o + Vector3(hx, 0, -hz + 0.6))
	# radio tower
	radio_tower = Node3D.new()
	radio_tower.position = o + Vector3(-9, 0, -8)
	add_child(radio_tower)
	var steel := M.painted_metal("tower", Color(0.62, 0.62, 0.6))
	var tower_h := 20.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh(radio_tower, ML.box(Vector3(0.12, tower_h, 0.12)), steel, Vector3(sx * 0.5, tower_h * 0.5, sz * 0.5),
					Vector3(sz * 0.045, 0, -sx * 0.045))
	for k in 9:
		var y := 1.2 + k * 2.1
		var wdt := 1.9 - y * 0.085
		for side in 4:
			var bb := Basis(Vector3.UP, side * PI * 0.5)
			_mesh(radio_tower, ML.box(Vector3(wdt, 0.06, 0.06)), steel, bb * Vector3(0, y, wdt * 0.5), Vector3(0, side * PI * 0.5, 0))
			_mesh(radio_tower, ML.box(Vector3(wdt * 1.35, 0.05, 0.05)), steel, bb * Vector3(0, y + 1.05, wdt * 0.5), Vector3(0, side * PI * 0.5, 0.62))
	_mesh(radio_tower, ML.cylinder(0.6, 0.6, 0.12, 16), M.solid(Color(0.8, 0.8, 0.78), 0.4), Vector3(0.3, tower_h - 3.0, 0.6), Vector3(PI * 0.5, 0.4, 0))
	_mesh(radio_tower, ML.cylinder(0.03, 0.05, 4.0, 6), steel, Vector3(0, tower_h + 2.0, 0))
	var beacon := OmniLight3D.new()
	beacon.position = Vector3(0, tower_h + 4.1, 0)
	beacon.light_color = Color(1.0, 0.1, 0.05)
	beacon.omni_range = 6.0
	radio_tower.add_child(beacon)
	var bulb := MeshInstance3D.new()
	bulb.mesh = ML.sphere(0.14, false, 8)
	bulb.material_override = M.emissive("beacon", Color(1, 0.1, 0.05), 6.0)
	bulb.position = beacon.position
	radio_tower.add_child(bulb)
	lamp_lights.append({"light": beacon, "base": 3.0, "group": "beacon", "bulb": bulb, "blink": true})
	var base := _body(radio_tower.position)
	_box_shape(base, Vector3(2.2, 3.0, 2.2), Vector3(0, 1.5, 0))
	interact_points["tower"] = {"pos": radio_tower.position + Vector3(0, 0, 1.9), "radius": 1.7, "label": "PLANT CHARGE", "node": radio_tower}
	# generator (powers the floodlights + searchlight)
	var g := o + Vector3(9, 0, -6)
	var gb := solid_box(g, Vector3(2.4, 1.4, 1.2), M.painted_metal("generator", Color(0.32, 0.38, 0.25)), 0.0, true)
	_mesh(gb, ML.box(Vector3(0.6, 1.1, 1.0)), M.solid(Color(0.12, 0.12, 0.12), 0.5, 0.6), Vector3(1.0, 0.75, 0))
	_mesh(gb, ML.cylinder(0.07, 0.07, 0.9, 8), _mat_metal, Vector3(-0.8, 1.8, 0.3))
	_mesh(gb, ML.cylinder(0.45, 0.45, 1.6, 12), M.painted_metal("fueltank", Color(0.5, 0.15, 0.1)), Vector3(0, 0.45, -1.2), Vector3(0, 0, PI * 0.5))
	generator = gb
	interact_points["generator"] = {"pos": g + Vector3(0, 0, 1.3), "radius": 1.7, "label": "PLANT CHARGE", "node": gb}
	# comms bunker (concrete)
	var bk := o + Vector3(-6, 0, 6)
	var t := 0.4
	_wall(bk, 0.0, Vector3(0, 0, -2.6), Vector3(7.0, 2.4, t), _mat_wall)
	_wall(bk, 0.0, Vector3(-3.5, 0, 0), Vector3(t, 2.4, 5.2), _mat_wall)
	_wall(bk, 0.0, Vector3(3.5, 0, 0), Vector3(t, 2.4, 5.2), _mat_wall)
	_wall(bk, 0.0, Vector3(-2.3, 0, 2.6), Vector3(2.8, 2.4, t), _mat_wall)
	_wall(bk, 0.0, Vector3(2.3, 0, 2.6), Vector3(2.8, 2.4, t), _mat_wall)
	for sx in [-1.0, 1.0]:
		_mesh(self, ML.box(Vector3(0.12, 2.3, 0.5)), _mat_metal, bk + Vector3(sx * 0.9, 1.15, 2.6))
	_mesh(self, ML.box(Vector3(1.92, 0.14, 0.5)), _mat_metal, bk + Vector3(0, 2.3, 2.6))
	var slab := MeshInstance3D.new()
	slab.mesh = ML.box(Vector3(7.6, 0.3, 5.8))
	slab.material_override = Nature.fade_material(Color(0.4, 0.41, 0.4), 1.0, 0.9)
	slab.position = bk + Vector3(0, 2.55, 0)
	add_child(slab)
	_room_light(bk + Vector3(0, 2.25, 0), 0.0, 7.0, "outpost_interior", Color(0.78, 0.88, 1.0))
	desk(bk + Vector3(-1.5, 0, -1.6), 0.0)
	desk(bk + Vector3(1.6, 0, -1.6), 0.0)
	rack(bk + Vector3(3.0, 0, 0.6), PI * 0.5, 2.4)
	# tents, containers, sandbag nests, vehicles, crates, fuel barrels
	_tent(o + Vector3(8, 0, 8), 0.0)
	_tent(o + Vector3(13, 0, 1), PI * 0.5)
	container(o + Vector3(-14, 0, 7), 0.0, Color(0.3, 0.35, 0.25))
	container(o + Vector3(1, 0, -13), PI * 0.5, Color(0.42, 0.24, 0.16))
	vehicle(o + Vector3(4, 0, 12.5), PI * 0.5 + 0.1)
	sandbags(o + Vector3(-1, 0, 2), 3.0, 0.0)
	sandbags(o + Vector3(-10, 0, -1), 2.5, 1.2)
	barrier(o + Vector3(6, 0, -1), 0.2)
	barrier(o + Vector3(-15, 0, -8), 1.4)
	crate(o + Vector3(-4, 0, -6), Vector3(1.2, 1.0, 1.2), 0.2)
	crate_stack(o + Vector3(14, 0, -10), 0.1)
	crate(o + Vector3(-12, 0, 13), Vector3(2.2, 1.0, 1.2), 0.0)
	for q in [Vector3(11.5, 0, -8.2), Vector3(12.2, 0, -7.5), Vector3(12.0, 0, -9.1)]:
		barrel(o + q, Color(0.55, 0.2, 0.12))
	_watchtower(o + Vector3(15, 0, 13), PI * 0.25, true)
	_watchtower(o + Vector3(-16, 0, -14), 0.0, false)
	# floodlight poles at the corners (powered by the generator)
	for q in [Vector3(-17, 0, 15), Vector3(17, 0, -15), Vector3(-17, 0, -15), Vector3(0, 0, 0)]:
		var p: Vector3 = o + q
		_mesh(self, ML.cylinder(0.08, 0.1, 5.0, 8), _mat_metal, p + Vector3(0, 2.5, 0))
		var fl := SpotLight3D.new()
		fl.position = p + Vector3(0, 5.0, 0)
		fl.light_color = Color(1.0, 0.95, 0.85)
		fl.spot_range = 22.0
		fl.spot_angle = 50.0
		fl.light_energy = 2.4
		fl.light_volumetric_fog_energy = 1.2
		add_child(fl)
		var inward: Vector3 = (o - p)
		inward.y = 0.0
		if inward.length() < 0.5:
			inward = Vector3(0, 0, 1)
		fl.look_at(fl.position + inward.normalized() * 1.0 + Vector3(0, -2.2, 0), Vector3.UP)
		var head := MeshInstance3D.new()
		head.mesh = ML.box(Vector3(0.5, 0.3, 0.3))
		head.material_override = M.emissive("flood", Color(1.0, 0.95, 0.8), 3.0)
		head.position = fl.position
		add_child(head)
		lamp_lights.append({"light": fl, "base": 2.4, "group": "outpost", "bulb": head})
		lights.append({"light": fl, "shadow": false})
	ammo_crates.append(o + Vector3(-6, 0, 10))


func _build_ruin(p: Vector3) -> void:
	## Burned-out hunter's cabin with a supply cache.
	_room_light(p + Vector3(1.8, 1.65, -0.8), 0.5, 4.0, "interior")
	_wall(p, 0.5, Vector3(0, 0, -2.2), Vector3(5.0, 1.4, 0.24), _mat_log)
	_wall(p, 0.5, Vector3(-2.5, 0, 0), Vector3(0.24, 0.9, 4.4), _mat_log)
	_wall(p, 0.5, Vector3(2.5, 0, -0.8), Vector3(0.24, 1.8, 2.8), _mat_log)
	crate(p + Vector3(0.5, 0, 0.3), Vector3(1.0, 0.8, 1.0), 0.4)
	ammo_crates.append(p + Vector3(-1.0, 0, 1.0))


# ================================================================ forest

func _cell(x: float, z: float, size: float) -> Vector2i:
	return Vector2i(floori(x / size), floori(z / size))


func _build_forest() -> void:
	var pine_crown := Nature.pine_crown_mesh()
	var broad_crown := Nature.broad_crown_mesh()
	_burn_rng(4)   # the old crown mesh drew 4 values; keeps the forest layout unchanged
	var trunk := Nature.trunk_mesh()
	var pine_mat := Nature.canopy_material(Color(0.1, 0.21, 0.1), 0.025, Vector3(0, 0.5, 0), 0.45, 3.0, 0.47, 0.19)
	var broad_mat := Nature.canopy_material(Color(0.2, 0.35, 0.08), 0.04, Vector3(0, 0.72, 0), 0.65, 2.4, 0.42, 0.1)
	var bush_mat := Nature.canopy_material(Color(0.17, 0.31, 0.08), 0.06, Vector3(0, 0.3, 0), 0.6, 3.2, 0.4, 0.16)
	bush_mat.set_shader_parameter("fade_min_h", 100.0)
	# chunked instance lists
	var chunks := {}   # Vector2i -> {pine_t, pine_c, broad_t, broad_c, bush, shapes}
	var spacing := 4.3
	var n := int(HALF * 2.0 / spacing)
	var big_cover := 0
	for ix in n:
		for iz in n:
			if randf() > 0.68:
				continue
			var x := -HALF + (ix + randf_range(0.15, 0.85)) * spacing
			var z := -HALF + (iz + randf_range(0.15, 0.85)) * spacing
			var p2 := Vector2(x, z)
			var od := _open_dist(p2)
			if od < 0.6:
				continue
			# thinner forest right at the edges of clearings and roads
			if od < 4.0 and randf() < 0.45:
				continue
			var ck := _cell(x, z, CHUNK)
			if not chunks.has(ck):
				chunks[ck] = {"pine_t": [], "pine_c": [], "broad_t": [], "broad_c": [], "shapes": []}
			var ch: Dictionary = chunks[ck]
			var pine := randf() < 0.66
			var gy := ground_y(x, z) - 0.25   # sink the base so slopes never show a gap
			var yaw := randf() * TAU
			var tint := Color(randf_range(0.82, 1.12), randf_range(0.85, 1.12), randf_range(0.8, 1.05))
			var r: float
			if pine:
				var h := randf_range(9.0, 17.0)
				r = randf_range(0.2, 0.38) * (h / 13.0)
				var cw := randf_range(4.6, 6.2) * (h / 13.0)
				ch.pine_t.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(r, h * 0.85, r)), Vector3(x, gy + h * 0.425, z)), Color.WHITE])
				ch.pine_c.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(cw, h, cw)), Vector3(x, gy, z)), tint])
			else:
				var h := randf_range(7.0, 11.0)
				r = randf_range(0.22, 0.36)
				var cw := randf_range(6.5, 9.0)
				ch.broad_t.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(r, h * 0.7, r)), Vector3(x, gy + h * 0.35, z)), Color.WHITE])
				ch.broad_c.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(cw, h, cw)), Vector3(x, gy, z)), tint])
			ch.shapes.append(Vector3(x, z, r))
			var gk := _cell(x, z, 8.0)
			if not _tree_grid.has(gk):
				_tree_grid[gk] = []
			_tree_grid[gk].append(Vector3(x, z, r))
			# AI cover behind the larger trunks
			if r >= 0.3 and randi() % 2 == 0:
				big_cover += 1
				for k in 4:
					var a := k * PI * 0.5
					var nrm := Vector3(cos(a), 0, sin(a))
					cover_points.append({"pos": _on_ground(Vector3(x, 0, z) + nrm * (r + 0.55)), "normal": nrm, "taken": null, "valid": true, "destroyed": false})
	# needles and leaf litter replace grass under the canopy
	var gpx := float(_ground_img.get_width()) / (HALF * 2.0)
	for ck in chunks:
		for sh in chunks[ck].shapes:
			_paint(_ground_img, Vector2(sh.x, sh.y), 3.6, gpx, 3, 0.85)
	_ground_tex.update(_ground_img)
	for ck in chunks:
		var ch: Dictionary = chunks[ck]
		_multimesh(trunk, _mat_bark, ch.pine_t + ch.broad_t, true)
		_multimesh(pine_crown, pine_mat, ch.pine_c, true)
		_multimesh(broad_crown, broad_mat, ch.broad_c, true)
		var body := _body(Vector3.ZERO)
		for s in ch.shapes:
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(s.z, 0.18)
			cyl.height = 5.0
			cs.shape = cyl
			cs.position = Vector3(s.x, ground_y(s.x, s.y) + 2.2, s.y)
			body.add_child(cs)
	_build_rocks_and_logs()
	_build_bushes(bush_mat)
	_build_grass()


func _multimesh(mesh: Mesh, mat: Material, items: Array, shadows: bool, vis_end: float = 0.0) -> MultiMeshInstance3D:
	if items.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	return mmi


func _free_spot(min_open: float) -> Vector3:
	for attempt in 40:
		var p := Vector2(randf_range(-HALF + 4, HALF - 4), randf_range(-HALF + 4, HALF - 4))
		if _open_dist(p) > min_open and tree_clearance(p) > 1.4:
			return Vector3(p.x, ground_y(p.x, p.y), p.y)
	return Vector3.INF


func _build_rocks_and_logs() -> void:
	var rock_meshes := [Nature.rock_mesh(1), Nature.rock_mesh(2), Nature.rock_mesh(3), Nature.rock_mesh(4)]
	for i in 75:
		var rock_mesh: Mesh = rock_meshes[i % rock_meshes.size()]
		var p := _free_spot(1.0)
		if p == Vector3.INF:
			continue
		var w := randf_range(1.0, 2.8)
		var h := randf_range(0.6, 1.7)
		var d := randf_range(0.9, 2.4)
		var rot := randf() * TAU
		var b := _body(p - Vector3(0, 0.15, 0), rot)
		_box_shape(b, Vector3(w * 0.8, h, d * 0.8), Vector3(0, h * 0.5, 0))
		_mesh(b, rock_mesh, _mat_rock, Vector3(0, h * 0.42, 0), Vector3(randf() * 0.3, randf() * TAU, randf() * 0.3), Vector3(w, h * 1.1, d))
		if randf() < 0.6:
			_mesh(b, rock_meshes[(i + 1) % rock_meshes.size()], _mat_rock, Vector3(w * 0.35, h * 0.25, d * 0.2), Vector3(0, randf() * TAU, 0), Vector3(w * 0.5, h * 0.6, d * 0.5))
		if h < 1.25:
			_add_cover(p, Vector3(w * 0.8, h, d * 0.8), rot)
	for i in 50:
		var p := _free_spot(1.5)
		if p == Vector3.INF:
			continue
		var ln := randf_range(3.0, 6.5)
		var r := randf_range(0.26, 0.4)
		var rot := randf() * TAU
		var b := _body(p - Vector3(0, 0.1, 0), rot, "log")
		_box_shape(b, Vector3(ln, r * 2.0, r * 2.0), Vector3(0, r, 0))
		_mesh(b, ML.cylinder(r, r * 0.9, ln, 10), _mat_log, Vector3(0, r, 0), Vector3(0, 0, PI * 0.5))
		_mesh(b, ML.cylinder(r * 0.4, r * 0.25, 0.8, 6), _mat_log, Vector3(ln * 0.2, r * 1.6, 0), Vector3(0.6, 0, 0.3))
		_add_cover(p, Vector3(ln, r * 2.0, r * 2.0), rot, b)
		b.finalize()


func _build_bushes(mat: Material) -> void:
	var meshes := [Nature.bush_mesh(9), Nature.bush_mesh(10), Nature.bush_mesh(11)]
	_burn_rng(48)
	var lists := [{}, {}, {}]
	for i in 900:
		var p := Vector2(randf_range(-HALF, HALF), randf_range(-HALF, HALF))
		var od := _open_dist(p)
		if od < -6.0 or road_dist(p) < 3.2 or _seg_dist(p, creek) < 3.0:
			continue
		var s := randf_range(1.0, 2.0)
		var k := randi() % 3
		var ck := _cell(p.x, p.y, CHUNK)
		if not lists[k].has(ck):
			lists[k][ck] = []
		var tint := Color(randf_range(0.8, 1.1), randf_range(0.85, 1.15), randf_range(0.8, 1.0))
		lists[k][ck].append([Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s * randf_range(0.7, 1.0), s)), Vector3(p.x, ground_y(p.x, p.y) - 0.08, p.y)), tint])
		var gk := _cell(p.x, p.y, 8.0)
		if not _bush_grid.has(gk):
			_bush_grid[gk] = []
		_bush_grid[gk].append(Vector3(p.x, p.y, s * 0.75))
	for k in 3:
		for ck in lists[k]:
			_multimesh(meshes[k], mat, lists[k][ck], true, 90.0)


## The meshes and grass now use their own RNGs. Draw the global values the
## previous versions consumed so tree, bush, patrol and spawn layouts stay identical.
func _burn_rng(n: int) -> void:
	for i in n:
		randf()


func _burn_old_grass_rng() -> void:
	_burn_rng(6)
	for i in 26000:
		var p := Vector2(randf_range(-HALF, HALF), randf_range(-HALF, HALF))
		if road_dist(p) < 2.6 or _seg_dist(p, creek) < 2.8:
			continue
		var inside := false
		for c in clearings:
			if p.distance_to(c[0]) < float(c[1]) * 0.55 and float(c[2]) > 0.5:
				inside = true
				break
		if inside and randf() < 0.85:
			continue
		_burn_rng(6)


func _build_grass() -> void:
	_burn_old_grass_rng()
	var tufts := [Nature.grass_tuft_mesh(5), Nature.grass_tuft_mesh(6)]
	var mat := Nature.grass_material()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# growth map (1 m cells): 0 = bare (roads, creek, pads) .. 1 = open meadow.
	# Sampling it per tuft keeps a 3x denser carpet as fast to build as before.
	var gn := int(HALF * 2.0)
	var grow := PackedFloat32Array()
	grow.resize(gn * gn)
	var pads := [Vector2(lz_south.x, lz_south.z), Vector2(lz_north.x, lz_north.z)]
	for iz in gn:
		for ix in gn:
			var p := Vector2(-HALF + ix + 0.5, -HALF + iz + 0.5)
			var g := 1.0
			if road_dist(p) < 2.6 or _seg_dist(p, creek) < 2.8 or p.distance_to(pads[0]) < 6.4 or p.distance_to(pads[1]) < 6.4:
				g = 0.0
			else:
				for c in clearings:
					if p.distance_to(c[0]) < float(c[1]) * 0.55 and float(c[2]) > 0.5:
						g = 0.15   # trodden camp ground
						break
				if g > 0.2 and tree_clearance(p) < 2.2:
					g = 0.3        # shaded forest floor
			grow[iz * gn + ix] = g
	# layer 0: base cover (always shown). layer 1: dense short fill (HIGH / ULTRA).
	for layer in 2:
		var per_chunk := [{}, {}]
		for i in (70000 if layer == 0 else 125000):
			var x := rng.randf_range(-HALF, HALF)
			var z := rng.randf_range(-HALF, HALF)
			var g := grow[clampi(int(z + HALF), 0, gn - 1) * gn + clampi(int(x + HALF), 0, gn - 1)]
			if rng.randf() > g:
				continue
			var k := i % 2
			var ck := _cell(x, z, GRASS_CHUNK)
			if not per_chunk[k].has(ck):
				per_chunk[k][ck] = []
			var sc := rng.randf_range(0.8, 1.5) if layer == 0 else rng.randf_range(0.5, 0.95)
			var tint := Color(rng.randf_range(0.8, 1.1), rng.randf_range(0.85, 1.1), rng.randf_range(0.75, 1.0))
			per_chunk[k][ck].append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.75, 1.3), sc)), Vector3(x, ground_y(x, z), z)), tint])
		for k in 2:
			for ck in per_chunk[k]:
				var node := _multimesh(tufts[k], mat, per_chunk[k][ck], false, 42.0 if layer == 0 else 34.0)
				if layer == 1 and node != null:
					_dense_nodes.append(node)
	# ferns on the forest floor, wildflowers in the meadows
	var fern := Nature.fern_mesh()
	var flower := Nature.flower_mesh()
	var flower_mat := Nature.flower_material()
	var ferns := {}
	var flowers := {}
	var petal := [Color(1.0, 0.98, 0.9), Color(1.0, 0.82, 0.15), Color(0.72, 0.55, 0.95), Color(1.0, 0.98, 0.9)]
	for i in 26000:
		var x := rng.randf_range(-HALF, HALF)
		var z := rng.randf_range(-HALF, HALF)
		var g := grow[clampi(int(z + HALF), 0, gn - 1) * gn + clampi(int(x + HALF), 0, gn - 1)]
		var ck := _cell(x, z, GRASS_CHUNK)
		if g > 0.25 and g < 0.35 and i % 3 == 0:
			if not ferns.has(ck):
				ferns[ck] = []
			var fs := rng.randf_range(0.8, 1.5)
			ferns[ck].append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(fs, fs, fs)), Vector3(x, ground_y(x, z), z)),
					Color(rng.randf_range(0.7, 1.0), rng.randf_range(0.8, 1.05), rng.randf_range(0.6, 0.9))])
		elif g > 0.9:
			# flowers grow in drifts, not evenly
			if sin(x * 0.31 + 1.7) * sin(z * 0.27 - 0.6) + sin((x + z) * 0.11) * 0.5 < 0.35:
				continue
			if not flowers.has(ck):
				flowers[ck] = []
			var ws := rng.randf_range(0.7, 1.3)
			flowers[ck].append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ws, ws, ws)), Vector3(x, ground_y(x, z), z)),
					petal[rng.randi() % petal.size()]])
	for ck in ferns:
		_multimesh(fern, mat, ferns[ck], false, 46.0)
	for ck in flowers:
		var fn := _multimesh(flower, flower_mat, flowers[ck], false, 30.0)
		if fn != null:
			_dense_nodes.append(fn)


## Invisible walls at the map edge; a dense tree line beyond them.
func _build_boundary() -> void:
	for e in [[Vector3(0, 0, -HALF - 1), Vector3(HALF * 2 + 4, 6, 2)], [Vector3(0, 0, HALF + 1), Vector3(HALF * 2 + 4, 6, 2)],
			[Vector3(-HALF - 1, 0, 0), Vector3(2, 6, HALF * 2 + 4)], [Vector3(HALF + 1, 0, 0), Vector3(2, 6, HALF * 2 + 4)]]:
		var b := _body(e[0])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		cs.position.y = 3.0
		b.add_child(cs)
	var crown := Nature.pine_crown_mesh()
	_burn_rng(4)
	var mat := Nature.foliage_material(Color(0.13, 0.22, 0.11), 0.02)
	var items: Array = []
	var vary := RandomNumberGenerator.new()   # own RNG: keeps the global layout sequence intact
	vary.seed = 99
	for i in 520:
		var a := randf() * TAU
		var side := randi() % 4
		var t := randf_range(-HALF - 14, HALF + 14)
		var off := randf_range(2.0, 16.0)
		var p: Vector2 = [Vector2(t, -HALF - off), Vector2(t, HALF + off), Vector2(-HALF - off, t), Vector2(HALF + off, t)][side]
		var h := randf_range(11.0, 18.0) * vary.randf_range(0.7, 1.45)
		var w := h * vary.randf_range(0.34, 0.5)
		var tint := Color(randf_range(0.8, 1.0), vary.randf_range(0.85, 1.1), vary.randf_range(0.85, 1.05))
		items.append([Transform3D(Basis(Vector3.UP, a).scaled(Vector3(w, h, w)), Vector3(p.x, ground_y(p.x, p.y) - 0.5, p.y)), tint])
	_multimesh(crown, mat, items, false)
	_build_far_hills()


## Distant forested ridgelines around the valley, faded by aerial perspective.
func _build_far_hills() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 311
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	var jag := FastNoiseLite.new()
	jag.seed = 312
	jag.frequency = 0.09
	var seg := 160
	var rings := [118.0, 140.0, 170.0, 210.0, 260.0, 330.0, 420.0, 540.0, 700.0]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in rings.size():
		var r: float = rings[ri]
		for i in seg + 1:
			var a := TAU * float(i) / seg
			var p := Vector2(cos(a), sin(a)) * r
			var rise := smoothstep(110.0, 330.0, r)
			var h := 4.0 + rise * (22.0 + 55.0 * (noise.get_noise_2dv(p) * 0.5 + 0.5))
			h += (jag.get_noise_2dv(p) * 0.5 + 0.5) * 6.0 * rise   # ragged tree-covered crest
			if ri == rings.size() - 1:
				h *= 0.6
			st.set_uv(Vector2(float(i) / seg, r))
			st.add_vertex(Vector3(p.x, h, p.y))
	var w := seg + 1
	for ri in rings.size() - 1:
		for i in seg:
			var k := ri * w + i
			st.add_index(k)
			st.add_index(k + w)
			st.add_index(k + 1)
			st.add_index(k + 1)
			st.add_index(k + w)
			st.add_index(k + w + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Nature.far_hills_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 64.0
	add_child(mi)


## Night-time fireflies over the clearings and the creek.
func _build_fireflies() -> void:
	var mat := M.glow(Color(0.85, 1.0, 0.45, 1.0))
	for c in [Vector2(camp.x, camp.z), Vector2(-62, -22), Vector2(55, -45), Vector2(bridge.x, bridge.z), Vector2(62, 52)]:
		var p := CPUParticles3D.new()
		p.amount = 60
		p.lifetime = 6.0
		p.preprocess = 6.0
		p.mesh = ML.sphere(0.035, false, 4)
		p.material_override = mat
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(12, 1.0, 12)
		p.direction = Vector3(1, 0.3, 0)
		p.spread = 180.0
		p.initial_velocity_min = 0.1
		p.initial_velocity_max = 0.4
		p.gravity = Vector3.ZERO
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = Vector3(c.x, 1.3, c.y)
		p.emitting = false
		p.visible = false
		add_child(p)
		fireflies.append(p)


# ================================================================ queries

## Distance from p to the nearest tree trunk surface (search radius ~8 m).
func tree_clearance(p: Vector2) -> float:
	var best := 99.0
	var c := _cell(p.x, p.y, 8.0)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for t in _tree_grid.get(c + Vector2i(dx, dz), []):
				best = minf(best, Vector2(t.x, t.y).distance_to(p) - t.z)
	return best


## Trees within r of pos (for the radar).
func trees_near(pos: Vector3, r: float) -> Array:
	var out: Array = []
	var c0 := _cell(pos.x - r, pos.z - r, 8.0)
	var c1 := _cell(pos.x + r, pos.z + r, 8.0)
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			for t in _tree_grid.get(Vector2i(x, z), []):
				if Vector2(t.x - pos.x, t.y - pos.z).length() < r:
					out.append(t)
	return out


## 0..1 concealment from bushes at pos (crouching in a bush hides you).
func concealment(pos: Vector3) -> float:
	var c := _cell(pos.x, pos.z, 8.0)
	var best := 0.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for b in _bush_grid.get(c + Vector2i(dx, dz), []):
				var d := Vector2(b.x - pos.x, b.y - pos.z).length()
				if d < b.z + 0.4:
					best = maxf(best, 1.0 - clampf((d - b.z) / 0.6, 0.0, 1.0) * 0.5)
	return best


func apply_quality(q: int) -> void:
	for n in _dense_nodes:
		if is_instance_valid(n):
			n.visible = q >= 1   # dense grass + flowers on HIGH / ULTRA shadows presets
	for entry in lights:
		var l: Light3D = entry.light
		if is_instance_valid(l):
			l.shadow_enabled = (q == 2) or (q == 1 and entry.shadow)


func _bake_navigation() -> void:
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


# ================================================================ mode setup

func _rand_patrol(center: Vector3, radius: float, n: int) -> Array:
	var pts: Array = [center]
	for i in n:
		for attempt in 12:
			var a := randf() * TAU
			var q := center + Vector3(cos(a), 0, sin(a)) * randf_range(radius * 0.4, radius)
			if tree_clearance(Vector2(q.x, q.z)) > 1.2 and absf(q.x) < HALF - 5 and absf(q.z) < HALF - 5:
				pts.append(q)
				break
	return pts


func _guard(pos: Vector3, yaw: float, group: String, patrol: Array = []) -> void:
	enemy_spawns.append({"pos": pos, "yaw": yaw, "patrol": patrol, "group": group})


func _define_mode() -> void:
	enemy_spawns.clear()
	var c := camp
	var o := outpost
	match mode:
		"ch1":
			player_spawn = lz_south + Vector3(0, 0, 2)
			player_yaw = 0.0
			# logging camp garrison
			_guard(c + Vector3(-6, 0, 14), PI * 0.8, "camp")
			_guard(c + Vector3(2, 0, 2), 0.5, "camp")
			_guard(c + Vector3(-9, 0, -6), PI, "camp")
			_guard(c + Vector3(10, 0, -5), PI * 0.9, "camp")
			_guard(c + Vector3(-11, 0, 9), 0.4, "camp", [c + Vector3(-11, 0, 9), c + Vector3(-17, 0, 3), c + Vector3(-12, 0, -3)])
			_guard(c + Vector3(14, 0, 4), -0.6, "camp", [c + Vector3(14, 0, 4), c + Vector3(6, 0, 14), c + Vector3(16, 0, -6)])
			_guard(c + Vector3(-1, 0, -10), PI, "camp", [c + Vector3(-1, 0, -10), c + Vector3(12, 0, -14), c + Vector3(-10, 0, -15)])
			_guard(c + Vector3(-15, 0, -13), 0.8, "camp")
			_guard(c + Vector3(5, 0, 9), 2.4, "camp", [c + Vector3(5, 0, 9), c + Vector3(-4, 0, 6)])
			# road + forest patrols between the LZ and the camp
			_guard(Vector3(8, 0, 56), 0.0, "woods", [Vector3(8, 0, 56), Vector3(18, 0, 38), Vector3(6, 0, 62)])
			_guard(Vector3(-14, 0, 52), 0.0, "woods", _rand_patrol(Vector3(-14, 0, 52), 14.0, 3))
			_guard(Vector3(36, 0, 58), 0.0, "woods", _rand_patrol(Vector3(36, 0, 58), 14.0, 3))
			_guard(Vector3(48, 0, 26), 0.0, "woods", _rand_patrol(Vector3(48, 0, 26), 12.0, 3))
			_guard(Vector3(8, 0, 12), 0.0, "woods", [Vector3(8, 0, 12), Vector3(-2, 0, 2), Vector3(14, 0, 16)])
			ammo_crates.append(lz_south + Vector3(-5, 0, 3))
		"ch2":
			player_spawn = bridge + Vector3(1.5, 0, 6.0)
			player_yaw = 0.15
			_guard(o + Vector3(4.5, 0, 19), PI, "outpost")
			_guard(o + Vector3(1.0, 0, 19), PI * 0.9, "outpost")
			_guard(o + Vector3(-6, 0, 4), PI, "outpost")
			_guard(o + Vector3(-8, 0, -5), 0.6, "outpost")
			_guard(o + Vector3(8, 0, -3.5), 2.8, "outpost")
			_guard(o + Vector3(10, 0, 5), PI, "outpost", [o + Vector3(10, 0, 5), o + Vector3(-12, 0, 11), o + Vector3(-13, 0, -2)])
			_guard(o + Vector3(-12, 0, -12), 0.4, "outpost", [o + Vector3(-12, 0, -12), o + Vector3(10, 0, -12), o + Vector3(14, 0, -3)])
			_guard(o + Vector3(15, 0, 11), 3.6, "outpost")
			_guard(o + Vector3(0, 0, -6), 1.2, "outpost")
			_guard(o + Vector3(-3, 0, 12), PI, "outpost")
			_guard(o + Vector3(17, 0, -13), -0.8, "outpost")
			_guard(o + Vector3(-15, 0, 4), 1.6, "outpost")
			_guard(Vector3(-10, 0, -22), 0.0, "woods", [Vector3(-10, 0, -22), Vector3(-20, 0, -36), Vector3(-6, 0, -12)])
			_guard(Vector3(-46, 0, -34), 0.0, "woods", _rand_patrol(Vector3(-46, 0, -34), 12.0, 3))
			_guard(Vector3(-6, 0, -48), 0.0, "woods", _rand_patrol(Vector3(-6, 0, -48), 12.0, 3))
			_guard(Vector3(-14, 0, -76), 0.0, "woods", [Vector3(-14, 0, -76), Vector3(4, 0, -82), Vector3(-24, 0, -68)])
			_guard(Vector3(18, 0, -70), 0.0, "woods", _rand_patrol(Vector3(18, 0, -70), 10.0, 3))
			ammo_crates.append(bridge + Vector3(-4, 0, 7))
			ammo_crates.append(lz_north + Vector3(-7, 0, 2))
		"pvp":
			# deathmatch: open spots at every landmark plus scattered woods
			pvp_spawns = [lz_south + Vector3(0, 0, 2), lz_north + Vector3(0, 0, 2), c + Vector3(-6, 0, 14),
					c + Vector3(14, 0, 4), o + Vector3(-6, 0, 4), o + Vector3(10, 0, 5), bridge + Vector3(1.5, 0, 6),
					bridge + Vector3(-2, 0, -8), Vector3(-58, 0, 48), Vector3(55, 0, -45), Vector3(-62, 0, -22), Vector3(62, 0, 52)]
			var rng := RandomNumberGenerator.new()   # own RNG: other modes' layouts stay identical
			rng.seed = 5150
			for i in 60:
				if pvp_spawns.size() >= 24:
					break
				var p := Vector2(rng.randf_range(-HALF + 8, HALF - 8), rng.randf_range(-HALF + 8, HALF - 8))
				if _open_dist(p) > 1.5 and tree_clearance(p) > 2.0:
					pvp_spawns.append(Vector3(p.x, 0, p.y))
			player_spawn = pvp_spawns[0]
			ammo_crates.append(c + Vector3(-12, 0, 2))
			ammo_crates.append(o + Vector3(0, 0, 12))
			ammo_crates.append(bridge + Vector3(-4, 0, 7))
		_:
			# zombie survival: hold the logging camp
			player_spawn = c + Vector3(2, 0, 3)
			player_yaw = 0.0
			zombie_spawns.clear()
			for i in 70:
				var a := randf() * TAU
				var q := c + Vector3(cos(a), 0, sin(a)) * randf_range(16.0, 48.0)
				if absf(q.x) < HALF - 4 and absf(q.z) < HALF - 4 and tree_clearance(Vector2(q.x, q.z)) > 1.2:
					zombie_spawns.append(q)
			ammo_crates.append(c + Vector3(-12, 0, 2))
			ammo_crates.append(c + Vector3(12, 0, 12))
	_snap_mode_points()


## Every spawn, patrol point and crate stands on the terrain.
func _snap_mode_points() -> void:
	player_spawn = _on_ground(player_spawn)
	for e in enemy_spawns:
		e.pos = _on_ground(e.pos)
		var pts: Array = []
		for q in e.patrol:
			pts.append(_on_ground(q))
		e.patrol = pts
	for i in ammo_crates.size():
		ammo_crates[i] = _on_ground(ammo_crates[i])
	for i in zombie_spawns.size():
		zombie_spawns[i] = _on_ground(zombie_spawns[i])
	for i in pvp_spawns.size():
		pvp_spawns[i] = _on_ground(pvp_spawns[i])
