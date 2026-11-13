extends SceneTree
## Movie-writer clip of the third-person run: rifle jog, rifle sprint (side,
## then front three-quarter), then a pistol sprint. Tracking camera.
##   godot --path . --fixed-fps 60 --write-movie run.avi -s res://tests/previews/run_showcase.gd
const Main = preload("res://scripts/main.gd")

var main
var p
var cam: Camera3D

func _initialize() -> void:
	call_deferred("run")

func leg(seconds: float, sprint: bool, offset: Vector3, look_up: float) -> void:
	p.global_position = Vector3(1.0, 0.05, 46)
	p.aim_yaw = 0.0
	p.velocity = Vector3.ZERO
	p.set("_pad_dir", Vector3.FORWARD)
	p.reset_physics_interpolation()
	Input.action_press("move_forward", 1.0)
	if sprint:
		Input.action_press("sprint")
	var n := int(seconds * 60.0)
	for i in n:
		main.camera_rig.yaw = 0.0
		var c: Vector3 = p.global_position + Vector3.UP * look_up
		cam.global_position = c + offset
		cam.look_at(c)
		await process_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	for i in 20:
		main.camera_rig.yaw = 0.0
		await process_frame

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	main = current_scene
	p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("running", false)
	main.tod.set("hour", 15.0)
	p.set_loadout([["m4a1", {"optic": "reddot"}], ["mk23", {}], ["knife_combat", {}]])
	p.set_first_person(false)
	p.using_pad = true
	main.camera_rig.override = true
	cam = Camera3D.new()
	main.add_child(cam)
	cam.fov = 40.0
	cam.make_current()
	for i in 30: await process_frame
	print("SHOT_START ", Engine.get_frames_drawn())
	await leg(2.6, false, Vector3(3.4, 0.2, 0.3), 1.0)        # rifle jog, side
	await leg(3.2, true, Vector3(3.6, 0.2, 0.3), 1.0)         # rifle sprint, side
	await leg(3.2, true, Vector3(1.9, 0.35, -3.6), 1.05)      # rifle sprint, front 3/4
	p.switch_to(1)
	for i in 50: await process_frame
	await leg(3.0, true, Vector3(3.4, 0.25, -1.2), 1.0)       # pistol sprint
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
