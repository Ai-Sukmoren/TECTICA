extends "res://scripts/characters/soldier.gd"
## Hostile AI soldier.
##
## Perception: vision cone + line-of-sight raycasts to chest and head, an
## awareness meter that fills faster at close range and slower vs. a crouched
## target, hearing of gunshots, and squad call-outs to nearby allies.
##
## States: PATROL -> SUSPICIOUS (investigate) -> COMBAT (take cover, hide,
## peek and fire bursts - standing up over low cover, stepping out past a
## wall's corner - reload behind cover, or strafe in the open) ->
## SEARCH (sweep last known position) -> back to PATROL.

const Palettes = preload("res://scripts/core/palettes.gd")
const Stealth = preload("res://scripts/stealth/stealth.gd")

## Awareness ladder (stealth.gd has the shared pieces):
##   PATROL       unaware: walks its route (weapon raised once the area is on alert)
##   SUSPICIOUS   noticed something: stops and stares at it while suspicion builds
##   INVESTIGATE  goes to check a glimpse, a sound or a body
##   ALERTED      knows something is wrong (gunfire, a body, a radio call): moves on it fast
##   SEARCH       hunts around the last known position with the squad, then stands down
##   COMBAT       has the operator: cover, flanks, suppression
## (new states are appended: the numbers travel over the network)
enum State { PATROL, SUSPICIOUS, COMBAT, SEARCH, INVESTIGATE, ALERTED }
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
## where the threat was when this cover was graded; re-graded once it moves this far
var _cover_threat := Vector3.INF
const COVER_REGRADE_MOVE := 5.0
## times this guard moved to a better spot after the threat moved (tests / debug)
var cover_moves := 0
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
## A training target (training.gd): stands where it is put, never perceives, moves or fires.
var dummy := false

# ---- stealth
## what is being checked (a glimpse, a sound's guessed spot, a body, a radio call)
var _stimulus := Vector3.ZERO
var _stim_kind := ""
## a body this guard is walking over to inspect
var _body_target: Node3D = null
var _inspect_t := -1.0
var _body_check := 0.0
## coordinated search: centre, current spot, wait there, seconds left, spots done
var _search_center := Vector3.ZERO
var _search_spot := Vector3.INF
var _search_wait := 0.0
var _search_left := 0.0
var _visited: Array = []
## held by the operator in a takedown: no thinking, no moving
var grabbed := false


func init_enemy(p_player, p_level, data: Dictionary, variant: int) -> void:
	player = p_player
	level = p_level
	home_pos = global_position
	home_yaw = float(data.get("yaw", 0.0))
	patrol = data.get("patrol", [])
	dummy = bool(data.get("dummy", false))
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
	_add_lean_zone()
	max_health = 100.0
	health = max_health
	_scan_t = randf() * 10.0
	nav = NavigationAgent3D.new()
	# over 0.5: path points can sit 0.5 m above the feet (desert navmesh), and a
	# bot right under its first point would never count it as reached
	nav.path_desired_distance = 0.75
	nav.target_desired_distance = 0.5
	nav.radius = 0.45
	nav.height = 1.8
	nav.path_max_distance = 2.0
	add_child(nav)
	add_to_group("enemies")
	if dummy:
		add_name_tag("TARGET")
		if bool(data.get("crouch", false)):
			set_crouch(true)
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
	if is_dead or dummy or grabbed:
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
	if state != State.COMBAT and (_lean_side != 0.0 or _peek_off != Vector3.ZERO):
		_lean_side = 0.0
		_lean(0.0)
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
		State.INVESTIGATE:
			_do_investigate(delta)
		State.ALERTED:
			_do_alerted(delta)
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
		if p.is_dead or p == self or p.team == team:
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
	if not _stealthy():
		_perceive_legacy(delta)
		return
	if sees_player:
		time_since_seen = 0.0
		last_known = player.global_position
		if state == State.COMBAT:
			Stealth.report_contact(last_known)
			return
		awareness = minf(awareness + _detect_gain() * delta, 1.0)
		if awareness >= 1.0:
			callout("THERE HE IS!", Color(1.0, 0.35, 0.3))
			_enter_combat(true)
		elif awareness >= 0.5 and state in [State.PATROL, State.SUSPICIOUS, State.INVESTIGATE]:
			# a proper look: walk over to where he was
			_enter_investigate(player.global_position, "sight")
		elif awareness >= 0.12 and state == State.PATROL:
			_enter_suspicious(player.global_position, "sight")
	elif state != State.COMBAT:
		# suspicion fades, slower once the area is on alert
		awareness = maxf(awareness - (0.05 if Stealth.alert >= 1.0 else 0.09) * delta, 0.0)
	_body_check -= delta
	if _body_check <= 0.0:
		_body_check = 0.5
		_look_for_bodies()


