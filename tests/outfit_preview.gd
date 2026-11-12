extends SceneTree
## Screenshots the Armory OUTFITS tab for a few outfits (needs a window).
##   godot --path . -s res://tests/outfit_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Outfits = preload("res://scripts/skins/outfits.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var arm = current_scene.hud.armory
	arm.open()
	arm.tab = 2
	for id in ["arctic", "neon", "gilded"]:
		arm.outfit_i = Outfits.ids().find(id)
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/outfit_" + id + ".jpg", 0.85)
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
