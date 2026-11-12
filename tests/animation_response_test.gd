extends SceneTree
## Regression: sprint recovery, blocked input, invalid remote weapon indexes.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("[response] ", label, " PASS=", ok)
	if not ok:
		failures += 1

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var p = main.player
	var rig = p.rig
	for hz in [30, 60, 144]:
		rig.sprint_amt = 1.0
		rig.sprint_target = 0.0
		for step in int(ceil(hz * 0.2)):
			rig._update_state(1.0 / hz)
		check(rig.sprint_amt < 0.05, "sprint exit within 0.2 seconds at %d Hz" % hz)
	p.aiming = true
	p.sprinting = true
	p.sliding = true
	p._vault_buffer = 0.3
	p._peek_off = Vector3.RIGHT
	rig.lean_target = 1.0
	rig.slide_target = 1.0
	p.input_blocked = true
	p._physics_process(1.0 / 60.0)
	check(not p.aiming and not p.sprinting and not p.sliding, "menu clears movement states")
	check(rig.lean_target == 0.0 and rig.slide_target == 0.0 and p._peek_off == Vector3.ZERO, "menu clears visual offsets")
	check(p._vault_buffer == 0.0, "menu clears queued jump")
	p.input_blocked = false
	var original: int = p.weapon_index
	p._net_weapon = -1
	p._puppet_physics(1.0 / 60.0)
	check(p.weapon_index == original, "negative remote weapon rejected")
	p._net_weapon = p.weapons.size()
	p._puppet_physics(1.0 / 60.0)
	check(p.weapon_index == original, "out-of-range remote weapon rejected")
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
