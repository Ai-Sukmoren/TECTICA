extends Node
## Gunsmith / class editor: pick a class, swap primary & secondary, change every
## attachment slot, compare stats, with a live rotating 3D preview.

const Data = preload("res://scripts/weapons/weapon_data.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Skins = preload("res://scripts/skins/skins.gd")
const Charm = preload("res://scripts/skins/charm.gd")
const Settings = preload("res://scripts/core/settings.gd")

const WeaponPreview = preload("res://scripts/ui/weapon_preview.gd")

var hud
var is_open := false
var row := 0
var _rows: Array = []
var _row_rects: Array = []
## the gun on its turntable (drag to turn, wheel to zoom)
var preview: WeaponPreview
## attachment slots with a real part on the previewed gun (only those take a skin)
var _skinnable: Dictionary = {}
var _skinnable_id := ""
const SKIN_TAG_W := 150.0


func setup(p_hud) -> void:
	hud = p_hud
	process_mode = Node.PROCESS_MODE_ALWAYS
	preview = WeaponPreview.new()
	add_child(preview)


func open() -> void:
	is_open = true
	row = 0
	preview.set_active(true)


func close() -> void:
	is_open = false
	preview.set_active(false)
	Loadout.save()


func _build_rows() -> void:
	_rows = [{"t": "class"}, {"t": "weapon", "s": "primary"}]
	for a in Data.SLOTS:
		_rows.append({"t": "att", "s": "primary", "a": a})
	_rows.append({"t": "charm", "s": "primary"})
	_rows.append({"t": "weapon", "s": "smg"})
	for a in Data.SLOTS:
		if a != "stock":
			_rows.append({"t": "att", "s": "smg", "a": a})
	_rows.append({"t": "charm", "s": "smg"})
	_rows.append({"t": "weapon", "s": "secondary"})
	for a in Data.SLOTS:
		if a != "stock":
			_rows.append({"t": "att", "s": "secondary", "a": a})
	_rows.append({"t": "charm", "s": "secondary"})
	_rows.append({"t": "knife", "s": "knife"})
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
		"charm":
			Loadout.cycle_charm(r.s, dir)
		"knife":
			Loadout.cycle_knife(dir)
		_:
			return
	Sfx.play(hud, "switch", Vector3.ZERO, -12.0, 0.0)
	# in a solo match the gun in the operator's hands changes as you pick
	if r.t in ["weapon", "att", "charm", "knife", "class"]:
		hud.gunsmith_live_update()


## True when row `i` is an attachment that is physically on the previewed gun.
func _part_row(i: int) -> bool:
	var r: Dictionary = _rows[i]
	return r.t == "att" and r.s == _skinnable_id and _skinnable.has(r.a)


## Steps the skin of the attachment on row `i` (match gun / factory / owned finishes).
func _change_part_skin(i: int, dir: int) -> void:
	if not _part_row(i):
		return
	var r: Dictionary = _rows[i]
	Collection.cycle_part(String(Loadout.entry(r.s).id), r.a, dir)
	Sfx.play(hud, "switch", Vector3.ZERO, -12.0, 0.0)
	hud.gunsmith_live_update()


func _part_skin_label(weapon: String, slot: String) -> String:
	var f := String(Collection.parts_for(weapon).get(slot, ""))
	if f == "":
		return "SKIN: GUN"
	return "SKIN: FACTORY" if f == Skins.FACTORY else "SKIN: " + Skins.finish_name(f).to_upper()


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
	if preview.handle(event):
		return false
	if event.is_action_pressed("reload"):
		preview.reset_view()
		return false
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		row = posmod(row - 1, _rows.size())
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		row = posmod(row + 1, _rows.size())
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_change(row, -1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_change(row, 1)
	elif event.is_action_pressed("peek_left"):
		_change_part_skin(row, -1)
	elif event.is_action_pressed("peek_right"):
		_change_part_skin(row, 1)
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
					if _part_row(i) and event.position.x > rr.end.x - SKIN_TAG_W:
						_change_part_skin(i, 1)   # the skin tag at the row's right end
						return false
					_change(i, -1 if event.position.x < rr.position.x + rr.size.x * 0.45 else 1)
				elif event.button_index == MOUSE_BUTTON_RIGHT:
					_change(i, -1)
	return false


func _process(_delta: float) -> void:
	if not is_open:
		return
	_build_rows()
	var e: Dictionary = Loadout.entry(_focus_slot())
	var wid := String(e.id)
	var before: Node3D = preview.weapon
	preview.show_weapon(wid, e.att, Collection.skin_for(wid), Collection.parts_for(wid), String(e.get("charm", "")))
	if preview.weapon != before:
		# attachment slots with a real part on the gun shown (only those take a skin)
		_skinnable = {}
		_skinnable_id = _focus_slot()
		for mi in preview.weapon.find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("skin_part"):
				_skinnable[String(mi.get_meta("skin_part"))] = true


# ---------------------------------------------------------------- drawing

func draw(c: Control, vp: Vector2) -> void:
	_build_rows()
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.025, 0.03, 0.9))
	hud._text(c, Vector2(70, 70), "GUNSMITH  //  CLASS LOADOUT", 26, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(70, 96), Loadout.class_desc(), 13, hud.DIM)

	# --- rows
	_row_rects.clear()
	var y := 140.0
	var row_step := minf(32.0, (vp.y - 220.0) / _rows.size())
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
				label = {"primary": "PRIMARY", "smg": "SMG"}.get(r.s, "PISTOL")
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
			"knife":
				label = "KNIFE"
				value = "%s   MELEE  ·  KEY 3" % Data.WEAPONS[Loadout.knife].name
				head = true
				y += 10.0
			"charm":
				indent = 22.0
				label = "WEAPON CHARM"
				value = Charm.label(String(Loadout.entry(r.s).get("charm", "")))
			"reset":
				label = "RESET CLASS TO DEFAULT"
				y += 12.0
			"back":
				label = "SAVE & BACK"
		var rect := Rect2(60 + indent, y - 20, 560 - indent, row_step - 2)
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
		if _part_row(i):
			# this attachment's own skin; Q / E (or a click here) changes it
			var wid := String(Loadout.entry(r.s).id)
			var pf := String(Collection.parts_for(wid).get(r.a, ""))
			var tag_col: Color = Skins.RARITY_COLORS[Skins.rarity_of(pf)] if Skins.FINISHES.has(pf) else hud.DIM
			hud._text(c, Vector2(rect.end.x - SKIN_TAG_W, y), ("Q  " if sel else "") + _part_skin_label(wid, r.a) + ("  E" if sel else ""), 11,
					tag_col if not sel else hud.WARN, HORIZONTAL_ALIGNMENT_RIGHT, SKIN_TAG_W - 8.0)
		y += row_step

	# --- preview
	var pr := Rect2(vp.x * 0.42, 110, vp.x * 0.54, vp.x * 0.27)
	c.draw_rect(pr, Color(0.06, 0.07, 0.08, 0.8))
	hud._brackets(c, pr, 18.0, Color(hud.TEXT, 0.4), 1.5)
	preview.draw(c, pr)
	var slot := _focus_slot()
	var e3: Dictionary = Loadout.entry(slot)
	var st := Data.compute(e3.id, e3.att)
	var base := Data.compute(e3.id, Data.WEAPONS[e3.id].defaults)
	hud._text(c, pr.position + Vector2(18, 34), String(st.name), 28, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, pr.position + Vector2(18, 56), String(st.category) + ("   ·   SUPPRESSED" if st.suppressed else "") + ("   ·   ARMOR-PIERCING" if st.get("pierce", false) else ""), 12, hud.DIM)
	var sk2 := Collection.skin_for(String(e3.id))
	hud._text(c, pr.position + Vector2(18, 76), "SKIN  ·  " + (Skins.finish_name(sk2).to_upper() if sk2 != "" else "FACTORY  (ARMORY TO CHANGE)"), 12,
			Skins.RARITY_COLORS[Skins.rarity_of(sk2)] if sk2 != "" else hud.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(pr.position.x + 18, pr.end.y - 14), "Drag to rotate  ·  Wheel to zoom  ·  [%s] reset view" % Settings.Controls.short("reload"), 12, hud.DIM)

	# --- stats
	draw_stats(c, st, base, Vector2(pr.position.x, pr.end.y + 34.0), pr.size.x, "Green = better than stock, red = worse.")
	hud._text(c, Vector2(0, vp.y - 30), "W/S select   ·   A/D or click change   ·   Q/E attachment skin   ·   Esc / B save & back", 12, hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Stat bars for `st`, each against `ref` (the gain green, the loss red), in two columns from `pos`, `width` wide;
## then magazine, reload and action, and `legend` under them. The gunsmith and the zombie shop draw these.
func draw_stats(c: Control, st: Dictionary, ref: Dictionary, pos: Vector2, width: float, legend: String) -> void:
	var bars := [
		["DAMAGE", _n(st.damage * st.pellets, 130.0), _n(ref.damage * ref.pellets, 130.0), "%d%s" % [int(st.damage), (" x%d" % int(st.pellets)) if int(st.pellets) > 1 else ""]],
		["FIRE RATE", _n(st.rpm, 1100.0), _n(ref.rpm, 1100.0), "%d RPM" % int(st.rpm)],
		["RANGE", _n(st.range, 170.0), _n(ref.range, 170.0), "%d m" % int(st.range)],
		["ACCURACY", 1.0 - _n(st.spread_aim, 4.5), 1.0 - _n(ref.spread_aim, 4.5), ""],
		["HIP FIRE", 1.0 - _n(st.spread_hip, 8.0), 1.0 - _n(ref.spread_hip, 8.0), ""],
		["RECOIL CONTROL", 1.0 - _n(st.recoil, 3.2), 1.0 - _n(ref.recoil, 3.2), ""],
		["MOBILITY", _n(st.mobility - 0.7, 0.5), _n(ref.mobility - 0.7, 0.5), ""],
		["ADS SPEED", _n(st.ads_speed, 1.8), _n(ref.ads_speed, 1.8), ""],
	]
	var bw := width * 0.5 - 30.0
	for i in bars.size():
		var b: Array = bars[i]
		var px := pos.x + (i % 2) * (bw + 50.0)
		var py := pos.y + (i / 2) * 40.0
		hud._text(c, Vector2(px, py), b[0], 12, hud.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		if b[3] != "":
			hud._text(c, Vector2(px, py), b[3], 12, hud.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, bw)
		var track := Rect2(px, py + 8, bw, 6)
		c.draw_rect(track, Color(1, 1, 1, 0.08))
		var cur: float = clampf(b[1], 0.02, 1.0)
		var r: float = clampf(b[2], 0.02, 1.0)
		c.draw_rect(Rect2(track.position, Vector2(bw * minf(cur, r), 6)), Color(hud.TEXT, 0.85))
		if cur > r + 0.005:
			c.draw_rect(Rect2(track.position + Vector2(bw * r, 0), Vector2(bw * (cur - r), 6)), hud.ACCENT)
		elif cur < r - 0.005:
			c.draw_rect(Rect2(track.position + Vector2(bw * cur, 0), Vector2(bw * (r - cur), 6)), hud.DANGER)
	var iy := pos.y + 4 * 40.0 + 14.0
	hud._text(c, Vector2(pos.x, iy), "MAGAZINE  %d / %d      RELOAD  %.1f s      %s" % [int(st.mag), int(st.reserve), float(st.reload), "AUTO" if st.auto else ("BOLT-ACTION" if st.cycle == "bolt" else ("PUMP-ACTION" if st.cycle == "pump" else ("LEVER-ACTION" if st.cycle == "lever" else "SEMI-AUTO")))],
			13, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(pos.x, iy + 22), legend, 11, hud.DIM)


func _n(v, maxv: float) -> float:
	return clampf(float(v) / maxv, 0.0, 1.0)
