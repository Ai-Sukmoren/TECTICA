extends SceneTree
## Gun warm-up: when a map loads, every gun's model file is loaded and kept, the
## warm-up node cleans itself up before the map is shown, and building a gun
## afterwards (switching to it mid-match) needs no disk access.
##   godot --headless --path . -s res://tests/gun_warmup_test.gd
const Main = preload("res://scripts/main.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Model = preload("res://scripts/weapons/weapon_model.gd")
const Warmup = preload("res://scripts/weapons/gun_warmup.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	preload("res://scripts/core/profile.gd").current = "gun_warmup_test"
	# the warm-up on its own: how long the loading screen gains
	var t0 := Time.get_ticks_usec()
	var w := Warmup.new()
	get_root().add_child(w)
	var built_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("  warm-up build: %.0f ms for %d models" % [built_ms, w.get_child_count()])
	check(w.get_child_count() >= (Data.PRIMARIES + Data.SMGS + Data.SECONDARIES).size(), "every gun is built")
	for i in Warmup.FRAMES + 2:
		await process_frame
	check(not is_instance_valid(w), "the warm-up frees itself before the map is shown")
	var missing: Array = []
	for id in Data.PRIMARIES + Data.SMGS + Data.SECONDARIES:
		var path := Model.LOW_POLY + String(Data.WEAPONS[id].model) + ".glb"
		if ResourceLoader.exists(path) and not Model._scenes.has(path):
			missing.append(id)
	check(missing.is_empty(), "every gun's model file stays loaded %s" % [missing])
	# switching guns after the warm-up: no file loads, only the build
	var worst := 0.0
	var worst_id := ""
	for id in Data.PRIMARIES + Data.SMGS + Data.SECONDARIES:
		var t := Time.get_ticks_usec()
		var parts := Model.build(String(Data.WEAPONS[id].model), Data.WEAPONS[id].defaults)
		var ms := (Time.get_ticks_usec() - t) / 1000.0
		parts.root.free()
		if ms > worst:
			worst = ms
			worst_id = id
	print("  slowest gun build after warm-up: %s %.1f ms" % [worst_id, worst])
	# the map: the warm-up runs as part of loading
	Main.saved_mode = "ch1"
	Main.saved_quality = 0
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	check(current_scene.get_node_or_null("GunWarmup") != null, "the map starts the warm-up while loading")
	for i in 10:
		await process_frame
	check(current_scene.get_node_or_null("GunWarmup") == null, "and it is gone once the map is up")
	print("GUN WARMUP: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
