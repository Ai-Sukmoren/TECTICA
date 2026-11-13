extends SceneTree
## Support-hand check: every gun in the operator's hands, seen from the left
## (support side), from above-left, and in first person; plus the left hand's
## distance to the gun's support marker. Needs a window.
##   godot --path . -s res://tests/previews/support_hand_preview.gd -- <out_dir> [gun ids]
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

const TILE := Vector2i(480, 360)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var guns: Array = a.slice(1) if a.size() > 1 else Data.PRIMARIES + Data.SECONDARIES
	root.size = TILE
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("running", false)
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(2.0, 0.05, 30)
	p.aim_yaw = 0.0
	var cam := Camera3D.new()
	main.add_child(cam)
	var sheet := Image.create(TILE.x * 3, TILE.y * guns.size(), false, Image.FORMAT_RGB8)
	for gi in guns.size():
		var id: String = guns[gi]
		p.set_loadout([[id, {}], ["knife_combat", {}]])
		p.set_first_person(false)
		main.camera_rig.override = true
		cam.fov = 30.0
		cam.make_current()
		await frames(40)
		var chest: Vector3 = p.rig.chest.global_position
		var tw = p.current_weapon()
		print("  %-6s third person: left hand to support marker %.1f cm" % [id, p.rig.hands[0].global_position.distance_to(tw.support.global_position) * 100.0])
		# left side (support hand faces the camera)
		cam.global_position = chest + Vector3(-1.25, 0.05, -0.35)
		cam.look_at(chest + Vector3(-0.05, -0.05, -0.32))
		await frames(4)
		sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i(0, gi * TILE.y))
		# above-left, three-quarter
		cam.global_position = chest + Vector3(-0.8, 0.75, -1.0)
		cam.look_at(chest + Vector3(-0.02, -0.08, -0.3))
		await frames(4)
		sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i(TILE.x, gi * TILE.y))
		# first person
		main.camera_rig.override = false
		p.set_first_person(true)
		p.fp_pitch = -0.05
		await frames(40)
		sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i(TILE.x * 2, gi * TILE.y))
		var w = p.current_weapon()
		var hand: Vector3 = p.rig.hands[0].global_position
		var sup: Vector3 = w.support.global_position if w.support != null else Vector3.INF
		print("  %-6s first person: left hand to support marker %.1f cm" % [id, hand.distance_to(sup) * 100.0])
	sheet.save_jpg(out + "/support_hands.jpg", 0.88)
	print("saved support_hands")
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
