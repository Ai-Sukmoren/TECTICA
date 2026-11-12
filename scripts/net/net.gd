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


## Accepts a join code ("K7M2Q"), "tectica://join/1.2.3.4:7777", "1.2.3.4:7777" or "1.2.3.4".
## Returns [ip, port] or [] if it isn't usable.
static func parse_invite(text: String) -> Array:
	var s := text.strip_edges()
	var coded := decode_code(s)
	if coded != "":
		return [coded, DEFAULT_PORT]   # a join code
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
## ---- join codes: a short code a friend can type instead of an address.
## There is no lobby server, so the code IS the host's address, packed:
##   5 characters  any private address (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
##                 or Tailscale address (100.64-127.x.x), on the default port
##   7 characters  any public IPv4 address (the host still needs UDP 7777 forwarded)
## The alphabet has no 0/O or 1/I, and codes are scrambled so neighbours on
## one network don't get near-identical codes.
const CODE_ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const _C5_BITS := 25
const _C5_MUL := 0x12D687B
const _C5_INV := 0xC236B3
const _C5_ADD := 0x0A5C3E1
const _C7_BITS := 35
const _C7_MUL := 0x1873593
const _C7_INV := 0x660ED309B
const _C7_ADD := 0x2F1B7A6D5
# private ranges packed back to back: [first octet, low second octet, count of second octets, bits below]
const _RANGES := [[10, 0, 256, 16], [100, 64, 64, 16], [172, 16, 16, 16], [192, 168, 1, 16]]


static func _octets(ip: String) -> Array:
	var parts := ip.strip_edges().split(".")
	if parts.size() != 4:
		return []
	var out: Array = []
	for p in parts:
		if not p.is_valid_int() or int(p) < 0 or int(p) > 255:
			return []
		out.append(int(p))
	return out


## Position of a private / Tailscale address in the packed ranges, or -1.
static func _private_index(o: Array) -> int:
	var base := 0
	for r in _RANGES:
		var span: int = int(r[2]) << int(r[3])
		if o[0] == r[0] and o[1] >= r[1] and o[1] < int(r[1]) + int(r[2]):
			return base + ((o[1] - int(r[1])) << 16) + (o[2] << 8) + o[3]
		base += span
	return -1


static func _private_total() -> int:
	var n := 0
	for r in _RANGES:
		n += int(r[2]) << int(r[3])
	return n


static func _to_text(v: int, chars: int) -> String:
	var s := ""
	for i in chars:
		s = CODE_ALPHABET[v & 31] + s
		v >>= 5
	return s


static func _from_text(s: String) -> int:
	var v := 0
	for ch in s:
		var i := CODE_ALPHABET.find(ch)
		if i < 0:
			return -1
		v = (v << 5) | i
	return v


## Join code for an address on `p_port`, or "" when it cannot be coded
## (custom port, Tailscale Funnel link, not an IPv4 address).
static func join_code(ip: String, p_port: int = DEFAULT_PORT) -> String:
	if p_port != DEFAULT_PORT or is_ws_address(ip):
		return ""
	var o := _octets(ip)
	if o.is_empty():
		return ""
	var idx := _private_index(o)
	if idx >= 0:
		var mask5 := (1 << _C5_BITS) - 1
		return _to_text((idx * _C5_MUL + _C5_ADD) & mask5, 5)
	var full: int = (o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3]
	var mask7 := (1 << _C7_BITS) - 1
	return _to_text((full * _C7_MUL + _C7_ADD) & mask7, 7)


## The address behind a join code ("" if it is not a valid code).
static func decode_code(text: String) -> String:
	var s := text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if s.length() == 5:
		var v := _from_text(s)
		if v < 0:
			return ""
		var mask5 := (1 << _C5_BITS) - 1
		var idx := ((v - _C5_ADD) * _C5_INV) & mask5
		if idx >= _private_total():
			return ""
		for r in _RANGES:
			var span: int = int(r[2]) << int(r[3])
			if idx < span:
				return "%d.%d.%d.%d" % [int(r[0]), int(r[1]) + (idx >> 16), (idx >> 8) & 255, idx & 255]
			idx -= span
		return ""
	if s.length() == 7:
		var v7 := _from_text(s)
		if v7 < 0:
			return ""
		var mask7 := (1 << _C7_BITS) - 1
		var full := ((v7 - _C7_ADD) * _C7_INV) & mask7
		if full >= (1 << 32) or (full >> 24) == 0:
			return ""
		return "%d.%d.%d.%d" % [(full >> 24) & 255, (full >> 16) & 255, (full >> 8) & 255, full & 255]
	return ""


## Addresses friends can reach this PC on: [{"label", "ip", "code"}], the real
## Wi-Fi / Ethernet adapter first, then Tailscale. Virtual adapters (WSL,
## Hyper-V, VirtualBox, VMware) are skipped: nobody outside this PC can use them.
static func host_addresses() -> Array:
	var lan := ""
	var lan_rank := 99
	var tail := ""
	for iface in IP.get_local_interfaces():
		var nm := (String(iface.get("friendly", "")) + " " + String(iface.get("name", ""))).to_lower()
		var virtual_adapter := false
		for bad in ["vethernet", "wsl", "hyper-v", "virtualbox", "vmware", "loopback", "bluetooth", "docker", "npcap"]:
			if nm.find(bad) >= 0:
				virtual_adapter = true
		for a in iface.get("addresses", []):
			var o := _octets(String(a))
			if o.is_empty() or o[0] == 127 or (o[0] == 169 and o[1] == 254):
				continue
			if o[0] == 100 and o[1] >= 64 and o[1] < 128:
				tail = String(a)
			elif not virtual_adapter and _private_index(o) >= 0:
				var rank := 0 if o[0] == 192 else (1 if o[0] == 10 else 2)
				if rank < lan_rank:
					lan_rank = rank
					lan = String(a)
	var out: Array = []
	if lan != "":
		out.append({"label": "WI-FI / LAN", "ip": lan, "code": join_code(lan, port)})
	if tail != "":
		out.append({"label": "TAILSCALE", "ip": tail, "code": join_code(tail, port)})
	if out.is_empty():
		var fallback := lan_ip()
		out.append({"label": "LAN", "ip": fallback, "code": join_code(fallback, port)})
	return out
