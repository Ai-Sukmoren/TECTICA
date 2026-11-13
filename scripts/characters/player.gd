extends "res://scripts/characters/soldier.gd"
## Player-controlled operator: camera-relative movement, mouse or twin-stick
## aiming (with light aim assist on gamepad), walk / jog / sprint / crouch,
## Q/E peeking, vaulting over low obstacles, firing, reloading, switching.

const Palettes = preload("res://scripts/core/palettes.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Settings = preload("res://scripts/core/settings.gd")
const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")

const SPEED_CROUCH := 1.7
const SPEED_AIM := 2.3
const SPEED_JOG := 4.3
const SPEED_SPRINT := 7.0
const PEEK_DIST := 0.65
const MOUSE_SENS := 0.0022
const PAD_LOOK_SPEED := 3.2

var camera_rig
var hovered_enemy: Node = null
var shots_fired := 0
var shots_hit := 0
var using_pad := false
var vaulting := false
var first_person := false
var regen_cap := 100.0
var sliding := false
var _slide_t := 0.0
var _slide_cd := 0.0
var _slide_speed := 0.0
var _slide_dir := Vector3.FORWARD
var _recoil_recover := 0.0
var fp_pitch := 0.0

var _pad_dir := Vector3.FORWARD
var _pad_dist := 8.0
var _pad_idle := 0.0
var _vault_t := 0.0
var _vault_dur := 0.6
var _vault_from := Vector3.ZERO
var _vault_to := Vector3.ZERO
var _vault_exit_speed := 4.3
var _saved_mask := 0
var _vault_cooldown := 0.0
var _vault_buffer := 0.0
const JUMP_SPEED := 5.8          # ~0.95 m apex with GRAVITY 18
const Terrain = preload("res://scripts/world/terrain.gd")
var _jump_cd := 0.0
# jump kick (V while sprinting)
const KICK_TIME := 0.56
const KICK_SPEED := 10.5
const KICK_UP := 4.4
const KICK_DAMAGE := 45.0
const KICK_KNOCK := 14.5
var kicking := false
var _kick_t := 0.0
var _kick_cd := 0.0
var _kick_dir := Vector3.FORWARD
var _kick_hit: Array = []
var _kick_landed := false
var _fall_speed := 0.0
var flashlight_on := false
var flashlight: SpotLight3D
## Player switched the light themselves (T): auto-on at dusk leaves it alone.
var flashlight_manual := false
var _torch: Node3D
var _torch_lens: MeshInstance3D

## Set by the HUD while an in-game menu is open in multiplayer (the world keeps running).
static var input_blocked := false
var name_tag: Label3D
var _net_flags := 0
var _net_weapon := 0
var _net_lean := 0.0
var _net_inspecting := false


## `loadout` = weapon specs (another peer's operator brings its own);
## `remote` builds a network-driven puppet with a name tag.
## Outfit (character skin) this operator wears.
var outfit := "multicam"


## Weapon specs plus this machine's outfit, as sent to other players.
static func net_loadout() -> Array:
	return Loadout.weapon_list() + [{"outfit": preload("res://scripts/skins/collection.gd").outfit}]


func setup_player(yaw: float = 0.0, loadout = null, remote: bool = false, tag: String = "") -> void:
	var specs: Array = Loadout.weapon_list()
	var outfit_id: String = preload("res://scripts/skins/collection.gd").outfit
	if loadout is Array and not (loadout as Array).is_empty():
		# another peer's loadout ends with its outfit: {"outfit": id}
		specs = []
		outfit_id = "multicam"
		for s in loadout:
			if s is Dictionary and (s as Dictionary).has("outfit"):
				outfit_id = String(s.outfit)
			else:
				specs.append(s)
	outfit = outfit_id
	setup_soldier(Palettes.outfit(outfit_id), specs, Layers.PLAYER, 0 if remote else Layers.WORLD | Layers.ENEMY, yaw)
	use_character_model(Color.WHITE)
	puppet = remote
	display_name = tag
	team = 0
	accel = 48.0   # full jog speed in under 0.1 s
	decel = 60.0
	_pad_dir = Vector3(-sin(yaw), 0, -cos(yaw))
	add_to_group("player")
	# weapon-mounted flashlight (T / Back)
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0, -0.02, -1.05)
	flashlight.spot_range = 30.0
	flashlight.spot_angle = 22.0
	flashlight.spot_attenuation = 0.8
	flashlight.light_energy = 5.0
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.light_volumetric_fog_energy = 0.6
	flashlight.shadow_enabled = true
	flashlight.visible = false
	rig.weapon_anchor.add_child(flashlight)
	_build_torch()
	_build_chem_lights()
	rig.one_hand_sprint = true  # sprint with the gun in the right hand only
	if remote and tag != "":
		name_tag = Label3D.new()
		name_tag.text = tag
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.fixed_size = true
		name_tag.pixel_size = 0.0011
		name_tag.font_size = 22
		name_tag.outline_size = 6
		name_tag.position = Vector3(0, 2.15, 0)
		name_tag.font = preload("res://scripts/ui/retro.gd").bold()
		add_child(name_tag)


