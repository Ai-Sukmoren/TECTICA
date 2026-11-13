extends SceneTree
## Movie-writer clip: three infected shot down in first person, then the same
## from a low side camera, to show the death animation.
##   godot --path . --fixed-fps 60 --write-movie deaths.avi -s res://tests/previews/zombie_death_showcase.gd
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func wait(s: float) -> void:
	for i in int(s * 60.0):
		await process_frame

func spawn(main, kind: String, pos: Vector3) -> Node:
	main.director._spawn_one(kind)
	var z = main.enemies[main.enemies.size() - 1]
	z.global_position = pos
	z.aim_yaw = 0.0
	z.max_health = 1000.0
	z.health = 1000.0
	z.reset_physics_interpolation()
	return z

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 80:
		await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("running", false)
	main.tod.set("hour", 14.0)
	p.set_loadout([["m4a1", {"optic": "reddot"}], ["knife_combat", {}]])
	p.global_position = Vector3(1.0, 0.05, 40)
	p.aim_yaw = 0.0
	p.fp_pitch = -0.05
	p.set_first_person(true)
	# three infected held in a row, filmed from a low side camera
	var zs: Array = []
	for k in [["walker", -2.2], ["runner", 0.0], ["brute", 2.2]]:
		var z = spawn(main, String(k[0]), p.global_position + Vector3(float(k[1]), 0, -6.0))
		z.aim_yaw = 0.0
		zs.append(z)
	await wait(0.3)
	for z in zs:
		z.set_physics_process(false)   # hold still for the camera
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 40.0
	cam.global_position = p.global_position + Vector3(6.5, 1.1, -4.2)
	cam.look_at(p.global_position + Vector3(0, 0.6, -6.6))
	cam.make_current()
	await wait(0.6)
	print("SHOT_START ", Engine.get_frames_drawn())
	var shots := [[Vector3(0, 1.25, 0), 2], [Vector3(0, 0, 0), 1], [Vector3(0, 1.1, 0), 3]]
	for i in zs.size():
		var z = zs[i]
		var n: int = shots[i][1]
		for b in n:
			var head := i == 1
			var at: Vector3 = z._head_center() if head else z.rig.chest.global_position
			z.health = 1.0 if b == n - 1 else 400.0
			p.current_weapon().cooldown = 0.0
			p.try_fire(at)
			await wait(0.11)
		await wait(1.4)
	await wait(1.0)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
