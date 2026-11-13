extends SceneTree
## Before/after visual audit: first-person + top-down shots of both zombie maps
## at day and dusk, at a fixed quality preset (needs a window, not --headless).
##   godot --path . -s res://tests/previews/visual_audit.gd -- <out_dir> [preset 0-3] [tag]
## Settings are changed in memory only; nothing is saved.
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var preset := int(a[1]) if a.size() > 1 else 2
	var tag: String = a[2] if a.size() > 2 else "shot"
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	for map in ["forest", "town"]:
		Main.saved_mode = "zombie"
		Main.saved_map = map
		Main.quick_restart = true
		Main.saved_first_person = false
		change_scene_to_file("res://scenes/main.tscn")
		await frames(90)
		var main = current_scene
		for k in Settings.PRESET_VALUES:
			Settings.v[k] = Settings.PRESET_VALUES[k][preset]
		Settings.v.preset = preset
		main.apply_graphics()
		main.hud.visible = false
		main.director.timer = 9999.0
		var p = main.player
		p.health = 100000.0
		for hour in [14.0, 18.6]:
			main.tod.set("hour", hour)
			for view in ["fp", "td"]:
				p.set_first_person(view == "fp")
				await frames(45)
				await RenderingServer.frame_post_draw
				var f := "%s/%s_%s_%s_%02d.jpg" % [out, tag, map, view, int(hour)]
				root.get_texture().get_image().save_jpg(f, 0.88)
				print("saved ", f)
	Settings.mark_clean_exit()   # a windowed run is not a crash
	quit(0)
