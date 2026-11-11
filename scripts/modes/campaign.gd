extends Node
## Campaign chapters and their objective chains.
##
##   CHAPTER 1  TIMBERLINE   (dawn -> day)   infiltrate the logging camp,
##              wipe out the garrison, download the intel, exfil to the bridge.
##   CHAPTER 2  NIGHTFALL    (night)         infiltrate the radio outpost, blow
##              the generator (lights die) and the radio tower, reach the LZ and
##              hold it against the reinforcements until the helicopter lands.
##
## Objective kinds: reach, clear (an enemy group), interact (hold F / X),
## charge (interact, then a timed demolition charge), hold (survive a timer).

const Blast = preload("res://scripts/weapons/blast.gd")
const FX = preload("res://scripts/fx/fx.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const M = preload("res://scripts/core/materials.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const Net = preload("res://scripts/net/net.gd")
const Player = preload("res://scripts/characters/player.gd")

const SAVE_PATH := "user://campaign.cfg"   # per account: Profile.path()
const Profile = preload("res://scripts/core/profile.gd")
const HOLD_TIME := 3.0
const CHARGE_FUSE := 6.0

static var completed := {}   # "ch1": best grade

var main
var level
var chapter := "ch1"
var step := 0
var objectives: Array = []
var hold_progress := 0.0
var holding := false
var charge_t := -1.0
var charge_node: Node3D
var hold_timer := 0.0
var _reinforced := false
var _wave2 := false
var _heli: Node3D
var _heli_rotor: Node3D
var _flare: Node3D
var _beep := 0.0
var _tower_down := false
## host: peer id -> holding the interact key at the objective
var net_interact: Dictionary = {}
var _sent_interact := false


static func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(Profile.path("campaign.cfg")) == OK:
		for k in ["ch1", "ch2"]:
			if cfg.has_section_key("campaign", k):
				completed[k] = cfg.get_value("campaign", k)


static func save_progress() -> void:
	var cfg := ConfigFile.new()
	for k in completed:
		cfg.set_value("campaign", k, completed[k])
	cfg.save(Profile.path("campaign.cfg"))


static func chapter_info(ch: String) -> Dictionary:
	if ch == "ch2":
		return {
			"num": 2, "name": "NIGHTFALL", "hour": 20.6, "par": 780.0,
			"location": "PINEWOOD VALLEY  -  RADIO OUTPOST KILO",
			"sitrep": "THE INTEL POINTS TO THE OUTPOST RELAYING ENEMY COMMS",
			"intel": "CUT THE POWER FIRST - THE FLOODLIGHTS DIE WITH IT  -  [T] FLASHLIGHT",
		}
	return {
		"num": 1, "name": "TIMBERLINE", "hour": 8.0, "par": 600.0,
		"location": "PINEWOOD VALLEY  -  NORTHERN LOGGING CAMP",
		"sitrep": "HOSTILE MILITIA OCCUPIED THE CAMP AT 0400",
		"intel": "THE WOODS HIDE YOU - CROUCH IN BUSHES  -  TREES STOP BULLETS",
	}


func setup(p_main, p_chapter: String) -> void:
	main = p_main
	level = main.level
	chapter = p_chapter
	add_to_group("campaign")
	if chapter == "ch2":
		objectives = [
			{"kind": "reach", "text": "INFILTRATE THE RADIO OUTPOST", "pos": level.outpost, "radius": 26.0},
			{"kind": "charge", "text": "SABOTAGE THE GENERATOR", "id": "generator"},
			{"kind": "charge", "text": "DESTROY THE RADIO TOWER", "id": "tower"},
			{"kind": "reach", "text": "REACH THE EXTRACTION LZ", "pos": level.lz_north, "radius": 7.0},
			{"kind": "hold", "text": "HOLD THE LZ UNTIL THE HELO LANDS", "pos": level.lz_north, "time": 50.0},
		]
	else:
		objectives = [
			{"kind": "reach", "text": "INFILTRATE THE LOGGING CAMP", "pos": level.camp, "radius": 24.0},
			{"kind": "clear", "text": "ELIMINATE THE CAMP GARRISON", "group": "camp", "pos": level.camp},
			{"kind": "interact", "text": "DOWNLOAD THE INTEL", "id": "intel"},
			{"kind": "reach", "text": "EXFIL TO THE RIVER CROSSING", "pos": level.bridge, "radius": 6.0},
		]


func info() -> Dictionary:
	return chapter_info(chapter)


func current() -> Dictionary:
	return objectives[step] if step < objectives.size() else {}


func objective_pos():
	var o := current()
	if o.is_empty():
		return null
	if o.has("id"):
		return level.interact_points[o.id].pos
	return o.get("pos")


func objective_text() -> String:
	var o := current()
	if o.is_empty():
		return "CHAPTER COMPLETE"
	var t: String = o.text
	match String(o.kind):
		"clear":
			t += "   %d LEFT" % _group_alive(String(o.group))
		"hold":
			t += "   %d" % int(ceil(hold_timer))
		"charge":
			if charge_t >= 0.0:
				t = "CHARGE SET  -  GET CLEAR   %.1f" % charge_t
	return t


func _group_alive(g: String) -> int:
	var n := 0
	for e in main.enemies:
		if is_instance_valid(e) and not e.is_dead and e.has_meta("group") and String(e.get_meta("group")) == g:
			n += 1
	return n


## True when the player can use the current interact objective (F / X).
func can_interact() -> bool:
	var o := current()
	if o.is_empty() or not (String(o.kind) in ["interact", "charge"]) or charge_t >= 0.0:
		return false
	var ip: Dictionary = level.interact_points[o.id]
	var pp: Vector3 = main.player.global_position
	return Vector2(pp.x - ip.pos.x, pp.z - ip.pos.z).length() < float(ip.radius) and not main.player.is_dead


func interact_label() -> String:
	var o := current()
	if o.is_empty() or not o.has("id"):
		return ""
	return String(level.interact_points[o.id].label)


func _local_interacting() -> bool:
	return can_interact() and Input.is_action_pressed("interact") and not Player.input_blocked


## Host: any operator holding interact inside the objective radius.
func _anyone_interacting() -> bool:
	if _local_interacting():
		return true
	var o := current()
	if o.is_empty() or not o.has("id"):
		return false
	var ip: Dictionary = level.interact_points[o.id]
	for id in net_interact:
		if not net_interact[id]:
			continue
		var p = main.players.get(id)
		if p != null and is_instance_valid(p) and not p.is_dead:
			var pp: Vector3 = p.global_position
			if Vector2(pp.x - ip.pos.x, pp.z - ip.pos.z).length() < float(ip.radius) + 0.5:
				return true
	return false


## Clients mirror the host: animations / timers only, objectives arrive as events.
func _client_tick(delta: float) -> void:
	_update_charge(delta, false)
	_update_heli(delta)
	var o := current()
	if not o.is_empty() and String(o.kind) == "hold" and _reinforced:
		hold_timer = maxf(hold_timer - delta, 0.0)
	var pressed := _local_interacting()
	if pressed != _sent_interact and Net.sync:
		_sent_interact = pressed
		Net.sync.client_game("interact", [pressed])
	holding = pressed


func _physics_process(delta: float) -> void:
	if main == null or main.game_over or not main._deployed:
		return
	if not Net.is_server():
		_client_tick(delta)
		return
	_update_charge(delta)
	_update_heli(delta)
	var o := current()
	if o.is_empty():
		return
	var pp: Vector3 = main.player.global_position
	match String(o.kind):
		"reach":
			var p: Vector3 = o.pos
			for op in main.alive_players():
				var q: Vector3 = op.global_position
				if Vector2(q.x - p.x, q.z - p.z).length() < float(o.radius):
					_advance()
					break
		"clear":
			if _group_alive(String(o.group)) == 0:
				_advance()
		"interact", "charge":
			holding = _anyone_interacting()
			if holding:
				hold_progress += delta / HOLD_TIME
				if hold_progress >= 1.0:
					hold_progress = 0.0
					holding = false
					if String(o.kind) == "interact":
						_advance()
					else:
						_plant_charge(String(o.id))
			else:
				hold_progress = maxf(hold_progress - delta * 2.0, 0.0)
		"hold":
			if not _reinforced:
				_reinforced = true
				hold_timer = float(o.time)
				if Net.sync:
					Net.sync.game_event("campaign", ["hold", hold_timer])
				_spawn_reinforcements()
				_spawn_heli()
			hold_timer -= delta
			if not _wave2 and hold_timer < 28.0:
				_wave2 = true
				_spawn_reinforcements()
			if hold_timer <= 0.0:
				_advance()


func _advance() -> void:
	var done := current()
	step += 1
	if Net.sync:
		Net.sync.game_event("campaign", ["advance", step])
	_after_advance(done)


func _after_advance(done: Dictionary) -> void:
	if String(done.get("kind", "")) == "interact":
		Sfx.play(main, "kill", main.player.global_position, -4.0, 0.0)
		main.hud.add_feed("INTEL SECURED", Color(0.5, 1.0, 0.7))
	Sfx.play(main, "mag_in", main.player.global_position, 0.0, 0.0)
	if step >= objectives.size():
		completed[chapter] = main.grade if main.grade != "" else "C"
		main.on_chapter_complete()
		if main.grade != "":
			completed[chapter] = main.grade
		save_progress()
		return
	main.hud.add_feed("OBJECTIVE COMPLETE  ·  " + String(done.text), Color(0.5, 1.0, 0.7))
	main.hud.wave_banner(String(current().text))
	if String(current().kind) == "hold":
		hold_timer = float(current().time)


# ------------------------------------------------------------------ charges

func _plant_charge(id: String) -> void:
	if Net.sync:
		Net.sync.game_event("campaign", ["plant", id])
	var ip: Dictionary = level.interact_points[id]
	charge_t = CHARGE_FUSE
	_beep = 0.0
	charge_node = Node3D.new()
	main.add_child(charge_node)
	charge_node.global_position = (ip.pos as Vector3) + Vector3(0, 0.4, 0) - ((ip.pos as Vector3) - (ip.node as Node3D).global_position).normalized() * 0.6
	var brick := MeshInstance3D.new()
	brick.mesh = ML.box(Vector3(0.28, 0.12, 0.18))
	brick.material_override = M.solid(Color(0.55, 0.52, 0.4), 0.8)
	charge_node.add_child(brick)
	var led := OmniLight3D.new()
	led.light_color = Color(1, 0.1, 0.05)
	led.omni_range = 2.0
	led.position.y = 0.12
	charge_node.add_child(led)
	charge_node.set_meta("id", id)
	Sfx.play(main, "pin", charge_node.global_position, 0.0, 0.0)
	main.hud.add_feed("CHARGE PLANTED  ·  GET CLEAR", Color(1.0, 0.75, 0.3))


func _update_charge(delta: float, authoritative: bool = true) -> void:
	if charge_t < 0.0:
		return
	charge_t -= delta
	if not authoritative:
		charge_t = maxf(charge_t, 0.01)   # the host's detonation event ends it
	_beep -= delta
	if _beep <= 0.0 and is_instance_valid(charge_node):
		_beep = clampf(charge_t / CHARGE_FUSE, 0.12, 1.0) * 0.8
		Sfx.play(main, "hitmarker", charge_node.global_position, -2.0, 0.0)
		var led := charge_node.get_child(1) as OmniLight3D
		led.light_energy = 3.0
		create_tween().tween_property(led, "light_energy", 0.0, 0.15)
	if charge_t <= 0.0 and authoritative:
		var id := String(charge_node.get_meta("id"))
		var at := charge_node.global_position
		if Net.sync:
			Net.sync.game_event("campaign", ["detonate", id, at])
		_detonate(id, at, true)
		_advance()


func _detonate(id: String, at: Vector3, deal_damage: bool) -> void:
	charge_t = -1.0
	if is_instance_valid(charge_node):
		charge_node.queue_free()
	Blast.detonate(level, at, 220.0, 8.0, main.player, [], deal_damage)
	main.camera_rig.add_shake(0.6)
	if id == "generator":
		_wreck_generator()
	else:
		_topple_tower()


## Host events on clients.
func net_event(args: Array) -> void:
	match String(args[0]):
		"advance":
			var done := current()
			step = int(args[1])
			_after_advance(done)
		"plant":
			_plant_charge(String(args[1]))
		"detonate":
			_detonate(String(args[1]), args[2], false)
		"hold":
			_reinforced = true
			hold_timer = float(args[1])
			_spawn_heli()


func net_slow() -> Array:
	return [step, hold_timer, hold_progress]


func apply_net_slow(s: Array) -> void:
	hold_timer = float(s[1])
	hold_progress = float(s[2])


## Late join: rebuild what has already happened in this chapter.
func net_state() -> Dictionary:
	return {"step": step, "hold": hold_timer, "reinf": _reinforced, "power": level.outpost_powered, "tower": _tower_down}


func apply_net_state(st: Dictionary) -> void:
	step = int(st.get("step", 0))
	if not bool(st.get("power", true)):
		_wreck_generator()
	if bool(st.get("tower", false)) and is_instance_valid(level.radio_tower):
		_tower_down = true
		level.radio_tower.rotation.z = -1.48
	if bool(st.get("reinf", false)):
		_reinforced = true
		hold_timer = float(st.get("hold", 0.0))
		_spawn_heli()


func _wreck_generator() -> void:
	level.outpost_powered = false
	var g: Node3D = level.generator
	if is_instance_valid(g):
		for c in g.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).material_override = M.solid(Color(0.08, 0.07, 0.06), 0.9)
	_burning(g.global_position + Vector3(0, 1.2, 0))
	main.hud.add_feed("POWER CUT  ·  OUTPOST LIGHTS DOWN", Color(0.6, 0.85, 1.0))
	get_tree().call_group("enemies", "hear_noise", g.global_position, 45.0)


