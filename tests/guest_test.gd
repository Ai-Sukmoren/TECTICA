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
	check(hud._needs_auth(), "signed out: the sign-in screen shows")
	var gi: int = hud.AUTH_ROWS.find("PLAY AS GUEST")
	check(gi >= 0 and gi < hud.AUTH_ROWS.find("QUIT"), "PLAY AS GUEST sits above QUIT")
	Campaign.completed = {}
	hud._auth_activate(gi)
	await frames(60)
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
	# CREATE ACCOUNT: back to the sign-in screen with an empty name and the hand-over note
	hud._menu_activate(ids.find("account"))
	await frames(60)
	hud = current_scene.hud
	check(hud._needs_auth() and Profile._from_guest, "CREATE ACCOUNT signs the guest out to the sign-in screen")
	check(String(hud._auth_user) == "" and String(hud._auth_msg).contains("GUEST PROGRESS"), "the screen says the guest's progress comes along")
	check(not Profile.signed_in(), "signing out does not bounce straight back into the guest")
	print("GUEST: failures=%d" % failures)
	Profile._from_guest = false
	Settings.mark_clean_exit()
	quit(1 if failures > 0 else 0)
