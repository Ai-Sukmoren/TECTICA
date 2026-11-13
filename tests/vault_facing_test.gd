extends SceneTree
## Vaulting keeps the view when backing over cover, still faces forward
## vaults, and footsteps play quieter on their own dry bus.
##   godot --headless --path . -s res://tests/vault_facing_test.gd
const Main = preload("res://scripts/main.gd")
const Layers = preload("res://scripts/core/layers.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func block(main, at: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.0, 0.9, 0.6)
	cs.shape = bs
	cs.position.y = 0.45
	b.add_child(cs)
	main.add_child(b)
	b.global_position = at
	return b

## Walks with `action` held into a block until a vault starts; returns the
## facing change in radians, or -1 if no vault happened.
func vault_with(main, action: String, block_offset: Vector3) -> float:
	var p = main.player
	p.velocity = Vector3.ZERO
	p.aim_yaw = 0.0                      # looking north (-z)
	p.rig.aim_yaw = 0.0
	var b := block(main, p.global_position + block_offset)
	for i in 10: await physics_frame
	var yaw0: float = p.aim_yaw
	Input.action_press(action)
	var vaulted := false
	for i in Engine.physics_ticks_per_second * 3:
		await physics_frame
		p.aim_yaw = yaw0 if not p.vaulting and not vaulted else p.aim_yaw   # hold the look like a still mouse
		if not vaulted and i % 6 == 0:
			Input.action_press("vault")
		elif not vaulted:
			Input.action_release("vault")
		if p.vaulting:
			vaulted = true
			break
	Input.action_release(action)
	Input.action_release("vault")
	var turned := absf(wrapf(p.aim_yaw - yaw0, -PI, PI))
	for i in Engine.physics_ticks_per_second: await physics_frame
	b.queue_free()
	await physics_frame
	return turned if vaulted else -1.0

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	main.player.health = 100000.0
	main.director.timer = 999.0
	main.player.global_position = Vector3(0, 0.05, 30)   # open street south of the crossroads
	for i in 20: await physics_frame

	var back: float = await vault_with(main, "move_back", Vector3(0, 0, 1.3))
	print("    backing over cover: view turned %.1f deg" % rad_to_deg(back))
	check(back >= 0.0, "backing into cover vaults")
	check(back >= 0.0 and back < deg_to_rad(10.0), "backing over cover keeps the view")
	main.player.global_position = Vector3(0, 0.05, 30)
	for i in 20: await physics_frame
	var fwd: float = await vault_with(main, "move_forward", Vector3(0, 0, -1.3))
	print("    forward vault: view turned %.1f deg" % rad_to_deg(fwd))
	check(fwd >= 0.0, "forward vault still works (faces the jump, as before)")

	check(AudioServer.get_bus_index("Foley") != -1, "footsteps have their own bus")
	var rev_idx := AudioServer.get_bus_index("SFX")
	var rev: AudioEffectReverb = AudioServer.get_bus_effect(rev_idx, 0)
	check(rev.wet <= 0.08 and rev.room_size <= 0.35, "room echo is short and quiet (wet %.2f, room %.2f)" % [rev.wet, rev.room_size])
	var foley_fx := AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Foley"))
	check(foley_fx == 0, "footsteps are dry (no reverb)")
	print("VAULT: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
