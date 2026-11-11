extends SceneTree
## Fixed-view rendering benchmark: --path . -s res://tests/render_benchmark.gd -- 2
var main
var frames := 0
var samples: Array[float] = []
var draws := 0.0
var last_tick := 0
func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := OS.get_cmdline_user_args()
	var script = load("res://scripts/main.gd")
	script.saved_quality = int(args[0]) if args.size() else 2
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
func _process(_delta: float) -> bool:
	frames += 1
	var now := Time.get_ticks_usec()
	if frames > 120:
		samples.append(float(now - last_tick) / 1000.0)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	last_tick = now
	if frames == 480:
		var total := 0.0
		for ms in samples:
			total += ms
		samples.sort()
		print("BENCH quality=%d mean_ms=%.2f fps=%.1f p95_ms=%.2f draws=%.0f" % [main.quality, total / samples.size(), 1000.0 * samples.size() / total, samples[int(samples.size() * 0.95)], draws / samples.size()])
		quit()
	return false
