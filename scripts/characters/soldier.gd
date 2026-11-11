extends CharacterBody3D
## Shared soldier body used by the player and AI: physics movement, health,
## hit zones, weapon inventory, reload / switch timing and death.

signal fired(soldier: Node, weapon: Node, result: Dictionary)
signal damaged(soldier: Node, amount: float, attacker: Node)
signal died(soldier: Node)

const SoldierRig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const FX = preload("res://scripts/fx/fx.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Layers = preload("res://scripts/core/layers.gd")
const Grenade = preload("res://scripts/weapons/grenade.gd")
const Net = preload("res://scripts/net/net.gd")

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.15
const SWITCH_TIME := 0.7
const GRAVITY := 18.0

var max_health := 100.0
var health := 100.0
var team := 0
var is_dead := false
var crouching := false
var aiming := false
var sprinting := false
## Upward speed to apply on the next grounded move (set by the jump input).
var jump_request := 0.0
var air_time := 0.0
var aim_yaw := 0.0
var aim_point := Vector3.ZERO
var accel := 16.0
var decel := 22.0

var rig: SoldierRig
var weapons: Array = []
var weapon_index := 0
var reload_timer := 0.0
var reload_duration := 1.0
var reload_tactical := false
var switch_timer := 0.0
var _switch_target := 0
var _switch_swapped := true
var _shape: CapsuleShape3D
var _peek_off := Vector3.ZERO
var grenades := 0
var throwing := 0.0
var since_damage := 99.0
var _throw_target := Vector3.ZERO
var _col: CollisionShape3D

# ---- multiplayer
## Peer that simulates this body (its player, or the host for AI).
var net_owner := 1
## Driven by network snapshots instead of input / AI.
var puppet := false
var display_name := ""
var last_attacker_name := ""
var last_headshot := false
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_yaw := 0.0
var _net_age := 0.0
var _net_has := false


func setup_soldier(palette: Dictionary, weapon_ids: Array, layer: int, mask: int, yaw: float = 0.0) -> void:
	collision_layer = layer
	collision_mask = mask
	floor_snap_length = 0.3
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.32
	_shape.height = STAND_HEIGHT
	_col = CollisionShape3D.new()
	_col.shape = _shape
	_col.position.y = STAND_HEIGHT * 0.5
	add_child(_col)
	rig = SoldierRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build(palette)
	rig.throw_release.connect(_on_throw_release)
	rig.footstep.connect(_on_footstep)
	for id in weapon_ids:
		weapons.append(_make_weapon(id))
	aim_yaw = yaw
	rig.snap_yaw(yaw)
	if not weapons.is_empty():
		_equip_current()


func _make_weapon(spec) -> Weapon:
	var w := Weapon.new()
	if spec is Array:
		w.setup(String(spec[0]), spec[1])
		if spec.size() > 2:
			w.apply_skin(String(spec[2]))   # [id, attachments, skin]
	else:
		w.setup(String(spec))
	return w


## Replaces the whole inventory (used when the loadout changes).
func set_loadout(specs: Array) -> void:
	for w in weapons:
		if is_instance_valid(w):
			w.queue_free()
	weapons.clear()
	for spec in specs:
		weapons.append(_make_weapon(spec))
	weapon_index = 0
	reload_timer = 0.0
	switch_timer = 0.0
	_equip_current()


func current_weapon() -> Weapon:
	return weapons[weapon_index]


func _equip_current() -> void:
	var others: Array = []
	for i in weapons.size():
		if i != weapon_index:
			others.append(weapons[i])
	rig.set_weapon(current_weapon(), others)


# ------------------------------------------------------------------ movement

func move_with(desired: Vector3, delta: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	var rate := accel if desired.length() > hv.length() else decel
	if not is_on_floor():
		rate *= 0.3   # limited air control
	hv = hv.move_toward(desired, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		air_time = 0.0
		velocity.y = -0.1
		if jump_request > 0.0:
			velocity.y = jump_request
	else:
		air_time += delta
		velocity.y -= GRAVITY * delta
	jump_request = 0.0
	move_and_slide()


func set_crouch(c: bool) -> void:
	if c == crouching:
		return
	crouching = c
	_shape.height = CROUCH_HEIGHT if c else STAND_HEIGHT
	_col.position.y = _shape.height * 0.5


func chest_height() -> float:
	return lerpf(1.3, 0.82, rig.crouch_amt)


func head_height() -> float:
	return lerpf(1.62, 1.05, rig.crouch_amt)


func peek_offset() -> Vector3:
	return _peek_off


func get_fire_origin() -> Vector3:
	return global_position + _peek_off + Vector3(0, lerpf(1.42, 0.98, rig.crouch_amt), 0)


func _sync_rig() -> void:
	rig.move_velocity = velocity
	rig.aim_yaw = aim_yaw
	rig.crouch_target = 1.0 if crouching else 0.0
	rig.aim_target = 1.0 if (aiming and not sprinting) else 0.0
	rig.sprint_target = 1.0 if sprinting else 0.0
	rig.air_target = 1.0 if (velocity.y > 1.0 or air_time > 0.15) and not is_on_floor() else 0.0
	if not weapons.is_empty():
		rig.ads_speed = float(current_weapon().stats.ads_speed)


# ------------------------------------------------------------------ combat

func can_act() -> bool:
	return not is_dead and reload_timer <= 0.0 and switch_timer <= 0.0 and throwing <= 0.0


func get_spread() -> float:
	var s := current_weapon().stats
	var base := lerpf(float(s.spread_hip), float(s.spread_aim), rig.aim_amt)
	var hv := Vector2(velocity.x, velocity.z).length()
	base += float(s.spread_move) * clampf(hv / 4.5, 0.0, 1.5)
	if crouching:
		base *= 0.7
	return base


func current_spread() -> float:
	return get_spread() + current_weapon().bloom


func try_fire(target: Vector3) -> bool:
	if not can_act() or sprinting:
		return false
	var w := current_weapon()
	if w.ammo <= 0:
		if w.cooldown <= 0.0:
			w.cooldown = 0.3
			Sfx.play(self, "dry", w.muzzle.global_position, -6.0)
			start_reload()
		return false
	if not w.ready_to_fire():
		return false
	var result := w.fire(self, get_fire_origin(), target, get_spread())
	rig.add_recoil(float(w.stats.recoil) * (float(w.stats.recoil_crouch) if crouching else 1.0))
	fired.emit(self, w, result)
	if Net.active and Net.sync:
		Net.sync.send_event(self, "shot", [result.ends])
	return true


## Another peer's shot: tracers, impacts, flash and sound only.
func net_shot(ends: Array) -> void:
	if weapons.is_empty() or is_dead:
		return
	var w := current_weapon()
	w.fire_fx(ends)
	rig.add_recoil(float(w.stats.recoil) * (float(w.stats.recoil_crouch) if crouching else 1.0))


func start_reload() -> void:
	if not can_act():
		return
	var w := current_weapon()
	if w.ammo >= int(w.stats.mag) or w.reserve <= 0:
		return
	reload_tactical = w.ammo > 0
	reload_duration = float(w.stats.reload) if reload_tactical else float(w.stats.reload_empty)
	reload_timer = reload_duration
	rig.play_reload(reload_duration, not reload_tactical)
	if Net.active and Net.sync:
		Net.sync.send_event(self, "reload", [reload_duration, not reload_tactical])


func switch_to(i: int) -> void:
	if i == weapon_index or i < 0 or i >= weapons.size() or not can_act():
		return
	_switch_target = i
	_switch_swapped = false
	switch_timer = SWITCH_TIME
	rig.play_switch(SWITCH_TIME)
	Sfx.play(self, "switch", global_position + Vector3.UP, -10.0)
	if Net.active and Net.sync:
		Net.sync.send_event(self, "switch", [i])


func net_switch(i: int) -> void:
	if i < 0 or i >= weapons.size():
		return
	_switch_target = i
	_switch_swapped = false
	switch_timer = SWITCH_TIME
	rig.play_switch(SWITCH_TIME)
	Sfx.play(self, "switch", global_position + Vector3.UP, -10.0)


func _tick_actions(delta: float) -> void:
	throwing = maxf(throwing - delta, 0.0)
	since_damage += delta
	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0:
			current_weapon().finish_reload(reload_tactical)
	if switch_timer > 0.0:
		switch_timer -= delta
		if not _switch_swapped and switch_timer <= SWITCH_TIME * 0.5:
			_switch_swapped = true
			weapon_index = _switch_target
			_equip_current()


## Lobs a frag grenade so it lands near `target`.
func throw_grenade(target: Vector3) -> bool:
	if grenades <= 0 or not can_act():
		return false
	grenades -= 1
	throwing = 0.7
	_throw_target = target
	rig.play_throw(0.7)
	Sfx.play(self, "pin", global_position + Vector3.UP * 1.3, -6.0)
	if Net.active and Net.sync:
		Net.sync.send_event(self, "throw")
	return true


func _on_throw_release() -> void:
	if is_dead or not is_inside_tree() or puppet:
		return   # a puppet's grenade arrives as its own network event
	var g := Grenade.new()
	g.thrower = self
	get_tree().current_scene.add_child(g)
	var p0: Vector3 = rig.hands[1].global_position
	g.global_position = p0
	var to := _throw_target - p0
	var t := clampf(Vector2(to.x, to.z).length() / 13.0, 0.45, 1.3)
	var v := to / t
	v.y = (to.y + 0.5 * 9.8 * t * t) / t
	g.linear_velocity = v
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	g.reset_physics_interpolation()
	if Net.active and Net.sync:
		Net.sync.send_event(self, "grenade", [p0, g.linear_velocity, g.angular_velocity])


func _on_footstep(pos: Vector3, intensity: float) -> void:
	var vol := lerpf(-24.0, -11.0, intensity) - (6.0 if crouching else 0.0)
	Sfx.play(self, "footstep", pos, vol, 0.25)


## Called by hitscan weapons. Returns true on a headshot.
func apply_damage(amount: float, hit_pos: Vector3, dir: Vector3, attacker: Node) -> bool:
	if is_dead:
		return false
	if attacker != null and attacker != self and attacker.get("team") == team:
		return false
	var headshot := hit_pos.y - global_position.y > head_height() - 0.14
	if not Net.owns(self):
		# another peer simulates this body: show the hit here, let its owner apply it
		FX.blood(self, hit_pos, dir)
		Sfx.play(self, "hit", hit_pos, -4.0)
		rig.hit_react(dir, amount * (2.5 if headshot else 1.0))
		if Net.sync:
			Net.sync.send_damage(self, amount, hit_pos, dir, attacker)
		return headshot
	if headshot:
		amount *= 2.5
	last_attacker_name = String(attacker.name) if is_instance_valid(attacker) else ""
	last_headshot = headshot
	health -= amount
	since_damage = 0.0
	FX.blood(self, hit_pos, dir)
	Sfx.play(self, "hit", hit_pos, -4.0)
	rig.hit_react(dir, amount)
	damaged.emit(self, amount, attacker)
	if health <= 0.0:
		die(dir)
	return headshot


func die(dir: Vector3) -> void:
	if is_dead:
		return
	is_dead = true
	health = 0.0
	reload_timer = 0.0
	switch_timer = 0.0
	collision_layer = 0
	collision_mask = Layers.WORLD
	velocity = Vector3.ZERO
	rig.play_death(dir)
	var fall := Vector3(dir.x, 0, dir.z).normalized()
	get_tree().create_timer(0.9).timeout.connect(func():
		if is_inside_tree():
			FX.blood_pool(self, global_position + fall * 1.0))
	if Net.active and Net.sync and not puppet:
		Net.sync.send_event(self, "die", [dir, last_attacker_name, last_headshot])
	died.emit(self)


## The owning peer reported this body's death.
func net_die(dir: Vector3, killer: String, headshot: bool) -> void:
	if is_dead:
		return
	last_attacker_name = killer
	last_headshot = headshot
	die(dir)
	var m = get_tree().current_scene
	if m != null and m.has_method("on_net_kill"):
		m.on_net_kill(self, killer, headshot)


## Snapshot target for a puppet (position, velocity, facing).
func _net_set(pos: Vector3, vel: Vector3, yaw: float) -> void:
	if not _net_has:
		_net_has = true
		global_position = pos
		aim_yaw = yaw
		reset_physics_interpolation()
	_net_pos = pos
	_net_vel = vel
	_net_yaw = yaw
	_net_age = 0.0


## Smoothly follows the latest snapshot, extrapolating briefly with its velocity.
func _puppet_move(delta: float) -> void:
	if not _net_has:
		return
	_net_age += delta
	var target := _net_pos + _net_vel * minf(_net_age, 0.2)
	if global_position.distance_to(target) > 4.0:
		global_position = target
		reset_physics_interpolation()
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-14.0 * delta))
	velocity = _net_vel
	aim_yaw = lerp_angle(aim_yaw, _net_yaw, 1.0 - exp(-16.0 * delta))
