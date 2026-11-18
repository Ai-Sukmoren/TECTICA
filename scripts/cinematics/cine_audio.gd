extends RefCounted
## Sound for cutscenes, synthesised like the rest of TECTICA's audio (sfx.gd):
## ambience loops (wind, dawn birds, night insects, fire, a generator), the
## helicopter's rotor, radio squelch and hiss, and a low tension drone.
## Every stream is built once and cached.

const RATE := 22050

static var _cache := {}


## A looping or one-shot stream by name (see the match below).
static func stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var s: AudioStreamWAV
	match sound:
		"wind":
			s = _wind()
		"birds":
			s = _birds()
		"insects":
			s = _insects()
		"rotor":
			s = _rotor()
		"generator":
			s = _generator()
		"fire":
			s = _fire()
		"static":
			s = _static()
		"squelch":
			s = _squelch(false)
		"squelch_out":
			s = _squelch(true)
		"drone":
			s = _drone()
		_:
			return null
	_cache[sound] = s
	return s


static func _wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


## Crossfades the tail into the head so a loop has no click at its seam.
static func _seamless(buf: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := buf.size() - fade
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = buf[i]
	for i in fade:
		var k := float(i) / fade
		out[i] = buf[n + i] * (1.0 - k) + buf[i] * k
	return out


static func _wind() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := RATE * 7
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		var gust := 0.55 + 0.45 * sin(t * 0.9) * sin(t * 0.37 + 1.0)
		buf[i] = lp2 * 6.0 * gust
	return _wav(_seamless(buf, RATE), true)


static func _birds() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := RATE * 9
	var buf := PackedFloat32Array()
	buf.resize(n)
	# a few distant birds: short rising / falling chirps in little phrases
	var t0 := 0.3
	while t0 < 8.4:
		var notes := rng.randi_range(2, 5)
		var f0 := rng.randf_range(2600.0, 4200.0)
		var vol := rng.randf_range(0.05, 0.14)
		for k in notes:
			var start := int((t0 + k * rng.randf_range(0.09, 0.16)) * RATE)
			var dur := int(rng.randf_range(0.05, 0.11) * RATE)
			var sweep := rng.randf_range(-1400.0, 1600.0)
			var ph := 0.0
			for i in dur:
				if start + i >= n:
					break
				var u := float(i) / dur
				ph += TAU * (f0 + sweep * u) / RATE
				buf[start + i] += sin(ph) * sin(u * PI) * vol
		t0 += rng.randf_range(0.7, 2.2)
	return _wav(_seamless(buf, RATE / 4), true)


static func _insects() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var n := RATE * 6
	var buf := PackedFloat32Array()
	buf.resize(n)
	# crickets: a high carrier chopped into trills, two voices out of step
	for v in 2:
		var f := 4300.0 + v * 380.0
		var rate := 27.0 + v * 4.0
		var phrase := 0.9 + v * 0.35
		var ph := 0.0
		for i in n:
			var t := float(i) / RATE
			ph += TAU * f / RATE
			var trill := maxf(sin(t * rate * TAU), 0.0)
			var on := 1.0 if fposmod(t + v * 0.4, phrase) < phrase * 0.55 else 0.0
			buf[i] += sin(ph) * trill * on * (0.05 - v * 0.015)
	for i in n:
		buf[i] += rng.randf_range(-1, 1) * 0.004
	return _wav(_seamless(buf, RATE / 2), true)


static func _rotor() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := RATE * 2
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var ph_t := 0.0
	var ph_w := 0.0
	var blade := 5.5   # blade passes per second: the "whop"
	for i in n:
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.08
		var beat := fposmod(t * blade, 1.0)
		var whop := exp(-beat * 9.0)
		ph_t += TAU * 92.0 / RATE
		ph_w += TAU * 1750.0 / RATE
		buf[i] = lp * 2.2 * (0.25 + whop) + sin(ph_t) * 0.12 * (0.6 + 0.4 * whop) + sin(ph_w) * 0.015
	return _wav(buf, true)   # exactly 11 blade passes: loops seamlessly


static func _generator() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var n := RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		buf[i] = sin(TAU * 60.0 * t) * 0.16 + sin(TAU * 120.0 * t) * 0.1 + sin(TAU * 180.0 * t) * 0.05 \
				+ sin(TAU * 25.0 * t) * 0.06 + rng.randf_range(-1, 1) * 0.02
	return _wav(buf, true)


static func _fire() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := RATE * 4
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		lp += (rng.randf_range(-1, 1) - lp) * 0.03
		buf[i] = lp * 1.6
	# crackles: sharp little pops
	for k in 70:
		var at := rng.randi_range(0, n - 400)
		var vol := rng.randf_range(0.08, 0.35)
		for i in rng.randi_range(40, 260):
			buf[at + i] += rng.randf_range(-1, 1) * vol * exp(-i / 40.0)
	return _wav(_seamless(buf, RATE / 3), true)


static func _static() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var n := RATE * 2
	var buf := PackedFloat32Array()
	buf.resize(n)
	var prev := 0.0
	for i in n:
		var w := rng.randf_range(-1, 1)
		buf[i] = (w - prev) * 0.09   # high-passed hiss
		prev = w
	return _wav(buf, true)


static func _squelch(closing: bool) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2 if closing else 1
	var n := int(RATE * (0.16 if closing else 0.12))
	var buf := PackedFloat32Array()
	buf.resize(n)
	var bp := 0.0
	var bp2 := 0.0
	for i in n:
		var u := float(i) / n
		bp += (rng.randf_range(-1, 1) - bp) * 0.35
		bp2 += (bp - bp2) * 0.5
		var env := (1.0 - u) if not closing else (sin(u * PI))
		buf[i] = (bp - bp2) * 1.4 * env
	# the key click
	var c0 := 0 if not closing else n - 60
	for i in 60:
		if c0 + i < n:
			buf[c0 + i] += (0.5 if i < 4 else 0.0)
	return _wav(buf, false)


static func _drone() -> AudioStreamWAV:
	var n := RATE * 8
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var swell := 0.6 + 0.4 * sin(t * TAU / 8.0)
		buf[i] = (sin(TAU * 55.0 * t) * 0.16 + sin(TAU * 55.4 * t) * 0.14 + sin(TAU * 82.5 * t) * 0.07
				+ sin(TAU * 110.0 * t) * 0.03) * swell
	return _wav(buf, true)   # whole cycles of the 8 s swell: loops cleanly
