extends "res://scripts/characters/soldier.gd"
## Infected soldier for Zombie Survival. Always hunts the player along the
## navmesh, groans, staggers when hit and lunges with a two-handed claw attack.
## Walkers, runners, brutes, low-profile crawlers, frontal-armored infected,
## and wounded berserkers. Special damage remains authoritative on the owner.

const Types = preload("res://scripts/characters/zombie_types.gd")
const Mat = preload("res://scripts/core/materials.gd")
const Geo = preload("res://scripts/core/mesh_lib.gd")

const Palettes = preload("res://scripts/core/palettes.gd")
const CreatureBody = preload("res://scripts/characters/creature_body.gd")
const Blast = preload("res://scripts/weapons/blast.gd")

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
## Separation push, refreshed ~15 times a second (staggered per zombie).
var _sep := Vector3.ZERO
var _sep_t := randf() * 0.066
## Live zombies, rebuilt once per physics frame and shared by every zombie.
static var _live: Array = []
static var _live_frame := -1
## Corpses stop simulating once they have dropped.
const CORPSE_SETTLE := 1.6
## Non-humanoid body (dog / bat); the humanoid rig is hidden for these.
var creature: CreatureBody
var _exploded := false
## Juggernaut (kind "boss"): slam and charge state, simulated by the owner.
var _slam_cd := 2.0
var _slam_t := 0.0          # > 0: winding up a ground slam
var _charge_cd := 3.0
var _charge_wind := 0.0     # > 0: roaring before a charge
var _charge_t := 0.0        # > 0: charging in a straight line
var _charge_dir := Vector3.FORWARD
var _charge_hit := false
var daze := 0.0             # > 0: ran into a wall, dazed and vulnerable
## Far from every operator the AI thinks on alternate physics ticks and
## glides along its velocity in between (half the CPU for distant hordes).
const FAR_THINK := 20.0
var _far := false
var _skip_acc := 0.0
var _tick_phase := randi() % 2


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
	elif kind == "bloater":
		rig.scale = Vector3(1.32, 1.04, 1.32)
	elif kind == "boss":
		rig.scale = Vector3.ONE * Types.BOSS_SCALE
		_shape.radius = 0.46
		_shape.height = STAND_HEIGHT * Types.BOSS_SCALE
		_col.position.y = _shape.height * 0.5
		accel = 6.0
		add_to_group("bosses")
	if Types.is_creature(kind):
		rig.visible = false
		creature = CreatureBody.new()
		creature.name = "Creature"
		add_child(creature)
		creature.build(kind)
		if kind == "dog":
			_shape.radius = 0.3
			_shape.height = 0.85
			_col.position.y = 0.45
		else:
			# bats fly: the hit capsule sits at hover height, the body floats
			_shape.radius = 0.28
			_shape.height = 0.6
			_col.position.y = CreatureBody.BAT_HOVER
			motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.6
	nav.target_desired_distance = 0.8
	nav.radius = 0.4 if kind != "boss" else 0.6
	nav.height = 1.8 if kind != "boss" else 2.8
	add_child(nav)
	_groan = randf_range(0.5, 5.0)
	add_to_group("enemies")
	add_to_group("zombies")
	call_deferred("optimize_detail")


## Flashed zombies stagger and lose track for a moment.
func flashbang(seconds: float, strength: float) -> void:
	super.flashbang(seconds, strength)
	if kind == "boss":
		_stagger = maxf(_stagger, seconds * 0.25)   # shrugs most of it off
		return
	_stagger = maxf(_stagger, seconds * 0.7)
	_attacking = 0.0


func is_in_combat() -> bool:
	return true


func _merge_exclude() -> Array:
	return _rage_marks   # their material swaps when enraged


func hear_noise(_pos: Vector3, _radius: float) -> void:
	pass


func hear_footstep(_pos: Vector3, _radius: float) -> void:
	pass


func _on_footstep(pos: Vector3, _intensity: float) -> void:
	if kind != "bat" and randf() < 0.5:
		Sfx.play(self, "footstep", pos, -21.0, 0.3)


func alert(_pos: Vector3) -> void:
	pass


