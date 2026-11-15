extends SceneTree
## Phone (touch mode): create an account and sign in using only finger taps
## (the USERNAME / PASSWORD fields and the SIGN IN / CREATE ACCOUNT buttons in
## the keyboard bar, the on-screen keys), then reach every title menu row and
## leave the Armory with the BACK button. Needs a window:
##   godot --path . -s res://tests/touch_signin_test.gd -- --touch
const Main = preload("res://scripts/main.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Settings = preload("res://scripts/core/settings.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

## A finger tap at a point in the UI layout space.
func tap(p: Vector2) -> void:
	var screen: Vector2 = root.get_final_transform() * p
	var d := InputEventScreenTouch.new()
	d.index = 0
	d.position = screen
	d.pressed = true
	Input.parse_input_event(d)
	await frames(3)
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = screen
	u.pressed = false
	Input.parse_input_event(u)
	await frames(3)

func key(tc, label: String) -> Rect2:
	tc._layout_keyboard()
	for k in tc._keys:
		if String(k[1]) == label:
			return k[0]
	return Rect2()

func type_text(tc, s: String) -> void:
	for ch in s.to_upper():
		var r := key(tc, ch)
		if r.size == Vector2.ZERO:
			check(false, "key %s exists" % ch)
			continue
		await tap(r.get_center())

func hud_now():
	return current_scene.hud

func run() -> void:
	Settings.ensure()
	Settings.v.window_mode = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	Profile.current = ""
	Main.quick_restart = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(120)
	var hud = hud_now()
	var tc = hud.touch
	check(tc != null, "touch controls are on")
	check(hud._needs_auth() and tc.wants_keyboard(), "sign-in screen with the on-screen keyboard")
	check(root.content_scale_size == Vector2i(1024, 576), "sign-in uses the bigger phone layout")
	hud._auth_user = ""
	hud._auth_pin = ""
	var nm := "ph%d" % (Time.get_ticks_usec() % 100000)
	await tap(key(tc, "USERNAME").get_center())
	check(int(hud._auth_row) == 0, "tapping the USERNAME field selects it")
	await type_text(tc, nm)
	check(String(hud._auth_user).to_lower() == nm, "typed the username (%s)" % hud._auth_user)
	await tap(key(tc, "PASSWORD").get_center())
	check(int(hud._auth_row) == 1, "tapping the PASSWORD field selects it")
	await type_text(tc, "4826")
	check(String(hud._auth_pin) == "4826", "typed the 4-digit password")
	await tap(key(tc, "CREATE ACCOUNT").get_center())
	await frames(30)
	check(Profile.signed_in() and Profile.current.to_lower() == nm, "CREATE ACCOUNT signs the new account in")
	hud = hud_now()
	hud._sign_out()
	await frames(40)
	hud = hud_now()
	tc = hud.touch
	hud._auth_user = ""
	hud._auth_pin = ""
	await tap(key(tc, "USERNAME").get_center())
	await type_text(tc, nm)
	await tap(key(tc, "PASSWORD").get_center())
	await type_text(tc, "4826")
	await tap(key(tc, "SIGN IN").get_center())
	await frames(30)
	check(Profile.signed_in() and Profile.current.to_lower() == nm, "SIGN IN with taps works")
	# title menu: every row is on screen
	hud = hud_now()
	tc = hud.touch
	await frames(20)
	check(root.content_scale_size == Vector2i(1280, 720), "menus use the regular layout")
	var vp: Vector2 = hud.overlay.size
	var all_on: bool = not hud._menu_rects.is_empty()
	for r in hud._menu_rects:
		if (r as Rect2).end.y > vp.y - 44.0 or (r as Rect2).position.y < 0.0:
			all_on = false
	check(all_on and hud._menu_rects.size() == hud._menu_entries().size(), "every title menu row fits on the phone screen (%d rows)" % hud._menu_rects.size())
	# armory -> BACK
	await tap((hud._menu_rects[hud._menu_index_of("armory")] as Rect2).get_center())
	await frames(10)
	check(hud.armory.is_open, "tapping ARMORY opens it")
	check(tc.wants_back(), "BACK shows in the Armory")
	await tap(tc.BACK_RECT.get_center())
	await frames(10)
	check(not hud.armory.is_open, "BACK leaves the Armory")
	print("TOUCH SIGN-IN: failures=%d" % failures)
	Settings.mark_clean_exit()
	quit(1 if failures > 0 else 0)
