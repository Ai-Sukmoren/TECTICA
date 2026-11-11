extends Node
## Procedural adaptive tactical score (D minor, 96 BPM, 8-bar loops).
## Two synchronised layers are synthesised on a worker thread at startup:
##   * ambient  - low drone, slow minor pads, sonar pings with echo, wind
##   * combat   - kick/snare/hats, galloping bass, brass stabs, tom fills
## `intensity` (0..1) crossfades between them.

const RATE := 22050
const BPM := 96.0
const BARS := 8

var intensity := 0.0
var master := 1.0
var muted := false

var _amb: AudioStreamPlayer
var _cmb: AudioStreamPlayer
var _thread: Thread
var _level := 0.0
var _ready_to_play := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_amb = AudioStreamPlayer.new()
	_cmb = AudioStreamPlayer.new()
	for p in [_amb, _cmb]:
		p.volume_db = -80.0
		p.bus = &"Music"
		add_child(p)
	_thread = Thread.new()
	_thread.start(_generate)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func toggle_mute() -> void:
	muted = not muted


func _process(delta: float) -> void:
	if not _ready_to_play:
		return
	_level = move_toward(_level, intensity, delta * (0.6 if intensity > _level else 0.18))
	var m := 0.0 if muted else master
	var amb_lin := lerpf(0.85, 0.3, _level) * m
	var cmb_lin := _level * 0.9 * m
	_amb.volume_db = linear_to_db(maxf(amb_lin, 0.0001)) - 4.0
	_cmb.volume_db = linear_to_db(maxf(cmb_lin, 0.0001)) - 4.0


# ================================================================ synthesis

func _generate() -> void:
	var beat := 60.0 / BPM
	var bar := beat * 4.0
	var n := int(bar * BARS * RATE)
	var amb := PackedFloat32Array()
	amb.resize(n)
	var cmb := PackedFloat32Array()
	cmb.resize(n)

	# progression: Dm | Bb | Gm | A  (2 bars each)
	var roots := [73.42, 58.27, 49.0, 55.0]
	var chords := [[146.83, 174.61, 220.0], [116.54, 146.83, 174.61], [98.0, 116.54, 146.83], [110.0, 138.59, 164.81]]

	# ---------------- ambient ----------------
	# drone + wind
	var wind := 0.0
	for i in n:
		var t := float(i) / RATE
		var lfo := 0.75 + 0.25 * sin(TAU * t / (bar * 2.0))
		wind += ((randf() * 2.0 - 1.0) - wind) * 0.02
		amb[i] = (sin(TAU * 36.71 * t) * 0.22 + sin(TAU * 55.0 * t) * 0.1 + sin(TAU * 73.42 * t + sin(TAU * 0.3 * t)) * 0.06) * lfo \
				+ wind * 0.35 * (0.6 + 0.4 * sin(TAU * t / 7.3))
	# pads
	for c in 4:
		var start := c * bar * 2.0
		var dur := bar * 2.0 + 1.2
		for f in chords[c]:
			for det in [0.997, 1.004]:
				_add_pad(amb, start, dur, f * det, 0.055)
	# sonar pings (with echo applied below)
	var ping_buf := PackedFloat32Array()
	ping_buf.resize(n)
	var ping_notes := [587.33, 440.0, 698.46, 523.25]
	for b in BARS:
		if b % 2 == 0:
			_add_ping(ping_buf, b * bar + beat * 0.0, ping_notes[(b / 2) % 4], 0.16)
		_add_ping(ping_buf, b * bar + beat * 2.5, ping_notes[(b + 1) % 4] * 0.5, 0.08)
	_echo(ping_buf, int(beat * 0.75 * RATE), 0.45)
	for i in n:
		amb[i] += ping_buf[i]
	_lowpass(amb, 0.35)

	# ---------------- combat ----------------
	for b in BARS:
		var bt := b * bar
		var root: float = roots[(b / 2) % 4]
		# drums
		for k in 4:
			_add_kick(cmb, bt + k * beat, 0.8)
		if b % 2 == 1:
			_add_kick(cmb, bt + 3.5 * beat, 0.55)
		_add_snare(cmb, bt + beat, 0.45)
		_add_snare(cmb, bt + 3.0 * beat, 0.45)
		for s in 16:
			_add_hat(cmb, bt + s * beat * 0.25, 0.09 if s % 2 == 1 else 0.05)
		# galloping bass: x . x x pattern per beat
		for k in 4:
			var b0 := bt + k * beat
			_add_bass(cmb, b0, beat * 0.45, root, 0.32)
			_add_bass(cmb, b0 + beat * 0.5, beat * 0.22, root, 0.26)
			_add_bass(cmb, b0 + beat * 0.75, beat * 0.22, root * (1.5 if k == 3 else 1.0), 0.26)
		# brass stab at each chord change
		if b % 2 == 0:
			for f in chords[(b / 2) % 4]:
				_add_stab(cmb, bt, beat * 1.6, f * 0.5, 0.11)
		# tom fill on the last bar
		if b == BARS - 1:
			for k in 6:
				_add_tom(cmb, bt + 2.5 * beat + k * beat * 0.25, 140.0 - k * 14.0, 0.5)
	# a little of the drone under the combat layer keeps the key centre
	for i in n:
		cmb[i] = tanh((cmb[i] + amb[i] * 0.25) * 1.2)
		amb[i] = tanh(amb[i] * 1.1)

	call_deferred("_start", _to_stream(amb), _to_stream(cmb))


