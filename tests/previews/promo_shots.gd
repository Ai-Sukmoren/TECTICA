extends SceneTree
## Scripted footage for an update promo. Run under the movie writer:
##   godot --path . --resolution 1280x720 --fixed-fps 60 --write-movie out.avi \
##       -s res://tests/previews/promo_shots.gd -- <forest|town>
## Prints "SHOT <name> <first frame> <last frame>" for cutting.
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Nature = preload("res://scripts/world/nature.gd")

var fc := 0
var main
var cam: Camera3D
var rig

func _initialize() -> void:
	call_deferred("run")

func _process(_d: float) -> bool:
	fc += 1
	return false

func frames(n: int) -> void:
	for i in n:
		await process_frame

## Free-camera move from `a` to `b`, looking at `t0` -> `t1`.
func fly(shot_name: String, hour: float, a: Vector3, b: Vector3, t0: Vector3, t1: Vector3, n: int) -> void:
	main.tod.set("hour", hour)
	rig.override = true
	cam.global_position = a
	cam.look_at(t0)
	for i in 40:
		cam.make_current()
		Nature.set_view(a)
		await process_frame
	var first := fc
	for i in n:
		var u := float(i) / float(n - 1)
		u = u * u * (3.0 - 2.0 * u)
		cam.global_position = a.lerp(b, u)
		cam.look_at(t0.lerp(t1, u))
		cam.make_current()
		Nature.set_view(cam.global_position)
		await process_frame
	print("SHOT %s %d %d" % [shot_name, first, fc])

func run() -> void:
	var map: String = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = map
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	main = current_scene
	for k in Settings.PRESET_VALUES:
		Settings.v[k] = Settings.PRESET_VALUES[k][2]
	main.apply_graphics()
	main.hud.visible = false
	main.director.timer = 9999.0
	var p = main.player
	p.health = 100000.0
	rig = get_nodes_in_group("camera_rig")[0]
	cam = Camera3D.new()
	cam.fov = 58
	root.add_child(cam)
	var extra: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	var only_td := extra == "td"
	if map == "forest":
		await fly("leaf", 14.0, Vector3(-2, 2.6, 18), Vector3(4, 3.4, 23), Vector3(30, 8, 45), Vector3(30, 9, 45), 300)
		await fly("pine", 14.0, Vector3(-6, 2.2, 12), Vector3(-10, 3.2, 16), Vector3(-30, 8, 30), Vector3(-30, 10, 30), 300)
		await fly("dusk", 18.6, Vector3(0, 3.5, 2), Vector3(5, 4.5, -3), Vector3(20, 6, -30), Vector3(24, 7, -30), 270)
	elif only_td:
		pass
	elif extra != "":
		# first person with one gun (weapon id in `extra`): four shots
		main.tod.set("hour", 13.0)
		p.global_position = Vector3(2.0, 0.05, 30)
		p.aim_yaw = 0.0
		p.set_loadout([[extra, {}], ["knife_combat", {}]])
		p.set_first_person(true)
		p.fp_pitch = -0.02
		await frames(70)
		var g0 := fc
		for s in 2:
			Input.action_press("fire")
			await frames(2)
			Input.action_release("fire")
			await frames(64)
		print("SHOT gun %d %d" % [g0, fc])
		Settings.mark_clean_exit()
		quit(0)
		return
	else:
		await fly("car", 14.0, Vector3(-19, 1.5, 32.5), Vector3(-23.5, 1.2, 31.2), Vector3(-24.5, 0.7, 36.4), Vector3(-24.5, 0.8, 36.4), 300)
		await fly("room", 14.0, Vector3(-15.6, 1.6, -19.6), Vector3(-17, 1.6, -18.2), Vector3(-22, 1.1, -19), Vector3(-22, 1.2, -18.5), 240)
		await fly("night", 23.0, Vector3(-7, 1.8, 7), Vector3(-4, 2.0, 5), Vector3(3, 1.6, -3), Vector3(6, 2.5, -8), 270)
		# first person with the rolling block: three shots, each followed by the roll
		main.tod.set("hour", 13.0)
		rig.override = false
		p.global_position = Vector3(2.0, 0.05, 30)
		p.aim_yaw = 0.0
		p.set_loadout([["rb45", {}], ["knife_combat", {}]])
		p.set_first_person(true)
		p.fp_pitch = -0.02
		await frames(70)
		var first := fc
		for s in 3:
			Input.action_press("fire")
			await frames(2)
			Input.action_release("fire")
			await frames(78)
		print("SHOT roll %d %d" % [first, fc])
	if map == "town":
		# top-down: walk up the road with the roof cutaway camera
		p.set_first_person(false)
		p.global_position = Vector3(1.0, 0.05, 42)
		rig.yaw = 0.0
		await frames(50)
		var first2 := fc
		p.using_pad = true
		for i in 270:
			p.set("_pad_dir", Vector3.FORWARD)
			await process_frame
		print("SHOT topdown %d %d" % [first2, fc])
	Settings.mark_clean_exit()
	quit(0)
