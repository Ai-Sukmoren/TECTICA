extends RigidBody3D
## M67-style fragmentation grenade: bounces, rolls, explodes after its fuse.
## Damage falls off with distance and is blocked by walls/cover.
## kind "flash": M84 stun grenade, no damage; blinds whoever sees the burst.

const FX = preload("res://scripts/fx/fx.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Layers = preload("res://scripts/core/layers.gd")
const Blast = preload("res://scripts/weapons/blast.gd")
const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const PP = preload("res://scripts/core/pack_props.gd")
const Net = preload("res://scripts/net/net.gd")

var thrower: Node
var kind := "frag"
const FLASH_RADIUS := 13.0
const FLASH_MAX := 4.5   # seconds of blindness at point blank, looking at it
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
	if kind == "flash":
		fuse = 1.6
		if not PP.add(self, "m84", Vector3(0, -0.06, 0), 0.0, 0.12).is_empty():
			add_to_group("grenades")
			return
	# M67 model from asset pack 4 (centred on the physics sphere)
	if not PP.add(self, "m67", Vector3(0, -0.055, 0), 0.0, 0.11).is_empty():
		add_to_group("grenades")
		return
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
	if kind == "flash":
		_flash_burst(global_position + Vector3.UP * 0.15)
		queue_free()
		return
	var pos := global_position
	print_verbose("[grenade] exploded at ", pos)
	Blast.detonate(self, pos, damage, radius, thrower if is_instance_valid(thrower) else null, [], not cosmetic)
	queue_free()


## M84 burst: a blinding light, a crack, and a stun for everyone who sees it.
## Strength falls off with distance and with how far they are looking away;
## walls and cover block it. AI is stunned where it is simulated; each
## machine blinds its own local player.
func _flash_burst(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.97, 0.9)
	light.light_energy = 18.0
	light.omni_range = 16.0
	get_tree().current_scene.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_callback(light.queue_free)
	FX.chips(self, pos, Vector3.UP, Color(0.95, 0.95, 0.9), 10, 0.02, 14, 2.4)
	Sfx.play(self, "flashbang", pos, 6.0, 0.05)
	var space := get_world_3d().direct_space_state
	var victims: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player")
	for v in victims:
		if not is_instance_valid(v) or v.get("is_dead") == true or not v.has_method("flashbang"):
			continue
		var local_player: bool = v.is_in_group("player") and not bool(v.get("puppet"))
		var ai_here: bool = not v.is_in_group("player") and Net.owns(v)
		if not local_player and not ai_here:
			continue
		var eye: Vector3 = v.global_position + Vector3.UP * 1.6
		var d := eye.distance_to(pos)
		if d > FLASH_RADIUS:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos, eye, Layers.WORLD)
		if not space.intersect_ray(q).is_empty():
			continue   # behind a wall
		var look := Vector3(-sin(float(v.aim_yaw)), 0, -cos(float(v.aim_yaw)))
		var to := (pos - eye)
		to.y = 0.0
		var facing := 1.0 if to.length() < 0.5 else clampf(0.55 + 0.45 * look.dot(to.normalized()), 0.2, 1.0)
		var strength := clampf(1.15 - d / FLASH_RADIUS, 0.0, 1.0) * facing
		if strength > 0.05:
			v.flashbang(strength * FLASH_MAX, strength)
			if ai_here and is_instance_valid(thrower) and thrower.is_in_group("player") and not bool(thrower.get("puppet")):
				preload("res://scripts/core/progression.gd").on_flash_blind()
