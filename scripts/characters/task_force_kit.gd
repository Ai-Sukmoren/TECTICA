extends RefCounted
## Outfit geometry in the operator's joint space. Each section gives its height,
## half-width, front and back. Shared meshes keep the kit cheap to instantiate.

const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")

const SECTIONS := {
	"helmet": [[0.113, 0.064, -0.063, 0.078], [0.081, 0.103, -0.108, 0.11], [0.021, 0.117, -0.132, 0.126], [-0.009, 0.109, -0.122, 0.121]],
	"mask": [[0.03, 0.083, -0.106, 0.045], [0.005, 0.103, -0.126, 0.068], [-0.048, 0.093, -0.125, 0.06], [-0.106, 0.062, -0.105, 0.028], [-0.126, 0.034, -0.084, -0.012]],
	"shirt": [[0.319, 0.08, -0.08, 0.078], [0.266, 0.18, -0.103, 0.104], [0.196, 0.211, -0.128, 0.126],
		[0.08, 0.181, -0.134, 0.13], [-0.035, 0.159, -0.12, 0.117], [-0.091, 0.138, -0.102, 0.101]],
	"hem": [[0.209, 0.151, -0.115, 0.114], [0.13, 0.153, -0.117, 0.118], [-0.014, 0.168, -0.13, 0.13], [-0.049, 0.176, -0.138, 0.14]],
	"sleeve": [[0.058, 0.034, -0.042, 0.044], [0.028, 0.069, -0.071, 0.07],
		[-0.048, 0.076, -0.077, 0.077], [-0.119, 0.064, -0.067, 0.067]],
	# boots sized to the leg: the shaft hugs the ankle (shin 8 cm across there), 23 cm heel to toe
	"boot": [[0.105, 0.047, -0.05, 0.05], [0.045, 0.05, -0.062, 0.056], [-0.013, 0.052, -0.142, 0.06], [-0.046, 0.054, -0.166, 0.064], [-0.065, 0.054, -0.162, 0.062]],
	"sole": [[-0.06, 0.055, -0.165, 0.064], [-0.077, 0.056, -0.168, 0.064], [-0.086, 0.052, -0.155, 0.059]],
}
static var _meshes := {}

