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
## slow walk (Alt): silent and a little less eye-catching than a jog
const SPEED_WALK := 2.0
## drag speed with a body in tow
const SPEED_DRAG := 1.5
const Stealth = preload("res://scripts/stealth/stealth.gd")
## takedown timings (s): a kill is quick, a choke-out takes longer but leaves no blood
## (the kill draws the combat knife first: grab, draw, one stab to the neck)
const TD_TIME_KILL := 1.55
const TD_STAB := 0.72
const TD_TIME_KO := 2.4
const TD_ALIGN := 0.25
const DECOY_COOLDOWN := 4.0
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
## FOCUS (single player): kills fill the meter; aiming or firing while vaulting, sliding or in the air spends it on
## bullet time - the game slows to FOCUS_SCALE (the HUD sets the speed) while the mouse keeps its full speed.
## Only with no other player connected (offline, or a local match against bots).
const FOCUS_SCALE := 0.35
const FOCUS_DRAIN := 0.4          # meter per real second of bullet time (a full meter lasts 2.5 s)
const FOCUS_MIN := 0.2            # needed to start it
const FOCUS_KILL := 0.25
const FOCUS_HEADSHOT := 0.35
const FOCUS_GRACE := 0.2          # real seconds it outlasts the stunt (a landing does not cut a shot short)
var focus := 0.5
var bullet_time := false
var _focus_grace := 0.0
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
var _vault_entry_speed := 4.3
## the obstacle along the vault path: where it starts and ends (horizontal metres from the take-off), and how far the
## drawn body rises over it (above the take-off floor)
var _vault_span := Vector2.ZERO
## how high the drawn body rides over the take-off floor along the path, every VAULT_STEP metres (from the obstacle's
## real shape: a lip, a rail or an overhanging top is cleared where it is)
var _vault_clear := PackedFloat32Array()
const VAULT_STEP := 0.05
var _saved_mask := 0
var _vault_cooldown := 0.0
var _vault_buffer := 0.0
## Lowest a vault may land below where it started: over a fence onto a kerb-high step, yes; off a bridge or a
## canal wall (3 m and more), never - a vault goes over cover, it does not drop off ledges.
const VAULT_MAX_DROP := 1.0
const JUMP_SPEED := 5.8          # ~0.95 m apex with GRAVITY 18
const Terrain = preload("res://scripts/world/terrain.gd")
var _jump_cd := 0.0
# jump kick (V while sprinting)
const KICK_TIME := 0.56
const KICK_SPEED := 10.5
const KICK_UP := 4.4
const KICK_DAMAGE := 45.0
const KICK_KNOCK := 14.5
# flying kick: sprint, jump, then V in the air. A heavier blow with a
# shockwave that staggers everyone around the one it lands on.
const AIR_KICK_DAMAGE := 90.0
const AIR_KICK_KNOCK := 21.0
const AIR_KICK_SPEED := 12.5
const AIR_KICK_MIN_SPEED := 4.5   # horizontal speed needed (a running jump)
const AIR_KICK_SPLASH := 2.8      # shockwave radius around the target
const AIR_KICK_SPLASH_KNOCK := 9.0
var kicking := false
var flying_kick := false   # the current kick started in the air
var kick_damage := KICK_DAMAGE   # damage of the kick in progress (read by main / HUD)
var _kick_t := 0.0
var _kick_cd := 0.0
var _kick_dir := Vector3.FORWARD
var _kick_hit: Array = []
var _kick_landed := false
var _fall_speed := 0.0
var flashlight_on := false
var flashlight: SpotLight3D
## Night-vision goggles (N): main.gd fades the effect in and out.
var nvg_on := false
## Player switched the light themselves (T): auto-on at dusk leaves it alone.
var flashlight_manual := false
var _torch: Node3D
var _torch_lens: MeshInstance3D
## The Surefire X300U model inside the torch mount (null: built-in housing).
var _torch_model: Node3D
## Weapon light model (local only); its origin is the rail clamp on the lens
## axis, lens 0.0466 m ahead of it and 0.0198 m below.
const TORCH_GLB := "res://assets/thirdparty/low_poly_attachments/flashlight.glb"

## Set by the HUD while an in-game menu is open in multiplayer (the world keeps running).
static var input_blocked := false

# ---- cutscenes (cutscene_director.gd drives the operator while input is blocked)
var cine_velocity := Vector3.ZERO
var cine_aim := false
var in_cutscene := false

# ---- stealth
## slow-walking (Alt held)
var walking := false
## takedown in progress: the guard held, lethal or not, the clock (-1 = none)
var takedown_target: Node3D = null
var takedown_lethal := false
var _td_t := -1.0
var _td_from := Vector3.ZERO
var _td_at := Vector3.ZERO
var _td_yaw := 0.0
var _td_struck := false
var _td_prev_weapon := -1
var _drag_crouched := false
var _td_next_struggle := 0.0
## a body in tow (F to pick up / put down)
var dragging: Node3D = null
## what F / V would do now (the HUD shows the prompt): a guard to take down, a body to drag
var td_candidate: Node3D = null
var body_candidate: Node3D = null
var _stealth_scan := 0.0
var decoy_cd := 0.0
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
	return own_specs() + [{"outfit": preload("res://scripts/skins/collection.gd").outfit}]


## Zombie Survival: the weapons this operator owns in the current run
## (pistol + knife, plus a bought primary). Empty in every other mode.
static var zombie_specs: Array = []


static func own_specs() -> Array:
	return Loadout.weapon_list() if zombie_specs.is_empty() else zombie_specs.duplicate(true)


