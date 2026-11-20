extends "res://tests/previews/fps_rig_fit_preview.gd"
## First-person reload strip: the eye view at fixed points of a tactical and an empty reload, one row per weapon.
## RS_ACT=fire: one shot and its action cycle instead (RS_DUR seconds); RS_ACT=sprint: into a full sprint.
## godot --path . -s res://tests/previews/reload_strip.gd -- <out_dir> [ids...]
var POINTS := [0.0, 0.15, 0.3, 0.42, 0.55, 0.66, 0.8, 0.95] if OS.get_environment("RS_P") == "" else Array(OS.get_environment("RS_P").split_floats(","))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(int(OS.get_environment("RS_W")) if OS.get_environment("RS_W") != "" else 480, int(OS.get_environment("RS_H")) if OS.get_environment("RS_H") != "" else 270)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.36, 0.42)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	scene.add_child(sun)
	cam = Camera3D.new(); cam.near = 0.04; cam.fov = 86; scene.add_child(cam); cam.current = true
	var ids: Array = args.slice(1) if args.size() > 1 else ["hk33", "g17", "mosin"]
	for id in ids:
		for empty in ([false, true] if OS.get_environment("RS_E") == "" else [OS.get_environment("RS_E") == "1"]):
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
			var dur := 2.4
			if OS.get_environment("RS_ACT") == "sprint":
				# run up to a full sprint and hold it (the gait keeps moving the gun)
				dur = 1.6
				rig.move_velocity = Vector3(0, 0, -6.5)
				rig.sprint_target = 1.0
			elif OS.get_environment("RS_ACT") == "fire":
				# one shot and the action cycling after it (bolt, lever, pump, revolver)
				dur = float(OS.get_environment("RS_DUR")) if OS.get_environment("RS_DUR") != "" else 1.2
				w.cycle_pending = 0.12
				rig.add_recoil(float(w.stats.recoil))
			else:
				rig.play_reload(dur, empty)
			var t := 0.0
			for k in POINTS.size():
				while t < POINTS[k] * dur:
					rig._animate(1.0 / 60.0)
					t += 1.0 / 60.0
				cam.global_transform = rig.fp_eye
				if OS.get_environment("RS_HIDE_R") != "":
					rig.shoulders[1].visible = false
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(out.path_join("%s_%s_%d.png" % [id, "empty" if empty else "tac", k]))
			rig.free()
	quit()
