extends SceneTree
## Phone screens in touch mode at a landscape phone shape: sign-in, title menu,
## armory, gunsmith, settings, in game and the zombie shop (needs a window).
##   godot --path . --resolution 1688x780 -s res://tests/previews/phone_preview.gd -- --touch [--ui=WxH] <out_dir>
const Main = preload("res://scripts/main.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Settings = preload("res://scripts/core/settings.gd")
var out := "user://"

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func snap(name: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("%s/%s.jpg" % [out, name], 0.88)
	print("saved ", name)

func run() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			out = a
	Settings.ensure()
	Settings.v.window_mode = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1688, 780))
	Profile.current = ""
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	change_scene_to_file("res://scenes/main.tscn")
	await frames(120)
	var hud = current_scene.hud
	hud._auth_user = "lilin"
	hud._auth_row = 1
	hud._auth_pin = "12"
	await snap("01_signin")
	Profile.current = "lilin"
	hud._switch_profile()
	await frames(90)
	hud = current_scene.hud
	await snap("02_title")
	hud.armory.open()
	await snap("03_armory")
	hud.armory.close()
	hud.gunsmith.open()
	await snap("04_gunsmith")
	hud.gunsmith.close()
	hud.settings_open = true
	await snap("05_settings")
	hud.settings_open = false
	hud._deploy()
	await frames(150)
	var main = current_scene
	main.player.health = 100000.0
	await snap("06_ingame")
	main.director.active = false
	main.director.timer = 9999.0
	hud._open_shop()
	await snap("07_shop")
	Settings.mark_clean_exit()
	quit(0)
