extends SceneTree
## Every vault on every map, done for real (first person), checked frame by frame:
##  - flying: the body is lifted far higher than the obstacle needs (it went into the air);
##  - clipping: the body (as drawn, lifted) passes through the obstacle instead of over it;
##  - landing: it ends on the floor it aimed for - not hanging in the air, not falling afterwards, not inside geometry.
##   godot --headless --fixed-fps 120 --path . -s res://tests/vault_audit_test.gd [-- map ...]
const Main = preload("res://scripts/main.gd")
const Layers = preload("res://scripts/core/layers.gd")
const MAX_VAULTS := 60
var failures := 0
var p


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	load("res://scripts/core/profile.gd").current = "vault_audit"
	var maps: Array = OS.get_cmdline_user_args()
	if maps.is_empty():
		maps = Main.MAPS.keys()
	for id in maps:
		await audit(String(id))
	print("VAULT AUDIT: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)


## Floor points of the play area: navigation polygon centres dropped onto the floor.
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


## What the drawn body overlaps ("" for nothing): a slim capsule from the lifted feet (legs tucked) to the chest.
func body_clips(space: PhysicsDirectSpaceState3D, pos: Vector3, lift: float) -> String:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.2
	shape.height = 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = Layers.WORLD
	q.exclude = [p.get_rid()]
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * (lift + 0.35 + 0.45))
	var hits := space.intersect_shape(q, 1)
	if hits.is_empty():
		return ""
	var o = hits[0].collider
	return "%s" % (o.name if o is Node else "?")


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
	var pts := floor_points(main)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	# candidates: from floor points, every 45 degrees, at a few run-up distances
	var found: Array = []
	var seen := {}
	for at in pts:
		for k in 8:
			var a := k * TAU / 8.0
			var dir := Vector3(-sin(a), 0, -cos(a))
			p.global_position = at
			var v = p._find_vault(dir)
			if v == null:
				continue
			var key := Vector3i(((v.to as Vector3) * 2.0).round())
			if seen.has(key):
				continue
			seen[key] = true
			found.append([at, dir])
	found.shuffle()
	var done := 0
	var flying: Array = []
	var clipping: Array = []
	var landing: Array = []
	for f in found.slice(0, MAX_VAULTS):
		var at: Vector3 = f[0]
		var dir: Vector3 = f[1]
		p.velocity = Vector3.ZERO
		p.global_position = at + Vector3.UP * 0.05
		p.aim_yaw = atan2(-dir.x, -dir.z)
		for i in 6:
			await physics_frame
		p.global_position = Vector3(at.x, p.global_position.y, at.z)
		var v = p._find_vault(dir)
		if v == null:
			continue
		done += 1
		var base_y: float = p.global_position.y
		var top_rel: float = float(v.top) - base_y
		p._start_vault(v, dir)
		var max_lift := 0.0
		var clip_frames := 0
		var clip_what := ""
		var frames := 0
		while p.vaulting and frames < 240:
			await physics_frame
			frames += 1
			var lift: float = p.rig.pivot.position.y
			# the drawn body's height over the take-off floor (the body itself may be going down to a lower landing)
			max_lift = maxf(max_lift, lift + p.global_position.y - base_y)
			var what := body_clips(space, p.global_position, lift)
			if what != "":
				clip_frames += 1
				if clip_what == "":
					clip_what = "%s at %s lift %.2f" % [what, p.global_position.snapped(Vector3.ONE * 0.01), lift]
		var land: Vector3 = v.to
		var where := "%s → %s (obstacle %.2f m)" % [at.snapped(Vector3.ONE * 0.01), land.snapped(Vector3.ONE * 0.01), top_rel]
		if max_lift > top_rel + 0.4:
			flying.append("%s lifted %.2f m" % [where, max_lift])
		if clip_frames > 2:
			clipping.append("%s through %s for %d frames" % [where, clip_what, clip_frames])
		# the landing: on the floor within a few frames, at the height it aimed for
		var on_floor_at := -1
		for i in 60:
			await physics_frame
			if p.is_on_floor():
				on_floor_at = i
				break
		var dy: float = p.global_position.y - land.y
		# up to 8 frames (67 ms at 120 Hz) to touch the floor: with Jolt a ledge landing can take one tick longer
		if on_floor_at < 0 or on_floor_at > 8 or dy < -0.25 or dy > 0.25:
			landing.append("%s ended %.2f m off its landing, on the floor after %d frames" % [where, dy, on_floor_at])
		else:
			# settled: wedged if it cannot stand up or is pinned on three sides
			for i in 12:
				await physics_frame
			var side := Vector3(-dir.z, 0.0, dir.x)
			var pinned := 0
			var up_xf: Transform3D = p.global_transform.translated(Vector3.UP * 0.04)
			for d in [dir, -dir, side, -side]:
				if p.test_move(up_xf, d * 0.05):
					pinned += 1
			if p.test_move(up_xf, Vector3.UP * 0.3) or pinned >= 3:
				landing.append("%s ended wedged in geometry (%d sides pinned) at %s" % [where, pinned, p.global_position.snapped(Vector3.ONE * 0.01)])
	print("%-10s %d vaults found, %d done · flying %d · through the obstacle %d · bad landings %d" % [id, found.size(), done, flying.size(), clipping.size(), landing.size()])
	for s in flying.slice(0, 4): print("    flying: ", s)
	for s in clipping.slice(0, 4): print("    clipping: ", s)
	for s in landing.slice(0, 4): print("    landing: ", s)
	failures += flying.size() + clipping.size() + landing.size()