func apply_damage(amount: float, hit_pos: Vector3, dir: Vector3, attacker: Node) -> bool:
	if Net.owns(self):
		var am := armor_multiplier(hit_pos, dir)
		if am < 1.0 and attacker != null and attacker.has_method("current_weapon") \
				and bool(attacker.current_weapon().stats.get("hollow", false)):
			am *= 0.5   # hollow points flatten on the plates
		amount *= am
		if daze > 0.0:
			amount *= Types.BOSS_STUN_DAMAGE
	var headshot := super.apply_damage(amount, hit_pos, dir, attacker)
	if Net.owns(self) and not is_dead and kind == "berserker" and health <= max_health * Types.RAGE_HEALTH:
		_set_enraged(true)
	if Net.owns(self) and not is_dead and kind == "boss" and health <= max_health * Types.BOSS_RAGE_HEALTH:
		_set_enraged(true)
	_stagger = {"brute": 0.12, "boss": 0.0}.get(kind, 0.35)
	return headshot


func is_head_hit(hit_pos: Vector3) -> bool:
	match kind:
		"bat":
			return false   # too small to have a weak point
		"dog":
			var local := hit_pos - global_position
			var forward := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
			return local.dot(forward) > 0.3 and local.y > 0.4 and local.y < 1.0
	return super.is_head_hit(hit_pos)


func chest_height() -> float:
	if kind == "boss":
		return super.chest_height() * Types.BOSS_SCALE
	match kind:
		"dog":
			return 0.55
		"bat":
			return CreatureBody.BAT_HOVER
	return super.chest_height()


func head_height() -> float:
	if kind == "boss":
		return super.head_height() * Types.BOSS_SCALE
	match kind:
		"dog":
			return 0.7
		"bat":
			return CreatureBody.BAT_HOVER + 0.1
	return super.head_height()


## Bats fly: no gravity, they hold a hover height over whatever is below them.
func move_with(desired: Vector3, delta: float) -> void:
	if kind != "bat":
		super.move_with(desired, delta)
		return
	if not is_dead:
		var t := Time.get_ticks_msec() * 0.001 + float(get_instance_id() % 97)
		desired += Vector3(desired.z, 0, -desired.x) * sin(t * 2.3) * 0.6   # erratic weave
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(desired, accel * delta)
	var ground := global_position.y
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 2.5, global_position + Vector3.DOWN * 4.0, Layers.WORLD, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		ground = hit.position.y
	velocity = Vector3(hv.x, clampf((ground - global_position.y) * 8.0, -6.0, 6.0), hv.z)
	move_and_slide()


func play_attack_anim(t: float) -> void:
	rig.play_attack(t)
	if creature:
		creature.play_attack(t)


func apply_knockback(v: Vector3, stun: float = 0.5) -> void:
	if kind == "bat":
		v.y = 0.0   # no jump impulse for flyers
	if kind == "boss":
		super.apply_knockback(Vector3(v.x, 0.0, v.z) * 0.2, 0.0)   # barely budges
		return
	super.apply_knockback(v, stun)
	_stagger = stun + 0.55   # reels before it comes again
	_attacking = 0.0
	_attack_cd = maxf(_attack_cd, 0.8)


func die(dir: Vector3) -> void:
	death_time = Time.get_ticks_msec() / 1000.0
	super.die(dir)
	if kind == "bloater":
		_detonate()