## Teammates' tags show through walls; opponents' only in plain sight.
func set_tag_style(friendly: bool) -> void:
	if name_tag == null:
		return
	name_tag.modulate = Color(0.55, 1.0, 0.6) if friendly else Color(1.0, 0.45, 0.4)
	name_tag.no_depth_test = friendly


# ------------------------------------------------------------------ network

func net_pack() -> Array:
	var f := (1 if crouching else 0) | (2 if aiming else 0) | (4 if sprinting else 0) 			| (8 if sliding else 0) | (16 if flashlight_on else 0) | (32 if vaulting else 0)
	f |= 64 if rig.inspect_t >= 0.0 else 0
	return [global_position, velocity, aim_yaw, fp_pitch, f, weapon_index, rig.lean_target, health, _peek_off]


func net_apply(p: Array) -> void:
	if p.size() < 9:
		return
	_net_set(p[0], p[1], float(p[2]))
	_net_flags = int(p[4])
	_net_weapon = int(p[5])
	_net_lean = float(p[6])
	if not is_dead:
		health = float(p[7])
	_peek_off = p[8]


func _puppet_physics(delta: float) -> void:
	if is_dead:
		_sync_rig()
		return
	_puppet_move(delta)
	var f := _net_flags
	set_crouch((f & 1) != 0)
	aiming = (f & 2) != 0
	sprinting = (f & 4) != 0
	sliding = (f & 8) != 0
	if ((f & 16) != 0) != flashlight_on:
		set_flashlight((f & 16) != 0)
	vaulting = (f & 32) != 0
	if _net_weapon != weapon_index and switch_timer <= 0.0 and _net_weapon >= 0 and _net_weapon < weapons.size():
		weapon_index = _net_weapon
		_equip_current()
	_sync_rig()
	rig.lean_target = _net_lean
	rig.slide_target = 1.0 if sliding else 0.0
	if (f & 64) != 0:
		if not _net_inspecting:
			rig.play_inspect()
	else:
		rig.cancel_inspect()
	_net_inspecting = (f & 64) != 0
	if name_tag:
		name_tag.visible = not is_dead


## Visible weapon light: a small housing on the right of the handguard whose
## lens glows while the beam is on.
func _build_torch() -> void:
	_torch = Node3D.new()
	_torch.name = "Torch"
	rig.weapon_anchor.add_child(_torch)
	var body := MeshInstance3D.new()
	body.mesh = ML.cylinder(0.017, 0.017, 0.11, 12)
	body.material_override = M.painted_metal("torch_body", Color(0.09, 0.09, 0.08))
	body.rotation.x = PI * 0.5
	_torch.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = ML.cylinder(0.022, 0.019, 0.03, 12)
	head.material_override = M.painted_metal("torch_body", Color(0.09, 0.09, 0.08))
	head.rotation.x = PI * 0.5
	head.position.z = -0.065
	_torch.add_child(head)
	_torch_lens = MeshInstance3D.new()
	_torch_lens.mesh = ML.cylinder(0.019, 0.019, 0.004, 12)
	_torch_lens.rotation.x = PI * 0.5
	_torch_lens.position.z = -0.081
	_torch.add_child(_torch_lens)
	_place_torch()
	_update_torch_lens()


func _place_torch() -> void:
	if _torch == null or weapons.is_empty():
		return
	# right side of the handguard (rifles) or under the slide (pistols)
	if current_weapon().is_melee():
		_torch.position = Vector3(0.0, -0.035, 0.03)   # knives: a small light by the grip
	else:
		_torch.position = Vector3(0.0, -0.05, -0.17) if current_weapon().is_pistol() else Vector3(0.034, 0.005, -0.4)


func _update_torch_lens() -> void:
	if _torch_lens:
		_torch_lens.material_override = M.emissive("torch_lens_on", Color(1.0, 0.95, 0.82), 6.0) if flashlight_on 				else M.solid(Color(0.55, 0.57, 0.6), 0.15, 0.3)


func _equip_current() -> void:
	super._equip_current()
	_place_torch()


## Green chem lights on the shoulder strap and the back of the vest, so every
## operator stays readable in the dark (soft glow, no shadows, cheap).
const CHEM_COLOR := Color(0.35, 1.0, 0.45)

