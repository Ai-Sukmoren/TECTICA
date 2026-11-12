extends "res://scripts/characters/soldier.gd"
## Hostile AI soldier.
##
## Perception: vision cone + line-of-sight raycasts to chest and head, an
## awareness meter that fills faster at close range and slower vs. a crouched
## target, hearing of gunshots, and squad call-outs to nearby allies.
##
## States: PATROL -> SUSPICIOUS (investigate) -> COMBAT (take cover, hide,
## peek and fire bursts, reload behind cover, or strafe in the open) ->
## SEARCH (sweep last known position) -> back to PATROL.

const Palettes = preload("res://scripts/core/palettes.gd")

enum State { PATROL, SUSPICIOUS, COMBAT, SEARCH }
## FLANK: circling to the player's side while the squad pins them down.
enum Phase { MOVING, HIDDEN, PEEKING, OPEN, FLANK }

const VIEW_DIST := 26.0
const FOV_HALF := 1.15
const WALK_SPEED := 1.6
const RUN_SPEED := 4.4

var player
var level
var state: State = State.PATROL
var phase: Phase = Phase.MOVING
var patrol: Array = []
var patrol_index := 0
var home_pos := Vector3.ZERO
var home_yaw := 0.0
var wait_timer := 0.0
var awareness := 0.0
var last_known := Vector3.ZERO
var sees_player := false
var time_since_seen := 99.0
var reaction_timer := 0.0
var alert_flash := 0.0
var cover = null
var nav: NavigationAgent3D

var _perceive_timer := 0.0
var _cover_timer := 0.0
var _phase_timer := 0.0
var _burst_left := 0
var _burst_timer := 0.0
var _search_timer := 0.0
var _investigate_delay := 0.0
var _strafe_sign := 1.0
var _strafe_timer := 0.0
var _scan_t := 0.0
var _grenade_check := 2.0
var torch: SpotLight3D
static var _squad_grenade_t := -100.0
## Squad tactics: one flanker at a time; the rest lay down suppressive fire.
static var _flanker: Node = null
var _flank_pos := Vector3.ZERO
var _flank_t := 0.0
var _flank_check := 3.0
var _fell_back := false
var _callout_cd := 0.0


func init_enemy(p_player, p_level, data: Dictionary, variant: int) -> void:
	player = p_player
	level = p_level
	home_pos = global_position
	home_yaw = float(data.get("yaw", 0.0))
	patrol = data.get("patrol", [])
	setup_soldier(Palettes.enemy(variant), ["akm"], Layers.ENEMY, Layers.WORLD | Layers.PLAYER | Layers.ENEMY, home_yaw)
	# desert / olive / dark tints so hostiles read differently from the (grey) player
	use_character_model([Color(1.25, 1.05, 0.72), Color(0.85, 1.0, 0.7), Color(0.75, 0.72, 0.7)][posmod(variant, 3)])
	team = 1
	grenades = 1
	flashbangs = 1 if randf() < 0.4 else 0
	torch = SpotLight3D.new()
	torch.position = Vector3(0, -0.02, -0.95)
	torch.spot_range = 20.0
	torch.spot_angle = 20.0
	torch.light_energy = 3.0
	torch.light_color = Color(1.0, 0.93, 0.8)
	torch.light_volumetric_fog_energy = 0.8
	torch.visible = false
	rig.weapon_anchor.add_child(torch)
	max_health = 100.0
	health = max_health
	_scan_t = randf() * 10.0
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.5
	nav.target_desired_distance = 0.5
	nav.radius = 0.45
	nav.height = 1.8
	nav.path_max_distance = 2.0
	add_child(nav)
	add_to_group("enemies")
	call_deferred("optimize_detail")


