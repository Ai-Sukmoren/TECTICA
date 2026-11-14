extends Node3D
## A firearm instance built from a base weapon + attachments: final stats,
## ammo, rate of fire, hitscan ballistics (incl. shotgun pellets), laser
## sight, bolt / pump cycling and the sight line used for aiming down sights.

const Data = preload("res://scripts/weapons/weapon_data.gd")
const Model = preload("res://scripts/weapons/weapon_model.gd")
const FX = preload("res://scripts/fx/fx.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Layers = preload("res://scripts/core/layers.gd")
const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const Skins = preload("res://scripts/skins/skins.gd")
const Sticker = preload("res://scripts/skins/sticker.gd")
const Charm = preload("res://scripts/skins/charm.gd")

var id := ""
var stats: Dictionary = {}
## Taped dual mag: true when the next reload is the quick flip to the other mag.
var dual_flip := true
var attachments: Dictionary = {}
var ammo := 0
var reserve := 0
var cooldown := 0.0
var bloom := 0.0
## Camera-space position of the weapon origin when aiming down sights.
var ads_offset := Vector3(0, -0.15, -0.3)
var cycle_pending := 0.0
## equipped finish ("" = factory)
var skin := ""
var _model_root: Node3D
var charm := ""
var _charm: Node3D

var grip: Node3D
var support: Node3D
var muzzle: Node3D
var mag_node: Node3D
var mag_well: Node3D
var charge: Node3D
var eject: Node3D
var pump: Node3D
var bolt: Node3D
## Rolling-block action: breech block and hammer pivots (null on other guns).
var roll: Node3D
var hammer: Node3D
var laser: Node3D
var _beam: MeshInstance3D
var _beam_dot: MeshInstance3D


func setup(weapon_id: String, att: Dictionary = {}, reserve_override: int = -1) -> void:
	id = weapon_id
	name = weapon_id
	stats = Data.compute(weapon_id, att)
	attachments = stats.attachments
	ammo = int(stats.mag)
	reserve = int(stats.reserve) if reserve_override < 0 else reserve_override
	var parts: Dictionary = preload("res://scripts/weapons/knife_model.gd").build(String(stats.model)) if is_melee() \
			else Model.build(String(stats.model), attachments)
	_spin = parts.get("spin")
	_handles = [parts.get("handle_safe"), parts.get("handle_bite")]
	add_child(parts.root)
	_model_root = parts.root
	grip = parts.grip
	support = parts.support
	muzzle = parts.muzzle
	mag_node = parts.mag
	mag_well = parts.mag_well
	charge = parts.charge
	eject = parts.eject
	pump = parts.pump
	bolt = parts.bolt
	roll = parts.get("roll")
	hammer = parts.get("hammer")
	laser = parts.laser
	var sight: Dictionary = parts.sight
	set_meta("iron_info", sight)   # sight line / rear / front positions, for fit checks
	var relief: float = sight.relief
	if is_pistol():
		relief = maxf(relief, 0.36)
	ads_offset = Vector3(0, -float(sight.y), -relief - float(sight.rear_z))
	if laser != null:
		_build_laser()


## Applies a weapon skin finish (see skins.gd) to the built model.
func apply_skin(finish: String) -> void:
	if finish == "" or finish == skin or not Skins.FINISHES.has(finish):
		return
	skin = finish
	Skins.apply(_model_root, finish, [Model._black, Model._worn])


## Places the current finish's sticker (if it has one) per `cfg` (see sticker.gd).
func apply_sticker(cfg: Dictionary) -> void:
	if is_melee():
		return   # no room for a sticker on a blade
	var id := String(Skins.FINISHES[skin].get("sticker", "")) if Skins.FINISHES.has(skin) else ""
	if id == "":
		Sticker.remove(_model_root)
		return
	Sticker.attach(_model_root, id, cfg if cfg is Dictionary else {})


func is_pistol() -> bool:
	return stats.kind == "pistol"


func is_melee() -> bool:
	return stats.kind == "melee"


# ---------------------------------------------------------------- knives

var _spin: Node3D
var _handles: Array = []
var _inspecting := false


## Knife flourish for the inspect animation, t in 0..1 (or < 0 to reset):
## combat knife flips over in the palm, the karambit spins round its finger
## ring, the butterfly knife's handles flip closed and open twice.
func inspect_motion(t: float) -> void:
	if not is_melee() or _spin == null:
		return
	if t < 0.0:
		if _inspecting:
			_inspecting = false
			_spin.transform = Transform3D.IDENTITY
			for h in _handles:
				if h != null:
					h.rotation = Vector3.ZERO
		return
	_inspecting = true
	match String(stats.get("inspect", "combat")):
		"karambit":
			var u := smoothstep(0.28, 0.72, t)
			var ring := Vector3(0, 0.002, 0.095)
			_spin.transform = Transform3D(Basis.IDENTITY, ring) * Transform3D(Basis(Vector3.RIGHT, -u * TAU * 2.0), Vector3.ZERO) \
					* Transform3D(Basis.IDENTITY, -ring)
		"butterfly":
			# closed = handles swung 180 deg round their pins over the blade
			var flips := clampf((t - 0.22) / 0.52, 0.0, 1.0) * 4.0
			var k: float = flips - floorf(flips)
			var closed := (1.0 - absf(1.0 - 2.0 * k)) if flips > 0.0 and flips < 4.0 else 0.0
			var e := closed * closed * (3.0 - 2.0 * closed)
			if _handles[0] != null:
				_handles[0].rotation.x = e * PI
			if _handles[1] != null:
				_handles[1].rotation.x = -e * PI
			_spin.rotation.z = smoothstep(0.22, 0.74, t) * TAU
		_:
			_spin.rotation.z = smoothstep(0.3, 0.55, t) * PI + smoothstep(0.62, 0.84, t) * PI


## A knife slash: hits the closest hostile in a cone in front, through no
## walls. A hit from behind does `backstab` times the damage.
func _slash(shooter: CharacterBody3D, origin: Vector3, target: Vector3) -> Dictionary:
	cooldown = 60.0 / float(stats.rpm)
	var fwd := target - origin
	fwd.y = 0.0
	if fwd.length() < 0.05:
		fwd = -shooter.global_transform.basis.z
	fwd = fwd.normalized()
	var reach := float(stats.range)
	var result := {"hit": null, "headshot": false, "killed": false, "position": origin + fwd * reach, "ends": [],
			"damage": 0.0, "hit_at": Vector3.ZERO, "melee": true, "backstab": false}
	var space := get_world_3d().direct_space_state
	var pool: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player")
	var best = null
	var best_d := INF
	for v in pool:
		if v == shooter or not is_instance_valid(v) or v.get("is_dead") != false or not v.has_method("apply_damage"):
			continue
		if v.get("team") != null and v.get("team") == shooter.get("team"):
			continue
		var to: Vector3 = v.global_position - shooter.global_position
		var dy := to.y
		to.y = 0.0
		var d := to.length()
		if d > reach or absf(dy) > 1.7:
			continue
		if d > 0.35 and fwd.dot(to / d) < 0.55:     # about a 113 deg arc in front
			continue
		var chest: Vector3 = v.global_position + Vector3.UP * (float(v.chest_height()) if v.has_method("chest_height") else 1.2)
		var q := PhysicsRayQueryParameters3D.create(origin, chest, Layers.WORLD, [shooter.get_rid()])
		if not space.intersect_ray(q).is_empty():
			continue
		if d < best_d:
			best_d = d
			best = v
	if best != null:
		var at: Vector3 = best.global_position + Vector3.UP * (float(best.chest_height()) if best.has_method("chest_height") else 1.2)
		var dmg := float(stats.damage)
		var their_fwd := Vector3(-sin(float(best.get("aim_yaw"))), 0, -cos(float(best.get("aim_yaw")))) if best.get("aim_yaw") != null else -fwd
		if their_fwd.dot(fwd) > 0.55:
			dmg *= float(stats.get("backstab", 1.0))
			result.backstab = true
		best.apply_damage(dmg, at, fwd, shooter)
		result.hit = best
		result.hit_at = at
		result.damage = dmg
		result.position = at
		result.killed = best.get("is_dead") == true
		Sfx.play(self, "knife_hit", at, -2.0, 0.12)
	else:
		# blade on a wall or prop: sparks and a scrape
		var q2 := PhysicsRayQueryParameters3D.create(origin, origin + fwd * reach, Layers.WORLD, [shooter.get_rid()])
		var wall := space.intersect_ray(q2)
		if not wall.is_empty():
			FX.impact(self, wall.position, wall.normal, FX.surface_of(wall.collider, wall.position, wall.normal))
			Sfx.play(self, "helmet_ping", wall.position, -10.0, 0.2)
	Sfx.play(self, String(stats.sound), origin, float(stats.volume), 0.12)
	return result


func apply_charm(charm_id: String) -> void:
	if is_melee():
		return
	var next := Charm.sanitize(charm_id)
	if next == charm:
		return
	if is_instance_valid(_charm):
		remove_child(_charm)
		_charm.queue_free()
	_charm = null
	charm = next
	if charm != "":
		_charm = Charm.new()
		_charm.setup(charm, is_pistol())
		# Seat the lanyard stud on the actual receiver / grip surface, including
		# imported guns, rather than assuming every weapon has the same width.
		var mount: Vector3 = _charm.position
		var side := INF
		for bounds: AABB in Sticker._parts(_model_root):
			if mount.y >= bounds.position.y and mount.y <= bounds.end.y and mount.z >= bounds.position.z and mount.z <= bounds.end.z:
				side = minf(side, bounds.position.x)
		if is_finite(side):
			mount.x = side - 0.003
			_charm.position = mount
		add_child(_charm)


func display_name() -> String:
	return String(stats.name)


func _process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	bloom = move_toward(bloom, 0.0, float(stats.bloom_recover) * delta)
	if laser != null and is_inside_tree():
		_update_laser()


func ready_to_fire() -> bool:
	return cooldown <= 0.0 and ammo > 0


func can_reload() -> bool:
	return reserve > 0 and ammo < int(stats.mag) + 1


func finish_reload(tactical: bool) -> void:
	var capacity := int(stats.mag) + (1 if tactical and stats.cycle == "" else 0)
	var take := mini(capacity - ammo, reserve)
	if take > 0:
		ammo += take
		reserve -= take


## Hitscan shot (or pellet volley) from `origin` toward `target`. Returns hit info.
func fire(shooter: CharacterBody3D, origin: Vector3, target: Vector3, spread_deg: float) -> Dictionary:
	if is_melee():
		return _slash(shooter, origin, target)
	if is_instance_valid(_charm):
		_charm.kick()
	cooldown = 60.0 / float(stats.rpm)
	ammo -= 1
	var total_spread := spread_deg + bloom
	bloom = minf(bloom + float(stats.bloom_add), float(stats.bloom_max))

	var base_dir := target - origin
	if base_dir.length() < 0.05:
		base_dir = -global_transform.basis.z
	base_dir = base_dir.normalized()
	var result := {"hit": null, "headshot": false, "killed": false, "position": origin + base_dir * float(stats.range), "ends": [],
			"damage": 0.0, "hit_at": Vector3.ZERO}
	var space := get_world_3d().direct_space_state
	var pellets := int(stats.get("pellets", 1))
	var from := muzzle.global_position
	for i in pellets:
		var dir := base_dir
		var sp := total_spread * (1.0 if pellets == 1 else 1.0)
		var yaw := deg_to_rad((randf() - randf()) * sp)
		var pitch := deg_to_rad((randf() - randf()) * sp * (0.3 if pellets == 1 else 0.6))
		dir = dir.rotated(Vector3.UP, yaw)
		var right := dir.cross(Vector3.UP)
		if right.length() > 0.01:
			dir = dir.rotated(right.normalized(), pitch)
		var end := origin + dir * float(stats.range)
		var skip: Array = [shooter.get_rid()]
		var hit := _trace(space, origin, end, skip)
		# humanoid infected: their wide bullet zone / movement capsule is only
		# the broad check; the shot must touch an actual body part (head,
		# torso, arm, leg), otherwise it flies on past to whatever is behind
		for pass_i in 6:
			if hit.is_empty():
				break
			var who: Object = hit.collider
			if who is Area3D:
				who = (who as Node).get_parent()
			if who == null or not who.has_method("hit_part"):
				break
			var part: Dictionary = who.hit_part(origin, dir, float(stats.range))
			if not part.is_empty():
				hit.collider = who
				if (part.pos as Vector3) != Vector3.INF:
					hit.position = part.pos
					hit.normal = -dir
				break
			skip.append((who as CollisionObject3D).get_rid())
			if (hit.collider as Object) is CollisionObject3D and hit.collider != who:
				skip.append((hit.collider as CollisionObject3D).get_rid())
			var zone = (who as Node).get_node_or_null("HitZone")
			if zone != null:
				skip.append((zone as CollisionObject3D).get_rid())
			hit = _trace(space, origin, end, skip)
		# [end, normal, kind]: 0 = nothing, 1 = world / prop, 2 = flesh (replayed on other peers)
		var shot_end := [end, Vector3.UP, 0]
		if not hit.is_empty():
			end = hit.position
			var col: Object = hit.collider
			if col != null and col.has_method("apply_damage"):
				var dist := origin.distance_to(end)
				var falloff := clampf(1.0 - maxf(dist - float(stats.falloff_start), 0.0) / 60.0, 0.5, 1.0)
				var hs: bool = col.apply_damage(float(stats.damage) * falloff, end, dir, shooter)
				if not col.is_in_group("destructibles") and col.get("destroyed") == null:
					result.damage += float(stats.damage) * falloff * (2.5 if hs else 1.0)
					if result.hit == null:
						result.hit_at = end
					result.headshot = result.headshot or hs
					result.hit = col
					result.killed = result.killed or col.get("is_dead") == true
			elif i % 2 == 0 or pellets == 1:
				FX.impact(self, end, hit.normal, FX.surface_of(col, end, hit.normal))
			var flesh: bool = col != null and col.has_method("apply_damage") and col.get("is_dead") != null
			shot_end = [end, hit.normal, 2 if flesh else int(FX.SURFACE_CODE.get(FX.surface_of(col, end, hit.normal), 1))]
		result.ends.append(shot_end)
		if i == 0:
			result.position = end
		if pellets == 1 or i % 2 == 0:
			FX.tracer(self, from, end, bool(stats.suppressed))
	FX.muzzle_flash(muzzle, float(stats.flash) * (0.45 if bool(stats.suppressed) else 1.0))
	if stats.cycle == "":
		FX.casing(self, eject.global_position, global_transform.basis.x, is_pistol())
	else:
		cycle_pending = 0.12
	Sfx.play(self, String(stats.sound), from, float(stats.volume))
	return result


## Bullet ray: world, bodies and the bullet-only zones around infected.
func _trace(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, skip: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SHOTS | Layers.HITZONE, skip)
	q.collide_with_areas = true
	return space.intersect_ray(q)


## Replays another peer's shot from its end points: tracers, impacts, blood,
## muzzle flash, casing and sound. No ammo, no damage.
func fire_fx(ends: Array) -> void:
	if is_melee():
		Sfx.play(self, String(stats.sound), global_position, float(stats.volume), 0.12)
		return
	if muzzle == null or not is_inside_tree():
		return
	var from := muzzle.global_position
	for i in ends.size():
		var e: Array = ends[i]
		var end: Vector3 = e[0]
		var even := ends.size() == 1 or i % 2 == 0
		if even:
			FX.tracer(self, from, end, bool(stats.suppressed))
		match int(e[2]):
			1, 3, 4, 5:
				if even:
					FX.impact(self, end, e[1], FX.SURFACE_NAME[int(e[2])])
			2:
				FX.blood(self, end, (end - from).normalized())
	FX.muzzle_flash(muzzle, float(stats.flash) * (0.45 if bool(stats.suppressed) else 1.0))
	if stats.cycle == "":
		FX.casing(self, eject.global_position, global_transform.basis.x, is_pistol())
	else:
		cycle_pending = 0.12
	Sfx.play(self, String(stats.sound), from, float(stats.volume))


# ------------------------------------------------------------------ laser

func _build_laser() -> void:
	var mat := M.glow(Color(1.0, 0.1, 0.05, 0.55))
	_beam = MeshInstance3D.new()
	_beam.mesh = ML.box(Vector3(0.004, 0.004, 1.0))
	_beam.material_override = mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	add_child(_beam)
	_beam_dot = MeshInstance3D.new()
	_beam_dot.mesh = ML.sphere(0.018, false, 8)
	_beam_dot.material_override = M.glow(Color(1.0, 0.15, 0.08, 0.9))
	_beam_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_dot.top_level = true
	add_child(_beam_dot)


func _update_laser() -> void:
	var from := laser.global_position
	var dir := -laser.global_transform.basis.z
	var to := from + dir * 40.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SHOTS)
	var owner_body := _owner_body()
	if owner_body:
		q.exclude = [owner_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		to = hit.position
	var length := maxf(from.distance_to(to), 0.01)
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	_beam.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1, 1, length)), from + dir * length * 0.5)
	_beam_dot.global_position = to
	_beam_dot.visible = not hit.is_empty()


func _owner_body() -> CollisionObject3D:
	var n := get_parent()
	while n != null:
		if n is CollisionObject3D:
			return n
		n = n.get_parent()
	return null
