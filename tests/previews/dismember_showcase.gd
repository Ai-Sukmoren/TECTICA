extends SceneTree
## Movie-writer clip: a walker comes at the camera, loses an arm, then a leg,
## and keeps crawling. Side camera. Prints SHOT_START.
##   godot --path . --fixed-fps 60 --write-movie dismember.avi -s res://tests/previews/dismember_showcase.gd
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func wait(s: float) -> void:
	for i in int(s * 60.0):
		await process_frame

func burst(p, z, part: String, i: int, n: int) -> void:
	for k in n:
		if not is_instance_valid(z) or z.is_dead:
			return
		var a: Vector3
		var b: Vector3
		if part == "arm":
			a = z.rig.elbows[i].global_position
			b = z.rig.hands[i].global_position
		else:
			a = z.rig.thighs[i].global_position
			b = z.rig.shins[i].global_position
		var tgt: Vector3 = (a + b) * 0.5
		var to: Vector3 = tgt - p.global_position
		p.aim_yaw = atan2(-to.x, -to.z)
		z.health = 150.0   # keep it alive for the camera
		p.current_weapon().cooldown = 0.0
		p.current_weapon().bloom = 0.0
		p.try_fire(tgt)
		await wait(0.1)
		var key := ("arm%d" if part == "arm" else "leg%d") % i
		if z.severed.has(key):
			break

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
	p.global_position = Vector3(1.0, 0.05, 44)
	p.aim_yaw = 0.0
	p.set_first_person(true)
	main.director._spawn_one("walker")
	var z = main.enemies[main.enemies.size() - 1]
	z.global_position = p.global_position + Vector3(0, 0, -11)
	z.max_health = 150.0
	z.health = 150.0
	z.reset_physics_interpolation()
	main.camera_rig.override = true
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 42.0
	cam.make_current()
	print("SHOT_START ", Engine.get_frames_drawn())
	var t := 0.0
	var step := 0
	while t < 9.0 and is_instance_valid(z) and not z.is_dead:
		# camera tracks the zombie from the side
		var zp: Vector3 = z.global_position
		cam.global_position = cam.global_position.lerp(zp + Vector3(4.2, 1.2, 1.2), 0.08) if t > 0.0 else zp + Vector3(4.2, 1.2, 1.2)
		cam.look_at(zp + Vector3(0, 0.7, 0))
		z.health = 150.0
		if step == 0 and t > 1.2:
			step = 1
			await burst(p, z, "arm", 1, 12)
		elif step == 1 and t > 3.0:
			step = 2
			await burst(p, z, "leg", 0, 12)
		await process_frame
		t += 1.0 / 60.0
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
