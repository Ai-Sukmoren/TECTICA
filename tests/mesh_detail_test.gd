extends SceneTree
const ML = preload("res://scripts/core/mesh_lib.gd")

func _initialize() -> void:
	var thin := ML.bbox(Vector3(0.0005, 0.02, 0.04))
	var vertices: PackedVector3Array = thin.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in vertices:
		if not v.is_finite() or absf(v.x) > 0.000251 or absf(v.y) > 0.010001 or absf(v.z) > 0.020001:
			push_error("Bevel escaped thin plate bounds: %s" % v)
			quit(1)
			return
	if ML.cylinder(0.0021, 0.0021, 0.01) == ML.cylinder(0.0022, 0.0022, 0.01):
		push_error("Sub-millimetre detail meshes collided in cache")
		quit(1)
		return
	print("MESH DETAIL PASS: bounded thin bevels, distinct precise cache entries")
	quit(0)