## Bloaters burst on death (or on reaching a target). Only the owner deals damage;
## other peers play the effect when the death event arrives.
func _detonate() -> void:
	if _exploded or not is_inside_tree():
		return
	_exploded = true
	rig.visible = false
	FX.blood(self, global_position + Vector3.UP * 1.1, Vector3.UP)
	Blast.detonate(self, global_position + Vector3.UP * 0.6, Types.BLOAT_DAMAGE, Types.BLOAT_RADIUS, self, [get_rid()], not puppet)


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
		# the body has hit the floor: no more physics for it (big win in late waves)
		if death_time > 0.0 and Time.get_ticks_msec() / 1000.0 - death_time > CORPSE_SETTLE and is_on_floor():
			set_physics_process(false)
		return
	if puppet:
		_puppet_move(delta)
		sprinting = (_net_flags & 4) != 0
		_groan -= delta
		if _groan <= 0.0:
			_groan = randf_range(3.5, 9.0)
			_vocalize()
		_sync_rig()
		return
	if _far and (Engine.get_physics_frames() + _tick_phase) % 2 == 1:
		_skip_acc += delta
		global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
		return
	delta += _skip_acc
	_skip_acc = 0.0
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
		_vocalize()

	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir := to / d if d > 0.01 else Vector3.FORWARD
	_far = d > FAR_THINK and kind != "boss" and _knock_t <= 0.0 and _attacking <= 0.0
	if _charge_t <= 0.0 and daze <= 0.0:
		_turn_to(atan2(-dir.x, -dir.z), delta, 9.0 if kind in ["dog", "bat"] else (6.0 if kind == "runner" else 4.0))
	_stagger = maxf(_stagger - delta, 0.0)
	sprinting = (kind == "runner" or enraged) and d > 3.0
	if kind == "boss" and _attacking <= 0.0 and _boss_update(delta, d, dir):
		_sync_rig()
		return

	# mid-attack: commit to the lunge, land the hit at the strike frame
	if _attacking > 0.0:
		_attacking -= delta
		move_with(dir * (1.2 if _attacking > 0.4 else 0.0), delta)
		if not _hit_done and _attacking < ATTACK_TIME * 0.5:
			_hit_done = true
			Sfx.play(self, "swipe", global_position + Vector3.UP * 1.3, -4.0)
			if kind == "bloater":
				die(dir)   # bursts on the target instead of clawing
				_sync_rig()
				return
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
			_attack_cd = {"brute": 1.5, "boss": 1.6, "dog": 0.7, "bat": 0.9}.get(kind, 1.0)
			play_attack_anim(ATTACK_TIME)
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
		_sep_t -= delta
		if _sep_t <= 0.0:
			_sep_t = 0.066
			_sep = _separation()
		move_with((move + _sep * 0.8).limit_length(1.0) * spd, delta)
	_sync_rig()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	var f := Engine.get_physics_frames()
	if f != _live_frame:
		_live_frame = f
		_live = get_tree().get_nodes_in_group("zombies").filter(func(z): return not z.is_dead)
	for e in _live:
		if e == self or not is_instance_valid(e) or e.is_dead:
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
		"dog", "bat":
			palette.headgear = "none"
			palette.eyes = false
		"bloater":
			palette.headgear = "none"
			palette.skin = Mat.solid(Color(0.55, 0.58, 0.32), 0.55)
			palette.vest = Mat.fabric("bloater_rags", Color(0.32, 0.3, 0.2))
		"berserker":
			palette.headgear = "none"
			palette.skin = Mat.solid(Color(0.62, 0.27, 0.23), 0.8)
			palette.vest = Mat.fabric("berserker_vest", Color(0.36, 0.08, 0.055))
		"boss":
			palette.headgear = "none"
			palette.skin = Mat.solid(Color(0.36, 0.33, 0.36), 0.75)
			palette.vest = Mat.fabric("boss_hide", Color(0.17, 0.13, 0.13))
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
	elif kind == "bloater":
		var gut := Mat.solid(Color(0.6, 0.62, 0.34), 0.45)
		var pus := Mat.emissive("bloater_pus", Color(0.75, 0.95, 0.2), 2.2)
		var belly := MeshInstance3D.new()
		belly.mesh = Geo.sphere(0.27, false, 14)
		belly.material_override = gut
		belly.position = Vector3(0, -0.02, -0.08)
		belly.scale = Vector3(1.0, 1.05, 0.95)
		rig.chest.add_child(belly)
		for i in 6:
			var boil := MeshInstance3D.new()
			boil.mesh = Geo.sphere(0.045 + 0.015 * (i % 3), false, 8)
			boil.material_override = pus
			var a := float(i) * 1.05
			boil.position = Vector3(sin(a) * 0.24, 0.12 * cos(a * 1.7), -0.08 - absf(cos(a)) * 0.2)
			rig.chest.add_child(boil)
	elif kind == "berserker":
		for side in [-1.0, 1.0]:
			var mark := MeshInstance3D.new()
			mark.mesh = Geo.sphere(0.075, false, 8)
			mark.position = Vector3(side * 0.22, 0.2, -0.12)
			mark.material_override = Mat.solid(Color(0.38, 0.07, 0.025))
			rig.chest.add_child(mark)
			_rage_marks.append(mark)
	elif kind == "boss":
		var bone := Mat.solid(Color(0.78, 0.74, 0.62), 0.6)
		var plate_mat := Mat.painted_metal("boss_plate", Color(0.22, 0.2, 0.19))
		for side in [-1.0, 1.0]:
			var pad := MeshInstance3D.new()
			pad.mesh = Geo.box(Vector3(0.22, 0.1, 0.3))
			pad.material_override = plate_mat
			pad.position = Vector3(side * 0.27, 0.27, 0.0)
			pad.rotation.z = side * 0.35
			rig.chest.add_child(pad)
		for i in 4:
			var spike := MeshInstance3D.new()
			spike.mesh = Geo.cylinder(0.0, 0.045, 0.22, 6)
			spike.material_override = bone
			spike.position = Vector3((i - 1.5) * 0.11, 0.1 + 0.06 * (i % 2), 0.17)
			spike.rotation.x = 1.15
			rig.chest.add_child(spike)
		var core := MeshInstance3D.new()
		core.mesh = Geo.sphere(0.09, false, 10)
		core.material_override = Mat.solid(Color(0.38, 0.07, 0.025))
		core.position = Vector3(0, 0.05, -0.2)
		rig.chest.add_child(core)
		_rage_marks.append(core)


