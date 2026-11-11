extends RefCounted
## Local player accounts: a username + 4-digit PIN per player on this PC.
## Each account keeps its own credits, skins, loadouts and campaign grades in
## user://profiles/<name>/. PINs are never stored - only a salted, stretched
## SHA-256 hash. Five wrong PINs lock sign-in for 30 seconds.
## (Local only: there is no online account server.)

const ACCOUNTS := "user://accounts.cfg"
const PIN_LEN := 4
const MAX_TRIES := 5
const LOCK_SECONDS := 30.0
const HASH_ROUNDS := 2000
## progress files that live per account
const FILES := ["armory.cfg", "loadout.cfg", "campaign.cfg"]

## signed-in username ("" = nobody, files fall back to the shared user:// root)
static var current := ""
static var _fails := 0
static var _locked_until := 0.0


static func signed_in() -> bool:
	return current != ""


## Where a progress file lives for the signed-in account.
static func path(file: String) -> String:
	if current == "":
		return "user://" + file
	return "user://profiles/%s/%s" % [current.to_lower(), file]


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(ACCOUNTS)
	return cfg


## Usernames on this PC (display spelling), most recent first.
static func accounts() -> Array:
	var cfg := _cfg()
	var out: Array = []
	if cfg.has_section("users"):
		for k in cfg.get_section_keys("users"):
			var u: Dictionary = cfg.get_value("users", k, {})
			out.append([String(u.get("name", k)), float(u.get("last", 0.0))])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out.map(func(e): return e[0])


static func last_user() -> String:
	var a := accounts()
	return String(a[0]) if not a.is_empty() else ""


## "" when fine, otherwise the reason it isn't.
static func check_name(n: String) -> String:
	var s := n.strip_edges()
	if s.length() < 3 or s.length() > 16:
		return "USERNAME MUST BE 3-16 CHARACTERS"
	for ch in s:
		if not (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-"):
			return "USERNAME: LETTERS, NUMBERS, _ AND - ONLY"
	return ""


static func check_pin(pin: String) -> String:
	if pin.length() != PIN_LEN or not pin.is_valid_int():
		return "PASSWORD MUST BE EXACTLY %d DIGITS" % PIN_LEN
	return ""


static func _hash(pin: String, salt: String) -> String:
	var h := salt + ":" + pin
	for i in HASH_ROUNDS:
		h = (h + salt).sha256_text()
	return h


static func locked_seconds() -> int:
	return maxi(int(ceil(_locked_until - Time.get_ticks_msec() / 1000.0)), 0)


## Creates the account and signs in. Returns "" or an error message.
static func create(name: String, pin: String) -> String:
	var err := check_name(name)
	if err == "":
		err = check_pin(pin)
	if err != "":
		return err
	var key := name.strip_edges().to_lower()
	var cfg := _cfg()
	if cfg.has_section_key("users", key):
		return "THAT USERNAME IS TAKEN ON THIS PC"
	var first := not cfg.has_section("users") or cfg.get_section_keys("users").is_empty()
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	cfg.set_value("users", key, {"name": name.strip_edges(), "salt": salt, "hash": _hash(pin, salt),
			"created": Time.get_unix_time_from_system(), "last": Time.get_unix_time_from_system()})
	if cfg.save(ACCOUNTS) != OK:
		return "COULD NOT SAVE THE ACCOUNT"
	DirAccess.make_dir_recursive_absolute("user://profiles/" + key)
	if first:
		# the first account keeps the progress made before accounts existed
		for f in FILES:
			if FileAccess.file_exists("user://" + f):
				DirAccess.copy_absolute("user://" + f, "user://profiles/%s/%s" % [key, f])
	current = name.strip_edges()
	_fails = 0
	return ""


## Signs in. Returns "" or an error message.
static func sign_in(name: String, pin: String) -> String:
	var lock := locked_seconds()
	if lock > 0:
		return "TOO MANY WRONG PASSWORDS  ·  TRY AGAIN IN %d s" % lock
	var key := name.strip_edges().to_lower()
	var cfg := _cfg()
	if key == "" or not cfg.has_section_key("users", key):
		return "NO ACCOUNT CALLED %s  ·  CREATE IT FIRST" % name.strip_edges().to_upper()
	if check_pin(pin) != "":
		return check_pin(pin)
	var u: Dictionary = cfg.get_value("users", key)
	if _hash(pin, String(u.salt)) != String(u.hash):
		_fails += 1
		if _fails >= MAX_TRIES:
			_fails = 0
			_locked_until = Time.get_ticks_msec() / 1000.0 + LOCK_SECONDS
			return "TOO MANY WRONG PASSWORDS  ·  LOCKED FOR %d s" % int(LOCK_SECONDS)
		return "WRONG PASSWORD  ·  %d TRIES LEFT" % (MAX_TRIES - _fails)
	_fails = 0
	u.last = Time.get_unix_time_from_system()
	cfg.set_value("users", key, u)
	cfg.save(ACCOUNTS)
	DirAccess.make_dir_recursive_absolute("user://profiles/" + key)
	current = String(u.get("name", name.strip_edges()))
	return ""


static func sign_out() -> void:
	current = ""
