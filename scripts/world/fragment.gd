extends RigidBody3D
## A physics chunk of a destroyed prop. Tumbles, settles, then shrinks away.
## A global cap keeps the number of live fragments bounded.

const Layers = preload("res://scripts/core/layers.gd")
const MAX_LIVE := 200

static var _live: Array = []

var life := 9.0
var _shrink := 1.2
var _mesh: MeshInstance3D


static func spawn(ctx: Node, mesh: Mesh, mat: Material, xf: Transform3D, half: Vector3,
		origin: Vector3, dir: Vector3, power: float) -> void:
	if ctx == null or not ctx.is_inside_tree():
		return
	var root := ctx.get_tree().current_scene
	if root == null:
		return
	while _live.size() >= MAX_LIVE:
		var old = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var f = load("res://scripts/world/fragment.gd").new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	# the mesh is centred on its AABB; keep any scale baked into xf
	var basis_scale := xf.basis.get_scale()
	mi.scale = basis_scale
	mi.position = -mesh.get_aabb().get_center() * basis_scale
	f.add_child(mi)
	f._mesh = mi
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (half * 2.0).max(Vector3.ONE * 0.04)
	cs.shape = bs
	f.add_child(cs)
	f.mass = clampf(bs.size.x * bs.size.y * bs.size.z * 300.0, 0.2, 25.0)
	f.life = randf_range(7.0, 11.0)
	root.add_child(f)
	f.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	f.reset_physics_interpolation()
	var away := xf.origin - origin
	away = away.normalized() if away.length() > 0.01 else Vector3.UP
	f.linear_velocity = (away * randf_range(1.5, 4.0) + dir * randf_range(0.5, 2.0)) * power \
			+ Vector3.UP * randf_range(1.0, 3.0) * power
	f.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 8.0 * power
	_live.append(f)


func _ready() -> void:
	collision_layer = Layers.DEBRIS
	collision_mask = Layers.WORLD | Layers.DEBRIS
	var pm := PhysicsMaterial.new()
	pm.friction = 0.85
	pm.bounce = 0.12
	physics_material_override = pm
	linear_damp = 0.3
	angular_damp = 1.2
	if _mesh:
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _physics_process(delta: float) -> void:
	life -= delta
	if life < _shrink:
		if not freeze:
			freeze = true
			collision_layer = 0
		_mesh.scale *= maxf(life / _shrink, 0.02) / maxf((life + delta) / _shrink, 0.02)
		global_position.y -= delta * 0.05
	if life <= 0.0:
		_live.erase(self)
		queue_free()