func _topple_tower() -> void:
	_tower_down = true
	var t: Node3D = level.radio_tower
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(t, "rotation:z", -1.48, 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		var land: Vector3 = t.global_position + Vector3(12, 0.2, 0)
		FX.explosion(level, land)
		Sfx.play(main, "break_hard", land, 6.0, 0.0)
		main.camera_rig.add_shake(0.5)
		_burning(t.global_position + Vector3(1.0, 0.8, 0)))
	main.hud.add_feed("RADIO TOWER DOWN  ·  COMMS SEVERED", Color(0.6, 0.85, 1.0))


func _burning(p: Vector3) -> void:
	var fire := CPUParticles3D.new()
	fire.amount = 36
	fire.lifetime = 1.1
	fire.mesh = ML.sphere(0.18, false, 6)
	fire.material_override = M.glow(Color(1.0, 0.45, 0.12, 0.8))
	fire.direction = Vector3.UP
	fire.spread = 20.0
	fire.initial_velocity_min = 0.8
	fire.initial_velocity_max = 1.8
	fire.gravity = Vector3(0, 0.6, 0)
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.4
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(fire)
	fire.global_position = p
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.2)
	l.light_energy = 2.5
	l.omni_range = 9.0
	main.add_child(l)
	l.global_position = p + Vector3(0, 0.8, 0)
	level.lamp_lights.append({"light": l, "base": 2.5, "group": "fire", "flicker": true})