## How fast suspicion builds while this guard can see the operator: closer, in the
## middle of the view, lit up, moving fast and an area on alert all speed it up.
func _detect_gain() -> float:
	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var gain := 1.1 * clampf(1.5 - d / VIEW_DIST, 0.25, 1.5)
	if d > 2.5:
		var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
		gain *= lerpf(1.25, 0.5, clampf(fwd.angle_to(to) / FOV_HALF, 0.0, 1.0))   # corner of the eye is slow
	gain *= Stealth.exposure(level, player)
	if state in [State.SUSPICIOUS, State.INVESTIGATE]:
		gain *= 1.8
	elif state in [State.SEARCH, State.ALERTED]:
		gain *= 2.6
	gain *= 1.0 + 0.3 * Stealth.alert
	if d < 3.0:
		gain *= 4.0   # right in front of him
	return gain


## Team deathmatch bots and other non-stealth guards keep the original quick perception.
func _perceive_legacy(delta: float) -> void:
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


# ================================================================ leaning

## How far a guard leans out round cover (the operator's own peek is about the same).
const LEAN_DIST := 0.45
## which way he leans on this peek: 1 right, -1 left, 0 stand up instead
var _lean_side := 0.0
var _lean_zone: Area3D
var _lean_shape: CapsuleShape3D


## Which way to lean out to see `threat`: a wall's corner says (its peek side);
## round a tree or a rock, whichever side has a clear line to the threat
## (0: nothing clear, so stand up over the cover instead).
func _choose_lean_side(threat: Vector3) -> float:
	var yaw := _yaw_to(threat)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	if cover != null and cover.get("peek", Vector3.ZERO) != Vector3.ZERO:
		var pk: Vector3 = cover.peek
		return 1.0 if pk.dot(right) >= 0.0 else -1.0
	var space := get_world_3d().direct_space_state
	var sides := [1.0, -1.0] if randf() < 0.5 else [-1.0, 1.0]
	for side in sides:
		var eye: Vector3 = global_position + right * float(side) * LEAN_DIST + Vector3(0, STAND_HEIGHT - 0.2, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, threat + Vector3(0, 1.2, 0), Layers.WORLD)
		if space.intersect_ray(q).is_empty():
			return side
	return 0.0


