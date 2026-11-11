extends Node3D
## Game bootstrap: environment & quality presets, level, player, enemies,
## camera, adaptive music, HUD, rules and call-outs.

const InputSetup = preload("res://scripts/core/input_setup.gd")
const Level = preload("res://scripts/world/forest_level.gd")
const TimeOfDay = preload("res://scripts/world/time_of_day.gd")
const Campaign = preload("res://scripts/modes/campaign.gd")
const Nature = preload("res://scripts/world/nature.gd")
const Player = preload("res://scripts/characters/player.gd")
const Enemy = preload("res://scripts/characters/enemy.gd")
const CameraRig = preload("res://scripts/camera/camera_rig.gd")
const HUD = preload("res://scripts/ui/hud.gd")
const Music = preload("res://scripts/audio/music.gd")
const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const WaveDirector = preload("res://scripts/modes/wave_director.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const PostFX = preload("res://scripts/fx/post_fx.gd")
const Net = preload("res://scripts/net/net.gd")
const NetSync = preload("res://scripts/net/net_sync.gd")
const Collection = preload("res://scripts/skins/collection.gd")

const PVP_KILL_LIMIT := 15
const PVP_TIME := 600.0
const COOP_RESPAWN := 10.0
const PVP_RESPAWN := 3.0

static var best_grade := ""

## Persist across restarts within one session.
static var saved_quality := 1
static var saved_first_person := false
static var saved_muted := false
## "ch1", "ch2" (campaign chapters) or "zombie"
static var saved_mode := "ch1"
## Skip the title screen once (used by restart).
static var quick_restart := false
static var _launch_checked := false

var level: Level
var player: Player
var camera_rig: CameraRig
var hud: HUD
var music: Music
var enemies: Array = []
var game_over := false
var victory := false
var elapsed := 0.0
var quality := 2
var start_first_person := false
var mode := "operation"
var director: WaveDirector
var _ammo_by_pos: Dictionary = {}
var post_fx: PostFX
var damage_taken := 0.0
var headshot_kills := 0
var grade := ""
var mission_score := 0
var _lowpass: AudioEffectLowPassFilter
var env: Environment
var sun: DirectionalLight3D
var _ammo_nodes: Array = []
var _was_contact := false
var _deployed := false
var _base_exposure := 1.25
var tod: TimeOfDay
var campaign: Campaign
var _variant := 0

# ---- multiplayer
## peer id -> operator (local included). Offline: {1: player}.
var players: Dictionary = {}
var net: Node
## PvP (host-authoritative): id -> [name, kills, deaths]
var pvp_scores: Dictionary = {}
var pvp_time_left := PVP_TIME
var pvp_winner := -1
## seconds until the local operator gets back up (multiplayer), < 0 = not scheduled
var respawn_t := -1.0
var _initial_spawns_done := false
var _ammo_taken: Array = []


func _ready() -> void:
	randomize()
	mode = saved_mode if saved_mode in ["ch1", "ch2", "zombie", "pvp"] else "ch1"
	if mode == "pvp" and not Net.is_pvp():
		mode = "ch1"   # deathmatch only exists in a multiplayer session
	Campaign.load_progress()
	InputSetup.setup()
	_setup_audio_bus()
	Settings.ensure()
	preload("res://scripts/ui/retro.gd").install()
	Settings.apply()
	_build_environment()
	if not _launch_checked:
		_launch_checked = true
		Net.read_launch_link()
		Net.register_link_handler()
		Net.funnel_cleanup_stale()

	net = NetSync.new()
	net.name = "NetSync"
	add_child(net)
	net.setup(self)

	level = Level.new()
	level.name = "Level"
	level.mode = mode
	add_child(level)
	level.build()

	tod = TimeOfDay.new()
	tod.name = "TimeOfDay"
	add_child(tod)
	var start_hour := 18.4 if mode == "zombie" else (15.5 if mode == "pvp" else float(Campaign.chapter_info(mode).hour))
	tod.setup(env, sun, level, start_hour)
	if mode == "zombie":
		tod.red_tint = 0.6

	var my_id := Net.my_id()
	player = Player.new()
	player.name = "P%d" % my_id
	player.net_owner = my_id
	add_child(player)
	var start: Array = net_pvp_spawn() if mode == "pvp" else [level.player_spawn, level.player_yaw]
	player.global_position = start[0]
	player.setup_player(float(start[1]), null, false, Net.default_name())
	player.team = _team_for(my_id)
	player.fired.connect(_on_fired)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	players[my_id] = player
	if Net.active and Net.is_server():
		Net.roster[1] = {"name": Net.default_name(), "loadout": Loadout.weapon_list()}
		_pvp_entry(1)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.target = player
	camera_rig.aim_source = player
	camera_rig.snap()
	player.camera_rig = camera_rig

	var spawns: Array = level.enemy_spawns if is_campaign() else []
	if mode == "pvp":
		pass   # players only
	elif mode == "zombie":
		director = WaveDirector.new()
		director.name = "WaveDirector"
		add_child(director)
		director.setup(self)
		for w in player.weapons:
			w.reserve = int(w.stats.reserve) * 2
	else:
		campaign = Campaign.new()
		campaign.name = "Campaign"
		add_child(campaign)
		campaign.setup(self, mode)
	for data in spawns:
		spawn_enemy(data)
	_initial_spawns_done = true

	for p in level.ammo_crates:
		_spawn_ammo(p)

	music = Music.new()
	music.name = "Music"
	add_child(music)
	music.muted = saved_muted

	start_first_person = saved_first_person
	_base_exposure = env.tonemap_exposure
	add_to_group("graphics_listener")
	apply_graphics()

	post_fx = PostFX.new()
	post_fx.name = "PostFX"
	add_child(post_fx)

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)


