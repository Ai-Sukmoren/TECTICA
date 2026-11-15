extends RefCounted
## Wadeable water on the current map: the forest creek. The forest sets it when
## it builds; every other map clears it. Footsteps ask `wading()` to swap the
## dry step for a splash.

## Creek centre line (x, z), half its width, and the water surface height.
static var line := PackedVector2Array()
static var half_width := 2.3
static var surface_y := 0.025
## Dry crossings (x, z, radius): the bridge keeps its footing above the water.
static var dry: Array = []


static func set_creek(p_line: PackedVector2Array, p_half_width: float, p_surface_y: float, p_dry: Array) -> void:
	line = p_line
	half_width = p_half_width
	surface_y = p_surface_y
	dry = p_dry


static func clear() -> void:
	line = PackedVector2Array()
	dry = []


## True when feet at `pos` stand in the water (not on a bank above it, not on the bridge).
static func wading(pos: Vector3) -> bool:
	if line.size() < 2 or pos.y > surface_y + 0.12:
		return false
	var p := Vector2(pos.x, pos.z)
	for d in dry:
		if p.distance_to(Vector2(d.x, d.y)) < d.z:
			return false
	for i in line.size() - 1:
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])) < half_width:
			return true
	return false