func is_in_combat() -> bool:
	return state == State.COMBAT


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	_tick_actions(delta)
	if puppet:
		_puppet_physics(delta)
		return
	if is_dead:
		move_with(Vector3.ZERO, delta)
		_sync_rig()
		return
	alert_flash = maxf(alert_flash - delta, 0.0)
	if blind_t > 0.0:
		# flashed: can't see or shoot, staggers about with an arm up
		blind_t -= delta
		sees_player = false
		aiming = false
		reaction_timer = maxf(reaction_timer, 0.6)
		_burst_left = 0
		var wobble := Vector3(sin(blind_t * 3.1), 0, cos(blind_t * 2.3)) * 0.6
		move_with(wobble, delta)
		_sync_rig()
		return
	if torch:
		torch.visible = _night() > 0.45
	_perceive(delta)
	match state:
		State.PATROL:
			_do_patrol(delta)
		State.SUSPICIOUS:
			_do_suspicious(delta)
		State.COMBAT:
			_do_combat(delta)
		State.SEARCH:
			_do_search(delta)
	_sync_rig()


# ================================================================ network puppet

var _net_flags := 0


## Host snapshot for this guard (clients only).
func net_target(pos: Vector3, vel: Vector3, yaw: float, flags: int, st: int, aw: float, af: float) -> void:
	_net_set(pos, vel, yaw)
	_net_flags = flags
	state = st as State
	awareness = aw
	alert_flash = af


func _puppet_physics(delta: float) -> void:
	if is_dead:
		_sync_rig()
		return
	_puppet_move(delta)
	set_crouch((_net_flags & 1) != 0)
	aiming = (_net_flags & 2) != 0
	sprinting = (_net_flags & 4) != 0
	alert_flash = maxf(alert_flash - delta, 0.0)
	if torch:
		torch.visible = _night() > 0.45
	_sync_rig()


# ================================================================ perception

## Engages the nearest operator it can see (multiplayer: any player).
func _pick_target() -> bool:
	var best = null
	var best_d := INF
	var best_vis := false
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_dead:
			continue
		var vis := _can_see(p)
		var d: float = global_position.distance_to(p.global_position)
		if (vis and not best_vis) or (vis == best_vis and d < best_d):
			best = p
			best_d = d
			best_vis = vis
	if best != null:
		player = best
	return best_vis


func _perceive(delta: float) -> void:
	time_since_seen += delta
	_perceive_timer -= delta
	if _perceive_timer <= 0.0:
		_perceive_timer = 0.1
		var was := sees_player
		sees_player = _pick_target()
		if sees_player and not was:
			reaction_timer = randf_range(0.3, 0.55)
	if player == null:
		return
	if player.is_dead:
		sees_player = false
	if sees_player:
		time_since_seen = 0.0
		last_known = player.global_position
		var d := global_position.distance_to(player.global_position)
		var gain := 1.3 * clampf(1.5 - d / VIEW_DIST, 0.3, 1.5)
		if state == State.SUSPICIOUS or state == State.SEARCH:
			gain *= 2.5
		if player.crouching:
			gain *= 0.55
		gain *= lerpf(1.0, 0.6, _night()) if player.get("flashlight_on") != true else 1.3
		if player.sprinting:
			gain *= 1.6
		if d < 4.0:
			gain *= 4.0
		awareness = minf(awareness + gain * delta, 1.0)
		if awareness >= 1.0 and state != State.COMBAT:
			_enter_combat(true)
		elif awareness > 0.35 and state == State.PATROL:
			_enter_suspicious(player.global_position)
	elif state != State.COMBAT:
		awareness = maxf(awareness - 0.1 * delta, 0.0)


func _can_see(p) -> bool:
	if p == null or p.is_dead:
		return false
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > VIEW_DIST * vision_scale(p):
		return false
	if d > 2.5:
		var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
		var fov := FOV_HALF * (1.5 if state == State.COMBAT else 1.0)
		if fwd.angle_to(to) > fov:
			return false
	var eye := global_position + Vector3(0, head_height() - 0.05, 0)
	var space := get_world_3d().direct_space_state
	for h in [p.chest_height(), p.head_height() - 0.05]:
		var q := PhysicsRayQueryParameters3D.create(eye, p.global_position + p.peek_offset() + Vector3(0, h, 0), Layers.WORLD)
		if space.intersect_ray(q).is_empty():
			return true
	return false


