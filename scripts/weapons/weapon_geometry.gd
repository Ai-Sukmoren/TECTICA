extends RefCounted
## Cached, flat-shaded machined geometry for close-up firearm silhouettes.
static var _cache: Dictionary = {}

static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var points := [a, b, c] if (b - a).cross(c - a).dot(n) < 0.0 else [a, c, b]
	for p in points:
		st.set_normal(n)
		st.set_uv(Vector2(p.z, p.y))
		st.add_vertex(p)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_triangle(st, a, b, c, n)
	_triangle(st, a, c, d, n)

## Octagonal cross-section with flat sides and distinct edge highlights.
static func machined(size: Vector3) -> ArrayMesh:
	var key := "machine:%s" % size
	if _cache.has(key):
		return _cache[key]
	var x := size.x * 0.5
	var y := size.y * 0.5
	var z := size.z * 0.5
	var bevel := minf(minf(x, y) * 0.3, 0.004)
	var corners := [Vector2(-x + bevel, -y), Vector2(x - bevel, -y), Vector2(x, -y + bevel), Vector2(x, y - bevel), Vector2(x - bevel, y), Vector2(-x + bevel, y), Vector2(-x, y - bevel), Vector2(-x, -y + bevel)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var n := Vector3(b.y - a.y, a.x - b.x, 0).normalized()
		_quad(st, Vector3(a.x, a.y, -z), Vector3(b.x, b.y, -z), Vector3(b.x, b.y, z), Vector3(a.x, a.y, z), n)
		_triangle(st, Vector3(0, 0, -z), Vector3(a.x, a.y, -z), Vector3(b.x, b.y, -z), Vector3.FORWARD)
		_triangle(st, Vector3(0, 0, z), Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3.BACK)
	st.generate_tangents()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh

## Extrude an authored Z/Y side outline with a recessed edge bevel on both sides.
static func profile(width: float, outline: PackedVector2Array) -> ArrayMesh:
	var key := "profile:%s:%s" % [width, outline]
	if _cache.has(key):
		return _cache[key]
	if Geometry2D.is_polygon_clockwise(outline):
		outline.reverse()
	var triangles := Geometry2D.triangulate_polygon(outline)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for t in range(0, triangles.size(), 3):
			var a := outline[triangles[t]]
			var b := outline[triangles[t + 1]]
			var c := outline[triangles[t + 2]]
			_triangle(st, Vector3(side * width * 0.5, a.y, a.x), Vector3(side * width * 0.5, b.y, b.x), Vector3(side * width * 0.5, c.y, c.x), Vector3(side, 0, 0))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var n := Vector3(0, a.x - b.x, b.y - a.y).normalized()
		_quad(st, Vector3(-width * 0.5, a.y, a.x), Vector3(width * 0.5, a.y, a.x), Vector3(width * 0.5, b.y, b.x), Vector3(-width * 0.5, b.y, b.x), n)
	st.generate_tangents()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh
