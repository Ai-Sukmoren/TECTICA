extends Node
## Plays one cutscene definition (chapter_cutscenes.gd) over the live level:
## its own camera, letterboxed overlay with subtitles and captions, actors (the
## operator, a helicopter, guards already on the map), sound loops and one-shots,
## and environment changes (time of day, mist, colour grade, fires). Ends by
## gliding the camera into the gameplay camera, so control is handed over
## without a cut.
##
## Timing runs on an AnimationPlayer: one Animation whose value track drives `t`
## (cameras, paths and fades read it) and whose method track fires every event at
## its exact time. A skip seeks to the end and applies whatever the remaining
## events would have left behind (definitions mark those "persist").
##
## Definition: {
##   "id", "length", "start_hour", "end_hour", "player_end": {pos, yaw},
##   "shots":  [{t, dur, type: move | track | to_game, ...}],
##   "events": [[time, kind, {args}]]   (kinds: see _event)
## }

signal finished(skipped: bool)

const CineAudio = preload("res://scripts/cinematics/cine_audio.gd")
const Helicopter = preload("res://scripts/cinematics/helicopter.gd")
const Stealth = preload("res://scripts/stealth/stealth.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Retro = preload("res://scripts/ui/retro.gd")

const ChapterCutscenes = preload("res://scripts/cinematics/chapter_cutscenes.gd")
const Net = preload("res://scripts/net/net.gd")
const Profile = preload("res://scripts/core/profile.gd")

const SKIP_HOLD := 0.9
## Tests and render tools set this to play cutscenes inside an automated run.
static var force := false


## True when deploying into `main`'s current mode should open with its cutscene:
## a campaign chapter that has one, solo, with SETTINGS > GAME > CUTSCENES on.
## Automated test runs skip them unless they set `force`.
static func wanted(main) -> bool:
	if main.campaign == null or not ChapterCutscenes.has_cutscene(String(main.mode)):
		return false
	if force:
		return true
	if Net.active or Profile._is_test_run():
		return false
	return bool(Settings.v.get("cutscenes", true))
const SPEAKER_COLORS := {"OVERWATCH": Color(0.55, 0.85, 1.0), "KILO-1": Color(1.0, 0.8, 0.4), "RAVEN-6": Color(0.6, 1.0, 0.65)}

var main
var def: Dictionary
## the timeline clock, written by the AnimationPlayer
var t := 0.0
var anim: AnimationPlayer
var cam: Camera3D
var actors := {}
var playing := false

var _attrs: CameraAttributesPractical
var _layer: CanvasLayer
var _canvas: Control
var _fired := {}
var _loops := {}
var _paths: Array = []
var _walks := {}
var _looks := {}
var _sub := {}
var _caption := {}
var _fade := 1.0
var _fade_from := 1.0
var _fade_to := 1.0
var _fade_t0 := 0.0
var _fade_dur := 0.0
var _box := 0.0
var _box_from := 0.0
var _box_to := 0.0
var _box_t0 := 0.0
var _box_dur := 0.0
var _grade_from := Vector3.ONE
var _grade_to := Vector3.ONE
var _grade_t0 := 0.0
var _grade_dur := 0.0
var _fog_from := 0.0
var _fog_to := 0.0
var _fog_t0 := 0.0
var _fog_dur := 0.0
var _rotor_from := 1.0
var _rotor_to := 1.0
var _rotor_t0 := 0.0
var _rotor_dur := 0.0
var _shot_index := -1
var _shot_start_xf := Transform3D.IDENTITY
var _shot_start_fov := 60.0
var _skip_hold := 0.0
var _skip_shown := 0.0
var _skipping := false
var _skip_t := 0.0
var _done := false
var _saved := {}
var _font: Font
var _font_bold: Font


## Starts `definition` in `p_main`. Call once; listen to `finished`.
func play(p_main, definition: Dictionary) -> void:
	main = p_main
	def = definition
	name = "Cutscene"
	process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(self)
	Retro.install()
	_font = Retro.body()
	_font_bold = Retro.bold()
	_save_state()
	_build_camera()
	_build_overlay()
	actors["player"] = main.player
	_build_timeline()
	playing = true
	_update(0.0)


# ------------------------------------------------------------------ setup / teardown

func _save_state() -> void:
	var p = main.player
	_saved = {
		"contrast": main.env.adjustment_contrast,
		"saturation": main.env.adjustment_saturation,
		"brightness": main.env.adjustment_brightness,
		"music": main.music.master if main.music else 1.0,
		"hud": main.hud.visible,
	}
	_grade_from = Vector3(main.env.adjustment_contrast, main.env.adjustment_saturation, main.env.adjustment_brightness)
	_grade_to = _grade_from
	# the operator becomes an actor: no player input, invisible to guards, silent to them
	p.input_blocked = true
	p.in_cutscene = true
	p.cine_velocity = Vector3.ZERO
	if p.is_in_group("player"):
		p.remove_from_group("player")
	Stealth.muted = true
	main.hud.visible = false
	main.camera_rig.override = true
	# the clock holds at the chapter's start time: the light doesn't drift during the scene
	if main.tod:
		_saved["tod_running"] = main.tod.running
		main.tod.running = false
		if def.has("hour"):
			main.tod.hour = float(def.hour)
			main.tod.apply_now()


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "CineCam"
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every rendered frame
	cam.near = 0.05
	cam.far = 400.0
	_attrs = CameraAttributesPractical.new()
	_attrs.auto_exposure_enabled = false
	cam.attributes = _attrs
	add_child(cam)
	cam.make_current()


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 30
	add_child(_layer)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_overlay)
	_layer.add_child(_canvas)