func _night() -> float:
	var n = level.get("night") if level else null
	return float(n) if n != null else 0.0


## How far this guard can spot the player right now: darkness, the player's
## flashlight and bushes (crouching inside one) all matter.
func vision_scale(p = null) -> float:
	if p == null:
		p = player
	var k := lerpf(1.0, 0.4, _night())
	if p == null:
		return k
	if p.get("flashlight_on") == true:
		k = maxf(k, 1.15)
	if level and level.has_method("concealment"):
		var c: float = level.concealment(p.global_position)
		k *= 1.0 - c * (0.65 if p.crouching else 0.3)
	if state == State.COMBAT:
		k = maxf(k, 0.55)
	return k


func hear_noise(pos: Vector3, radius: float) -> void:
	if is_dead:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	var guess := pos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	if state == State.COMBAT:
		if not sees_player:
			last_known = guess
		return
	last_known = guess
	if d < radius * 0.6:
		_enter_combat(false)
	else:
		_enter_suspicious(guess)


## Flush a hidden player out of cover with a frag.
func _try_grenade() -> void:
	if (grenades <= 0 and flashbangs <= 0) or not can_act() or sees_player:
		return
	if time_since_seen < 1.0 or time_since_seen > 8.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _squad_grenade_t < 7.0:
		return
	var d := _flat_dist(last_known)
	if d < 6.0 or d > 19.0 or randf() > 0.4:
		return
	aim_yaw = _yaw_to(last_known)
	var flash := flashbangs > 0 and randf() < 0.5
	if throw_grenade(last_known + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)), "flash" if flash else "frag"):
		_squad_grenade_t = now
		callout("FLASHBANG!" if flash else "FRAG OUT!", Color(0.9, 0.95, 1.0) if flash else Color(1.0, 0.55, 0.2))


func hear_footstep(pos: Vector3, radius: float) -> void:
	if is_dead or state == State.COMBAT:
		return
	if global_position.distance_to(pos) < radius:
		awareness = maxf(awareness, 0.45)
		_enter_suspicious(pos)


func alert(pos: Vector3) -> void:
	if is_dead or state == State.COMBAT:
		return
	last_known = pos
	_enter_combat(false)


func apply_damage(amount: float, hit_pos: Vector3, dir: Vector3, attacker: Node) -> bool:
	var headshot := super.apply_damage(amount, hit_pos, dir, attacker)
	if not is_dead and attacker is Node3D and attacker != self:
		last_known = (attacker as Node3D).global_position
		if state != State.COMBAT:
			_enter_combat(true)
		elif phase == Phase.PEEKING:
			phase = Phase.HIDDEN
			_phase_timer = randf_range(0.8, 1.6)
		# badly hurt: break off to cover further back (once)
		if not _fell_back and health < max_health * 0.35 and state == State.COMBAT:
			_fell_back = true
			_end_flank()
			var back = level.find_cover(self, last_known, true)
			if back != null:
				_release_cover()
				cover = back
				phase = Phase.MOVING
				_cover_timer = 2.5
				callout("FALLING BACK!", Color(0.95, 0.85, 0.4))
	return headshot


func flashbang(seconds: float, strength: float) -> void:
	super.flashbang(seconds, strength)
	if is_dead:
		return
	_release_cover()
	_end_flank()
	if state != State.COMBAT and strength > 0.2:
		_enter_combat(false)
	callout("I'M BLIND!", Color(1.0, 1.0, 1.0))


func apply_knockback(v: Vector3, stun: float = 0.5) -> void:
	super.apply_knockback(v, stun)
	reaction_timer = maxf(reaction_timer, 0.9)   # winded: can't shoot back at once
	_burst_left = 0


