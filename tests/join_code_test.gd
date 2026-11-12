extends SceneTree
## Join codes: every private / Tailscale address packs into 5 characters and
## back, public addresses into 7, typing variations are accepted, bad input is
## rejected, and links / plain addresses still parse.
##   godot --headless --path . -s res://tests/join_code_test.gd
const Net = preload("res://scripts/net/net.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	var private := ["192.168.1.23", "192.168.0.1", "192.168.255.255", "10.0.0.5", "10.255.255.255", "10.0.0.0",
			"172.16.0.1", "172.31.255.254", "100.64.0.1", "100.127.255.255", "100.101.102.103"]
	var bad := 0
	for ip in private:
		var code := Net.join_code(ip)
		if code.length() != 5 or Net.decode_code(code) != ip:
			bad += 1
			print("    %s -> %s -> %s" % [ip, code, Net.decode_code(code)])
	check(bad == 0, "home, office and Tailscale addresses make 5-character codes")
	print("    192.168.1.23 -> %s    10.0.0.5 -> %s    100.64.0.1 -> %s" % [Net.join_code("192.168.1.23"), Net.join_code("10.0.0.5"), Net.join_code("100.64.0.1")])

	var public := ["8.8.8.8", "203.0.113.77", "1.2.3.4", "255.255.255.254", "127.0.0.1", "172.32.0.1", "100.128.0.1", "192.169.0.1"]
	bad = 0
	for ip in public:
		var code := Net.join_code(ip)
		if code.length() != 7 or Net.decode_code(code) != ip:
			bad += 1
			print("    %s -> %s -> %s" % [ip, code, Net.decode_code(code)])
	check(bad == 0, "public addresses make 7-character codes")

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var seen := {}
	bad = 0
	for i in 20000:
		var ip := ""
		match i % 4:
			0: ip = "192.168.%d.%d" % [rng.randi() % 256, rng.randi() % 256]
			1: ip = "10.%d.%d.%d" % [rng.randi() % 256, rng.randi() % 256, rng.randi() % 256]
			2: ip = "172.%d.%d.%d" % [16 + rng.randi() % 16, rng.randi() % 256, rng.randi() % 256]
			3: ip = "100.%d.%d.%d" % [64 + rng.randi() % 64, rng.randi() % 256, rng.randi() % 256]
		var code := Net.join_code(ip)
		if Net.decode_code(code) != ip or (seen.has(code) and seen[code] != ip):
			bad += 1
		seen[code] = ip
	check(bad == 0, "20,000 random addresses round-trip with no two sharing a code")

	var code := Net.join_code("192.168.1.23")
	var only_safe := true
	for ch in code:
		if Net.CODE_ALPHABET.find(ch) < 0:
			only_safe = false
	check(only_safe and code.find("0") < 0 and code.find("O") < 0 and code.find("1") < 0 and code.find("I") < 0, "codes avoid 0/O and 1/I (%s)" % code)
	check(Net.decode_code(code.to_lower()) == "192.168.1.23", "lower case works")
	check(Net.decode_code(" " + code.substr(0, 2) + "-" + code.substr(2) + " ") == "192.168.1.23", "spaces and dashes are ignored")
	var differ := 0
	var next := Net.join_code("192.168.1.24")
	for i in 5:
		if code[i] != next[i]:
			differ += 1
	check(differ >= 2, "neighbouring PCs get clearly different codes (%s vs %s)" % [code, next])

	check(Net.decode_code("0O1I0") == "" and Net.decode_code("ABC") == "" and Net.decode_code("ABCDEFGH") == "" and Net.decode_code("") == "", "invalid codes are rejected")
	bad = 0
	for i in 5000:
		var junk := ""
		for k in 5:
			junk += Net.CODE_ALPHABET[rng.randi() % 32]
		var ip := Net.decode_code(junk)
		if ip != "" and Net.join_code(ip) != junk:
			bad += 1
	check(bad == 0, "a mistyped code either fails or maps to exactly one address")
	check(Net.join_code("192.168.1.23", 7780) == "", "custom ports have no code")
	check(Net.join_code("wss://pc.tail1234.ts.net:10000") == "", "Funnel links have no code")

	var inv := Net.parse_invite(code)
	check(inv.size() == 2 and String(inv[0]) == "192.168.1.23" and int(inv[1]) == Net.DEFAULT_PORT, "typing a code in JOIN resolves to the host")
	check(Net.parse_invite(code, 7790) == ["192.168.1.23", Net.DEFAULT_PORT], "a join code overrides a previously entered port")
	check(Net.parse_invite("100.64.0.5", 7790) == ["100.64.0.5", 7790], "a direct Tailscale IP uses the entered port")
	inv = Net.parse_invite("192.168.1.5")
	check(String(inv[0]) == "192.168.1.5" and int(inv[1]) == Net.DEFAULT_PORT, "plain addresses still work")
	inv = Net.parse_invite("tectica://join/10.0.0.9:7790")
	check(String(inv[0]) == "10.0.0.9" and int(inv[1]) == 7790, "invite links still work")
	inv = Net.parse_invite("pc.tail1234.ts.net")
	check(String(inv[0]).begins_with("wss://"), "Funnel addresses still work")
	check(Net.parse_invite("https://pc.tail1234.ts.net:10000/") == ["wss://pc.tail1234.ts.net:10000", 0], "HTTPS Funnel links use WebSocket")
	check(Net.parse_invite("tectica://join/wss://pc.tail1234.ts.net:10000") == ["wss://pc.tail1234.ts.net:10000", 0], "copied Funnel links use WebSocket")
	check(Net.parse_invite("https://example.com").is_empty(), "unrecognized URLs are rejected")

	var mine := Net.host_addresses()
	var good := not mine.is_empty()
	for a in mine:
		print("    this PC: %s  %s  code %s" % [a.label, a.ip, a.code])
		if String(a.code) != "" and Net.decode_code(String(a.code)) != String(a.ip):
			good = false
	check(good, "this PC's own codes point back to it")
	print("JOINCODE: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
