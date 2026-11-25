extends SceneTree
## Movie-writer clip: each gun in first person on the training range, as the player sees it:
## a look at it from the hip, aim down the sights, a burst, then a reload.
## Each argument is a gun id, optionally with attachments: aug_a4:optic=reddot,underbarrel=afg,side=laser
## Prints "GUN <id> <first frame>" so captions can be timed.
##   godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie fp.avi -s res://tests/previews/new_guns_fp_video.gd -- <ids...>
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

func _initialize() -> void:
	run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	Main.saved_mode = "training"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(120)
	var p = current_scene.player
	p.health = 100000.0
	p.max_health = 100000.0
	for id in ids:
		var parts := String(id).split(":")
		var gid := parts[0]
		var want := {}
		if parts.size() > 1:
			for kv in parts[1].split(","):
				want[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
		var att: Dictionary = Data.sanitize(gid, want)
		p.set_loadout([[gid, att, "", {}, "", {}]])
		p.aim_yaw = 0.0
		p.fp_pitch = -0.05
		await frames(20)
		print("GUN ", gid, " ", Engine.get_frames_drawn(), " ", att)
		for i in 70:   # hip: a slow look left and back
			p.aim_yaw += sin(i / 70.0 * TAU) * 0.003
			await process_frame
		Input.action_press("aim")
		await frames(45)
		Input.action_press("fire")
		await frames(40)
		Input.action_release("fire")
		await frames(25)
		Input.action_release("aim")
		await frames(10)
		Input.action_press("reload")
		await process_frame
		Input.action_release("reload")
		await frames(150)
	quit(0)
