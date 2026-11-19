extends SceneTree
## Movie-writer take for the 1.46 film: the gunsmith, attachments on the SCAR-H changed one after another at the
## pace of a player clicking through them (every 15 frames), each change shown on the turntable at once.
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "ch1"
	Main.quick_restart = true
	Main._new_player_checked = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120: await process_frame
	var gs = current_scene.hud.gunsmith
	gs.open()
	for i in 60: await process_frame
	print("MARK open ", Engine.get_frames_drawn())
	var rows: Array = []
	for i in gs._rows.size():
		if gs._rows[i].t == "att" and gs._rows[i].s == "primary":
			rows.append(i)
	for i in rows:
		gs.row = i
		for k in 3:
			gs._change(i, 1)
			for f in 15: await process_frame
	print("MARK end ", Engine.get_frames_drawn())
	quit(0)