func _build_timeline() -> void:
	anim = AnimationPlayer.new()
	anim.name = "Timeline"
	# stepped by _process, so every frame's camera, cuts and events read the same clock
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	add_child(anim)
	anim.root_node = NodePath("..")
	var a := Animation.new()
	a.length = float(def.length)
	var clock := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(clock, NodePath(".:t"))
	a.value_track_set_update_mode(clock, Animation.UPDATE_CONTINUOUS)
	a.track_insert_key(clock, 0.0, 0.0)
	a.track_insert_key(clock, a.length, a.length)
	var calls := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(calls, NodePath("."))
	# a track holds one key per time: events sharing a moment fire together, in order
	var at_time := {}
	var evs: Array = def.events
	for i in evs.size():
		var tk := snappedf(float(evs[i][0]), 0.001)
		if not at_time.has(tk):
			at_time[tk] = []
		at_time[tk].append(i)
	for tk in at_time:
		a.track_insert_key(calls, float(tk), {"method": "_event_group", "args": [at_time[tk]]})
	var lib := AnimationLibrary.new()
	lib.add_animation("cut", a)
	anim.add_animation_library("", lib)
	anim.animation_finished.connect(func(_n): _finish(false))
	anim.play("cut")


## Hands the game back: camera, operator, sound, light and HUD as they were (or
## as the cutscene left them on purpose: time of day, fires, the operator's spot).
func _finish(skipped: bool) -> void:
	if _done:
		return
	_done = true
	playing = false
	if skipped:
		var evs: Array = def.events
		for i in evs.size():
			if not _fired.has(i) and (evs[i][2] as Dictionary).get("persist", false):
				_event(i)
	anim.stop()
	var p = main.player
	var end: Dictionary = def.get("player_end", {})
	if not end.is_empty() and (skipped or p.global_position.distance_to(end.pos) > 0.5):
		p.global_position = end.pos
	if not end.is_empty():
		p.aim_yaw = float(end.yaw)
		p.rig.aim_yaw = p.aim_yaw
	p.cine_velocity = Vector3.ZERO
	p.cine_aim = false
	p.set_crouch(false)
	p.visible = true
	p.reset_physics_interpolation()
	p.input_blocked = false
	p.in_cutscene = false
	if not p.is_in_group("player"):
		p.add_to_group("player")
	Stealth.muted = false
	for k in actors:
		if actors[k] is Helicopter:
			actors[k].queue_free()
	for k in _loops:
		(_loops[k] as Node).queue_free()
	_loops.clear()
	main.env.adjustment_contrast = float(_saved.contrast)
	main.env.adjustment_saturation = float(_saved.saturation)
	main.env.adjustment_brightness = float(_saved.brightness)
	if main.music:
		main.music.master = float(_saved.music)
	if main.tod:
		main.tod.cine_fog = 0.0
		main.tod.running = bool(_saved.get("tod_running", true))
		if def.has("hour"):
			main.tod.hour = float(def.hour)
			main.tod.apply_now()
	main.hud.visible = bool(_saved.hud)
	main.camera_rig.override = false
	if skipped:
		main.camera_rig.snap()   # after a skip there's no glide to continue from
	finished.emit(skipped)
	queue_free()


