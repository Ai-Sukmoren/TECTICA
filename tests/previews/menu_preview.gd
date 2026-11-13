extends SceneTree
## Renders the title menu to a PNG (needs a GPU):  godot --path . -s res://tests/previews/menu_preview.gd -- <out.png> [w] [h]
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var a := OS.get_cmdline_user_args()
	root.size = Vector2i(int(a[1]) if a.size() > 1 else 1600, int(a[2]) if a.size() > 2 else 900)
	load("res://scripts/core/profile.gd").current = "lilin"   # preview only: skip the sign-in screen
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120: await process_frame
	var hud = current_scene.get_node_or_null("HUD")
	print("[menu] signed_in=", hud.Profile.signed_in() if hud else "?", " title=", hud.title if hud else "?")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(a[0])
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
