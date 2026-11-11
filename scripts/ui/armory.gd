extends Node
## ARMORY: weapon-skin supply packs (booster-pack style opening) and the
## collection where owned skins are equipped. Credits are earned in the field.
##
##   PACKS       pick one of three packs, buy it with credits, watch it shake
##               and tear open, then flip the five skins one by one (rarest
##               last) with a live 3D preview of each gun in its new finish.
##   COLLECTION  every gun x every finish; owned skins can be equipped.

const Skins = preload("res://scripts/skins/skins.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")

const OPEN_TIME := 1.35
const FLIP_SPEED := 3.2
## showcase gun + finish shown on each pack's preview
const PACK_SHOWCASE := [["m4a1", "woodland"], ["ak47", "damascus"], ["awp", "aurora"]]

var hud
var is_open := false
var tab := 0                 # 0 packs, 1 collection
var pack_i := 1
var phase := "browse"        # browse -> opening -> reveal
var t := 0.0
var cards: Array = []
var flipped := 0
var flip_t: Array = []
var burst_t: Array = []
var focus_card := -1
var msg := ""
var msg_t := 0.0
var shake := 0.0
var coll_weapon := 0
var coll_tile := 0

var _sv: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _preview_key := ""
var _spin := 0.0
var _tab_rects: Array = []
var _pack_rects: Array = []
var _card_rects: Array = []
var _tile_rects: Array = []
var _wlist_rects: Array = []


func setup(p_hud) -> void:
	hud = p_hud
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sv = SubViewport.new()
	_sv.size = Vector2i(960, 420)
	_sv.transparent_bg = true
	_sv.own_world_3d = true
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 2.6
	_sv.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 1.6
	rim.light_color = Color(0.7, 0.8, 1.0)
	_sv.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 28.0
	_sv.add_child(_cam)
	_pivot = Node3D.new()
	_sv.add_child(_pivot)


func open() -> void:
	Collection.ensure()
	is_open = true
	phase = "browse"
	tab = 0
	_preview_key = ""
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func close() -> void:
	is_open = false
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Collection.save()


func _tiles() -> Array:
	return [""] + Skins.finish_ids()


func _coll_weapon_id() -> String:
	return String(Skins.weapon_ids()[coll_weapon])


# ================================================================ actions

func _say(text: String, bad: bool = false) -> void:
	msg = text
	msg_t = 3.0
	if bad:
		shake = 0.45
		Sfx.play(hud, "dry", Vector3.ZERO, -6.0, 0.0)


func _buy() -> void:
	var pack: Dictionary = Skins.PACKS[pack_i]
	if Collection.credits < int(pack.price):
		_say("NOT ENOUGH CREDITS  ·  EARN MORE IN THE FIELD (KILLS, WAVES, MISSIONS)", true)
		return
	cards = Collection.open_pack(pack_i)
	if cards.is_empty():
		return
	phase = "opening"
	t = 0.0
	flipped = 0
	focus_card = -1
	flip_t = []
	burst_t = []
	for i in cards.size():
		flip_t.append(0.0)
		burst_t.append(0.0)
	Sfx.play(hud, "pin", Vector3.ZERO, -4.0, 0.0)


func _flip_next() -> void:
	if flipped >= cards.size():
		return
	focus_card = flipped
	burst_t[flipped] = 1.0
	var r := int(cards[flipped].rarity)
	Sfx.play(hud, ["switch", "mag_in", "hitmarker", "kill", "kill"][r], Vector3.ZERO, [-8.0, -6.0, -4.0, -2.0, 2.0][r], 0.0)
	flipped += 1


func _flip_all() -> void:
	while flipped < cards.size():
		_flip_next()


func _equip_tile() -> void:
	var w := _coll_weapon_id()
	var f: String = _tiles()[coll_tile]
	if not Collection.has_skin(w, f):
		_say("LOCKED  ·  PULL IT FROM A SUPPLY PACK", true)
		return
	Collection.equip(w, f)
	Sfx.play(hud, "mag_in", Vector3.ZERO, -4.0, 0.0)
	_say("EQUIPPED  ·  %s  %s" % [Skins.weapon_name(w), Skins.finish_name(f).to_upper() if f != "" else "FACTORY"])


