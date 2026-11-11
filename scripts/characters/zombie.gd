extends "res://scripts/characters/soldier.gd"
## Infected soldier for Zombie Survival. Always hunts the player along the
## navmesh, groans, staggers when hit and lunges with a two-handed claw attack.
## Walkers, runners, brutes, low-profile crawlers, frontal-armored infected,
## and wounded berserkers. Special damage remains authoritative on the owner.

const Types = preload("res://scripts/characters/zombie_types.gd")
const Mat = preload("res://scripts/core/materials.gd")
const Geo = preload("res://scripts/core/mesh_lib.gd")

const Palettes = preload("res://scripts/core/palettes.gd")

const ATTACK_RANGE := 1.35
const HIT_RANGE := 1.9
const ATTACK_TIME := 0.8

var player
var kind := "walker"
var enraged := false
var _rage_marks: Array[MeshInstance3D] = []
var move_speed := 1.8
var damage := 10.0
var death_time := -1.0

# fields the HUD / aim assist read from every hostile
var alert_flash := 0.0
var awareness := 0.0

var nav: NavigationAgent3D
var _repath := 0.0
var _attack_cd := 0.0
var _attacking := 0.0
var _hit_done := false
var _groan := 0.0
var _stagger := 0.0
var _retarget := 0.0
var _net_flags := 0


func init_zombie(p_player, p_kind: String, hp: float, spd: float, dmg: float, variant: int) -> void:
	player = p_player
	kind = p_kind
	move_speed = spd
	damage = dmg
	var to: Vector3 = player.global_position - global_position
	setup_soldier(_type_palette(variant), [], Layers.ENEMY, Layers.WORLD | Layers.PLAYER | Layers.ENEMY, atan2(-to.x, -to.z))
	team = 2
	max_health = hp
	health = hp
	accel = 10.0 if kind != "runner" else 16.0
	rig.zombie = true
	rig.zombie_kind = kind
	if kind == "crawler":
		set_crouch(true)
		rig.crouch_target = 1.0
		rig.crouch_amt = 1.0
	_build_type_details()
	if kind == "brute":
		rig.scale = Vector3.ONE * 1.18
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.6
	nav.target_desired_distance = 0.8
	nav.radius = 0.4
	nav.height = 1.8
	add_child(nav)
	_groan = randf_range(0.5, 5.0)
	add_to_group("enemies")
	add_to_group("zombies")


func is_in_combat() -> bool:
	return true


func hear_noise(_pos: Vector3, _radius: float) -> void:
	pass


func hear_footstep(_pos: Vector3, _radius: float) -> void:
	pass


func _on_footstep(pos: Vector3, _intensity: float) -> void:
	if randf() < 0.5:
		Sfx.play(self, "footstep", pos, -21.0, 0.3)


func alert(_pos: Vector3) -> void:
	pass


func apply_damage(amount: float, hit_pos: Vector3, dir: Vector3, attacker: Node) -> bool:
	if Net.owns(self):
		amount *= armor_multiplier(hit_pos, dir)
	var headshot := super.apply_damage(amount, hit_pos, dir, attacker)
	if Net.owns(self) and not is_dead and kind == "berserker" and health <= max_health * Types.RAGE_HEALTH:
		_set_enraged(true)
	_stagger = 0.35 if kind != "brute" else 0.12
	return headshot


func apply_knockback(v: Vector3, stun: float = 0.5) -> void:
	super.apply_knockback(v, stun)
	_stagger = stun + 0.55   # reels before it comes again
	_attacking = 0.0
	_attack_cd = maxf(_attack_cd, 0.8)


func die(dir: Vector3) -> void:
	death_time = Time.get_ticks_msec() / 1000.0
	super.die(dir)


## Host snapshot (clients only); state / awareness are unused for zombies.
func net_target(pos: Vector3, vel: Vector3, yaw: float, flags: int, _st: int, _aw: float, _af: float) -> void:
	_net_set(pos, vel, yaw)
	_net_flags = flags
	_set_enraged((flags & 8) != 0)


