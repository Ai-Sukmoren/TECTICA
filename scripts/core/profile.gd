extends RefCounted
## Local player accounts: a username + 4-digit PIN per player on this PC.
## Each account keeps its own credits, skins, loadouts and campaign grades in
## user://profiles/<name>/. PINs are never stored - only a salted, stretched
## SHA-256 hash. Five wrong PINs lock sign-in for 30 seconds.
## (Local only: there is no online account server.)

const ACCOUNTS := "accounts.cfg"   # under _root()
const PIN_LEN := 4
const MAX_TRIES := 5
const LOCK_SECONDS := 30.0
const HASH_ROUNDS := 2000
## sign-in history kept for the admin dashboard (newest last, capped)
const LOGIN_LOG := "login_log.cfg"   # under _root()
const LOG_MAX := 400
## progress files that live per account
const FILES := ["armory.cfg", "loadout.cfg", "campaign.cfg"]

## signed-in username ("" = nobody, files fall back to the shared user:// root)
static var current := ""
## The no-password guest: plays at once, keeps its progress in profiles/guest/,
## and hands that progress to the account created when it signs out.
const GUEST := "Guest"
## Set when the guest signs out: the next account created takes over its progress.
static var _from_guest := false
static var _fails := 0
static var _locked_until := 0.0
static var _admin_for := "?"
static var _admin_val := false


static func signed_in() -> bool:
	return current != ""


static func is_guest() -> bool:
	return current == GUEST


## Signs in as the guest (no password). The first launch does this by itself.
static func play_as_guest() -> void:
	current = GUEST
	_fails = 0
	if not _is_test_run():
		DirAccess.make_dir_recursive_absolute(_root() + "profiles/" + GUEST.to_lower())
	log_event(current, "guest")


## Where a progress file lives for the signed-in account. Automated tests
## (scripts under res://tests/) get a sandbox so they never touch real saves.
static func path(file: String) -> String:
	var root := _root()
	if current == "":
		return root + file
	var dir := root + "profiles/" + current.to_lower()
	if root != "user://":
		DirAccess.make_dir_recursive_absolute(dir)
	return dir + "/" + file


static var _test_run := -1


## Where accounts, the login log and every profile live: automated tests get a
## sandbox so a test run never adds accounts to (or reads them from) this PC.
static func _root() -> String:
	if not _is_test_run():
		return "user://"
	if not DirAccess.dir_exists_absolute("user://test_sandbox"):
		DirAccess.make_dir_recursive_absolute("user://test_sandbox")
	return "user://test_sandbox/"


static func _is_test_run() -> bool:
	if _test_run < 0:
		var loop = Engine.get_main_loop()
		var scr = loop.get_script() if loop != null else null
		_test_run = 1 if scr != null and String(scr.resource_path).begins_with("res://tests/") else 0
	return _test_run == 1


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(_root() + ACCOUNTS)
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
	if s.to_lower() == GUEST.to_lower():
		return "PICK ANOTHER USERNAME  ·  GUEST IS RESERVED"
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
	# the built-in admin doesn't count: the first *player* account inherits old progress
	var first := not cfg.has_section("users") or Array(cfg.get_section_keys("users")).filter(func(k): return k != ADMIN_NAME).is_empty()
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	cfg.set_value("users", key, {"name": name.strip_edges(), "salt": salt, "hash": _hash(pin, salt),
			"created": Time.get_unix_time_from_system(), "last": Time.get_unix_time_from_system()})
	if cfg.save(_root() + ACCOUNTS) != OK:
		return "COULD NOT SAVE THE ACCOUNT"
	DirAccess.make_dir_recursive_absolute(_root() + "profiles/" + key)
	# a guest who signs out to make an account keeps what it earned as the guest;
	# otherwise the first account keeps the progress made before accounts existed
	var from := _root() + "profiles/%s/" % GUEST.to_lower() if _from_guest else (_root() if first else "")
	if from != "":
		for f in FILES:
			if FileAccess.file_exists(from + f):
				DirAccess.copy_absolute(from + f, _root() + "profiles/%s/%s" % [key, f])
				if _from_guest:
					DirAccess.remove_absolute(from + f)   # handed over: the guest starts fresh
	_from_guest = false
	current = name.strip_edges()
	_fails = 0
	_ensure_admin()
	log_event(current, "created")
	_report_login()
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
		u.fails = int(u.get("fails", 0)) + 1
		cfg.set_value("users", key, u)
		cfg.save(_root() + ACCOUNTS)
		log_event(String(u.get("name", key)), "wrong_pin")
		if _fails >= MAX_TRIES:
			_fails = 0
			_locked_until = Time.get_ticks_msec() / 1000.0 + LOCK_SECONDS
			log_event(String(u.get("name", key)), "locked")
			return "TOO MANY WRONG PASSWORDS  ·  LOCKED FOR %d s" % int(LOCK_SECONDS)
		return "WRONG PASSWORD  ·  %d TRIES LEFT" % (MAX_TRIES - _fails)
	_fails = 0
	u.last = Time.get_unix_time_from_system()
	u.logins = int(u.get("logins", 0)) + 1
	cfg.set_value("users", key, u)
	cfg.save(_root() + ACCOUNTS)
	DirAccess.make_dir_recursive_absolute(_root() + "profiles/" + key)
	current = String(u.get("name", name.strip_edges()))
	_from_guest = false   # an existing account: the guest keeps its own progress
	_ensure_admin()
	log_event(current, "sign_in")
	_report_login()
	return ""