func alive_players() -> Array:
	var out: Array = []
	if player != null and not player.is_dead:
		out.append(player)
	for id in players:
		var p = players[id]
		if is_instance_valid(p) and p != player and not p.is_dead:
			out.append(p)
	return out


func _exit_tree() -> void:
	Net.join_threads()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("[quit] window close request from the OS")
		Net.leave()   # also removes the Tailscale Funnel mapping when hosting online


func is_zombie_mode() -> bool:
	return mode == "zombie"


func is_campaign() -> bool:
	return mode == "ch1" or mode == "ch2"


## `net_name` / `variant` are given when the host replicates a spawn.
func spawn_enemy(data: Dictionary, net_name: String = "", variant: int = -1):
	var v := _variant if variant < 0 else variant
	var e := Enemy.new()
	e.name = net_name if net_name != "" else "Enemy%d" % v
	e.puppet = Net.active and not Net.is_server()
	add_child(e)
	e.global_position = data.pos
	e.init_enemy(player, level, data, v)
	e.set_meta("group", String(data.get("group", "")))
	e.fired.connect(_on_fired)
	e.died.connect(_on_enemy_died)
	e.reset_physics_interpolation()
	enemies.append(e)
	_variant = maxi(_variant, v + 1)
	if _initial_spawns_done and Net.active and Net.is_server():
		# spawned mid-match (reinforcements): every peer needs a copy
		e.set_meta("net_extra", ["enemy", String(e.name), data.pos, float(data.get("yaw", 0.0)), String(data.get("group", "")), v])
		if Net.sync:
			Net.sync.send_spawn_enemy(e, data, v)
	return e


## Straight into the next chapter (skips the title, plays its briefing).
func continue_to(next_mode: String) -> void:
	if _net_reload(next_mode):
		return
	saved_mode = next_mode
	quick_restart = true
	saved_first_person = player.first_person or start_first_person
	saved_muted = music.muted
	get_tree().paused = false
	get_tree().reload_current_scene()


func on_chapter_complete() -> void:
	if game_over:
		return
	game_over = true
	victory = true
	_grade_mission()
	var reward: int = {"S": 500, "A": 350, "B": 250}.get(grade, 150)
	Collection.add_credits(reward)
	hud.add_feed("CHAPTER %d COMPLETE  ·  +%d CR" % [int(campaign.info().num), reward], Color(0.5, 1.0, 0.7))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_mode(m: String) -> void:
	if _net_reload(m):
		return
	saved_mode = m
	saved_first_person = start_first_person
	saved_muted = music.muted
	get_tree().paused = false
	get_tree().reload_current_scene()


func restart() -> void:
	if _net_reload(mode):
		return
	quick_restart = true
	saved_first_person = player.first_person or start_first_person
	saved_muted = music.muted
	get_tree().paused = false
	get_tree().reload_current_scene()


## Respawns any picked-up ammo cans (between zombie waves).
func refresh_ammo() -> void:
	for p in level.ammo_crates:
		var key := str(p)
		if not _ammo_by_pos.has(key) or not is_instance_valid(_ammo_by_pos[key]):
			_spawn_ammo(p)


func on_deploy() -> void:
	_deployed = true
	player.apply_loadout()
	if Net.active and Net.is_server():
		Net.roster[1] = {"name": Net.default_name(), "loadout": Loadout.weapon_list()}
	player.grenades = 2
	if director != null:
		player.grenades = 3
		player.regen_cap = 70.0
	if tod.night > 0.5:
		player.set_flashlight(true)
		for w in player.weapons:
			w.reserve = int(w.stats.reserve) * 2
	if director != null:
		# zombie survival runs from dusk into the night: deploy with the light on
		player.set_flashlight(true)
		hud.add_feed("FLASHLIGHT ON  ·  [T] TOGGLE", Color(1.0, 0.92, 0.7))
	saved_first_person = start_first_person
	saved_muted = music.muted
	hud.add_feed("OPERATOR DEPLOYED", Color(0.62, 0.92, 0.58))


