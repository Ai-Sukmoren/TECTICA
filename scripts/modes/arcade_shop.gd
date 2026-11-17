extends Node3D
## The Zombie Survival shop as a place: the NEO-TOKYO ARCADE cabinet stands on
## open floor a few metres from the start of every zombie map. The shop opens
## only within REACH of it ([interact]), between waves. Placement waits one
## physics frame (the level's collision must be in the physics space), then
## tries rings round the spawn for a spot with floor at spawn height and room
## for the cabinet, its screen turned to the spawn. A pink lamp marks it.

const Layers = preload("res://scripts/core/layers.gd")
const MODEL := "res://assets/thirdparty/arcade/arcade.glb"
const REACH := 2.4                   # metres from the cabinet the shop opens
const SIZE := Vector3(0.95, 2.0, 1.3) # the cabinet's footprint and height (m)

var placed := false


## Stands the cabinet near `spawn` once physics is ready.
func place(spawn: Vector3) -> void:
	name = "ArcadeShop"
	await get_tree().physics_frame
	await get_tree().physics_frame
	var at := _find_spot(spawn)
	global_position = at
	# screen faces the spawn (the model's screen side is its +Z)
	var to := Vector3(spawn.x - at.x, 0, spawn.z - at.z)
	if to.length() > 0.1:
		rotation.y = atan2(to.x, to.z)
	_build()
	placed = true


func in_reach(p: Node3D) -> bool:
	return placed and p != null and p.global_position.distance_to(global_position) < REACH


func _find_spot(spawn: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = SIZE + Vector3(0.3, -0.2, 0.3)   # a little room round it, clear of the floor
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.WORLD
	for dist in [3.5, 5.0, 6.5, 8.0, 2.5, 10.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var p := spawn + Vector3(sin(a), 0, cos(a)) * float(dist)
			var down := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p - Vector3(0, 1.5, 0), Layers.WORLD)
			var hit := space.intersect_ray(down)
			if hit.is_empty() or absf(float(hit.position.y) - spawn.y) > 0.6:
				continue
			var floor_at: Vector3 = hit.position
			q.transform = Transform3D(Basis.IDENTITY, floor_at + Vector3(0, SIZE.y * 0.5 + 0.12, 0))
			if not space.intersect_shape(q, 1).is_empty():
				continue
			# a clear line from the spawn, so it can be walked to and seen
			var los := PhysicsRayQueryParameters3D.create(spawn + Vector3(0, 1.2, 0), floor_at + Vector3(0, 1.2, 0), Layers.WORLD)
			if not space.intersect_ray(los).is_empty():
				continue
			return floor_at
	return spawn + Vector3(2.5, 0, 0)


func _build() -> void:
	if ResourceLoader.exists(MODEL):
		add_child((load(MODEL) as PackedScene).instantiate())
	else:
		# stand-in when the model pack is missing: a dark cabinet with a lit screen
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = SIZE
		mi.mesh = bm
		mi.position.y = SIZE.y * 0.5
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.06, 0.12)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.2, 0.7)
		m.emission_energy_multiplier = 0.4
		mi.material_override = m
		add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = SIZE
	cs.shape = bs
	cs.position.y = SIZE.y * 0.5
	body.add_child(cs)
	add_child(body)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.3, 0.6)
	lamp.light_color = Color(1.0, 0.3, 0.75)
	lamp.light_energy = 1.6
	lamp.omni_range = 5.0
	add_child(lamp)
