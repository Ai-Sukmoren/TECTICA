extends SceneTree
## Every gun in first person in a real match scene, with every optic and muzzle it takes (paired up), under a skin
## with the sticker on: a hip and an aimed frame each, saved as <out>/<gun>.jpg sheets to look at. Needs a window.
##   godot --path . --resolution 1280x720 -s res://tests/previews/attachment_ingame.gd -- <out_dir> [skin]
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var main
var out := ""


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	return img


func run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var skin := args[1] if args.size() > 1 else "ruby"
	Main.saved_mode = "training"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	main = current_scene
	var p = main.player
	p.health = 100000.0
	p.max_health = 100000.0
	p.aim_yaw = 0.0
	p.fp_pitch = -0.05
	for id in Data.WEAPONS:
		var wd: Dictionary = Data.WEAPONS[id]
		if wd.get("kind", "") == "melee":
			continue
		var optics: Array = wd.options.get("optic", ["iron"])
		var muzzles: Array = wd.options.get("muzzle", ["none"])
		var n := maxi(optics.size(), muzzles.size())
		var shots: Array = []
		for k in n:
			var att := {"optic": optics[k % optics.size()], "muzzle": muzzles[k % muzzles.size()]}
			p.set_loadout([[id, Data.sanitize(id, att), skin, {"on": true, "id": "patch_02"}, "", {}]])
			p.aim_yaw = 0.0
			p.fp_pitch = -0.05
			await frames(25)
			shots.append([await grab(), "%s / %s" % [att.optic, att.muzzle]])
			Input.action_press("aim")
			await frames(45)
			shots.append([await grab(), "ADS"])
			Input.action_release("aim")
			await frames(15)
		var w: int = shots[0][0].get_width()
		var h: int = shots[0][0].get_height()
		var cols := 4
		var rows := int(ceil(shots.size() / float(cols)))
		var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
		for i in shots.size():
			var img: Image = shots[i][0]
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
		sheet.save_jpg("%s/%s.jpg" % [out, id], 0.8)
		var labels: Array = shots.map(func(s): return s[1])
		print("GUN %s %s" % [id, str(labels)])
	quit()
