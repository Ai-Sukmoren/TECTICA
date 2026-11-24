extends SceneTree
## Movie-writer clip: the weapon light on a gun in first person, at night in the forest, as the player sees it.
##   godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie light.avi -s res://tests/previews/torch_ingame_video.gd -- [gun id]
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var gun: String = a[0] if a.size() > 0 else "p90"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	Main._new_player_checked = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/loading.tscn")
	while not (current_scene != null and current_scene.get_script() == Main and not root.get_node("MapTransition")._busy):
		await process_frame
	var main = current_scene
	main.director.active = false
	main.tod.set("running", false)
	main.tod.set("hour", 22.5)
	var p = main.player
	p.set_loadout([[gun, {}, "", {}, "", {}]])
	p.set_first_person(true)
	p.set_flashlight(true)
	p.health = 100000.0
	for i in 60:
		await process_frame
	print("SHOT_START ", Engine.get_frames_drawn())
	for i in 300:   # look around slowly: left, right, then down at the ground
		var t := i / 60.0
		p.aim_yaw += sin(t * 1.3) * 0.004
		p.fp_pitch = -0.12 - 0.12 * sin(t * 0.9)
		await process_frame
	quit(0)
