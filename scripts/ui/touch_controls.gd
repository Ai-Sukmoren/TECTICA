extends CanvasLayer
## On-screen controls for phones (see platform.gd).
##   left half      floating move stick (push far to sprint)
##   right half     floating aim stick (aim assist on; push to the rim to fire)
##   buttons        FIRE, RELOAD, JUMP, CROUCH, SWAP, FRAG, FLASH, KICK, ADS, USE, pause
##   keyboard       appears on the sign-in screen and the multiplayer text rows
## Everything feeds the normal input actions, the same path a gamepad uses.
## Touches on a control also swallow the matching emulated mouse event so the
## menus underneath don't react to them.

const STICK_R := 92.0       # stick travel radius (UI pixels, 1280x720 layout)
const FIRE_AT := 0.86       # aim stick deflection that also pulls the trigger

var hud: Node
var main: Node

# finger index -> what it is holding: "move", "aim" or a button id
var _fingers: Dictionary = {}
var _move_origin := Vector2.ZERO
var _move_vec := Vector2.ZERO
var _aim_origin := Vector2.ZERO
var _aim_vec := Vector2.ZERO
var _pressed: Dictionary = {}       # button id -> true while held
var _toggles: Dictionary = {}       # ads / sprint latch
var _canvas: Control
var _buttons: Array = []            # [id, centre, radius, label, action, kind]
var _keys: Array = []               # [rect, label, keycode, unicode]
var _shift := true
var _fullscreen_asked := false


func setup(p_hud: Node) -> void:
	hud = p_hud
	main = p_hud.main
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)


# ------------------------------------------------------------------ state

func _size() -> Vector2:
	return _canvas.size if _canvas != null else Vector2(1280, 720)


func in_game() -> bool:
	if hud == null or main == null or hud.title or main.player == null or main.player.is_dead:
		return false
	if main.game_over or hud.settings_open or hud.mp_pause or main.get_tree().paused:
		return false
	return not (main.has_method("killcam_active") and main.killcam_active())


## The screen wants typed text: sign-in, or a text row of the multiplayer menu.
func wants_keyboard() -> bool:
	if hud == null:
		return false
	if hud._needs_auth():
		return true
	return hud.title and hud.mp_open and int(hud.mp_row) in [0, 3, 4]


func portrait() -> bool:
	var s := _size()
	return s.y > s.x


# ------------------------------------------------------------------ layout

func _layout() -> void:
	var s := _size()
	var r := s.x - 92.0
	var b := s.y - 92.0
	_buttons = [
		["fire", Vector2(r - 40.0, b - 110.0), 62.0, "FIRE", "fire", "hold"],
		["reload", Vector2(r - 172.0, b - 36.0), 40.0, "RELOAD", "reload", "tap"],
		["vault", Vector2(r + 36.0, b + 8.0), 40.0, "JUMP", "vault", "tap"],
		["crouch", Vector2(r - 92.0, b + 24.0), 34.0, "CROUCH", "crouch", "tap"],
		["switch", Vector2(r - 196.0, b - 128.0), 34.0, "SWAP", "switch_weapon", "tap"],
		["grenade", Vector2(r - 176.0, b - 222.0), 32.0, "FRAG", "grenade", "tap"],
		["flash", Vector2(r - 96.0, b - 226.0), 32.0, "FLASH", "flashbang", "tap"],
		["ads", Vector2(r + 36.0, b - 206.0), 32.0, "ADS", "aim", "toggle"],
		["kick", Vector2(r + 40.0, b - 120.0), 0.0, "", "kick", "tap"],
		["interact", Vector2(s.x * 0.5, s.y - 56.0), 30.0, "USE", "interact", "tap"],
		["sprint", Vector2(150.0, s.y - 250.0), 30.0, "SPRINT", "sprint", "toggle"],
		["pause", Vector2(44.0, 44.0), 26.0, "II", "pause", "tap"],
		["shop", Vector2(s.x * 0.5, s.y - 140.0), 0.0, "SHOP", "shop", "tap"],
		["nvg", Vector2(110.0, 140.0), 26.0, "NVG", "nvg", "tap"],
	]
	# zombie shop button only between waves
	if main != null and main.director != null and not main.director.active and main.player != null and not main.player.is_dead:
		_buttons[12][2] = 34.0
	# kick only shows while sprinting (it is a sprinting move)
	if main != null and main.player != null and main.player.sprinting:
		_buttons[8][2] = 34.0
		_buttons[8][3] = "KICK"


