extends Node
## Procedural adaptive lofi score (D minor, 72 BPM, swung, 8-bar loop).
## Two synchronised layers are synthesised on a worker thread at startup:
##   * calm    - electric-piano chords (Dm9 | Bbmaj7 | Gm9 | A7b9), a sparse
##               bell melody with echo, vinyl crackle and hiss
##   * combat  - the same keys ducking under a dusty boom-bap beat (soft kick,
##               snare, shuffled hats) and a warm sub bass
## Both go through tape wobble, a low-pass and a light bit-crush.
## `intensity` (0..1) crossfades between them.

const RATE := 22050
const BPM := 72.0
const BARS := 8
const SWING := 0.12          # how late the off-beat 16ths land, in beats

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
	var amb_lin := lerpf(0.85, 0.4, _level) * m   # the keys stay in the room when it kicks off
	var cmb_lin := _level * 0.9 * m
	_amb.volume_db = linear_to_db(maxf(amb_lin, 0.0001)) - 4.0
	_cmb.volume_db = linear_to_db(maxf(cmb_lin, 0.0001)) - 4.0


# ================================================================ synthesis

func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7802   # the same take every time
	var beat := 60.0 / BPM
	var bar := beat * 4.0
	var n := int(bar * BARS * RATE)
	var keys := PackedFloat32Array()
	keys.resize(n)
	var bells := PackedFloat32Array()
	bells.resize(n)
	var drums := PackedFloat32Array()
	drums.resize(n)
	var bass := PackedFloat32Array()
	bass.resize(n)
	var duck := PackedFloat32Array()   # 1 = open, dips after each kick
	duck.resize(n)
	duck.fill(1.0)

	# two bars per chord: Dm9 | Bbmaj7 | Gm9 | A7b9
	var chords := [
		[146.83, 174.61, 220.0, 261.63, 329.63],
		[116.54, 146.83, 174.61, 220.0, 293.66],
		[98.0, 146.83, 174.61, 220.0, 233.08],
		[110.0, 138.59, 164.81, 196.0, 233.08],
	]
	var roots := [73.42, 58.27, 49.0, 55.0]

	# ---------------- keys: lazy strummed chords ----------------
	for b in BARS:
		var ch: Array = chords[(b / 2) % 4]
		var bt := b * bar
		# on the one, then a softer push late in the bar
		var hits := [[0.0, 1.0], [2.5 + SWING, 0.62]] if b % 2 == 0 else [[0.0, 0.8], [1.5 + SWING, 0.5], [3.0, 0.55]]
		for h in hits:
			var t0: float = bt + float(h[0]) * beat + rng.randf_range(0.0, 0.012)
			for k in ch.size():
				_add_ep(keys, t0 + k * 0.022, 2.6, float(ch[k]), 0.085 * float(h[1]) * (1.0 if k > 0 else 1.25))

	# ---------------- bells: sparse melody, D minor pentatonic ----------------
	var tune := [
		[0, 1.0, 587.33], [0, 2.5, 523.25], [1, 0.5, 440.0], [1, 3.0, 349.23],
		[2, 1.0, 466.16], [2, 2.5, 440.0], [3, 1.5, 349.23],
		[4, 0.5, 392.0], [4, 2.0, 466.16], [5, 1.0, 587.33], [5, 3.5, 523.25],
		[6, 1.0, 554.37], [6, 2.5, 440.0], [7, 1.5, 329.63], [7, 3.0, 293.66],
	]
	for nt in tune:
		var late := SWING if fmod(float(nt[1]), 1.0) > 0.4 else 0.0
		_add_bell(bells, int(nt[0]) * bar + (float(nt[1]) + late) * beat, float(nt[2]), 0.11)
	_echo(bells, int(beat * 0.75 * RATE), 0.38)

	# ---------------- beat: dusty boom-bap ----------------
	for b in BARS:
		var bt := b * bar
		var kicks := [0.0, 1.5 + SWING, 2.5] if b % 2 == 0 else [0.0, 2.25 + SWING, 2.5, 3.5 + SWING]
		for k in kicks:
			var kt: float = bt + float(k) * beat + rng.randf_range(-0.004, 0.006)
			_add_kick(drums, kt, 0.85 if float(k) < 0.1 else 0.62)
			_add_duck(duck, kt)
		for s in [1.0, 3.0]:
			_add_snare(drums, bt + s * beat + rng.randf_range(0.004, 0.016), 0.34, rng)   # dragging backbeat
		if b % 4 == 3:
			_add_snare(drums, bt + (3.5 + SWING) * beat, 0.14, rng)                        # ghost into the turnaround
		for s in 8:
			var off := SWING if s % 2 == 1 else 0.0
			var vol := (0.075 if s % 2 == 0 else 0.045) * rng.randf_range(0.7, 1.1)
			_add_hat(drums, bt + (s * 0.5 + off) * beat + rng.randf_range(-0.005, 0.007), vol, rng)
		# sub bass under the kicks, walking up into the next chord
		var root: float = roots[(b / 2) % 4]
		var next: float = roots[((b / 2) + 1) % 4]
		_add_sub(bass, bt, beat * 1.4, root, 0.5)
		_add_sub(bass, bt + (1.5 + SWING) * beat, beat * 0.8, root, 0.38)
		_add_sub(bass, bt + 2.5 * beat, beat * 0.9, root * (1.5 if b % 2 == 0 else 1.0), 0.4)
		if b % 2 == 1:
			_add_sub(bass, bt + (3.5 + SWING) * beat, beat * 0.4, (root + next) * 0.5, 0.32)

	# ---------------- vinyl: hiss and crackle ----------------
	var vinyl := PackedFloat32Array()
	vinyl.resize(n)
	var hiss := 0.0
	var pop := 0.0
	for i in n:
		hiss += ((rng.randf() * 2.0 - 1.0) - hiss) * 0.35
		if rng.randf() < 0.00075:
			pop = rng.randf_range(-1.0, 1.0) * rng.randf_range(0.25, 1.0)
		pop *= 0.72
		vinyl[i] = hiss * 0.012 + pop * 0.09

	# ---------------- mix ----------------
	var amb := PackedFloat32Array()
	amb.resize(n)
	var cmb := PackedFloat32Array()
	cmb.resize(n)
	for i in n:
		var t := float(i) / RATE
		var trem := 1.0 - 0.14 * (0.5 + 0.5 * sin(TAU * 4.6 * t))
		var k := keys[i] * trem
		amb[i] = k * 2.2 + bells[i] * 1.7 + vinyl[i] * 1.3
		cmb[i] = drums[i] * 0.75 + bass[i] * 0.85 + (k * 0.8 + bells[i] * 0.6) * duck[i] + vinyl[i] * 0.6
	for buf in [amb, cmb]:
		_tape(buf)
		_lowpass(buf, 0.42)
		_lowpass(buf, 0.6)
		for i in n:
			# gentle saturation, then a 9-bit crush for grit
			buf[i] = roundf(tanh(buf[i] * 1.25) * 256.0) / 256.0

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


