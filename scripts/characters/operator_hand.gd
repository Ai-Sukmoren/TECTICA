extends RefCounted
## Fingerless glove in the existing hand socket's space. The shell and exposed
## fingertips share a continuous section at each opening, in both hand poses.

const SIDES := 12
const Body = preload("res://scripts/characters/body_mesh.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
static var _cache := {}

## Stitched reinforcements follow the palm. They sit before the moving finger joints.
static func padding(side: float) -> ArrayMesh:
	var key := "operator_glove_padding_%d" % int(side)
	if _cache.has(key):
		return _cache[key]
	var parts := []
	for i in 4:
		var y := 0.031 - i * 0.02
		var arch := sqrt(maxf(0.0, 1.0 - pow(y / 0.043, 2.0)))
		var pad := Transform3D(Basis(Vector3.BACK, side * y * 9.0),
			Vector3(side * (0.007 + 0.016 * arch), y, -0.026 + absf(i - 1.0) * 0.002))
		parts.append([ML.rbox(Vector3(0.006, 0.014, 0.024), 0.003), pad])
	var tab := Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(side * 0.018, -0.002, 0.026))
	parts.append([ML.rbox(Vector3(0.006, 0.043, 0.013), 0.0025), tab])
	_cache[key] = Body.merge(key, parts)
	return _cache[key]

static func mesh(side: float) -> ArrayMesh:
	if _cache.has(side):
		return _cache[side]
	var closed := _surfaces(side, false)
	var open := _surfaces(side, true)
	var fitted := _surfaces(side, false, true)
	var result := ArrayMesh.new()
	result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	result.add_blend_shape("Release")
	result.add_blend_shape("PropContact")
	for i in closed.size():
		var shapes: Array[Array] = []
		for target in [open[i], fitted[i]]:
			var shape := []
			shape.resize(Mesh.ARRAY_MAX)
			shape[Mesh.ARRAY_VERTEX] = target[Mesh.ARRAY_VERTEX]
			shape[Mesh.ARRAY_NORMAL] = target[Mesh.ARRAY_NORMAL]
			shapes.append(shape)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, closed[i], shapes)
	_cache[side] = result
	return result