func _layout_keyboard() -> void:
	_keys.clear()
	var s := _size()
	var rows := ["1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]
	var kw := minf((s.x - 40.0) / 10.5, 84.0)
	var kh := 50.0
	var top := s.y - 4.0 * (kh + 6.0) - kh - 12.0
	# bar above the keys: what is being typed + the actions hidden behind them
	var bar_y := top - 58.0
	var actions: Array = [["SIGN IN", "act_signin"], ["CREATE ACCOUNT", "act_create"]] if hud._needs_auth() else [["HIDE KEYBOARD", "act_hide"]]
	var ax := s.x - 16.0
	for i in range(actions.size() - 1, -1, -1):
		var w := 70.0 + String(actions[i][0]).length() * 11.0
		ax -= w
		_keys.append([Rect2(ax, bar_y, w, 46.0), String(actions[i][0]), String(actions[i][1]), 0])
		ax -= 8.0
	for ri in rows.size():
		var row: String = rows[ri]
		var x0 := (s.x - row.length() * (kw + 6.0)) * 0.5
		for ci in row.length():
			var ch := row[ci]
			var code: int = OS.find_keycode_from_string(ch)   # letters and digits share their ASCII code
			_keys.append([Rect2(x0 + ci * (kw + 6.0), top + ri * (kh + 6.0), kw, kh), ch, code, ch.unicode_at(0)])
	var y := top + 4.0 * (kh + 6.0)
	var x := (s.x - (kw * 2.0 + kw * 4.0 + kw * 2.0 + kw * 2.0 + 18.0)) * 0.5
	_keys.append([Rect2(x, y, kw * 2.0, kh), "DEL", KEY_BACKSPACE, 0]); x += kw * 2.0 + 6.0
	_keys.append([Rect2(x, y, kw * 4.0, kh), "SPACE", KEY_SPACE, 32]); x += kw * 4.0 + 6.0
	_keys.append([Rect2(x, y, kw * 2.0, kh), "TAB", KEY_TAB, 0]); x += kw * 2.0 + 6.0
	_keys.append([Rect2(x, y, kw * 2.0, kh), "ENTER", KEY_ENTER, 0])


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if hud == null:
		return
	if event is InputEventScreenTouch and event.pressed and not _fullscreen_asked:
		_fullscreen_asked = true
		if OS.has_feature("web"):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)   # needs a user gesture
	var pos = _ui_pos(event)
	# the emulated mouse copy of a touch on one of our controls: swallow it
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and pos != null and _over_control(pos):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, pos)
		else:
			_touch_up(event.index)
		if _fingers.has(event.index) or not event.pressed:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		_touch_move(event.index, pos)
		get_viewport().set_input_as_handled()


## Event position in the 1280x720-based UI space the controls are drawn in.
func _ui_pos(event: InputEvent):
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouse):
		return null
	return event.position   # _input already delivers them in the stretched UI space


func _over_control(p: Vector2) -> bool:
	if wants_keyboard():
		# the whole panel, gaps included: menus hidden behind it react to the
		# pointer moving over them (the sign-in screen moves its selection)
		return p.y >= _keyboard_top() - 10.0
	return _over_play_control(p)


func _keyboard_top() -> float:
	var top := 9999.0
	for k in _keys:
		top = minf(top, (k[0] as Rect2).position.y)
	return top


func _over_play_control(p: Vector2) -> bool:
	if not in_game():
		return false
	return true   # in play the whole screen belongs to the sticks and buttons


func _touch_down(idx: int, p: Vector2) -> void:
	if wants_keyboard():
		for k in _keys:
			if (k[0] as Rect2).has_point(p):
				_type_key.call_deferred(k)   # not while this touch is still being dispatched
				_fingers[idx] = "key"
				return
		return
	if not in_game():
		return
	_layout()
	for bt in _buttons:
		if float(bt[2]) > 0.0 and p.distance_to(bt[1]) <= float(bt[2]) + 10.0:
			_fingers[idx] = String(bt[0])
			_button_down(bt)
			return
	if p.x < _size().x * 0.45:
		_fingers[idx] = "move"
		_move_origin = p
		_move_vec = Vector2.ZERO
	else:
		_fingers[idx] = "aim"
		_aim_origin = p
		_aim_vec = Vector2.ZERO
	_apply_sticks()