## Returns true when the screen should close.
func handle(event: InputEvent) -> bool:
	var back: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")
	if phase == "opening":
		if event.is_action_pressed("ui_accept") or back:
			t = OPEN_TIME
		return false
	if phase == "reveal":
		var go: bool = event.is_action_pressed("ui_accept") or event.is_action_pressed("vault")
		var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_flip_all()
		elif back:
			if flipped < cards.size():
				_flip_all()
			else:
				phase = "browse"
		elif go or click:
			if flipped < cards.size():
				if click:
					for i in _card_rects.size():
						if (_card_rects[i] as Rect2).has_point(event.position) and i >= flipped:
							_flip_next()
							return false
				_flip_next()
			elif go:
				_buy()   # open another of the same pack
			elif click:
				for i in _card_rects.size():
					if (_card_rects[i] as Rect2).has_point(event.position):
						focus_card = i
		elif event is InputEventMouseMotion and flipped > 0:
			for i in _card_rects.size():
				if (_card_rects[i] as Rect2).has_point(event.position) and i < flipped:
					focus_card = i
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
			focus_card = maxi(focus_card - 1, 0)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
			focus_card = mini(focus_card + 1, flipped - 1)
		return false

	if back:
		return true
	if event.is_action_pressed("peek_left") or event.is_action_pressed("peek_right") or event.is_action_pressed("ui_focus_next") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_TAB):
		tab = 1 - tab
		_preview_key = ""
		return false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _tab_rects.size():
			if (_tab_rects[i] as Rect2).has_point(event.position):
				tab = i
				return false
	if tab == 0:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
			pack_i = posmod(pack_i - 1, Skins.PACKS.size())
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
			pack_i = posmod(pack_i + 1, Skins.PACKS.size())
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("vault"):
			_buy()
		elif event is InputEventMouseMotion:
			for i in _pack_rects.size():
				if (_pack_rects[i] as Rect2).has_point(event.position):
					pack_i = i
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in _pack_rects.size():
				if (_pack_rects[i] as Rect2).has_point(event.position):
					pack_i = i
					_buy()
	else:
		var n_tiles := _tiles().size()
		if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
			coll_weapon = posmod(coll_weapon - 1, Skins.weapon_ids().size())
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
			coll_weapon = posmod(coll_weapon + 1, Skins.weapon_ids().size())
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
			coll_tile = posmod(coll_tile - 1, n_tiles)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
			coll_tile = posmod(coll_tile + 1, n_tiles)
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("vault"):
			_equip_tile()
		elif event is InputEventMouseMotion:
			for i in _tile_rects.size():
				if (_tile_rects[i] as Rect2).has_point(event.position):
					coll_tile = i
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in _wlist_rects.size():
				if (_wlist_rects[i] as Rect2).has_point(event.position):
					coll_weapon = i
					return false
			for i in _tile_rects.size():
				if (_tile_rects[i] as Rect2).has_point(event.position):
					coll_tile = i
					_equip_tile()
	return false


# ================================================================ update

func _process(delta: float) -> void:
	if not is_open:
		return
	t += delta
	_spin += delta * 0.5
	msg_t = maxf(msg_t - delta, 0.0)
	shake = maxf(shake - delta, 0.0)
	if phase == "opening" and t >= OPEN_TIME:
		phase = "reveal"
		Sfx.play(hud, "swipe", Vector3.ZERO, 0.0, 0.0)
	for i in flip_t.size():
		if i < flipped:
			flip_t[i] = minf(float(flip_t[i]) + delta * FLIP_SPEED, 1.0)
		burst_t[i] = maxf(float(burst_t[i]) - delta * 0.7, 0.0)
	# what the 3D preview shows
	var w := ""
	var f := ""
	if phase == "reveal" and focus_card >= 0 and focus_card < cards.size():
		w = String(cards[focus_card].weapon)
		f = String(cards[focus_card].finish)
	elif phase == "browse" and tab == 0:
		w = PACK_SHOWCASE[pack_i][0]
		f = PACK_SHOWCASE[pack_i][1]
	elif phase == "browse":
		w = _coll_weapon_id()
		f = _tiles()[coll_tile]
	_set_preview(w, f)
	_pivot.rotation = Vector3(0.1 * sin(_spin * 0.7), -PI * 0.5 + sin(_spin) * 0.8, 0)


