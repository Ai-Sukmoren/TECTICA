extends RefCounted
## Anatomical body parts for the procedural soldier and infected
## (soldier_rig.gd). Each part is lofted through elliptical cross-sections
## taken from human proportions (hip and buttock, quadriceps, calf bulge,
## deltoid and biceps, tapering forearm, V-shaped chest, jaw, cheekbones,
## brow) and smooth-shaded, for a realistic polygonal look. Parts hang from the
## same joints as before, so the animation is unchanged. Meshes are cached:
## every body shares them.
##
## A ring is [y, half width (x), half depth (z), centre z]; -Z is the front.

static var _cache := {}


## Lofts `rings` (any order; sorted top to bottom) into a closed tube with
## `sides` facets round. The tube is smooth shaded; the end caps stay flat
## (they sit inside the joints, and a smooth cap would bend the rim's normals).
static func loft(key: String, rings: Array, sides: int = 12) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var rs := rings.duplicate()
	rs.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var pts: Array = []
	for r in rs:
		var ring: Array = []
		for i in sides:
			var a := TAU * (float(i) + 0.5) / float(sides)
			ring.append(Vector3(sin(a) * float(r[1]), float(r[0]), float(r[3]) + cos(a) * float(r[2])))
		pts.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for k in pts.size() - 1:
		var a: Array = pts[k]
		var b: Array = pts[k + 1]
		for i in sides:
			var j := (i + 1) % sides
			_tri(st, a[i], a[j], b[j])
			_tri(st, a[i], b[j], b[i])
	st.set_smooth_group(-1)
	_cap(st, pts[0])
	_cap(st, pts[pts.size() - 1])
	st.index()   # shared corners, so the tube's normals average across facets
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Closes a ring with a fan, wound both ways so it shows from either side.
static func _cap(st: SurfaceTool, ring: Array) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	if (ring[0] as Vector3).distance_to(c) < 0.002:
		return
	for i in ring.size():
		var j := (i + 1) % ring.size()
		_tri(st, c, ring[i], ring[j])
		_tri(st, c, ring[j], ring[i])


# --------------------------------------------------------------- body parts

## Pelvis on the hip joint: crotch, hip bones, buttocks behind.
static func pelvis() -> ArrayMesh:
	return loft("pelvis", [
		[0.11, 0.150, 0.105, 0.0],
		[0.04, 0.168, 0.115, 0.005],
		[-0.05, 0.170, 0.122, 0.018],
		[-0.12, 0.135, 0.105, 0.012],
		[-0.16, 0.070, 0.070, 0.0],
	], 16)


## Thigh from the hip joint down to the knee: full at the top, quadriceps in
## front, tapering to a narrow knee.
static func thigh(length: float) -> ArrayMesh:
	return loft("thigh%.3f" % length, [
		[0.05, 0.098, 0.100, 0.008],
		[-0.06, 0.096, 0.100, 0.0],
		[-length * 0.35, 0.086, 0.090, -0.008],
		[-length * 0.65, 0.074, 0.078, -0.004],
		[-length * 0.9, 0.060, 0.064, 0.0],
		[-length - 0.02, 0.054, 0.060, 0.004],
	], 12)


## Shin from the knee to the ankle: the calf bulges behind, the ankle is slim.
static func shin(length: float) -> ArrayMesh:
	return loft("shin%.3f" % length, [
		[0.02, 0.055, 0.058, 0.004],
		[-length * 0.12, 0.058, 0.064, 0.012],
		[-length * 0.32, 0.060, 0.070, 0.020],
		[-length * 0.6, 0.050, 0.054, 0.010],
		[-length * 0.85, 0.042, 0.044, 0.004],
		[-length, 0.040, 0.042, 0.0],
	], 12)


## Lower torso on the spine joint: waist up to the bottom of the ribs.
static func abdomen() -> ArrayMesh:
	return loft("abdomen", [
		[0.25, 0.158, 0.110, 0.0],
		[0.14, 0.142, 0.102, 0.0],
		[0.02, 0.140, 0.100, -0.004],
		[-0.08, 0.152, 0.106, 0.0],
	], 16)


