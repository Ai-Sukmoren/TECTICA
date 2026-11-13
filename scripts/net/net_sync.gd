extends Node
## All multiplayer traffic for one match. Lives at /root/Main/NetSync on every
## peer. Messages route through the host (star topology), and the host only
## sends to peers whose world has finished loading, so nobody receives
## traffic for nodes it doesn't have yet.
##
##   client -> host   c_*   (hello, ready, own operator state / events,
##                           damage on things it doesn't own, prop hits, input)
##   host -> clients  s_*   (welcome, world snapshot, other operators, AI
##                           snapshots + events, spawns, prop destruction,
##                           objective / wave / score events)

const Net = preload("res://scripts/net/net.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Grenade = preload("res://scripts/weapons/grenade.gd")

const PLAYER_DT := 1.0 / 30.0
const ENEMY_DT := 1.0 / 15.0
const SLOW_DT := 0.5
const READY_RETRY := 1.5

var main
## host: peers whose world is loaded and in sync
var ready_peers: Dictionary = {}
## client: waiting for the host's world snapshot
var awaiting_world := false
var _tp := 0.0
var _te := 0.0
var _ts := 0.0
var _retry := 0.0


func setup(p_main) -> void:
	main = p_main
	Net.sync = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mp := multiplayer
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connected_to_server.connect(_on_connected)
	mp.connection_failed.connect(_on_connection_failed)
	mp.server_disconnected.connect(_on_server_disconnected)
	if Net.active and not mp.is_server():
		awaiting_world = true
		_retry = 0.0


func _exit_tree() -> void:
	if Net.sync == self:
		Net.sync = null


func is_host() -> bool:
	return Net.active and multiplayer.is_server()


func _physics_process(delta: float) -> void:
	if not Net.active or main == null:
		return
	if awaiting_world:
		_retry -= delta
		if _retry <= 0.0:
			_retry = READY_RETRY
			c_ready.rpc_id(1, Net.default_name(), preload("res://scripts/characters/player.gd").net_loadout())
		return
	if main.player == null:
		return
	_tp += delta
	_te += delta
	_ts += delta
	if _tp >= PLAYER_DT:
		_tp = 0.0
		var pack: Array = main.player.net_pack()
		if multiplayer.is_server():
			for pid in ready_peers:
				s_pstate.rpc_id(pid, 1, pack)
		else:
			c_pstate.rpc_id(1, pack)
	if multiplayer.is_server():
		if _te >= ENEMY_DT:
			_te = 0.0
			_send_enemies()
		if _ts >= SLOW_DT:
			_ts = 0.0
			var st: Dictionary = main.net_slow_state()
			for pid in ready_peers:
				s_slow.rpc_id(pid, st)


static func _clean_name(n: String, id: int) -> String:
	var s := n.strip_edges().to_upper()
	var out := ""
	for ch in s:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) < 127:
			out += ch
	out = out.substr(0, 16)
	return out if out != "" else "PLAYER %d" % id


# ================================================================ connection

func _on_connected() -> void:
	Net.status = "CONNECTED  ·  JOINING ..."
	c_hello.rpc_id(1, Net.default_name())


func _on_connection_failed() -> void:
	Net.leave()
	Net.status = "CONNECTION FAILED  ·  CHECK THE IP / PORT"


func _on_server_disconnected() -> void:
	var was := Net.active
	Net.leave()
	Net.status = "HOST LEFT THE GAME"
	if was and main != null:
		main.leave_to_title()


func _on_peer_connected(_id: int) -> void:
	pass   # the newcomer introduces itself with c_hello


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or main == null:
		return
	var nm := String(Net.roster.get(id, {}).get("name", "PLAYER"))
	Net.roster.erase(id)
	ready_peers.erase(id)
	main.remove_remote_player(id)
	main.feed(nm + " LEFT", "dim")
	for pid in ready_peers:
		s_player_left.rpc_id(pid, id, nm)
	main.net_check_all_down()