# ================================================================ audio

func _setup_audio_bus() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var mi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(mi, "Music")
		AudioServer.set_bus_send(mi, "Master")
	if AudioServer.get_bus_effect_count(0) == 0:
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(0, lpf)
	_lowpass = AudioServer.get_bus_effect(0, 0) as AudioEffectLowPassFilter
	if AudioServer.get_bus_index("SFX") != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, "SFX")
	AudioServer.set_bus_send(idx, "Master")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.55
	rev.damping = 0.6
	rev.wet = 0.18
	rev.dry = 1.0
	AudioServer.add_bus_effect(idx, rev)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -12.0
	comp.ratio = 3.0
	AudioServer.add_bus_effect(idx, comp)


# ================================================================ graphics

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_color = Color(0.04, 0.05, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.56, 0.68)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.12
	env.tonemap_white = 6.0
	# contact shadows: wide, strong ambient occlusion that also dims direct light a little
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.6
	env.ssao_power = 1.7
	env.ssao_detail = 0.7
	env.ssao_light_affect = 0.22
	env.ssao_ao_channel_affect = 0.35
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.2
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_bloom = 0.09
	env.glow_strength = 1.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.volumetric_fog_density = 0.009
	env.volumetric_fog_albedo = Color(0.62, 0.66, 0.74)
	env.volumetric_fog_anisotropy = 0.72      # forward scattering: visible sun shafts through the trees
	env.volumetric_fog_length = 72.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 0.08
	env.volumetric_fog_temporal_reprojection_enabled = true
	# distance haze: far ridges and the tree line fade into the sky colour
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0026
	env.fog_aerial_perspective = 0.7
	env.fog_sky_affect = 0.0
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2
	env.sdfgi_energy = 0.9
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.16
	env.adjustment_saturation = 1.14
	env.adjustment_brightness = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	var attrs := CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = false
	we.camera_attributes = attrs
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_color = Color(1.0, 0.84, 0.66)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_blur = 1.1
	sun.light_volumetric_fog_energy = 0.6
	sun.light_angular_distance = 0.6          # soft penumbra that widens with distance
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)


## 0 = LOW, 1 = HIGH, 2 = ULTRA
## F2 / title-menu shortcut: LOW, HIGH, ULTRA presets.
func set_quality(q: int) -> void:
	Settings.set_preset(clampi(q, 0, 2))
	Settings.save()


## Applies every VIDEO setting (called whenever a setting changes).
func apply_graphics() -> void:
	if env == null:
		return
	var v: Dictionary = Settings.v
	quality = int(v.preset)
	saved_quality = quality
	env.ssao_enabled = bool(v.ssao)
	env.ssr_enabled = bool(v.ssr)
	env.ssil_enabled = bool(v.ssil)
	env.sdfgi_enabled = bool(v.gi)
	env.volumetric_fog_enabled = bool(v.fog)
	env.glow_enabled = bool(v.bloom)
	if tod == null:
		env.tonemap_exposure = _base_exposure * float(v.brightness)
	var vp := get_viewport()
	var aa := int(v.aa)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
			Viewport.MSAA_DISABLED, Viewport.MSAA_2X][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 or aa == 5 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == 4
	var rs := float(v.render_scale)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if rs >= 0.999 else Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = rs
	# shadows: OFF / LOW / HIGH / ULTRA
	var sh := int(v.shadows)
	if sun:
		sun.shadow_enabled = sh > 0
		sun.shadow_blur = [1.0, 1.0, 1.6, 1.4][sh]
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if sh <= 1 else \
				(DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 8192][sh], true)
	vp.positional_shadow_atlas_size = [1024, 2048, 4096, 8192][sh]
	if level:
		level.apply_quality(sh - 1)
	if camera_rig and camera_rig.cam:
		camera_rig.cam.fov = float(v.tactical_fov)


func _spawn_ammo(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var green := M.painted_metal("ammo_can", Color(0.26, 0.33, 0.2))
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = ML.box(Vector3(0.5, 0.3, 0.26))
		mi.material_override = green
		mi.position = Vector3(0, 0.15 + i * 0.3, 0)
		mi.rotation.y = i * 0.3
		root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.6)
	light.light_energy = 0.8
	light.omni_range = 1.8
	light.position = Vector3(0, 0.9, 0)
	root.add_child(light)
	root.set_meta("key", str(pos))
	_ammo_nodes.append(root)
	_ammo_by_pos[str(pos)] = root


