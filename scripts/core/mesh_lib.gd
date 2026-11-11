extends RefCounted
## Cached primitive meshes. Identical sizes share one mesh resource.

static var _cache: Dictionary = {}


static func box(size: Vector3) -> BoxMesh:
	var key := "box_%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not _cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_cache[key] = m
	return _cache[key]


## Box with rounded edges and corners (subdivided cube pushed onto a
## rounded shell). `radius` < 0 picks ~28% of the smallest side, max 3 cm.
static func rbox(size: Vector3, radius: float = -1.0) -> ArrayMesh:
	var r := radius if radius >= 0.0 else minf(minf(minf(size.x, size.y), size.z) * 0.28, 0.03)
	var key := "rbox_%.3f_%.3f_%.3f_%.3f" % [size.x, size.y, size.z, r]
	if _cache.has(key):
		return _cache[key]
	var b := BoxMesh.new()
	b.size = size
	b.subdivide_width = 2
	b.subdivide_height = 2
	b.subdivide_depth = 2
	var arr := b.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var inner := size * 0.5 - Vector3.ONE * r
	for i in verts.size():
		var v := verts[i]
		var c := v.clamp(-inner, inner)
		var d := v - c
		var n := d.normalized() if d.length_squared() > 1e-10 else norms[i]
		verts[i] = c + n * r
		norms[i] = n
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache[key] = m
	return m


## Box with a small machined bevel (weapons, hardware): edges catch the light.
static func bbox(size: Vector3) -> ArrayMesh:
	var smallest := minf(minf(size.x, size.y), size.z)
	return rbox(size, clampf(smallest * 0.22, 0.0008, 0.0045))


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var key := "cap_%.3f_%.3f" % [radius, height]
	if not _cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(height, radius * 2.0)
		m.radial_segments = 16
		m.rings = 6
		_cache[key] = m
	return _cache[key]


static func cylinder(top: float, bottom: float, height: float, segments: int = 16) -> CylinderMesh:
	var key := "cyl_%.3f_%.3f_%.3f_%d" % [top, bottom, height, segments]
	if not _cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_cache[key] = m
	return _cache[key]


static func sphere(radius: float, hemisphere: bool = false, segments: int = 18) -> SphereMesh:
	var key := "sph_%.3f_%s_%d" % [radius, hemisphere, segments]
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius if hemisphere else radius * 2.0
		m.is_hemisphere = hemisphere
		m.radial_segments = segments
		m.rings = maxi(segments / 2, 4)
		_cache[key] = m
	return _cache[key]


static func quad(size: Vector2) -> QuadMesh:
	var key := "quad_%.3f_%.3f" % [size.x, size.y]
	if not _cache.has(key):
		var m := QuadMesh.new()
		m.size = size
		_cache[key] = m
	return _cache[key]


static func plane(size: Vector2) -> PlaneMesh:
	var key := "plane_%.3f_%.3f" % [size.x, size.y]
	if not _cache.has(key):
		var m := PlaneMesh.new()
		m.size = size
		_cache[key] = m
	return _cache[key]
