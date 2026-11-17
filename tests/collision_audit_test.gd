extends SceneTree
## Collision and movement audit of every map, with the real operator and the real input:
##  1. floor: the operator stands on every walkable spot of the play area and must not sink through the floor;
##  2. routes: walks and sprints along navigation routes between random walkable spots; must not fall through,
##     leave the map or get stuck (a stair that needs a jump counts as stuck);
##  3. exploits: sprint + jump (Shift + Space), with a crouch, and plain jumps straight at the nearest walls and
##     obstacles must never leave the map, end up inside geometry or wedged off the ground.
##   godot --headless --fixed-fps 120 --path . -s res://tests/collision_audit_test.gd [-- map ...]
const Main = preload("res://scripts/main.gd")
const ModelLevel = preload("res://scripts/world/model_level.gd")
const Layers = preload("res://scripts/core/layers.gd")
const ROUTES := 24
const EXPLOITS := 40
var failures := 0
var main
var p
var lv


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	load("res://scripts/core/profile.gd").current = "collision_audit"
	var maps: Array = OS.get_cmdline_user_args()
	if maps.is_empty():
		maps = Main.MAPS.keys()
	for id in maps:
		await audit(String(id))
	print("COLLISION AUDIT: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await physics_frame
		p.health = p.max_health


func release_all() -> void:
	for a in ["move_forward", "sprint", "vault", "crouch", "move_left", "move_right", "move_back"]:
		Input.action_release(a)


## The play area: navigation polygon centres on the island the operator spawns on, with their heights.
func play_points() -> Array:
	var nm: NavigationMesh = lv.nav_region.navigation_mesh
	var verts := nm.get_vertices()
	var by_vert := {}
	var cen: Array = []
	for i in nm.get_polygon_count():
		var c := Vector3.ZERO
		for k in nm.get_polygon(i):
			c += verts[k]
			var key := Vector3i((verts[k] * 20.0).round())
			if not by_vert.has(key): by_vert[key] = []
			by_vert[key].append(i)
		cen.append(c / nm.get_polygon(i).size())
	var start := 0
	for i in cen.size():
		if (cen[i] as Vector3).distance_to(lv.player_spawn) < (cen[start] as Vector3).distance_to(lv.player_spawn):
			start = i
	var seen := {start: true}
	var q := [start]
	var out: Array = []
	while not q.is_empty():
		var i: int = q.pop_back()
		out.append(cen[i])
		for k in nm.get_polygon(i):
			for j in by_vert[Vector3i((verts[k] * 20.0).round())]:
				if not seen.has(j):
					seen[j] = true
					q.append(j)
	return out


func put(at: Vector3, yaw: float = 0.0) -> void:
	release_all()
	p.velocity = Vector3.ZERO
	p.global_position = at + Vector3.UP * 0.15
	p.aim_yaw = yaw
	p.rig.aim_yaw = yaw
	p.rig.lower_yaw = yaw
	if p.crouching:
		p.set_crouch(false)
	p.reset_physics_interpolation()


func bounds_ok(pos: Vector3) -> bool:
	if lv.get("_lo") == null:
		return pos.y > -30.0
	var lo: Vector3 = lv._lo
	var hi: Vector3 = lv._hi
	return pos.x > lo.x - 0.2 and pos.x < hi.x + 0.2 and pos.z > lo.z - 0.2 and pos.z < hi.z + 0.2 and pos.y > lo.y - 0.5


## Inside geometry: the model's meshes are hollow shells, so from inside one, rays in most directions meet the
## back of a face (its normal points along the ray). From open floor they meet front faces or nothing.
func inside_geometry(pos: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var c := pos + Vector3.UP * 0.9
	var backs := 0
	for d in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var q := PhysicsRayQueryParameters3D.create(c, c + d * 40.0, Layers.WORLD, [p.get_rid()])
		q.hit_back_faces = true
		var h := space.intersect_ray(q)
		if not h.is_empty() and (h.normal as Vector3).dot(d) > 0.2:
			backs += 1
	return backs >= 4


## Off the ground (perched on a railing, a wall top): only a failure if walking and jumping in every direction
## cannot get the body back onto the floor.
func trapped() -> bool:
	for k in 4:
		p.aim_yaw = k * PI * 0.5
		Input.action_press("move_forward")
		for i in 60:
			if i % 20 == 0:
				Input.action_press("vault")
			elif i % 20 == 2:
				Input.action_release("vault")
			await frames(1)
		release_all()
		for i in 120:   # a jump lasts about 80 frames: wait for the landing
			await frames(1)
			if p.is_on_floor():
				return false
	return true


func audit(id: String) -> void:
	Main.saved_mode = "zombie"
	Main.saved_map = id
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	main = current_scene
	lv = main.level
	p = main.player
	if main.director != null:
		main.director.set_physics_process(false)
	p.set_first_person(true)
	var pts := play_points()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)

	# 1 floor
	var sank: Array = []
	for pt in pts:
		put(pt)
		await frames(24)
		if p.global_position.y < (pt as Vector3).y - 0.7 or not bounds_ok(p.global_position):
			sank.append((pt as Vector3).snapped(Vector3.ONE * 0.1))
	# 2 routes (walk, then sprint)
	var falls: Array = []
	var stuck: Array = []
	var oob: Array = []
	var map_rid: RID = lv.get_world_3d().navigation_map
	for sprint in [false, true]:
		for r in ROUTES:
			var a: Vector3 = pts[rng.randi() % pts.size()]
			var b: Vector3 = pts[rng.randi() % pts.size()]
			var path := NavigationServer3D.map_get_path(map_rid, a, b, true)
			if path.size() < 2 or a.distance_to(b) < 4.0:
				continue
			put(path[0])
			await frames(4)
			var k := 1
			var last_prog := 0.0
			var best := INF
			var t := 0.0
			var bad := ""
			Input.action_press("move_forward")
			if sprint:
				Input.action_press("sprint")
			while k < path.size() and t < 40.0:
				var target: Vector3 = path[k]
				var d := Vector3(target.x - p.global_position.x, 0, target.z - p.global_position.z)
				if d.length() < 0.45:
					k += 1
					best = INF
					continue
				p.aim_yaw = atan2(-d.x, -d.z)
				await frames(1)
				t += 1.0 / 120.0
				var seg_y := minf(path[k - 1].y, target.y)
				if p.global_position.y < seg_y - 1.6:
					bad = "fall"
					break
				if not bounds_ok(p.global_position):
					bad = "oob"
					break
				if d.length() < best - 0.05:
					best = d.length()
					last_prog = t
				elif t - last_prog > 2.5:
					bad = "stuck"
					break
			release_all()
			var where := "%s → %s (at %s)" % [a.snapped(Vector3.ONE * 0.1), b.snapped(Vector3.ONE * 0.1), p.global_position.snapped(Vector3.ONE * 0.1)]
			match bad:
				"fall": falls.append(("sprint " if sprint else "walk ") + where)
				"oob": oob.append(("sprint " if sprint else "walk ") + where)
				"stuck": stuck.append(("sprint " if sprint else "walk ") + where)
	# 3 exploits: sprint-jump and jump straight at the nearest obstacle in a random direction
	var escapes: Array = []
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var tries := 0
	while tries < EXPLOITS:
		var a: Vector3 = pts[rng.randi() % pts.size()]
		var ang := rng.randf() * TAU
		var dir := Vector3(-sin(ang), 0, -cos(ang))
		var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 0.5, a + Vector3.UP * 0.5 + dir * 5.0, Layers.WORLD)
		if space.intersect_ray(q).is_empty():
			continue
		tries += 1
		put(a, ang)
		await frames(3)
		var mode := tries % 3
		Input.action_press("move_forward")
		if mode != 2:
			Input.action_press("sprint")
		for i in 180:
			p.aim_yaw = ang
			if i % 18 == 0:
				Input.action_press("vault")
			elif i % 18 == 3:
				Input.action_release("vault")
			if mode == 1 and i == 40:
				Input.action_press("crouch")
			if mode == 1 and i == 44:
				Input.action_release("crouch")
			await frames(1)
		release_all()
		await frames(60)
		var pos: Vector3 = p.global_position
		var kind: String = ["sprint+jump", "sprint+jump+crouch", "jump"][mode]
		if not bounds_ok(pos):
			escapes.append("%s left the map at %s" % [kind, pos.snapped(Vector3.ONE * 0.1)])
		elif inside_geometry(pos):
			escapes.append("%s ended inside geometry at %s" % [kind, pos.snapped(Vector3.ONE * 0.1)])
		elif not p.is_on_floor() and await trapped():
			escapes.append("%s ended trapped off the ground at %s [vault %s slide %s crouch %s vel %s contacts %d]" % [kind, pos.snapped(Vector3.ONE * 0.1),
					p.vaulting, p.sliding, p.crouching, p.velocity.snapped(Vector3.ONE * 0.01), p.get_slide_collision_count()])
			for k in p.get_slide_collision_count():
				var c: KinematicCollision3D = p.get_slide_collision(k)
				var o = c.get_collider()
				print("        contact %s n%s @%s" % [o.shape_owner_get_owner(o.shape_find_owner(c.get_collider_shape_index())).name if o is CollisionObject3D else "?", c.get_normal().snapped(Vector3.ONE * 0.01), c.get_position().snapped(Vector3.ONE * 0.01)])
	var n_routes := ROUTES * 2
	print("%-10s floor %d spots: %d sank · routes: %d falls, %d stuck, %d out of bounds (of ~%d) · exploits: %d of %d escaped" % [id, pts.size(), sank.size(), falls.size(), stuck.size(), oob.size(), n_routes, escapes.size(), EXPLOITS])
	for s in sank.slice(0, 6): print("    sank at ", s)
	for s in falls.slice(0, 6): print("    fell: ", s)
	for s in stuck.slice(0, 6): print("    stuck: ", s)
	for s in oob.slice(0, 6): print("    out: ", s)
	for s in escapes.slice(0, 6): print("    exploit: ", s)
	failures += sank.size() + falls.size() + oob.size() + escapes.size() + (1 if stuck.size() > n_routes / 8 else 0)

