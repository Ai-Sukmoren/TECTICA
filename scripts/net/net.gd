extends RefCounted
## Multiplayer session state (survives scene reloads) and connection helpers.
##
## Topology: one host (peer 1) + up to 7 clients over ENet, joined by IP.
## The host is authoritative for AI, waves, campaign objectives and props;
## every peer simulates its own operator and owns that operator's health.
## Offline play leaves `active` false and everything behaves as before.

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 7

## "" offline, "coop" (campaign chapters / zombies together) or "pvp".
static var kind := ""
static var active := false
static var player_name := ""
static var join_ip := "127.0.0.1"
static var port := DEFAULT_PORT
static var status := ""          # last connection message for the menu
## peer id -> {"name": String, "loadout": Array}  (host keeps the full roster)
static var roster: Dictionary = {}
## The live NetSync node of the current match (null offline / between scenes).
static var sync: Node = null


static func _mp() -> MultiplayerAPI:
	return (Engine.get_main_loop() as SceneTree).get_multiplayer()


static func my_id() -> int:
	return _mp().get_unique_id() if active else 1


static func is_server() -> bool:
	return not active or _mp().is_server()


static func is_pvp() -> bool:
	return active and kind == "pvp"


## True when this peer simulates `node` (its own operator, or AI / props on the host).
static func owns(node: Object) -> bool:
	if not active or node == null:
		return true
	var o = node.get("net_owner")
	return int(o if o != null else 1) == my_id()


static func default_name() -> String:
	if player_name != "":
		return player_name
	var prof = preload("res://scripts/core/profile.gd")
	if prof.signed_in():
		return prof.current.to_upper()
	return "OPERATOR-%03d" % (randi() % 1000)


## ---- online hosting through Tailscale Funnel
## Funnel only relays TCP/HTTPS, so online games use a WebSocket transport:
## the host serves ws://127.0.0.1:WS_PORT and Funnel publishes it as
## wss://<machine>.<tailnet>.ts.net:FUNNEL_PORT. Friends need no Tailscale.
## Funnel allows public ports 443, 8443 and 10000; the game only ever adds /
## removes its own 10000 mapping and never touches the others.
const WS_PORT := 7778
const FUNNEL_PORT := 10000
## "enet" (direct UDP) or "ws" (WebSocket, used with Funnel)
static var transport := "enet"
static var funnel_url := ""
static var funnel_error := ""
static var funnel_active := false
static var _funnel_thread: Thread


static func tailscale_cli() -> String:
	for p in ["C:/Program Files/Tailscale/tailscale.exe", "/usr/bin/tailscale", "/usr/local/bin/tailscale",
			"/Applications/Tailscale.app/Contents/MacOS/Tailscale"]:
		if FileAccess.file_exists(p):
			return p
	return "tailscale"


static func is_ws_address(a: String) -> bool:
	var l := a.strip_edges().to_lower()
	return l.begins_with("ws://") or l.begins_with("wss://")


## Starts the Funnel mapping on a background thread (the CLI can take a moment).
static func funnel_start() -> void:
	funnel_url = ""
	funnel_error = ""
	_funnel_join()
	_funnel_thread = Thread.new()
	_funnel_thread.start(_funnel_job)


static func _funnel_job() -> void:
	var cli := tailscale_cli()
	var out: Array = []
	var code := OS.execute(cli, ["funnel", "--bg", "--https=%d" % FUNNEL_PORT, "http://127.0.0.1:%d" % WS_PORT], out, true)
	var text := "\n".join(out)
	if code != 0:
		if text.find("login.tailscale.com") >= 0:
			var i := text.find("https://login.tailscale.com")
			funnel_error = "ENABLE FUNNEL FOR THIS PC: " + text.substr(i).split("\n")[0].strip_edges()
		elif code == -1 or text.strip_edges() == "":
			funnel_error = "TAILSCALE NOT FOUND  ·  INSTALL IT AND SIGN IN"
		else:
			funnel_error = "FUNNEL FAILED: " + text.strip_edges().split("\n")[0].substr(0, 90)
		return
	funnel_active = true
	out.clear()
	OS.execute(cli, ["status", "--json"], out, true)
	var j = JSON.parse_string("\n".join(out))
	var dns := ""
	if j is Dictionary and j.has("Self"):
		dns = String(j.Self.get("DNSName", "")).trim_suffix(".")
	if dns == "":
		funnel_error = "FUNNEL ON, BUT COULD NOT READ THIS PC'S TAILSCALE NAME"
		return
	funnel_url = "wss://%s:%d" % [dns, FUNNEL_PORT]