static func _surfaces(side: float, open: bool, fitted: bool = false) -> Array:
	var cloth := SurfaceTool.new()
	var skin := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Narrow heel at the wrist, broad metacarpals and a shallow cupped palm.
	var palm := PackedVector3Array([Vector3(0, -0.002, 0.051), Vector3(0, -0.002, 0.034),
		Vector3(side * 0.002, 0, 0.01), Vector3(side * 0.005, 0, -0.021),
		Vector3(side * 0.009, 0.001, -0.038), Vector3(side * 0.009, 0.001, -0.044)])
	_tube(cloth, cloth, palm, [0.024, 0.03, 0.04, 0.043, 0.04, 0.033],
		[0.016, 0.018, 0.02, 0.019, 0.014, 0.009], 6)
	var lengths := [0.94, 1.0, 0.91, 0.75]
	var girths := [0.0096, 0.0101, 0.0094, 0.0083]
	for i in 4:
		var base := Vector3(side * 0.012, 0.032 - i * 0.0206, -0.034 + absf(i - 1.0) * 0.003)
		var path := PackedVector3Array()
		var widths := []
		var depths := []
		var curve := [
			Vector2(0, 0), Vector2(0.006, -0.014), Vector2(0.008, -0.029),
			Vector2(0.006, -0.042), Vector2(-0.002, -0.051), Vector2(-0.013, -0.058),
			Vector2(-0.027, -0.059), Vector2(-0.036, -0.054), Vector2(-0.044, -0.043), Vector2(-0.045, -0.04)]
		var thickness := [0.97, 1.02, 0.99, 1.02, 0.91, 0.9, 0.92, 0.84, 0.65, 0.15]
		for k in curve.size():
			var u := float(k) / (curve.size() - 1)
			var bend: Vector2 = curve[k]
			if open:
				bend = Vector2(0.003 * sin(u * PI) - 0.014 * u * u, -0.091 * u)
			var spread := (1.45 - i) * (0.005 if open else 0.0015) * u
			if fitted:
				# Change the digital silhouette independently of wrist rotation.
				# The right index separates while the left fingertips arc up the prop.
				if side > 0 and i == 0:
					bend = bend.lerp(Vector2(-0.01 * u * u, -0.09 * u), 0.72)
				elif side < 0:
					spread += 0.021 * u * u
					bend.x -= 0.01 * u
			path.append(base + Vector3(bend.x * side, spread, bend.y) * float(lengths[i]))
			widths.append(float(girths[i]) * float(thickness[k]))
			depths.append(float(girths[i]) * float(thickness[k]) * 0.88)
		_tube(cloth, skin, path, widths, depths, 3)
	# The thumb starts against the heel and crosses the palm on a separate arc.
	var thumb := PackedVector3Array()
	var thumb_path := [Vector3(0, 0.02, 0.019), Vector3(-0.005, 0.033, 0.013),
		Vector3(-0.012, 0.045, -0.002), Vector3(-0.018, 0.052, -0.018),
		Vector3(-0.027, 0.053, -0.032), Vector3(-0.037, 0.048, -0.042),
		Vector3(-0.042, 0.044, -0.048), Vector3(-0.043, 0.043, -0.05)]
	for i in thumb_path.size():
		var point: Vector3 = thumb_path[i]
		var u := float(i) / (thumb_path.size() - 1)
		if open:
			point += Vector3(0.015, 0.022, 0.018) * u
		elif fitted and side < 0:
			point += Vector3(0.011, 0.009, -0.019) * u
		point.x *= side
		thumb.append(point)
	_tube(cloth, skin, thumb, [0.018, 0.019, 0.015, 0.012, 0.0118, 0.011, 0.008, 0.002],
		[0.014, 0.016, 0.014, 0.012, 0.011, 0.01, 0.007, 0.002], 3)
	return [cloth.commit_to_arrays(), skin.commit_to_arrays()]

static func _tube(base: SurfaceTool, tip: SurfaceTool, path: PackedVector3Array,
		widths: Array, depths: Array, opening: int) -> void:
	var rings := []
	for i in path.size():
		var first := maxi(0, i - 1)
		var last := mini(path.size() - 1, i + 1)
		var tangent := (path[last] - path[first]).normalized()
		var across := Vector3.UP.slide(tangent).normalized()
		var outward := tangent.cross(across).normalized()
		var ring := []
		for j in SIDES:
			var a := TAU * j / SIDES
			var offset := across * cos(a) * float(widths[i]) + outward * sin(a) * float(depths[i])
			var normal := (across * cos(a) / float(widths[i]) + outward * sin(a) / float(depths[i])).normalized()
			if i == path.size() - 1:
				normal = (normal + tangent).normalized()
			ring.append([path[i] + offset, normal])
		rings.append(ring)
	for i in path.size() - 1:
		var surface := base if i < opening else tip
		for j in SIDES:
			var end := (j + 1) % SIDES
			for vertex in [rings[i][j], rings[i + 1][j], rings[i + 1][end],
					rings[i][j], rings[i + 1][end], rings[i][end]]:
				_add(surface, vertex)
	for j in range(1, SIDES - 1):
		for vertex in [rings[0][0], rings[0][j], rings[0][j + 1]]:
			_add(base, vertex)
		var last_surface := base if opening >= path.size() else tip
		for vertex in [rings[-1][0], rings[-1][j + 1], rings[-1][j]]:
			_add(last_surface, vertex)

static func _add(surface: SurfaceTool, vertex: Array) -> void:
	var point: Vector3 = vertex[0]
	surface.set_normal(vertex[1])
	surface.set_uv(Vector2(point.z, point.y + point.x) * 9.0)
	surface.add_vertex(point)
