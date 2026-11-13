extends SceneTree
## Co-op Zombie Survival on every map: the Multiplayer panel offers each map,
## and a joining client loads the host's map. Run host first, then client:
##   godot --headless --path . -s res://tests/mp_zombie_maps_test.gd -- host town
##   godot --headless --path . -s res://tests/mp_zombie_maps_test.gd -- client town
const Net = preload("res://scripts/net/net.gd")
var role := ""
var map := ""
var f := 0
var port := 7793
var checked_menu := false

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	map = a[1] if a.size() > 1 else "town"
	var ms = load("res://scripts/main.gd")
	ms.saved_quality = 0
	if role == "host":
		Net.player_name = "HOSTY"
		print("host err=", Net.host("coop", port, false))
		ms.saved_mode = "zombie"
		ms.saved_map = map
		ms.quick_restart = true
	else:
		Net.player_name = "CLIENTY"
		ms.saved_mode = "ch1"
		ms.saved_map = "forest"
		ms.quick_restart = false
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	if role == "client":
		print("join err=", Net.join("127.0.0.1", port))

func _physics_process(_d: float) -> bool:
	f += 1
	var m = current_scene
	if m == null or not m.has_method("alive_players") or m.player == null:
		return false
	if role == "host" and not checked_menu:
		checked_menu = true
		var opts: Array = m.hud._mp_coop_options()
		print("[menu] co-op options=", opts)
		for id in m.MAPS.keys():
			var tok := "zombie" if id == "forest" else "zombie@" + String(id)
			print("[menu] %s offered=%s label=%s" % [tok, opts.has(tok), m.hud._mp_coop_label(tok)])
		print("[host] mode=%s map=%s token=%s" % [m.mode, m.map_id, m.mode_token()])
	if role == "client" and f % 60 == 0:
		print("[client] t=%d active=%s mode=%s map=%s" % [f / 60, Net.active, m.mode, m.map_id])
		if Net.active and m.mode == "zombie" and m.map_id == map:
			print("[client] PASS joined zombie on ", map)
			Net.leave()
			quit(0)
	if role == "client" and f > 60 * 40:
		print("[client] FAIL still mode=%s map=%s" % [m.mode, m.map_id])
		quit(1)
	if role == "host" and f > 60 * 45:
		Net.leave()
		quit(0)
	return false
