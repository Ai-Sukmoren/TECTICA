extends SceneTree
## Title screen operator before and after changing outfit, class and skin.
## Needs a window.
##   godot --path . -s res://tests/previews/menu_live_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Collection = preload("res://scripts/skins/collection.gd")

func _initialize() -> void:
	call_deferred("run")

func wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout

func grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	root.size = Vector2i(960, 540)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	Main.quick_restart = false
	change_scene_to_file("res://scenes/main.tscn")
	await wait(1.5)
	var main = current_scene
	var cam = main.hud.menu_cam
	var outfit0 := Collection.outfit
	var class0 := Loadout.class_index
	var shots: Array = []
	for step in 3:
		if step == 1:
			Collection.outfit = "carbon"
		elif step == 2:
			Collection.outfit = "night_ops"
			Loadout.cycle_class(1)
		# hold the hero shot so every frame is comparable
		cam.shot = 0
		cam.t = 3.0
		await wait(0.8)
		cam.shot = 0
		cam.t = 3.0
		await wait(0.1)
		shots.append(await grab())
	var sheet := Image.create(960 * 3, 540, false, Image.FORMAT_RGB8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, 960, 540), Vector2i(960 * i, 0))
	sheet.save_jpg(out + "/menu_live.jpg", 0.88)
	print("saved menu_live")
	Collection.outfit = outfit0
	while Loadout.class_index != class0:
		Loadout.cycle_class(1)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
