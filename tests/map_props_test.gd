extends SceneTree
## Map prop fixes: a police car's light bar and beacons go with the car when it
## is destroyed (they used to stay floating), and the night lamp update keeps
## running after a lit prop is gone. Hotel Meridian stands in Dead End.
##   godot --headless --path . -s res://tests/map_props_test.gd
const Main = preload("res://scripts/main.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var lv = main.level
	main.player.health = 100000.0
	main.director.timer = 9999.0
	var beacons: Array = lv.lamp_lights.filter(func(e): return e.group == "beacon" and e.light.get_parent().has_method("destroy"))
	check(beacons.size() == 4, "two police cars, two beacons each (%d)" % beacons.size())
	var car: Node = beacons[0].light.get_parent()
	check(car is StaticBody3D and car.has_method("destroy"), "beacons ride on the police car body")
	var gone: Array = beacons.filter(func(e): return e.light.get_parent() == car)
	car.destroy(car.global_position + Vector3(0, 1, 3), Vector3(0, 0, -1), true)
	for i in 10: await process_frame
	check(gone.all(func(e): return not is_instance_valid(e.light)), "destroying the car removes its beacons")
	# the time-of-day lamp pass and the quality pass skip the freed lights
	main.tod.set("hour", 22.0)
	for i in 30: await process_frame
	lv.apply_quality(2)
	check(beacons.filter(func(e): return is_instance_valid(e.light)).size() == 2, "the other police car keeps its beacons")
	check(lv.has_method("hotel_roof_y") and lv.hotel_roof_y() > 15.0, "Hotel Meridian stands in Dead End")
	print("map_props_test: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
