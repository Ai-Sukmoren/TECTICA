extends RefCounted
## Keyboard / mouse rebinding. Each bindable action gets one key or mouse
## button (it replaces that action's keyboard + mouse events; gamepad
## bindings are never touched). Saved to user://controls.cfg and applied at
## startup by input_setup.gd. Two actions may share a key (F is interact and
## first person by default); the settings screen flags any other overlap.

const PATH := "user://controls.cfg"

## [action, label] in the order shown on the CONTROLS tab.
const BINDABLE := [
	["move_forward", "MOVE FORWARD"], ["move_back", "MOVE BACK"], ["move_left", "MOVE LEFT"], ["move_right", "MOVE RIGHT"],
	["fire", "FIRE"], ["aim", "AIM DOWN SIGHTS"], ["sprint", "SPRINT"], ["crouch", "CROUCH"], ["vault", "JUMP / VAULT"],
	["kick", "DROPKICK (WHILE SPRINTING)"], ["reload", "RELOAD"], ["switch_weapon", "SWITCH WEAPON"],
	["weapon_1", "PRIMARY"], ["weapon_2", "SECONDARY"], ["weapon_3", "KNIFE"], ["peek_left", "PEEK LEFT"], ["peek_right", "PEEK RIGHT"],
	["grenade", "FRAG GRENADE"], ["flashbang", "FLASHBANG"], ["flashlight", "FLASHLIGHT"], ["interact", "INTERACT"],
	["toggle_view", "FIRST PERSON / TOP-DOWN"], ["inspect", "INSPECT WEAPON"], ["cam_rot_left", "ROTATE CAMERA LEFT"],
	["cam_rot_right", "ROTATE CAMERA RIGHT"], ["music", "MUSIC ON / OFF"], ["shop", "ZOMBIE SHOP"],
]
## Pairs that share a key on purpose (different situations).
const SHARED_OK := [["interact", "toggle_view"], ["kick", "cam_rot_right"]]

## action -> Array of default keyboard/mouse events (captured before saved binds apply).
static var _defaults: Dictionary = {}


static func _path() -> String:
	return ("user://test_sandbox/" if preload("res://scripts/core/profile.gd")._is_test_run() else "user://") + "controls.cfg"


static func _is_kbm(ev: InputEvent) -> bool:
	return ev is InputEventKey or ev is InputEventMouseButton


## Remember the built-in bindings, then apply the player's saved ones.
static func init_after_defaults() -> void:
	_defaults.clear()
	for b in BINDABLE:
		var evs: Array = []
		for ev in InputMap.action_get_events(String(b[0])):
			if _is_kbm(ev):
				evs.append(ev.duplicate())
		_defaults[String(b[0])] = evs
	load_saved()


static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path()) != OK:
		return
	for b in BINDABLE:
		var a := String(b[0])
		if not cfg.has_section_key("binds", a):
			continue
		var d = cfg.get_value("binds", a)
		if d is Dictionary:
			var ev := _from_dict(d)
			if ev != null:
				_set_kbm(a, [ev])


static func save() -> void:
	var cfg := ConfigFile.new()
	for b in BINDABLE:
		var a := String(b[0])
		var evs := _kbm_events(a)
		if not evs.is_empty() and not _same(evs, _defaults.get(a, [])):
			cfg.set_value("binds", a, _to_dict(evs[0]))
	DirAccess.make_dir_recursive_absolute(_path().get_base_dir())
	cfg.save(_path())


## Binds `action` to the pressed key / mouse button.
static func rebind(action: String, ev: InputEvent) -> bool:
	var e: InputEvent
	if ev is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = (ev as InputEventKey).physical_keycode if (ev as InputEventKey).physical_keycode != 0 else (ev as InputEventKey).keycode
		e = k
	elif ev is InputEventMouseButton:
		var mb := (ev as InputEventMouseButton).button_index
		if mb in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return false
		var m := InputEventMouseButton.new()
		m.button_index = mb
		e = m
	else:
		return false
	_set_kbm(action, [e])
	save()
	return true


static func reset_all() -> void:
	for a in _defaults:
		var evs: Array = []
		for ev in _defaults[a]:
			evs.append(ev.duplicate())
		_set_kbm(a, evs)
	save()


static func _set_kbm(action: String, evs: Array) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if _is_kbm(ev):
			InputMap.action_erase_event(action, ev)
	for ev in evs:
		InputMap.action_add_event(action, ev)


static func _kbm_events(action: String) -> Array:
	var out: Array = []
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if _is_kbm(ev):
				out.append(ev)
	return out


static func _to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "code": int((ev as InputEventKey).physical_keycode)}
	return {"type": "mouse", "button": int((ev as InputEventMouseButton).button_index)}


static func _from_dict(d: Dictionary) -> InputEvent:
	if String(d.get("type", "")) == "key":
		var k := InputEventKey.new()
		k.physical_keycode = int(d.get("code", 0)) as Key
		return k
	if String(d.get("type", "")) == "mouse":
		var m := InputEventMouseButton.new()
		m.button_index = int(d.get("button", 1)) as MouseButton
		return m
	return null


static func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if str(_to_dict(a[i])) != str(_to_dict(b[i])):
			return false
	return true


static func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var phys := (ev as InputEventKey).physical_keycode
		var key := DisplayServer.keyboard_get_keycode_from_physical(phys) if DisplayServer.get_name() != "headless" else phys
		var s := OS.get_keycode_string(key)
		return s.to_upper() if s != "" else "KEY %d" % int(phys)
	if ev is InputEventMouseButton:
		var b := (ev as InputEventMouseButton).button_index
		return {MOUSE_BUTTON_LEFT: "LEFT MOUSE", MOUSE_BUTTON_RIGHT: "RIGHT MOUSE", MOUSE_BUTTON_MIDDLE: "MIDDLE MOUSE",
				MOUSE_BUTTON_XBUTTON1: "MOUSE 4", MOUSE_BUTTON_XBUTTON2: "MOUSE 5"}.get(b, "MOUSE %d" % int(b))
	return "?"


## "W / UP" style label of everything bound to an action on keyboard + mouse.
static func label(action: String) -> String:
	var parts: Array = []
	for ev in _kbm_events(action):
		parts.append(event_label(ev))
	return " / ".join(parts) if not parts.is_empty() else "UNBOUND"


## Short label of the first key, for in-game hints like "[G]".
static func short(action: String) -> String:
	var evs := _kbm_events(action)
	return event_label(evs[0]) if not evs.is_empty() else "-"


## Labels of other bindable actions using one of this action's keys.
static func conflicts(action: String) -> Array:
	var mine: Array = []
	for ev in _kbm_events(action):
		mine.append(str(_to_dict(ev)))
	var out: Array = []
	for b in BINDABLE:
		var other := String(b[0])
		if other == action or [action, other] in SHARED_OK or [other, action] in SHARED_OK:
			continue
		for ev in _kbm_events(other):
			if str(_to_dict(ev)) in mine:
				out.append(String(b[1]))
				break
	return out


## Settings rows for the CONTROLS tab: [action, label, "bind"] + reset row.
static func rows() -> Array:
	var out: Array = []
	for b in BINDABLE:
		out.append([String(b[0]), String(b[1]), "bind"])
	out.append(["reset_binds", "RESET ALL TO DEFAULTS", "reset"])
	return out