static func _report_login() -> void:
	if _is_test_run():
		return
	var tree := Engine.get_main_loop() as SceneTree
	var service := tree.root.get_node_or_null("Community")
	if service != null:
		service.record_login(current)


static func sign_out() -> void:
	if current != "":
		log_event(current, "sign_out")
	_from_guest = is_guest()
	current = ""


# ------------------------------------------------------------------ admin

## The signed-in account has admin rights (dashboard, every skin unlocked).
static func is_admin(name: String = current) -> bool:
	if name == "":
		return false
	if name == current and _admin_for == current:
		return _admin_val   # cached: UI asks every frame
	var u: Dictionary = _cfg().get_value("users", name.strip_edges().to_lower(), {})
	var v := bool(u.get("admin", false))
	if name == current:
		_admin_for = current
		_admin_val = v
	return v


## Built-in admin account (local PC only). Created on first launch if missing;
## change the PIN by deleting the "admin" entry from accounts.cfg and editing
## ADMIN_PIN, or sign in as admin and grant admin to your own account instead.
const ADMIN_NAME := "admin"
const ADMIN_PIN := "1234"


static func _ensure_admin() -> void:
	seed_admin()


## Makes sure the built-in admin account exists (stored hashed like any other).
static func seed_admin() -> void:
	var cfg := _cfg()
	var key := ADMIN_NAME.to_lower()
	if cfg.has_section_key("users", key):
		var u: Dictionary = cfg.get_value("users", key)
		if not bool(u.get("admin", false)):
			u.admin = true
			cfg.set_value("users", key, u)
			cfg.save(_root() + ACCOUNTS)
		return
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	cfg.set_value("users", key, {"name": ADMIN_NAME, "salt": salt, "hash": _hash(ADMIN_PIN, salt), "admin": true,
			"created": Time.get_unix_time_from_system(), "last": 0.0})
	cfg.save(_root() + ACCOUNTS)
	DirAccess.make_dir_recursive_absolute(_root() + "profiles/" + key)
	_admin_for = "?"


## Admin only: grant or revoke admin on another account.
static func set_admin(name: String, on: bool) -> bool:
	if not is_admin():
		return false
	var key := name.strip_edges().to_lower()
	var cfg := _cfg()
	if not cfg.has_section_key("users", key) or (key == current.to_lower() and not on):
		return false   # can't remove your own admin (avoids locking everyone out)
	var u: Dictionary = cfg.get_value("users", key)
	u.admin = on
	cfg.set_value("users", key, u)
	cfg.save(_root() + ACCOUNTS)
	log_event(current, ("grant_admin:" if on else "revoke_admin:") + String(u.get("name", key)))
	return true


static func log_event(user: String, event: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_root() + LOGIN_LOG)
	var entries: Array = cfg.get_value("log", "entries", [])
	entries.append({"t": Time.get_unix_time_from_system(), "user": user, "event": event})
	if entries.size() > LOG_MAX:
		entries = entries.slice(entries.size() - LOG_MAX)
	cfg.set_value("log", "entries", entries)
	cfg.save(_root() + LOGIN_LOG)


## Newest first. Empty unless the signed-in account is admin.
static func login_log(limit: int = 100) -> Array:
	if not is_admin():
		return []
	var cfg := ConfigFile.new()
	cfg.load(_root() + LOGIN_LOG)
	var entries: Array = cfg.get_value("log", "entries", [])
	entries.reverse()
	return entries.slice(0, limit)


## One row per account for the admin dashboard. Empty unless admin.
## PIN hashes and salts are never included.
static func dashboard_rows() -> Array:
	if not is_admin():
		return []
	var cfg := _cfg()
	var rows: Array = []
	if not cfg.has_section("users"):
		return rows
	for k in cfg.get_section_keys("users"):
		var u: Dictionary = cfg.get_value("users", k, {})
		var arm := ConfigFile.new()
		arm.load(_root() + "profiles/%s/armory.cfg" % k)
		var owned: Dictionary = arm.get_value("armory", "owned", {})
		var camp := ConfigFile.new()
		camp.load(_root() + "profiles/%s/campaign.cfg" % k)
		var chapters: Array = []
		if camp.has_section("campaign"):
			for ck in camp.get_section_keys("campaign"):
				chapters.append("%s:%s" % [ck.to_upper(), str(camp.get_value("campaign", ck))])
		rows.append({
			"name": String(u.get("name", k)),
			"admin": bool(u.get("admin", false)),
			"created": float(u.get("created", 0.0)),
			"last": float(u.get("last", 0.0)),
			"logins": int(u.get("logins", 0)),
			"fails": int(u.get("fails", 0)),
			"credits": int(arm.get_value("armory", "credits", 0)),
			"skins": owned.size(),
			"packs": int(arm.get_value("armory", "packs_opened", 0)),
			"campaign": " ".join(chapters) if not chapters.is_empty() else "-",
		})
	rows.sort_custom(func(a, b): return a.last > b.last)
	return rows
