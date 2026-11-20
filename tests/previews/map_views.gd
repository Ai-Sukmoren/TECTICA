extends "res://tests/perf/perf_suite.gd"
## Fixed first-person stills of the model maps and the knives, for before / after comparisons of texture changes.
##   godot --path . -s res://tests/previews/map_views.gd -- <out_dir>

func run() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	Settings.ensure()
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for map in ["warehouse", "backrooms", "tokyo"]:
		var main = await _load(map)
		_place(main, main.level.player_spawn, "fp")
		for k in 3:
			main.player.aim_yaw = k * TAU / 3.0
			main.player.fp_pitch = -0.08
			await frames(30)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("%s_%d.png" % [map, k]))
		if map == "warehouse":
			# the karambit close up in first person
			var p = main.player
			p.preview_loadout(["karambit"])
			await frames(30)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("karambit.png"))
	Settings.mark_clean_exit()
	quit()
