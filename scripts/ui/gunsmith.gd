extends Node
## Gunsmith / class editor: pick a class, swap primary & secondary, change every
## attachment slot, compare stats, with a live rotating 3D preview.

const Data = preload("res://scripts/weapons/weapon_data.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Skins = preload("res://scripts/skins/skins.gd")

var hud
var is_open := false
var row := 0
var _rows: Array = []
var _row_rects: Array = []
var _sv: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _preview_key := ""
var _spin := 0.0


func setup(p_hud) -> void:
	hud = p_hud
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sv = SubViewport.new()
	_sv.size = Vector2i(960, 480)
	_sv.transparent_bg = true
	_sv.own_world_3d = true
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 2.4
	_sv.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 1.4
	rim.light_color = Color(1.0, 0.55, 0.45)
	_sv.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_sv.add_child(_cam)
	_pivot = Node3D.new()
	_sv.add_child(_pivot)


func open() -> void:
	is_open = true
	row = 0
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_key = ""


func close() -> void:
	is_open = false
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Loadout.save()


func _build_rows() -> void:
	_rows = [{"t": "class"}, {"t": "weapon", "s": "primary"}]
	for a in Data.SLOTS:
		_rows.append({"t": "att", "s": "primary", "a": a})
	_rows.append({"t": "weapon", "s": "secondary"})
	for a in Data.SLOTS:
		if a != "stock":
			_rows.append({"t": "att", "s": "secondary", "a": a})
	_rows.append({"t": "reset"})
	_rows.append({"t": "back"})


func _focus_slot() -> String:
	if row < _rows.size() and _rows[row].has("s"):
		return _rows[row].s
	return "primary"


func _change(i: int, dir: int) -> void:
	var r: Dictionary = _rows[i]
	match r.t:
		"class":
			Loadout.cycle_class(dir)
		"weapon":
			Loadout.cycle_weapon(r.s, dir)
		"att":
			Loadout.cycle_attachment(r.s, r.a, dir)
		_:
			return
	Sfx.play(hud, "switch", Vector3.ZERO, -12.0, 0.0)


func _activate(i: int) -> bool:
	var r: Dictionary = _rows[i]
	if r.t == "back":
		return true
	if r.t == "reset":
		Loadout.reset_class()
	else:
		_change(i, 1)
	return false


## Returns true when the screen should close.
func handle(event: InputEvent) -> bool:
	_build_rows()
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("crouch"):
		return true
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		row = posmod(row - 1, _rows.size())
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		row = posmod(row + 1, _rows.size())
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_change(row, -1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_change(row, 1)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("vault"):
		return _activate(row)
	elif event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				row = i
	elif event is InputEventMouseButton and event.pressed:
		for i in _row_rects.size():
			var rr: Rect2 = _row_rects[i]
			if rr.has_point(event.position):
				row = i
				if event.button_index == MOUSE_BUTTON_LEFT:
					var t: String = _rows[i].t
					if t == "back" or t == "reset":
						return _activate(i)
					_change(i, -1 if event.position.x < rr.position.x + rr.size.x * 0.45 else 1)
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					_change(i, -1)
	return false


func _process(delta: float) -> void:
	if not is_open:
		return
	_spin += delta * 0.45
	_build_rows()
	var e: Dictionary = Loadout.entry(_focus_slot())
	var sk := Collection.skin_for(String(e.id))
	var key := str(e.id) + str(e.att) + sk
	if key != _preview_key:
		_preview_key = key
		for c in _pivot.get_children():
			c.queue_free()
		var w := Weapon.new()
		w.setup(String(e.id), e.att)
		w.apply_skin(sk)
		_pivot.add_child(w)
		var pistol := w.is_pistol()
		w.position = Vector3(0, -0.02, 0.1 if pistol else 0.26)
		var dist := 0.75 if pistol else (1.75 if e.id == "awp" else 1.4)
		_cam.position = Vector3(0, 0.12, dist)
		_cam.look_at(Vector3(0, 0.02, 0), Vector3.UP)
	_pivot.rotation = Vector3(0.12 * sin(_spin * 0.7), -PI * 0.5 + sin(_spin) * 0.9, 0)


# ---------------------------------------------------------------- drawing

func draw(c: Control, vp: Vector2) -> void:
	_build_rows()
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.025, 0.03, 0.9))
	hud._text(c, Vector2(70, 70), "GUNSMITH  //  CLASS LOADOUT", 26, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(70, 96), Loadout.class_desc(), 13, hud.DIM)

	# --- rows
	_row_rects.clear()
	var y := 140.0
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var indent := 0.0
		var label := ""
		var value := ""
		var head := false
		match r.t:
			"class":
				label = "CLASS"
				value = Loadout.class_label()
				head = true
			"weapon":
				var e: Dictionary = Loadout.entry(r.s)
				label = "PRIMARY" if r.s == "primary" else "SECONDARY"
				value = "%s   %s" % [Data.WEAPONS[e.id].name, Data.WEAPONS[e.id].category]
				head = true
				y += 10.0
			"att":
				var e2: Dictionary = Loadout.entry(r.s)
				indent = 22.0
				label = Data.SLOT_NAMES[r.a]
				var opts: Array = Data.WEAPONS[e2.id].options[r.a]
				value = String(Data.ATTACHMENTS[r.a][e2.att[r.a]].name)
				if opts.size() <= 1:
					value += "   (FIXED)"
			"reset":
				label = "RESET CLASS TO DEFAULT"
				y += 12.0
			"back":
				label = "SAVE & BACK"
		var rect := Rect2(60 + indent, y - 20, 560 - indent, 28)
		_row_rects.append(rect)
		var sel := i == row
		if sel:
			c.draw_rect(rect, Color(hud.RED, 0.22))
			hud._brackets(c, rect, 8.0, hud.RED, 2.0)
		var col: Color = hud.TEXT if sel else (hud.TEXT if head else hud.DIM)
		hud._text(c, Vector2(rect.position.x + 12, y), label, 14 if head else 13, col, HORIZONTAL_ALIGNMENT_LEFT, -1, head)
		if value != "":
			var shown := ("<  " + value + "  >") if sel else value
			hud._text(c, Vector2(rect.position.x + 170, y), shown, 14 if head else 13, hud.WARN if sel else col, HORIZONTAL_ALIGNMENT_LEFT, -1, head)
		y += 32.0

	# --- preview
	var pr := Rect2(vp.x * 0.42, 110, vp.x * 0.54, vp.x * 0.27)
	c.draw_rect(pr, Color(0.06, 0.07, 0.08, 0.8))
	hud._brackets(c, pr, 18.0, Color(hud.TEXT, 0.4), 1.5)
	c.draw_texture_rect(_sv.get_texture(), pr, false)
	var slot := _focus_slot()
	var e3: Dictionary = Loadout.entry(slot)
	var st := Data.compute(e3.id, e3.att)
	var base := Data.compute(e3.id, Data.WEAPONS[e3.id].defaults)
	hud._text(c, pr.position + Vector2(18, 34), String(st.name), 28, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, pr.position + Vector2(18, 56), String(st.category) + ("   ·   SUPPRESSED" if st.suppressed else ""), 12, hud.DIM)
	var sk2 := Collection.skin_for(String(e3.id))
	hud._text(c, pr.position + Vector2(18, 76), "SKIN  ·  " + (Skins.finish_name(sk2).to_upper() if sk2 != "" else "FACTORY  (ARMORY TO CHANGE)"), 12,
			Skins.RARITY_COLORS[Skins.rarity_of(sk2)] if sk2 != "" else hud.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)

	# --- stats
	var sy := pr.end.y + 34.0
	var bars := [
		["DAMAGE", _n(st.damage * st.pellets, 130.0), _n(base.damage * base.pellets, 130.0), "%d%s" % [int(st.damage), (" x%d" % int(st.pellets)) if int(st.pellets) > 1 else ""]],
		["FIRE RATE", _n(st.rpm, 1100.0), _n(base.rpm, 1100.0), "%d RPM" % int(st.rpm)],
		["RANGE", _n(st.range, 170.0), _n(base.range, 170.0), "%d m" % int(st.range)],
		["ACCURACY", 1.0 - _n(st.spread_aim, 4.5), 1.0 - _n(base.spread_aim, 4.5), ""],
		["HIP FIRE", 1.0 - _n(st.spread_hip, 8.0), 1.0 - _n(base.spread_hip, 8.0), ""],
		["RECOIL CONTROL", 1.0 - _n(st.recoil, 3.2), 1.0 - _n(base.recoil, 3.2), ""],
		["MOBILITY", _n(st.mobility - 0.7, 0.5), _n(base.mobility - 0.7, 0.5), ""],
		["ADS SPEED", _n(st.ads_speed, 1.8), _n(base.ads_speed, 1.8), ""],
	]
	var bx := pr.position.x
	var bw := pr.size.x * 0.5 - 30.0
	for i in bars.size():
		var b: Array = bars[i]
		var col_i := i % 2
		var row_i := i / 2
		var px := bx + col_i * (bw + 50.0)
		var py := sy + row_i * 40.0
		hud._text(c, Vector2(px, py), b[0], 12, hud.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		if b[3] != "":
			hud._text(c, Vector2(px, py), b[3], 12, hud.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, bw)
		var track := Rect2(px, py + 8, bw, 6)
		c.draw_rect(track, Color(1, 1, 1, 0.08))
		var cur: float = clampf(b[1], 0.02, 1.0)
		var ref: float = clampf(b[2], 0.02, 1.0)
		c.draw_rect(Rect2(track.position, Vector2(bw * minf(cur, ref), 6)), Color(hud.TEXT, 0.85))
		if cur > ref + 0.005:
			c.draw_rect(Rect2(track.position + Vector2(bw * ref, 0), Vector2(bw * (cur - ref), 6)), hud.ACCENT)
		elif cur < ref - 0.005:
			c.draw_rect(Rect2(track.position + Vector2(bw * cur, 0), Vector2(bw * (ref - cur), 6)), hud.DANGER)
	var iy := sy + 4 * 40.0 + 14.0
	hud._text(c, Vector2(bx, iy), "MAGAZINE  %d / %d      RELOAD  %.1f s      %s" % [int(st.mag), int(st.reserve), float(st.reload), "AUTO" if st.auto else ("BOLT-ACTION" if st.cycle == "bolt" else ("PUMP-ACTION" if st.cycle == "pump" else "SEMI-AUTO"))],
			13, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(bx, iy + 22), "Green = better than stock, red = worse.", 11, hud.DIM)
	hud._text(c, Vector2(0, vp.y - 30), "W/S select   ·   A/D or click change   ·   Esc / B save & back", 12, hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _n(v, maxv: float) -> float:
	return clampf(float(v) / maxv, 0.0, 1.0)