# ================================================================ rules

func _physics_process(delta: float) -> void:
	if not game_over and _deployed:
		elapsed += delta
		if mode == "pvp" and Net.is_server():
			pvp_time_left -= delta
			if pvp_time_left <= 0.0:
				_pvp_end(_pvp_leader())
	_update_music()
	if player == null or player.is_dead:
		return
	for n in _ammo_nodes.duplicate():
		if not is_instance_valid(n):
			continue
		var d := Vector2(n.global_position.x - player.global_position.x, n.global_position.z - player.global_position.z).length()
		if d < 1.2:
			for w in player.weapons:
				w.reserve = maxi(w.reserve, int(w.stats.reserve))
			player.health = minf(player.health + 35.0, player.max_health)
			player.grenades = mini(player.grenades + 1, 4)
			hud.add_feed("RESUPPLIED  ·  +AMMO  +FRAG  +35 HP", Color(0.5, 1.0, 0.7))
			Sfx.play(self, "mag_in", n.global_position, 0.0)
			_ammo_nodes.erase(n)
			var key := str(n.get_meta("key", ""))
			n.queue_free()
			if Net.active and Net.sync:
				if Net.is_server():
					_ammo_taken.append(key)
					Net.sync.game_event("ammo", [key])
				else:
					Net.sync.client_game("ammo", [key])


func _process(_delta: float) -> void:
	if player == null or hud == null:
		return
	_update_respawn(_delta)
	var vcam := get_viewport().get_camera_3d()
	if vcam != null:
		Nature.set_view(vcam.global_position)
	# zombie survival: the light comes on by itself as night falls
	# (unless the player switched it off on purpose)
	if director != null and _deployed and not player.is_dead and not player.flashlight_on 			and not player.flashlight_manual and tod.night > 0.35:
		player.set_flashlight(true)
		hud.add_feed("NIGHTFALL  ·  FLASHLIGHT ON  [T]", Color(1.0, 0.92, 0.7))
	# low health: muffled hearing, washed-out colour, lens fringing on hits
	var low := 0.0 if player.is_dead else clampf((40.0 - player.health) / 40.0, 0.0, 1.0)
	if _lowpass:
		_lowpass.cutoff_hz = lerpf(20000.0, 900.0, low)
	if player.first_person:
		Nature.set_fade(Vector3(0, -1000, 0), 0.0, 0.0)
	else:
		var fc: Vector3 = player.get_global_transform_interpolated().origin
		Nature.set_fade(fc + Vector3(0, 0, 1.5), 7.5, 15.0)
	var fx_on := bool(Settings.v.film_grain)
	post_fx.grain = 0.012 if fx_on else 0.0
	post_fx.aberration = (hud.damage_flash + low * 0.5) if fx_on and not player.first_person else 0.0
	post_fx.desaturate = 0.85 if player.is_dead else low * 0.6


func _update_music() -> void:
	if music == null:
		return
	var contact := false
	for e in enemies:
		if not e.is_dead and e.is_in_combat():
			contact = true
			break
	if contact and not _was_contact and hud and not player.is_dead and director == null and _deployed:
		hud.add_feed("CONTACT  ·  YOU'VE BEEN SPOTTED", Color(1.0, 0.45, 0.35))
	_was_contact = contact
	if game_over:
		music.intensity = 0.0
		music.master = 0.6
	elif not _deployed:
		music.intensity = 0.0
	elif director != null:
		music.intensity = 1.0 if director.active else 0.25
	else:
		music.intensity = 1.0 if contact else 0.0


func enemies_alive() -> int:
	var n := 0
	for e in enemies:
		if not e.is_dead:
			n += 1
	return n


func time_string() -> String:
	return "%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]


func _on_fired(soldier: Node, weapon: Node, result: Dictionary) -> void:
	if soldier == player:
		camera_rig.add_shake(float(weapon.stats.shake) * (0.5 if player.first_person else 1.0))
		get_tree().call_group("enemies", "hear_noise", player.global_position, float(weapon.stats.noise_radius))
		if result.hit != null and result.hit != player:
			player.shots_hit += 1
			hud.on_hit(result.killed, result.headshot)
			if result.killed and director != null:
				director.on_kill(result.headshot)
			if result.killed:
				if result.headshot:
					headshot_kills += 1
				var wname := String(weapon.stats.name)
				var cr := 10 + (5 if result.headshot else 0)
				Collection.add_credits(cr)
				hud.add_feed(("HEADSHOT  ·  " if result.headshot else "") + "TANGO DOWN  ·  " + wname + "  ·  +%d CR" % cr, Color(1.0, 0.55, 0.45))
	else:
		hud.ping_enemy(soldier)
		var p: Vector3 = result.position
		var shooter_pos: Vector3 = (soldier as Node3D).global_position
		var closest := Geometry3D.get_closest_point_to_segment(player.global_position + Vector3.UP, shooter_pos + Vector3.UP, p)
		if closest.distance_to(player.global_position + Vector3.UP) < 1.5:
			camera_rig.add_shake(0.08)