# ------------------------------------------------------------------ frame update

func _process(delta: float) -> void:
	if _done:
		return
	_handle_skip(delta)
	if not _skipping and not _done:
		anim.advance(delta)
		if _done:
			return
	_update(delta)
	_canvas.queue_redraw()


func _handle_skip(delta: float) -> void:
	if _skipping:
		_skip_t += delta
		_fade = minf(_skip_t / 0.35, 1.0)
		if _skip_t >= 0.4:
			_finish(true)
		return
	var held := Input.is_action_pressed("vault") or Input.is_action_pressed("pause") or Input.is_action_pressed("ui_accept")
	if held:
		_skip_shown = 3.0
		_skip_hold += delta
		if _skip_hold >= SKIP_HOLD:
			skip()
	else:
		_skip_hold = maxf(_skip_hold - delta * 2.0, 0.0)
		_skip_shown = maxf(_skip_shown - delta, 0.0)


## Fades out and ends the cutscene now (state restored as if it had played out).
func skip() -> void:
	if not _skipping and not _done:
		_skipping = true
		_skip_t = 0.0
		anim.pause()


func _update(delta: float) -> void:
	if not _skipping:
		_fade = _ramp(_fade_from, _fade_to, _fade_t0, _fade_dur)
	_box = _ramp(_box_from, _box_to, _box_t0, _box_dur)
	var g := Vector3(
		_ramp(_grade_from.x, _grade_to.x, _grade_t0, _grade_dur),
		_ramp(_grade_from.y, _grade_to.y, _grade_t0, _grade_dur),
		_ramp(_grade_from.z, _grade_to.z, _grade_t0, _grade_dur))
	main.env.adjustment_contrast = g.x
	main.env.adjustment_saturation = g.y
	main.env.adjustment_brightness = g.z
	if main.tod:
		main.tod.cine_fog = _ramp(_fog_from, _fog_to, _fog_t0, _fog_dur)
	for k in actors:
		if actors[k] is Helicopter:
			(actors[k] as Helicopter).rotor = _ramp(_rotor_from, _rotor_to, _rotor_t0, _rotor_dur)
	_update_paths()
	_update_walks(delta)
	_update_looks(delta)
	_update_loops(delta)
	_update_camera()


func _ramp(a: float, b: float, t0: float, dur: float) -> float:
	if dur <= 0.0:
		return b if t >= t0 else a
	return lerpf(a, b, smoothstep(0.0, 1.0, clampf((t - t0) / dur, 0.0, 1.0)))


# ------------------------------------------------------------------ camera