@rpc("any_peer", "call_remote", "reliable")
func c_hello(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	Net.roster[id] = {"name": _clean_name(pname, id), "loadout": []}
	s_welcome.rpc_id(id, Net.kind, main.mode_token())


@rpc("authority", "call_remote", "reliable")
func s_welcome(kind: String, mode: String) -> void:
	Net.active = true
	Net.kind = kind
	Net.status = "JOINED"
	main.net_enter_world(mode)


@rpc("any_peer", "call_remote", "reliable")
func c_ready(pname: String, loadout: Array) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var info := {"name": _clean_name(pname, id), "loadout": loadout}
	Net.roster[id] = info
	var spawn: Array
	if ready_peers.has(id) and main.players.has(id) and is_instance_valid(main.players[id]):
		var p = main.players[id]
		spawn = [p.global_position, p.aim_yaw]   # duplicate request: resend the world only
	else:
		spawn = main.net_spawn_for(id)
		main.add_remote_player(id, info, spawn[0], spawn[1])
		for pid in ready_peers:
			s_player_joined.rpc_id(pid, id, info, spawn[0], spawn[1])
		main.feed(String(info.name) + " JOINED", "good")
	var players := []
	for pid in main.players:
		var p = main.players[pid]
		if pid == id or not is_instance_valid(p):
			continue
		players.append([pid, Net.roster.get(pid, {"name": "PLAYER", "loadout": []}), p.global_position, p.aim_yaw, p.is_dead])
	s_world.rpc_id(id, {"spawn": spawn, "players": players, "state": main.net_world_state()})
	ready_peers[id] = true


@rpc("authority", "call_remote", "reliable")
func s_world(data: Dictionary) -> void:
	if not awaiting_world:
		return
	awaiting_world = false
	main.net_apply_world(data)


@rpc("authority", "call_remote", "reliable")
func s_player_joined(id: int, info: Dictionary, pos: Vector3, yaw: float) -> void:
	if id == Net.my_id():
		return
	main.add_remote_player(id, info, pos, yaw)
	main.feed(String(info.get("name", "PLAYER")) + " JOINED", "good")


@rpc("authority", "call_remote", "reliable")
func s_player_left(id: int, nm: String) -> void:
	main.remove_remote_player(id)
	main.feed(nm + " LEFT", "dim")


# ================================================================ operators

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_pstate(pack: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not ready_peers.has(id):
		return
	var p = main.players.get(id)
	if p != null and is_instance_valid(p) and p.puppet:
		p.net_apply(pack)
	for pid in ready_peers:
		if pid != id:
			s_pstate.rpc_id(pid, id, pack)


@rpc("authority", "call_remote", "unreliable_ordered")
func s_pstate(id: int, pack: Array) -> void:
	var p = main.players.get(id)
	if p != null and is_instance_valid(p) and p.puppet:
		p.net_apply(pack)


## Something this peer simulates did something everyone should see.
func send_event(node: Node, kind: String, args: Array = []) -> void:
	if not Net.active or node == null:
		return
	if multiplayer.is_server():
		for pid in ready_peers:
			s_event.rpc_id(pid, String(node.name), kind, args)
	elif not awaiting_world:
		c_event.rpc_id(1, String(node.name), kind, args)


@rpc("any_peer", "call_remote", "reliable")
func c_event(nm: String, kind: String, args: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	var node: Node = main.get_node_or_null(nm)
	# only an entity's owner may drive it
	if node == null or int(node.get("net_owner") if node.get("net_owner") != null else 1) != id:
		return
	_apply_event(node, kind, args)
	for pid in ready_peers:
		if pid != id:
			s_event.rpc_id(pid, nm, kind, args)


@rpc("authority", "call_remote", "reliable")
func s_event(nm: String, kind: String, args: Array) -> void:
	var node: Node = main.get_node_or_null(nm)
	if node != null:
		_apply_event(node, kind, args)


func _apply_event(node: Node, kind: String, args: Array) -> void:
	if not node.get("puppet"):
		return
	match kind:
		"shot":
			node.net_shot(args[0])
			main.on_remote_shot(node, args[0])
		"reload":
			node.rig.play_reload(float(args[0]), bool(args[1]))
		"switch":
			node.net_switch(int(args[0]))
		"throw":
			node.throwing = 0.7
			node.rig.play_throw(0.7)
		"grenade":
			spawn_grenade(node, args[0], args[1], args[2], true, String(args[3]) if args.size() > 3 else "frag")
		"vault":
			node.rig.play_vault(float(args[0]), float(args[1]), args[2])
		"attack":
			if node.has_method("play_attack_anim"):
				node.play_attack_anim(float(args[0]))
			else:
				node.rig.play_attack(float(args[0]))
		"kick":
			node.rig.play_kick(float(args[0]))
		"helmet":
			node.knock_off_helmet(args[0])
		"boss":
			if node.has_method("net_boss"):
				node.net_boss(args)
		"die":
			node.net_die(args[0], String(args[1]), bool(args[2]))
		"respawn":
			main.respawn_remote(node, args[0], float(args[1]))
		"sever":
			if node.has_method("net_sever"):
				node.net_sever(String(args[0]), String(args[1]), args[2])
		"loadout":
			# zombie shop purchase: show the new gun and remember it for respawns / late joiners
			var pack: Array = args[0]
			var specs: Array = pack.filter(func(s): return not (s is Dictionary))
			if not specs.is_empty():
				node.set_loadout(specs)
			var info: Dictionary = node.get_meta("info", {"name": node.display_name})
			info["loadout"] = pack
			node.set_meta("info", info)
			var id := int(node.get("net_owner"))
			if multiplayer.is_server() and Net.roster.has(id):
				Net.roster[id]["loadout"] = pack


func spawn_grenade(thrower: Node, pos: Vector3, vel: Vector3, ang: Vector3, cosmetic: bool, kind: String = "frag") -> void:
	var g := Grenade.new()
	g.thrower = thrower
	g.cosmetic = cosmetic
	g.kind = kind
	main.add_child(g)
	g.global_position = pos
	g.linear_velocity = vel
	g.angular_velocity = ang
	g.reset_physics_interpolation()


# ================================================================ damage

## `target` belongs to another peer: its owner applies the damage.
func send_damage(target: Node, amount: float, pos: Vector3, dir: Vector3, attacker: Node) -> void:
	var an := String(attacker.name) if is_instance_valid(attacker) else ""
	if multiplayer.is_server():
		var owner_id := int(target.get("net_owner"))
		if ready_peers.has(owner_id):
			s_damage.rpc_id(owner_id, String(target.name), amount, pos, dir, an)
	elif not awaiting_world:
		c_damage.rpc_id(1, String(target.name), amount, pos, dir, an)


@rpc("any_peer", "call_remote", "reliable")
func c_damage(nm: String, amount: float, pos: Vector3, dir: Vector3, an: String) -> void:
	var t = main.get_node_or_null(nm)
	if t == null or t.get("is_dead") == true:
		return
	var attacker: Node = main.get_node_or_null(an) if an != "" else null
	if Net.owns(t):
		t.apply_damage(amount, pos, dir, attacker)
	else:
		var owner_id := int(t.get("net_owner"))
		if ready_peers.has(owner_id):
			s_damage.rpc_id(owner_id, nm, amount, pos, dir, an)


@rpc("authority", "call_remote", "reliable")
func s_damage(nm: String, amount: float, pos: Vector3, dir: Vector3, an: String) -> void:
	var t = main.get_node_or_null(nm)
	if t != null and Net.owns(t) and t.get("is_dead") == false:
		t.apply_damage(amount, pos, dir, main.get_node_or_null(an) if an != "" else null)


## Kick knockback on a body another peer simulates.
func send_knock(target: Node, v: Vector3) -> void:
	if multiplayer.is_server():
		var owner_id := int(target.get("net_owner"))
		if ready_peers.has(owner_id):
			s_knock.rpc_id(owner_id, String(target.name), v)
	elif not awaiting_world:
		c_knock.rpc_id(1, String(target.name), v)


@rpc("any_peer", "call_remote", "reliable")
func c_knock(nm: String, v: Vector3) -> void:
	var t = main.get_node_or_null(nm)
	if t == null or t.get("is_dead") == true or v.length() > 30.0:
		return
	if Net.owns(t):
		t.apply_knockback(v)
	else:
		var owner_id := int(t.get("net_owner"))
		if ready_peers.has(owner_id):
			s_knock.rpc_id(owner_id, nm, v)


@rpc("authority", "call_remote", "reliable")
func s_knock(nm: String, v: Vector3) -> void:
	var t = main.get_node_or_null(nm)
	if t != null and Net.owns(t) and t.get("is_dead") == false:
		t.apply_knockback(v)


# ================================================================ props

func send_prop(prop: Node, kind: String, amount: float, a: Vector3, b: Vector3) -> void:
	if awaiting_world:
		return
	c_prop.rpc_id(1, int(prop.net_id), kind, amount, a, b)


@rpc("any_peer", "call_remote", "reliable")
func c_prop(id: int, kind: String, amount: float, a: Vector3, b: Vector3) -> void:
	var p = main.level.prop_by_id(id)
	if p == null or p.destroyed:
		return
	if kind == "hit":
		p.apply_damage(amount, a, b, null)
	else:
		p.apply_blast(amount, a)


func send_prop_destroyed(prop: Node, origin: Vector3, dir: Vector3, blast: bool) -> void:
	for pid in ready_peers:
		s_prop_destroy.rpc_id(pid, int(prop.net_id), origin, dir, blast)


@rpc("authority", "call_remote", "reliable")
func s_prop_destroy(id: int, origin: Vector3, dir: Vector3, blast: bool) -> void:
	var p = main.level.prop_by_id(id)
	if p != null and not p.destroyed:
		p.destroy(origin, dir, blast)


# ================================================================ AI

func _send_enemies() -> void:
	var arr := []
	for e in main.enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		var f := (1 if e.crouching else 0) | (2 if e.aiming else 0) | (4 if e.sprinting else 0)
		if e.get("enraged") == true:
			f |= 8
		var st = e.get("state")
		arr.append([String(e.name), e.global_position, e.velocity, e.aim_yaw, f,
				int(st) if st != null else 0, float(e.awareness), float(e.alert_flash)])
	if arr.is_empty():
		return
	# keep each packet under the MTU (unreliable fragments are dropped as a whole)
	for i in range(0, arr.size(), 8):
		var chunk := arr.slice(i, i + 8)
		for pid in ready_peers:
			s_enemies.rpc_id(pid, chunk)


@rpc("authority", "call_remote", "unreliable_ordered")
func s_enemies(arr: Array) -> void:
	for it in arr:
		var e = main.get_node_or_null(String(it[0]))
		if e != null and e.puppet and not e.is_dead:
			e.net_target(it[1], it[2], float(it[3]), int(it[4]), int(it[5]), float(it[6]), float(it[7]))


func send_spawn_enemy(e: Node, data: Dictionary, variant: int) -> void:
	for pid in ready_peers:
		s_spawn_enemy.rpc_id(pid, String(e.name), data.pos, float(data.get("yaw", 0.0)), String(data.get("group", "")), variant)


@rpc("authority", "call_remote", "reliable")
func s_spawn_enemy(nm: String, pos: Vector3, yaw: float, group: String, variant: int) -> void:
	if main.get_node_or_null(nm) == null:
		main.spawn_enemy({"pos": pos, "yaw": yaw, "patrol": [], "group": group}, nm, variant)


func send_spawn_zombie(z: Node, args: Array) -> void:
	for pid in ready_peers:
		s_spawn_zombie.rpc_id(pid, String(z.name), z.global_position, args)


@rpc("authority", "call_remote", "reliable")
func s_spawn_zombie(nm: String, pos: Vector3, args: Array) -> void:
	if main.get_node_or_null(nm) == null and main.director != null:
		main.director.spawn_puppet(nm, pos, args)


# ================================================================ game flow

func game_event(kind: String, args: Array = []) -> void:
	if not is_host():
		return
	for pid in ready_peers:
		s_game.rpc_id(pid, kind, args)


@rpc("authority", "call_remote", "reliable")
func s_game(kind: String, args: Array) -> void:
	main.net_game_event(kind, args)


func client_game(kind: String, args: Array = []) -> void:
	if Net.active and not multiplayer.is_server() and not awaiting_world:
		c_game.rpc_id(1, kind, args)


@rpc("any_peer", "call_remote", "reliable")
func c_game(kind: String, args: Array) -> void:
	if multiplayer.is_server():
		main.net_client_game(multiplayer.get_remote_sender_id(), kind, args)


@rpc("authority", "call_remote", "unreliable_ordered")
func s_slow(st: Dictionary) -> void:
	if not awaiting_world:
		main.net_apply_slow(st)
