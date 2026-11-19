extends SceneTree
## Windowed: worst frame after each gunsmith click (attachment cycling).
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(960, 540)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	Main.quick_restart = true
	Main._new_player_checked = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	var hud = current_scene.hud
	var gs = hud.gunsmith
	gs.open()
	for i in 30:
		await process_frame
	var rows: Array = []
	for i in gs._rows.size():
		if gs._rows[i].t == "att" and gs._rows[i].s == "primary":
			rows.append(i)
	var worst_first := 0.0
	var worst_again := 0.0
	var all: Array = []
	for pass_i in 2:
		for i in rows:
			for step in [1, 1, -1, -1]:
				gs._change(i, step)
				var t := Time.get_ticks_usec()
				var worst := 0.0
				for f in 3:
					await process_frame
					var now := Time.get_ticks_usec()
					worst = maxf(worst, float(now - t) / 1000.0)
					t = now
				all.append(worst)
				if pass_i == 0:
					worst_first = maxf(worst_first, worst)
				else:
					worst_again = maxf(worst_again, worst)
	all.sort()
	print("GS clicks=%d median %.1f ms  worst first-time %.1f ms  worst repeat %.1f ms" % [all.size(), all[all.size() / 2], worst_first, worst_again])
	gs.is_open = false
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