func die(dir: Vector3) -> void:
	_end_flank()
	if torch:
		torch.visible = false
		torch.queue_free()
		torch = null
	_release_cover()
	super.die(dir)


# ================================================================ state entry

func _enter_combat(call_out: bool) -> void:
	state = State.COMBAT
	awareness = 1.0
	alert_flash = 1.8
	reaction_timer = maxf(reaction_timer, randf_range(0.35, 0.6))
	phase = Phase.MOVING
	_cover_timer = 0.0
	if call_out:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e != self and not e.is_dead and e.global_position.distance_to(global_position) < 20.0:
				e.alert(last_known)


func _enter_suspicious(pos: Vector3) -> void:
	if state == State.COMBAT:
		return
	state = State.SUSPICIOUS
	last_known = pos
	_investigate_delay = randf_range(0.6, 1.2)
	_search_timer = 0.0


func _enter_search() -> void:
	state = State.SEARCH
	_release_cover()
	_search_timer = 0.0
	set_crouch(false)


# ================================================================ behaviours

func _do_patrol(delta: float) -> void:
	aiming = false
	sprinting = false
	set_crouch(false)
	if patrol.size() >= 2:
		if wait_timer > 0.0:
			wait_timer -= delta
			move_with(Vector3.ZERO, delta)
			_scan_t += delta
			_turn_to(aim_yaw + sin(_scan_t * 0.9) * 0.02, delta, 2.0)
		elif _nav_to(patrol[patrol_index], WALK_SPEED, delta):
			wait_timer = randf_range(1.5, 3.5)
			patrol_index = (patrol_index + 1) % patrol.size()
		else:
			_face_velocity(delta)
	else:
		if global_position.distance_to(home_pos) > 1.0:
			_nav_to(home_pos, WALK_SPEED, delta)
			_face_velocity(delta)
		else:
			move_with(Vector3.ZERO, delta)
			_scan_t += delta
			_turn_to(home_yaw + sin(_scan_t * 0.35) * 0.7, delta, 1.5)


func _do_suspicious(delta: float) -> void:
	aiming = true
	sprinting = false
	_turn_to(_yaw_to(last_known), delta, 4.0)
	if awareness <= 0.0:
		state = State.PATROL
		return
	if _investigate_delay > 0.0:
		_investigate_delay -= delta
		move_with(Vector3.ZERO, delta)
		return
	if _nav_to(last_known, WALK_SPEED * 1.2, delta):
		_search_timer += delta
		_turn_to(aim_yaw + delta * 1.5, delta, 2.0)
		if _search_timer > 4.0:
			state = State.PATROL
	else:
		_face_velocity(delta, true)


func _do_search(delta: float) -> void:
	aiming = true
	sprinting = false
	if _nav_to(last_known, 2.6, delta):
		_search_timer += delta
		_scan_t += delta
		_turn_to(aim_yaw + 2.2 * delta * signf(sin(_scan_t * 0.6)), delta, 3.0)
		if _search_timer > 7.0:
			state = State.PATROL
			awareness = 0.3
	else:
		_face_velocity(delta, true)


