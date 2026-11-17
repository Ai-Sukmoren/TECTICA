extends SceneTree
## The title menu's PLAY section for each MODE: campaign, Zombie Survival on
## TOKYO, Team Deathmatch vs AI and Free for All vs AI (needs a window).
##   godot --path . -s res://tests/previews/play_menu_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const HUD = preload("res://scripts/ui/hud.gd")

func _initialize() -> void:
	call_deferred("run")

func shot(out: String, name: String) -> void:
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/menu_" + name + ".jpg", 0.9)
	print("saved ", name)

func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	load("res://scripts/core/profile.gd").current = "lilin"
	for k in [["ch1", "", "forest", "campaign"], ["zombie", "", "tokyo", "zombie"], ["zombie", "tdm", "tokyo", "tdm"], ["zombie", "ffa", "warehouse", "ffa"]]:
		Main.saved_mode = k[0]
		Main.saved_map = k[2]
		HUD.vs_ai = k[1]
		change_scene_to_file("res://scenes/main.tscn")
		for i in 90: await process_frame
		var hud = current_scene.get_node("HUD")
		hud.menu_index = 1
		await shot(out, k[3])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
