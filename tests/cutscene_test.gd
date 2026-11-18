extends SceneTree
## Chapter cutscenes (cutscene_director.gd, chapter_cutscenes.gd): Chapter 1 plays
## to the end, Chapter 2 is skipped half way; both must hand the game back intact.
##   godot --headless --path . -s res://tests/cutscene_test.gd
const Main = preload("res://scripts/main.gd")
const Director = preload("res://scripts/cinematics/cutscene_director.gd")
const Chapters = preload("res://scripts/cinematics/chapter_cutscenes.gd")
const Stealth = preload("res://scripts/stealth/stealth.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func open(ch: String):
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = ch
	Main.quick_restart = false
	Main._new_player_checked = true   # the test profile has no progress: don't divert to TRAINING
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	await frames(30)
	return current_scene

## Common end-state checks once a cutscene has handed back.
func check_handback(main, def: Dictionary, label: String) -> void:
	var p = main.player
	var end: Dictionary = def.player_end
	check(main.get_node_or_null("Cutscene") == null, label + ": the director is gone")
	check(p.global_position.distance_to(end.pos) < 0.6, label + ": the operator stands on his start spot (%.2f m off)" % p.global_position.distance_to(end.pos))
	check(not p.input_blocked and p.cine_velocity == Vector3.ZERO, label + ": player control is back")
	check(p.is_in_group("player") and not Stealth.muted, label + ": guards can see and hear him again")
	check(main._deployed and main.hud.visible and not main.camera_rig.override, label + ": deployed, HUD on, gameplay camera in charge")
	check(main.tod.running and main.tod.cine_fog == 0.0 and absf(main.tod.hour - float(def.hour)) < 0.05, label + ": clock running from the chapter start, no cinematic mist")
	check(get_nodes_in_group("player").size() == 1, label + ": exactly one operator")

func run() -> void:
	Director.force = true
	Engine.time_scale = 3.0   # the timeline and physics both run on it

	# ------------------------------------------------------------ Chapter 1: played to the end
	var main = await open("ch1")
	var def: Dictionary = Chapters.build("ch1", main)
	check(def.shots.size() >= 6 and (def.shots[-1] as Dictionary).type == "to_game", "ch1: storyboarded shots ending in a glide to gameplay (%d shots)" % def.shots.size())
	var times: Array = def.events.map(func(e): return float(e[0]))
	var sorted := times.duplicate()
	sorted.sort()
	check(times == sorted and float(times[-1]) < float(def.length), "ch1: events in time order inside the timeline")
	main.hud._deploy()
	await frames(2)
	var d = main.get_node_or_null("Cutscene")
	check(d != null and d.playing, "ch1: deploying plays the cutscene")
	check(main.player.input_blocked and not main.player.is_in_group("player") and Stealth.muted, "ch1: the operator is an actor (no input, hidden from guards)")
	check(not main._deployed, "ch1: the mission waits for the cutscene")
	var saw_heli := false
	var saw_sub := false
	var last_xf := Transform3D.IDENTITY
	var max_jump := 0.0
	var jump_at := ""
	var prev := Vector3.INF
	var last_shot := -1
	while is_instance_valid(d) and d.playing:
		await process_frame
		if not is_instance_valid(d) or not d.playing:
			break
		saw_heli = saw_heli or d.actors.has("heli")
		saw_sub = saw_sub or not d._sub.is_empty()
		var idx: int = d._shot_at(d.t)
		var pos: Vector3 = d.cam.global_position
		if idx == last_shot and prev != Vector3.INF and pos.distance_to(prev) > max_jump:
			max_jump = pos.distance_to(prev)   # within a shot: no snaps
			jump_at = "shot %d at %.2f s" % [idx + 1, d.t]
		prev = pos
		last_shot = idx
		last_xf = d.cam.global_transform
	check(saw_heli and saw_sub, "ch1: the helicopter flew and the dialogue played")
	check(max_jump < 3.0, "ch1: no camera snaps inside a shot (largest frame step %.2f m at 3x speed, %s)" % [max_jump, jump_at])
	await frames(2)
	var game_cam: Camera3D = main.camera_rig.active_camera()
	var handover := game_cam.global_position.distance_to(last_xf.origin)
	check(handover < 0.6, "ch1: the gameplay camera picks up where the cutscene ended (%.2f m)" % handover)
	check_handback(main, def, "ch1")

	# ------------------------------------------------------------ Chapter 2: skipped half way
	main = await open("ch2")
	def = Chapters.build("ch2", main)
	var fires_before := 0
	for n in main.get_children():
		if n is GPUParticles3D or n is CPUParticles3D or String(n.name).begins_with("Fire"):
			fires_before += 1
	main.hud._deploy()
	await frames(2)
	d = main.get_node_or_null("Cutscene")
	check(d != null and d.playing, "ch2: deploying plays the cutscene")
	while is_instance_valid(d) and d.t < 24.0:
		await process_frame
	check(is_instance_valid(d) and d.actors.has("guard"), "ch2: a sentry on the map was cast for the outpost shot")
	d.skip()
	for i in 20000:   # headless frames are tiny: wait for the fade by time, not frames
		await process_frame
		if not is_instance_valid(main.get_node_or_null("Cutscene")):
			break
	await frames(5)
	check_handback(main, def, "ch2 (skipped)")
	var burning := 0
	for n in main.get_children():
		if n is GPUParticles3D or n is CPUParticles3D or String(n.name).begins_with("Fire"):
			burning += 1
	check(burning >= fires_before, "ch2: the camp fires persist into gameplay after a skip")
	check(main.player.flashlight_on, "ch2: deployed at night with the flashlight on")

	Engine.time_scale = 1.0
	print("CUTSCENE: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