## Hunts the nearest living operator (multiplayer: any player).
func _pick_target() -> void:
	var best = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_dead:
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	if best != null:
		player = best


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	if is_dead:
		if not puppet:
			move_with(Vector3.ZERO, delta)
		_sync_rig()
		return
	if puppet:
		_puppet_move(delta)
		sprinting = (_net_flags & 4) != 0
		_groan -= delta
		if _groan <= 0.0:
			_groan = randf_range(3.5, 9.0)
			Sfx.play(self, "groan", global_position + Vector3.UP * 1.5, -9.0 if kind != "brute" else -4.0, 0.25)
		_sync_rig()
		return
	_retarget -= delta
	if _retarget <= 0.0 or player == null or player.is_dead:
		_retarget = 0.5
		_pick_target()
	if player == null:
		move_with(Vector3.ZERO, delta)
		_sync_rig()
		return

	_groan -= delta
	if _groan <= 0.0:
		_groan = randf_range(3.5, 9.0)
		Sfx.play(self, "groan", global_position + Vector3.UP * 1.5, -9.0 if kind != "brute" else -4.0, 0.25)

	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir := to / d if d > 0.01 else Vector3.FORWARD
	_turn_to(atan2(-dir.x, -dir.z), delta, 6.0 if kind == "runner" else 4.0)
	_stagger = maxf(_stagger - delta, 0.0)
	sprinting = (kind == "runner" or enraged) and d > 3.0

	# mid-attack: commit to the lunge, land the hit at the strike frame
	if _attacking > 0.0:
		_attacking -= delta
		move_with(dir * (1.2 if _attacking > 0.4 else 0.0), delta)
		if not _hit_done and _attacking < ATTACK_TIME * 0.5:
			_hit_done = true
			Sfx.play(self, "swipe", global_position + Vector3.UP * 1.3, -4.0)
			if d < HIT_RANGE and not player.is_dead and _clear_melee_path():
				player.apply_damage(damage * (Types.RAGE_DAMAGE if enraged else 1.0), player.global_position + Vector3(0, 1.25, 0), dir, self)
		_sync_rig()
		return

	_attack_cd -= delta
	if player.is_dead:
		move_with(Vector3.ZERO, delta)
	elif d < ATTACK_RANGE:
		move_with(Vector3.ZERO, delta)
		if _attack_cd <= 0.0 and _clear_melee_path():
			_attacking = ATTACK_TIME
			_hit_done = false
			_attack_cd = 1.0 if kind != "brute" else 1.5
			rig.play_attack(ATTACK_TIME)
			if Net.active and Net.sync:
				Net.sync.send_event(self, "attack", [ATTACK_TIME])
	else:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.25
			nav.target_position = player.global_position
		var move := dir
		if d > 2.5 and not nav.is_navigation_finished():
			var next := nav.get_next_path_position() - global_position
			next.y = 0.0
			if next.length() > 0.05:
				move = next.normalized()
		var spd := move_speed * (Types.RAGE_SPEED if enraged else 1.0) * (0.35 if _stagger > 0.0 else 1.0)
		move_with((move + _separation() * 0.8).limit_length(1.0) * spd, delta)
	_sync_rig()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("zombies"):
		if e == self or e.is_dead:
			continue
		var d: Vector3 = global_position - e.global_position
		d.y = 0.0
		var l := d.length()
		if l < 1.0 and l > 0.001:
			push += d / l * (1.0 - l)
	return push


func _turn_to(target_yaw: float, delta: float, rate: float) -> void:
	aim_yaw = wrapf(aim_yaw + clampf(wrapf(target_yaw - aim_yaw, -PI, PI), -rate * delta, rate * delta), -PI, PI)


func armor_multiplier(hit_pos: Vector3, incoming: Vector3) -> float:
	if kind != "armored": return 1.0
	var height := hit_pos.y - global_position.y
	# Helmet silhouette is readable, but headshots and legs remain weak points.
	if height < 0.65 or height > head_height() - 0.14: return 1.0
	var forward := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	var toward_attacker := Vector3(-incoming.x, 0, -incoming.z).normalized()
	return Types.ARMOR_MULTIPLIER if forward.dot(toward_attacker) > 0.4 else 1.0


func _type_palette(variant: int) -> Dictionary:
	var palette := Palettes.zombie(variant)
	match kind:
		"crawler":
			palette.headgear = "none"
			palette.skin = Mat.solid(Color(0.43, 0.52, 0.29), 0.9)
			palette.vest = Mat.fabric("crawler_rags", Color(0.31, 0.29, 0.13))
		"armored":
			palette.headgear = "helmet"
			palette.helmet = Mat.painted_metal("infected_helmet", Color(0.16, 0.23, 0.28))
			palette.vest = palette.helmet
		"berserker":
			palette.headgear = "none"
			palette.skin = Mat.solid(Color(0.62, 0.27, 0.23), 0.8)
			palette.vest = Mat.fabric("berserker_vest", Color(0.36, 0.08, 0.055))
	return palette


func _build_type_details() -> void:
	if kind == "armored":
		var plate := MeshInstance3D.new()
		plate.mesh = Geo.box(Vector3(0.44, 0.39, 0.10))
		plate.material_override = Mat.painted_metal("infected_plate", Color(0.19, 0.27, 0.32))
		plate.position = Vector3(0, 0.08, -0.18)
		rig.chest.add_child(plate)
		var stripe := MeshInstance3D.new()
		stripe.mesh = Geo.box(Vector3(0.32, 0.045, 0.012))
		stripe.material_override = Mat.solid(Color(0.85, 0.63, 0.16))
		stripe.position = Vector3(0, 0.12, -0.238)
		rig.chest.add_child(stripe)
	elif kind == "berserker":
		for side in [-1.0, 1.0]:
			var mark := MeshInstance3D.new()
			mark.mesh = Geo.sphere(0.075, false, 8)
			mark.position = Vector3(side * 0.22, 0.2, -0.12)
			mark.material_override = Mat.solid(Color(0.38, 0.07, 0.025))
			rig.chest.add_child(mark)
			_rage_marks.append(mark)


func _set_enraged(on: bool) -> void:
	if kind != "berserker" or enraged == on or is_dead: return
	enraged = on
	for mark in _rage_marks:
		mark.material_override = Mat.emissive("rage_glow", Color(1.0, 0.19, 0.025), 2.5) if on else Mat.solid(Color(0.38, 0.07, 0.025))
	if on:
		Sfx.play(self, "groan", global_position + Vector3.UP, -2.0)


func _clear_melee_path() -> bool:
	if not is_instance_valid(player) or player.is_dead: return false
	var origin := global_position + Vector3.UP * chest_height()
	var target: Vector3 = player.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin, target, Layers.WORLD, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
