extends SceneTree
## Forest creek wading: footsteps in the water splash (sound + effect), the
## bridge and banks stay dry, and other maps clear the water.
##   godot --headless --path . -s res://tests/water_test.gd [-- <wav_out>]
const Main = preload("res://scripts/main.gd")
const Water = preload("res://scripts/world/water.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
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
	Main.saved_map = "forest"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var lv = main.level
	main.player.health = 100000.0
	main.director.timer = 9999.0
	check(Water.line.size() > 10, "forest registers the creek")
	# a point on the creek well away from the bridge
	var c: Vector2 = lv.creek[lv.creek.size() / 4]
	var bridge := Vector2(lv.bridge.x, lv.bridge.z)
	if c.distance_to(bridge) < 8.0:
		c = lv.creek[lv.creek.size() * 3 / 4]
	var bed := Vector3(c.x, -0.4, c.y)
	check(Water.wading(bed), "standing in the creek is wading")
	check(not Water.wading(Vector3(c.x, 0.8, c.y)), "above the water (on a log or bank) is dry")
	check(not Water.wading(Vector3(bridge.x, lv.bridge.y, bridge.y)), "the bridge is dry")
	check(not Water.wading(Vector3(c.x + 12.0, -0.4, c.y + 12.0)), "away from the creek is dry")
	# a footstep in the creek spawns the splash effect
	var before := main.get_child_count()
	main.player._on_footstep(bed, 1.0)
	await process_frame
	check(main.get_child_count() >= before + 3, "a wading footstep spawns droplets, spray and a ripple")
	var s: AudioStreamWAV = Sfx._stream_for("splash_step")
	check(s != null and s.data.size() > 10000, "splash footstep sound is generated")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		s.save_to_wav(args[0])
		print("  saved ", args[0])
	# other maps clear the water
	Main.saved_map = "town"
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	check(Water.line.is_empty() and not Water.wading(bed), "Dead End has no creek")
	print("water_test: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(1 if failures > 0 else 0)