func _point(v) -> Vector3:
	if v is Vector3:
		return v
	if v is Dictionary:
		var a = actors.get(String(v.actor))
		if a == null or not is_instance_valid(a):
			return Vector3.ZERO
		var off: Vector3 = v.get("offset", Vector3.ZERO)
		if bool(v.get("local", false)):
			return (a as Node3D).global_transform * off
		return (a as Node3D).global_position + off
	return Vector3.ZERO


func _ease(u: float, kind: String) -> float:
	match kind:
		"linear":
			return u
		"in":
			return u * u * u
		"out":
			return 1.0 - pow(1.0 - u, 3.0)
	return u * u * (3.0 - 2.0 * u)


## A slow, layered sway like a camera operator's hands (never a shake).
func _handheld(amount: float) -> Vector3:
	var tt := t + 3.7
	return Vector3(
		sin(tt * 1.13) * 0.6 + sin(tt * 2.71 + 1.3) * 0.3 + sin(tt * 6.3 + 0.4) * 0.1,
		sin(tt * 0.97 + 2.0) * 0.6 + sin(tt * 2.29 + 0.6) * 0.3 + sin(tt * 5.7 + 2.2) * 0.1,
		sin(tt * 0.71 + 4.0) * 0.5 + sin(tt * 1.9) * 0.5) * amount


func _shot_at(time: float) -> int:
	var shots: Array = def.shots
	var idx := -1
	for i in shots.size():
		if float(shots[i].t) <= time:
			idx = i
	return idx


func _update_camera() -> void:
	var idx := _shot_at(t)
	if idx < 0:
		return
	var s: Dictionary = def.shots[idx]
	if idx != _shot_index:
		_shot_index = idx
		_shot_start_xf = cam.global_transform
		_shot_start_fov = cam.fov
	var u := _ease(clampf((t - float(s.t)) / maxf(float(s.dur), 0.01), 0.0, 1.0), String(s.get("ease", "inout")))
	var fovs: Array = s.get("fov", [55.0, 55.0])
	var fov := lerpf(float(fovs[0]), float(fovs[1]), u)
	var pos: Vector3
	var look: Vector3
	match String(s.type):
		"to_game":
			var target := _game_camera()
			var xf: Transform3D = _shot_start_xf.interpolate_with(target[0], u)
			cam.global_transform = xf
			cam.fov = lerpf(_shot_start_fov, float(target[1]), u)
			_set_focus(s, 0.0)
			return
		"track":
			var a := _point(s.subject)
			var off: Vector3 = (s.off_from as Vector3).lerp(s.off_to, u)
			pos = a + off
			look = a + (s.get("look_off", Vector3(0, 1.0, 0)) as Vector3)
		_:
			pos = _point(s.from).lerp(_point(s.to), u)
			look = _point(s.look_from).lerp(_point(s.get("look_to", s.look_from)), u)
	var hand := float(s.get("hand", 0.0))
	if hand > 0.0:
		var n := _handheld(hand)
		var basis := Basis.looking_at((look - pos).normalized(), Vector3.UP)
		pos += basis.x * n.x * 0.05 + basis.y * n.y * 0.035
		look += basis.x * n.z * 0.08 * pos.distance_to(look) * 0.05
	if pos.distance_to(look) > 0.01:
		cam.global_transform = Transform3D(Basis.looking_at((look - pos).normalized(), Vector3.UP), pos)
		if s.has("roll"):
			cam.rotate_object_local(Vector3.FORWARD, deg_to_rad(float(s.roll)) * (1.0 - u * 0.5))
	cam.fov = fov
	_set_focus(s, pos.distance_to(_point(s.focus)) if s.has("focus") else 0.0)


