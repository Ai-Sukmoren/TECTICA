extends SceneTree
## Two-process check that a friend can join with nothing but a join code,
## and lands on the host's map (run the host first, then the client):
##   godot --headless --path . -s res://tests/join_code_e2e.gd -- host
##   godot --headless --path . -s res://tests/join_code_e2e.gd -- client
## Uses this PC's loopback address, so the code is the 7-character kind.
const Net = preload("res://scripts/net/net.gd")
const Main = preload("res://scripts/main.gd")
var role := ""
var t := 0.0
var done := false

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	load("res://scripts/core/profile.gd").current = "host_test" if role == "host" else "client_test"
	if role == "host":
		Net.player_name = "HOSTY"
		Main.saved_mode = "zombie"
		Main.saved_map = "town"
		Main.quick_restart = true
		print("[e2e] host err=%d code=%s" % [Net.host("coop", Net.DEFAULT_PORT), Net.join_code("127.0.0.1")])
	else:
		Net.player_name = "CLIENTY"
		Main.saved_mode = "ch1"
		Main.quick_restart = false
	change_scene_to_file("res://scenes/main.tscn")

func _process(delta: float) -> bool:
	t += delta
	var main = current_scene
	if main == null or done:
		return false
	if role == "client" and t > 1.5 and not Net.active and Net.status == "":
		var code := Net.join_code("127.0.0.1")
		var inv := Net.parse_invite(code)   # exactly what the JOIN row does with typed text
		print("[e2e] client typed %s -> %s:%d" % [code, inv[0], inv[1]])
		Net.join(String(inv[0]), int(inv[1]))
	var n: int = main.players.size() if main.get("players") != null else 0
	if Net.active and n >= 2:
		done = true
		print("[e2e] %s PASS  players=%d  map=%s  mode=%s" % [role, n, main.map_id, main.mode])
		create_timer(1.5, true, false, true).timeout.connect(func(): Net.leave(); quit(0))
	elif t > 45.0:
		done = true
		print("[e2e] %s FAIL  timeout  active=%s players=%d status=%s" % [role, Net.active, n, Net.status])
		Net.leave()
		quit(1)
	return false