func _touch_move(idx: int, p: Vector2) -> void:
	match String(_fingers[idx]):
		"move":
			var d := p - _move_origin
			if d.length() > STICK_R:
				_move_origin = p - d.normalized() * STICK_R   # the stick follows a long drag
				d = p - _move_origin
			_move_vec = d / STICK_R
		"aim":
			var d := p - _aim_origin
			if d.length() > STICK_R:
				_aim_origin = p - d.normalized() * STICK_R
				d = p - _aim_origin
			_aim_vec = d / STICK_R
		_:
			return
	_apply_sticks()


func _touch_up(idx: int) -> void:
	if not _fingers.has(idx):
		return
	var what := String(_fingers[idx])
	_fingers.erase(idx)
	match what:
		"move":
			_move_vec = Vector2.ZERO
		"aim":
			_aim_vec = Vector2.ZERO
		"key":
			pass
		_:
			for bt in _buttons:
				if String(bt[0]) == what and String(bt[5]) == "hold":
					Input.action_release(String(bt[4]))
					_pressed.erase(what)
	_apply_sticks()


func _button_down(bt: Array) -> void:
	var id := String(bt[0])
	var action := String(bt[4])
	match String(bt[5]):
		"hold":
			Input.action_press(action)
			_pressed[id] = true
		"toggle":
			var on := not bool(_toggles.get(id, false))
			_toggles[id] = on
			if on:
				Input.action_press(action)
			else:
				Input.action_release(action)
		_:
			_tap(action)