func _build_chem_lights() -> void:
	var glow := M.emissive("chem_light", CHEM_COLOR, 4.0)
	for spot in [[Vector3(-0.12, 0.13, -0.175), Vector3(0.25, 0, 0.2)], [Vector3(0.1, 0.16, 0.2), Vector3(-0.2, 0, -0.15)]]:
		var stick := MeshInstance3D.new()
		stick.name = "ChemLight"
		stick.mesh = ML.cylinder(0.011, 0.011, 0.11, 8)
		stick.material_override = glow
		stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stick.position = spot[0]
		stick.rotation = spot[1]
		rig.chest.add_child(stick)
	var light := OmniLight3D.new()
	light.name = "ChemGlow"
	light.light_color = CHEM_COLOR
	light.light_energy = 0.55
	light.omni_range = 3.2
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	light.position = Vector3(0, 0.15, 0)
	rig.chest.add_child(light)


func set_flashlight(on: bool) -> void:
	flashlight_on = on
	if flashlight:
		flashlight.visible = on
	_update_torch_lens()


## Interact objective in reach: F / X act on it instead of view / reload.
func _interact_context() -> bool:
	var c = get_tree().get_first_node_in_group("campaign")
	return c != null and c.can_interact()


func _input(event: InputEvent) -> void:
	if puppet or input_blocked:
		return
	if event is InputEventJoypadButton and event.pressed:
		using_pad = true
	elif event is InputEventJoypadMotion:
		var trig: bool = event.axis == JOY_AXIS_TRIGGER_LEFT or event.axis == JOY_AXIS_TRIGGER_RIGHT
		# triggers rest at -1 on some pads; only a real pull or a firm stick push counts
		if (trig and event.axis_value > 0.6) or (not trig and absf(event.axis_value) > 0.55):
			using_pad = true
	elif ((event is InputEventMouseMotion and event.relative.length() > 3.0) or event is InputEventMouseButton or event is InputEventKey) 			and not preload("res://scripts/core/platform.gd").touch_mode():
		using_pad = false   # on phones the touch sticks drive the stick-aim path
	if first_person and not is_dead and event is InputEventMouseMotion 			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * float(Settings.v.sensitivity) * (0.6 if aiming else 1.0) / maxf(lerpf(1.0, float(current_weapon().stats.zoom), rig.aim_amt), 1.0)
		aim_yaw = wrapf(aim_yaw - event.screen_relative.x * sens, -PI, PI)
		fp_pitch = clampf(fp_pitch - event.screen_relative.y * sens, -1.25, 1.2)
		# Render the latest look input without waiting for a physics tick.
		rig.aim_yaw = aim_yaw
		rig.fp_pitch = fp_pitch


func _unhandled_input(event: InputEvent) -> void:
	if puppet or input_blocked or is_dead or vaulting or kicking or rig == null or weapons.is_empty():
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var step := 0
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			step = -1
		MOUSE_BUTTON_WHEEL_DOWN:
			step = 1
		_:
			return
	rig.cancel_inspect()
	switch_to(posmod(weapon_index + step, weapons.size()))
	get_viewport().set_input_as_handled()


## Looking through a magnified optic (ACOG / sniper scope) in first person.
func is_scoped() -> bool:
	return first_person and not is_dead and rig.aim_amt > 0.85 and float(current_weapon().stats.zoom) >= 2.0


func _update_scope_visibility() -> void:
	var scoped := is_scoped()
	current_weapon().visible = not scoped
	for s in rig.shoulders:
		s.visible = not scoped


func apply_loadout() -> void:
	set_loadout(Loadout.weapon_list())


func set_first_person(on: bool) -> void:
	rig.cancel_inspect()
	first_person = on and not is_dead
	rig.set_first_person(first_person)
	if camera_rig:
		camera_rig.first_person = first_person
	if first_person:
		fp_pitch = -0.08
	if not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if first_person else Input.MOUSE_MODE_CONFINED_HIDDEN


func get_fire_origin() -> Vector3:
	if first_person and not is_dead:
		return rig.fp_eye.origin
	return super.get_fire_origin()


