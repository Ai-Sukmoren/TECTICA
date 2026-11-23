extends Node
## Training: a guided run through the controls on THE RANGE (training_level.gd).
## One step at a time; each waits until the operator has done it, then the next
## one starts. Range targets are enemies that stand still (enemy.gd `dummy`);
## the kill house at the end holds real hostiles. Going down puts the operator
## back at the last station reached instead of ending the run.

const Sfx = preload("res://scripts/fx/sfx.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Campaign = preload("res://scripts/modes/campaign.gd")
const Player = preload("res://scripts/characters/player.gd")
const M = preload("res://scripts/core/materials.gd")

const RESPAWN_DELAY := 3.0
const LOOK_TURN := 2.4          # radians of looking around the first step asks for
const SPRINT_TIME := 1.0        # seconds of sprinting the sprint step asks for
const MARKER_RADIUS := 1.8
const GRENADE_FALLBACK := 3.5   # a throw that misses still passes the grenade step after this long
const REWARD := 250             # credits, the first time the course is finished

## What each step asks. `how` names actions in braces ({sprint}), shown as that
## action's current key; `pad` is the same hint for a gamepad.
const STEPS := [
	{"id": "look", "text": "LOOK AROUND", "how": "MOVE THE MOUSE", "pad": "RIGHT STICK"},
	{"id": "walk", "text": "WALK TO THE MARKER", "how": "{move_forward} {move_left} {move_back} {move_right} TO MOVE", "pad": "LEFT STICK TO MOVE"},
	{"id": "sprint", "text": "SPRINT TO THE NEXT MARKER", "how": "HOLD {sprint} WHILE MOVING", "pad": "CLICK L3 WHILE MOVING"},
	{"id": "vault", "text": "VAULT OVER THE WALL", "how": "{vault} AT THE WALL", "pad": "A AT THE WALL"},
	{"id": "crouch", "text": "CROUCH", "how": "{crouch} TO CROUCH  ·  PRESS AGAIN TO STAND", "pad": "B TO CROUCH"},
	{"id": "slide", "text": "SLIDE", "how": "SPRINT, THEN {crouch}", "pad": "SPRINT (L3), THEN B"},
	{"id": "range", "text": "GO TO THE FIRING LINE", "how": "THE MARKER ON THE RADAR SHOWS THE WAY", "pad": "THE MARKER ON THE RADAR SHOWS THE WAY"},
	{"id": "fire", "text": "SHOOT THE NEAR TARGET", "how": "{fire} TO FIRE", "pad": "RT TO FIRE"},
	{"id": "ads", "text": "AIM DOWN SIGHTS: HIT THE FAR TARGETS", "how": "HOLD {aim} TO AIM  ·  {fire} TO FIRE", "pad": "HOLD LT TO AIM  ·  RT TO FIRE"},
	{"id": "reload", "text": "RELOAD", "how": "{reload} TO RELOAD", "pad": "X TO RELOAD"},
	{"id": "peek", "text": "PEEK LEFT AND RIGHT", "how": "{peek_left} / {peek_right} TO LEAN OUT OF COVER", "pad": "LB / RB TO LEAN OUT OF COVER"},
	{"id": "switch", "text": "SWITCH WEAPONS", "how": "{weapon_1} {weapon_2} {weapon_3} {weapon_4}  OR  {switch_weapon} / MOUSE WHEEL", "pad": "Y TO SWITCH WEAPONS"},
	{"id": "grenade", "text": "THROW A GRENADE BEHIND THE SANDBAGS", "how": "AIM AT THE SANDBAGS  ·  {grenade} TO THROW", "pad": "AIM AT THE SANDBAGS  ·  D-PAD DOWN"},
	{"id": "kick", "text": "DROPKICK", "how": "SPRINT, THEN {kick}", "pad": "SPRINT (L3), THEN D-PAD RIGHT"},
	{"id": "bullet", "text": "BULLET TIME: VAULT THE WALL AND AIM", "how": "{vault} AT THE WALL  ·  HOLD {aim} MID-VAULT  ·  KILLS REFILL FOCUS", "pad": "A AT THE WALL  ·  HOLD LT MID-VAULT"},
	{"id": "live", "text": "LIVE FIRE: CLEAR THE KILL HOUSE", "how": "THESE ONES SHOOT BACK  ·  USE COVER, PEEK AND RELOAD", "pad": "THESE ONES SHOOT BACK  ·  USE COVER, PEEK AND RELOAD"},
]

var main
var level
var step := 0
var finished := false
## Seconds until the operator is back up (< 0: not down).
var respawn_t := -1.0

var _t := 0.0                 # time in the current step
var _turned := 0.0
var _last_yaw := 0.0
var _sprint_t := 0.0
var _peeked := [false, false]
var _start_weapon := 0
var _start_grenades := 0
var _thrown_t := -1.0
var _bullet_seen := false
var _checkpoint := Vector3.ZERO
var _checkpoint_yaw := 0.0
var _near: Node
var _far: Array = []
var _grenade: Node
var _hostiles: Array = []
var _ring: MeshInstance3D


func setup(p_main) -> void:
	main = p_main
	level = main.level
	_checkpoint = level.player_spawn
	_checkpoint_yaw = level.player_yaw
	_near = _target(level.near_target)
	for t in level.far_targets:
		_far.append(_target(t))
	_grenade = _target(level.grenade_target)
	_target(level.bullet_target)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.15
	torus.outer_radius = 1.35
	torus.rings = 48
	_ring.mesh = torus
	_ring.material_override = M.emissive("training_marker", Color(1.0, 0.78, 0.25), 2.5)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	main.add_child(_ring)


func _target(data: Dictionary) -> Node:
	var d := data.duplicate()
	d["dummy"] = true
	return main.spawn_enemy(d)


func current() -> Dictionary:
	return STEPS[step] if step < STEPS.size() else {}


func _id() -> String:
	return String(current().get("id", ""))


## The step's instruction, with a count where there is one.
func objective_text() -> String:
	if finished:
		return "TRAINING COMPLETE"
	var t := String(current().text)
	match _id():
		"ads":
			t += "   %d LEFT" % _alive(_far)
		"live":
			t += "   %d LEFT" % _alive(_hostiles)
	return t


## How to do it, with the operator's own keys (or the gamepad's).
func how_text() -> String:
	if finished:
		return ""
	var s := current()
	var how := String(s.pad if main.player.using_pad else s.how)
	if s.id == "vault" and Settings.v.auto_vault:
		how += ", OR SPRINT INTO IT"
	if main.player.using_pad:
		return how
	for b in Settings.Controls.BINDABLE:
		var tag := "{%s}" % b[0]
		if how.contains(tag):
			how = how.replace(tag, "[%s]" % Settings.Controls.short(String(b[0])))
	return how


## Where the waypoint points (null: nowhere in particular).
func objective_pos():
	if finished:
		return null
	match _id():
		"walk":
			return level.walk_marker
		"sprint":
			return level.sprint_marker
		"vault":
			return level.past_vault
		"range":
			return level.firing_line
		"fire":
			return _pos_of(_near)
		"grenade":
			return _pos_of(_grenade)
		"bullet":
			return level.bullet_target.pos
		"live":
			if main.player.global_position.z > level.house_door.z - 1.5:
				return level.house_door
	return null


func can_interact() -> bool:
	return false


func _pos_of(n) -> Variant:
	return n.global_position if is_instance_valid(n) and not n.is_dead else null


func _alive(list: Array) -> int:
	var n := 0
	for e in list:
		if is_instance_valid(e) and not e.is_dead:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	_update_ring()
	if finished or main.game_over or not main.get("_deployed"):
		return
	var p: Player = main.player
	if p.is_dead:
		if respawn_t >= 0.0:
			respawn_t -= delta
			if respawn_t < 0.0:
				main.respawn_local(_checkpoint, _checkpoint_yaw)
		return
	_t += delta
	if _done(p, delta):
		_advance(p)


## True once the operator has done what the current step asks.
func _done(p: Player, delta: float) -> bool:
	match _id():
		"look":
			_turned += absf(wrapf(p.aim_yaw - _last_yaw, -PI, PI))
			_last_yaw = p.aim_yaw
			return _turned >= LOOK_TURN
		"walk", "range":
			return _reached(p, objective_pos())
		"sprint":
			if p.sprinting:
				_sprint_t += delta
			return _sprint_t >= SPRINT_TIME and _reached(p, level.sprint_marker)
		"vault":
			return p.global_position.z < level.vault_z - 0.6 and p.is_on_floor() and not p.vaulting
		"crouch":
			return p.crouching
		"slide":
			return p.sliding
		"fire":
			return _alive([_near]) == 0
		"ads":
			return _alive(_far) == 0
		"reload":
			return Input.is_action_just_pressed("reload") or p.reload_timer > 0.0
		"peek":
			_peeked[0] = _peeked[0] or Input.is_action_pressed("peek_left")
			_peeked[1] = _peeked[1] or Input.is_action_pressed("peek_right")
			return _peeked[0] and _peeked[1]
		"switch":
			return p.weapon_index != _start_weapon
		"grenade":
			if _thrown_t < 0.0:
				if p.grenades < _start_grenades:
					_thrown_t = 0.0
				elif p.grenades == 0:
					p.grenades = 1   # never stuck without one to throw
					_start_grenades = 1
			else:
				_thrown_t += delta
			return _alive([_grenade]) == 0 or _thrown_t >= GRENADE_FALLBACK
		"kick":
			return p.kicking
		"bullet":
			if not p.bullet_time and p.focus < 1.0 and not _bullet_seen:
				p.focus = 1.0   # a full meter for the lesson
			_bullet_seen = _bullet_seen or p.bullet_time
			return _bullet_seen and not p.bullet_time
		"live":
			return _t > 0.5 and _alive(_hostiles) == 0
	return false


func _reached(p: Player, at) -> bool:
	if at == null:
		return false
	var d := Vector2(p.global_position.x - (at as Vector3).x, p.global_position.z - (at as Vector3).z)
	return d.length() < MARKER_RADIUS


func _advance(p: Player) -> void:
	var done := String(current().text)
	if p.is_on_floor() and not p.vaulting:
		_checkpoint = p.global_position
		_checkpoint_yaw = p.aim_yaw
	step += 1
	_t = 0.0
	if step >= STEPS.size():
		_finish()
		return
	main.hud.add_feed("DONE  ·  " + done, Color(0.5, 1.0, 0.7))
	Sfx.play_ui(main, "ui_tick", 0.0)
	_begin(p)


## Per-step setup when it starts.
func _begin(p: Player) -> void:
	match _id():
		"look":
			_last_yaw = p.aim_yaw
		"switch":
			_start_weapon = p.weapon_index
		"grenade":
			p.grenades = maxi(p.grenades, 1)
			_start_grenades = p.grenades
			_thrown_t = -1.0
		"live":
			for h in level.house_hostiles:
				_hostiles.append(main.spawn_enemy(h))
			main.hud.wave_banner("LIVE FIRE")


func _finish() -> void:
	finished = true
	var first := not Campaign.completed.has("training")
	Campaign.completed["training"] = "DONE"
	Campaign.save_progress()
	main.on_training_complete(REWARD if first else 0)


## Called the moment the operator goes down.
func on_player_died() -> void:
	respawn_t = RESPAWN_DELAY


## First call after deploy: the first step starts.
func start() -> void:
	_begin(main.player)
	main.hud.wave_banner("TRAINING")


func _update_ring() -> void:
	var at = null
	if not finished and main.get("_deployed") and _id() in ["walk", "sprint", "vault", "range"]:
		at = objective_pos()
	_ring.visible = at != null
	if at != null:
		_ring.global_position = (at as Vector3) + Vector3(0, 0.05, 0)
		_ring.rotation.y += 0.02
