extends SceneTree
## Windowed: how long each map takes from the loading scene to the reveal.
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.quick_restart = true
	Main._new_player_checked = true
	for spec in [["zombie", "forest"], ["zombie", "warehouse"], ["zombie", "backrooms"], ["zombie", "tokyo"], ["ch1", "forest"]]:
		Main.saved_mode = spec[0]
		Main.saved_map = spec[1]
		var t0 := Time.get_ticks_usec()
		if current_scene != null and current_scene.get_script() == Main:
			preload("res://scripts/ui/transition.gd").change_map(self)
		else:
			change_scene_to_file("res://scenes/loading.tscn")
		var worst := 0.0
		var last := t0
		var main_at := 0.0
		while true:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			if (now - last) > 250_000:
				var tr0 = root.get_node_or_null("MapTransition")
				print("[load]    long frame %4d ms  scene=%s  stage=%s %d%%" % [(now - last) / 1000, current_scene.name if current_scene else "-", tr0._stage_text if tr0 else "-", int(tr0._target) if tr0 else -1])
			last = now
			if main_at == 0.0 and current_scene != null and current_scene.get_script() == Main:
				main_at = (now - t0) / 1000.0
			var tr = root.get_node_or_null("MapTransition")
			if main_at > 0.0 and tr != null and not tr._busy:
				break
			if now - t0 > 20_000_000:
				var pr: Array = []
				var st := ResourceLoader.load_threaded_get_status("res://scenes/main.tscn", pr)
				print("[load] timeout: scene=%s busy=%s status=%d progress=%s finishing=%s" % [current_scene.name if current_scene else "null", tr._busy if tr else "no overlay", st, pr, current_scene.get("_finishing")])
				break
		print("[load] %-6s %-10s main ready at %6.0f ms  revealed at %6.0f ms  longest frozen frame %5.0f ms" % [spec[0], spec[1], main_at, (last - t0) / 1000.0, worst])
	quit(0)
