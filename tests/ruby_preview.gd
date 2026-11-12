extends SceneTree
## Renders the Ruby + sticker AK and the new infected (dog, bat, bloater) next
## to a chem-lit operator to PNGs. Needs a GPU (run without --headless):
##   godot --path . -s res://tests/ruby_preview.gd -- <out_dir>
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Zombie = preload("res://scripts/characters/zombie.gd")
const Player = preload("res://scripts/characters/player.gd")

class Target extends Node3D:
	var is_dead := false
	var team := 0


func _initialize() -> void:
	call_deferred("run")


func _shot(path: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[preview] saved ", path)


func run() -> void:
	Engine.max_fps = 60
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else "user://"
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.1)
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.6, 0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	var cam := Camera3D.new()
	scene.add_child(cam)

	# --- 1: ruby AK with the sticker, right side to camera
	var guns: Array = []
	var y := 0.42
	for id in ["awp", "ak47", "mk23"]:
		var gun := Weapon.new()
		gun.setup(id, {})
		scene.add_child(gun)
		gun.apply_skin("ruby")
		gun.apply_sticker({"side": 0})
		gun.rotation.y = -PI * 0.5
		gun.position = Vector3(0, y, 0)
		y -= 0.42
		guns.append(gun)
	cam.position = Vector3(0, 0.0, 2.0)
	cam.look_at(Vector3(0, 0.0, 0))
	cam.fov = 40
	await _shot(out.path_join("ruby_ak.png"))
	for g in guns:
		g.queue_free()

	# --- 2: new infected + chem-lit operator at night
	env.environment.background_color = Color(0.01, 0.012, 0.02)
	env.environment.ambient_light_energy = 0.12
	sun.light_energy = 0.08
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	scene.add_child(ground)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	scene.add_child(floor_body)
	var target := Target.new()
	scene.add_child(target)
	target.position = Vector3(0, 0, 6)
	var x := -2.4
	for kind in ["dog", "bat", "bloater"]:
		var z := Zombie.new()
		scene.add_child(z)
		z.position = Vector3(x, 0, 0)
		z.init_zombie(target, kind, 100.0, 0.0, 10.0, 1)
		z.set_physics_process(false)
		z.aim_yaw = 0.6
		z.rig.snap_yaw(0.6)
		x += 2.0
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3, 2)
	lamp.omni_range = 8
	lamp.light_energy = 1.2
	scene.add_child(lamp)
	var p := Player.new()
	scene.add_child(p)
	p.position = Vector3(3.6, 0, 0.5)
	p.setup_player(PI * 0.8, [["m4a1", {}]], false, "")
	p.set_physics_process(false)
	cam.position = Vector3(0.6, 2.2, 5.6)
	cam.look_at(Vector3(0.6, 0.8, 0))
	cam.fov = 55
	await _shot(out.path_join("infected_night.png"))
	quit(0)
