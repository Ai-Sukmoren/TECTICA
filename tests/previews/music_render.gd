extends SceneTree
## Renders the procedural score to WAV files so it can be listened to and
## checked (level, clipping, loop seam).
##   godot --headless --path . -s res://tests/previews/music_render.gd -- <out_dir>
const Music = preload("res://scripts/audio/music.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	var m = Music.new()
	root.add_child(m)
	var t0 := Time.get_ticks_msec()
	while not m._ready_to_play:
		await process_frame
	print("[music] generated in %d ms" % (Time.get_ticks_msec() - t0))
	for pair in [["calm", m._amb.stream], ["combat", m._cmb.stream]]:
		var st: AudioStreamWAV = pair[1]
		var d := st.data
		var n := d.size() / 2
		var peak := 0.0
		var sum := 0.0
		var clipped := 0
		for i in n:
			var v := d.decode_s16(i * 2) / 30000.0
			peak = maxf(peak, absf(v))
			sum += v * v
			if absf(v) > 0.999:
				clipped += 1
		var seam := absf(d.decode_s16(0) - d.decode_s16((n - 1) * 2)) / 30000.0
		print("[music] %-6s %.1f s  peak %.2f  rms %.3f  clipped %d  seam jump %.3f" % [pair[0], float(n) / st.mix_rate, peak, sqrt(sum / n), clipped, seam])
		st.save_to_wav(out + "/tectica_lofi_" + String(pair[0]) + ".wav")
	quit(0)