func _set_preview(weapon: String, finish: String) -> void:
	var k := weapon + ":" + finish
	if k == _preview_key:
		return
	_preview_key = k
	for ch in _pivot.get_children():
		ch.queue_free()
	if weapon == "":
		return
	var gun := Weapon.new()
	gun.setup(weapon, {})
	gun.apply_skin(finish)
	_pivot.add_child(gun)
	var pistol := gun.is_pistol()
	gun.position = Vector3(0, -0.02, 0.1 if pistol else 0.26)
	var dist := 0.8 if pistol else (1.9 if weapon == "awp" else 1.5)
	_cam.position = Vector3(0, 0.1, dist)
	_cam.look_at(Vector3(0, 0.02, 0), Vector3.UP)


# ================================================================ drawing

func draw(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.02, 0.03, 0.94))
	var sx := sin(t * 70.0) * 10.0 * shake
	hud._text(c, Vector2(60 + sx, 66), "ARMORY  //  WEAPON SKINS", 26, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(60, 90), "%d / %d SKINS COLLECTED   ·   %d PACKS OPENED" % [Collection.total_owned(), Skins.FINISHES.size() * Skins.weapon_ids().size(), Collection.packs_opened], 12, hud.DIM)
	hud._text(c, Vector2(vp.x - 360 + sx, 66), "CR  %s" % _thousands(Collection.credits), 26, hud.WARN, HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
	hud._text(c, Vector2(vp.x - 360, 90), "CREDITS  ·  EARNED IN THE FIELD", 11, hud.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	if phase == "browse":
		_tab_rects.clear()
		for i in 2:
			var r := Rect2(60 + i * 220, 108, 200, 30)
			_tab_rects.append(r)
			var sel := i == tab
			c.draw_rect(r, Color(hud.RED, 0.25) if sel else Color(1, 1, 1, 0.04))
			if sel:
				hud._brackets(c, r, 8.0, hud.RED, 2.0)
			hud._text(c, Vector2(r.position.x, r.position.y + 21), ["SUPPLY PACKS", "COLLECTION"][i], 14, hud.TEXT if sel else hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
		if tab == 0:
			_draw_packs(c, vp)
		else:
			_draw_collection(c, vp)
	elif phase == "opening":
		_draw_opening(c, vp)
	else:
		_draw_reveal(c, vp)
	if msg_t > 0.0:
		hud._text(c, Vector2(sx, vp.y - 62), msg, 15, Color(hud.WARN, clampf(msg_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _preview_rect(vp: Vector2, top: float, h: float) -> Rect2:
	var w := minf(vp.x * 0.62, h * 2.3)
	return Rect2(vp.x * 0.5 - w * 0.5, top, w, h)


# ---------------------------------------------------------------- packs

func _draw_pack(c: Control, r: Rect2, pack: Dictionary, glow: float, tear: float = 0.0) -> void:
	var c0: Color = pack.colors[0]
	var c1: Color = pack.colors[1]
	if glow > 0.0:
		for k in 4:
			var g := 6.0 + k * 6.0
			c.draw_rect(r.grow(g), Color(c1, 0.07 * glow * (4 - k)), false, 6.0)
	# foil body: vertical gradient
	var bands := 16
	for i in bands:
		var f := float(i) / bands
		var col := c0.lerp(c0.lightened(0.25), sin(f * PI) * 0.6)
		c.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * f, r.size.x, r.size.y / bands + 1.0), col)
	# moving shimmer band
	var sh := fmod(t * 0.35 + float(pack.price) * 0.001, 1.6) - 0.3
	var x0 := r.position.x + r.size.x * sh
	var shimmer := PackedVector2Array([Vector2(x0, r.position.y), Vector2(x0 + 40, r.position.y),
			Vector2(x0 - 30, r.end.y), Vector2(x0 - 70, r.end.y)])
	var clipped := Geometry2D.intersect_polygons(shimmer, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	for poly in clipped:
		c.draw_colored_polygon(poly, Color(1, 1, 1, 0.13))
	# crimped seals top and bottom (top one tears off when opened)
	var seal := 16.0
	var top_off := Vector2(tear * 30.0, -tear * 160.0)
	_crimp(c, Rect2(r.position + top_off, Vector2(r.size.x, seal)), c1.darkened(0.2), tear * 0.5)
	_crimp(c, Rect2(Vector2(r.position.x, r.end.y - seal), Vector2(r.size.x, seal)), c1.darkened(0.2), 0.0)
	# emblem
	var cen := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.38)
	c.draw_circle(cen, r.size.x * 0.24, Color(0, 0, 0, 0.35))
	c.draw_arc(cen, r.size.x * 0.24, 0, TAU, 40, c1, 3.0, true)
	c.draw_arc(cen, r.size.x * 0.13, 0, TAU, 32, Color(c1, 0.7), 2.0, true)
	for a in 4:
		var d := Vector2.RIGHT.rotated(a * PI * 0.5)
		c.draw_line(cen + d * r.size.x * 0.08, cen + d * r.size.x * 0.3, c1, 2.0)
	hud._text(c, Vector2(r.position.x, r.position.y + r.size.y * 0.66), String(pack.name), 18, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	hud._text(c, Vector2(r.position.x, r.position.y + r.size.y * 0.66 + 22), "%d WEAPON SKINS" % int(pack.cards), 12, Color(c1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	hud._text(c, Vector2(r.position.x, r.position.y + r.size.y * 0.66 + 40), String(pack.tag), 10, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	hud._text(c, Vector2(r.position.x, r.end.y - 26), "CR  %s" % _thousands(int(pack.price)), 20, hud.WARN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)


func _crimp(c: Control, r: Rect2, col: Color, rot: float) -> void:
	var pts := PackedVector2Array()
	var teeth := 14
	pts.append(r.position)
	for i in teeth + 1:
		var x := r.position.x + r.size.x * float(i) / teeth
		pts.append(Vector2(x, r.position.y + (r.size.y if i % 2 == 0 else r.size.y * 0.55)))
	pts.append(Vector2(r.end.x, r.position.y))
	if rot != 0.0:
		var cen := r.get_center()
		for i in pts.size():
			pts[i] = cen + (pts[i] - cen).rotated(rot)
	c.draw_colored_polygon(pts, col)


func _draw_packs(c: Control, vp: Vector2) -> void:
	var pr := _preview_rect(vp, 150, vp.y * 0.26)
	c.draw_texture_rect(_sv.get_texture(), pr, false)
	var show: Array = PACK_SHOWCASE[pack_i]
	hud._text(c, Vector2(0, pr.end.y + 4), "PREVIEW  ·  %s  %s" % [Skins.weapon_name(show[0]), Skins.finish_name(show[1]).to_upper()], 11, hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_pack_rects.clear()
	var pw := minf(230.0, vp.x * 0.17)
	var ph := pw * 1.42
	var gap := pw * 0.3
	var total := pw * 3 + gap * 2
	var y := pr.end.y + 40
	for i in Skins.PACKS.size():
		var sel := i == pack_i
		var lift := (14.0 + sin(t * 3.0) * 4.0) if sel else 0.0
		var r := Rect2(vp.x * 0.5 - total * 0.5 + i * (pw + gap), y - lift, pw, ph)
		_pack_rects.append(r)
		_draw_pack(c, r, Skins.PACKS[i], 1.0 if sel else 0.0)
		if not sel:
			c.draw_rect(r, Color(0, 0, 0, 0.35))
	# odds for the selected pack
	var pack: Dictionary = Skins.PACKS[pack_i]
	var oy := y + ph + 30
	var parts: Array = []
	for r_i in 5:
		parts.append("%s %s%%" % [Skins.RARITY_NAMES[r_i], _pct(float(pack.odds[r_i]))])
	var seg_w := 170.0
	var x := vp.x * 0.5 - seg_w * 2.5
	for r_i in 5:
		hud._text(c, Vector2(x + r_i * seg_w, oy), parts[r_i], 12, Skins.RARITY_COLORS[r_i], HORIZONTAL_ALIGNMENT_CENTER, seg_w, true)
	var afford: bool = Collection.credits >= int(pack.price)
	hud._text(c, Vector2(0, oy + 28), ("Enter / click  ·  OPEN %s  (CR %s)" % [pack.name, _thousands(int(pack.price))]) if afford else "NOT ENOUGH CREDITS FOR THIS PACK",
			15, hud.WARN if afford else hud.DANGER, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	hud._text(c, Vector2(0, vp.y - 30), "A/D choose pack   ·   Enter open   ·   Q/E or Tab  collection   ·   Esc back      Duplicates refund credits", 12, hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _pct(v: float) -> String:
	return ("%.1f" % v) if v < 10.0 and absf(v - roundf(v)) > 0.01 else str(int(roundf(v)))


func _draw_opening(c: Control, vp: Vector2) -> void:
	var pack: Dictionary = Skins.PACKS[pack_i]
	var k := clampf(t / OPEN_TIME, 0.0, 1.0)
	var c1: Color = pack.colors[1]
	# light rays behind the pack
	var cen := vp * 0.5
	for i in 16:
		var a := TAU * i / 16.0 + t * 0.6
		var w := 0.08
		var len := vp.length() * 0.6
		c.draw_colored_polygon(PackedVector2Array([cen, cen + Vector2.RIGHT.rotated(a - w) * len, cen + Vector2.RIGHT.rotated(a + w) * len]), Color(c1, 0.05 + 0.1 * k))
	var pw := 300.0
	var ph := pw * 1.42
	var shake_amt := pow(k, 2.0) * 14.0
	var off := Vector2(sin(t * 60.0), cos(t * 47.0)) * shake_amt
	var r := Rect2(cen - Vector2(pw, ph) * 0.5 + off, Vector2(pw, ph))
	var tear := smoothstep(0.72, 1.0, k)
	_draw_pack(c, r, pack, 1.0 + k, tear)
	var flash := smoothstep(0.85, 1.0, k)
	if flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, flash * 0.85))
	hud._text(c, Vector2(0, vp.y - 40), "OPENING  %s ..." % pack.name, 14, hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


# ---------------------------------------------------------------- reveal

func _draw_swatch(c: Control, r: Rect2, finish: String) -> void:
	if finish == "" or not Skins.FINISHES.has(finish):
		c.draw_rect(r, Color(0.18, 0.2, 0.22))
		return
	var cols: Array = Skins.FINISHES[finish].c
	c.draw_rect(r, cols[0])
	var nx := 8
	var ny := 3
	for i in nx:
		for j in ny:
			var h := fposmod(sin(float(i) * 12.9898 + float(j) * 78.233 + float(finish.hash() % 97)) * 43758.5453, 1.0)
			if h < 0.45 or cols.size() < 2:
				continue
			var col: Color = cols[1 + int(h * 10.0) % (cols.size() - 1)]
			var cell := Vector2(r.size.x / nx, r.size.y / ny)
			c.draw_rect(Rect2(r.position + Vector2(i, j) * cell, cell), col)
	if float(Skins.FINISHES[finish].get("e", 0.0)) > 0.0:
		var g: Color = cols[1] if cols.size() > 1 else cols[0]
		var y := r.position.y + r.size.y * (0.5 + 0.35 * sin(t * 2.5))
		c.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(g, 0.9), 2.0)
	c.draw_rect(r, Color(0, 0, 0, 0.5), false, 1.0)


func _draw_card(c: Control, r: Rect2, card: Dictionary, f: float, burst: float) -> void:
	var rar := int(card.rarity)
	var rc: Color = Skins.RARITY_COLORS[rar]
	var sx := absf(cos(f * PI))
	var showing_face := f >= 0.5
	var cr := Rect2(r.position.x + r.size.x * (1.0 - sx) * 0.5, r.position.y, r.size.x * maxf(sx, 0.02), r.size.y)
	if showing_face and rar >= 3:
		# rays behind epic / legendary pulls
		var cen := r.get_center()
		for i in 12:
			var a := TAU * i / 12.0 + t * (0.8 if rar == 4 else 0.5)
			var len := r.size.y * (0.9 + 0.3 * burst)
			c.draw_colored_polygon(PackedVector2Array([cen, cen + Vector2.RIGHT.rotated(a - 0.07) * len, cen + Vector2.RIGHT.rotated(a + 0.07) * len]), Color(rc, 0.12))
	if showing_face and burst > 0.0:
		for k in 3:
			c.draw_arc(r.get_center(), r.size.y * (0.4 + (1.0 - burst) * (0.6 + k * 0.3)), 0, TAU, 48, Color(rc, burst * 0.5), 3.0, true)
	if not showing_face:
		var pack: Dictionary = Skins.PACKS[pack_i]
		c.draw_rect(cr, Color(0.07, 0.08, 0.1))
		c.draw_rect(cr.grow(-6), (pack.colors[0] as Color).darkened(0.3))
		c.draw_rect(cr, pack.colors[1], false, 3.0)
		if sx > 0.3:
			hud._text(c, Vector2(cr.position.x, cr.get_center().y + 14), "?", 46, Color(pack.colors[1], 0.9), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, true)
		return
	# face
	c.draw_rect(cr, Color(0.04, 0.045, 0.055))
	c.draw_rect(Rect2(cr.position, Vector2(cr.size.x, 30)), Color(rc, 0.85))
	if sx < 0.35:
		c.draw_rect(cr, rc, false, 3.0)
		return
	hud._text(c, Vector2(cr.position.x, cr.position.y + 21), Skins.RARITY_NAMES[rar], 13, Color(0.03, 0.03, 0.04), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, true)
	_draw_swatch(c, Rect2(cr.position + Vector2(12, 42), Vector2(cr.size.x - 24, cr.size.y * 0.32)), String(card.finish))
	var ty := cr.position.y + 50 + cr.size.y * 0.32
	hud._text(c, Vector2(cr.position.x, ty + 14), Skins.weapon_name(String(card.weapon)), 16, hud.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, true)
	hud._text(c, Vector2(cr.position.x, ty + 36), Skins.finish_name(String(card.finish)).to_upper(), 14, rc, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, true)
	if bool(card.new):
		c.draw_rect(Rect2(cr.position.x + 10, cr.end.y - 36, cr.size.x - 20, 24), Color(hud.ACCENT, 0.2))
		hud._text(c, Vector2(cr.position.x, cr.end.y - 18), "NEW!", 14, hud.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, true)
	else:
		hud._text(c, Vector2(cr.position.x, cr.end.y - 18), "DUPLICATE  +%d CR" % int(card.refund), 11, hud.WARN, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, true)
	c.draw_rect(cr, rc, false, 3.0 + (2.0 if rar >= 3 else 0.0))


func _draw_reveal(c: Control, vp: Vector2) -> void:
	var pr := _preview_rect(vp, 120, vp.y * 0.34)
	if focus_card >= 0:
		var fc: Dictionary = cards[focus_card]
		var rc: Color = Skins.RARITY_COLORS[int(fc.rarity)]
		c.draw_rect(pr, Color(rc, 0.05))
		hud._brackets(c, pr, 18.0, Color(rc, 0.6), 2.0)
		c.draw_texture_rect(_sv.get_texture(), pr, false)
		hud._text(c, Vector2(pr.position.x + 16, pr.position.y + 30), "%s  |  %s" % [Skins.weapon_name(String(fc.weapon)), Skins.finish_name(String(fc.finish)).to_upper()], 20, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		hud._text(c, Vector2(pr.position.x + 16, pr.position.y + 50), Skins.RARITY_NAMES[int(fc.rarity)], 13, rc, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_card_rects.clear()
	var cw := minf(180.0, vp.x * 0.13)
	var ch := cw * 1.45
	var gap := 22.0
	var total := cw * cards.size() + gap * (cards.size() - 1)
	var y := pr.end.y + 30
	for i in cards.size():
		var r := Rect2(vp.x * 0.5 - total * 0.5 + i * (cw + gap), y, cw, ch)
		if i == focus_card:
			r.position.y -= 10
		if i == flipped and flipped < cards.size():
			r.position.y -= 6.0 + 4.0 * sin(t * 6.0)   # next card to flip bobs
		_card_rects.append(r)
		_draw_card(c, r, cards[i], _face_t(i), float(burst_t[i]))
	var prompt := ""
	if flipped < cards.size():
		prompt = "Space / Enter / click  ·  FLIP NEXT   ·   R  reveal all   (%d LEFT)" % (cards.size() - flipped)
	else:
		var new_n := 0
		var refund := 0
		for cd in cards:
			if bool(cd.new):
				new_n += 1
			refund += int(cd.refund)
		hud._text(c, Vector2(0, y + ch + 34), "%d NEW SKIN%s   ·   DUPLICATES REFUNDED  +%d CR" % [new_n, "" if new_n == 1 else "S", refund], 15, hud.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
		var pk: Dictionary = Skins.PACKS[pack_i]
		prompt = "Enter  ·  OPEN ANOTHER (CR %s)   ·   hover a card to inspect   ·   Esc  back" % _thousands(int(pk.price))
	hud._text(c, Vector2(0, vp.y - 30), prompt, 13, hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


## Card flip progress mapped to 0..1 (0 = back, 1 = face).
func _face_t(i: int) -> float:
	return float(flip_t[i])


# ---------------------------------------------------------------- collection

func _draw_collection(c: Control, vp: Vector2) -> void:
	var weapons := Skins.weapon_ids()
	var finishes := Skins.FINISHES.size()
	_wlist_rects.clear()
	var y := 170.0
	for i in weapons.size():
		var id: String = weapons[i]
		var r := Rect2(60, y - 20, 250, 30)
		_wlist_rects.append(r)
		var sel := i == coll_weapon
		if sel:
			c.draw_rect(r, Color(hud.RED, 0.22))
			hud._brackets(c, r, 8.0, hud.RED, 2.0)
		hud._text(c, Vector2(r.position.x + 12, y), Skins.weapon_name(id), 14, hud.TEXT if sel else hud.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		hud._text(c, Vector2(r.position.x, y), "%d / %d" % [Collection.owned_for(id), finishes], 12, hud.ACCENT if Collection.owned_for(id) > 0 else hud.DIM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12)
		y += 34.0
	var wid := _coll_weapon_id()
	var tiles := _tiles()
	var gx := 340.0
	var cols := 5
	var tw := minf((vp.x * 0.58 - gx * 0.0) / cols - 10.0, 170.0)
	var th := 78.0
	var pr := Rect2(gx, 150, tw * cols + 10 * (cols - 1), vp.y * 0.24)
	c.draw_rect(pr, Color(0.06, 0.07, 0.08, 0.7))
	c.draw_texture_rect(_sv.get_texture(), pr, false)
	var cur: String = tiles[coll_tile]
	var cur_r := Skins.rarity_of(cur)
	hud._text(c, pr.position + Vector2(14, 28), "%s  |  %s" % [Skins.weapon_name(wid), Skins.finish_name(cur).to_upper() if cur != "" else "FACTORY"], 18, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	if cur != "":
		hud._text(c, pr.position + Vector2(14, 48), Skins.RARITY_NAMES[cur_r] + ("" if Collection.has_skin(wid, cur) else "   ·   LOCKED (PREVIEW)"), 12,
				Skins.RARITY_COLORS[cur_r], HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_tile_rects.clear()
	var ty := pr.end.y + 18
	var eq := Collection.skin_for(wid)
	for i in tiles.size():
		var f: String = tiles[i]
		var col_i := i % cols
		var row_i := i / cols
		var r := Rect2(gx + col_i * (tw + 10), ty + row_i * (th + 10), tw, th)
		_tile_rects.append(r)
		var have := Collection.has_skin(wid, f)
		var rar := Skins.rarity_of(f)
		var rc: Color = Skins.RARITY_COLORS[rar] if f != "" else hud.DIM
		c.draw_rect(r, Color(0.05, 0.06, 0.07, 0.9))
		if have:
			_draw_swatch(c, Rect2(r.position + Vector2(6, 6), Vector2(r.size.x - 12, 30)), f)
		else:
			c.draw_rect(Rect2(r.position + Vector2(6, 6), Vector2(r.size.x - 12, 30)), Color(0.1, 0.11, 0.12))
			hud._text(c, Vector2(r.position.x, r.position.y + 28), "LOCKED", 11, Color(rc, 0.45), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
		var label := Skins.finish_name(f).to_upper() if f != "" else "FACTORY"
		hud._text(c, Vector2(r.position.x + 6, r.position.y + 54), label, 11, rc if have else Color(rc, 0.5), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12, true)
		var cnt := Collection.count(wid, f)
		if f != "" and cnt > 1:
			hud._text(c, Vector2(r.position.x, r.position.y + 54), "x%d" % cnt, 10, hud.DIM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6)
		if f == eq:
			c.draw_rect(Rect2(r.position.x, r.end.y - 16, r.size.x, 16), Color(hud.ACCENT, 0.3))
			hud._text(c, Vector2(r.position.x, r.end.y - 4), "EQUIPPED", 10, hud.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
		var sel := i == coll_tile
		c.draw_rect(r, rc if (have or sel) else Color(rc, 0.3), false, 3.0 if sel else 1.5)
		if sel:
			hud._brackets(c, r.grow(4), 8.0, hud.RED, 2.0)
	hud._text(c, Vector2(0, vp.y - 30), "W/S gun   ·   A/D skin   ·   Enter / click equip   ·   Q/E or Tab  packs   ·   Esc back", 12, hud.DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
