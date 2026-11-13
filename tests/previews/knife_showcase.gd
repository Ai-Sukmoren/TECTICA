extends SceneTree
## A short first-person showcase of the knives: for each one, idle, the
## inspect flourish, a forehand + backhand slash and a sprint. Meant for
## Godot's movie writer:
##   godot --path . --resolution 1280x720 --fixed-fps 60 --write-movie out.avi -s res://tests/previews/knife_showcase.gd
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await process_frame

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("hour", 17.6)   # warm late-afternoon light
	for knife in ["knife_combat", "karambit", "butterfly"]:
		p.global_position = Vector3(0, 0.05, 38)
		p.aim_yaw = 0.0
		p.set_loadout([["m4a1", {}], ["mk23", {}], [knife, {}]])
		p.weapon_index = 2
		p._equip_current()
		p.set_first_person(true)
		main.camera_rig.first_person = true
		await wait(1.0)
		p.rig.play_inspect()
		while p.rig.inspect_t >= 0.0:
			await process_frame
		await wait(0.5)
		for n in 2:
			p.current_weapon().cooldown = 0.0
			p.try_fire(p.global_position + Vector3(0, 1.2, -3))
			await wait(0.7)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await wait(1.6)
		Input.action_release("sprint")
		Input.action_release("move_forward")
		await wait(0.8)
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
