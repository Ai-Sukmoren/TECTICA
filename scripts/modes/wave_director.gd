extends Node
## Zombie Survival director: endless escalating waves, balanced by wave number
## with a mercy slow-down when the player is hurt. Between waves the player is
## healed and resupplied. The run ends when the player dies.
##
## Balance (wave n):
##   zombies per wave   6 + 4n
##   max alive          min(6 + 2n, 28)
##   spawn interval     max(0.35, 1.5 - 0.08n) s   (x1.6 when HP < 35)
##   health             60 * (1 + 0.18(n-1))       runner x0.8, brute x3
##   damage             8 + 1.2n                   brute x2
##   weighted roster and variant stats are defined in zombie_types.gd

const Types = preload("res://scripts/characters/zombie_types.gd")
const Zombie = preload("res://scripts/characters/zombie.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Net = preload("res://scripts/net/net.gd")
const Terrain = preload("res://scripts/world/terrain.gd")

static var best_wave := 0
static var best_score := 0

var main: Node
var wave := 0
var active := false
var timer := 6.0
var to_spawn := 0
var kills := 0
var headshots := 0
var score := 0
var _spawn_cd := 0.0
var _variant := 0


func setup(p_main: Node) -> void:
	main = p_main


func alive() -> int:
	var n := 0
	for e in main.enemies:
		if is_instance_valid(e) and not e.is_dead:
			n += 1
	return n


func remaining() -> int:
	return alive() + to_spawn


## Headshot bonus (kills themselves are counted from the zombie's died signal,
## so grenade kills count too).
func on_kill(headshot: bool) -> void:
	if headshot:
		headshots += 1
		score += 50


func _on_zombie_died(_z: Node) -> void:
	kills += 1
	score += 100


func on_player_died() -> void:
	best_wave = maxi(best_wave, wave - 1 if active else wave)
	best_score = maxi(best_score, score)


func _physics_process(delta: float) -> void:
	if main == null or main.game_over or not main._deployed:
		return
	_cleanup()
	if not Net.is_server():
		# clients mirror the host: countdown only, waves arrive as events
		if not active:
			timer = maxf(timer - delta, 0.0)
		return
	if not active:
		timer -= delta
		if timer <= 0.0:
			_begin_wave()
		return

	var max_alive := mini(6 + 2 * wave, 28)
	var interval := maxf(0.35, 1.5 - 0.08 * wave)
	for p in main.alive_players():
		if p.health < 35.0:
			interval *= 1.6
			break
	_spawn_cd -= delta
	if to_spawn > 0 and _spawn_cd <= 0.0 and alive() < max_alive:
		_spawn_cd = interval
		if _spawn_one():
			to_spawn -= 1
	if to_spawn == 0 and alive() == 0:
		_end_wave()


func _begin_wave() -> void:
	wave += 1
	active = true
	to_spawn = 6 + 4 * wave
	_spawn_cd = 0.5
	_announce_wave()
	if Net.sync:
		Net.sync.game_event("wave", ["begin", wave, to_spawn])


func _announce_wave() -> void:
	main.hud.add_feed("WAVE %d  ·  %d INFECTED INBOUND" % [wave, to_spawn], Color(1.0, 0.4, 0.3))
	main.hud.wave_banner("WAVE %d" % wave)
	match wave:
		3: main.hud.add_feed("CRAWLERS  ·  WATCH THE GROUND", Color(0.7, 0.9, 0.3))
		5: main.hud.add_feed("ARMORED  ·  AIM FOR HEAD OR FLANK", Color(0.6, 0.8, 1.0))
		6: main.hud.add_feed("BERSERKERS  ·  WOUNDED INFECTED ENRAGE", Color(1.0, 0.35, 0.12))


func _end_wave() -> void:
	active = false
	timer = 12.0
	score += wave * 250
	if Net.sync:
		Net.sync.game_event("wave", ["end", wave])
	apply_wave_end()


## Wave cleared: every peer heals / resupplies its own operator; a downed
## operator (multiplayer) gets back up for the next wave.
func apply_wave_end() -> void:
	var p = main.player
	if p.is_dead and Net.active:
		main.respawn_near_team()
		p = main.player
	p.health = minf(p.health + 35.0, p.max_health)
	for w in p.weapons:
		w.reserve = maxi(w.reserve, int(w.stats.reserve) * 2)
	main.refresh_ammo()
	p.grenades = mini(p.grenades + 2, 5)
	var cr := 20 * wave
	preload("res://scripts/skins/collection.gd").add_credits(cr)
	main.hud.add_feed("WAVE %d CLEARED  ·  +35 HP  ·  AMMO & FRAGS  ·  +%d CR" % [wave, cr], Color(0.55, 1.0, 0.6))
	main.hud.wave_banner("WAVE %d CLEARED" % wave)
	Sfx.play(main, "mag_in", p.global_position, 0.0)


## Host events on clients.
func net_event(args: Array) -> void:
	match String(args[0]):
		"begin":
			wave = int(args[1])
			to_spawn = int(args[2])
			active = true
			_announce_wave()
		"end":
			wave = int(args[1])
			active = false
			timer = 12.0
			apply_wave_end()


func net_state() -> Array:
	return [wave, active, timer, to_spawn, kills, score, headshots]


func apply_net_state(s: Array) -> void:
	wave = int(s[0])
	active = bool(s[1])
	timer = float(s[2])
	to_spawn = int(s[3])
	kills = int(s[4])
	score = int(s[5])
	headshots = int(s[6])


## A host-spawned zombie on a client.
func spawn_puppet(nm: String, pos: Vector3, args: Array) -> void:
	var z := Zombie.new()
	z.name = nm
	z.puppet = true
	main.add_child(z)
	z.global_position = pos
	z.init_zombie(main.player, String(args[0]), float(args[1]), float(args[2]), float(args[3]), int(args[4]))
	z.reset_physics_interpolation()
	main.enemies.append(z)


func _spawn_one() -> bool:
	var alive_ops: Array = main.alive_players()
	if alive_ops.is_empty():
		return false
	var player = alive_ops[randi() % alive_ops.size()]
	var level = main.level
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var map: RID = main.get_world_3d().navigation_map
	var eye: Vector3 = player.global_position + Vector3(0, 1.5, 0)
	var hidden: Array = []
	var visible: Array = []
	for sp in level.zombie_spawns:
		var p: Vector3 = sp
		var d := p.distance_to(player.global_position)
		if d < 11.0 or d > 45.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, p + Vector3(0, 1.2, 0), 1)
		if space.intersect_ray(q).is_empty():
			visible.append(p)
		else:
			hidden.append(p)
	var pool := hidden if not hidden.is_empty() else visible
	if pool.is_empty():
		return false
	var pos: Vector3 = pool[randi() % pool.size()] + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	pos = NavigationServer3D.map_get_closest_point(map, pos)
	pos.y = Terrain.height(pos.x, pos.z) + 0.05

	var kind := Types.pick(wave, randf())
	var stats := Types.stats(kind, wave)
	var hp: float = stats.hp
	var dmg: float = stats.damage
	var spd: float = stats.speed
	if kind == "walker":
		spd = minf(randf_range(1.4, 2.1) + 0.05 * wave, 2.7)

	var z := Zombie.new()
	z.name = "Zombie%d" % _variant
	main.add_child(z)
	z.global_position = pos
	z.init_zombie(player, kind, hp, spd, dmg, _variant)
	z.died.connect(_on_zombie_died)
	z.reset_physics_interpolation()
	if Net.active and Net.sync:
		var zargs := [kind, hp, spd, dmg, _variant]
		z.set_meta("net_extra", ["zombie", String(z.name), pos, zargs])
		Net.sync.send_spawn_zombie(z, zargs)
	_variant += 1
	main.enemies.append(z)
	return true


## Frees corpses after a while so long runs stay fast.
func _cleanup() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for e in main.enemies.duplicate():
		if not is_instance_valid(e):
			main.enemies.erase(e)
		elif e.is_dead and e.get("death_time") != null and e.death_time > 0.0 and now - e.death_time > 15.0:
			main.enemies.erase(e)
			e.queue_free()
