extends RefCounted
## Phone / tablet support. Touch mode turns on for phone and tablet browsers
## (and on a desktop with `-- --touch` for testing). It:
##   * scales the whole UI from a 1280x720 layout so menus fit a phone
##   * starts on the lighter graphics and the DEAD END map
##   * takes fire / aim off the (touch-emulated) mouse so a tap is not a shot
##   * adds the on-screen sticks, buttons and keyboard (touch_controls.gd)

const UI_SIZE := Vector2i(1280, 720)
## Sign-in and play are drawn bigger (keys, sticks and buttons sized for
## thumbs); the dense menus (title, armory, gunsmith) keep UI_SIZE to fit.
const UI_SIZE_PLAY := Vector2i(1024, 576)
static var _play_ui := false

static var _touch := -1
static var _set_up := false
static var _defaults_done := false


## Layout size the phone UI is drawn at (smaller = bigger on screen).
## `-- --ui=WxH` overrides the play size for testing.
static func ui_size(play: bool = false) -> Vector2i:
	if not play:
		return UI_SIZE
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui="):
			var p := a.substr(5).split("x")
			if p.size() == 2:
				return Vector2i(int(p[0]), int(p[1]))
	return UI_SIZE_PLAY


## Bigger layout for sign-in and play, the regular one for menus.
static func set_play_ui(on: bool) -> void:
	if not touch_mode() or on == _play_ui:
		return
	_play_ui = on
	var root := (Engine.get_main_loop() as SceneTree).root
	root.content_scale_size = ui_size(on)


static func is_web() -> bool:
	return OS.has_feature("web")


static func touch_mode() -> bool:
	if _touch < 0:
		var on := OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("android") or OS.has_feature("ios")
		if is_web() and DisplayServer.is_touchscreen_available():
			on = true
		if "--touch" in OS.get_cmdline_user_args():
			on = true
		if "--no-touch" in OS.get_cmdline_user_args():
			on = false
		_touch = 1 if on else 0
	return _touch == 1


## First launch on a phone: the light map in Zombie Survival. Runs before
## main.gd reads the mode.
static func first_launch_defaults(main_script) -> void:
	if _defaults_done:
		return
	_defaults_done = true
	if touch_mode() and not main_script.quick_restart:
		main_script.saved_mode = "zombie"
		main_script.saved_map = "warehouse"


## Once per launch, after the input map and saved settings are loaded.
static func setup_once() -> void:
	if _set_up:
		return
	_set_up = true
	if not touch_mode():
		return
	var root := (Engine.get_main_loop() as SceneTree).root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = ui_size()
	# lighter rendering: SAFE preset, half-resolution 3D, 60 FPS
	var S = preload("res://scripts/core/settings.gd")
	S.set_preset(S.SAFE)
	S.v.render_scale = 0.5
	S.v.max_fps = 1
	S.v.shake = minf(float(S.v.shake), 0.6)
	S.apply()
	# a tap anywhere must not fire or aim: the sticks and buttons do that
	for action in ["fire", "aim"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)
