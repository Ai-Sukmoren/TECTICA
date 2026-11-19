extends SceneTree
## Movie-writer take for the 1.46 film: the FN SCAR-H on iron sights, in first person, brought up to the eye at 0.3x
## engine time (the engine itself runs slow: no interpolation), then one shot. Prints frame marks.
##   godot --path . --fixed-fps 60 --resolution 1920x1080 --write-movie scar.avi -s res://tests/previews/trailer146_scar.gd
const Main = preload("res://scripts/main.gd")
var main
func _initialize() -> void:
	call_deferred("run")
func frames(n: int) -> void:
	for i in n:
		main.player.health = 100000.0
		await process_frame
func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	Main._new_player_checked = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120: await process_frame
	main = current_scene
	main.director.set_physics_process(false)
	main.hud.visible = false
	main.tod.set("running", false)
	main.tod.set("hour", 16.8)
	var p = main.player
	p.set_loadout([["scar_h", {"optic": "iron"}], ["g17", {}], ["knife_combat", {}]])
	p.set_first_person(true)
	p.aim_yaw = 0.35
	await frames(90)
	print("MARK hip ", Engine.get_frames_drawn())
	Engine.time_scale = 0.3
	await frames(30)
	print("MARK raise ", Engine.get_frames_drawn())
	Input.action_press("aim")
	await frames(150)
	print("MARK fire ", Engine.get_frames_drawn())
	Input.action_press("fire")
	await frames(4)
	Input.action_release("fire")
	await frames(110)
	print("MARK end ", Engine.get_frames_drawn())
	Input.action_release("aim")
	Engine.time_scale = 1.0
	quit(0)
