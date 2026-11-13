extends Node
## Admin-only dashboard: every account on this PC with its sign-in stats and
## progress, plus the recent sign-in / failed-PIN / lockout log.
## Data comes from profile.gd, which returns nothing unless the signed-in
## account is an admin. PIN hashes are never shown.

const Profile = preload("res://scripts/core/profile.gd")

var hud
var is_open := false
var row := 0
var log_scroll := 0
var msg := ""
var msg_t := 0.0
var _rows: Array = []
var _log: Array = []
var _row_rects: Array = []
var _global := true
var _service
var _refresh_in := 0.0

const EVENT_LABELS := {
	"sign_in": "SIGNED IN", "sign_out": "SIGNED OUT", "created": "ACCOUNT CREATED",
	"wrong_pin": "WRONG PASSWORD", "locked": "LOCKED OUT (5 FAILS)",
}


func setup(p_hud) -> void:
	hud = p_hud
	process_mode = Node.PROCESS_MODE_ALWAYS
	_service = get_tree().root.get_node("Community")
	_service.dashboard_updated.connect(_global_received)


func open() -> void:
	if not Profile.is_admin():
		return
	is_open = true
	log_scroll = 0
	refresh()


func close() -> void:
	is_open = false


func refresh() -> void:
	if _global:
		_service.refresh_dashboard()
		_refresh_in = 15.0
		return
	_rows = Profile.dashboard_rows()
	_log = Profile.login_log(200)
	row = clampi(row, 0, maxi(_rows.size() - 1, 0))


func _process(delta: float) -> void:
	msg_t = maxf(msg_t - delta, 0.0)
	if is_open and _global:
		_refresh_in -= delta
		if _refresh_in <= 0.0:
			refresh()


func _global_received() -> void:
	if not _global:
		return
	_rows = _service.dashboard.get("rows", [])
	_log = _service.dashboard.get("events", [])
	row = clampi(row, 0, maxi(_rows.size() - 1, 0))


static func when(t: float) -> String:
	if t <= 0.0:
		return "-"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_string_from_unix_time(int(t) + bias, true).substr(0, 16)


