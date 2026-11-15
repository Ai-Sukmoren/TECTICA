extends SceneTree
## NEIGHBOURHOOD city map: loads for Zombie Survival with spawns and navigation.
##   godot --headless --path . -s res://tests/city_test.gd
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	load("res://scripts/core/profile.gd").current = "city_test"
	Main.saved_mode = "zombie"; Main.saved_map = "city"; Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var lv = current_scene.level
	var ok: bool = current_scene.map_id == "city" and lv.zombie_spawns.size() >= 10 and current_scene.player.global_position.y < 1.0
	print("CITY: spawns %d, player %s -> %s" % [lv.zombie_spawns.size(), current_scene.player.global_position, "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)