static func _funnel_join() -> void:
	if _funnel_thread != null and _funnel_thread.is_started() and not _funnel_thread.is_alive():
		_funnel_thread.wait_to_finish()
		_funnel_thread = null


## Startup: clear a mapping left behind if the game crashed while hosting online
## (only the game's own port; runs in the background so launch isn't delayed).
static func funnel_cleanup_stale() -> void:
	if not FileAccess.file_exists(tailscale_cli()) or active:
		return
	_funnel_join()
	_funnel_thread = Thread.new()
	_funnel_thread.start(func():
		var out: Array = []
		OS.execute(tailscale_cli(), ["serve", "status", "--json"], out, true)
		if "
".join(out).find(":%d" % FUNNEL_PORT) >= 0 and "
".join(out).find("127.0.0.1:%d" % WS_PORT) >= 0:
			OS.execute(tailscale_cli(), ["funnel", "--https=%d" % FUNNEL_PORT, "off"], [], true))


## Waits for the short-lived helper threads (link registration, Funnel CLI)
## so none is destroyed while still running.
static func join_threads() -> void:
	for t in [_funnel_thread, _reg_thread]:
		if t != null and t.is_started():
			t.wait_to_finish()
	_funnel_thread = null


## Removes only the game's own Funnel mapping.
static func funnel_stop() -> void:
	_funnel_join()
	if not funnel_active:
		return
	funnel_active = false
	funnel_url = ""
	OS.execute(tailscale_cli(), ["funnel", "--https=%d" % FUNNEL_PORT, "off"], [], true)


## ---- invite links:  tectica://join/<ip>:<port>
const LINK_PREFIX := "tectica://join/"
## a link the game was launched with (clicked tectica:// link / --join argument)
static var pending_join := ""
static var public_ip := ""


static func invite_link(ip: String) -> String:
	if is_ws_address(ip):
		return LINK_PREFIX + ip
	return "%s%s:%d" % [LINK_PREFIX, ip, port]


## Accepts "tectica://join/1.2.3.4:7777", "1.2.3.4:7777" or "1.2.3.4".
## Returns [ip, port] or [] if it isn't usable.
static func parse_invite(text: String) -> Array:
	var s := text.strip_edges()
	if s.to_lower().begins_with("tectica://"):
		s = s.substr(10)
		if s.to_lower().begins_with("join/"):
			s = s.substr(5)
	s = s.trim_suffix("/")
	if s == "":
		return []
	if is_ws_address(s):
		return [s, 0]
	if s.to_lower().split(":")[0].ends_with(".ts.net"):
		# a bare Funnel address: wss on the game's Funnel port
		return ["wss://" + (s if s.count(":") == 1 else "%s:%d" % [s, FUNNEL_PORT]), 0]
	var p := DEFAULT_PORT
	var colon := s.rfind(":")
	if colon > 0 and s.count(":") == 1:
		var ps := s.substr(colon + 1)
		if ps.is_valid_int():
			p = clampi(int(ps), 1, 65535)
		s = s.substr(0, colon)
	return [s, p]


## This PC's address on the local network (what LAN friends join).
static func lan_ip() -> String:
	var best := ""
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
		if best == "":
			best = a
	return best if best != "" else "127.0.0.1"


