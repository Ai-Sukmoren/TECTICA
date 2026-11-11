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

var id := ""
var stats: Dictionary = {}
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

var grip: Node3D
var support: Node3D
var muzzle: Node3D
var mag_node: Node3D
var mag_well: Node3D
var charge: Node3D
var eject: Node3D
var pump: Node3D
var bolt: Node3D
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
	var parts: Dictionary = Model.build(String(stats.model), attachments)
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
	laser = parts.laser
	var sight: Dictionary = parts.sight
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


func is_pistol() -> bool:
	return stats.kind == "pistol"


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
	cooldown = 60.0 / float(stats.rpm)
	ammo -= 1
	var total_spread := spread_deg + bloom
	bloom = minf(bloom + float(stats.bloom_add), float(stats.bloom_max))

	var base_dir := target - origin
	if base_dir.length() < 0.05:
		base_dir = -global_transform.basis.z
	base_dir = base_dir.normalized()
	var result := {"hit": null, "headshot": false, "killed": false, "position": origin + base_dir * float(stats.range), "ends": []}
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
		var q := PhysicsRayQueryParameters3D.create(origin, end, Layers.SHOTS, [shooter.get_rid()])
		var hit := space.intersect_ray(q)
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
					result.headshot = result.headshot or hs
					result.hit = col
					result.killed = result.killed or col.get("is_dead") == true
			elif i % 2 == 0 or pellets == 1:
				FX.impact(self, end, hit.normal)
			var flesh: bool = col != null and col.has_method("apply_damage") and col.get("is_dead") != null
			shot_end = [end, hit.normal, 2 if flesh else 1]
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


## Replays another peer's shot from its end points: tracers, impacts, blood,
## muzzle flash, casing and sound. No ammo, no damage.
func fire_fx(ends: Array) -> void:
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
			1:
				if even:
					FX.impact(self, end, e[1])
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
