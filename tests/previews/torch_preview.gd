extends SceneTree
## Weapon light check: every gun in the operator's hands, seen from its right
## side (and from below for pistols), light on. Prints the torch-to-gun gap.
## Needs a window.
##   godot --path . -s res://tests/previews/torch_preview.gd -- <out_dir> [tag]
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const TILE := Vector2i(400, 260)

func _initialize() -> void:
	call_deferred("run")

func grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var tag: String = a[1] if a.size() > 1 else "now"
	var guns: Array = Data.PRIMARIES + Data.SECONDARIES
	root.size = TILE
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("running", false)
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(2.0, 0.05, 30)
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 30.0
	cam.near = 0.02
	cam.make_current()
	var cols := 4
	var rows := int(ceil(guns.size() / float(cols)))
	var sheet := Image.create(TILE.x * cols, TILE.y * rows, false, Image.FORMAT_RGB8)
	for gi in guns.size():
		var id: String = guns[gi]
		p.set_loadout([[id, {}], ["knife_combat", {}]])
		p.set_first_person(false)
		p.set_flashlight(true)
		for i in 40: await process_frame
		var w = p.current_weapon()
		var t: Transform3D = w.global_transform
		var mid: Vector3 = t * (Vector3(0, 0.0, -0.08) if w.is_pistol() else Vector3(0, 0, -0.25))
		cam.global_position = t * (Vector3(0.6, -0.05, -0.1) if w.is_pistol() else Vector3(0.75, 0.05, -0.25))
		cam.look_at(mid, t.basis.y)
		for i in 3: await process_frame
		var img := await grab()
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i((gi % cols) * TILE.x, (gi / cols) * TILE.y))
		var torch: Node3D = p.get("_torch")
		print("  %-6s torch at %s (weapon space)" % [id, str((t.affine_inverse() * torch.global_position).snapped(Vector3.ONE * 0.001))])
	sheet.save_jpg(out + "/torch_%s.jpg" % tag, 0.88)
	print("saved torch_%s" % tag)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