## Electric piano note: a mellow fundamental with a bell-like attack that
## fades fast. Tails wrap around the loop so the seam is silent.
func _add_ep(buf: PackedFloat32Array, t0: float, dur: float, f: float, vol: float) -> void:
	var n := buf.size()
	var a := int(t0 * RATE)
	var count := int(dur * RATE)
	var w := TAU * f / RATE
	for j in count:
		var u := float(j) / RATE
		var env := minf(u / 0.008, 1.0) * exp(-u * 1.5) * minf((dur - u) / 0.15, 1.0)
		var ph := w * j
		buf[(a + j) % n] += (sin(ph) + 0.42 * sin(ph * 2.0) * exp(-u * 3.0) + 0.14 * sin(ph * 4.0) * exp(-u * 9.0)) * env * vol


## Soft bell / kalimba pluck for the melody.
func _add_bell(buf: PackedFloat32Array, t0: float, f: float, vol: float) -> void:
	var n := buf.size()
	var a := int(t0 * RATE)
	var w := TAU * f / RATE
	for j in int(1.4 * RATE):
		var u := float(j) / RATE
		var ph := w * j
		buf[(a + j) % n] += (sin(ph) + 0.3 * sin(ph * 3.0) * exp(-u * 10.0)) * minf(u / 0.004, 1.0) * exp(-u * 3.6) * vol


