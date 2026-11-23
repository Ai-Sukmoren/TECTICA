extends SceneTree
## New players: PLAY AS GUEST on the sign-in screen, the guest's title menu
## (CREATE ACCOUNT instead of SIGN OUT, no GRAPHICS / MUSIC rows), a guest with
## no progress deploys into TRAINING, and "guest" can't be taken as a username.
## Never writes user://accounts.cfg (progress files go to the test sandbox).
##   godot --headless --path . -s res://tests/guest_test.gd
const Main = preload("res://scripts/main.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Campaign = preload("res://scripts/modes/campaign.gd")
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

## Waits for the map transition to finish (a new one is ignored while it runs).
func settle() -> void:
	var T = load("res://scripts/ui/transition.gd")
	for i in 600:
		await process_frame
		if T._inst == null or not T._inst._busy:
			break
	await frames(5)


func run() -> void:
	check(Profile.check_name("guest") != "" and Profile.check_name("GUEST") != "", "\"guest\" is reserved as a username")
	check(Profile.check_name("rookie") == "", "an ordinary username is still fine")
	# signed out on a PC with accounts: the sign-in screen offers PLAY AS GUEST
	Profile.current = ""
	Main.quick_restart = false
	Main.saved_mode = "ch1"
	change_scene_to_file("res://scenes/main.tscn")
	await frames(30)
	var hud = current_scene.hud
	var before = current_scene
	check(hud._needs_auth(), "signed out: the sign-in screen shows")
	var gi: int = hud.AUTH_ROWS.find("PLAY AS GUEST")
	check(gi >= 0 and gi < hud.AUTH_ROWS.find("QUIT"), "PLAY AS GUEST sits above QUIT")
	Campaign.completed = {}
	before = current_scene
	hud._auth_activate(gi)
	for i in 600:
		await process_frame
		if current_scene != before and current_scene != null and current_scene.get("hud") != null:
			break
	await settle()
	hud = current_scene.hud
	check(Profile.is_guest() and Profile.signed_in(), "PLAY AS GUEST signs in as the guest")
	check(not hud._needs_auth(), "the guest goes straight to the title menu")
	check(Profile.path("loadout.cfg").contains("profiles/guest/"), "the guest keeps its own progress files")
	# no finished chapter or training: DEPLOY starts the training course
	check(current_scene.mode == "training", "a guest with no progress deploys into TRAINING (mode=%s)" % current_scene.mode)
	var ids: Array = hud._menu_entries().map(func(e): return String(e.id))
	check(not ids.has("graphics") and not ids.has("music") and ids.has("settings"), "GRAPHICS and MUSIC moved into SETTINGS")
	var acc: Dictionary = hud._menu_entries()[ids.find("account")]
	check(String(acc.label) == "CREATE ACCOUNT", "the guest's menu offers CREATE ACCOUNT instead of SIGN OUT")
	# A guest can skip directly to Survival from the Mode picker.
	hud.menu_index = hud._menu_index_of("mode")
	var input := InputEventAction.new()
	input.pressed = true
	input.action = "ui_accept"
	hud._unhandled_input(input)
	check(hud._mode_picker_index >= 0 and Main.saved_mode == "training", "opening Mode leaves Training loaded")
	input.action = "ui_cancel"
	hud._unhandled_input(input)
	check(hud._mode_picker_index == -1 and Main.saved_mode == "training", "cancel closes the picker and keeps the mode")
	input.action = "ui_accept"
	hud._unhandled_input(input)
	input.action = "ui_down"
	for i in hud._play_choices().find("zombie"):
		hud._unhandled_input(input)
	check(Main.saved_mode == "training", "browsing modes does not load other chapters")
	input.action = "ui_accept"
	before = current_scene
	hud._unhandled_input(input)
	check(Main.saved_mode == "zombie", "confirm selects Zombie Survival directly")
	for i in 600:
		await process_frame
		if current_scene != before and current_scene != null and current_scene.get("hud") != null:
			break
	await settle()
	hud = current_scene.hud
	check(current_scene.mode == "zombie" and hud.title, "the picker arrives at the Survival title menu")

	# CREATE ACCOUNT: back to the sign-in screen with an empty name and the hand-over note
	before = current_scene
	hud._menu_activate(hud._menu_index_of("account"))
	for i in 600:   # until the map has reloaded signed out (the transition takes a moment)
		await process_frame
		if current_scene != before and current_scene != null and current_scene.get("hud") != null:
			break
	await settle()
	hud = current_scene.hud
	check(hud._needs_auth() and Profile._from_guest, "CREATE ACCOUNT signs the guest out to the sign-in screen")
	check(String(hud._auth_user) == "" and String(hud._auth_msg).contains("GUEST PROGRESS"), "the screen says the guest's progress comes along")
	check(not Profile.signed_in(), "signing out does not bounce straight back into the guest")
	print("GUEST: failures=%d" % failures)
	Profile._from_guest = false
	Settings.mark_clean_exit()
	quit(1 if failures > 0 else 0)