## A one-frame press, the way a key tap reads in the game.
func _tap(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _type_key(k: Array) -> void:
	if k[2] is String:
		match String(k[2]):
			"act_signin":
				hud._auth_submit(false)
			"act_create":
				hud._auth_submit(true)
			"act_hide":
				hud.mp_row = 1   # off the text rows
		return
	var down := InputEventKey.new()
	down.keycode = int(k[2]) as Key
	down.physical_keycode = int(k[2]) as Key
	down.unicode = int(k[3])
	down.pressed = true
	Input.parse_input_event(down)
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


## The field the keyboard is typing into, shown above the keys.
func _field_text() -> String:
	var cur := "_" if int(Time.get_ticks_msec() / 500) % 2 == 0 else " "
	if hud._needs_auth():
		if int(hud._auth_row) == 1:
			return "PASSWORD  " + "*".repeat(String(hud._auth_pin).length()) + cur + "   (TAB = username)"
		return "USERNAME  " + String(hud._auth_user) + cur + "   (TAB = password)"
	return String(hud._mp_items()[int(hud.mp_row)])


## Sticks -> the move / look actions a gamepad drives.
func _apply_sticks() -> void:
	var m := _move_vec.limit_length(1.0)
	_set_axis("move_left", "move_right", m.x)
	_set_axis("move_forward", "move_back", m.y)
	var a := _aim_vec.limit_length(1.0)
	_set_axis("look_left", "look_right", a.x)
	_set_axis("look_up", "look_down", a.y)
	var firing := a.length() >= FIRE_AT
	if firing and not _pressed.has("stick_fire"):
		Input.action_press("fire")
		_pressed["stick_fire"] = true
	elif not firing and _pressed.has("stick_fire"):
		_pressed.erase("stick_fire")
		if not _pressed.has("fire"):
			Input.action_release("fire")


func _set_axis(neg: String, pos: String, v: float) -> void:
	if v < -0.05:
		Input.action_press(neg, -v)
		Input.action_release(pos)
	elif v > 0.05:
		Input.action_press(pos, v)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


## Leaving play (menu, death, pause) lets go of everything.
func _release_all() -> void:
	if _fingers.is_empty() and _pressed.is_empty() and _move_vec == Vector2.ZERO and _aim_vec == Vector2.ZERO and _toggles.is_empty():
		return
	_fingers.clear()
	_move_vec = Vector2.ZERO
	_aim_vec = Vector2.ZERO
	_apply_sticks()
	for bt in _buttons:
		Input.action_release(String(bt[4]))
	_pressed.clear()
	_toggles.clear()


func _process(_delta: float) -> void:
	if hud == null:
		return
	var playing := in_game()
	if playing:
		main.player.using_pad = true   # the stick aim path (with aim assist)
	else:
		if not wants_keyboard():
			_release_all()
	if wants_keyboard():
		_layout_keyboard()
	_layout()
	_canvas.queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw_controls() -> void:
	var c := _canvas
	var s := _size()
	var font: Font = hud._font_bold if hud != null and hud.get("_font_bold") != null else ThemeDB.fallback_font
	if portrait():
		c.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.88))
		c.draw_string(font, Vector2(0, s.y * 0.5 - 10.0), "ROTATE YOUR PHONE", HORIZONTAL_ALIGNMENT_CENTER, s.x, 34, Color(1, 1, 1))
		c.draw_string(font, Vector2(0, s.y * 0.5 + 30.0), "TECTICA plays in landscape", HORIZONTAL_ALIGNMENT_CENTER, s.x, 20, Color(1, 1, 1, 0.6))
		return
	if wants_keyboard():
		var top := 9999.0
		for k in _keys:
			top = minf(top, (k[0] as Rect2).position.y)
		c.draw_rect(Rect2(0, top - 10.0, s.x, s.y - top + 10.0), Color(0.02, 0.03, 0.04, 0.95))
		c.draw_string(font, Vector2(20.0, top + 30.0), _field_text(), HORIZONTAL_ALIGNMENT_LEFT, s.x * 0.55, 22, Color(1.0, 0.8, 0.35))
		for k in _keys:
			var r: Rect2 = k[0]
			var act: bool = k[2] is String
			c.draw_rect(r, Color(0.85, 0.2, 0.15, 0.55) if act else Color(1, 1, 1, 0.1))
			c.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.5)
			c.draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 9.0), String(k[1]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24 if String(k[1]).length() == 1 else 16, Color(1, 1, 1, 0.92))
		return
	if not in_game():
		return
	var ink := Color(1, 1, 1, 0.55)
	# sticks: a hint ring where they appear, the live stick while held
	if _fingers.values().has("move"):
		c.draw_arc(_move_origin, STICK_R, 0, TAU, 40, Color(1, 1, 1, 0.3), 3.0)
		c.draw_circle(_move_origin + _move_vec.limit_length(1.0) * STICK_R, 34.0, Color(1, 1, 1, 0.35))
	else:
		c.draw_arc(Vector2(150, s.y - 150), STICK_R, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0)
		c.draw_string(font, Vector2(150 - 60, s.y - 144), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color(1, 1, 1, 0.3))
	if _fingers.values().has("aim"):
		var firing := _aim_vec.length() >= FIRE_AT
		c.draw_arc(_aim_origin, STICK_R, 0, TAU, 40, Color(1, 0.3, 0.25, 0.6) if firing else Color(1, 1, 1, 0.3), 3.0)
		c.draw_arc(_aim_origin, STICK_R * FIRE_AT, 0, TAU, 40, Color(1, 0.3, 0.25, 0.25), 1.5)
		c.draw_circle(_aim_origin + _aim_vec.limit_length(1.0) * STICK_R, 34.0, Color(1, 0.35, 0.3, 0.45) if firing else Color(1, 1, 1, 0.35))
	for bt in _buttons:
		var rad := float(bt[2])
		if rad <= 0.0:
			continue
		var id := String(bt[0])
		var on: bool = _pressed.has(id) or bool(_toggles.get(id, false))
		var col := Color(1.0, 0.32, 0.25) if id == "fire" else Color(1, 1, 1)
		c.draw_circle(bt[1], rad, Color(col, 0.38 if on else 0.16))
		c.draw_arc(bt[1], rad, 0, TAU, 32, Color(col, 0.75 if on else 0.45), 2.0)
		var fs := 18 if rad >= 50.0 else (13 if String(bt[3]).length() > 4 else 15)
		c.draw_string(font, Vector2((bt[1] as Vector2).x - rad, (bt[1] as Vector2).y + fs * 0.35), String(bt[3]), HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0, fs, ink if not on else Color(1, 1, 1, 0.95))
