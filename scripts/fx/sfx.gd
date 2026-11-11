extends RefCounted
## Procedurally synthesised sound effects (no audio files needed).
## Streams are generated once and cached.

static var _streams: Dictionary = {}

const RATE := 22050


static func play(ctx: Node, sound: String, pos: Vector3, volume_db: float = 0.0, pitch_var: float = 0.07) -> void:
	if ctx == null or not ctx.is_inside_tree():
		return
	var stream := _stream_for(sound)
	if stream == null:
		return
	var root := ctx.get_tree().current_scene
	if root == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.unit_size = 14.0
	p.max_distance = 90.0
	p.bus = &"SFX"
	root.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


static func _stream_for(sound: String) -> AudioStreamWAV:
	if sound == "footstep":
		return _footstep_variant()
	if _streams.has(sound):
		return _streams[sound]
	var s: AudioStreamWAV = null
	match sound:
		"shot_loud":
			s = _shot(0.6, 14.0, 0.32, 62.0, 1.0)
		"shot_pistol":
			s = _shot(0.4, 22.0, 0.42, 85.0, 0.85)
		"shot_rifle":
			s = _shot(0.5, 18.0, 0.38, 70.0, 0.9)
		"shot_smg":
			s = _shot(0.32, 26.0, 0.45, 95.0, 0.75)
		"shot_sniper":
			s = _shot(1.1, 9.0, 0.25, 48.0, 1.15)
		"shot_shotgun":
			s = _shot(0.75, 11.0, 0.22, 52.0, 1.1)
		"shot_suppressed":
			s = _suppressed()
		"dry":
			s = _click(0.04, 3200.0, 0.5)
		"mag_out":
			s = _click(0.09, 1400.0, 0.7)
		"mag_in":
			s = _click(0.08, 1900.0, 0.85)
		"bolt":
			s = _double_click()
		"casing":
			s = _tink()
		"hit":
			s = _thud()
		"switch":
			s = _click(0.12, 900.0, 0.5)
		"hitmarker":
			s = _click(0.05, 2600.0, 0.55)
		"kill":
			s = _ding()
		"explosion":
			s = _explosion()
		"heartbeat":
			s = _heartbeat()
		"pin":
			s = _click(0.14, 3400.0, 0.5)
		"groan":
			s = _groan()
		"swipe":
			s = _swipe()
		"break_wood":
			s = _break(0.55, 0.22, 140.0, 9.0)
		"break_sand":
			s = _break(0.45, 0.05, 70.0, 7.0)
		"break_hard":
			s = _break(0.8, 0.35, 95.0, 5.0)
		"impact_wood":
			s = _knock(0.09, 0.25, 220.0)
		"impact_sand":
			s = _knock(0.07, 0.05, 90.0)
		"impact_hard":
			s = _knock(0.08, 0.5, 520.0)
	_streams[sound] = s
	return s


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


