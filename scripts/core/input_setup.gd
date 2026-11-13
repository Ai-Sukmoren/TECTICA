extends RefCounted
## Registers the input map at runtime (keyboard/mouse + gamepad) so the
## project needs no editor setup.
##
## Gamepad (Xbox naming): L-stick move, R-stick aim, RT fire, LT aim,
## L3 sprint, A vault, B crouch, X reload, Y switch weapon, LB/RB peek,
## D-pad left/right rotate camera, D-pad up/down zoom, Start pause, Back debug.

static func setup() -> void:
	Input.use_accumulated_input = false
	if not InputMap.has_action("inspect"):
		_act("inspect", [KEY_I])
	if not InputMap.has_action("weapon_3"):
		_act("weapon_3", [KEY_3])
	if InputMap.has_action("flashlight"):
		return
	_act("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_act("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_act("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_act("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_act("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_act("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_act("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_act("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_act("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK])
	_act("crouch", [KEY_C, KEY_CTRL], [JOY_BUTTON_B])
	_act("vault", [KEY_SPACE], [JOY_BUTTON_A])
	_act("kick", [KEY_V], [JOY_BUTTON_DPAD_RIGHT])
	_act("reload", [KEY_R], [JOY_BUTTON_X])
	_act("peek_left", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_act("peek_right", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	_act("weapon_1", [KEY_1])
	_act("weapon_2", [KEY_2])
	_act("switch_weapon", [KEY_X], [JOY_BUTTON_Y])
	_act("cam_rot_left", [KEY_Z], [JOY_BUTTON_DPAD_LEFT])
	_act("cam_rot_right", [KEY_V], [JOY_BUTTON_DPAD_RIGHT])
	_act("zoom_in", [], [JOY_BUTTON_DPAD_UP])
	_act("zoom_out", [], [])
	_act("grenade", [KEY_G], [JOY_BUTTON_DPAD_DOWN])
	_act("flashbang", [KEY_H], [])
	_act("toggle_debug", [KEY_F1])
	_act("flashlight", [KEY_T], [JOY_BUTTON_BACK])
	_act("interact", [KEY_F], [JOY_BUTTON_X])
	_act("shop", [KEY_B])
	_act("toggle_view", [KEY_F], [JOY_BUTTON_RIGHT_STICK])
	_act("quality", [KEY_F2])
	_act("music", [KEY_M])
	_act("restart", [KEY_ENTER], [JOY_BUTTON_A])
	_act("pause", [KEY_ESCAPE], [JOY_BUTTON_START])
	_act("fire", [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_act("aim", [], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_mouse("fire", MOUSE_BUTTON_LEFT)
	_mouse("aim", MOUSE_BUTTON_RIGHT)
	# the player's own key bindings (settings > CONTROLS)
	preload("res://scripts/core/controls.gd").init_after_defaults()


static func _act(action: String, keys: Array, buttons: Array = [], axes: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(action, jm)


static func _mouse(action: String, button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