## Aim is updated every rendered frame (not once per physics tick), so the
## operator turns with the mouse / stick with no added latency.
func _process(delta: float) -> void:
	if rig == null or puppet or is_dead or vaulting or kicking or input_blocked:
		return
	_update_aim(delta)
	rig.aim_yaw = aim_yaw


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	_tick_actions(delta)
	if puppet:
		_puppet_physics(delta)
		return
	_vault_cooldown = maxf(_vault_cooldown - delta, 0.0)
	if input_blocked and not is_dead and not vaulting and not kicking:
		rig.cancel_inspect()
		aiming = false
		sprinting = false
		sliding = false
		_vault_buffer = 0.0
		_peek_off = Vector3.ZERO
		move_with(Vector3.ZERO, delta)
		_sync_rig()
		rig.lean_target = 0.0
		rig.slide_target = 0.0
		_update_scope_visibility()
		return
	var ctx := _interact_context()
	if Input.is_action_just_pressed("toggle_view") and not ctx:
		set_first_person(not first_person)
	if Input.is_action_just_pressed("flashlight") and not is_dead:
		set_flashlight(not flashlight_on)
		flashlight_manual = true
		Sfx.play(self, "dry", global_position + Vector3.UP * 1.4, -12.0, 0.1)
	if is_dead:
		sliding = false
		if first_person:
			set_first_person(false)
		move_with(Vector3.ZERO, delta)
		_peek_off = Vector3.ZERO
		_sync_rig()
		return
	# health regeneration after a few seconds out of harm's way
	if since_damage > 5.0 and health < regen_cap:
		health = minf(health + 7.0 * delta, regen_cap)
	if vaulting:
		_update_vault(delta)
		_sync_rig()
		return
	_kick_cd = maxf(_kick_cd - delta, 0.0)
	if kicking:
		_update_kick(delta)
		_sync_rig()
		rig.slide_target = 0.0
		return

	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_yaw: float = camera_rig.yaw if camera_rig else 0.0
	if first_person:
		cam_yaw = aim_yaw
	var wish := Basis(Vector3.UP, cam_yaw) * Vector3(iv.x, 0, iv.y)

	aiming = Input.is_action_pressed("aim") and not current_weapon().is_melee()
	_slide_cd = maxf(_slide_cd - delta, 0.0)
	if Input.is_action_just_pressed("crouch"):
		var hv0 := Vector2(velocity.x, velocity.z).length()
		if sprinting and hv0 > 5.0 and _slide_cd <= 0.0 and not sliding:
			_start_slide()
		elif not sliding:
			set_crouch(not crouching)
	var firing := Input.is_action_pressed("fire")
	# Inspection is cosmetic. Every combat input wins, even if the requested
	# action cannot start (for example reload with a full magazine).
	var interrupt_inspect := firing or aiming or Input.is_action_pressed("sprint") \
			or Input.is_action_just_pressed("reload") or Input.is_action_just_pressed("grenade") \
			or Input.is_action_just_pressed("switch_weapon") or Input.is_action_just_pressed("weapon_1") \
			or Input.is_action_just_pressed("weapon_2") or Input.is_action_just_pressed("vault") \
			or Input.is_action_just_pressed("kick") or sliding
	if interrupt_inspect:
		rig.cancel_inspect()
	var sprint_held := Input.is_action_pressed("sprint")
	if using_pad and sprinting and iv.length() > 0.5:
		sprint_held = true  # L3 toggles sprint on gamepad; keep it while stick is pushed
	sprinting = sprint_held and wish.length() > 0.2 and not aiming and not firing and not sliding
	if sprinting and crouching and not sliding:
		set_crouch(false)
	if not interrupt_inspect and Input.is_action_just_pressed("inspect") and can_act() and not sprinting:
		# Read this tick's aim/sprint state, including a just-released trigger.
		_sync_rig()
		if rig.play_inspect():
			Sfx.play(self, "switch", global_position + Vector3.UP * 1.4, -14.0, 0.05)

	# ---- jump kick (V / D-pad right while sprinting)
	if Input.is_action_just_pressed("kick") and sprinting and is_on_floor() and not sliding and _kick_cd <= 0.0:
		_start_kick(wish.normalized())
		_sync_rig()
		return

	# ---- vault over low obstacles (Space / A, or automatically while sprinting)
	if Input.is_action_just_pressed("vault"):
		_vault_buffer = 0.3
	_vault_buffer = maxf(_vault_buffer - delta, 0.0)
	if not sliding and _vault_cooldown <= 0.0 and (_vault_buffer > 0.0 or (sprinting and wish.length() > 0.5)):
		var vdir := wish.normalized() if wish.length() > 0.2 else Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
		var v = _find_vault(vdir)
		if v != null:
			_vault_buffer = 0.0
			_start_vault(v, vdir)
			_sync_rig()
			return

	# ---- jump (Space / A when there is nothing to vault over)
	_jump_cd = maxf(_jump_cd - delta, 0.0)
	if _vault_buffer > 0.0 and (is_on_floor() or air_time < COYOTE_TIME) and not sliding and _jump_cd <= 0.0:
		_vault_buffer = 0.0
		_jump_cd = 0.4
		if crouching:
			set_crouch(false)
		jump_request = JUMP_SPEED
	# landing: footstep thump + a small body dip scaled by fall speed
	if not is_on_floor():
		_fall_speed = maxf(_fall_speed, -velocity.y)
	elif _fall_speed > 0.0:
		if _fall_speed > 3.5:
			_on_footstep(global_position, clampf(_fall_speed / 8.0, 0.4, 1.0))
			rig.hit_react(Vector3(-sin(rig.lower_yaw), 0, -cos(rig.lower_yaw)), _fall_speed * 2.0)
		_fall_speed = 0.0

	var speed := SPEED_JOG
	if sprinting:
		speed = SPEED_SPRINT
	elif crouching:
		speed = SPEED_CROUCH
	elif aiming:
		speed = SPEED_AIM
	if not sprinting and wish.length() > 0.1:
		var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
		var d := wish.normalized().dot(fwd)
		if d < -0.3:
			speed *= 0.72
		elif d < 0.4:
			speed *= 0.88
	var lean_in := Input.get_action_strength("peek_right") - Input.get_action_strength("peek_left")
	if absf(lean_in) > 0.1:
		speed *= 0.6
	speed *= float(current_weapon().stats.mobility)
	if sliding:
		_update_slide(delta, wish)
	else:
		move_with(wish.limit_length(1.0) * speed, delta)
	if _recoil_recover > 0.0:
		var rec := minf(_recoil_recover, 1.4 * delta)
		fp_pitch -= rec
		_recoil_recover -= rec

	_update_peek(lean_in)

	if Input.is_action_just_pressed("grenade"):
		_throw()
	if Input.is_action_just_pressed("flashbang"):
		_throw("flash")
	if Input.is_action_just_pressed("reload") and not ctx:
		start_reload()
	if Input.is_action_just_pressed("weapon_1"):
		switch_to(0)
	if Input.is_action_just_pressed("weapon_2"):
		switch_to(1)
	if Input.is_action_just_pressed("weapon_3"):
		switch_to(2)   # knife
	if Input.is_action_just_pressed("switch_weapon"):
		switch_to((weapon_index + 1) % weapons.size())

	var w := current_weapon()
	if bool(w.stats.auto):
		if firing:
			_fire()
	elif Input.is_action_just_pressed("fire"):
		_fire()
	_sync_rig()
	_update_scope_visibility()
	rig.lean_target = lean_in
	rig.slide_target = 1.0 if sliding else 0.0