func _on_player_damaged(_soldier: Node, amount: float, attacker: Node) -> void:
	damage_taken += amount
	hud.on_player_damaged(amount, attacker)
	camera_rig.add_shake(0.25)


func _on_player_died(_soldier: Node) -> void:
	if Net.active:
		# multiplayer: teammates fight on; the host decides when it's over
		if mode == "pvp":
			respawn_t = PVP_RESPAWN
		elif is_campaign():
			respawn_t = COOP_RESPAWN
		else:
			respawn_t = -1.0   # zombies: back up when the wave is cleared
		if Net.is_server():
			on_any_player_died(player)
		return
	if director != null:
		director.on_player_died()
	game_over = true
	victory = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_enemy_died(e: Node) -> void:
	# host: headshot bonus for kills made by other operators
	if Net.active and Net.is_server() and director != null and e.last_headshot \
			and e.last_attacker_name != "" and e.last_attacker_name != String(player.name):
		director.on_kill(true)


## Operation debrief: score from speed, accuracy, headshots and damage taken.
func _grade_mission() -> void:
	var acc := 0.0 if player.shots_fired == 0 else float(player.shots_hit) / player.shots_fired
	var par: float = float(campaign.info().par) if campaign else 420.0
	mission_score = int(1000.0 + maxf(0.0, par - elapsed) * 1.5 + acc * 600.0 + headshot_kills * 60.0 - damage_taken * 2.5)
	mission_score = maxi(mission_score, 0)
	if mission_score >= 2200:
		grade = "S"
	elif mission_score >= 1800:
		grade = "A"
	elif mission_score >= 1400:
		grade = "B"
	else:
		grade = "C"
	if best_grade == "" or "SABC".find(grade) < "SABC".find(best_grade):
		best_grade = grade


# ================================================================ multiplayer

func _team_for(id: int) -> int:
	return 100 + id if mode == "pvp" else 0


## Host broadcasts a mode change / restart; clients ignore their own requests.
func _net_reload(m: String) -> bool:
	if not Net.active:
		return false
	if Net.is_server():
		if Net.sync:
			Net.sync.game_event("reload", [m])
		saved_mode = m
		quick_restart = true
		saved_first_person = player.first_person or start_first_person
		saved_muted = music.muted
		get_tree().paused = false
		get_tree().reload_current_scene()
	return true


## Joined a session / host changed the mode: load straight into that world.
func net_enter_world(m: String) -> void:
	saved_mode = m
	quick_restart = true
	saved_first_person = (player.first_person if player else false) or start_first_person
	saved_muted = music.muted if music else saved_muted
	get_tree().paused = false
	get_tree().reload_current_scene()


func leave_to_title() -> void:
	Net.leave()
	if saved_mode == "pvp" or mode == "pvp":
		saved_mode = "ch1"
	else:
		saved_mode = mode
	quick_restart = false
	Player.input_blocked = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func feed(text: String, kind: String = "") -> void:
	if hud == null:
		return
	var col := Color(0.62, 0.92, 0.58) if kind == "good" else (Color(1.0, 0.55, 0.45) if kind == "bad" else Color(0.86, 0.7, 0.46, 0.88))
	hud.add_feed(text, col)


func local_name() -> String:
	return String(player.name) if player else ""


func display_name_of(id: int) -> String:
	if id == Net.my_id():
		return Net.default_name()
	var p = players.get(id)
	if p != null and is_instance_valid(p) and p.display_name != "":
		return p.display_name
	return String(Net.roster.get(id, {}).get("name", "PLAYER %d" % id))


func _make_operator(id: int, info: Dictionary, pos: Vector3, yaw: float, remote: bool) -> Node:
	var p := Player.new()
	p.name = "P%d" % id
	p.net_owner = id
	add_child(p)
	p.global_position = pos
	p.setup_player(yaw, info.get("loadout", []) if remote else null, remote, String(info.get("name", "PLAYER")))
	p.team = _team_for(id)
	p.set_meta("info", info)
	p.reset_physics_interpolation()
	return p