# ------------------------------------------------------------------ extraction

func _spawn_reinforcements() -> void:
	var lz: Vector3 = level.lz_north
	var spots := [Vector3(-22, 0, -60), Vector3(-30, 0, -68), Vector3(24, 0, -66), Vector3(4, 0, -62)]
	if _wave2:
		spots = [Vector3(30, 0, -80), Vector3(-26, 0, -86), Vector3(-8, 0, -60)]
	for s in spots:
		var e = main.spawn_enemy({"pos": s, "yaw": 0.0, "patrol": [], "group": "reinforce"})
		if e:
			e.alert(lz)
	main.hud.add_feed("ENEMY QRF INBOUND  ·  HOLD THE LZ", Color(1.0, 0.45, 0.35))


func _spawn_heli() -> void:
	_heli = Node3D.new()
	main.add_child(_heli)
	var dark := M.painted_metal("heli", Color(0.2, 0.24, 0.18))
	var glass := M.solid(Color(0.1, 0.13, 0.16), 0.1, 0.5)
	var parts := [
		[ML.capsule(1.1, 4.8), dark, Vector3(0, 1.2, 0), Vector3(PI * 0.5, 0, 0), Vector3.ONE],
		[ML.box(Vector3(0.5, 0.6, 5.0)), dark, Vector3(0, 1.6, 4.6), Vector3.ZERO, Vector3.ONE],
		[ML.box(Vector3(0.1, 1.4, 0.9)), dark, Vector3(0, 2.2, 7.0), Vector3.ZERO, Vector3.ONE],
		[ML.sphere(0.9, false, 12), glass, Vector3(0, 1.4, -1.9), Vector3.ZERO, Vector3(1, 0.8, 1)],
		[ML.box(Vector3(0.12, 0.12, 3.2)), _metal(), Vector3(-0.9, 0.1, 0), Vector3.ZERO, Vector3.ONE],
		[ML.box(Vector3(0.12, 0.12, 3.2)), _metal(), Vector3(0.9, 0.1, 0), Vector3.ZERO, Vector3.ONE],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = p[1]
		mi.position = p[2]
		mi.rotation = p[3]
		mi.scale = p[4]
		_heli.add_child(mi)
	_heli_rotor = Node3D.new()
	_heli_rotor.position = Vector3(0, 2.55, 0)
	_heli.add_child(_heli_rotor)
	for k in 4:
		var blade := MeshInstance3D.new()
		blade.mesh = ML.box(Vector3(0.3, 0.04, 6.2))
		blade.material_override = M.solid(Color(0.1, 0.1, 0.1), 0.7)
		blade.position = Basis(Vector3.UP, k * PI * 0.5) * Vector3(0, 0, 3.1)
		blade.rotation.y = k * PI * 0.5
		_heli_rotor.add_child(blade)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 0.4, -1.5)
	spot.rotation.x = -1.2
	spot.spot_range = 40.0
	spot.spot_angle = 18.0
	spot.light_energy = 6.0
	_heli.add_child(spot)
	_heli.position = level.lz_north + Vector3(-60, 40, 60)
	_heli.visible = false
	# green smoke + flare on the pad
	_flare = Node3D.new()
	main.add_child(_flare)
	_flare.global_position = level.lz_north + Vector3(2, 0.1, 2)
	var smoke := CPUParticles3D.new()
	smoke.amount = 40
	smoke.lifetime = 5.0
	smoke.mesh = ML.sphere(0.5, false, 6)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.4, 0.95, 0.45, 0.35)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.material_override = sm
	smoke.direction = Vector3.UP
	smoke.spread = 15.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.4
	smoke.gravity = Vector3(0.3, 0.2, 0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 3.0
	_flare.add_child(smoke)
	var gl := OmniLight3D.new()
	gl.light_color = Color(0.3, 1.0, 0.4)
	gl.light_energy = 2.0
	gl.omni_range = 7.0
	gl.position.y = 0.5
	_flare.add_child(gl)


func _metal() -> Material:
	return M.solid(Color(0.15, 0.16, 0.15), 0.5, 0.6)


func _update_heli(delta: float) -> void:
	if _heli == null:
		return
	_heli_rotor.rotate_y(delta * 28.0)
	var o := current()
	var remaining := hold_timer if (not o.is_empty() and String(o.kind) == "hold") else 0.0
	var lz: Vector3 = level.lz_north
	if remaining < 22.0:
		_heli.visible = true
		var k := clampf(1.0 - remaining / 22.0, 0.0, 1.0)
		var approach := lz + Vector3(-60, 40, 60)
		var hover := lz + Vector3(0, 12, 0)
		var target: Vector3
		if k < 0.7:
			target = approach.lerp(hover, smoothstep(0.0, 0.7, k))
		else:
			target = hover.lerp(lz + Vector3(0, 0.2, 0), smoothstep(0.7, 1.0, k))
		_heli.global_position = _heli.global_position.lerp(target, 1.0 - exp(-3.0 * delta))
		var dir := lz - approach
		_heli.rotation.y = atan2(dir.x, dir.z) + PI