func setup_player(yaw: float = 0.0, loadout = null, remote: bool = false, tag: String = "") -> void:
	var specs: Array = own_specs()
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
	_build_rig_extras()
	if remote and tag != "":
		add_name_tag(tag)


## Wear a different outfit right now (the title-screen operator follows the
## armory live). Rebuilds the body; weapons and lights carry over.
func set_outfit(id: String) -> void:
	if id == outfit or rig == null:
		return
	outfit = id
	rebuild_rig(Palettes.outfit(id))
	use_character_model(Color.WHITE)
	_build_rig_extras()


## Show a new set of weapons without deploying (title screen preview).
func preview_loadout(specs: Array) -> void:
	var held := weapon_index
	set_loadout(specs)
	if held > 0 and held < weapons.size():
		weapon_index = held
		_equip_current()


## Lights and kit that hang on the rig: weapon light, torch, chem sticks.
func _build_rig_extras() -> void:
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
	flashlight.visible = flashlight_on
	rig.weapon_anchor.add_child(flashlight)
	_build_torch()
	_build_chem_lights()
	rig.one_hand_sprint = true  # sprint with the gun in the right hand only


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
	if ResourceLoader.exists(TORCH_GLB):
		_torch_model = (load(TORCH_GLB) as PackedScene).instantiate() as Node3D
		_torch.add_child(_torch_model)
		for n in _torch_model.find_children("*", "MeshInstance3D", true, false):
			if String(n.name).begins_with("SM_Lamp"):
				_torch_lens = n as MeshInstance3D
			elif String(n.name).begins_with("SM_Glass"):
				(n as MeshInstance3D).material_override = M.solid(Color(0.85, 0.9, 0.95, 0.15), 0.05, 0.2)
				((n as MeshInstance3D).material_override as BaseMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_place_torch()
		_update_torch_lens()
		return
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
	# right side of the handguard (long guns) or under the frame (pistols),
	# measured on the gun's own mesh so it sits on every model
	var w := current_weapon()
	if _torch_model != null:
		_torch_model.visible = not w.is_melee()
	if w.is_melee():
		_torch.position = Vector3(0.0, -0.035, 0.03)   # knives: a small light by the grip
		if flashlight:
			flashlight.position = Vector3(0, -0.02, -1.05)
		return
	if not w.has_meta("torch_mount"):
		w.set_meta("torch_mount", _torch_mount(w))
	var mount: Vector3 = w.get_meta("torch_mount")
	_torch.position = mount
	_torch.scale = Vector3.ONE * (PISTOL_LIGHT if w.is_pistol() else 1.0)
	if _torch_model != null:
		# the X300U clamps to the gun: under a pistol's frame (clamp up), on the
		# right of a rifle's handguard (turned so the clamp faces the gun), with
		# its lens where the built-in housing's lens was
		var lens_z := -0.081 + 0.0466
		if w.is_pistol():
			_torch_model.rotation = Vector3.ZERO
			_torch_model.position = Vector3(0.0136, 0.017 + 0.0014, lens_z)   # body centred under the frame (the switch paddle sits to one side)
		else:
			_torch_model.rotation = Vector3(0, 0, PI * 0.5)
			_torch_model.position = Vector3(-0.017, 0, lens_z)
	if flashlight:
		# the beam starts just ahead of the muzzle, in line with the lens
		var mz: float = (w.global_transform.affine_inverse() * w.muzzle.global_position).z if w.muzzle else mount.z - 0.3
		flashlight.position = Vector3(mount.x, mount.y, minf(mz, mount.z - 0.081) - 0.12)


## Pistol lights are compact: the housing is drawn at this scale.
const PISTOL_LIGHT := 0.72


## Where the light housing goes on this gun, in weapon space: hugging the
## right side of the handguard just ahead of the support hand (lens behind
## the muzzle), or tucked under a pistol's frame ahead of the trigger guard.
func _torch_mount(w: Weapon) -> Vector3:
	const R := 0.017      # housing radius
	const HALF := 0.055   # half the housing length; the lens is 0.081 ahead of its centre
	var inv := w.global_transform.affine_inverse()
	var muz: Vector3 = inv * w.muzzle.global_position if w.muzzle else Vector3(0, 0.03, -0.5)
	var verts := PackedVector3Array()
	for n in w.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := inv * mi.global_transform
		for v in mi.mesh.get_faces():
			verts.append(xf * v)
	if w.is_pistol():
		# compact light: lens just behind the muzzle, body clear of the trigger guard
		var cz := muz.z + (0.081 + 0.008) * PISTOL_LIGHT
		var lo := INF
		for v in verts:
			# the dust cover: underside of the frame's front few centimetres
			if v.z > muz.z and v.z < muz.z + 0.05 and absf(v.x) < 0.03 and v.y < muz.y:
				lo = minf(lo, v.y)
		if lo == INF:
			return Vector3(0.0, -0.05, -0.17)
		return Vector3(0.0, lo - R * PISTOL_LIGHT - 0.001, cz)
	var sup: Vector3 = inv * w.support.global_position if w.support else muz * 0.6
	# ahead of the support hand, but the lens stays behind the muzzle
	var cz2 := maxf(sup.z - 0.1, muz.z + 0.081 + 0.03)
	var top := muz.y + 0.035      # skip optics / rails above the bore
	var bottom := muz.y - 0.07    # and magazines / bipods / grips below
	var right := -INF
	for v in verts:
		if absf(v.z - cz2) < HALF and v.y < top and v.y > bottom:
			right = maxf(right, v.x)
	if right == -INF:
		return Vector3(0.034, 0.005, -0.4)
	var ys := 0.0
	var count := 0
	for v in verts:
		if absf(v.z - cz2) < HALF and v.y < top and v.y > bottom and v.x > right - 0.006:
			ys += v.y
			count += 1
	var y := ys / count if count > 0 else muz.y - 0.01
	return Vector3(right + R + 0.001, y, cz2)


func _update_torch_lens() -> void:
	if _torch_lens:
		_torch_lens.material_override = M.emissive("torch_lens_on", Color(1.0, 0.95, 0.82), 6.0) if flashlight_on 				else M.solid(Color(0.55, 0.57, 0.6), 0.15, 0.3)


func _equip_current() -> void:
	super._equip_current()
	_place_torch()


## Green chem sticks on the shoulder strap and the back of the vest, so every
## operator stays readable in the dark. They only glow themselves: no light is
## cast on the body (it showed as a green rim on the operator, also on the menu).
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


## Number keys pick weapons by role, so they still work when the inventory is
## short (zombie runs start with only a pistol and a knife).
func _slot(role: String) -> int:
	for i in weapons.size():
		var w = weapons[i]
		match role:
			"primary":
				if not w.is_pistol() and not w.is_melee():
					return i
			"smg":
				if String(w.stats.category) == "SMG" and i > 0:
					return i
			"pistol":
				if w.is_pistol():
					return i
			"knife":
				if w.is_melee():
					return i
	return weapon_index


func set_flashlight(on: bool) -> void:
	flashlight_on = on
	if flashlight:
		flashlight.visible = on
	_update_torch_lens()


## Interact objective or the zombie arcade shop in reach: F / X act on it
## instead of view / reload.
func _interact_context() -> bool:
	if td_candidate != null or body_candidate != null or dragging != null or _td_t >= 0.0:
		return true
	var c = get_tree().get_first_node_in_group("campaign")
	if c != null and c.can_interact():
		return true
	var a = get_tree().get_first_node_in_group("arcade_shop")
	return a != null and a.can_interact(self)


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
	if first_person and not is_dead and _td_t < 0.0 and event is InputEventMouseMotion 			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
	var st: Dictionary = current_weapon().stats
	return first_person and not is_dead and rig.aim_amt > 0.85 and (float(st.zoom) >= 2.0 or bool(st.get("overlay", false)))


func _update_scope_visibility() -> void:
	var scoped := is_scoped()
	current_weapon().visible = not scoped
	if _torch != null:
		_torch.visible = not scoped   # the weapon light rides on the gun: hide it with the gun
	for s in rig.shoulders:
		s.visible = not scoped


func apply_loadout() -> void:
	set_loadout(own_specs())


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


## The operator's shots stay on the crosshair while walking: moving opens the
## cone a little from the hip and barely at all aiming down sights; a full
## sprint-speed hip shot still scatters.
func _move_spread(hv: float) -> float:
	# bullet time steadies the hands: a vault or slide shot lands where the crosshair is
	return clampf(hv / 6.0, 0.0, 1.2) * lerpf(0.6, 0.15, rig.aim_amt) * (0.25 if bullet_time else 1.0)


## Aiming and shooting in the middle of a vault: the gun comes up (no hand on the obstacle) and fires as usual.
func _vault_fire() -> void:
	var w := current_weapon()
	if w.is_melee():
		return
	aiming = Input.is_action_pressed("aim")
	var firing := Input.is_action_pressed("fire")
	if not (aiming or firing):
		return
	sprinting = false
	rig.vault_aim = true
	rig.cancel_inspect()
	if bool(w.stats.auto):
		if firing:
			_fire()
	elif Input.is_action_just_pressed("fire"):
		_fire()


## A kill fills the FOCUS meter (more for a headshot).
func add_focus(headshot: bool) -> void:
	focus = minf(focus + (FOCUS_HEADSHOT if headshot else FOCUS_KILL), 1.0)


## Bullet time starts when the operator aims or fires during a stunt (vault, slide, a jump) with enough FOCUS, and
## runs while the stunt lasts and the meter holds. Never with other players: their game must keep its speed.
func _update_focus(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	var stunt := vaulting or sliding or kicking or (not is_on_floor() and air_time > 0.1)
	var engaged := Input.is_action_pressed("aim") or Input.is_action_pressed("fire")
	if not Net.alone() or is_dead or current_weapon().is_melee():
		_end_bullet_time()
		return
	if bullet_time:
		focus = maxf(focus - FOCUS_DRAIN * real, 0.0)
		_focus_grace = FOCUS_GRACE if stunt else _focus_grace - real
		if focus <= 0.0 or _focus_grace <= 0.0:
			_end_bullet_time()
	elif stunt and engaged and focus >= FOCUS_MIN:
		bullet_time = true
		_focus_grace = FOCUS_GRACE
		Sfx.play_ui(self, "focus_in", -4.0)


func _end_bullet_time() -> void:
	if bullet_time:
		bullet_time = false
		Sfx.play_ui(self, "focus_out", -8.0)


func get_fire_origin() -> Vector3:
	if first_person and not is_dead:
		return rig.fp_eye.origin
	return super.get_fire_origin()


## Aim is updated every rendered frame (not once per physics tick), so the
## operator turns with the mouse / stick with no added latency.
func _process(delta: float) -> void:
	if rig == null or puppet or is_dead or kicking or input_blocked or _td_t >= 0.0:
		return   # (aim keeps updating during a vault: the operator can shoot in it)
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
		_end_bullet_time()
		if not in_cutscene:
			rig.cancel_inspect()   # (a cutscene plays the weapon check on purpose)
		aiming = cine_aim
		sprinting = false
		sliding = false
		_vault_buffer = 0.0
		_peek_off = Vector3.ZERO
		move_with(cine_velocity, delta)
		_sync_rig()
		rig.lean_target = 0.0
		rig.slide_target = 0.0
		_update_scope_visibility()
		return
	var ctx := _interact_context()
	if Input.is_action_just_pressed("toggle_view") and not ctx:
		set_first_person(not first_person)
	if Input.is_action_just_pressed("nvg") and not is_dead:
		nvg_on = not nvg_on
		Sfx.play(self, "switch", global_position + Vector3.UP * 1.6, -8.0, 0.0)
	if Input.is_action_just_pressed("flashlight") and not is_dead:
		set_flashlight(not flashlight_on)
		flashlight_manual = true
		Sfx.play(self, "dry", global_position + Vector3.UP * 1.4, -12.0, 0.1)
	if is_dead:
		sliding = false
		_end_bullet_time()
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
		_vault_fire()
		_update_focus(delta)
		_sync_rig()
		return
	_kick_cd = maxf(_kick_cd - delta, 0.0)
	if kicking:
		_update_kick(delta)
		_update_focus(delta)
		_sync_rig()
		rig.slide_target = 0.0
		return
	# ---- stealth: takedowns (F knock out / V kill from behind), bodies (F drag / drop), decoys
	if _td_t >= 0.0:
		_update_takedown(delta)
		_sync_rig()
		return
	_stealth_scan -= delta
	if _stealth_scan <= 0.0:
		_stealth_scan = 0.1
		_scan_stealth()
	decoy_cd = maxf(decoy_cd - delta, 0.0)
	var td_kill := Input.is_action_just_pressed("kick") and not sprinting
	if (Input.is_action_just_pressed("interact") or td_kill) and is_instance_valid(td_candidate) \
			and dragging == null and Stealth.can_takedown(self, td_candidate):
		_start_takedown(td_candidate, td_kill)
		_sync_rig()
		return
	if Input.is_action_just_pressed("interact"):
		if dragging != null:
			drop_body()
		elif is_instance_valid(body_candidate):
			start_drag(body_candidate)
	if dragging != null and (Input.is_action_pressed("fire") or Input.is_action_pressed("aim") or Input.is_action_just_pressed("vault")):
		drop_body()   # back to the fight: let go at once
	if Input.is_action_just_pressed("decoy"):
		throw_decoy()

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
	# ---- flying kick (V in the air during a running jump)
	if Input.is_action_just_pressed("kick") and not is_on_floor() and air_time > 0.04 and not sliding and _kick_cd <= 0.0 \
			and Vector2(velocity.x, velocity.z).length() >= AIR_KICK_MIN_SPEED:
		var fdir := wish.normalized() if wish.length() > 0.2 else Vector3(velocity.x, 0, velocity.z).normalized()
		_start_kick(fdir, true)
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

	walking = Input.is_action_pressed("walk") and not sprinting and not crouching
	if dragging != null:
		sprinting = false
		aiming = false
	var speed := SPEED_JOG
	if sprinting:
		speed = SPEED_SPRINT
	elif crouching:
		speed = SPEED_CROUCH
	elif aiming:
		speed = SPEED_AIM
	elif walking:
		speed = SPEED_WALK
	if dragging != null:
		speed = minf(speed, SPEED_DRAG)
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
	if Input.is_action_just_pressed("launcher"):
		fire_launcher(aim_point)
	if Input.is_action_just_pressed("reload") and not ctx:
		var was := reload_timer
		start_reload()
		if reload_timer > 0.0 and was <= 0.0:
			Stealth.emit_sound(self, global_position, 5.0, "reload", self)
	if Input.is_action_just_pressed("weapon_1"):
		switch_to(_slot("primary"))
	if Input.is_action_just_pressed("weapon_2"):
		switch_to(_slot("smg"))
	if Input.is_action_just_pressed("weapon_3"):
		switch_to(_slot("pistol"))
	if Input.is_action_just_pressed("weapon_4"):
		switch_to(_slot("knife"))
	if Input.is_action_just_pressed("switch_weapon"):
		switch_to((weapon_index + 1) % weapons.size())

	var w := current_weapon()
	if dragging != null:
		_update_drag()
	elif bool(w.stats.auto):
		if firing:
			_fire()
	elif Input.is_action_just_pressed("fire"):
		_fire()
	_update_focus(delta)
	_sync_rig()
	if dragging != null:
		rig.sprint_target = 1.0   # rifle slung low in one hand, the other on the body
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
	# The body itself must be able to make the jump: swept up clear of the top, across to the landing spot and down
	# onto walkable floor no more than VAULT_MAX_DROP below the take-off. These are real collision sweeps, so no
	# wall, boundary, railing or building can be passed through, and the landing is never inside geometry or off a
	# ledge. (Rays alone missed walls beyond their reach and could not tell the inside of a hollow mesh.)
	var xf := global_transform
	var lift := Vector3.UP * (top - base.y + 0.08)
	if test_move(xf, lift):
		return null
	var over := xf.translated(lift)
	for past in [0.85, 0.5]:   # land well clear of the far edge when there is room: a longer, softer way down
		var land: Vector3 = front + dir * (edge + float(past))
		var across := Vector3(land.x - base.x, 0.0, land.z - base.z)
		if test_move(over, across):
			continue
		var down := KinematicCollision3D.new()
		if not test_move(over.translated(across), -lift - Vector3.UP * VAULT_MAX_DROP, down) or down.get_normal().y < 0.7:
			continue
		land.y = over.origin.y + down.get_travel().y
		if not _landing_ok(Transform3D(xf.basis, land), dir):
			continue
		return {"top": top, "plant": Vector3(front.x, top, front.z) + dir * 0.18 + Vector3(-dir.z, 0, dir.x) * -0.15, "to": land,
				"front": front_dist, "depth": edge}
	return null


## The height the drawn body must ride at along the vault path (every VAULT_STEP m), from the obstacle as it is:
## rays down across the body's width find what is under it; the body (legs tucked, feet ~0.3 m above the hips'
## drop, a quarter metre deep either side) stays 5 cm over it, and rises / comes down smoothly before and after
## (0.7 m ahead, 0.5 m behind).
func _vault_clearance(dir: Vector3, dist: float) -> PackedFloat32Array:
	var space := get_world_3d().direct_space_state
	var base := global_position
	var side := Vector3(-dir.z, 0.0, dir.x)
	var n := int(dist / VAULT_STEP) + 1
	var need := PackedFloat32Array()
	need.resize(n)
	for i in n:
		var c := base + dir * (i * VAULT_STEP)
		var h := 0.0
		for o in [0.0, 0.18, -0.18]:
			var at: Vector3 = c + side * o
			var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, base.y + 1.6, at.z), Vector3(at.x, base.y + 0.05, at.z), Layers.WORLD, [get_rid()])
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				h = maxf(h, (hit.position as Vector3).y - base.y)
		need[i] = maxf(h - 0.3 + 0.05, 0.0) if h > 0.3 else 0.0
	# the body is a quarter metre deep either side of its middle: clear the obstacle for all of it
	var wide := PackedFloat32Array()
	wide.resize(n)
	var r := int(0.25 / VAULT_STEP)
	for i in n:
		for j in range(maxi(0, i - r), mini(n, i + r + 1)):
			wide[i] = maxf(wide[i], need[j])
	need = wide
	# a smooth envelope: rise ahead of each high point, come down after it
	var out := PackedFloat32Array()
	out.resize(n)
	var ahead := int(0.7 / VAULT_STEP)
	var behind := int(0.5 / VAULT_STEP)
	for i in n:
		if need[i] <= 0.0:
			continue
		for j in range(maxi(0, i - ahead), mini(n, i + behind + 1)):
			var x := float(i - j) / (ahead if j < i else behind) if j != i else 0.0
			out[j] = maxf(out[j], need[i] * (1.0 - smoothstep(0.0, 1.0, absf(x))))
	return out