## Returns true when the screen should close.
func handle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_global = not _global
		_rows = []
		_log = []
		row = 0
		log_scroll = 0
		refresh()
		return false
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		row = posmod(row - 1, maxi(_rows.size(), 1))
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		row = posmod(row + 1, maxi(_rows.size(), 1))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_PAGEDOWN:
		log_scroll = mini(log_scroll + 10, maxi(_log.size() - 10, 0))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_PAGEUP:
		log_scroll = maxi(log_scroll - 10, 0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		log_scroll = mini(log_scroll + 3, maxi(_log.size() - 10, 0))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		log_scroll = maxi(log_scroll - 3, 0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_G and not _global and not _rows.is_empty():
		var r: Dictionary = _rows[row]
		if Profile.set_admin(String(r.name), not bool(r.admin)):
			msg = ("ADMIN GRANTED  ·  " if not bool(r.admin) else "ADMIN REVOKED  ·  ") + String(r.name).to_upper()
		else:
			msg = "YOU CAN'T REMOVE YOUR OWN ADMIN"
		msg_t = 3.0
		refresh()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		refresh()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				row = i
	return false


func draw(c: Control, vp: Vector2) -> void:
	if _global:
		_draw_global(c, vp)
		return
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.02, 0.03, 0.95))
	hud._text(c, Vector2(60, 66), "ADMIN  //  DASHBOARD", 26, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(60, 90), "SIGNED IN AS  " + Profile.current.to_upper() + "   ·   LOCAL ACCOUNTS ON THIS PC", 12, hud.DIM)

	# --- summary tiles
	var total_logins := 0
	var total_fails := 0
	for r in _rows:
		total_logins += int(r.logins)
		total_fails += int(r.fails)
	var day_ago := Time.get_unix_time_from_system() - 86400.0
	var active_24h := 0
	var seen := {}
	for e in _log:
		if String(e.event) == "sign_in" and float(e.t) > day_ago and not seen.has(String(e.user)):
			seen[String(e.user)] = true
			active_24h += 1
	var tiles := [["ACCOUNTS", str(_rows.size()), hud.TEXT], ["TOTAL SIGN-INS", str(total_logins), hud.ACCENT],
			["ACTIVE (24 H)", str(active_24h), hud.ACCENT], ["FAILED PASSWORDS", str(total_fails), hud.DANGER if total_fails > 0 else hud.DIM]]
	for i in tiles.size():
		var tr := Rect2(60 + i * 230, 110, 214, 62)
		c.draw_rect(tr, Color(1, 1, 1, 0.04))
		c.draw_rect(Rect2(tr.position, Vector2(3, tr.size.y)), Color(tiles[i][2], 0.8))
		hud._text(c, tr.position + Vector2(14, 22), tiles[i][0], 11, hud.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		hud._text(c, tr.position + Vector2(14, 50), tiles[i][1], 24, tiles[i][2], HORIZONTAL_ALIGNMENT_LEFT, -1, true)

	# --- accounts table
	var cols := [["PLAYER", 0], ["ROLE", 170], ["CREATED", 250], ["LAST SIGN-IN", 400], ["LOGINS", 550],
			["FAILED", 630], ["CREDITS", 710], ["SKINS", 800], ["PACKS", 870], ["CAMPAIGN", 940]]
	var tx := 60.0
	var ty := 200.0
	for col in cols:
		hud._text(c, Vector2(tx + col[1], ty), col[0], 11, hud.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	c.draw_line(Vector2(tx, ty + 8), Vector2(vp.x - 60, ty + 8), Color(hud.TEXT, 0.2), 1.0)
	_row_rects.clear()
	var max_rows := 8
	for i in mini(_rows.size(), max_rows):
		var r: Dictionary = _rows[i]
		var y := ty + 32 + i * 28.0
		var rr := Rect2(tx - 8, y - 19, vp.x - 120 + 16, 26)
		_row_rects.append(rr)
		if i == row:
			c.draw_rect(rr, Color(hud.RED, 0.2))
			hud._brackets(c, rr, 6.0, hud.RED, 1.5)
		var me := String(r.name).to_lower() == Profile.current.to_lower()
		var vals := [String(r.name).to_upper() + ("  (YOU)" if me else ""), "ADMIN" if bool(r.admin) else "PLAYER",
				when(float(r.created)), when(float(r.last)), str(r.logins), str(r.fails), str(r.credits),
				str(r.skins), str(r.packs), String(r.campaign)]
		for j in cols.size():
			var colr: Color = hud.TEXT
			if j == 1 and bool(r.admin):
				colr = hud.WARN
			elif j == 5 and int(r.fails) > 0:
				colr = hud.DANGER
			hud._text(c, Vector2(tx + cols[j][1], y), vals[j], 12, colr, HORIZONTAL_ALIGNMENT_LEFT, -1, j == 0)
	if _rows.size() > max_rows:
		hud._text(c, Vector2(tx, ty + 32 + max_rows * 28.0), "+ %d more" % (_rows.size() - max_rows), 11, hud.DIM)

	# --- activity log
	var ly := ty + 32 + max_rows * 28.0 + 34
	hud._text(c, Vector2(tx, ly), "RECENT SIGN-IN ACTIVITY", 14, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(tx, ly), "%d EVENTS" % _log.size(), 11, hud.DIM, HORIZONTAL_ALIGNMENT_RIGHT, vp.x - 120)
	c.draw_line(Vector2(tx, ly + 8), Vector2(vp.x - 60, ly + 8), Color(hud.TEXT, 0.2), 1.0)
	var lines := int((vp.y - 80 - (ly + 30)) / 22.0)
	for i in range(log_scroll, mini(_log.size(), log_scroll + lines)):
		var e: Dictionary = _log[i]
		var y := ly + 30 + (i - log_scroll) * 22.0
		var ev := String(e.event)
		var label := String(EVENT_LABELS.get(ev, ev.replace("_", " ").to_upper()))
		var colr: Color = hud.DANGER if ev in ["wrong_pin", "locked"] else (hud.ACCENT if ev in ["sign_in", "created"] else hud.DIM)
		hud._text(c, Vector2(tx, y), when(float(e.t)), 12, hud.DIM)
		hud._text(c, Vector2(tx + 170, y), String(e.user).to_upper(), 12, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		hud._text(c, Vector2(tx + 400, y), label, 12, colr, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	if _log.is_empty():
		hud._text(c, Vector2(tx, ly + 30), "No sign-ins recorded yet (logging starts with this update).", 12, hud.DIM)

	if msg_t > 0.0:
		hud._text(c, Vector2(0, vp.y - 58), msg, 14, Color(hud.WARN, clampf(msg_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	hud._text(c, Vector2(0, vp.y - 30), "Tab global sign-ins   ·   W/S select   ·   G admin role   ·   wheel scroll log   ·   F5 refresh   ·   Esc back", 12, hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_global(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.02, 0.03, 0.95))
	hud._text(c, Vector2(60, 66), "ADMIN  //  GLOBAL SIGN-INS", 26, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(60, 94), str(_service.dashboard_status), 12, hud.DIM)
	hud._text(c, Vector2(60, 128), "%d RECORDED PLAYERS   ·   %d SIGN-INS   ·   %d ACTIVE IN 24 HOURS" % [
		_rows.size(), int(_service.dashboard.get("total", 0)), int(_service.dashboard.get("active", 0))], 14, hud.ACCENT)
	hud._text(c, Vector2(60, 156), "Successful local sign-ins reported by updated game clients. Installation IDs distinguish identical names.", 11, hud.DIM)
	var first := maxi(row - 7, 0)
	_row_rects.clear()
	for i in range(first, mini(first + 8, _rows.size())):
		var r: Dictionary = _rows[i]
		var y := 196.0 + (i - first) * 30.0
		if i == row:
			c.draw_rect(Rect2(54, y - 20, vp.x - 114, 28), Color(hud.RED, 0.2))
		hud._text(c, Vector2(60, y), str(r.name), 14, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		hud._text(c, Vector2(280, y), "PC " + str(r.device), 12, hud.DIM)
		hud._text(c, Vector2(450, y), when(float(r.last)), 12, hud.TEXT)
		hud._text(c, Vector2(690, y), "%d sign-ins" % int(r.logins), 12, hud.ACCENT)
	if _rows.is_empty():
		hud._text(c, Vector2(60, 196), "No player sign-ins received yet.", 14, hud.DIM)
	hud._text(c, Vector2(60, 460), "RECENT SIGN-INS", 14, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var lines := maxi(int((vp.y - 550) / 24), 0)
	for i in range(log_scroll, mini(_log.size(), log_scroll + lines)):
		var e: Dictionary = _log[i]
		var y := 490 + (i - log_scroll) * 24
		hud._text(c, Vector2(60, y), when(float(e.t)), 12, hud.DIM)
		hud._text(c, Vector2(280, y), str(e.user), 12, hud.TEXT)
		hud._text(c, Vector2(510, y), "PC %s  ·  v%s" % [e.device, e.version], 12, hud.DIM)
	hud._text(c, Vector2(60, vp.y - 30), "W/S select player   ·   wheel scroll log   ·   F5 refresh   ·   Tab local accounts   ·   Esc back", 12, hud.DIM)
