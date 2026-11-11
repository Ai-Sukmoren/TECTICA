extends RigidBody3D
## M67-style fragmentation grenade: bounces, rolls, explodes after its fuse.
## Damage falls off with distance and is blocked by walls/cover.

const FX = preload("res://scripts/fx/fx.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Layers = preload("res://scripts/core/layers.gd")
const Blast = preload("res://scripts/weapons/blast.gd")
const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")

var thrower: Node
## Another peer's grenade: same flight and blast effects, but no damage here.
var cosmetic := false
var fuse := 2.2
var damage := 150.0
var radius := 6.5
var _clink_cd := 0.0
var _exploded := false
var _landed := false


func _ready() -> void:
	collision_layer = Layers.DEBRIS
	collision_mask = Layers.WORLD
	mass = 0.4
	continuous_cd = true
	angular_damp = 1.5
	linear_damp = 0.0
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.9
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.05
	cs.shape = sh
	add_child(cs)
	var body := MeshInstance3D.new()
	body.mesh = ML.sphere(0.042, false, 12)
	body.scale = Vector3(1.0, 1.25, 1.0)
	body.material_override = M.painted_metal("grenade", Color(0.25, 0.3, 0.2))
	add_child(body)
	var spoon := MeshInstance3D.new()
	spoon.mesh = ML.box(Vector3(0.014, 0.07, 0.012))
	spoon.material_override = M.solid(Color(0.5, 0.5, 0.48), 0.4, 0.8)
	spoon.position = Vector3(0.03, 0.03, 0)
	add_child(spoon)
	add_to_group("grenades")


func _on_body_entered(_b: Node) -> void:
	# first impact: the grenade bites and rolls only a short way
	if not _landed:
		_landed = true
		linear_velocity = Vector3(linear_velocity.x * 0.3, linear_velocity.y * 0.4, linear_velocity.z * 0.3)
		linear_damp = 3.5
		angular_damp = 4.0
	if _clink_cd <= 0.0 and linear_velocity.length() > 1.0:
		_clink_cd = 0.15
		Sfx.play(self, "casing", global_position, -4.0, 0.3)


func _physics_process(delta: float) -> void:
	_clink_cd -= delta
	fuse -= delta
	if fuse <= 0.0 and not _exploded:
		explode()


func explode() -> void:
	_exploded = true
	var pos := global_position
	print_verbose("[grenade] exploded at ", pos)
	Blast.detonate(self, pos, damage, radius, thrower if is_instance_valid(thrower) else null, [], not cosmetic)
	queue_free()
