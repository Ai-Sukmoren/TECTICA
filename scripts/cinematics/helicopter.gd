extends Node3D
## Utility helicopter for cutscenes: cabin with open side doors, cockpit glass,
## engine deck, tapered tail boom with fin and stabiliser, skids, a 4-blade main
## rotor and a tail rotor (both spin with `rotor`, a translucent disc fades in at
## speed), navigation lights, a blinking anti-collision beacon, a dim red cabin
## light and a searchlight. Built from primitives like the rest of the valley.
## Nose points -Z.

const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")

## 0 = stopped, 1 = full flight speed (blade spin and the blur disc follow it)
var rotor := 1.0
var _main_rotor: Node3D
var _tail_rotor: Node3D
var _disc: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _beacon: OmniLight3D
var _beacon_mesh: MeshInstance3D
var searchlight: SpotLight3D
var _t := 0.0


func _ready() -> void:
	var olive := M.painted_metal("heli_olive", Color(0.21, 0.24, 0.17))
	var dark := M.solid(Color(0.07, 0.075, 0.07), 0.6, 0.3)
	var steel := M.solid(Color(0.32, 0.33, 0.32), 0.45, 0.7)
	var glass := M.solid(Color(0.06, 0.09, 0.11), 0.05, 0.6)
	var hollow := M.solid(Color(0.02, 0.022, 0.025), 0.9)
	# cabin: a box with chamfered roof and belly
	_part(ML.box(Vector3(2.0, 1.55, 3.4)), olive, Vector3(0, 1.45, 0.2))
	_part(ML.box(Vector3(1.7, 0.35, 3.2)), olive, Vector3(0, 2.33, 0.25))
	_part(ML.box(Vector3(1.8, 0.3, 3.3)), olive, Vector3(0, 0.6, 0.2))
	# open side doors: dark recesses, a red cabin light inside
	for sx in [-1.0, 1.0]:
		_part(ML.box(Vector3(0.05, 1.15, 1.5)), hollow, Vector3(sx * 1.01, 1.45, 0.55))
		_part(ML.box(Vector3(0.06, 1.25, 0.08)), steel, Vector3(sx * 1.02, 1.45, -0.24))
	var cab := OmniLight3D.new()
	cab.light_color = Color(1.0, 0.25, 0.15)
	cab.light_energy = 0.6
	cab.omni_range = 2.6
	cab.position = Vector3(0, 1.9, 0.5)
	add_child(cab)
	# nose and cockpit
	_part(ML.box(Vector3(1.8, 1.25, 1.2)), olive, Vector3(0, 1.3, -2.05))
	_part(ML.sphere(0.95, false, 14), olive, Vector3(0, 1.1, -2.65), Vector3.ZERO, Vector3(0.95, 0.7, 0.9))
	_part(ML.box(Vector3(1.6, 0.75, 0.06)), glass, Vector3(0, 1.75, -2.72), Vector3(-0.5, 0, 0))
	for sx in [-1.0, 1.0]:
		_part(ML.box(Vector3(0.06, 0.6, 1.0)), glass, Vector3(sx * 0.91, 1.62, -2.05))
		_part(ML.box(Vector3(0.05, 0.75, 0.05)), dark, Vector3(sx * 0.45, 1.75, -2.7), Vector3(-0.5, 0, 0))
	# engine deck, exhausts, intake
	_part(ML.box(Vector3(1.1, 0.55, 2.4)), olive, Vector3(0, 2.75, 0.55))
	for sx in [-1.0, 1.0]:
		_part(ML.cylinder(0.16, 0.2, 0.6, 10), dark, Vector3(sx * 0.42, 2.8, 1.85), Vector3(PI * 0.5, 0, 0))
	_part(ML.box(Vector3(0.7, 0.25, 0.4)), dark, Vector3(0, 2.95, -0.55))
	# tail boom, fin, stabiliser
	_part(ML.cylinder(0.24, 0.42, 5.6, 12), olive, Vector3(0, 2.05, 4.55), Vector3(PI * 0.5, 0, 0))
	_part(ML.box(Vector3(0.12, 1.7, 1.0)), olive, Vector3(0, 2.8, 7.3), Vector3(-0.3, 0, 0))
	_part(ML.box(Vector3(1.9, 0.08, 0.55)), olive, Vector3(0, 2.05, 6.6))
	# skids with struts
	for sx in [-1.0, 1.0]:
		_part(ML.cylinder(0.06, 0.06, 3.9, 8), steel, Vector3(sx * 1.05, 0.06, 0.1), Vector3(PI * 0.5, 0, 0))
		_part(ML.cylinder(0.06, 0.06, 0.5, 8), steel, Vector3(sx * 1.05, 0.12, -1.85), Vector3(-0.9, 0, 0))
		for z in [-0.8, 1.2]:
			_part(ML.cylinder(0.05, 0.05, 0.7, 8), steel, Vector3(sx * 0.95, 0.4, z), Vector3(0, 0, sx * 0.35))
	# main rotor: mast, hub, four blades, the blur disc
	_part(ML.cylinder(0.12, 0.14, 0.5, 10), dark, Vector3(0, 3.25, 0.1))
	_main_rotor = Node3D.new()
	_main_rotor.position = Vector3(0, 3.5, 0.1)
	add_child(_main_rotor)
	var hub := MeshInstance3D.new()
	hub.mesh = ML.cylinder(0.25, 0.25, 0.16, 12)
	hub.material_override = dark
	_main_rotor.add_child(hub)
	for k in 4:
		var blade := MeshInstance3D.new()
		blade.mesh = ML.box(Vector3(0.36, 0.05, 6.6))
		blade.material_override = dark
		blade.position = Basis(Vector3.UP, k * PI * 0.5) * Vector3(0, 0, 3.4)
		blade.rotation.y = k * PI * 0.5
		_main_rotor.add_child(blade)
	_disc = MeshInstance3D.new()
	_disc.mesh = ML.cylinder(6.9, 6.9, 0.01, 40)
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.albedo_color = Color(0.05, 0.05, 0.05, 0.0)
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc.material_override = _disc_mat
	_disc.position = Vector3(0, 3.5, 0.1)
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	# tail rotor on the fin's left side
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(-0.14, 2.95, 7.45)
	add_child(_tail_rotor)
	for k in 3:
		var tb := MeshInstance3D.new()
		tb.mesh = ML.box(Vector3(0.03, 1.15, 0.13))
		tb.material_override = dark
		tb.position = Basis(Vector3.RIGHT, k * TAU / 3.0) * Vector3(0, 0.55, 0)
		tb.rotation.x = k * TAU / 3.0
		_tail_rotor.add_child(tb)
	# navigation lights, anti-collision beacon, searchlight
	_nav_light(Vector3(-1.02, 1.35, -1.1), Color(1.0, 0.1, 0.08))
	_nav_light(Vector3(1.02, 1.35, -1.1), Color(0.1, 1.0, 0.25))
	_nav_light(Vector3(0, 2.35, 7.85), Color(1, 1, 1))
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.1, 0.05)
	_beacon.omni_range = 5.0
	_beacon.position = Vector3(0, 3.05, 1.6)
	add_child(_beacon)
	_beacon_mesh = _part(ML.sphere(0.07, false, 8), M.solid(Color(1.0, 0.15, 0.1)), Vector3(0, 3.05, 1.6))
	searchlight = SpotLight3D.new()
	searchlight.position = Vector3(0, 0.45, -2.4)
	searchlight.rotation.x = -1.05
	searchlight.spot_range = 45.0
	searchlight.spot_angle = 16.0
	searchlight.light_energy = 0.0
	searchlight.light_volumetric_fog_energy = 2.5
	add_child(searchlight)


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	add_child(mi)
	return mi


func _nav_light(pos: Vector3, col: Color) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.8
	l.omni_range = 1.6
	l.position = pos
	add_child(l)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	_part(ML.sphere(0.05, false, 6), m, pos)


func _process(delta: float) -> void:
	_t += delta
	_main_rotor.rotate_y(delta * 26.0 * rotor)
	_tail_rotor.rotate_x(delta * 70.0 * rotor)
	# the blades blur into a faint disc at speed
	_disc_mat.albedo_color.a = smoothstep(0.35, 1.0, rotor) * 0.22
	for c in _main_rotor.get_children():
		if c is MeshInstance3D and c != _main_rotor.get_child(0):
			(c as MeshInstance3D).visible = rotor < 0.85 or fposmod(_t * 31.0, 1.0) < 0.5
	var on := fposmod(_t, 1.1) < 0.12
	_beacon.light_energy = 3.0 if on else 0.0
	_beacon_mesh.visible = on