## Launched by a clicked tectica:// link (or --join <link>)?
static func read_launch_link() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in args.size():
		var a := String(args[i])
		if a.to_lower().begins_with("tectica://"):
			pending_join = a
		elif a == "--join" and i + 1 < args.size():
			pending_join = String(args[i + 1])


static var _reg_thread: Thread


## Exported Windows builds register tectica:// (per user, no admin) so a
## clicked invite link opens the game and joins. Runs on a background thread
## and only when the entry is missing / points at another copy of the game,
## so it can never hold up startup.
static func register_link_handler() -> void:
	if not OS.has_feature("windows") or not OS.has_feature("template"):
		return
	if _reg_thread != null:
		return
	_reg_thread = Thread.new()
	_reg_thread.start(_register_job)


static func _register_job() -> void:
	var exe := OS.get_executable_path().replace("/", "\\")
	var base := "HKCU\\Software\\Classes\\tectica"
	var out: Array = []
	OS.execute("reg", ["query", base + "\\shell\\open\\command", "/ve"], out, true)
	if "\n".join(out).find(exe) >= 0:
		return   # already registered for this copy
	# every value is passed with /d and /f, so reg never stops to ask (Yes/No)
	OS.execute("reg", ["add", base, "/ve", "/d", "URL:TECTICA invite", "/f"], [], true)
	OS.execute("reg", ["add", base, "/v", "URL Protocol", "/t", "REG_SZ", "/d", "1", "/f"], [], true)
	# reg.exe needs the inner quotes escaped (\") so paths with spaces survive
	OS.execute("reg", ["add", base + "\\shell\\open\\command", "/ve", "/d", "\\\"" + exe + "\\\" \\\"%1\\\"", "/f"], [], true)


## `online` = WebSocket server published through Tailscale Funnel.
static func host(p_kind: String, p_port: int = DEFAULT_PORT, online: bool = false) -> int:
	leave()
	var err: int
	if online:
		var wp := WebSocketMultiplayerPeer.new()
		err = wp.create_server(WS_PORT)
		if err != OK:
			status = "HOST FAILED  ·  PORT %d IN USE?" % WS_PORT
			return err
		_mp().multiplayer_peer = wp
		transport = "ws"
		funnel_start()
	else:
		var peer := ENetMultiplayerPeer.new()
		err = peer.create_server(p_port, MAX_CLIENTS)
		if err != OK:
			status = "HOST FAILED  ·  PORT %d IN USE?" % p_port
			return err
		_mp().multiplayer_peer = peer
		transport = "enet"
	kind = p_kind
	port = p_port
	active = true
	roster = {1: {"name": default_name(), "loadout": []}}
	status = "HOSTING ON PORT %d" % p_port
	return OK


static func join(ip: String, p_port: int = DEFAULT_PORT) -> int:
	leave()
	if is_ws_address(ip):
		# online host (Tailscale Funnel / WebSocket)
		var wp := WebSocketMultiplayerPeer.new()
		var werr := wp.create_client(ip.strip_edges())
		if werr != OK:
			status = "COULD NOT CONNECT TO %s" % ip
			return werr
		_mp().multiplayer_peer = wp
		transport = "ws"
		join_ip = ip
		status = "CONNECTING TO %s ..." % ip
		return OK
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, p_port)
	if err != OK:
		status = "COULD NOT CONNECT TO %s" % ip
		return err
	_mp().multiplayer_peer = peer
	transport = "enet"
	join_ip = ip
	port = p_port
	# `active` turns on once the host welcomes us (NetSync)
	status = "CONNECTING TO %s:%d ..." % [ip, p_port]
	return OK


static func leave() -> void:
	funnel_stop()
	var mp := _mp()
	if mp.multiplayer_peer != null and not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer.close()
	mp.multiplayer_peer = OfflineMultiplayerPeer.new()
	active = false
	kind = ""
	roster = {}