func _add_kick(buf: PackedFloat32Array, t0: float, vol: float) -> void:
	var n := buf.size()
	var a := int(t0 * RATE)
	var ph := 0.0
	for j in int(0.38 * RATE):
		var u := float(j) / RATE
		ph += TAU * (46.0 + 70.0 * exp(-u * 24.0)) / RATE
		buf[(a + j) % n] += tanh(sin(ph) * 1.6) * exp(-u * 7.5) * vol


## Sidechain: the keys dip right after a kick and swell back.
func _add_duck(duck: PackedFloat32Array, t0: float) -> void:
	var n := duck.size()
	var a := int(t0 * RATE)
	for j in int(0.4 * RATE):
		var u := float(j) / RATE
		var i := (a + j) % n
		duck[i] = minf(duck[i], 1.0 - 0.5 * exp(-u * 8.0))


## Dusty snare: filtered noise over a short body, no crack.
func _add_snare(buf: PackedFloat32Array, t0: float, vol: float, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var a := int(t0 * RATE)
	var lp := 0.0
	for j in int(0.22 * RATE):
		var u := float(j) / RATE
		lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.55
		buf[(a + j) % n] += (lp * exp(-u * 17.0) + sin(TAU * 190.0 * u) * exp(-u * 30.0) * 0.5) * vol


func _add_hat(buf: PackedFloat32Array, t0: float, vol: float, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var a := int(t0 * RATE)
	var prev := 0.0
	for j in int(0.045 * RATE):
		var u := float(j) / RATE
		var nz := rng.randf() * 2.0 - 1.0
		buf[(a + j) % n] += (nz - prev) * exp(-u * 85.0) * vol
		prev = nz


## Warm sub: sine with a little second harmonic, soft edges.
func _add_sub(buf: PackedFloat32Array, t0: float, dur: float, f: float, vol: float) -> void:
	var n := buf.size()
	var a := int(t0 * RATE)
	var w := TAU * f / RATE
	for j in int(dur * RATE):
		var u := float(j) / RATE
		var env := minf(u / 0.012, 1.0) * minf((dur - u) / 0.06, 1.0)
		var ph := w * j
		buf[(a + j) % n] += tanh((sin(ph) + 0.22 * sin(ph * 2.0)) * 1.3) * env * vol


## Feedback echo that wraps around the loop: repeats of the last notes land
## on the first bar, so the seam is inaudible.
func _echo(buf: PackedFloat32Array, delay: int, feedback: float) -> void:
	var n := buf.size()
	for i in n:
		buf[i] += buf[(i - delay + n) % n] * feedback


## Tape wow and flutter: read the buffer through a slowly wandering delay.
## Both wobbles complete whole cycles per loop, so the seam stays clean.
func _tape(buf: PackedFloat32Array) -> void:
	var n := buf.size()
	var src := buf.duplicate()
	var loop_t := float(n) / RATE
	var wow := TAU * roundf(loop_t * 0.55) / loop_t      # ~0.55 Hz
	var flutter := TAU * roundf(loop_t * 6.3) / loop_t   # ~6.3 Hz
	for i in n:
		var t := float(i) / RATE
		var pos := float(i) + sin(wow * t) * 14.0 + sin(flutter * t) * 2.2 + n
		var i0 := int(pos)
		var fr := pos - i0
		buf[i] = lerpf(src[i0 % n], src[(i0 + 1) % n], fr)


func _lowpass(buf: PackedFloat32Array, a: float) -> void:
	var y := 0.0
	# run-in over the tail so the filter state matches at the loop point
	for i in range(buf.size() - 2000, buf.size()):
		y += (buf[i] - y) * a
	for i in buf.size():
		y += (buf[i] - y) * a
		buf[i] = y