func add_remote_player(id: int, info: Dictionary, pos: Vector3, yaw: float, dead: bool = false) -> Node:
	remove_remote_player(id)
	var p = _make_operator(id, info, pos, yaw, true)
	p.set_tag_style(mode != "pvp")
	p.died.connect(_on_remote_player_died)
	players[id] = p
	if Net.is_server():
		_pvp_entry(id)
	if dead:
		p.die(Vector3.FORWARD)
	return p


func remove_remote_player(id: int) -> void:
	var p = players.get(id)
	players.erase(id)
	if p != null and is_instance_valid(p) and p != player:
		p.queue_free()


## Keep the old body as a corpse for a while, under another name.
func _retire_body(b: Node) -> void:
	b.name = "%s_down%d" % [b.name, Time.get_ticks_msec() % 100000]
	b.remove_from_group("player")
	get_tree().create_timer(12.0).timeout.connect(func():
		if is_instance_valid(b):
			b.queue_free())


func respawn_remote(old: Node, pos: Vector3, yaw: float) -> void:
	var id := int(old.net_owner)
	var info: Dictionary = old.get_meta("info", {"name": old.display_name, "loadout": []})
	_retire_body(old)
	players.erase(id)
	add_remote_player(id, info, pos, yaw)


func respawn_local(pos: Vector3, yaw: float) -> void:
	var id := Net.my_id()
	var was_fp: bool = start_first_person
	var old := player
	if Net.sync:
		Net.sync.send_event(old, "respawn", [pos, yaw])   # before the old body is renamed
	_retire_body(old)
	var p := _make_operator(id, {"name": Net.default_name()}, pos, yaw, false) as Player
	p.fired.connect(_on_fired)
	p.damaged.connect(_on_player_damaged)
	p.died.connect(_on_player_died)
	player = p
	players[id] = p
	camera_rig.target = p
	camera_rig.aim_source = p
	p.camera_rig = camera_rig
	camera_rig.snap()
	hud.player = p
	p.grenades = 3 if director != null else 2
	if director != null:
		p.regen_cap = 70.0
	if tod.night > 0.5 or director != null:
		p.set_flashlight(true)
	p.set_first_person(was_fp)
	respawn_t = -1.0
	hud.add_feed("BACK IN THE FIGHT", Color(0.62, 0.92, 0.58))


## Next to a living teammate (or the mission start if nobody is up).
func respawn_near_team() -> void:
	var mates: Array = []
	for p in alive_players():
		if p != player:
			mates.append(p)
	var pos: Vector3 = level.player_spawn
	var yaw := level.player_yaw
	if not mates.is_empty():
		var m = mates[randi() % mates.size()]
		var off := Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6))
		pos = m.global_position + off
		yaw = m.aim_yaw
	pos.y = level.ground_y(pos.x, pos.z) if level.has_method("ground_y") else pos.y
	respawn_local(pos, yaw)


func _update_respawn(delta: float) -> void:
	if not Net.active or not player.is_dead or game_over or respawn_t < 0.0:
		return
	respawn_t -= delta
	if respawn_t > 0.0:
		return
	if mode == "pvp":
		var sp := net_pvp_spawn()
		respawn_local(sp[0], float(sp[1]))
	elif alive_players().is_empty():
		respawn_t = 1.0   # nobody to regroup with: wait (the host may end the mission)
	else:
		respawn_near_team()


## Where a joining / respawning operator appears.
func net_spawn_for(_id: int) -> Array:
	if mode == "pvp":
		return net_pvp_spawn()
	var alive := alive_players()
	var base: Vector3 = alive[0].global_position if not alive.is_empty() else level.player_spawn
	var pos := base + Vector3(randf_range(-2.0, 2.0), 0, randf_range(1.0, 2.5))
	if level.has_method("ground_y"):
		pos.y = level.ground_y(pos.x, pos.z)
	return [pos, alive[0].aim_yaw if not alive.is_empty() else level.player_yaw]


## Deathmatch spawn farthest from every other living operator.
func net_pvp_spawn() -> Array:
	var spots: Array = level.get("pvp_spawns") if level.get("pvp_spawns") != null else []
	if spots.is_empty():
		return [level.player_spawn, level.player_yaw]
	var best: Vector3 = spots[randi() % spots.size()]
	var best_d := -1.0
	for s in spots:
		var d := INF
		for p in alive_players():
			if p == player:
				continue
			d = minf(d, (s as Vector3).distance_to(p.global_position))
		d += randf() * 6.0   # a little variety when nobody is around
		if d > best_d:
			best_d = d
			best = s
	return [best, randf() * TAU]


func _on_remote_player_died(p: Node) -> void:
	if Net.is_server():
		on_any_player_died(p)


