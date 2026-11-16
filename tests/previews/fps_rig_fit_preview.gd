extends SceneTree
## Deterministic render of the real rig at its gameplay FPS eye transform.
## godot --path . -s res://tests/previews/fps_rig_fit_preview.gd -- output [ids...]
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
var rig
var cam: Camera3D
var out: String

func _initialize() -> void:
	run.call_deferred()

func shot(id: String, state: String) -> void:
	cam.global_transform = rig.fp_eye
	cam.fov = 86.0 / lerpf(1.0, float(rig.weapon.stats.zoom) * 1.35, rig.aim_amt)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(id + "_" + state + ".png"))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.055, 0.075, 0.10)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.7
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_energy = 1.6
	scene.add_child(sun)
	cam = Camera3D.new()
	cam.near = 0.04
	cam.fov = 86
	scene.add_child(cam)
	cam.current = true
	var ids: Array = args.slice(1) if args.size() > 1 else Data.PRIMARIES + Data.SMGS + Data.SECONDARIES + Data.KNIVES
	for id in ids:
		rig = Rig.new()
		scene.add_child(rig)
		rig.build(Palettes.player())
		rig.set_process(false)
		rig.set_first_person(true)
		var w = Weapon.new()
		w.setup(id)
		rig.set_weapon(w, [])
		w.set_process(false)
		rig.aim_target = 0.0
		rig.sprint_target = 0.0
		rig.one_hand_sprint = true
		rig._free_arm = 0
		rig.fp_pitch = 0
		for i in 100:
			rig._animate(1.0 / 60.0)
		await shot(id, "idle")
		rig.aim_target = 1.0
		for i in 60:
			rig._animate(1.0 / 60.0)
		await shot(id, "ads")
		rig.aim_target = 0.0
		for i in 60:
			rig._animate(1.0 / 60.0)
		rig.play_inspect()
		for i in 50:
			rig._animate(1.0 / 60.0)
		await shot(id, "inspect")
		rig.cancel_inspect()
		for i in 80:
			rig._animate(1.0 / 60.0)
		if not w.is_melee():
			rig.play_reload(2.0, true)
			for i in 20:
				rig._animate(1.0 / 60.0)
			await shot(id, "reload_mag")
			for i in 75:
				rig._animate(1.0 / 60.0)
			await shot(id, "reload_action")
			rig.cancel_reload()
		if String(w.stats.get("cycle", "")) != "":
			rig.cycle_t = 0
			rig._cycle_dur = 1.0
			for i in 28:
				rig._animate(1.0 / 60.0)
			await shot(id, "cycle")
			rig.cycle_t = -1
		rig.sprint_target = 1.0
		for i in 90:
			rig._animate(1.0 / 60.0)
		await shot(id, "sprint")
		print("FPS_PREVIEW ", id)
		rig.weapon = null
		w.free()
		rig.queue_free()
		await process_frame
	scene.queue_free()
	await process_frame
	quit()
