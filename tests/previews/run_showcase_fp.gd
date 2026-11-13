extends SceneTree
## Movie-writer clip of the first-person run: rifle jog, rifle sprint,
## pistol jog, pistol sprint, down the town road.
##   godot --path . --fixed-fps 60 --write-movie run_fp.avi -s res://tests/previews/run_showcase_fp.gd
const Main = preload("res://scripts/main.gd")

var main
var p

func _initialize() -> void:
	call_deferred("run")

func leg(seconds: float, sprint: bool) -> void:
	p.global_position = Vector3(1.0, 0.05, 46)
	p.aim_yaw = 0.0
	p.fp_pitch = -0.04
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	for i in 6: await process_frame
	Input.action_press("move_forward", 1.0)
	if sprint:
		Input.action_press("sprint")
	for i in int(seconds * 60.0):
		p.aim_yaw = 0.0
		await process_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	for i in 24: await process_frame

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
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
	p.set_first_person(true)
	p.set_process_input(false)   # no mouse look while filming
	for i in 40: await process_frame
	print("SHOT_START ", Engine.get_frames_drawn())
	await leg(2.6, false)    # rifle jog
	await leg(3.2, true)     # rifle sprint
	p.switch_to(1)
	for i in 50: await process_frame
	await leg(2.4, false)    # pistol jog
	await leg(3.0, true)     # pistol sprint
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