func _set_enraged(on: bool) -> void:
	if kind not in ["berserker", "boss"] or enraged == on or is_dead: return
	enraged = on
	for mark in _rage_marks:
		mark.material_override = Mat.emissive("rage_glow", Color(1.0, 0.19, 0.025), 2.5) if on else Mat.solid(Color(0.38, 0.07, 0.025))
	if on:
		Sfx.play(self, "groan", global_position + Vector3.UP, -2.0 if kind != "boss" else 4.0)


func _clear_melee_path() -> bool:
	if not is_instance_valid(player) or player.is_dead: return false
	var origin := global_position + Vector3.UP * chest_height()
	var target: Vector3 = player.global_position + Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(origin, target, Layers.WORLD, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _vocalize() -> void:
	match kind:
		"bat":
			Sfx.play(self, "hitmarker", global_position + Vector3.UP * CreatureBody.BAT_HOVER, -14.0, 0.4)
		"dog":
			Sfx.play(self, "groan", global_position + Vector3.UP * 0.6, -6.0, 0.45)
		_:
			Sfx.play(self, "groan", global_position + Vector3.UP * 1.5, -9.0 if kind not in ["brute", "bloater"] else -4.0, 0.25)


# ---- Juggernaut boss --------------------------------------------------------

## Slam when the target is close, charge when it keeps its distance. Returns
## true when an ability drove this frame's movement.
func _boss_update(delta: float, d: float, dir: Vector3) -> bool:
	var rage := 0.65 if enraged else 1.0
	accel = 28.0 if _charge_t > 0.0 else 6.0   # bursts off the line, plants hard after
	_slam_cd -= delta
	_charge_cd -= delta
	if daze > 0.0:
		daze -= delta
		move_with(Vector3.ZERO, delta)
		return true
	if _slam_t > 0.0:
		_slam_t -= delta
		move_with(Vector3.ZERO, delta)
		if _slam_t <= 0.0:
			_slam_impact()
		return true
	if _charge_wind > 0.0:
		_charge_wind -= delta
		_charge_dir = dir   # keeps aiming during the roar, then commits
		move_with(Vector3.ZERO, delta)
		if _charge_wind <= 0.0:
			_charge_t = Types.BOSS_CHARGE_TIME
			_charge_hit = false
		return true
	if _charge_t > 0.0:
		_charge_t -= delta
		aim_yaw = atan2(-_charge_dir.x, -_charge_dir.z)
		sprinting = true
		move_with(_charge_dir * Types.BOSS_CHARGE_SPEED * (1.15 if enraged else 1.0), delta)
		if not _charge_hit and d < 1.9 and not player.is_dead:
			_charge_hit = true
			_charge_t = 0.0
			player.apply_damage(damage * 1.6, player.global_position + Vector3(0, 1.25, 0), _charge_dir, self)
			_knock_target(player, _charge_dir * 12.0 + Vector3.UP * 4.0, 0.8)
			Sfx.play(self, "explosion", global_position + Vector3.UP, -6.0, 0.15)
		elif _charge_t < Types.BOSS_CHARGE_TIME - 0.25 and _hit_wall():
			_charge_t = 0.0
			daze = Types.BOSS_WALL_STUN
			_boss_fx("daze")
			if Net.active and Net.sync:
				Net.sync.send_event(self, "boss", ["daze"])
		return true
	if player.is_dead:
		return false
	if d < Types.BOSS_SLAM_RANGE and _slam_cd <= 0.0 and _clear_melee_path():
		_slam_t = Types.BOSS_SLAM_WINDUP
		_slam_cd = Types.BOSS_SLAM_CD * rage
		_attack_cd = maxf(_attack_cd, Types.BOSS_SLAM_WINDUP + 0.5)
		_boss_fx("slam")
		if Net.active and Net.sync:
			Net.sync.send_event(self, "boss", ["slam"])
		return true
	if d > Types.BOSS_CHARGE_MIN and d < Types.BOSS_CHARGE_MAX and _charge_cd <= 0.0 and _clear_melee_path():
		_charge_wind = Types.BOSS_CHARGE_WINDUP
		_charge_cd = Types.BOSS_CHARGE_CD * rage
		_boss_fx("charge")
		if Net.active and Net.sync:
			Net.sync.send_event(self, "boss", ["charge"])
		return true
	return false


## The slam lands: every operator in reach is hurt and thrown outward.
func _slam_impact() -> void:
	var pos := global_position
	_boss_fx("impact")
	if Net.active and Net.sync:
		Net.sync.send_event(self, "boss", ["impact"])
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or p.is_dead:
			continue
		var off: Vector3 = p.global_position - pos
		off.y = 0.0
		var dist := off.length()
		if dist > Types.BOSS_SLAM_RADIUS:
			continue
		var out := off / dist if dist > 0.05 else Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
		var f := 1.0 - 0.6 * dist / Types.BOSS_SLAM_RADIUS
		p.apply_damage(damage * 1.4 * f, p.global_position + Vector3(0, 1.0, 0), out, self)
		_knock_target(p, out * 9.0 * f + Vector3.UP * 4.5, 0.6)


func _knock_target(p: Node, v: Vector3, stun: float) -> void:
	if not is_instance_valid(p) or p.is_dead:
		return
	if Net.owns(p):
		p.apply_knockback(v, stun)
	elif Net.sync:
		Net.sync.send_knock(p, v)


## Solid geometry ahead (not another body) stopped the charge.
func _hit_wall() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other is Node and ((other as Node).is_in_group("zombies") or (other as Node).is_in_group("player")):
			continue
		if absf(c.get_normal().y) < 0.5 and c.get_normal().dot(_charge_dir) < -0.5:
			return true
	return false


## Host boss events on clients.
func net_boss(args: Array) -> void:
	_boss_fx(String(args[0]))


## Telegraphs and impacts, played on every peer.
func _boss_fx(what: String) -> void:
	var pos := global_position
	match what:
		"slam":
			play_attack_anim(Types.BOSS_SLAM_WINDUP + 0.3)
			Sfx.play(self, "groan", pos + Vector3.UP * 2.0, 4.0, 0.1)
			_slam_ring(Types.BOSS_SLAM_WINDUP)
		"impact":
			FX.chips(self, pos + Vector3.UP * 0.1, Vector3.UP, Color(0.36, 0.31, 0.24), 26, 0.06, 9, 1.6)
			Sfx.play(self, "explosion", pos, 0.0, 0.1)
			_shake_near(pos, 0.9)
		"charge":
			Sfx.play(self, "groan", pos + Vector3.UP * 2.0, 7.0, 0.05)
			_shake_near(pos, 0.35)
		"daze":
			FX.chips(self, pos + Vector3.UP * 1.6, Vector3.UP, Color(0.9, 0.85, 0.5), 14, 0.03, 6, 1.0)
			Sfx.play(self, "helmet_ping", pos + Vector3.UP * 2.5, 2.0, 0.1)
			_shake_near(pos, 0.6)


func _shake_near(pos: Vector3, amount: float) -> void:
	var scene := get_tree().current_scene
	var cam = scene.get("camera_rig") if scene else null
	if cam == null or not is_instance_valid(cam) or cam.target == null:
		return
	var d: float = cam.target.global_position.distance_to(pos)
	cam.add_shake(amount * clampf(1.0 - d / 24.0, 0.0, 1.0))


static var _ring_mat: StandardMaterial3D

## Red ground ring that grows to the slam radius during the wind-up.
func _slam_ring(seconds: float) -> void:
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.albedo_color = Color(1.0, 0.12, 0.05, 0.32)
		_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = Types.BOSS_SLAM_RADIUS
	m.bottom_radius = Types.BOSS_SLAM_RADIUS
	m.height = 0.03
	m.radial_segments = 40
	m.rings = 1
	ring.mesh = m
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3.UP * 0.06
	ring.scale = Vector3(0.15, 1.0, 0.15)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE, seconds).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.12)
	tw.tween_callback(ring.queue_free)