## Shallow depth of field around the focus distance (0 = everything sharp).
func _set_focus(s: Dictionary, dist: float) -> void:
	var amount := float(s.get("dof", 0.0))
	if dist <= 0.0 or amount <= 0.0:
		_attrs.dof_blur_far_enabled = false
		_attrs.dof_blur_near_enabled = false
		return
	_attrs.dof_blur_far_enabled = true
	_attrs.dof_blur_far_distance = dist + 1.0 + dist * 0.35
	_attrs.dof_blur_far_transition = maxf(dist * 0.8, 2.0)
	_attrs.dof_blur_near_enabled = dist > 2.0
	_attrs.dof_blur_near_distance = maxf(dist * 0.45, 0.3)
	_attrs.dof_blur_near_transition = maxf(dist * 0.3, 0.3)
	_attrs.dof_blur_amount = amount


## Where the gameplay camera will be when control returns: the operator's eye
## in first person, the tactical camera above him otherwise.
func _game_camera() -> Array:
	var p = main.player
	if main.start_first_person and p.rig.fp_mode:
		return [p.rig.fp_eye, float(Settings.v.fov)]
	return [main.camera_rig.cam.global_transform, main.camera_rig.cam.fov]


# ------------------------------------------------------------------ events

func _event_group(indices: Array) -> void:
	for i in indices:
		_event(int(i))