func _start(a: AudioStreamWAV, c: AudioStreamWAV) -> void:
	_amb.stream = a
	_cmb.stream = c
	_amb.play()
	_cmb.play()
	_ready_to_play = true


func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = buf.size()
	return s


func _range(buf: PackedFloat32Array, t0: float, dur: float) -> Vector2i:
	var a := int(t0 * RATE)
	return Vector2i(a, mini(a + int(dur * RATE), buf.size()))


func _add_pad(buf: PackedFloat32Array, t0: float, dur: float, f: float, vol: float) -> void:
	var r := _range(buf, t0, dur)
	var w := TAU * f / RATE
	for i in range(r.x, r.y):
		var u := float(i - r.x) / RATE
		var env := minf(u / 1.4, 1.0) * minf((dur - u) / 1.2, 1.0)
		var ph := w * i
		buf[i] += (sin(ph) + 0.35 * sin(ph * 2.0) + 0.12 * sin(ph * 3.0)) * env * vol


func _add_ping(buf: PackedFloat32Array, t0: float, f: float, vol: float) -> void:
	var r := _range(buf, t0, 1.2)
	var w := TAU * f / RATE
	for i in range(r.x, r.y):
		var u := float(i - r.x) / RATE
		buf[i] += sin(w * (i - r.x)) * exp(-u * 4.5) * vol


func _add_kick(buf: PackedFloat32Array, t0: float, vol: float) -> void:
	var r := _range(buf, t0, 0.32)
	var ph := 0.0
	for i in range(r.x, r.y):
		var u := float(i - r.x) / RATE
		ph += TAU * (45.0 + 90.0 * exp(-u * 28.0)) / RATE
		buf[i] += sin(ph) * exp(-u * 9.0) * vol


func _add_snare(buf: PackedFloat32Array, t0: float, vol: float) -> void:
	var r := _range(buf, t0, 0.25)
	for i in range(r.x, r.y):
		var u := float(i - r.x) / RATE
		buf[i] += ((randf() * 2.0 - 1.0) * exp(-u * 16.0) + sin(TAU * 185.0 * u) * exp(-u * 25.0) * 0.6) * vol


func _add_hat(buf: PackedFloat32Array, t0: float, vol: float) -> void:
	var r := _range(buf, t0, 0.05)
	var prev := 0.0
	for i in range(r.x, r.y):
		var u := float(i - r.x) / RATE
		var nz := randf() * 2.0 - 1.0
		buf[i] += (nz - prev) * exp(-u * 70.0) * vol
		prev = nz


func _add_bass(buf: PackedFloat32Array, t0: float, dur: float, f: float, vol: float) -> void:
	var r := _range(buf, t0, dur)
	var lp := 0.0
	for i in range(r.x, r.y):
		var u := float(i - r.x) / RATE
		var saw := 2.0 * fposmod(f * u, 1.0) - 1.0
		lp += (saw - lp) * 0.12
		var env := minf(u / 0.005, 1.0) * minf((dur - u) / 0.02, 1.0)
		buf[i] += (lp + sin(TAU * f * 0.5 * u) * 0.5) * env * vol


func _add_stab(buf: PackedFloat32Array, t0: float, dur: float, f: float, vol: float) -> void:
	var r := _range(buf, t0, dur)
	var lp := 0.0
	for i in range(r.x, r.y):
		var u := float(i - r.x) / RATE
		var saw := 2.0 * fposmod(f * u, 1.0) - 1.0 + 2.0 * fposmod(f * 1.005 * u, 1.0) - 1.0
		lp += (saw - lp) * (0.05 + 0.2 * exp(-u * 6.0))
		buf[i] += lp * exp(-u * 2.2) * minf(u / 0.01, 1.0) * vol


func _add_tom(buf: PackedFloat32Array, t0: float, f: float, vol: float) -> void:
	var r := _range(buf, t0, 0.4)
	var ph := 0.0
	for i in range(r.x, r.y):
		var u := float(i - r.x) / RATE
		ph += TAU * f * (1.0 + exp(-u * 20.0) * 0.5) / RATE
		buf[i] += sin(ph) * exp(-u * 7.0) * vol


func _echo(buf: PackedFloat32Array, delay: int, feedback: float) -> void:
	for i in range(delay, buf.size()):
		buf[i] += buf[i - delay] * feedback


func _lowpass(buf: PackedFloat32Array, a: float) -> void:
	var y := 0.0
	for i in buf.size():
		y += (buf[i] - y) * a
		buf[i] = y
