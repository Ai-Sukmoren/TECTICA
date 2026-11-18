extends SceneTree
## Recorded sounds: every gunshot / reload sound listed in sfx.gd has all its takes in assets/audio/sfx/, imported and
## playable; every gun plays a recording (a suppressor switches to the suppressed takes); a shot plays in a scene.
##   godot --headless --path . -s res://tests/sfx_samples_test.gd
const Sfx = preload("res://scripts/fx/sfx.gd")
const WData = preload("res://scripts/weapons/weapon_data.gd")
var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var total := 0
	for sound in Sfx.SAMPLES:
		var takes: Array = Sfx._takes_of(sound)
		var good := takes.filter(func(t): return t is AudioStreamOggVorbis and (t as AudioStream).get_length() > 0.1)
		total += good.size()
		check(good.size() == int(Sfx.SAMPLES[sound]), "%s: %d of %d recorded takes" % [sound, good.size(), int(Sfx.SAMPLES[sound])])
	print("    %d recorded takes" % total)
	for id in WData.WEAPONS:
		var st: Dictionary = WData.compute(id, {})
		if st.kind == "melee":
			check(String(st.sound) == "knife_swing", "%s swings with the knife sound (%s)" % [id, st.sound])
			continue
		check(not Sfx._takes_of(String(st.sound)).is_empty(), "%s fires a recording (%s)" % [id, st.sound])
	var sup: Dictionary = WData.compute("scar_h", {"muzzle": "suppressor"})
	check(String(sup.sound) == "shot_suppressed", "a suppressor switches the SCAR-H to the suppressed takes")
	check(Sfx._level("shot_ak") > 0.0 and Sfx._level("dry") == 0.0, "recorded shots get their level lift, synthesised sounds none")
	var root := Node3D.new()
	get_root().add_child(root)
	current_scene = root
	await process_frame
	Sfx.play(root, "shot_ak", Vector3.ZERO, -3.0)
	await process_frame
	var players := root.get_children().filter(func(n): return n is AudioStreamPlayer3D)
	check(players.size() == 1 and players[0].stream is AudioStreamOggVorbis, "a shot plays its recording in the world")
	print("SFX SAMPLES: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