static func _shot(duration: float, decay: float, lp_amount: float, thump_hz: float, gain: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * lp_amount
		lp2 += (white - lp2) * 0.04
		var crack := white * exp(-t * 110.0) * 0.7
		var body := lp * exp(-t * decay) * 1.3
		var tail := lp2 * exp(-t * 3.5) * 1.4
		var thump := sin(TAU * thump_hz * t * (1.0 - t)) * exp(-t * 24.0) * 0.9
		out[i] = (crack + body + tail + thump) * gain
	return _to_stream(out)


static func _suppressed() -> AudioStreamWAV:
	var n := int(0.28 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * 0.35
		var hiss := (white - lp) * exp(-t * 38.0) * 0.55
		var puff := lp * exp(-t * 26.0) * 0.6
		var clack := 0.0
		if t > 0.028:
			clack = (randf() * 2.0 - 1.0) * exp(-(t - 0.028) * 160.0) * 0.45
		var thump := sin(TAU * 110.0 * t) * exp(-t * 40.0) * 0.35
		out[i] = hiss + puff + clack + thump
	return _to_stream(out)


static func _click(duration: float, freq: float, gain: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var tone := sin(TAU * freq * t) * exp(-t * 90.0)
		var noise := (randf() * 2.0 - 1.0) * exp(-t * 140.0)
		out[i] = (tone * 0.6 + noise * 0.5) * gain
	return _to_stream(out)


static func _double_click() -> AudioStreamWAV:
	var n := int(0.22 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for start in [0.0, 0.11]:
			if t >= start:
				var u: float = t - start
				v += (sin(TAU * 1500.0 * u) * 0.5 + (randf() * 2.0 - 1.0) * 0.5) * exp(-u * 120.0)
		out[i] = v * 0.8
	return _to_stream(out)


static func _tink() -> AudioStreamWAV:
	var n := int(0.25 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 4200.0 * t) + sin(TAU * 6100.0 * t) * 0.5) * exp(-t * 28.0) * 0.35
	return _to_stream(out)


static func _groan() -> AudioStreamWAV:
	var d := 1.1
	var n := int(d * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var base := randf_range(75.0, 105.0)
	for i in n:
		var t := float(i) / RATE
		var f := base * (1.0 - 0.25 * t / d) + sin(TAU * 5.5 * t) * 4.0
		ph += f / RATE
		var saw := 2.0 * fposmod(ph, 1.0) - 1.0
		var src := saw * 0.7 + (randf() * 2.0 - 1.0) * 0.5
		lp += (src - lp) * 0.09
		lp2 += (lp - lp2) * 0.2
		out[i] = (lp2 * 1.8 + (lp - lp2) * 0.6) * sin(PI * t / d)
	return _to_stream(out)


static func _swipe() -> AudioStreamWAV:
	var n := int(0.28 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * (0.05 + 0.4 * t / 0.28)
		out[i] = lp * sin(PI * t / 0.28) * 1.6
	return _to_stream(out)


static func _thud() -> AudioStreamWAV:
	var n := int(0.18 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.15
		out[i] = (sin(TAU * 90.0 * t) * 0.8 + lp * 1.5) * exp(-t * 30.0)
	return _to_stream(out)


## Splintering / collapsing prop: noise crackle bursts over a low thump.
static func _break(duration: float, bright: float, thump_hz: float, decay: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var crackle := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * bright
		if randf() < 0.004:
			crackle = 1.0
		crackle *= 0.995
		var thump := sin(TAU * thump_hz * t * (1.0 - t * 0.6)) * exp(-t * 18.0)
		out[i] = tanh((lp * (0.6 + crackle * 1.4) * exp(-t * decay) * 1.6 + thump * 0.9) * 1.2)
	return _to_stream(out)


## Bullet striking a prop.
static func _knock(duration: float, bright: float, hz: float) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += ((randf() * 2.0 - 1.0) - lp) * bright
		out[i] = (lp * 1.4 + sin(TAU * hz * t) * 0.6) * exp(-t * 45.0)
	return _to_stream(out)


static func _ding() -> AudioStreamWAV:
	var n := int(0.35 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 1320.0 * t) * 0.5 + sin(TAU * 1980.0 * t) * 0.25) * exp(-t * 11.0) * 0.6
	return _to_stream(out)


static func _explosion() -> AudioStreamWAV:
	var n := int(2.2 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := randf() * 2.0 - 1.0
		lp += (white - lp) * 0.12
		lp2 += (white - lp2) * 0.02
		ph += (35.0 + 70.0 * exp(-t * 6.0)) / RATE
		var boom := sin(TAU * ph) * exp(-t * 3.0) * 1.1
		var crack := white * exp(-t * 40.0) * 0.8
		var body := lp * exp(-t * 4.0) * 1.4
		var rumble := lp2 * exp(-t * 1.2) * 2.2
		out[i] = tanh((boom + crack + body + rumble) * 1.3)
	return _to_stream(out)


## Boot on forest ground: soft heel thud, a lighter toe-off, gritty crunch of
## dirt / needles and a little grass rustle. No tonal component (a sine
## "thump" reads as a cartoon boop). Several takes, picked at random, so a
## run never machine-guns the same sample.
const STEP_VARIANTS := 8
static var _steps: Array = []


static func _footstep_variant() -> AudioStreamWAV:
	if _steps.is_empty():
		for v in STEP_VARIANTS:
			_steps.append(_footstep(v))
	return _steps[randi() % _steps.size()]


static func _footstep(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + variant
	var n := int(0.3 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var toe_t := rng.randf_range(0.055, 0.1)      # heel -> toe roll
	var toe_gain := rng.randf_range(0.35, 0.6)
	var heel_gain := rng.randf_range(0.8, 1.0)
	var grit_amt := rng.randf_range(0.5, 1.0)
	var rustle_amt := rng.randf_range(0.15, 0.4)
	var body_lp := rng.randf_range(0.035, 0.06)    # weight of the thud
	var lp_body := 0.0
	var lp_mid := 0.0
	var bp_a := 0.0
	var bp_b := 0.0
	var hp_prev := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf() * 2.0 - 1.0
		# impacts: short soft-attack envelopes (no click)
		var heel := heel_gain * smoothstep(0.0, 0.004, t) * exp(-t * 32.0)
		var tt := t - toe_t
		var toe := 0.0 if tt < 0.0 else toe_gain * smoothstep(0.0, 0.006, tt) * exp(-tt * 40.0)
		var impact := heel + toe
		# low thud: heavily low-passed noise
		lp_body += (white - lp_body) * body_lp
		lp_mid += (white - lp_mid) * 0.22
		var thud := lp_body * 5.5 * impact + lp_mid * 0.9 * impact
		# grit / needle crunch: sparse crackles band-passed to ~1-4 kHz
		var dens := exp(-t * 18.0) * grit_amt
		if tt >= 0.0:
			dens += 0.6 * exp(-tt * 22.0) * grit_amt
		var crackle := rng.randf_range(-1.0, 1.0) if rng.randf() < 0.09 * dens else 0.0
		bp_a += (crackle - bp_a) * 0.55
		bp_b += (bp_a - bp_b) * 0.12
		var grit := (bp_a - bp_b) * 1.6
		# grass / leaf rustle: high-passed noise with a slower tail
		hp = 0.86 * (hp + white - hp_prev)
		hp_prev = white
		var rustle := hp * rustle_amt * smoothstep(0.0, 0.02, t) * exp(-t * 11.0) * 0.35
		out[i] = tanh((thud + grit + rustle) * 1.1) * 0.9
	# fade to silence at the end
	var fade := int(0.03 * RATE)
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	return _to_stream(out)


static func _heartbeat() -> AudioStreamWAV:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for st in [0.0, 0.17]:
			if t >= st:
				var u: float = t - st
				v += sin(TAU * 52.0 * u) * exp(-u * 22.0) * (1.0 if st == 0.0 else 0.7)
		out[i] = v * 0.9
	return _to_stream(out)