## Leans toward `side` (0 = back upright). The eye, the muzzle (soldier.gd uses
## _peek_off) and the bullet zone go with the upper body; a wall beside him stops it.
func _lean(side: float) -> void:
	rig.lean_target = side
	var right := Vector3(cos(aim_yaw), 0, -sin(aim_yaw))
	var want := right * rig.lean_amt * LEAN_DIST
	if want.length() > 0.02:
		var base := global_position + Vector3(0, chest_height(), 0)
		var q := PhysicsRayQueryParameters3D.create(base, base + want * 1.4, Layers.WORLD, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var room := maxf(base.distance_to(hit.position) / 1.4 - 0.08, 0.0)
			want = want.normalized() * minf(room, want.length())
	_peek_off = want if want.length() > 0.02 else Vector3.ZERO
	if _lean_zone != null:
		var out := _peek_off != Vector3.ZERO
		_lean_zone.collision_layer = Layers.HITZONE if out else 0
		if out:
			_lean_shape.height = head_height() - chest_height() + 0.75
			_lean_zone.position = _peek_off.rotated(Vector3.UP, -rotation.y) + Vector3(0, (chest_height() - 0.25 + head_height() + 0.12) * 0.5, 0)


## Bullet-only zone for the leaned-out upper body: the movement capsule stays
## behind the cover, so without it a leaning guard could shoot but not be shot.
func _add_lean_zone() -> void:
	_lean_zone = Area3D.new()
	_lean_zone.name = "HitZone"
	_lean_zone.collision_layer = 0
	_lean_zone.collision_mask = 0
	_lean_zone.monitoring = false
	var cs := CollisionShape3D.new()
	_lean_shape = CapsuleShape3D.new()
	_lean_shape.radius = 0.28
	_lean_shape.height = 1.0
	cs.shape = _lean_shape
	_lean_zone.add_child(cs)
	add_child(_lean_zone)


## weapon.gd asks where a shot along origin + dir hit this guard: the leaned-out
## chest and head (when leaning), or his body as usual; {} = it passed by.
func hit_part(origin: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var end := origin + dir * reach
	if _peek_off != Vector3.ZERO:
		var a := global_position + _peek_off + Vector3(0, chest_height() - 0.25, 0)
		var b := global_position + _peek_off + Vector3(0, head_height() + 0.12, 0)
		var pts := Geometry3D.get_closest_points_between_segments(origin, end, a, b)
		if (pts[0] as Vector3).distance_to(pts[1]) < 0.3:
			return {"pos": pts[0]}
	var c0 := global_position   # from the feet: leg hits count
	var c1 := global_position + Vector3(0, head_height() + 0.12, 0)
	var bp := Geometry3D.get_closest_points_between_segments(origin, end, c0, c1)
	if (bp[0] as Vector3).distance_to(bp[1]) < 0.36:
		return {"pos": Vector3.INF}   # the body itself: keep the hit as traced
	return {}


## Moving quietly enough to get right behind a guard unnoticed.
func _sneaking(p) -> bool:
	return p.get("crouching") == true or p.get("walking") == true 			or Vector2(p.velocity.x, p.velocity.z).length() < 2.6


## Stealth rules apply to campaign / training guards, not to deathmatch bots.
func _stealthy() -> bool:
	return not has_meta("tdm_bot")


## Aware of the operator: fighting, or has had a good look. Takedowns need a guard
## who isn't (stealth.gd can_takedown).
func is_aware_of(_p = null) -> bool:
	return state == State.COMBAT or (sees_player and awareness >= 0.5) or grabbed


## True when `pos` is in this guard's view: in range (darkness shortens it), inside
## the view cone (or right next to him) and with nothing solid in between.
func can_see_point(pos: Vector3, max_dist: float = VIEW_DIST) -> bool:
	if is_dead or blind_t > 0.0:
		return false
	var to := pos - global_position
	to.y = 0.0
	var d := to.length()
	var light := Stealth.light_at(level, pos)
	if d > max_dist * lerpf(0.35, 1.0, light):
		return false
	if d > 2.5:
		var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
		if fwd.angle_to(to) > FOV_HALF * (1.5 if state == State.COMBAT else 1.0):
			return false
	var eye := global_position + _peek_off + Vector3(0, head_height() - 0.05, 0)
	var q := PhysicsRayQueryParameters3D.create(eye, pos, Layers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Something happened in plain view (stealth.gd notify_witnesses).
func witness(pos: Vector3, what: String, actor: Node) -> void:
	if is_dead or not _stealthy() or state == State.COMBAT:
		return
	if what == "takedown":
		Stealth.raise_alert(2.0, 1.4)
		if actor is Node3D and _can_see(actor):
			player = actor
			last_known = (actor as Node3D).global_position
			callout("TAKEDOWN! OPEN FIRE!", Color(1.0, 0.35, 0.3))
			_enter_combat(true)
		else:
			_enter_alerted(pos, "HEY! WHAT WAS THAT?", true)


## Fallen guards in view that nobody has found yet: go and look.
func _look_for_bodies() -> void:
	if state == State.COMBAT or _body_target != null or level == null:
		return
	for b in Stealth.open_bodies(get_tree(), level):
		if b == self:
			continue
		if can_see_point((b as Node3D).global_position + Vector3(0, 0.35, 0), 20.0):
			_body_target = b
			_inspect_t = -1.0
			awareness = maxf(awareness, 0.4)
			callout("WHAT THE...?", Color(1.0, 0.85, 0.4))
			_enter_investigate((b as Node3D).global_position, "body")
			return


func _can_see(p) -> bool:
	if p == null or p.is_dead:
		return false
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > VIEW_DIST * vision_scale(p):
		return false
	# right next to him he senses anyone behind him, unless they sneak (crouched,
	# slow-walking or barely moving): that is how takedowns get close
	if d > 2.5 or (_stealthy() and state != State.COMBAT and _sneaking(p)):
		var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
		var fov := FOV_HALF * (1.5 if state == State.COMBAT else 1.0)
		if fwd.angle_to(to) > fov:
			return false
	var eye := global_position + _peek_off + Vector3(0, head_height() - 0.05, 0)
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


## A sound reached this guard (stealth.gd emit_sound; walls already shortened `radius`).
## He hears roughly where it came from, worse the further away, and reacts by how
## alarming it is: a footstep makes him look, a suppressed shot sends him to check,
## gunfire puts the squad on alert. Only gunfire right next to him starts a fight.
func hear_sound(pos: Vector3, radius: float, kind: String, source: Node = null) -> void:
	if is_dead or dummy or grabbed:
		return
	if not _stealthy():
		if kind == "footstep":
			_hear_footstep_legacy(pos, radius)
		else:
			_hear_noise_legacy(pos, radius)
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	var far := clampf(d / maxf(radius, 0.1), 0.0, 1.0)
	var err := lerpf(0.6, 4.5, far)
	var guess := pos + Vector3(randf_range(-err, err), 0, randf_range(-err, err))
	var alarm: int = Stealth.SOUND_ALARM.get(kind, 1)
	if state == State.COMBAT:
		if not sees_player:
			last_known = guess
		return
	if alarm >= 2:
		Stealth.raise_alert(1.5, 0.6)
		if d < 7.0 and source is Node3D and source.is_in_group("player"):
			player = source
			last_known = guess
			callout("CONTACT!", Color(1.0, 0.35, 0.3))
			_enter_combat(true)
		else:
			_enter_alerted(guess, "GUNSHOTS!" if kind == "gunshot" else "WHAT WAS THAT?!", true)
	elif alarm == 1:
		Stealth.raise_alert(0.8)
		if state in [State.SEARCH, State.ALERTED]:
			_stimulus = guess
			_search_center = guess
		else:
			awareness = maxf(awareness, 0.45)
			_enter_investigate(guess, kind)
	else:
		if state == State.PATROL:
			awareness = maxf(awareness, 0.3 if kind == "distraction" else 0.2)
			_enter_suspicious(guess, kind)
		elif state in [State.SUSPICIOUS, State.INVESTIGATE]:
			_stimulus = guess
			if state == State.INVESTIGATE:
				_search_wait = 0.0
		elif far < 0.6:
			_search_center = guess   # searching: close noises pull the search over


func hear_noise(pos: Vector3, radius: float) -> void:
	hear_sound(pos, radius, "gunshot", null)


func _hear_noise_legacy(pos: Vector3, radius: float) -> void:
	if is_dead or dummy:
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
	hear_sound(pos, radius, "footstep", null)


func _hear_footstep_legacy(pos: Vector3, radius: float) -> void:
	if is_dead or state == State.COMBAT:
		return
	if global_position.distance_to(pos) < radius:
		awareness = maxf(awareness, 0.45)
		_enter_suspicious(pos)


func alert(pos: Vector3) -> void:
	if is_dead or dummy or state == State.COMBAT:
		return
	last_known = pos
	_enter_combat(false)


func apply_damage(amount: float, hit_pos: Vector3, dir: Vector3, attacker: Node) -> bool:
	if grabbed:
		return false   # the operator's own body shields him mid-takedown
	var headshot := super.apply_damage(amount, hit_pos, dir, attacker)
	if is_dead and _stealthy():
		Stealth.raise_alert(1.0)
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


## Held from behind by the operator (takedown): frozen until knocked out or killed.
func grab() -> void:
	grabbed = true
	aiming = false
	sprinting = false
	_burst_left = 0
	_end_flank()
	_release_cover()
	Stealth.release_claim(self)


## Non-lethal takedown: down for good, no blood. Guards who find him know he was
## jumped (a lower alarm than a corpse).
func knock_out(dir: Vector3) -> void:
	set_meta("knocked_out", true)
	grabbed = false
	die(dir)


func die(dir: Vector3) -> void:
	grabbed = false
	Stealth.release_claim(self)
	_end_flank()
	if torch:
		torch.visible = false
		torch.queue_free()
		torch = null
	_release_cover()
	super.die(dir)


# ================================================================ state entry

func _enter_combat(call_out: bool) -> void:
	_body_target = null
	Stealth.release_claim(self)
	if _stealthy():
		Stealth.raise_alert(2.0, 1.0)
		Stealth.report_contact(last_known)
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


func _enter_suspicious(pos: Vector3, kind: String = "sight") -> void:
	if state == State.COMBAT:
		return
	state = State.SUSPICIOUS
	last_known = pos
	_stimulus = pos
	_stim_kind = kind
	_investigate_delay = randf_range(0.9, 1.6) if _stealthy() else randf_range(0.6, 1.2)
	_search_timer = 0.0
	if _stealthy():
		callout("HUH?", Color(1.0, 1.0, 1.0, 0.9))


## Goes to check `pos` (a glimpse, a sound, a body): weapon up once the area is on alert.
func _enter_investigate(pos: Vector3, kind: String) -> void:
	if state == State.COMBAT:
		return
	if state != State.INVESTIGATE:
		callout("I'LL CHECK IT OUT", Color(1.0, 0.85, 0.4))
	state = State.INVESTIGATE
	_stimulus = pos
	_stim_kind = kind
	last_known = pos
	_search_wait = 0.0
	_search_timer = 0.0


## Knows something is wrong: moves on `pos` fast; tells the squad if `radio`.
func _enter_alerted(pos: Vector3, shout: String, radio: bool) -> void:
	if state == State.COMBAT:
		return
	var was := state
	state = State.ALERTED
	_stimulus = pos
	last_known = pos
	awareness = maxf(awareness, 0.55)
	if was != State.ALERTED:
		alert_flash = 1.0
		callout(shout, Color(1.0, 0.6, 0.25))
		if radio:
			_radio(pos, 22.0)


## Calls it in: guards within `reach` who aren't fighting move on `pos` too.
func _radio(pos: Vector3, reach: float) -> void:
	Stealth.report_contact(pos)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e.is_dead or not e.has_method("on_radio"):
			continue
		if (e as Node3D).global_position.distance_to(global_position) < reach:
			e.on_radio(pos)


## A squadmate called something in.
func on_radio(pos: Vector3) -> void:
	if is_dead or dummy or grabbed or not _stealthy() or state in [State.COMBAT, State.ALERTED]:
		return
	var err := 2.5
	_enter_alerted(pos + Vector3(randf_range(-err, err), 0, randf_range(-err, err)), "COPY, MOVING!", false)


func _enter_search() -> void:
	state = State.SEARCH
	_release_cover()
	_search_timer = 0.0
	set_crouch(false)
	_body_target = null
	if _stealthy():
		# the whole squad works the last known position; elevated alert searches longer
		var shared := Stealth.last_known
		_search_center = shared if shared != Vector3.INF and Stealth.now() - Stealth.last_known_t < 30.0 \
				and shared.distance_to(global_position) < 30.0 else last_known
		_search_left = 16.0 + 6.0 * Stealth.alert + randf_range(0.0, 4.0)
		_search_spot = Vector3.INF
		_search_wait = 0.0
		_visited.clear()


# ================================================================ behaviours

func _do_patrol(delta: float) -> void:
	aiming = _stealthy() and Stealth.alert >= 1.0   # on alert: weapons up on the rounds
	sprinting = false
	set_crouch(false)
	if has_meta("tdm_bot"):
		_tdm_roam(delta)
		return
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


# ================================================================ team deathmatch

var _hunt_goal := Vector3.INF
var _hunt_t := 0.0


## A deathmatch bot with nobody in sight goes looking: usually toward where
## the other team is (a little off, so it does not beeline), sometimes along a
## different lane through the map; a bot on a human's team often moves up with
## that player instead. Combat, cover and flanking take over once it sees someone.
func _tdm_roam(delta: float) -> void:
	_hunt_t -= delta
	if _hunt_goal == Vector3.INF or _hunt_t <= 0.0 or global_position.distance_to(_hunt_goal) < 2.5:
		_hunt_goal = _pick_hunt_goal()
		_hunt_t = randf_range(8.0, 14.0)
	var far := global_position.distance_to(_hunt_goal) > 12.0
	sprinting = far
	if _nav_to(_hunt_goal, RUN_SPEED if far else RUN_SPEED * 0.6, delta):
		_hunt_goal = Vector3.INF
	else:
		_face_velocity(delta)


func _pick_hunt_goal() -> Vector3:
	var foes: Array = []
	var lead = null
	for p in get_tree().get_nodes_in_group("player"):
		if p == self or p.is_dead:
			continue
		if p.team != team:
			foes.append(p)
		elif not p.has_meta("tdm_bot"):
			lead = p   # a human on this bot's team
	var r := randf()
	var goal := global_position
	if lead != null and r < 0.35:
		var a := randf() * TAU
		goal = lead.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.5, 7.0)
	elif not foes.is_empty() and r < 0.85:
		var near = foes[0]
		for f in foes:
			if global_position.distance_to(f.global_position) < global_position.distance_to(near.global_position):
				near = f
		var a2 := randf() * TAU
		goal = near.global_position + Vector3(cos(a2), 0, sin(a2)) * randf_range(2.0, 7.0)
	else:
		var main := get_tree().current_scene
		var lanes: Array = main.level.get("pvp_spawns") if main != null and main.get("level") != null else []
		if not lanes.is_empty():
			goal = lanes[randi() % lanes.size()]
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return goal   # navigation not ready on the first frame: path to it next time
	return NavigationServer3D.map_get_closest_point(map, goal)


func _do_suspicious(delta: float) -> void:
	if _stealthy():
		_do_suspicious_stealth(delta)
		return
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


## Stops and stares at what caught his eye or ear; then goes to check it, or,
## if it was only a glimpse that faded, shrugs it off.
func _do_suspicious_stealth(delta: float) -> void:
	aiming = Stealth.alert >= 1.0
	sprinting = false
	move_with(Vector3.ZERO, delta)
	_turn_to(_yaw_to(_stimulus), delta, 3.5)
	_investigate_delay -= delta
	if _investigate_delay > 0.0:
		return
	if _stim_kind == "sight" and awareness < 0.12:
		state = State.PATROL
		callout("...NOTHING.", Color(1.0, 1.0, 1.0, 0.8))
		return
	_enter_investigate(_stimulus, _stim_kind)


## Walks to the spot and looks around it; a body found on the way is inspected
## and called in. Nothing there: back to the rounds.
func _do_investigate(delta: float) -> void:
	sprinting = false
	if is_instance_valid(_body_target):
		_do_inspect_body(delta)
		return
	_body_target = null
	aiming = Stealth.alert >= 1.0 or awareness > 0.4
	if _search_wait <= 0.0:
		if _nav_to(_stimulus, WALK_SPEED * 1.25, delta):
			_search_wait = randf_range(3.0, 4.5)
		else:
			_face_velocity(delta, true)
		return
	_search_wait -= delta
	move_with(Vector3.ZERO, delta)
	_scan_t += delta
	_turn_to(aim_yaw + 2.0 * delta * signf(sin(_scan_t * 0.8)), delta, 3.0)
	if _search_wait <= 0.0:
		state = State.PATROL
		awareness = minf(awareness, 0.15)
		callout("NOTHING HERE.", Color(1.0, 1.0, 1.0, 0.8))


## Kneels at a body, then calls it in: the squad moves on the spot and searches.
func _do_inspect_body(delta: float) -> void:
	aiming = true
	var bp := _body_target.global_position
	if _inspect_t < 0.0:
		if _flat_dist(bp) > 1.4:
			_nav_to(bp, RUN_SPEED * 0.6, delta)
			_face_velocity(delta, true)
			return
		_inspect_t = 1.8
		set_crouch(true)
	move_with(Vector3.ZERO, delta)
	_turn_to(_yaw_to(bp), delta, 5.0)
	_inspect_t -= delta
	if _inspect_t > 0.0:
		return
	set_crouch(false)
	var body := _body_target
	_body_target = null
	_inspect_t = -1.0
	var ko := Stealth.is_knocked_out(body)
	Stealth.report_body(body)
	callout("HE'S OUT COLD! INTRUDER!" if ko else "MAN DOWN! WE HAVE AN INTRUDER!", Color(1.0, 0.5, 0.25))
	last_known = bp
	Stealth.report_contact(bp)
	_radio(bp, 30.0)
	_enter_search()
	_search_center = bp


## Moves on the reported spot fast, weapon up; once there, searches it.
func _do_alerted(delta: float) -> void:
	aiming = true
	sprinting = false
	if _nav_to(_stimulus, RUN_SPEED * 0.75, delta) or _flat_dist(_stimulus) < 3.0:
		_enter_search()
		_search_center = _stimulus
	else:
		_face_velocity(delta, true)


## Coordinated search: each searcher claims a different hiding spot or corner
## near the centre (stealth.gd search_point), checks it, then the next. When the
## time runs out without contact he goes back to his rounds, still on alert.
func _do_search_stealth(delta: float) -> void:
	aiming = true
	sprinting = false
	_search_left -= delta
	if _search_left <= 0.0:
		Stealth.release_claim(self)
		state = State.PATROL
		awareness = 0.15
		callout("ALL CLEAR... STAY SHARP.", Color(1.0, 1.0, 1.0, 0.8))
		return
	if _search_spot == Vector3.INF:
		_search_spot = Stealth.search_point(level, _search_center, self, _visited)
		_search_wait = 0.0
	if _search_wait <= 0.0:
		if _nav_to(_search_spot, 2.6, delta) or _flat_dist(_search_spot) < 1.2:
			_search_wait = randf_range(1.8, 3.2)
		else:
			_face_velocity(delta, true)
		return
	_search_wait -= delta
	move_with(Vector3.ZERO, delta)
	_scan_t += delta
	_turn_to(aim_yaw + 2.4 * delta * signf(sin(_scan_t * 0.7)), delta, 3.0)
	if _search_wait <= 0.0:
		_visited.append(_search_spot)
		_search_spot = Vector3.INF


func _do_search(delta: float) -> void:
	if _stealthy():
		_do_search_stealth(delta)
		return
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
		if _stealthy():
			callout("LOST HIM! SPREAD OUT!", Color(1.0, 0.7, 0.3))
			Stealth.report_contact(last_known)
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
		if cover != null and not _wants_cover():
			_release_cover()
			phase = Phase.OPEN   # back on the attack
		elif _wants_cover() and (cover == null or not level.is_cover_good(cover, threat)):
			_release_cover()
			cover = level.find_cover(self, threat)
			_cover_threat = threat
			phase = Phase.MOVING if cover != null else Phase.OPEN
		elif cover != null and phase != Phase.FLANK and threat.distance_to(_cover_threat) > COVER_REGRADE_MOVE:
			# the threat has moved: grade the area again; keep this spot unless another is clearly better
			_cover_threat = threat
			var mine = cover
			var better = level.find_cover(self, threat, false, mine)
			if better != null and better != mine:
				_release_cover()
				better.taken = self
				cover = better
				phase = Phase.MOVING
				cover_moves += 1
			elif better == null:
				mine.taken = self
		elif cover != null and phase == Phase.OPEN:
			phase = Phase.MOVING
	if cover == null and phase in [Phase.MOVING, Phase.HIDDEN, Phase.PEEKING]:
		phase = Phase.OPEN   # no cover to go to (a deathmatch bot not under fire, or it was let go): fight in the open

	_turn_to(_yaw_to(threat), delta, 7.0)
	if phase != Phase.PEEKING:
		_lean(0.0)

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
			_hold(_cover_spot(false), delta)
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
				_lean_side = _choose_lean_side(threat)
		Phase.PEEKING:
			if _lean_side != 0.0:
				# at a wall's corner: step out to it and lean round; at a tree or a rock: lean out in place
				_hold(_cover_spot(true), delta)
				_lean(_lean_side)
			else:
				_hold(_cover_spot(true), delta)   # low cover: stand up over it
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
	# either side, random first: when water or a wall closes one side, go round the other
	var side := to.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	var reach := randf_range(9.0, 12.0)
	var p := Vector3.INF
	for s: float in [1.0, -1.0]:
		var q: Vector3 = threat + side * s * reach + to.normalized() * 2.0
		q = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, q)
		if q.distance_to(threat) >= 6.0:
			p = q
			break
	if p == Vector3.INF:
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


## Ends this guard's flank everywhere: the squad slot and the FLANK phase together
## (a flashbang used to free the slot but leave the guard flanking, so a second
## squadmate could start one too).
func _end_flank() -> void:
	if _flanker == self:
		_flanker = null
	if phase == Phase.FLANK:
		phase = Phase.MOVING
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


## Whether to fight from cover now. Mission guards always do. Deathmatch bots duck into cover when they are hit or
## low on ammo and come back out to fight once it has gone quiet (a match of bots that only hide never ends).
func _wants_cover() -> bool:
	if not has_meta("tdm_bot"):
		return true
	var w := current_weapon()
	return since_damage < 3.0 or reload_timer > 0.0 or w.ammo < int(w.stats.mag) * 0.3


## Where to stand in cover: its spot, or peeking, the sidestep past a wall's corner (low cover: the same spot, standing).
## Where the bot is when its cover was let go (flashed, falling back) before the phase moved on.
func _cover_spot(peeking: bool) -> Vector3:
	if cover == null:
		return global_position
	return cover.pos + (cover.get("peek", Vector3.ZERO) as Vector3 if peeking else Vector3.ZERO)


## Stands on `spot` (a cover spot, or the sidestep out of it), stepping there when off it.
func _hold(spot: Vector3, delta: float) -> void:
	var d := Vector3(spot.x - global_position.x, 0.0, spot.z - global_position.z)
	if d.length() > 0.12:
		move_with(d.normalized() * minf(RUN_SPEED * 0.6, d.length() * 8.0), delta)
	else:
		move_with(Vector3.ZERO, delta)


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
