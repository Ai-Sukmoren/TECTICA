extends SceneTree
## First-person audit of every gun with every attachment it takes: hip and
## aimed, one picture each (needs a window).
##   godot --path . -s res://tests/previews/fov_audit.gd -- <out_dir> [gun ...]
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

## Default build, each optic on its own, then everything else fitted at once.
func configs(id: String) -> Array:
	var o: Dictionary = Data.WEAPONS[id].options
	var out: Array = [["default", {}]]
	for op in o.optic:
		if op in ["reddot", "holo"]:
			out.append([op, {"optic": op}])
	var full := {}
	for m in o.muzzle:
		if m in ["suppressor", "heavy_suppressor"]:
			full["muzzle"] = m
	if "laser" in o.underbarrel:
		full["underbarrel"] = "laser"
	if not full.is_empty():
		out.append(["kit", full])
	return out

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	var guns: Array = a.slice(1) if a.size() > 1 else Data.PRIMARIES + Data.SECONDARIES
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "desert"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.director.set_physics_process(false)
	main.hud.visible = false
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(0, 0.05, 30)
	p.aim_yaw = 0.0
	for id in guns:
		for c in configs(id):
			p.set_loadout([[id, c[1]], ["knife_combat", {}]])
			p.set_first_person(true)
			p.set_flashlight(true)
			p.fp_pitch = -0.03
			for aim in [false, true]:
				if aim:
					Input.action_press("aim")
				else:
					Input.action_release("aim")
				await frames(50)
				await RenderingServer.frame_post_draw
				var f := "%s/fov_%s_%s_%s.jpg" % [out, id, c[0], "ads" if aim else "hip"]
				root.get_texture().get_image().save_jpg(f, 0.85)
			Input.action_release("aim")
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
