extends SceneTree
## Third-person run cycle sheet: 8 frames across a stride, seen from the side
## and from front-left, for jogging and sprinting with a rifle and a pistol.
## Needs a window.
##   godot --path . -s res://tests/previews/run_cycle_preview.gd -- <out_dir> [tag]
const Main = preload("res://scripts/main.gd")
const TILE := Vector2i(300, 360)
const N := 8

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
	var gun: String = a[2] if a.size() > 2 else "m4a1"
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
	p.set_loadout([[gun, {}], ["mk23", {}], ["knife_combat", {}]])
	p.set_first_person(false)
	p.using_pad = true            # no mouse aim: face where we run
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 34.0
	cam.make_current()
	var rows: Array = [["rifle", "jog"], ["rifle", "sprint"], ["pistol", "jog"], ["pistol", "sprint"]]
	var views := ["side", "front"]
	var sheet := Image.create(TILE.x * N, TILE.y * rows.size() * views.size(), false, Image.FORMAT_RGB8)
	var row := 0
	for r in rows:
		p.switch_to(0 if r[0] == "rifle" else 1)
		for i in 50: await physics_frame
		for v in views:
			p.global_position = Vector3(1.0, 0.05, 42)
			p.set("_pad_dir", Vector3.FORWARD)
			p.aim_yaw = 0.0   # run north (-z)
			p.velocity = Vector3.ZERO
			p.reset_physics_interpolation()
			for i in 5: await physics_frame
			Input.action_press("move_forward", 1.0)
			if r[1] == "sprint":
				Input.action_press("sprint")
			for i in 70:
				main.camera_rig.yaw = 0.0
				await physics_frame
			# one stride is 2*PI of rig.phase: sample N evenly spaced phases
			var start: float = p.rig.phase
			var k := 0
			var guard := 0
			while k < N and guard < 600:
				guard += 1
				main.camera_rig.yaw = 0.0
				await process_frame
				var d: float = fposmod(p.rig.phase - start, TAU)
				if d >= k * TAU / N - 0.01 or (k == 0):
					var c: Vector3 = p.global_position + Vector3.UP * 1.0
					if v == "side":
						cam.global_position = c + Vector3(3.0, 0.1, 0)
					else:
						cam.global_position = c + Vector3(1.6, 0.3, -3.2)
					cam.look_at(c)
					await process_frame
					sheet.blit_rect(await grab(), Rect2i(Vector2i.ZERO, TILE), Vector2i(k * TILE.x, row * TILE.y))
					k += 1
			for x in ["move_forward", "sprint"]:
				Input.action_release(x)
			for i in 30: await physics_frame
			print("  row %d: %s %s %s frames=%d z=%.1f" % [row, r[0], r[1], v, k, p.global_position.z])
			row += 1
	sheet.save_jpg(out + "/run_cycle_%s.jpg" % tag, 0.86)
	print("saved run_cycle_%s" % tag)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
