extends "res://tests/previews/fps_rig_fit_preview.gd"
## Frame-by-frame capture of the FPS arms on every weapon through every animation.
## godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie out.avi
##       -s res://tests/previews/fps_arm_video.gd [-- ids...]
## Prints "VIDEO_SEGMENT <id> <first frame> <frames>" so the movie can be cut per weapon.
const FPS := 30
var caption: Label
var frame := 0

func segment(title: String, seconds: float, every: Callable = Callable()) -> void:
	caption.text = "%s  /  %s" % [String(rig.weapon.stats.name), title]
	for i in int(seconds * FPS):
		if every.is_valid():
			every.call(i)
		rig._animate(1.0 / FPS)
		rig.weapon._process(1.0 / FPS)
		cam.global_transform = rig.fp_eye
		cam.fov = 86.0 / lerpf(1.0, minf(float(rig.weapon.stats.zoom), 1.3) * 1.35, rig.aim_amt)
		frame += 1
		await process_frame
		await RenderingServer.frame_post_draw

## One shot as the game shows it: muzzle flash, tracer, casing, recoil, cycling.
func shoot() -> void:
	var w = rig.weapon
	var far: Vector3 = w.muzzle.global_position - rig.fp_eye.basis.z * 40.0
	w.fire_fx([[far, Vector3.UP, 0]])
	if String(w.stats.cycle) != "":
		w.cycle_pending = 0.12
	rig.add_recoil(0.05)

func shots(count: int, gap: int) -> Callable:
	return func(i: int) -> void:
		if i % gap == 0 and i / gap < count:
			shoot()

func run() -> void:
	root.mode = Window.MODE_WINDOWED
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
	var canvas := CanvasLayer.new()
	scene.add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(32, 28)
	caption.add_theme_font_size_override("font_size", 26)
	canvas.add_child(caption)
	var note := Label.new()
	note.text = "TECTICA  |  FPS arms · in-engine animation preview"
	note.position = Vector2(32, 65)
	note.modulate = Color(0.6, 0.72, 0.85)
	canvas.add_child(note)
	var args := OS.get_cmdline_user_args()
	var ids: Array = args if not args.is_empty() else Data.PRIMARIES + Data.SMGS + Data.SECONDARIES + Data.KNIVES
	for id in ids:
		var start := frame
		rig = Rig.new()
		scene.add_child(rig)
		rig.build(Palettes.player())
		rig.set_process(false)
		rig.set_first_person(true)
		var w := Weapon.new()
		w.setup(id)
		rig.set_weapon(w, [])
		w.set_process(false)
		rig.one_hand_sprint = true
		for i in 60:
			rig._animate(1.0 / 60.0)
		rig.play_switch(0.5)
		await segment("DRAW", 0.7)
		await segment("IDLE", 1.0)
		rig.move_velocity = Vector3(0.4, 0, -2.7)
		await segment("WALK", 1.4)
		rig.move_velocity = Vector3.ZERO
		if w.is_melee():
			await segment("SLASH", 1.8, func(i: int) -> void:
				if i % 18 == 0:
					rig.play_slash(0.5))
		else:
			var cycles := String(w.stats.cycle) != ""
			var gap := 12 if cycles else maxi(2, int(FPS * 60.0 / float(w.stats.rpm)))
			await segment("HIP FIRE", 1.6 if cycles else 1.0, shots(1 if cycles else 5, gap if not cycles else 99))
			rig.aim_target = 1.0
			await segment("AIM DOWN SIGHTS", 0.8)
			await segment("ADS FIRE", 1.6 if cycles else 0.8, shots(1 if cycles else 4, gap if not cycles else 99))
			rig.aim_target = 0.0
			await segment("RETURN TO HIP", 0.5)
			rig.play_reload(2.2, false)
			await segment("RELOAD", 2.4)
			rig.play_reload(2.6, true)
			await segment("EMPTY RELOAD", 2.9)
		rig.play_inspect()
		await segment("INSPECT", Rig.INSPECT_DURATION + 0.3)
		rig.move_velocity = Vector3(0, 0, -6)
		rig.sprint_target = 1.0
		await segment("SPRINT", 1.2)
		rig.move_velocity = Vector3.ZERO
		rig.sprint_target = 0.0
		await segment("RECOVER", 0.5)
		if not w.is_melee():
			rig.play_throw(0.7)
			await segment("GRENADE THROW", 1.1)
		print("VIDEO_SEGMENT %s %d %d" % [id, start, frame - start])
		rig.free()
	scene.queue_free()
	await process_frame
	quit()
