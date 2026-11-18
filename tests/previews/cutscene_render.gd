extends SceneTree
## Renders a chapter cutscene and the first seconds of gameplay after it
## (cutscene-director skill). Prints "MARK shot<N> <frame>" at every cut and
## "MARK game <frame>" when control returns.
##   godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie out.avi \
##         -s res://tests/previews/cutscene_render.gd -- ch1 [first_person]
const Main = preload("res://scripts/main.gd")
const Director = preload("res://scripts/cinematics/cutscene_director.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var ch := a[0] if a.size() > 0 else "ch1"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = ch
	Main.quick_restart = false
	Main._new_player_checked = true   # the test profile has no progress: don't divert to TRAINING
	Main.saved_first_person = a.size() > 1 and a[1] == "first_person"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30:
		await process_frame
	var main = current_scene
	main.start_first_person = Main.saved_first_person
	Director.force = true
	main.hud._deploy()
	var d = main.get_node_or_null("Cutscene")
	var last := -1
	while is_instance_valid(d) and d.playing:
		var idx: int = d._shot_at(d.t)
		if idx != last:
			last = idx
			print("MARK shot%d %d" % [idx + 1, Engine.get_frames_drawn()])
		await process_frame
	print("MARK game %d" % Engine.get_frames_drawn())
	for i in 90:
		await process_frame
	quit(0)