func _do_combat(delta: float) -> void:
	sprinting = false
	if player == null or player.is_dead:
		_enter_search()
		return
	var threat: Vector3 = player.global_position if sees_player else last_known
	if not sees_player and time_since_seen > 7.0:
		_enter_search()
		return
	_grenade_check -= delta
	if _grenade_check <= 0.0:
		_grenade_check = 1.0
		_try_grenade()

	_try_flank(delta, threat)
	if phase == Phase.FLANK:
		_do_flank(delta, threat)
		return

	_cover_timer -= delta
	if _cover_timer <= 0.0:
		_cover_timer = 0.8
		if cover == null or not level.is_cover_good(cover, threat):
			_release_cover()
			cover = level.find_cover(self, threat)
			phase = Phase.MOVING if cover != null else Phase.OPEN
		elif phase == Phase.OPEN:
			phase = Phase.MOVING

	_turn_to(_yaw_to(threat), delta, 7.0)

	match phase:
		Phase.MOVING:
			set_crouch(false)
			aiming = sees_player
			var cp: Vector3 = cover.pos
			if _nav_to(cp, RUN_SPEED, delta) or _flat_dist(cp) < 0.6:
				phase = Phase.HIDDEN
				_phase_timer = randf_range(0.5, 1.2)
			elif sees_player and randf() < 0.5:
				_shoot(delta)
		Phase.HIDDEN:
			move_with(Vector3.ZERO, delta)
			set_crouch(true)
			aiming = false
			var w := current_weapon()
			if w.ammo < int(w.stats.mag) * 0.4 and w.reserve > 0 and reload_timer <= 0.0:
				start_reload()
				if randf() < 0.5:
					callout("RELOADING!", Color(0.8, 0.85, 0.9))
			_phase_timer -= delta
			if _phase_timer <= 0.0 and reload_timer <= 0.0:
				phase = Phase.PEEKING
				_phase_timer = randf_range(1.5, 3.0)
				_burst_timer = 0.0
		Phase.PEEKING:
			move_with(Vector3.ZERO, delta)
			set_crouch(false)
			aiming = true
			if sees_player:
				_shoot(delta)
			elif _suppressing():
				_shoot(delta, last_known)
			_phase_timer -= delta
			if _phase_timer <= 0.0 or current_weapon().ammo <= 0:
				phase = Phase.HIDDEN
				_phase_timer = randf_range(1.0, 2.2)
		Phase.OPEN:
			set_crouch(false)
			aiming = sees_player or _suppressing()
			if not sees_player and _suppressing():
				# hold here and pin the player while the flanker works around
				move_with(_separation(), delta)
				set_crouch(true)
				_shoot(delta, last_known)
			elif not sees_player:
				_nav_to(threat, RUN_SPEED * 0.8, delta)
			else:
				var to := threat - global_position
				to.y = 0.0
				var d := to.length()
				var dir := to.normalized()
				_strafe_timer -= delta
				if _strafe_timer <= 0.0:
					_strafe_timer = randf_range(1.2, 2.6)
					_strafe_sign = -_strafe_sign
				var move := dir.cross(Vector3.UP) * _strafe_sign
				if d > 16.0:
					move += dir
				elif d < 7.0:
					move -= dir
				move_with(move.normalized() * 2.2 + _separation(), delta)
				_shoot(delta)


func _shoot(delta: float, at = null) -> void:
	if reaction_timer > 0.0:
		reaction_timer -= delta
		return
	var w := current_weapon()
	if w.ammo <= 0:
		start_reload()
		return
	_burst_timer -= delta
	if _burst_left <= 0:
		if _burst_timer <= 0.0:
			_burst_left = randi_range(3, 6)
		return
	var aim_at: Vector3 = player.global_position if at == null else at
	if absf(wrapf(_yaw_to(aim_at) - aim_yaw, -PI, PI)) > 0.18:
		return
	var target: Vector3 = player.global_position + player.peek_offset() + Vector3(0, player.chest_height(), 0)
	if at != null:
		# suppressive fire: rake the area around the last known position
		target = (at as Vector3) + Vector3(randf_range(-1.2, 1.2), randf_range(0.6, 1.6), randf_range(-1.2, 1.2))
	if try_fire(target):
		_burst_left -= 1
		if _burst_left <= 0:
			_burst_timer = randf_range(0.35, 0.9)


func get_spread() -> float:
	var base := super.get_spread()
	if player == null:
		return base
	var d := global_position.distance_to(player.global_position)
	var pv := Vector2(player.velocity.x, player.velocity.z).length()
	return base + d * 0.06 + pv * 0.45 + (1.0 if player.crouching else 0.0)


# ================================================================ squad tactics

