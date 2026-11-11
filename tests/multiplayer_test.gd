extends SceneTree
## Two-process multiplayer check (run the host first, then the client):
##   godot --headless --path . -s res://tests/multiplayer_test.gd -- host coop
##   godot --headless --path . -s res://tests/multiplayer_test.gd -- client coop
## Checks joining, movement sync, client damage on host AI (coop) and
## host damage on the client's operator (pvp: use "pvp" on both).
## Optional 3rd arg: host "ws" (local WebSocket) / "funnel" (Tailscale Funnel);
## client <address> e.g. ws://127.0.0.1:7778 or wss://<pc>.<tailnet>.ts.net:10000
const Net = preload("res://scripts/net/net.gd")
var role := ""
var kind := ""
var f := 0
var port := 7791
var start_pos := Vector3.ZERO
var target_name := ""
var t0 := -1
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	kind = a[1]
	var ms = load("res://scripts/main.gd")
	ms.saved_quality = 0
	var via := String(a[2]) if a.size() > 2 else ""
	if role == "host":
		Net.player_name = "HOSTY"
		if via == "ws":
			# WebSocket transport without publishing it (local test)
			var wp := WebSocketMultiplayerPeer.new()
			print("ws host err=", wp.create_server(Net.WS_PORT))
			Net.leave()
			Engine.get_main_loop().get_multiplayer().multiplayer_peer = wp
			Net.transport = "ws"
			Net.kind = kind
			Net.active = true
			Net.roster = {1: {"name": "HOSTY", "loadout": []}}
		else:
			print("host err=", Net.host(kind, port, via == "funnel"))
		ms.saved_mode = "pvp" if kind == "pvp" else "ch1"
		ms.quick_restart = true
	else:
		Net.player_name = "CLIENTY"
		ms.saved_mode = "ch1"
		ms.quick_restart = false
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	if role == "client":
		print("join err=", Net.join(via if via != "" else "127.0.0.1", port))
func _physics_process(_d: float) -> bool:
	f += 1
	var m = current_scene
	if m == null or not m.has_method("alive_players") or m.player == null:
		return false
	if role == "host" and Net.transport == "ws" and f % 60 == 0 and (Net.funnel_url != "" or Net.funnel_error != ""):
		print("[host] funnel url=", Net.funnel_url, " err=", Net.funnel_error)
	if f % 150 == 0:
		print("[%s] t=%d active=%s mode=%s players=%s alive_enemies=%d hp=%.0f" % [role, f / 60, Net.active, m.mode, m.players.keys(), m.enemies_alive(), m.player.health])
	var others0: Array = m.players.keys().filter(func(k): return k != Net.my_id())
	if t0 < 0 and Net.active and not others0.is_empty():
		t0 = f
		print("[%s] in session at t=%d" % [role, f / 60])
	if t0 < 0:
		return f > 3000
	var r := f - t0
	if role == "client":
		if r == 60:
			start_pos = m.player.global_position
			Input.action_press("move_forward")
		if r == 180:
			Input.action_release("move_forward")
			print("[client] moved %.2f m locally" % m.player.global_position.distance_to(start_pos))
		if r == 240 and kind == "coop":
			var best = null
			for e in m.enemies:
				if not e.is_dead and (best == null or e.global_position.distance_to(m.player.global_position) < best.global_position.distance_to(m.player.global_position)):
					best = e
			if best:
				target_name = String(best.name)
				print("[client] shooting puppet ", target_name, " puppet=", best.puppet, " hp=", best.health)
				best.apply_damage(400.0, best.global_position + Vector3(0, 1.0, 0), Vector3.FORWARD, m.player)
		if r == 360 and target_name != "":
			var e = m.get_node_or_null(target_name)
			print("[client] ", target_name, " dead on client=", e.is_dead if e else "missing")
	else:
		var others: Array = m.players.keys().filter(func(k): return k != 1)
		if others.is_empty():
			return false
		var pup = m.players[others[0]]
		if r == 30:
			start_pos = pup.global_position
		if r == 240:
			print("[host] client puppet %s moved %.2f m on host, puppet=%s tag=%s" % [pup.name, pup.global_position.distance_to(start_pos), pup.puppet, pup.display_name])
		if r == 260 and kind == "pvp":
			print("[host] hitting client puppet, team host=%d client=%d" % [m.player.team, pup.team])
			pup.apply_damage(30.0, pup.global_position + Vector3(0, 1.0, 0), Vector3.FORWARD, m.player)
		if r == 380 and kind == "coop":
			var dead := []
			for e in m.enemies:
				if e.is_dead:
					dead.append(String(e.name))
			print("[host] dead enemies on host: ", dead)
	if r == (480 if role == "client" else 560):
		print("[%s] final hp=%.0f players=%s" % [role, m.player.health, m.players.keys()])
		Net.leave()   # also removes a Funnel mapping
		return true
	return false
