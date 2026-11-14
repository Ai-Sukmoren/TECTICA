extends SceneTree
## The rolling-block pistol in first person: hip, sights, and frames through
## the roll that follows a shot. Needs a window.
##   godot --path . -s res://tests/previews/rb_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(out: String, tag: String) -> void:
	await RenderingServer.frame_post_draw
	var f := "%s/db_%s.jpg" % [out, tag]
	root.get_texture().get_image().save_jpg(f, 0.9)
	print("saved ", f)

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(2.0, 0.05, 30)
	p.aim_yaw = 0.0
	p.set_loadout([["db2", {}], ["knife_combat", {}]])
	p.set_first_person(true)
	p.fp_pitch = -0.02
	await frames(60)
	await shot(out, "hip")
	Input.action_press("aim")
	await frames(50)
	await shot(out, "ads")
	Input.action_release("aim")
	await frames(40)
	Input.action_press("fire")
	await frames(2)
	Input.action_release("fire")
	var n := 0
	var last := -1.0
	for i in 90:
		await process_frame
		var ct: float = p.rig.cycle_t
		for mark in [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
			if last < mark and ct >= mark:
				await shot(out, "roll_%d" % n)
				n += 1
		last = ct
	print("ammo ", p.current_weapon().ammo)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
