extends SceneTree
## Multiplayer spawn spots (joiners, respawns, deathmatch) must be standable:
## no overlap with the map and a floor below. Exits 1 on failure.
##   godot --headless --path . -s res://tests/mp_spawn_test.gd -- <zombie|pvp> <map>
const Main = preload("res://scripts/main.gd")
var f := 0
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a[0] == "pvp":
		print("host=", preload("res://scripts/net/net.gd").host("pvp", 7795))
	Main.saved_mode = a[0]
	Main.saved_map = a[1]
	Main.quick_restart = true
	Main.saved_quality = 0
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	current_scene = m
func _physics_process(_d: float) -> bool:
	f += 1
	if f < 120:
		return false
	var m = current_scene
	var space: PhysicsDirectSpaceState3D = m.player.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	var bad_wall := 0
	var bad_floor := 0
	var n := 40
	var names := {}
	for i in n + 1:
		var pos: Vector3 = m.player.global_position if i == n else m.net_spawn_for(1000 + i)[0]
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(), pos + Vector3(0, 0.95, 0))
		q.collision_mask = 1
		q.exclude = [m.player.get_rid()]
		var hit := space.intersect_shape(q, 1)
		var ray := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -1.5, 0), 1)
		var fl := space.intersect_ray(ray)
		if i == n:
			print("player spot: hit=", hit.map(func(h): return str(h.collider.name)), " floor=", fl.get("position", "none"), " on_floor=", m.player.is_on_floor())
			continue
		if not hit.is_empty():
			bad_wall += 1
			names[str(hit[0].collider.name)] = true
		if fl.is_empty():
			bad_floor += 1
	print("hit names ", names.keys())
	print("RESULT mode=%s map=%s player=%s spawns=%d in_wall=%d no_floor=%d" % [m.mode, m.map_id, m.player.global_position, n, bad_wall, bad_floor])
	quit(1 if bad_wall + bad_floor > 0 else 0)
	return false
