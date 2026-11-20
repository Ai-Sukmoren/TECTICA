extends "res://tests/previews/fps_rig_fit_preview.gd"
## First-person reload clip: a tactical and an empty reload per weapon, captioned.
## godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie out.avi
##       -s res://tests/previews/reload_video.gd [-- ids...]
const FPS := 30
var caption: Label

func segment(title: String, seconds: float) -> void:
	caption.text = "%s  /  %s" % [String(rig.weapon.stats.name), title]
	for i in int(seconds * FPS):
		rig._animate(1.0 / FPS)
		rig.weapon._process(1.0 / FPS)
		cam.global_transform = rig.fp_eye
		await process_frame
		await RenderingServer.frame_post_draw

func run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.34, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	cam = Camera3D.new(); cam.near = 0.04; cam.fov = 86; scene.add_child(cam); cam.current = true
	var canvas := CanvasLayer.new()
	scene.add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(32, 28)
	caption.add_theme_font_size_override("font_size", 30)
	canvas.add_child(caption)
	var args := OS.get_cmdline_user_args()
	var ids: Array = args if not args.is_empty() else ["hk33", "scar_h", "g17"]
	for id in ids:
		rig = Rig.new()
		scene.add_child(rig)
		rig.build(Palettes.player())
		rig.set_process(false)
		rig.set_first_person(true)
		var w := Weapon.new()
		w.setup(id)
		rig.set_weapon(w, [])
		w.set_process(false)
		for i in 60:
			rig._animate(1.0 / 60.0)
		await segment("READY", 0.6)
		rig.play_reload(2.2, false)
		await segment("RELOAD", 2.4)
		rig.play_reload(2.6, true)
		await segment("EMPTY RELOAD", 2.9)
		rig.free()
	scene.queue_free()
	await process_frame
	quit()