## A squad member pinned down by a hidden player may break off to flank.
func _try_flank(delta: float, threat: Vector3) -> void:
	_flank_check -= delta
	if _flank_check > 0.0 or phase == Phase.FLANK:
		return
	_flank_check = randf_range(2.0, 3.5)
	if sees_player or time_since_seen < 2.5 or time_since_seen > 12.0 or _fell_back:
		return
	if is_instance_valid(_flanker) and not _flanker.is_dead and _flanker != self:
		return
	if health < max_health * 0.5 or randf() > 0.55:
		return
	var allies := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and not e.is_dead and e.get("state") == State.COMBAT and e.global_position.distance_to(global_position) < 25.0:
			allies += 1
	if allies < 1:
		return   # a lone guard holds cover instead of wandering off
	# a point off to the side of the player, 9-12 m away, reachable on the navmesh
	var to := global_position - threat
	to.y = 0.0
	if to.length() < 0.5:
		return
	var side := to.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	var p := threat + side * randf_range(9.0, 12.0) + to.normalized() * 2.0
	p = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
	if p.distance_to(threat) < 6.0:
		return
	_flanker = self
	_flank_pos = p
	_flank_t = 11.0
	_release_cover()
	phase = Phase.FLANK
	callout("FLANKING!", Color(1.0, 0.35, 0.3))


func _do_flank(delta: float, threat: Vector3) -> void:
	_flank_t -= delta
	set_crouch(false)
	aiming = sees_player
	sprinting = not sees_player
	if sees_player:
		# found an angle: fight from here
		_end_flank()
		phase = Phase.OPEN
		_shoot(delta)
		return
	_turn_to(_yaw_to(_flank_pos if _flat_dist(_flank_pos) > 2.0 else threat), delta, 7.0)
	if _nav_to(_flank_pos, RUN_SPEED, delta) or _flank_t <= 0.0:
		_end_flank()
		phase = Phase.OPEN   # push in from the new side


func _end_flank() -> void:
	if _flanker == self:
		_flanker = null
	sprinting = false


## Pinned-down squadmates fire on the last known position while someone flanks.
func _suppressing() -> bool:
	return is_instance_valid(_flanker) and _flanker != self and not _flanker.is_dead \
			and time_since_seen < 6.0 and _flat_dist(last_known) < 24.0


## Short shout over the head (FLANKING! / FRAG OUT! / RELOADING!).
func callout(text: String, color: Color) -> void:
	if _callout_cd > Time.get_ticks_msec() / 1000.0:
		return
	_callout_cd = Time.get_ticks_msec() / 1000.0 + 2.5
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 2.25, 0)
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", 2.6, 1.4)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.4).set_delay(0.6)
	tw.tween_callback(l.queue_free)


# ================================================================ helpers

func _nav_to(target: Vector3, spd: float, delta: float) -> bool:
	if nav.target_position.distance_to(target) > 0.4:
		nav.target_position = target
	if _flat_dist(target) < 0.6 or nav.is_navigation_finished():
		move_with(Vector3.ZERO, delta)
		return true
	var next := nav.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	if d.length() > 0.01:
		d = d.normalized()
	move_with((d + _separation() * 0.6).limit_length(1.0) * spd, delta)
	return false


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.is_dead:
			continue
		var d: Vector3 = global_position - e.global_position
		d.y = 0.0
		var l := d.length()
		if l < 1.4 and l > 0.001:
			push += d / l * (1.4 - l)
	return push


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _yaw_to(p: Vector3) -> float:
	var to := p - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return aim_yaw
	return atan2(-to.x, -to.z)


func _turn_to(target_yaw: float, delta: float, rate: float) -> void:
	aim_yaw = wrapf(aim_yaw + clampf(wrapf(target_yaw - aim_yaw, -PI, PI), -rate * delta, rate * delta), -PI, PI)


func _face_velocity(delta: float, slow: bool = false) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() > 0.3:
		_turn_to(atan2(-hv.x, -hv.z), delta, 3.0 if slow else 6.0)


func _release_cover() -> void:
	if cover != null:
		if cover.taken == self:
			cover.taken = null
		cover = null