# ------------------------------------------------------------------ aiming

func _update_aim(delta: float) -> void:
	hovered_enemy = null
	rig.fp_pitch = fp_pitch
	if first_person:
		_update_fp_aim(delta)
		return
	if using_pad:
		_update_pad_aim(delta)
	else:
		_update_mouse_aim()

	var target_yaw := aim_yaw
	if sprinting:
		var hv := Vector3(velocity.x, 0, velocity.z)
		if hv.length() > 0.5:
			target_yaw = atan2(-hv.x, -hv.z)
	else:
		var to := aim_point - global_position
		to.y = 0.0
		if to.length() > 0.3:
			target_yaw = atan2(-to.x, -to.z)
	aim_yaw = lerp_angle(aim_yaw, target_yaw, 1.0 - exp(-(16.0 if sprinting else 40.0) * delta))


func _update_fp_aim(delta: float) -> void:
	var rs := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.15)
	if rs.length() > 0.0:
		var k := PAD_LOOK_SPEED * float(Settings.v.sensitivity) * (0.5 if aiming else 1.0) * delta / maxf(lerpf(1.0, float(current_weapon().stats.zoom), rig.aim_amt), 1.0)
		aim_yaw = wrapf(aim_yaw - rs.x * absf(rs.x) * k * 1.4, -PI, PI)
		fp_pitch = clampf(fp_pitch - rs.y * absf(rs.y) * k, -1.25, 1.2)
	rig.fp_pitch = fp_pitch
	var eye: Transform3D = rig.fp_eye
	var fwd := -(Basis(Vector3.UP, aim_yaw) * Basis(Vector3.RIGHT, fp_pitch)).z
	var from := global_position + Vector3(0, head_height(), 0) + _peek_off
	if eye.origin != Vector3.ZERO:
		from = eye.origin
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 120.0, Layers.WORLD | Layers.ENEMY | (Layers.PLAYER if Net.is_pvp() else 0), [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		aim_point = from + fwd * 120.0
	else:
		aim_point = hit.position
		if hit.collider != null and hit.collider.get("team") == 1 and not hit.collider.is_dead:
			hovered_enemy = hit.collider


func _update_mouse_aim() -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var mp := vp.get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 300.0, Layers.ENEMY | (Layers.PLAYER if Net.is_pvp() else 0), [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and not hit.collider.is_dead:
		hovered_enemy = hit.collider
		aim_point = hit.position
	elif absf(dir.y) > 0.001:
		var h := get_fire_origin().y - 0.25
		aim_point = from + dir * ((h - from.y) / dir.y)


func _update_pad_aim(delta: float) -> void:
	var cam_yaw: float = camera_rig.yaw if camera_rig else 0.0
	var rs := Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.2)
	if rs.length() > 0.25:
		_pad_idle = 0.0
		_pad_dir = (Basis(Vector3.UP, cam_yaw) * Vector3(rs.x, 0, rs.y)).normalized()
		_pad_dist = lerpf(_pad_dist, lerpf(4.0, 12.0, clampf(rs.length(), 0.0, 1.0)), 1.0 - exp(-6.0 * delta))
	else:
		_pad_idle += delta
		var hv := Vector3(velocity.x, 0, velocity.z)
		if _pad_idle > 0.6 and hv.length() > 1.0 and not aiming:
			_pad_dir = _pad_dir.slerp(hv.normalized(), 1.0 - exp(-5.0 * delta)).normalized()

	# light aim assist: snap toward the closest visible hostile inside a narrow cone
	var best = null
	var best_ang := deg_to_rad(9.0 if aiming else 6.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_dead:
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		if to.length() > 26.0 or to.length() < 0.5:
			continue
		var ang := _pad_dir.angle_to(to.normalized())
		if ang < best_ang:
			best_ang = ang
			best = e
	var h := get_fire_origin().y - 0.25
	if best != null:
		hovered_enemy = best
		var tp: Vector3 = best.global_position + Vector3(0, best.chest_height(), 0)
		var to2 := tp - global_position
		to2.y = 0.0
		_pad_dir = _pad_dir.slerp(to2.normalized(), 1.0 - exp(-(10.0 if aiming else 5.0) * delta)).normalized()
		aim_point = global_position + _pad_dir * to2.length()
		aim_point.y = tp.y
	else:
		aim_point = global_position + _pad_dir * _pad_dist
		aim_point.y = global_position.y + h - global_position.y


# ------------------------------------------------------------------ peek

func _update_peek(lean_in: float) -> void:
	if sprinting or absf(rig.lean_amt) < 0.01:
		_peek_off = Vector3.ZERO
		return
	var right := Vector3(cos(aim_yaw), 0, -sin(aim_yaw))
	var want := right * rig.lean_amt * PEEK_DIST
	var base := global_position + Vector3(0, chest_height(), 0)
	var q := PhysicsRayQueryParameters3D.create(base, base + want * 1.4, Layers.WORLD, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var room := maxf(base.distance_to(hit.position) / 1.4 - 0.08, 0.0)
		want = want.normalized() * minf(room, want.length())
	_peek_off = want
	if lean_in == 0.0 and absf(rig.lean_amt) < 0.05:
		_peek_off = Vector3.ZERO


# ------------------------------------------------------------------ vault

## Probes ahead for a low obstacle with clear space beyond it.
func _find_vault(dir: Vector3):
	var space := get_world_3d().direct_space_state
	var base := global_position
	var knee := base + Vector3(0, 0.45, 0)
	var q := PhysicsRayQueryParameters3D.create(knee, knee + dir * 1.7, Layers.WORLD, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var front: Vector3 = hit.position
	if (hit.normal as Vector3).dot(-dir) < 0.5:
		return null
	var front_dist := Vector2(front.x - base.x, front.z - base.z).length()
	# must be clear at chest height (otherwise it's a wall / tall stack)
	var chest := base + Vector3(0, 1.45, 0)
	q = PhysicsRayQueryParameters3D.create(chest, chest + dir * (front_dist + 1.6), Layers.WORLD, [get_rid()])
	if not space.intersect_ray(q).is_empty():
		return null
	# obstacle top height
	var probe := front + dir * 0.12
	q = PhysicsRayQueryParameters3D.create(Vector3(probe.x, base.y + 2.2, probe.z), Vector3(probe.x, base.y + 0.05, probe.z), Layers.WORLD)
	var top_hit := space.intersect_ray(q)
	if top_hit.is_empty():
		return null
	var top: float = top_hit.position.y
	if top - base.y < 0.35 or top - base.y > 1.3:
		return null
	# find the far edge
	var depth := 0.12
	var edge := -1.0
	while depth < 1.9:
		depth += 0.15
		var p := front + dir * depth
		q = PhysicsRayQueryParameters3D.create(Vector3(p.x, top + 0.3, p.z), Vector3(p.x, base.y + 0.05, p.z), Layers.WORLD)
		var h := space.intersect_ray(q)
		if h.is_empty() or (h.position as Vector3).y < base.y + 0.15:
			edge = depth
			break
	if edge < 0.0:
		return null
	var land := front + dir * (edge + 0.5)
	land.y = maxf(base.y, Terrain.height(land.x, land.z))
	# landing spot must fit the body
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.7
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.transform = Transform3D(Basis.IDENTITY, land + Vector3(0, 0.95, 0))
	sq.collision_mask = Layers.WORLD
	if not space.intersect_shape(sq, 1).is_empty():
		return null
	return {"top": top, "plant": Vector3(front.x, top, front.z) + dir * 0.18 + Vector3(-dir.z, 0, dir.x) * -0.15, "to": land}


func _start_vault(v: Dictionary, dir: Vector3) -> void:
	vaulting = true
	_vault_t = 0.0
	_vault_from = global_position
	_vault_to = v.to
	var hv := Vector2(velocity.x, velocity.z).length()
	_vault_exit_speed = clampf(hv, SPEED_JOG * 0.8, SPEED_SPRINT)
	var dist := Vector2(_vault_to.x - _vault_from.x, _vault_to.z - _vault_from.z).length()
	_vault_dur = clampf(dist / maxf(hv, 4.5) * 1.2, 0.5, 0.85)
	_saved_mask = collision_mask
	collision_mask = 0
	set_crouch(false)
	aiming = false
	if reload_timer > 0.0:
		reload_timer = 0.0
	# Face the jump only when it is roughly ahead. Backing over cover (or
	# vaulting sideways) keeps the view where the player is looking.
	var look := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	if look.dot(dir) > 0.2:
		aim_yaw = atan2(-dir.x, -dir.z)
		_pad_dir = dir
	_peek_off = Vector3.ZERO
	rig.lean_target = 0.0
	rig.play_vault(_vault_dur, float(v.top), v.plant)
	Sfx.play(self, "switch", global_position + Vector3.UP, -6.0)
	if Net.active and Net.sync:
		Net.sync.send_event(self, "vault", [_vault_dur, float(v.top), v.plant])


func _update_vault(delta: float) -> void:
	_vault_t += delta / _vault_dur
	var t := minf(_vault_t, 1.0)
	var e := t * 0.55 + t * t * (3.0 - 2.0 * t) * 0.45
	var p := _vault_from.lerp(_vault_to, e)
	var prev := global_position
	global_position = Vector3(p.x, _vault_from.y, p.z)
	velocity = (global_position - prev) / maxf(delta, 0.0001)
	velocity.y = 0.0
	if _vault_t >= 1.0:
		vaulting = false
		_vault_cooldown = 0.35
		collision_mask = _saved_mask
		var dir := Vector3(_vault_to.x - _vault_from.x, 0, _vault_to.z - _vault_from.z).normalized()
		velocity = dir * _vault_exit_speed
		Sfx.play(self, "hit", global_position, -10.0)
		if using_pad:
			Input.start_joy_vibration(0, 0.3, 0.2, 0.12)


# ------------------------------------------------------------------ jump kick

## Flying kick: launches forward and up; whatever the leg connects with takes
## damage and is thrown back. Committed - no steering or shooting until it lands.
func _start_kick(dir: Vector3) -> void:
	if dir.length() < 0.1:
		dir = Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	kicking = true
	_kick_t = 0.0
	_kick_dir = dir.normalized()
	_kick_hit.clear()
	_kick_landed = false
	aiming = false
	sprinting = true      # keeps the one-handed carry pose through the kick
	set_crouch(false)
	if reload_timer > 0.0:
		reload_timer = 0.0
	aim_yaw = atan2(-_kick_dir.x, -_kick_dir.z)
	_pad_dir = _kick_dir
	_peek_off = Vector3.ZERO
	rig.lean_target = 0.0
	velocity = _kick_dir * KICK_SPEED + Vector3.UP * KICK_UP
	rig.play_kick(KICK_TIME)
	Sfx.play(self, "swipe", global_position + Vector3.UP, -2.0, 0.1)
	if Net.active and Net.sync:
		Net.sync.send_event(self, "kick", [KICK_TIME])


func _update_kick(delta: float) -> void:
	_kick_t += delta
	var k := clampf(_kick_t / KICK_TIME, 0.0, 1.0)
	var sp := lerpf(KICK_SPEED, 5.5, k) * (0.45 if _kick_landed else 1.0)
	velocity.x = _kick_dir.x * sp
	velocity.z = _kick_dir.z * sp
	velocity.y -= GRAVITY * delta
	move_and_slide()
	rig.aim_yaw = aim_yaw
	# the leg is out between ~18 % and ~72 % of the move
	if k > 0.18 and k < 0.72:
		var shape := SphereShape3D.new()
		shape.radius = 0.85
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, global_position + _kick_dir * 0.95 + Vector3.UP * 0.95)
		q.collision_mask = Layers.ENEMY | (Layers.PLAYER if Net.is_pvp() else 0)
		q.exclude = [get_rid()]
		for hit in get_world_3d().direct_space_state.intersect_shape(q, 8):
			var c = hit.collider
			if c == null or c == self or c in _kick_hit or not c.has_method("take_kick"):
				continue
			if c.get("is_dead") == true or c.get("team") == team:
				continue
			_kick_hit.append(c)
			_kick_landed = true
			var at: Vector3 = c.global_position + Vector3.UP * 1.1
			c.take_kick(KICK_DAMAGE, at, _kick_dir, self, _kick_dir * KICK_KNOCK + Vector3.UP * 4.2)
			var killed: bool = c.get("is_dead") == true
			Sfx.play(self, "hit", at, 6.0, 0.1)
			Sfx.play(self, "impact_wood", at, 2.0, 0.2)
			# impact burst: dust and grit off the boots, blood on the target
			FX.chips(self, at, -_kick_dir, Color(0.45, 0.4, 0.33), 14, 0.035, 10, 1.6)
			FX.blood(self, at, _kick_dir)
			if camera_rig:
				camera_rig.add_shake(1.0 if killed else 0.75)
			if using_pad:
				Input.start_joy_vibration(0, 0.9, 1.0, 0.3 if killed else 0.2)
			var hud_node = get_tree().current_scene.get_node_or_null("HUD") if get_tree().current_scene else null
			if hud_node != null and hud_node.has_method("slowmo"):
				hud_node.slowmo(0.3 if killed else 0.45, 0.35 if killed else 0.18)
			var m = get_tree().current_scene
			if m != null and m.has_method("on_kick_hit"):
				m.on_kick_hit(c)
	if _kick_t >= KICK_TIME and (is_on_floor() or _kick_t > KICK_TIME + 0.3):
		kicking = false
		_kick_cd = 0.55
		_on_footstep(global_position, 0.9)


# ------------------------------------------------------------------ slide

func _start_slide() -> void:
	sliding = true
	_slide_t = 0.9
	var hv := Vector3(velocity.x, 0, velocity.z)
	_slide_dir = hv.normalized()
	_slide_speed = maxf(hv.length(), SPEED_SPRINT) * 1.18
	sprinting = false
	set_crouch(true)
	Sfx.play(self, "swipe", global_position, -6.0, 0.15)


func _update_slide(delta: float, wish: Vector3) -> void:
	_slide_t -= delta
	_slide_speed = maxf(_slide_speed - 8.5 * delta, 0.0)
	if wish.length() > 0.2:
		_slide_dir = _slide_dir.slerp(wish.normalized(), 1.2 * delta).normalized()
	velocity.x = _slide_dir.x * _slide_speed
	velocity.z = _slide_dir.z * _slide_speed
	velocity.y = -0.1 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if _slide_t <= 0.0 or _slide_speed < 2.6 or get_slide_collision_count() > 0 and Vector2(velocity.x, velocity.z).length() < 1.0:
		sliding = false
		_slide_cd = 0.45


# ------------------------------------------------------------------ fire

## Real recoil in first person: the view climbs and drifts, then partially recovers.
func _fp_recoil() -> void:
	var st := current_weapon().stats
	var r: float = float(st.recoil) * (float(st.recoil_crouch) if crouching else 1.0)
	var kick := 0.0105 * r * (0.75 if aiming else 1.0)
	fp_pitch = clampf(fp_pitch + kick, -1.25, 1.2)
	aim_yaw = wrapf(aim_yaw + randf_range(-0.6, 0.6) * kick * 0.6, -PI, PI)
	_recoil_recover += kick * 0.6


func _fire() -> void:
	if first_person:
		if try_fire(aim_point):
			shots_fired += 1
			_fp_recoil()
		return
	var origin := get_fire_origin()
	var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	var flat := aim_point - origin
	flat.y = 0.0
	var target := origin + fwd * maxf(flat.length(), 2.0)
	if flat.length() > 1.5:
		target.y = aim_point.y
	if try_fire(target):
		shots_fired += 1
		if using_pad:
			var s: float = current_weapon().stats.shake
			Input.start_joy_vibration(0, s * 2.0, s * 1.2, 0.06)


func _throw(kind: String = "frag") -> void:
	var target := aim_point
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() < 2.0:
		flat = Vector3(-sin(aim_yaw), 0, -cos(aim_yaw)) * 8.0
	if flat.length() > 22.0:
		flat = flat.normalized() * 22.0
	target = global_position + flat
	if first_person:
		target.y = clampf(aim_point.y, 0.0, 2.0)
	if throw_grenade(target, kind):
		aim_yaw = atan2(-flat.x, -flat.z) if not first_person else aim_yaw


## Footsteps: sprinting is loud, jogging carries a little, walking / crouching is silent.
func _on_footstep(pos: Vector3, intensity: float) -> void:
	super._on_footstep(pos, intensity)
	var radius := 0.0
	if sprinting:
		radius = 10.0
	elif not crouching and not aiming and Vector2(velocity.x, velocity.z).length() > 3.5:
		radius = 4.5
	if radius > 0.0:
		get_tree().call_group("enemies", "hear_footstep", pos, radius)


## Flashed: white-out on screen and ringing ears (local operator only).
func flashbang(seconds: float, strength: float) -> void:
	super.flashbang(seconds, strength)
	if puppet:
		return
	var m = get_tree().current_scene
	var h = m.get_node_or_null("HUD") if m else null
	if h != null and h.has_method("flash_white"):
		h.flash_white(seconds, strength)