func _event(i: int) -> void:
	if _fired.has(i) or _done:
		return
	_fired[i] = true
	var e: Array = def.events[i]
	var kind := String(e[1])
	var a: Dictionary = e[2]
	match kind:
		"fade":
			_fade_from = _fade
			_fade_to = float(a.to)
			_fade_t0 = t
			_fade_dur = float(a.get("dur", 1.0))
		"letterbox":
			_box_from = _box
			_box_to = float(a.to)
			_box_t0 = t
			_box_dur = float(a.get("dur", 1.0))
		"caption":
			_caption = {"lines": a.lines, "t0": t, "t1": t + float(a.get("dur", 5.0))}
		"line":
			_sub = {"who": String(a.who), "text": String(a.text), "t0": t, "t1": t + float(a.get("dur", 3.0)), "radio": bool(a.get("radio", false))}
			if _sub.radio:
				_one_shot("squelch", -14.0)
				_loop_to("static", -30.0, 0.15)
				get_tree().create_timer(float(a.get("dur", 3.0))).timeout.connect(func():
					if not _done:
						_one_shot("squelch_out", -16.0)
						_loop_to("static", -80.0, 0.2))
		"sfx":
			if a.has("pos"):
				Sfx.play(main, String(a.name), _point(a.pos), float(a.get("vol", 0.0)), 0.08)
			else:
				Sfx.play_ui(main, String(a.name), float(a.get("vol", 0.0)))
		"loop":
			_loop_to(String(a.name), float(a.get("vol", -12.0)), float(a.get("fade", 1.0)), a.get("at"))
		"grade":
			_grade_from = Vector3(main.env.adjustment_contrast, main.env.adjustment_saturation, main.env.adjustment_brightness)
			_grade_to = Vector3(float(a.get("contrast", _grade_from.x)), float(a.get("saturation", _grade_from.y)), float(a.get("brightness", _grade_from.z)))
			_grade_t0 = t
			_grade_dur = float(a.get("dur", 1.0))
		"grade_restore":
			# back to the game's own grade, gently, before control returns
			_grade_from = Vector3(main.env.adjustment_contrast, main.env.adjustment_saturation, main.env.adjustment_brightness)
			_grade_to = Vector3(float(_saved.contrast), float(_saved.saturation), float(_saved.brightness))
			_grade_t0 = t
			_grade_dur = float(a.get("dur", 1.0))
		"fog":
			_fog_from = main.tod.cine_fog if main.tod else 0.0
			_fog_to = float(a.to)
			_fog_t0 = t
			_fog_dur = float(a.get("dur", 1.0))
		"music":
			if main.music:
				main.music.master = float(a.master)
		"tod":
			if main.tod:
				main.tod.hour = float(a.hour)
				main.tod.apply_now()
		"fire":
			if main.campaign != null and main.campaign.has_method("_burning"):
				main.campaign._burning(a.pos)
		"heli":
			var h: Node3D = Helicopter.new()
			main.add_child(h)
			h.global_position = a.pos
			h.rotation.y = float(a.get("yaw", 0.0))
			actors[String(a.get("as", "heli"))] = h
			_rotor_from = float(a.get("rotor", 1.0))
			_rotor_to = _rotor_from
		"rotor":
			_rotor_from = _ramp(_rotor_from, _rotor_to, _rotor_t0, _rotor_dur)
			_rotor_to = float(a.to)
			_rotor_t0 = t
			_rotor_dur = float(a.get("dur", 1.0))
		"searchlight":
			var hl = actors.get(String(a.get("actor", "heli")))
			if hl is Helicopter:
				(hl as Helicopter).searchlight.light_energy = float(a.get("energy", 5.0))
		"path":
			_paths.append({"actor": String(a.actor), "t0": t, "keys": a.keys})
		"place":
			var n = actors.get(String(a.actor))
			if n != null:
				n.global_position = a.pos
				if a.has("yaw"):
					if n.get("aim_yaw") != null:
						n.aim_yaw = float(a.yaw)
						if n.get("rig") != null:
							n.rig.aim_yaw = n.aim_yaw
					else:
						n.rotation.y = float(a.yaw)
				if a.has("visible"):
					n.visible = bool(a.visible)
				if n.has_method("reset_physics_interpolation"):
					n.reset_physics_interpolation()
		"show":
			var sn = actors.get(String(a.actor))
			if sn != null:
				sn.visible = bool(a.get("on", true))
		"walk":
			_walks[String(a.actor)] = {"to": a.to, "speed": float(a.get("speed", 1.4))}
		"look":
			_looks[String(a.actor)] = {"at": a.get("at"), "yaw": a.get("yaw"), "rate": float(a.get("rate", 3.0))}
		"crouch":
			var cn = actors.get(String(a.actor))
			if cn != null:
				cn.set_crouch(bool(a.on))
		"aim":
			var an = actors.get(String(a.actor))
			if an != null:
				an.cine_aim = bool(a.on)
		"anim":
			var nn = actors.get(String(a.actor))
			if nn != null and nn.get("rig") != null:
				match String(a.name):
					"inspect":
						nn.rig.play_inspect()
					"reload":
						nn.rig.play_reload(2.2, false)
						Sfx.play(main, "mag_out", nn.global_position + Vector3.UP * 1.2, -8.0)
						get_tree().create_timer(1.3).timeout.connect(func():
							if is_instance_valid(nn):
								Sfx.play(main, "mag_in", nn.global_position + Vector3.UP * 1.2, -8.0))
		"flashlight":
			main.player.set_flashlight(bool(a.on))
			Sfx.play(main, "dry", main.player.global_position + Vector3.UP * 1.4, -12.0)
		"bind_enemy":
			var best = null
			var bd := INF
			for en in main.enemies:
				if en.is_dead:
					continue
				var d: float = en.global_position.distance_to(a.near)
				if d < bd:
					bd = d
					best = en
			if best != null:
				actors[String(a.as)] = best
		"game_view":
			# the gameplay camera gets ready at the operator's final spot for the glide in
			var p = main.player
			var end: Dictionary = def.get("player_end", {})
			if not end.is_empty():
				p.global_position = end.pos
				p.aim_yaw = float(end.yaw)
				p.rig.aim_yaw = p.aim_yaw
				p.reset_physics_interpolation()
			p.set_first_person(main.start_first_person)
			main.camera_rig.snap()
			cam.make_current()


# ------------------------------------------------------------------ actors

