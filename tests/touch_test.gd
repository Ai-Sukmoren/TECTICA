extends SceneTree
## Phone controls with simulated fingers (run with `-- --touch`):
## UI scaled to 1280x720, move stick walks, aim stick turns and fires at the
## rim, buttons reload / throw, the keyboard types a join code, and a tap does
## not fire through the emulated mouse.
##   godot --headless --path . -s res://tests/touch_test.gd -- --touch [out_dir]
const Main = preload("res://scripts/main.gd")
const Platform = preload("res://scripts/core/platform.gd")
const Net = preload("res://scripts/net/net.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

## Events arrive in window pixels; the controls work in the 1280x720 UI.
func win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p

func touch(i: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = win(p)
	e.pressed = down
	Input.parse_input_event(e)

func drag(i: int, p: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = win(p)
	e.relative = rel
	Input.parse_input_event(e)

func ticks(n: int) -> void:
	for k in n: await physics_frame

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[1] if args.size() > 1 else ""
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var hud = main.hud
	var p = main.player
	p.health = 100000.0
	main.director.timer = 999.0
	check(Platform.touch_mode(), "touch mode is on")
	check(root.content_scale_size == Platform.UI_SIZE, "UI laid out at %s" % [root.content_scale_size])
	check(hud.touch != null and hud.touch.in_game(), "touch controls are up in play")
	check(InputMap.action_get_events("fire").filter(func(e): return e is InputEventMouseButton).is_empty(), "a tap is not bound to fire")
	var tc = hud.touch
	var s: Vector2 = tc._size()
	print("    UI size %s" % s)

	# move stick: finger down left, drag up = forward
	var start: Vector3 = p.global_position
	touch(0, Vector2(160, s.y - 160), true)
	await process_frame
	drag(0, Vector2(160, s.y - 260), Vector2(0, -100))
	await ticks(Engine.physics_ticks_per_second)
	var moved: float = p.global_position.distance_to(start)
	print("    moved %.2f m in 1 s" % moved)
	check(moved > 2.0, "move stick walks the operator")
	touch(0, Vector2(160, s.y - 260), false)
	await ticks(20)
	var stop_at: Vector3 = p.global_position
	await ticks(30)
	check(p.global_position.distance_to(stop_at) < 0.4, "letting go stops")

	# aim stick: to the right, all the way = fire
	var w = p.current_weapon()
	w.ammo = int(w.stats.mag)
	var fired0: int = p.shots_fired
	touch(1, Vector2(s.x * 0.62, s.y * 0.5), true)
	await process_frame
	drag(1, Vector2(s.x * 0.62 + 40, s.y * 0.5), Vector2(40, 0))
	await ticks(20)
	check(p.shots_fired == fired0, "half deflection aims without firing")
	drag(1, Vector2(s.x * 0.62 + 100, s.y * 0.5), Vector2(60, 0))
	await ticks(Engine.physics_ticks_per_second / 2)
	print("    aim yaw %.2f, shots %d" % [p.aim_yaw, p.shots_fired - fired0])
	check(absf(wrapf(p.aim_yaw + PI * 0.5, -PI, PI)) < 0.35, "aim stick turns the operator to the right")
	check(p.shots_fired > fired0, "pushing to the rim fires")
	touch(1, Vector2(s.x * 0.62 + 100, s.y * 0.5), false)
	await ticks(10)
	var fired1: int = p.shots_fired
	await ticks(20)
	check(p.shots_fired == fired1, "letting go stops firing")

	# emulated mouse click in play must not fire
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = win(Vector2(s.x * 0.6, s.y * 0.4))
	mb.pressed = true
	Input.parse_input_event(mb)
	await ticks(10)
	mb = mb.duplicate()
	mb.pressed = false
	Input.parse_input_event(mb)
	check(p.shots_fired == fired1, "a tap is not a shot")

	# buttons
	tc._layout()
	var pos := {}
	for b in tc._buttons:
		pos[String(b[0])] = b[1]
	w.ammo = 1
	touch(2, pos.reload, true)
	await process_frame
	touch(2, pos.reload, false)
	await ticks(5)
	check(p.reload_timer > 0.0, "RELOAD button reloads")
	await ticks(Engine.physics_ticks_per_second * 3)
	var frags: int = p.grenades
	touch(3, pos.grenade, true)
	await process_frame
	touch(3, pos.grenade, false)
	await ticks(Engine.physics_ticks_per_second)
	check(p.grenades == frags - 1, "FRAG button throws (%d -> %d)" % [frags, p.grenades])

	if out != "":
		touch(0, Vector2(170, s.y - 170), true)
		await process_frame
		drag(0, Vector2(210, s.y - 230), Vector2(40, -60))
		touch(1, Vector2(s.x * 0.65, s.y * 0.45), true)
		await process_frame
		drag(1, Vector2(s.x * 0.65 + 50, s.y * 0.45 - 30), Vector2(50, -30))
		for i in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/touch_play.jpg", 0.85)
		touch(0, Vector2(210, s.y - 230), false)
		touch(1, Vector2(s.x * 0.65 + 50, s.y * 0.45 - 30), false)

	# keyboard on the JOIN row
	hud.title = true
	hud._mp_open()
	hud.mp_row = 3
	Net.join_ip = ""
	await process_frame
	check(tc.wants_keyboard(), "keyboard shows on the JOIN row")
	tc._layout_keyboard()
	for ch in ["B", "7", "A", "H", "G"]:
		for k in tc._keys:
			if String(k[1]) == ch:
				var c: Vector2 = (k[0] as Rect2).get_center()
				touch(4, c, true)
				await process_frame
				touch(4, c, false)
				await process_frame
	print("    typed: '%s'" % Net.join_ip)
	check(Net.join_ip.to_upper() == "B7AHG", "tapping keys types a join code")
	if out != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out + "/touch_keyboard.jpg", 0.85)
	hud.mp_open = false
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	print("TOUCH: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