## A landing the body can stand on: solid floor right under its middle and around it (not a rail or a kerb's edge it
## would tip off), room to stand up, and not pinned between walls.
func _landing_ok(at: Transform3D, dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var o := at.origin
	var side := Vector3(-dir.z, 0.0, dir.x)
	for d in [Vector3.ZERO, dir * 0.3, side * 0.3, -side * 0.3]:
		var q := PhysicsRayQueryParameters3D.create(o + Vector3.UP * 0.3 + d, o + Vector3.DOWN * 0.15 + d, Layers.WORLD, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (d == Vector3.ZERO and (hit.normal as Vector3).y < 0.8):
			return false
	var up := at.translated(Vector3.UP * 0.04)
	if test_move(up, Vector3.UP * 0.3):
		return false
	var blocked := 0
	for d in [dir, -dir, side, -side]:
		if test_move(up, d * 0.08):
			blocked += 1
	return blocked < 2


func _start_vault(v: Dictionary, dir: Vector3) -> void:
	vaulting = true
	_vault_t = 0.0
	_vault_from = global_position
	_vault_to = v.to
	var hv := Vector2(velocity.x, velocity.z).length()
	_vault_exit_speed = clampf(hv, SPEED_JOG * 0.8, SPEED_SPRINT)
	var dist := Vector2(_vault_to.x - _vault_from.x, _vault_to.z - _vault_from.z).length()
	_vault_dur = clampf(dist / maxf(hv, 4.5) * 1.2, 0.5, 0.85)
	_vault_entry_speed = clampf(hv, 0.0, dist / _vault_dur * 1.5)
	_vault_clear = _vault_clearance(dir, dist)
	_vault_span = Vector2(-1.0, -1.0)
	for i in _vault_clear.size():
		if _vault_clear[i] > 0.0:
			if _vault_span.x < 0.0:
				_vault_span.x = i * VAULT_STEP
			_vault_span.y = i * VAULT_STEP
	if _vault_span.x < 0.0:
		_vault_span = Vector2(dist * 0.4, dist * 0.6)
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
	var height := float(v.top) - global_position.y
	rig.play_vault(_vault_dur, height, v.plant)
	rig.drive_vault(0.0, 0.0)
	Sfx.play(self, "switch", global_position + Vector3.UP, -6.0)
	if Net.active and Net.sync:
		Net.sync.send_event(self, "vault", [_vault_dur, height, v.plant])


## The vault, by where the body is over the ground rather than by the clock: it carries on at the speed it came in
## with (no hitch on take-off) to the speed it leaves with; it rises as it reaches the obstacle, stays clear of it
## while over it and comes down past it; the hand plant, the tuck and the landing dip follow the same path.
func _update_vault(delta: float) -> void:
	_vault_t += delta / _vault_dur
	var t := minf(_vault_t, 1.0)
	var dist := Vector2(_vault_to.x - _vault_from.x, _vault_to.z - _vault_from.z).length()
	# Hermite ease: leaves at the entry speed, arrives at the exit speed
	var v1 := minf(_vault_exit_speed, dist / _vault_dur * 1.5)
	var d := clampf((t * t * t - 2.0 * t * t + t) * _vault_dur * _vault_entry_speed + (-2.0 * t * t * t + 3.0 * t * t) * dist
			+ (t * t * t - t * t) * _vault_dur * v1, 0.0, dist)
	var e := d / maxf(dist, 0.001)
	var p := _vault_from.lerp(_vault_to, e)
	var prev := global_position
	global_position = p   # along the path the sweeps cleared, ending on the landing floor
	velocity = (global_position - prev) / maxf(delta, 0.0001)
	velocity.y = 0.0
	# the rise over the obstacle, above the straight line from the take-off floor to the landing floor
	var s0 := clampf(_vault_span.x, 0.0, dist)
	var s1 := clampf(_vault_span.y, s0, dist)
	var k := d / VAULT_STEP
	var i0 := clampi(int(k), 0, _vault_clear.size() - 1)
	var i1 := mini(i0 + 1, _vault_clear.size() - 1)
	var clear := lerpf(_vault_clear[i0], _vault_clear[i1], clampf(k - i0, 0.0, 1.0))
	if s0 <= 0.05:
		clear *= smoothstep(0.0, 0.04, t)   # pressed up against it: up in the first moments rather than at once
	var lift := maxf(clear - (_vault_to.y - _vault_from.y) * e, 0.0)
	# the animation's timeline along the same path: 0.2 reaching the obstacle, 0.7 leaving it
	var phase := 1.0
	if t < 1.0:
		if d < s0:
			phase = 0.2 * d / maxf(s0, 0.001)
		elif d < s1:
			phase = lerpf(0.2, 0.7, (d - s0) / maxf(s1 - s0, 0.001))
		else:
			phase = lerpf(0.7, 0.99, (d - s1) / maxf(dist - s1, 0.001))
	rig.drive_vault(phase, lift)
	if _vault_t >= 1.0:
		vaulting = false
		rig.drive_vault(-1.0, -1.0)
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
func _start_kick(dir: Vector3, air: bool = false) -> void:
	if dir.length() < 0.1:
		dir = Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	flying_kick = air
	kick_damage = AIR_KICK_DAMAGE if air else KICK_DAMAGE
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
	if air:
		# already airborne: drive forward and hold the height a moment longer
		velocity = _kick_dir * AIR_KICK_SPEED + Vector3.UP * maxf(velocity.y, 2.6)
	else:
		velocity = _kick_dir * KICK_SPEED + Vector3.UP * KICK_UP
	rig.play_kick(KICK_TIME)
	Sfx.play(self, "swipe", global_position + Vector3.UP, 1.0 if air else -2.0, 0.1)
	if Net.active and Net.sync:
		Net.sync.send_event(self, "kick", [KICK_TIME])


func _update_kick(delta: float) -> void:
	_kick_t += delta
	var k := clampf(_kick_t / KICK_TIME, 0.0, 1.0)
	var sp := lerpf(AIR_KICK_SPEED if flying_kick else KICK_SPEED, 5.5, k) * (0.45 if _kick_landed else 1.0)
	velocity.x = _kick_dir.x * sp
	velocity.z = _kick_dir.z * sp
	velocity.y -= GRAVITY * delta
	move_and_slide()
	rig.aim_yaw = aim_yaw
	# the leg is out between ~18 % and ~72 % of the move
	if k > 0.18 and k < 0.72:
		var shape := SphereShape3D.new()
		shape.radius = 1.0 if flying_kick else 0.85
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
			if flying_kick:
				c.take_kick(AIR_KICK_DAMAGE, at, _kick_dir, self, _kick_dir * AIR_KICK_KNOCK + Vector3.UP * 5.5)
			else:
				c.take_kick(KICK_DAMAGE, at, _kick_dir, self, _kick_dir * KICK_KNOCK + Vector3.UP * 4.2)
			var killed: bool = c.get("is_dead") == true
			Sfx.play(self, "hit", at, 6.0, 0.1)
			Sfx.play(self, "impact_wood", at, 2.0, 0.2)
			# impact burst: dust and grit off the boots, blood on the target
			FX.chips(self, at, -_kick_dir, Color(0.45, 0.4, 0.33), 26 if flying_kick else 14, 0.035, 18 if flying_kick else 10, 1.6)
			FX.blood(self, at, _kick_dir)
			if flying_kick:
				_air_kick_shockwave(c, at)
			if camera_rig:
				camera_rig.add_shake((1.4 if killed else 1.15) if flying_kick else (1.0 if killed else 0.75))
			if using_pad:
				Input.start_joy_vibration(0, 1.0, 1.0, 0.4 if flying_kick else (0.3 if killed else 0.2))
			var hud_node = get_tree().current_scene.get_node_or_null("HUD") if get_tree().current_scene else null
			if hud_node != null and hud_node.has_method("slowmo"):
				if flying_kick:
					hud_node.slowmo(0.22, 0.45)
				else:
					hud_node.slowmo(0.3 if killed else 0.45, 0.35 if killed else 0.18)
			var m = get_tree().current_scene
			if m != null and m.has_method("on_kick_hit"):
				m.on_kick_hit(c)
	if _kick_t >= KICK_TIME and (is_on_floor() or _kick_t > KICK_TIME + 0.3):
		kicking = false
		flying_kick = false
		_kick_cd = 0.55
		_on_footstep(global_position, 0.9)


## Flying kick landed: a shockwave shoves and staggers everyone around the
## target (no extra damage), with a thump and a ring of dust.
func _air_kick_shockwave(target: Node, at: Vector3) -> void:
	Sfx.play(self, "explosion", at, -12.0, 0.15)
	FX.chips(self, Vector3(at.x, global_position.y + 0.05, at.z), Vector3.UP, Color(0.5, 0.46, 0.38), 0, 0.03, 16, 2.4)
	var shape := SphereShape3D.new()
	shape.radius = AIR_KICK_SPLASH
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = Layers.ENEMY | (Layers.PLAYER if Net.is_pvp() else 0)
	q.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 16):
		var o = hit.collider
		if o == null or o == self or o == target or o in _kick_hit or not o.has_method("apply_knockback"):
			continue
		if o.get("is_dead") == true or o.get("team") == team:
			continue
		var away: Vector3 = (o as Node3D).global_position - at
		away.y = 0.0
		if away.length() < 0.05:
			away = _kick_dir
		var near := 1.0 - clampf(away.length() / AIR_KICK_SPLASH, 0.0, 1.0)
		var push: Vector3 = away.normalized() * AIR_KICK_SPLASH_KNOCK * (0.5 + 0.5 * near) + Vector3.UP * 2.0
		if Net.owns(o):
			o.apply_knockback(push, 0.6)
		elif Net.sync:
			Net.sync.send_knock(o, push)


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


## Footsteps: sprinting is loud, jogging carries a little, walking, slow walking
## and crouching are silent (a hard landing is not). Walls muffle them (stealth.gd).
func _on_footstep(pos: Vector3, intensity: float) -> void:
	super._on_footstep(pos, intensity)
	var radius := 0.0
	if sprinting:
		radius = 10.0
	elif not crouching and not aiming and not walking and Vector2(velocity.x, velocity.z).length() > 3.5:
		radius = 4.5
	if intensity > 0.6 and not crouching:
		radius = maxf(radius, 6.0 * intensity)   # landing from a jump or a drop
	if Water.wading(pos):
		radius = maxf(radius, 7.0)   # splashing carries
	if radius > 0.0:
		Stealth.emit_sound(self, pos, radius, "footstep", self)


## Flashed: white-out on screen and ringing ears (local operator only).
func flashbang(seconds: float, strength: float) -> void:
	super.flashbang(seconds, strength)
	if puppet:
		return
	var m = get_tree().current_scene
	var h = m.get_node_or_null("HUD") if m else null
	if h != null and h.has_method("flash_white"):
		h.flash_white(seconds, strength)


# ------------------------------------------------------------------ stealth

## Who / what the F and V prompts point at (every 0.1 s). Takedowns run on the
## machine that simulates the guards (solo or the host); dragging bodies is solo.
func _scan_stealth() -> void:
	td_candidate = null
	body_candidate = null
	if is_dead or vaulting or kicking or sliding or dragging != null or not (Net.alone() or Net.is_server()):
		return
	td_candidate = Stealth.takedown_target(self)
	if td_candidate != null or not Net.alone():
		return
	var best_d := 1.8
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get("is_dead") != true or e.get("dummy") == true:
			continue
		var d: float = (e as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			body_candidate = e


## Grabs `e` from behind: the operator slides into place behind him and either
## chokes him out (F, quiet, no blood) or kills him (V, quicker, louder).
## Guards who can see it react (stealth.gd notify_witnesses).
func _start_takedown(e: Node3D, lethal: bool) -> void:
	takedown_target = e
	takedown_lethal = lethal
	_td_t = 0.0
	_td_struck = false
	_td_next_struggle = 0.3
	e.grab()
	rig.cancel_inspect()
	if reload_timer > 0.0:
		reload_timer = 0.0
		rig.cancel_reload()
	aiming = false
	sliding = false
	_peek_off = Vector3.ZERO
	rig.lean_target = 0.0
	set_crouch(false)
	_end_bullet_time()
	# a kill: the free hand clamps his mouth while the other draws the combat knife;
	# a knockout: the free arm locks round his neck, the gun hangs in the other hand
	_td_prev_weapon = weapon_index
	var knife := _slot("knife")
	if lethal and knife >= 0 and knife != weapon_index:
		switch_to(knife)
	sprinting = not lethal or knife < 0     # one-handed carry pose for the rifle
	var fwd := Vector3(-sin(e.aim_yaw), 0, -cos(e.aim_yaw))
	_td_from = global_position
	_td_at = e.global_position - fwd * 0.72
	_td_at.y = global_position.y
	_td_yaw = e.aim_yaw
	velocity = Vector3.ZERO
	Sfx.play(self, "swipe", e.global_position + Vector3.UP * 1.3, -10.0, 0.1)
	Stealth.emit_sound(self, e.global_position, 3.5 if lethal else 2.5, "takedown", self)
	Stealth.notify_witnesses(get_tree(), e.global_position + Vector3.UP * 1.0, "takedown", self, [e])


func _update_takedown(delta: float) -> void:
	_td_t += delta
	var e := takedown_target
	if not is_instance_valid(e):
		_end_takedown()
		return
	var dur := TD_TIME_KILL if takedown_lethal else TD_TIME_KO
	var k := smoothstep(0.0, TD_ALIGN, _td_t)
	global_position = _td_from.lerp(_td_at, k)
	velocity = Vector3.ZERO
	aim_yaw = lerp_angle(aim_yaw, _td_yaw, k)
	rig.aim_yaw = aim_yaw
	if first_person:
		fp_pitch = lerpf(fp_pitch, -0.42, 1.0 - exp(-8.0 * delta))
		rig.fp_pitch = fp_pitch
	var back := -Vector3(-sin(_td_yaw), 0, -cos(_td_yaw))
	if not e.is_dead and e.get("rig") != null and e.rig.head != null:
		# the free hand on him: over the mouth for a kill, the neck for a choke
		var hold: Vector3 = e.rig.head.global_position + back * 0.08 + Vector3(0, -0.06 if takedown_lethal else -0.2, 0)
		rig.left_reach = hold
	if not e.is_dead:
		if not takedown_lethal and _td_t >= _td_next_struggle:
			# he fights the hold, weaker each time
			_td_next_struggle += randf_range(0.25, 0.4)
			e.rig.hit_react(back + Vector3(randf_range(-0.4, 0.4), 0, 0), lerpf(2.4, 0.6, _td_t / dur))
			if camera_rig:
				camera_rig.add_shake(0.06)
		if takedown_lethal and current_weapon().is_melee() and _td_t >= TD_STAB - 0.22 and not _td_struck and rig.slash_t < 0.0:
			rig.play_slash(0.5)   # the stab comes in round his shoulder
		var strike := TD_STAB if takedown_lethal else dur - 0.45
		if _td_t >= strike and not _td_struck:
			_td_struck = true
			if takedown_lethal:
				if not current_weapon().is_melee():
					rig.play_attack(0.4)
				Sfx.play(self, "knife_hit", e.global_position + Vector3.UP * 1.3, -2.0, 0.1)
				FX.blood(self, e.global_position + Vector3.UP * 1.35, back)
				e.grabbed = false
				e.apply_damage(e.health + 50.0, e.global_position + Vector3.UP * 1.0, -back, self)
				Stealth.emit_sound(self, e.global_position, 4.0, "takedown", self)
			else:
				Sfx.play(self, "groan", e.global_position + Vector3.UP * 1.3, -14.0, 0.1)
				e.knock_out(-back)
				var m = get_tree().current_scene
				if m != null and m.has_method("on_takedown"):
					m.on_takedown(e)
	if takedown_lethal and _td_struck and _td_t >= TD_STAB + 0.25:
		rig.left_reach = Vector3.INF   # he goes down: let go
	if _td_t >= dur:
		_end_takedown()
	else:
		move_with(Vector3.ZERO, delta)


func _end_takedown() -> void:
	if is_instance_valid(takedown_target) and not takedown_target.is_dead:
		takedown_target.grabbed = false   # interrupted: he's free
	takedown_target = null
	_td_t = -1.0
	sprinting = false
	rig.left_reach = Vector3.INF
	if _td_prev_weapon >= 0 and _td_prev_weapon != weapon_index:
		switch_to(_td_prev_weapon)   # knife away, back to the gun
	_td_prev_weapon = -1
	_stealth_scan = 0.0


func is_taking_down() -> bool:
	return _td_t >= 0.0


## Picks a body up by the shoulders: slow, no shooting until it's put down.
func start_drag(body: Node3D) -> void:
	dragging = body
	body.set_meta("dragged", true)
	rig.cancel_inspect()
	aiming = false
	_drag_crouched = crouching
	set_crouch(true)   # stooped over him, one hand on his collar
	body_candidate = null
	Sfx.play_foley(self, "step_grass", body.global_position, -14.0, 0.2)


## Puts the body down where it is; in a bush or the dark it's hidden.
func drop_body() -> void:
	if dragging == null:
		return
	var b := dragging
	dragging = null
	rig.left_reach = Vector3.INF
	set_crouch(_drag_crouched)
	if is_instance_valid(b):
		b.remove_meta("dragged")
		Stealth.emit_sound(self, b.global_position, 3.0, "body", self)
		var lvl = get_tree().current_scene.get("level") if get_tree().current_scene else null
		var m = get_tree().current_scene
		if m != null and m.get("hud") != null and Stealth.body_hidden(lvl, b):
			m.hud.add_feed("BODY HIDDEN", Color(0.55, 0.85, 0.6))
	_stealth_scan = 0.0


## The body is held by the shoulders in front of the operator, who backs away
## pulling it along the ground (in first person it stays in view).
func _update_drag() -> void:
	var b := dragging
	if not is_instance_valid(b) or is_dead:
		dragging = null
		return
	var fwd := Vector3(-sin(aim_yaw), 0, -cos(aim_yaw))
	var right := Vector3(fwd.z, 0, -fwd.x) * -1.0
	# his shoulders come to the operator's left hand, his legs trail away from him
	var grip := global_position + fwd * 0.5 - right * 0.18
	var brig = b.get("rig")
	if brig != null and brig.chest != null and brig.hips != null:
		var chest: Vector3 = brig.chest.global_position
		var hips: Vector3 = brig.hips.global_position
		var along := Vector3(hips.x - chest.x, 0, hips.z - chest.z)
		if along.length() > 0.1:
			var turn := along.signed_angle_to(fwd, Vector3.UP)   # legs pointing away
			b.rotation.y += turn * 0.2
		var off := Vector3(chest.x - b.global_position.x, 0, chest.z - b.global_position.z)
		var want := grip - off
		want.y = global_position.y
		b.global_position = b.global_position.lerp(want, 0.35)
		# a settled corpse's model stops updating (soldier_rig.gd): carry it with the body
		brig.global_transform = b.global_transform.scaled_local(brig._render_scale)
		rig.left_reach = brig.chest.global_position + Vector3(0, 0.12, 0)
	else:
		var want := global_position + fwd * 1.3
		want.y = global_position.y
		b.global_position = b.global_position.lerp(want, 0.35)
		b.rotation.y = lerp_angle(b.rotation.y, aim_yaw + PI, 0.2)


## Throws a pebble-sized decoy: where it lands it clatters and guards in earshot
## go to look (stealth.gd "distraction"). A short cooldown, no ammo.
func throw_decoy() -> bool:
	if decoy_cd > 0.0 or dragging != null or not can_act():
		return false
	var target := aim_point
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() < 3.0:
		flat = Vector3(-sin(aim_yaw), 0, -cos(aim_yaw)) * 8.0
	if flat.length() > 20.0:
		flat = flat.normalized() * 20.0
	target = global_position + flat
	if throw_grenade(target, "decoy"):
		decoy_cd = DECOY_COOLDOWN
		return true
	return false