static func shell(key: String) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var rings := []
	for row in SECTIONS[key]:
		var y := float(row[0])
		var x := float(row[1])
		var front := float(row[2])
		var back := float(row[3])
		var bevel := (back - front) * 0.19
		rings.append([Vector3(0, y, front), Vector3(x * 0.69, y, front + bevel * 0.28),
			Vector3(x, y, front + bevel), Vector3(x, y, back-bevel), Vector3(x * 0.64, y, back),
			Vector3(-x * 0.64, y, back), Vector3(-x, y, back-bevel), Vector3(-x, y, front + bevel),
			Vector3(-x * 0.69, y, front + bevel * 0.28)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = rings[0].size()
	for k in rings.size() - 1:
		for i in count:
			var j := (i + 1) % count
			var a: Vector3 = rings[k][i]
			var b: Vector3 = rings[k][j]
			var c: Vector3 = rings[k + 1][j]
			var d: Vector3 = rings[k + 1][i]
			_face(st, a, c, b)
			_face(st, a, d, c)
	for i in range(1, count - 1):
		_face(st, rings[0][0], rings[0][i], rings[0][i + 1])
		_face(st, rings[-1][0], rings[-1][i + 1], rings[-1][i])
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh

static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for v: Vector3 in [a, b, c]:
		var uv := Vector2(v.x, v.y)
		if absf(normal.y) > 0.7:
			uv = Vector2(v.x, v.z)
		elif absf(normal.x) > 0.7:
			uv = Vector2(v.z, v.y)
		st.set_uv(uv * 4.0)
		st.set_normal(normal)
		st.add_vertex(v)

static func head(rig, p: Dictionary) -> void:
	var mask: Material = p.face
	var amber: Material = p.get("visor", M.painted_metal("task_force_visor", Color("#eca03c")))
	var dark := M.matte("task_force_gasket", Color("#171f20"), 0.8)
	rig._mesh(rig.head, shell("mask"), mask, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		var bank := Vector3(0, -side * 0.28, side * 0.16)
		var center := Vector3(side * 0.05, 0.002, -0.119)
		rig._mesh(rig.head, ML.rbox(Vector3(0.103, 0.046, 0.018)), dark, center, bank)
		rig._mesh(rig.head, ML.rbox(Vector3(0.088, 0.028, 0.012)), amber, center + Vector3(0, 0, -0.009), bank)
		for i in 3:
			var vent := Vector3(side * (0.047 - i * 0.003), -0.049 - i * 0.012, -0.124 + i * 0.004)
			rig._mesh(rig.head, ML.rbox(Vector3(0.037, 0.004, 0.005)), dark, vent, bank)
	rig._build_headgear(rig.head, p)


static func helmet(rig, p: Dictionary) -> void:
	var dark := M.matte("task_force_gasket", Color("#171f20"), 0.8)
	var helmet: Node3D = rig._node(rig.head, "Helmet", Vector3(0, 0.042, 0))
	rig.helmet_node = helmet
	rig._mesh(helmet, shell("helmet"), p.helmet, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		rig._mesh(helmet, ML.rbox(Vector3(0.019, 0.052, 0.078)), dark, Vector3(side * 0.108, -0.015, 0.003), Vector3(0.18, 0, 0))
		rig._mesh(helmet, ML.rbox(Vector3(0.022, 0.031, 0.06)), p.vest, Vector3(side * 0.115, -0.015, 0.003), Vector3(0.18, 0, 0))
	if p.get("nvg", false):
		# flip-up night vision on the shroud, its lenses in the visor's colour
		var lens: Material = p.get("visor", dark)
		rig._mesh(helmet, ML.rbox(Vector3(0.05, 0.026, 0.024)), dark, Vector3(0, 0.072, -0.118))
		rig._mesh(helmet, ML.rbox(Vector3(0.024, 0.05, 0.026)), dark, Vector3(0, 0.1, -0.13), Vector3(0.45, 0, 0))
		for sx in [-1.0, 1.0]:
			rig._mesh(helmet, ML.cylinder(0.018, 0.021, 0.07, 10), dark, Vector3(sx * 0.026, 0.135, -0.13), Vector3(0.55, 0, 0))
			rig._mesh(helmet, ML.cylinder(0.016, 0.016, 0.005, 10), lens, Vector3(sx * 0.026, 0.165, -0.11), Vector3(0.55, 0, 0))

static func torso(rig, p: Dictionary) -> void:
	rig._mesh(rig.chest, shell("shirt"), p.get("shirt", p.camo), Vector3.ZERO)
	rig._mesh(rig.spine, shell("hem"), p.get("shirt", p.camo), Vector3.ZERO)
	# A small raised collar and stitched badge leave the shoulder line exposed.
	rig._mesh(rig.chest, ML.cylinder(0.066, 0.086, 0.043, 12), p.face, Vector3(0, 0.315, 0))
	rig._mesh(rig.chest, ML.rbox(Vector3(0.063, 0.033, 0.007)), p.face,
		Vector3(-0.081, 0.165, -0.121), Vector3(0, 0.17, 0))
	var trim: Material = p.get("badge", M.matte("task_force_embroidery", Color("#cb9854"), 0.85))
	for i in 2:
		rig._mesh(rig.chest, ML.rbox(Vector3(0.009, 0.019, 0.004)), trim,
			Vector3(-0.091 + i * 0.019, 0.165, -0.127), Vector3(0, 0.17, -0.3))


static func limbs(rig, p: Dictionary) -> void:
	for i in 2:
		# the short shirt sleeve sits at the shoulder, right beside the eye: first person only casts its shadow
		rig._mesh(rig.shoulders[i], shell("sleeve"), p.get("shirt", p.camo), Vector3.ZERO).set_meta("fp_shadow_only", true)
		rig._mesh(rig.feet[i], shell("boot"), p.boots, Vector3.ZERO)
		rig._mesh(rig.feet[i], shell("sole"), p.gear, Vector3.ZERO)
		for strap in 2:
			rig._mesh(rig.feet[i], ML.rbox(Vector3(0.08, 0.009, 0.015)), p.gear,
				Vector3(0, 0.029 - strap * 0.013, -0.072 - strap * 0.021), Vector3(-0.45, 0, 0))