## Upper torso on the chest joint: ribcage widening to the shoulders (a V
## from behind), sloping trapezius up to the neck.
static func chest_body() -> ArrayMesh:
	return loft("chest", [
		[0.335, 0.062, 0.058, 0.004],
		[0.300, 0.120, 0.078, 0.010],
		[0.250, 0.195, 0.100, 0.008],
		[0.170, 0.205, 0.122, 0.0],
		[0.060, 0.188, 0.124, -0.004],
		[-0.050, 0.162, 0.112, 0.0],
	], 16)


static func neck() -> ArrayMesh:
	return loft("neck", [
		[0.40, 0.050, 0.054, 0.006],
		[0.33, 0.056, 0.060, 0.010],
		[0.28, 0.064, 0.064, 0.012],
	], 12)


## Head round its joint: chin and jaw in front, cheekbones, brow, skull.
static func head() -> ArrayMesh:
	return loft("head", [
		[0.128, 0.020, 0.024, 0.006],
		[0.112, 0.060, 0.072, 0.008],
		[0.080, 0.084, 0.098, 0.006],
		[0.048, 0.089, 0.104, 0.002],
		[0.030, 0.090, 0.106, 0.000],    # brow ridge
		[0.012, 0.089, 0.100, 0.002],    # eye line (sockets sit in front of it)
		[-0.012, 0.088, 0.100, -0.004],  # cheekbones
		[-0.040, 0.080, 0.092, -0.010],
		[-0.070, 0.068, 0.080, -0.020],  # jaw corner
		[-0.092, 0.050, 0.062, -0.032],
		[-0.108, 0.030, 0.040, -0.046],  # chin
		[-0.116, 0.014, 0.020, -0.056],
	], 16)


## Short beard over the jaw and chin (from below the cheekbones), set forward so its back half stays
## inside the head (sideburns at the cheeks, no neck beard behind).
static func beard() -> ArrayMesh:
	return loft("beard", [
		[-0.038, 0.083, 0.058, -0.040],
		[-0.052, 0.081, 0.072, -0.034],
		[-0.070, 0.071, 0.070, -0.036],
		[-0.092, 0.054, 0.056, -0.040],
		[-0.110, 0.032, 0.036, -0.050],
		[-0.121, 0.012, 0.015, -0.058],
	], 16)


## A wedge of a nose: bridge to tip, wider at the nostrils.
static func nose() -> ArrayMesh:
	return loft("nose", [
		[0.014, 0.008, 0.006, 0.0],
		[-0.012, 0.014, 0.014, -0.008],
		[-0.022, 0.016, 0.010, -0.004],
	], 6)


## Upper arm from the shoulder joint: rounded deltoid cap, biceps in front,
## narrowing to the elbow.
static func upper_arm(length: float) -> ArrayMesh:
	return loft("uarm%.3f" % length, [
		[0.06, 0.050, 0.055, 0.0],
		[0.02, 0.074, 0.074, 0.0],
		[-0.05, 0.068, 0.068, -0.002],
		[-length * 0.45, 0.056, 0.062, -0.008],
		[-length * 0.8, 0.050, 0.054, -0.004],
		[-length - 0.02, 0.046, 0.048, 0.0],
	], 12)


## Forearm sleeve from the elbow: full just below the elbow, tapering and
## flattening to the wrist. `thin` is the bare-skin version (rolled sleeves).
static func forearm(length: float, thin: bool = false) -> ArrayMesh:
	var k := 0.82 if thin else 1.0
	return loft("farm%.3f%s" % [length, "t" if thin else ""], [
		[0.03, 0.050 * k, 0.050 * k, 0.0],
		[-length * 0.22, 0.054 * k, 0.051 * k, 0.0],
		[-length * 0.55, 0.047 * k, 0.043 * k, 0.0],
		[-length * 0.88, 0.040 * k, 0.034 * k, 0.0],
	], 12)


## Low-poly ball to fill a bending joint (knee, elbow).
static func joint(radius: float) -> ArrayMesh:
	return loft("joint%.3f" % radius, [
		[radius, 0.0, 0.0, 0.0],
		[radius * 0.6, radius * 0.8, radius * 0.8, 0.0],
		[0.0, radius, radius, 0.0],
		[-radius * 0.6, radius * 0.8, radius * 0.8, 0.0],
		[-radius, 0.0, 0.0, 0.0],
	], 10)
