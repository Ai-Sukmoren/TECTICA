extends SceneTree
## Key rebinding: labels, rebinding keys and mouse buttons (gamepad kept),
## conflicts, save + reload, reset, and the CONTROLS settings tab flow.
##   godot --headless --path . -s res://tests/controls_test.gd
const Main = preload("res://scripts/main.gd")
const Controls = preload("res://scripts/core/controls.gd")
const Settings = preload("res://scripts/core/settings.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	return e

func has_pad(action: String) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			return true
	return false

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	Controls.reset_all()

	check(Controls.label("reload") == "R", "reload defaults to R (%s)" % Controls.label("reload"))
	check(Controls.label("aim") == "RIGHT MOUSE", "aim defaults to right mouse")
	check(Controls.conflicts("interact").is_empty(), "interact / first person share F on purpose")

	check(Controls.rebind("reload", key(KEY_T)), "rebind reload to T")
	check(Controls.label("reload") == "T", "reload now shows T")
	check(has_pad("reload"), "gamepad button for reload kept")
	var ev := key(KEY_T)
	check(InputMap.event_is_action(ev, "reload"), "pressing T triggers reload")
	check(not InputMap.event_is_action(key(KEY_R), "reload"), "R no longer reloads")
	check("FLASHLIGHT" in Controls.conflicts("reload"), "clash with the flashlight key is reported")

	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	mb.pressed = true
	check(Controls.rebind("aim", mb) and Controls.label("aim") == "MOUSE 4", "aim can move to mouse 4")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	check(not Controls.rebind("fire", wheel), "mouse wheel is refused")

	# saved: wipe the live map back to defaults by hand, then load
	Controls._set_kbm("reload", [key(KEY_R)])
	Controls.load_saved()
	check(Controls.label("reload") == "T" and Controls.label("aim") == "MOUSE 4", "bindings reload from controls.cfg")

	Controls.reset_all()
	check(Controls.label("reload") == "R" and Controls.label("aim") == "RIGHT MOUSE", "reset restores defaults")
	check(Controls.label("move_forward") == "W / UP", "movement keeps both default keys (%s)" % Controls.label("move_forward"))

	# settings screen flow
	var hud = main.hud
	hud.settings_open = true
	hud._settings_set_tab(Settings.TABS.find("CONTROLS"))
	var rows: Array = Settings.rows(hud.settings_tab)
	hud.settings_row = rows.find(rows.filter(func(r): return r[0] == "grenade")[0])
	var acc := InputEventAction.new()
	acc.action = "ui_accept"
	acc.pressed = true
	hud._settings_input(acc)
	check(hud._binding == "grenade", "Enter on FRAG GRENADE waits for a key")
	hud._settings_input(key(KEY_K))
	check(hud._binding == "" and Controls.label("grenade") == "K", "pressing K binds the grenade to K")
	hud._settings_input(acc)
	hud._settings_input(key(KEY_ESCAPE))
	check(hud._binding == "" and Controls.label("grenade") == "K", "Esc cancels without changing it")
	check(hud.settings_open, "settings stay open after binding")
	hud.settings_row = rows.size() - 1   # reset row
	hud._settings_input(acc)
	check(Controls.label("grenade") == "G", "RESET ALL row restores G")

	Controls.reset_all()
	print("CONTROLS: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
