extends SceneTree
## Promo clips for the 13 Nov 2026 updates (v1.15 - v1.17), one shot per run,
## meant for Godot's movie writer:
##   godot --path . --resolution 1920x1080 --fixed-fps 60 --write-movie <shot>.avi \
##         -s res://tests/previews/update_showcase.gd -- <shot> [--touch]
## Shots: menu, town_fp, town_dusk, forest_run, knife, town_td, touch.
## Prints "SHOT_START <frame>" when the shot begins so loading can be trimmed.
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

var shot := "town_fp"

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		shot = a[0]
	call_deferred("run")

func wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await process_frame

func ultra(main) -> void:
	for k in Settings.PRESET_VALUES:
		Settings.v[k] = Settings.PRESET_VALUES[k][3]
	Settings.v.preset = 3
	Settings.v.show_fps = false
	main.apply_graphics()

func start() -> void:
	print("SHOT_START ", Engine.get_frames_drawn())

func nearest_zombie(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for z in get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.get("is_dead"):
			continue
		var d: float = (z as Node3D).global_position.distance_to(from)
		if d < bd:
			bd = d
			best = z
	return best

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	var town := shot in ["town_fp", "town_dusk", "knife", "town_td", "touch", "menu"]
	Main.saved_mode = "zombie"
	Main.saved_map = "town" if town else "forest"
	Main.quick_restart = shot != "menu"
	Main.saved_first_person = shot in ["town_fp", "town_dusk", "knife", "touch", "forest_run"]
	change_scene_to_file("res://scenes/main.tscn")
	for i in 70:
		await process_frame
	var main = current_scene
	ultra(main)
	if shot == "menu":
		# the cinematic title camera: hero shot, then the crane move
		var cam = main.hud.menu_cam
		cam.shot = 0
		cam.t = 0.0
		await wait(0.5)
		start()
		await wait(7.5)
		finish()
		return
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = shot in ["town_td", "touch"]
	var lvl = main.level
	match shot:
		"town_fp":
			main.tod.set("hour", 14.2)
			p.global_position = Vector3(2.2, 0.05, 46)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.04
			p.set_first_person(true)
			await wait(0.6)
			start()
			Input.action_press("move_forward")
			for f in 60 * 6:
				p.aim_yaw = sin(f / 60.0 * 0.5) * 0.12
				await process_frame
			Input.action_release("move_forward")
			# look around: the gas station to the right, the houses to the left
			for f in 60 * 4:
				var t := f / 240.0
				p.aim_yaw = -sin(t * TAU) * 0.9
				p.fp_pitch = 0.04 + sin(t * PI) * 0.1
				await process_frame
		"town_dusk":
			main.tod.set("hour", 18.75)
			p.global_position = Vector3(-6.0, 0.05, 24)
			p.aim_yaw = 0.7
			p.fp_pitch = 0.16
			p.set_first_person(true)
			await wait(0.8)
			start()
			for f in 60 * 8:
				var t := f / 480.0
				p.aim_yaw = 0.7 - t * 1.6
				p.fp_pitch = 0.16 - t * 0.1
				await process_frame
		"forest_run":
			main.tod.set("hour", 13.0)
			var camp: Vector3 = lvl.camp
			p.global_position = Vector3(camp.x, lvl.ground_y(camp.x, camp.z + 14) + 0.05, camp.z + 14)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.02
			p.set_first_person(true)
			await wait(0.6)
			start()
			await wait(0.8)
			Input.action_press("move_forward")
			Input.action_press("sprint")
			for f in 60 * 5:
				p.aim_yaw = sin(f / 60.0 * 0.8) * 0.2
				await process_frame
			Input.action_release("sprint")
			await wait(1.2)
			Input.action_release("move_forward")
			await wait(0.6)
		"knife":
			main.tod.set("hour", 17.6)
			p.global_position = Vector3(0, 0.05, 38)
			p.aim_yaw = 0.0
			p.set_loadout([["m4a1", {}], ["mk23", {}], ["karambit", {}]])
			p.weapon_index = 2
			p._equip_current()
			p.set_first_person(true)
			await wait(0.8)
			start()
			await wait(0.4)
			p.rig.play_inspect()
			while p.rig.inspect_t >= 0.0:
				await process_frame
			await wait(0.3)
			for n in 2:
				p.current_weapon().cooldown = 0.0
				p.try_fire(p.global_position + Vector3(0, 1.2, -3))
				await wait(0.6)
			await wait(0.4)
		"town_td":
			main.tod.set("hour", 15.5)
			p.global_position = Vector3(0.5, 0.05, 1.0)
			p.set_first_person(false)
			main.director.timer = 0.5   # first wave now
			await wait(1.0)
			start()
			for f in 60 * 10:
				var z := nearest_zombie(p.global_position)
				if z != null:
					var d: Vector3 = z.global_position - p.global_position
					p.aim_yaw = atan2(-d.x, -d.z)
					if d.length() < 22.0 and f % 2 == 0:
						p.current_weapon().cooldown = 0.0
						p.try_fire(z.global_position + Vector3(0, 1.1, 0))
				p.health = 100.0   # the HUD shows a real health bar
				await process_frame
		"touch":
			main.tod.set("hour", 14.2)
			p.global_position = Vector3(-1.5, 0.05, 30)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.03
			p.set_first_person(true)
			await wait(0.8)
			start()
			Input.action_press("move_forward")
			p.health = 100.0
			for f in 60 * 3:
				p.aim_yaw = sin(f / 60.0 * 0.7) * 0.25
				await process_frame
			Input.action_release("move_forward")
			for n in 3:
				p.current_weapon().cooldown = 0.0
				p.try_fire(p.global_position + Vector3(0, 1.3, -20))
				await wait(0.25)
			await wait(1.5)
	finish()

func finish() -> void:
	Settings.mark_clean_exit()   # a windowed render is not a crash
	quit(0)
