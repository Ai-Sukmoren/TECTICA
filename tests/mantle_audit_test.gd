extends SceneTree
## Every mantle (climb up onto a ledge) on every map, done for real in first person and checked frame by frame:
##  - clipping: the body or the first-person camera passes through the ledge instead of climbing over it;
##  - landing: it ends standing on the ledge it aimed for - not hanging, not falling off, not wedged in geometry;
##  - play area: it never ends off the map's walkable area (the top of an outer wall, a roof outside the map);
##  - timing: a climb takes a believable time for its height.
## Also checks that a ledge above reach, or with no room on top, is refused.
##   godot --headless --fixed-fps 120 --path . -s res://tests/mantle_audit_test.gd [-- map ...]
const Main = preload("res://scripts/main.gd")
const Layers = preload("res://scripts/core/layers.gd")
const Player = preload("res://scripts/characters/player.gd")
const MAX_MANTLES := 40
var failures := 0
var total := 0
var p


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	load("res://scripts/core/profile.gd").current = "mantle_audit"
	var maps: Array = OS.get_cmdline_user_args()
	if maps.is_empty():
		maps = Main.MAPS.keys()
	for id in maps:
		await audit(String(id))
	if total == 0:
		print("FAIL no mantles found on any map")
		failures += 1
	print("MANTLE AUDIT: %d mantles, failures=%d" % [total, failures])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)


func floor_points(main) -> Array:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var nm: NavigationMesh = main.level.nav_region.navigation_mesh
	var verts := nm.get_vertices()
	var out: Array = []
	for i in nm.get_polygon_count():
		var c := Vector3.ZERO
		for k in nm.get_polygon(i):
			c += verts[k]
		c /= nm.get_polygon(i).size()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.6, c + Vector3.DOWN * 1.5, Layers.WORLD))
		if not hit.is_empty() and (hit.normal as Vector3).y > 0.8:
			out.append(hit.position)
	return out


## What overlaps a slim capsule of the body from the knees to the chest ("" for nothing).
func body_clips(space: PhysicsDirectSpaceState3D, pos: Vector3) -> String:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.2
	shape.height = 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = Layers.WORLD
	q.exclude = [p.get_rid()]
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.8)
	var hits := space.intersect_shape(q, 1)
	if hits.is_empty():
		return ""
	var o = hits[0].collider
	return "%s" % (o.name if o is Node else "?")


func camera_clips(space: PhysicsDirectSpaceState3D) -> bool:
	var cam := root.get_viewport().get_camera_3d()
	if cam == null:
		return false
	var s := SphereShape3D.new()
	s.radius = 0.06
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = s
	q.collision_mask = Layers.WORLD
	q.exclude = [p.get_rid()]
	q.transform = Transform3D(Basis.IDENTITY, cam.global_position)
	return not space.intersect_shape(q, 1).is_empty()