## Host: a death anywhere in the session.
func on_any_player_died(p: Node) -> void:
	if mode == "pvp":
		_pvp_on_death(p)
	else:
		net_check_all_down()


## Host (co-op): the mission is lost only when nobody is left standing.
func net_check_all_down() -> void:
	if not Net.is_server() or game_over or not _deployed or mode == "pvp":
		return
	if alive_players().is_empty():
		if Net.sync:
			Net.sync.game_event("over", ["down"])
		_net_over(["down"])


func _net_over(args: Array) -> void:
	if game_over:
		return
	game_over = true
	if String(args[0]) == "pvp":
		pvp_winner = int(args[1])
		victory = pvp_winner == Net.my_id()
		var reward := 300 if victory else 100
		Collection.add_credits(reward)
		hud.add_feed("MATCH OVER  ·  +%d CR" % reward, Color(1.0, 0.85, 0.4))
	else:
		victory = false
		if director != null:
			director.on_player_died()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _pvp_entry(id: int) -> void:
	if mode != "pvp" or pvp_scores.has(id):
		return
	pvp_scores[id] = [display_name_of(id), 0, 0]


func _pvp_on_death(victim: Node) -> void:
	var vid := int(victim.net_owner)
	_pvp_entry(vid)
	var killer: Node = get_node_or_null(victim.last_attacker_name) if victim.last_attacker_name != "" else null
	var kid := int(killer.net_owner) if killer != null and killer.get("net_owner") != null and killer is Player else -1
	pvp_scores[vid][2] += 1
	var text := "%s  WENT DOWN" % pvp_scores[vid][0]
	if kid > 0 and kid != vid:
		_pvp_entry(kid)
		pvp_scores[kid][1] += 1
		text = "%s  >>  %s%s" % [pvp_scores[kid][0], pvp_scores[vid][0], "  (HEADSHOT)" if victim.last_headshot else ""]
	feed(text, "bad")
	if Net.sync:
		Net.sync.game_event("feed", [text])
	if kid > 0 and int(pvp_scores[kid][1]) >= PVP_KILL_LIMIT:
		_pvp_end(kid)


func _pvp_leader() -> int:
	var best := -1
	var best_k := -1
	for id in pvp_scores:
		if int(pvp_scores[id][1]) > best_k:
			best_k = int(pvp_scores[id][1])
			best = id
	return best


func _pvp_end(winner: int) -> void:
	if game_over:
		return
	if Net.sync:
		Net.sync.game_event("over", ["pvp", winner])
	_net_over(["pvp", winner])


## Kill confirmation for whoever fired the shot (any peer).
func on_net_kill(victim: Node, killer: String, headshot: bool) -> void:
	if killer == "" or killer != local_name():
		return
	hud.on_hit(true, headshot)
	if victim is Player:
		Collection.add_credits(25)
		hud.add_feed("YOU TOOK DOWN  " + String(victim.display_name) + "  ·  +25 CR", Color(1.0, 0.55, 0.45))
	else:
		if headshot:
			headshot_kills += 1
		var cr := 10 + (5 if headshot else 0)
		Collection.add_credits(cr)
		hud.add_feed(("HEADSHOT  ·  " if headshot else "") + "TANGO DOWN  ·  +%d CR" % cr, Color(1.0, 0.55, 0.45))


## The local operator's jump kick connected.
func on_kick_hit(target: Node) -> void:
	var killed: bool = target.get("is_dead") == true
	hud.on_hit(killed, false)
	if killed:
		Collection.add_credits(15)
		hud.add_feed("KICK KILL  ·  +15 CR", Color(1.0, 0.55, 0.45))


## Another peer's shot was replayed here.
func on_remote_shot(shooter: Node, ends: Array) -> void:
	if player == null or ends.is_empty():
		return
	var from: Vector3 = (shooter as Node3D).global_position + Vector3.UP * 1.4
	var end: Vector3 = ends[0][0]
	if shooter is Player:
		if Net.is_server() and not shooter.weapons.is_empty():
			get_tree().call_group("enemies", "hear_noise", shooter.global_position, float(shooter.current_weapon().stats.noise_radius))
		if mode == "pvp":
			hud.ping_enemy(shooter)
	else:
		hud.ping_enemy(shooter)
	var closest := Geometry3D.get_closest_point_to_segment(player.global_position + Vector3.UP, from, end)
	if closest.distance_to(player.global_position + Vector3.UP) < 1.5:
		camera_rig.add_shake(0.08)


func _remove_ammo(key: String) -> void:
	var n = _ammo_by_pos.get(key)
	if n != null and is_instance_valid(n):
		_ammo_nodes.erase(n)
		n.queue_free()


# ---- host -> client world sync