## Keyframed paths: [[seconds after the event, position, yaw (rad), pitch (rad)]],
## Catmull-Rom through the points so nothing moves in straight jerky segments.
func _update_paths() -> void:
	for pth in _paths:
		var n = actors.get(String(pth.actor))
		if n == null or not is_instance_valid(n):
			continue
		var keys: Array = pth.keys
		var lt: float = t - float(pth.t0)
		if lt < float(keys[0][0]):
			continue
		var k := 0
		while k < keys.size() - 2 and lt > float(keys[k + 1][0]):
			k += 1
		var k1 := mini(k + 1, keys.size() - 1)
		var span := maxf(float(keys[k1][0]) - float(keys[k][0]), 0.001)
		var u := clampf((lt - float(keys[k][0])) / span, 0.0, 1.0)
		var p0: Vector3 = keys[maxi(k - 1, 0)][1]
		var p1: Vector3 = keys[k][1]
		var p2: Vector3 = keys[k1][1]
		var p3: Vector3 = keys[mini(k1 + 1, keys.size() - 1)][1]
		var us := u * u * (3.0 - 2.0 * u) if keys.size() == 2 else u
		(n as Node3D).global_position = p1.cubic_interpolate(p2, p0, p3, us)
		var yaw := lerp_angle(float(keys[k][2]), float(keys[k1][2]), us)
		var pitch := lerpf(float(keys[k][3]) if keys[k].size() > 3 else 0.0, float(keys[k1][3]) if keys[k1].size() > 3 else 0.0, us)
		(n as Node3D).rotation = Vector3(pitch, yaw, 0.0)


## The operator walks: his own physics moves him (feet, footsteps, the rig), the
## director only steers.
func _update_walks(_delta: float) -> void:
	for k in _walks.keys():
		var n = actors.get(k)
		var w: Dictionary = _walks[k]
		if n == null:
			_walks.erase(k)
			continue
		var to: Vector3 = w.to
		var d := Vector3(to.x - n.global_position.x, 0, to.z - n.global_position.z)
		if d.length() < 0.15:
			n.cine_velocity = Vector3.ZERO
			_walks.erase(k)
			continue
		n.cine_velocity = d.normalized() * minf(float(w.speed), d.length() * 3.0)
		if not _looks.has(k):
			n.aim_yaw = lerp_angle(n.aim_yaw, atan2(-d.x, -d.z), 0.08)
			n.rig.aim_yaw = n.aim_yaw


func _update_looks(delta: float) -> void:
	for k in _looks.keys():
		var n = actors.get(k)
		if n == null or n.get("aim_yaw") == null:
			_looks.erase(k)
			continue
		var l: Dictionary = _looks[k]
		var want: float
		if l.yaw != null:
			want = float(l.yaw)
		else:
			var at := _point(l.at)
			want = atan2(-(at.x - n.global_position.x), -(at.z - n.global_position.z))
		n.aim_yaw = lerp_angle(n.aim_yaw, want, 1.0 - exp(-float(l.rate) * delta))
		n.rig.aim_yaw = n.aim_yaw


# ------------------------------------------------------------------ sound

func _one_shot(sound: String, vol: float) -> void:
	var s := AudioStreamPlayer.new()
	s.stream = CineAudio.stream(sound)
	s.volume_db = vol
	s.bus = &"SFX"
	add_child(s)
	s.play()
	s.finished.connect(s.queue_free)


## Starts / retargets a loop's volume (fade in seconds). `at`: a point or actor to
## sound from (3D), else it plays flat (ambience, radio).
func _loop_to(sound: String, vol: float, fade: float, at = null) -> void:
	var p: Node = _loops.get(sound)
	if p == null:
		if vol <= -79.0:
			return
		if at != null:
			var p3 := AudioStreamPlayer3D.new()
			p3.unit_size = 18.0
			p3.max_distance = 220.0
			p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			p = p3
		else:
			p = AudioStreamPlayer.new()
		p.set("stream", CineAudio.stream(sound))
		p.set("bus", &"SFX")
		p.set("volume_db", -60.0)
		if at != null:
			p.set_meta("at", at)   # (a null meta value would delete the key)
		add_child(p)
		p.call("play")
		_loops[sound] = p
	p.set_meta("from", float(p.get("volume_db")))
	p.set_meta("to", vol)
	p.set_meta("t0", t)
	p.set_meta("fade", fade)