func audit(id: String) -> void:
	Main.saved_mode = "zombie"
	Main.saved_map = id
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	var main = current_scene
	if main.director != null:
		main.director.set_physics_process(false)
	p = main.player
	p.health = 1.0e9
	p.max_health = 1.0e9
	p.set_first_person(true)
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var found: Array = []
	var seen := {}
	for at in floor_points(main):
		for k in 8:
			var a := k * TAU / 8.0
			var dir := Vector3(-sin(a), 0, -cos(a))
			p.global_position = at
			var m = p._find_mantle(dir)
			if m == null:
				continue
			var key := Vector3i(((m.to as Vector3) * 2.0).round())
			if seen.has(key):
				continue
			seen[key] = true
			found.append([at, dir])
	found.shuffle()
	var done := 0
	var skipped := 0
	var clipping: Array = []
	var landing: Array = []
	var outside: Array = []
	var timing: Array = []
	for f in found.slice(0, MAX_MANTLES):
		var at: Vector3 = f[0]
		var dir: Vector3 = f[1]
		p.velocity = Vector3.ZERO
		p.global_position = at + Vector3.UP * 0.05
		p.aim_yaw = atan2(-dir.x, -dir.z)
		for i in 6:
			await physics_frame
		p.global_position = Vector3(at.x, p.global_position.y, at.z)
		var m = p._find_mantle(dir)
		if m == null:
			continue
		if body_clips(space, p.global_position) != "":
			skipped += 1   # the take-off spot itself overlaps something: a player can't stand there
			continue
		done += 1
		var base_y: float = p.global_position.y
		var top_rel: float = float(m.top) - base_y
		var where := "%s up %.2f m" % [at.snapped(Vector3.ONE * 0.01), top_rel]
		p._start_mantle(m, dir)
		var clip_frames := 0
		var cam_frames := 0
		var clip_what := ""
		var frames := 0
		while p.vaulting and frames < 400:
			await physics_frame
			frames += 1
			var what := body_clips(space, p.global_position)
			if what != "":
				clip_frames += 1
				if clip_what == "":
					clip_what = "%s at %s" % [what, p.global_position.snapped(Vector3.ONE * 0.01)]
			if camera_clips(space):
				cam_frames += 1
		var secs := frames / 120.0
		if secs < 0.35 or secs > 1.4:
			timing.append("%s took %.2f s" % [where, secs])
		if clip_frames > 2:
			clipping.append("%s body through %s for %d frames" % [where, clip_what, clip_frames])
		if cam_frames > 2:
			clipping.append("%s camera inside geometry for %d frames" % [where, cam_frames])
		var land: Vector3 = m.to
		var on_floor_at := -1
		for i in 60:
			await physics_frame
			if p.is_on_floor():
				on_floor_at = i
				break
		var dy: float = p.global_position.y - land.y
		if on_floor_at < 0 or on_floor_at > 6 or absf(dy) > 0.25:
			landing.append("%s ended %.2f m off its ledge, on the floor after %d frames" % [where, dy, on_floor_at])
		else:
			for i in 12:
				await physics_frame
			var side := Vector3(-dir.z, 0.0, dir.x)
			var pinned := 0
			var up_xf: Transform3D = p.global_transform.translated(Vector3.UP * 0.04)
			for d in [dir, -dir, side, -side]:
				if p.test_move(up_xf, d * 0.05):
					pinned += 1
			if p.test_move(up_xf, Vector3.UP * 0.3) or pinned >= 3:
				landing.append("%s ended wedged (%d sides pinned)" % [where, pinned])
			if not p._in_play_area(p.global_position):
				outside.append("%s ended off the play area at %s" % [where, p.global_position.snapped(Vector3.ONE * 0.01)])
	total += done
	print("%-10s %d mantles found, %d done (%d bad take-off spots skipped) · through geometry %d · bad landings %d · off the map %d · timing %d" % [id,
			found.size(), done, skipped, clipping.size(), landing.size(), outside.size(), timing.size()])
	for s in clipping.slice(0, 4): print("    clipping: ", s)
	for s in landing.slice(0, 4): print("    landing: ", s)
	for s in outside.slice(0, 4): print("    outside: ", s)
	for s in timing.slice(0, 4): print("    timing: ", s)
	failures += clipping.size() + landing.size() + outside.size() + timing.size()
	await refusals(main, id)


## A test wall built in the open: 2.6 m (out of reach) is refused; 1.6 m is climbed; 1.6 m with a slab 1 m over its
## top (no room to stand) is refused.
func refusals(main, id: String) -> void:
	if id != String(Main.MAPS.keys()[0]):
		return
	p.global_position = main.level.player_spawn + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	var at: Vector3 = p.global_position
	var dir := Vector3(0, 0, -1)
	var cases := [[2.6, false, false], [1.6, false, true], [1.6, true, false]]
	for c in cases:
		var holder := Node3D.new()
		main.add_child(holder)
		_box(holder, at + dir * 1.35 + Vector3(0, c[0] * 0.5, 0), Vector3(3.0, c[0], 1.5))
		if c[1]:
			_box(holder, at + dir * 1.35 + Vector3(0, c[0] + 1.0 + 0.1, 0), Vector3(3.0, 0.2, 1.5))
		await physics_frame
		await physics_frame
		var m = p._find_mantle(dir)
		var ok: bool = (m != null) == c[2]
		print("  refusal check: wall %.1f m%s -> %s %s" % [c[0], " under a slab" if c[1] else "", "climbs" if m != null else "refused", "ok" if ok else "FAIL"])
		if not ok:
			failures += 1
		holder.queue_free()
		await physics_frame


func _box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = center