func net_world_state() -> Dictionary:
	var dead: Array = []
	var extra: Array = []
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.is_dead:
			dead.append(String(e.name))
		elif e.has_meta("net_extra"):
			extra.append(e.get_meta("net_extra"))
	return {
		"tod": tod.hour, "el": elapsed, "dead": dead, "extra": extra,
		"props": level.destroyed_ids.duplicate(),
		"camp": campaign.net_state() if campaign != null else {},
		"dir": director.net_state() if director != null else [],
		"pvp": [pvp_scores, pvp_time_left],
		"ammo": _ammo_taken.duplicate(),
		"over": [game_over, "pvp" if mode == "pvp" else "down", pvp_winner],
	}


func net_apply_world(data: Dictionary) -> void:
	var sp: Array = data.get("spawn", [])
	if sp.size() == 2:
		player.global_position = sp[0]
		player.aim_yaw = float(sp[1])
		player.rig.snap_yaw(float(sp[1]))
		player.reset_physics_interpolation()
		camera_rig.snap()
	for it in data.get("players", []):
		add_remote_player(int(it[0]), it[1], it[2], float(it[3]), bool(it[4]))
	var st: Dictionary = data.get("state", {})
	tod.hour = float(st.get("tod", tod.hour))
	tod.apply_now()
	elapsed = float(st.get("el", 0.0))
	for nm in st.get("dead", []):
		var e = get_node_or_null(String(nm))
		if e != null and not e.is_dead:
			e.die(Vector3.FORWARD)
	for ex in st.get("extra", []):
		if String(ex[0]) == "enemy":
			if get_node_or_null(String(ex[1])) == null:
				spawn_enemy({"pos": ex[2], "yaw": float(ex[3]), "patrol": [], "group": String(ex[4])}, String(ex[1]), int(ex[5]))
		elif String(ex[0]) == "zombie" and director != null:
			if get_node_or_null(String(ex[1])) == null:
				director.spawn_puppet(String(ex[1]), ex[2], ex[3])
	for id in st.get("props", []):
		var pr = level.prop_by_id(int(id))
		if pr != null and not pr.destroyed:
			pr.destroy(pr.center(), Vector3.UP, false)
	if campaign != null and not (st.get("camp", {}) as Dictionary).is_empty():
		campaign.apply_net_state(st.camp)
	if director != null and not (st.get("dir", []) as Array).is_empty():
		director.apply_net_state(st.dir)
	var pv: Array = st.get("pvp", [])
	if pv.size() == 2:
		pvp_scores = pv[0]
		pvp_time_left = float(pv[1])
	for key in st.get("ammo", []):
		_remove_ammo(String(key))
	var ov: Array = st.get("over", [false])
	if bool(ov[0]):
		_net_over([ov[1], ov[2]] if String(ov[1]) == "pvp" else ["down"])
	hud.add_feed("JOINED  ·  %d OPERATOR%s IN THE FIELD" % [players.size(), "" if players.size() == 1 else "S"], Color(0.62, 0.92, 0.58))


func net_slow_state() -> Dictionary:
	return {
		"tod": tod.hour, "el": elapsed,
		"dir": director.net_state() if director != null else [],
		"camp": campaign.net_slow() if campaign != null else [],
		"pvp": [pvp_scores, pvp_time_left] if mode == "pvp" else [],
	}


func net_apply_slow(st: Dictionary) -> void:
	var h := float(st.get("tod", tod.hour))
	if absf(h - tod.hour) > 0.05:
		tod.hour = h
	elapsed = float(st.get("el", elapsed))
	if director != null and not (st.get("dir", []) as Array).is_empty():
		director.apply_net_state(st.dir)
	if campaign != null and not (st.get("camp", []) as Array).is_empty():
		campaign.apply_net_slow(st.camp)
	var pv: Array = st.get("pvp", [])
	if pv.size() == 2:
		pvp_scores = pv[0]
		pvp_time_left = float(pv[1])


## Host -> client game events.
func net_game_event(kind: String, args: Array) -> void:
	match kind:
		"reload":
			net_enter_world(String(args[0]))
		"campaign":
			if campaign != null:
				campaign.net_event(args)
		"wave":
			if director != null:
				director.net_event(args)
		"over":
			_net_over(args)
		"feed":
			feed(String(args[0]), "bad")
		"ammo":
			_remove_ammo(String(args[0]))


## Client -> host requests.
func net_client_game(id: int, kind: String, args: Array) -> void:
	match kind:
		"interact":
			if campaign != null:
				campaign.net_interact[id] = bool(args[0])
		"ammo":
			var key := String(args[0])
			_remove_ammo(key)
			_ammo_taken.append(key)
			if Net.sync:
				Net.sync.game_event("ammo", [key])
