extends RefCounted
## Phone / tablet support. Touch mode turns on for phone and tablet browsers
## (and on a desktop with `-- --touch` for testing). It:
##   * scales the whole UI from a 1280x720 layout so menus fit a phone
##   * starts on the lighter graphics and the DEAD END map
##   * takes fire / aim off the (touch-emulated) mouse so a tap is not a shot
##   * adds the on-screen sticks, buttons and keyboard (touch_controls.gd)

const UI_SIZE := Vector2i(1280, 720)

static var _touch := -1
static var _set_up := false
static var _defaults_done := false


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
		main_script.saved_map = "town"


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
	root.content_scale_size = UI_SIZE
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
