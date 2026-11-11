extends RefCounted
## Shared terrain height field. The level fills it at build time; FX, debris
## and movement probes query it so nothing assumes the ground is at y = 0.
## Returns 0 everywhere until a level sets it (flat maps keep working).

static var step := 2.0
static var half := 130.0
static var n := 0
static var data := PackedFloat32Array()


static func set_grid(p_half: float, p_step: float, p_n: int, p_data: PackedFloat32Array) -> void:
	half = p_half
	step = p_step
	n = p_n
	data = p_data


static func clear() -> void:
	n = 0
	data = PackedFloat32Array()


## Ground height at world (x, z), bilinear between grid samples.
static func height(x: float, z: float) -> float:
	if n < 2:
		return 0.0
	var fx := clampf((x + half) / step, 0.0, float(n) - 1.001)
	var fz := clampf((z + half) / step, 0.0, float(n) - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * n + ix
	return lerpf(lerpf(data[i], data[i + 1], tx), lerpf(data[i + n], data[i + n + 1], tx), tz)


static func normal(x: float, z: float) -> Vector3:
	if n < 2:
		return Vector3.UP
	var e := step * 0.5
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


## Same point dropped onto the ground.
static func snap(p: Vector3) -> Vector3:
	return Vector3(p.x, height(p.x, p.z), p.z)
