extends Node3D
## Cosmetic metal keepsakes. Kept outside the skinned model so finishes and
## sticker bounds never recolour the hardware or include the hanging charm.
const ML = preload("res://scripts/core/mesh_lib.gd")
const IDS := ["", "dog_tags", "cartridge", "compass"]
const LABELS := ["NONE", "STEEL DOG TAGS", "BRASS CARTRIDGE", "FIELD COMPASS"]
const MAX_SWING := 0.65
var charm_id := ""
var _swing: Node3D
var _angle := Vector2.ZERO
var _velocity := Vector2.ZERO
var _previous_position := Vector3.ZERO
var _previous_velocity := Vector3.ZERO
var _sampled := false
static var _steel: StandardMaterial3D
static var _dark: StandardMaterial3D
static var _brass: StandardMaterial3D
static var _red: StandardMaterial3D
static var _ring_mesh: TorusMesh

static func sanitize(id: String) -> String:
	return id if id in IDS else ""

static func label(id: String) -> String:
	return LABELS[IDS.find(sanitize(id))]

static func _materials() -> void:
	if _steel != null:
		return
	_steel = _material(Color(0.49, 0.53, 0.55), 0.85, 0.32)
	_dark = _material(Color(0.045, 0.055, 0.06), 0.55, 0.5)
	_brass = _material(Color(0.6, 0.39, 0.12), 0.82, 0.3)
	_red = _material(Color(0.65, 0.075, 0.035), 0.1, 0.55)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.0025
	_ring_mesh.outer_radius = 0.004
	_ring_mesh.rings = 12
	_ring_mesh.ring_segments = 8

static func _material(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	return m

func setup(id: String, pistol: bool) -> void:
	charm_id = sanitize(id)
	name = "WeaponCharm"
	_materials()
	# Rear receiver / grip-heel lanyard position, outside the support-hand path.
	position = Vector3(-0.028, -0.057, 0.025) if pistol else Vector3(-0.058, 0.065, 0.025)
	_part(self, ML.cylinder(0.0045, 0.0045, 0.006, 12), _dark, Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	_part(self, _ring_mesh, _steel, Vector3(-0.004, -0.003, 0), Vector3(0, 0, PI * 0.5))
	_swing = Node3D.new()
	_swing.name = "Pendulum"
	_swing.position = Vector3(-0.006, -0.005, 0)
	add_child(_swing)
	for i in 3:
		_part(_swing, _ring_mesh, _steel, Vector3(0, -0.006 - i * 0.006, 0), Vector3(PI * 0.5 if i % 2 else 0, 0, PI * 0.5))
	match charm_id:
		"dog_tags":
			_tag(Vector3(0, -0.039, 0), 0.08)
			_tag(Vector3(0.004, -0.041, 0.009), -0.18)
		"cartridge":
			_part(_swing, ML.cylinder(0.005, 0.005, 0.023, 16), _brass, Vector3(0, -0.035, 0))
			_part(_swing, ML.cylinder(0.0058, 0.0058, 0.002, 16), _brass, Vector3(0, -0.024, 0))
			_part(_swing, ML.cylinder(0.003, 0.005, 0.006, 16), _brass, Vector3(0, -0.049, 0))
			_part(_swing, ML.cylinder(0.0005, 0.003, 0.011, 16), _steel, Vector3(0, -0.057, 0), Vector3(PI, 0, 0))
		"compass":
			_compass()

func _tag(at: Vector3, roll: float) -> void:
	var tag := Node3D.new()
	tag.position = at
	tag.rotation.x = roll
	_swing.add_child(tag)
	_part(tag, ML.rbox(Vector3(0.002, 0.033, 0.019), 0.0009), _steel, Vector3.ZERO)
	_part(tag, ML.rbox(Vector3(0.0024, 0.028, 0.015), 0.0008), _dark, Vector3.ZERO)
	_part(tag, ML.rbox(Vector3(0.0028, 0.026, 0.013), 0.0008), _steel, Vector3.ZERO)
	for row in 3:
		_part(tag, ML.box(Vector3(0.0006, 0.001, 0.009 - row * 0.001)), _dark, Vector3(-0.0015, 0.004 - row * 0.004, 0))

func _compass() -> void:
	var center := Vector3(0, -0.038, 0)
	var side := Vector3(0, 0, PI * 0.5)
	_part(_swing, ML.cylinder(0.015, 0.015, 0.005, 24), _brass, center, side)
	_part(_swing, ML.cylinder(0.012, 0.012, 0.0054, 24), _dark, center, side)
	for i in 4:
		var a := i * PI * 0.5
		_part(_swing, ML.box(Vector3(0.0007, 0.003, 0.001)), _steel, center + Vector3(-0.003, cos(a) * 0.009, sin(a) * 0.009), Vector3(a, 0, 0))
	_part(_swing, ML.cylinder(0, 0.002, 0.008, 3), _red, center + Vector3(-0.0035, 0.004, 0))
	_part(_swing, ML.cylinder(0, 0.002, 0.008, 3), _steel, center + Vector3(-0.0035, -0.004, 0), Vector3(PI, 0, 0))

func _part(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var p := MeshInstance3D.new()
	p.mesh = mesh
	p.material_override = material
	p.position = at
	p.rotation = rot
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)

func kick() -> void:
	_velocity += Vector2(0.75, -0.35)

func _process(delta: float) -> void:
	if _swing == null or not is_visible_in_tree():
		_sampled = false
		return
	# Cosmetic starting values: bounded 37-degree swing and 120 Hz integration.
	# A 1-second hitch must stay finite; reduce spring force if stability fails.
	var dt := clampf(delta, 0.0001, 0.05)
	var motion := Vector3.ZERO
	if _sampled and delta < 0.1:
		var v := (global_position - _previous_position) / dt
		motion = global_basis.inverse() * ((v - _previous_velocity) / dt).limit_length(25.0)
		_previous_velocity = v
	else:
		_previous_velocity = Vector3.ZERO
	_previous_position = global_position
	_sampled = true
	var down := global_basis.inverse() * Vector3.DOWN
	var target := Vector2(atan2(-down.z, -down.y), atan2(down.x, -down.y)).clamp(Vector2.ONE * -MAX_SWING, Vector2.ONE * MAX_SWING)
	target += Vector2(motion.z, -motion.x) * 0.008
	var steps := maxi(1, int(ceil(dt * 120.0)))
	var h := dt / steps
	for i in steps:
		_velocity += ((target - _angle) * 80.0 - _velocity * 11.0) * h
		_angle = (_angle + _velocity * h).clamp(Vector2.ONE * -MAX_SWING, Vector2.ONE * MAX_SWING)
	_swing.rotation = Vector3(_angle.x, 0, _angle.y)