func _update_loops(_delta: float) -> void:
	for k in _loops:
		var p: Node = _loops[k]
		var u := clampf((t - float(p.get_meta("t0"))) / maxf(float(p.get_meta("fade")), 0.01), 0.0, 1.0)
		p.set("volume_db", lerpf(float(p.get_meta("from")), float(p.get_meta("to")), u))
		var at = p.get_meta("at") if p.has_meta("at") else null
		if at != null and p is AudioStreamPlayer3D:
			(p as AudioStreamPlayer3D).global_position = _point(at)


# ------------------------------------------------------------------ overlay

func _draw_overlay() -> void:
	var c := _canvas
	var vp := c.size
	# letterbox to 2.39:1
	var bar := maxf((vp.y - vp.x / 2.39) * 0.5, 0.0) * _box
	if bar > 0.5:
		c.draw_rect(Rect2(0, 0, vp.x, bar), Color.BLACK)
		c.draw_rect(Rect2(0, vp.y - bar, vp.x, bar), Color.BLACK)
	# location / time caption, typed in at the lower left
	if not _caption.is_empty() and t < float(_caption.t1):
		var a := clampf((float(_caption.t1) - t) / 0.8, 0.0, 1.0)
		var chars := int((t - float(_caption.t0)) * 28.0)
		var y := vp.y - bar - 64.0
		var lines: Array = _caption.lines
		for i in lines.size():
			var s := String(lines[i])
			var shown := s.substr(0, clampi(chars, 0, s.length()))
			chars -= s.length() + 4
			c.draw_string(_font_bold if i == 0 else _font, Vector2(56, y + i * 24.0), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 22 if i == 0 else 15,
					Color(1, 1, 1, a) if i == 0 else Color(0.86, 0.7, 0.46, a))
	# subtitles
	if not _sub.is_empty() and t < float(_sub.t1):
		var a2 := clampf((t - float(_sub.t0)) / 0.15, 0.0, 1.0) * clampf((float(_sub.t1) - t) / 0.25, 0.0, 1.0)
		var who := String(_sub.who)
		var col: Color = SPEAKER_COLORS.get(who, Color(1, 1, 1))
		var line := String(_sub.text)
		var y2 := vp.y - bar - 28.0 if bar > 1.0 else vp.y - 70.0
		var tag := ("((%s))  " if _sub.radio else "%s  ") % who
		var tw := _font_bold.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var lw := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var x0 := (vp.x - tw - lw) * 0.5
		c.draw_rect(Rect2(x0 - 14, y2 - 22, tw + lw + 28, 32), Color(0, 0, 0, 0.45 * a2))
		c.draw_string(_font_bold, Vector2(x0, y2), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(col, a2))
		c.draw_string(_font, Vector2(x0 + tw, y2), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1, a2))
	# skip prompt, only after a key is touched
	if _skip_shown > 0.0 and not _skipping:
		var a3 := clampf(_skip_shown, 0.0, 1.0)
		var at := Vector2(vp.x - 70.0, vp.y - bar - 40.0 if bar > 1.0 else vp.y - 60.0)
		c.draw_arc(at, 12.0, 0.0, TAU, 32, Color(1, 1, 1, 0.25 * a3), 2.0, true)
		c.draw_arc(at, 12.0, -PI * 0.5, -PI * 0.5 + TAU * (_skip_hold / SKIP_HOLD), 32, Color(1, 1, 1, a3), 3.0, true)
		c.draw_string(_font_bold, at + Vector2(-210, 6), "HOLD [%s] TO SKIP" % Settings.Controls.short("vault"), HORIZONTAL_ALIGNMENT_RIGHT, 190, 13, Color(1, 1, 1, 0.8 * a3))
	if _fade > 0.001:
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _fade))
