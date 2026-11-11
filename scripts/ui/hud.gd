extends CanvasLayer
## Tactical HUD: title screen with logo + menu, mission briefing, compass,
## radar minimap (spotted / firing hostiles), weapon & health readouts,
## reticle (top-down and first person), awareness markers, call-out feed,
## animation debug panel + blend-space widget (F1), pause and debrief.

const LOGO_PATH := "res://assets/logo.png"
const Gunsmith = preload("res://scripts/ui/gunsmith.gd")
const Armory = preload("res://scripts/ui/armory.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const WData = preload("res://scripts/weapons/weapon_data.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const PAUSE_ITEMS := ["RESUME", "SETTINGS", "RESTART", "QUIT TO TITLE"]
const Campaign = preload("res://scripts/modes/campaign.gd")
const MODES := ["ch1", "ch2", "zombie"]
const Net = preload("res://scripts/net/net.gd")
const PlayerScript = preload("res://scripts/characters/player.gd")
const ARROW_ITEMS := [3, 4, 5, 6, 7]

const Retro = preload("res://scripts/ui/retro.gd")
const ACCENT := Retro.ACCENT
const TEXT := Retro.TEXT
const DIM := Retro.DIM
const WARN := Retro.WARN
const DANGER := Retro.DANGER
const RED := Retro.RED

var main: Node
var player
var camera_rig
var debug_visible := false
var hit_marker := 0.0
var hit_kill := false
var hit_head := false
var damage_flash := 0.0
var feed: Array = []
var help_timer := 0.0
var blend_trail: Array = []
var title := true
var menu_index := 0
var briefing_t := -1.0
var settings_open := false
var settings_row := 0
var settings_tab := 0
var _settings_scroll := 0
var _tab_rects: Array = []
var _settings_idx: Array = []
var pause_index := 0
var _dmg_dirs: Array = []
var _heartbeat := 0.0
var _settings_rects: Array = []
var _pause_rects: Array = []
static var last_menu_index := 0
var _banner := ""
var _banner_t := 0.0
## multiplayer menu (title) and non-pausing in-game menu
var mp_open := false
var mp_row := 0
var mp_pause := false
var _mp_rects: Array = []
var _mp_coop_mode := "ch1"
var _mp_port_text := ""
## host online through Tailscale Funnel (WebSocket) instead of direct UDP
static var mp_online := false

var _fps := 60.0
var _vignette: GradientTexture2D
var _logo: Texture2D
var _font: Font
var _font_bold: Font
var _font_display: Font
var _spotted: Dictionary = {}
var _spot_timer := 0.0
var _sweep := 0.0
var _menu_rects: Array = []
var _time := 0.0


class Overlay extends Control:
	var hud
	func _draw() -> void:
		hud._draw_overlay(self)


var overlay: Overlay
var gunsmith: Gunsmith
var armory: Armory


func setup(p_main: Node) -> void:
	main = p_main
	player = main.player
	camera_rig = main.camera_rig
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = Overlay.new()
	overlay.hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.05, 0.5)
	_vignette.width = 256
	_vignette.height = 256

	Retro.install()
	_font = Retro.body()
	_font_bold = Retro.bold()
	_font_display = Retro.display()
	_logo = _load_logo()
	gunsmith = Gunsmith.new()
	add_child(gunsmith)
	gunsmith.setup(self)
	armory = Armory.new()
	add_child(armory)
	armory.setup(self)

	menu_index = last_menu_index
	if not Profile.signed_in():
		_auth_user = Profile.last_user()
		_auth_row = 1 if _auth_user != "" else 0
		if Profile.accounts().is_empty():
			_auth_msg = "NO ACCOUNTS YET  ·  PICK A USERNAME + %d-DIGIT PASSWORD, THEN CREATE ACCOUNT" % Profile.PIN_LEN
	if Net.pending_join != "" and not Net.active:
		# launched from a clicked invite link: straight to joining
		var inv := Net.parse_invite(Net.pending_join)
		Net.pending_join = ""
		if not inv.is_empty():
			_mp_open()
			Net.join_ip = String(inv[0])
			_mp_port_text = str(int(inv[1]))
			_mp_save()
			Net.join(Net.join_ip, Net.port)
			mp_row = 3
	if main.quick_restart:
		main.quick_restart = false
		call_deferred("_deploy")
		return
	# title screen: the world is visible but frozen until DEPLOY
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _load_logo() -> Texture2D:
	if ResourceLoader.exists(LOGO_PATH):
		var t = load(LOGO_PATH)
		if t is Texture2D:
			return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(LOGO_PATH))
	if img and not img.is_empty():
		return ImageTexture.create_from_image(img)
	return null


# ================================================================ events

func on_hit(killed: bool, headshot: bool) -> void:
	hit_marker = 0.25
	hit_kill = killed
	hit_head = headshot
	var ear: Vector3 = player.global_position + Vector3.UP * 1.6
	if killed:
		Sfx.play(player, "kill", ear, -6.0 if not headshot else -2.0, 0.0)
	else:
		Sfx.play(player, "hitmarker", ear, -10.0, 0.05)


func on_player_damaged(amount: float, attacker: Node = null) -> void:
	if attacker is Node3D and attacker != player:
		_dmg_dirs.append({"pos": (attacker as Node3D).global_position, "t": 1.6})
		if _dmg_dirs.size() > 6:
			_dmg_dirs.pop_front()
	damage_flash = clampf(damage_flash + amount / 35.0, 0.0, 1.0)
	if player.using_pad:
		Input.start_joy_vibration(0, 0.5, 0.8, 0.2)


func wave_banner(text: String) -> void:
	_banner = text
	_banner_t = 3.0


func ping_enemy(e: Node) -> void:
	_spotted[e] = maxf(_spotted.get(e, 0.0), 1.6)


func add_feed(text: String, color: Color = TEXT) -> void:
	feed.push_front({"text": text, "t": 5.0, "color": color})
	if feed.size() > 5:
		feed.pop_back()


func _menu_items() -> Array:
	return [
		"DEPLOY",
		"MULTIPLAYER  ·  CO-OP / PVP",
		"ARMORY  ·  SKIN PACKS   CR " + str(Collection.credits),
		"MODE:  " + _mode_label(main.mode),
		"LOADOUT:  " + Loadout.class_label() + "  ·  GUNSMITH",
		"VIEW:  " + ("FIRST PERSON" if main.start_first_person else "TACTICAL TOP-DOWN"),
		"GRAPHICS:  " + Settings.PRESETS[main.quality],
		"MUSIC:  " + ("OFF" if main.music.muted else "ON"),
		"SETTINGS",
		"ACCOUNT:  " + Profile.current.to_upper() + "  ·  SIGN OUT",
		"QUIT",
	]


func _mode_label(m: String) -> String:
	if m == "zombie":
		return "ZOMBIE SURVIVAL"
	var inf := Campaign.chapter_info(m)
	var lbl := "CHAPTER %d  %s" % [int(inf.num), String(inf.name)]
	if Campaign.completed.has(m):
		lbl += "  [" + String(Campaign.completed[m]) + "]"
	return lbl


func _menu_activate(i: int, dir: int = 0) -> void:
	match i:
		0:
			_deploy()
		1:
			_mp_open()
		2:
			armory.open()
		3:
			last_menu_index = 3
			main.set_mode(MODES[posmod(MODES.find(main.mode) + (dir if dir != 0 else 1), MODES.size())])
		4:
			if dir == 0:
				gunsmith.open()
			else:
				Loadout.cycle_class(dir)
				Loadout.save()
		5:
			main.start_first_person = not main.start_first_person
		6:
			main.set_quality(posmod(main.quality + (dir if dir != 0 else 1), 3))
		7:
			main.music.toggle_mute()
		8:
			settings_open = true
			settings_row = 0
		9:
			_sign_out()
		10:
			print("[quit] title menu QUIT (menu_index=%d)" % menu_index)
			get_tree().quit()


func _deploy() -> void:
	title = false
	briefing_t = 0.0
	help_timer = 18.0
	get_tree().paused = false
	player.set_first_person(main.start_first_person)
	if not main.start_first_person:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	main.on_deploy()


func _unhandled_input(event: InputEvent) -> void:
	if settings_open:
		_settings_input(event)
		return
	if _needs_auth():
		_auth_input(event)
		return
	if title and gunsmith.is_open:
		if gunsmith.handle(event):
			gunsmith.close()
		return
	if title and mp_open:
		_mp_input(event)
		return
	if title and armory.is_open:
		if armory.handle(event):
			armory.close()
			# equipped skins show up on the operator straight away
			player.apply_loadout()
		return
	if title:
		var items := _menu_items()
		if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
			menu_index = posmod(menu_index - 1, items.size())
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
			menu_index = posmod(menu_index + 1, items.size())
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
			if menu_index in ARROW_ITEMS:
				_menu_activate(menu_index, -1)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
			if menu_index in ARROW_ITEMS:
				_menu_activate(menu_index, 1)
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("vault"):
			_menu_activate(menu_index)
		elif event is InputEventMouseMotion:
			for i in _menu_rects.size():
				if (_menu_rects[i] as Rect2).has_point(event.position):
					menu_index = i
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in _menu_rects.size():
				if (_menu_rects[i] as Rect2).has_point(event.position):
					menu_index = i
					_menu_activate(i)
		return

	if (get_tree().paused or mp_pause) and not main.game_over:
		_pause_input(event)
		return
	if event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible
	elif event.is_action_pressed("quality"):
		main.set_quality(posmod(main.quality + 1, 3))
		add_feed("GRAPHICS  ·  " + Settings.PRESETS[main.quality], DIM)
	elif event.is_action_pressed("music"):
		main.music.toggle_mute()
		add_feed("MUSIC  ·  " + ("OFF" if main.music.muted else "ON"), DIM)
	elif event.is_action_pressed("pause") and not main.game_over:
		pause_index = 0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if Net.active:
			mp_pause = true   # the session keeps running for everyone else
		else:
			get_tree().paused = true
	elif event.is_action_pressed("pause") and main.game_over and Net.active:
		main.leave_to_title()
	elif event.is_action_pressed("restart") and main.game_over:
		if Net.active and not Net.is_server():
			return   # the host decides what comes next
		if main.victory and main.mode == "ch1":
			main.continue_to("ch2")
		elif main.victory and main.mode == "ch2":
			main.set_mode("ch1")
		else:
			main.restart()


func _process(delta: float) -> void:
	_time += delta
	PlayerScript.input_blocked = Net.active and (mp_pause or settings_open)
	hit_marker = maxf(hit_marker - delta, 0.0)
	damage_flash = maxf(damage_flash - delta * 0.9, 0.0)
	help_timer -= delta
	_banner_t = maxf(_banner_t - delta, 0.0)
	for d in _dmg_dirs:
		d.t -= delta
	_dmg_dirs = _dmg_dirs.filter(func(d): return d.t > 0.0)
	if not title and not get_tree().paused and player and not player.is_dead and player.health < 30.0:
		_heartbeat -= delta
		if _heartbeat <= 0.0:
			_heartbeat = lerpf(0.55, 1.05, player.health / 30.0)
			Sfx.play(player, "heartbeat", player.global_position + Vector3.UP * 1.6, -2.0, 0.0)
	_sweep = fmod(_sweep + delta * 1.6, TAU)
	if briefing_t >= 0.0:
		briefing_t += delta
		if briefing_t > 6.0:
			briefing_t = -1.0
	_fps = lerpf(_fps, 1.0 / maxf(delta, 0.0001), 0.05)
	for f in feed:
		f.t -= delta
	feed = feed.filter(func(f): return f.t > 0.0)
	if player and player.rig:
		blend_trail.push_front(player.rig.local_move)
		if blend_trail.size() > 24:
			blend_trail.pop_back()
	if not title and not get_tree().paused:
		_update_spotting(delta)
	overlay.queue_redraw()


## Marks hostiles the operator has line of sight to (shown on the radar).
func _update_spotting(delta: float) -> void:
	for e in _spotted.keys():
		_spotted[e] -= delta
		if _spotted[e] <= 0.0 or not is_instance_valid(e) or e.is_dead:
			_spotted.erase(e)
	_spot_timer -= delta
	if _spot_timer > 0.0 or player.is_dead:
		return
	_spot_timer = 0.2
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var eye: Vector3 = player.global_position + player.peek_offset() + Vector3(0, player.head_height(), 0)
	for e in main.enemies:
		if e.is_dead or e.global_position.distance_to(player.global_position) > 30.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, e.global_position + Vector3(0, e.chest_height(), 0), 1)
		if space.intersect_ray(q).is_empty():
			_spotted[e] = 2.0


# ================================================================ drawing helpers

func _text(c: Control, pos: Vector2, s: String, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, bold: bool = false) -> void:
	# big bold headlines use the condensed display weight
	if bold and size >= 22 and _has_letters(s):
		var ds := int(size * 0.95)
		c.draw_string_outline(_font_display, pos + Vector2(2, 2), s, align, width, ds, 4, Color(0, 0, 0, color.a * 0.55))
		c.draw_string(_font_display, pos, s, align, width, ds, color)
		return
	c.draw_string(_font_bold if bold else _font, pos, s, align, width, size + 1, color)


static var _letters_re: RegEx


func _has_letters(s: String) -> bool:
	if _letters_re == null:
		_letters_re = RegEx.create_from_string("[A-Za-z]")
	return _letters_re.search(s) != null


func _brackets(c: Control, r: Rect2, arm: float, col: Color, w: float = 2.0) -> void:
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		c.draw_line(corner, corner + Vector2(arm * sx, 0), col, w)
		c.draw_line(corner, corner + Vector2(0, arm * sy), col, w)


func _draw_logo(c: Control, center: Vector2, width: float, alpha: float = 1.0) -> void:
	if _logo == null:
		_text(c, center + Vector2(-width * 0.5, 20), "TECTICA", int(width / 5.0), Color(TEXT, alpha), HORIZONTAL_ALIGNMENT_CENTER, width, true)
		return
	var sz := Vector2(width, width * float(_logo.get_height()) / float(_logo.get_width()))
	c.draw_texture_rect(_logo, Rect2(center - sz * 0.5, sz), false, Color(1, 1, 1, alpha))


# ================================================================ main draw

func _draw_overlay(c: Control) -> void:
	if player == null:
		return
	var vp := c.size

	# cinematic vignette + damage / low-health pulse
	c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, vp), false, Color(0, 0, 0, 0.55))
	var low: float = clampf(1.0 - player.health / 40.0, 0.0, 1.0) * (0.55 + 0.25 * sin(_time * 6.0))
	var v := maxf(damage_flash, low if not player.is_dead else 0.0)
	if v > 0.01:
		c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, vp), false, Color(0.6, 0.0, 0.0, v * 0.85))

	if title:
		_draw_title(c, vp)
		return

	# Quiet backing plates keep telemetry readable over bright surfaces.
	for panel in [Rect2(vp.x - 344, 24, 328, 126), Rect2(16, vp.y - 100, 224, 82)]:
		c.draw_rect(panel, Color(0.025, 0.045, 0.055, 0.78))
		c.draw_rect(panel, Color(0.42, 0.66, 0.69, 0.24), false, 1.0)
		c.draw_rect(Rect2(panel.position, Vector2(3, panel.size.y)), Color(ACCENT, 0.8))
	_draw_enemy_markers(c)
	_brackets(c, Rect2(Vector2(14, 14), vp - Vector2(28, 28)), 26.0, Color(TEXT, 0.25), 1.5)
	_draw_compass(c, vp)
	_draw_radar(c, Vector2(vp.x - 128, vp.y - 140), 100.0)
	if bool(Settings.v.show_fps):
		_draw_fps(c, vp)
	_draw_threats(c, vp)

	# ---- weapon panel (top-right)
	var w = player.current_weapon()
	var ammo_col := TEXT if w.ammo > int(w.stats.mag) * 0.25 else WARN
	if w.ammo == 0:
		ammo_col = DANGER
	var wname := String(w.stats.name)
	if w.skin != "":
		wname += "  ·  " + String(preload("res://scripts/skins/skins.gd").finish_name(w.skin)).to_upper()
	_text(c, Vector2(vp.x - 330, 46), wname, 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
	_text(c, Vector2(vp.x - 330, 86), "%d" % w.ammo, 42, ammo_col, HORIZONTAL_ALIGNMENT_RIGHT, 230, true)
	_text(c, Vector2(vp.x - 95, 86), "/ %d" % w.reserve, 18, DIM)
	var pips := int(w.stats.mag)
	if pips > 45:
		c.draw_rect(Rect2(vp.x - 250, 96, 220, 6), Color(DIM, 0.25))
		c.draw_rect(Rect2(vp.x - 250, 96, 220.0 * w.ammo / pips, 6), TEXT)
	else:
		var pip_w := minf(220.0 / pips, 7.0)
		for i in pips:
			var x: float = vp.x - 30 - (pips - i) * pip_w
			c.draw_rect(Rect2(x, 96, pip_w - 2.0, 6), TEXT if i < w.ammo else Color(DIM, 0.25))
	var mode := ("AUTO" if bool(w.stats.auto) else ("BOLT" if w.stats.cycle == "bolt" else ("PUMP" if w.stats.cycle == "pump" else "SEMI")))
	var att: Dictionary = w.attachments
	for slot in ["optic", "muzzle", "underbarrel"]:
		if att.get(slot, "none") not in ["none", "iron", "integral"]:
			mode += "  ·  " + String(WData.ATTACHMENTS[slot][att[slot]].name).to_upper()
	if bool(w.stats.suppressed) and att.get("muzzle") != "suppressor":
		mode += "  ·  SUPPRESSED"
	_text(c, Vector2(vp.x - 330, 120), mode, 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	if player.reload_timer > 0.0:
		_text(c, Vector2(vp.x - 330, 140), "TACTICAL RELOAD" if player.reload_tactical else "RELOADING", 12, WARN, HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
	elif w.ammo == 0:
		_text(c, Vector2(vp.x - 330, 140), "EMPTY  ·  RELOAD", 12, DANGER, HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
	_text(c, Vector2(vp.x - 330, 160), "FRAG  x%d   [G]" % player.grenades, 12, WARN if player.grenades > 0 else Color(DIM, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
	for i in feed.size():
		var f = feed[i]
		var col: Color = f.color
		col.a = clampf(f.t, 0.0, 1.0)
		_text(c, Vector2(vp.x - 330, 194 + i * 22), f.text, 14, col, HORIZONTAL_ALIGNMENT_RIGHT, 300, true)

	# ---- objective (top-centre, under compass)
	var alive: int = main.enemies_alive()
	var total: int = main.enemies.size()
	var dir_node = main.director
	if main.mode == "pvp":
		var mine: Array = main.pvp_scores.get(Net.my_id(), ["", 0, 0])
		var lead: int = main._pvp_leader()
		var lead_s := ""
		if lead > 0 and main.pvp_scores.has(lead):
			lead_s = "   ·   LEADER  %s  %d" % [main.pvp_scores[lead][0], int(main.pvp_scores[lead][1])]
		var tl := maxf(main.pvp_time_left, 0.0)
		_text(c, Vector2(0, 92), "DEATHMATCH  ·  FIRST TO %d   ·   YOU  %d / %d%s" % [main.PVP_KILL_LIMIT, int(mine[1]), int(mine[2]), lead_s], 14, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
		_text(c, Vector2(0, 110), "%d:%02d LEFT   ·   %s" % [int(tl) / 60, int(tl) % 60, main.tod.clock_string()], 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	elif dir_node != null:
		var line := "WAVE %d   ·   INFECTED %d   ·   SCORE %d" % [dir_node.wave, dir_node.remaining(), dir_node.score]
		if not dir_node.active:
			line = "NEXT WAVE IN %d   ·   SCORE %d" % [int(ceil(dir_node.timer)), dir_node.score]
		_text(c, Vector2(0, 92), line, 14, WARN if not dir_node.active else TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
		_text(c, Vector2(0, 110), "KILLS %d   ·   %s   ·   T+ %s" % [dir_node.kills, main.tod.clock_string(), main.time_string()], 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	else:
		var cp = main.campaign
		if cp != null:
			var ci: Dictionary = cp.info()
			_text(c, Vector2(0, 92), "> " + cp.objective_text(), 14, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
			_text(c, Vector2(0, 110), "CH.%d %s   ·   %s   ·   T+ %s" % [int(ci.num), String(ci.name), main.tod.clock_string(), main.time_string()],
					11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
			_draw_waypoint(c, vp)
			_draw_interact(c, vp)
	if _banner_t > 0.0:
		var ba := clampf(_banner_t, 0.0, 1.0) * clampf((3.0 - _banner_t) * 4.0, 0.0, 1.0)
		_text(c, Vector2(0, vp.y * 0.3), _banner, 48, Color(RED, ba), HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)

	# ---- health + stance (bottom-left, under radar)
	var hp: float = clampf(player.health / player.max_health, 0.0, 1.0)
	var hb := Rect2(26, vp.y - 62, 184, 8)
	_text(c, Vector2(26, vp.y - 70), "HP  %d" % int(ceil(player.health)), 13, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	c.draw_rect(hb, Color(0, 0, 0, 0.5))
	var hcol := ACCENT if hp > 0.5 else (WARN if hp > 0.25 else DANGER)
	c.draw_rect(Rect2(hb.position, Vector2(hb.size.x * hp, hb.size.y)), hcol)
	for i in range(1, 10):
		var x := hb.position.x + hb.size.x * i / 10.0
		c.draw_line(Vector2(x, hb.position.y), Vector2(x, hb.end.y), Color(0, 0, 0, 0.55), 1.0)
	var stance := "CROUCHED" if player.crouching else "STANDING"
	if player.sprinting:
		stance += "  ·  SPRINT"
	if player.kicking:
		stance = "JUMP KICK"
	if player.vaulting:
		stance = "VAULT"
	if absf(player.rig.lean_amt) > 0.4:
		stance += "  ·  PEEK " + ("R" if player.rig.lean_amt > 0.0 else "L")
	stance += "  ·  " + ("FPV" if player.first_person else "TOP-DOWN")
	if player.flashlight_on:
		stance += "  ·  LIGHT"
	_text(c, Vector2(26, vp.y - 34), stance, 11, DIM)

	if debug_visible:
		_draw_debug(c)
		_draw_blend_space(c, Rect2(24, vp.y - 260, 230, 150), player.rig)

	if not player.is_dead:
		_draw_reticle(c)

	if briefing_t >= 0.0:
		_draw_briefing(c, vp)
	elif help_timer > 0.0:
		var a := clampf(help_timer / 2.0, 0.0, 1.0)
		var help := "WASD move  ·  Mouse aim  ·  LMB fire  ·  RMB ADS  ·  Shift sprint  ·  V jump-kick (sprinting)  ·  Space vault / jump  ·  Q/E peek  ·  C crouch  ·  R reload  ·  G frag  ·  T flashlight  ·  F interact / first person  ·  Z/V rotate  ·  M music"
		if player.using_pad:
			help = "L-stick move  ·  R-stick aim  ·  RT fire  ·  LT ADS  ·  L3 sprint  ·  A vault  ·  LB/RB peek  ·  B crouch  ·  X reload / interact  ·  Y weapon  ·  Back flashlight  ·  R3 first person  ·  Start pause"
		_text(c, Vector2(0, vp.y - 26), help, 12, Color(TEXT, a * 0.75), HORIZONTAL_ALIGNMENT_CENTER, vp.x)

	if Net.active and not main.game_over:
		_draw_squad(c, vp)
		if player.is_dead:
			var msg := "DOWN  ·  WAITING FOR A TEAMMATE"
			if main.respawn_t > 0.0:
				msg = "RESPAWN IN %d" % int(ceil(main.respawn_t))
			elif main.director != null:
				msg = "DOWN  ·  BACK UP WHEN THE WAVE IS CLEARED"
			_text(c, Vector2(0, vp.y * 0.62), msg, 26, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	if settings_open:
		_draw_settings(c, vp)
	elif (get_tree().paused or mp_pause) and not main.game_over:
		_draw_pause(c, vp)
	elif main.game_over and main.mode == "pvp":
		_draw_pvp_over(c, vp)
	elif main.game_over:
		var won: bool = main.victory
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.45))
		_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.28), minf(vp.x * 0.36, 560.0), 0.9)
		var acc: float = 0.0 if player.shots_fired == 0 else 100.0 * player.shots_hit / player.shots_fired
		if main.director != null:
			var dn = main.director
			var survived: int = dn.wave - 1 if dn.active else dn.wave
			_text(c, Vector2(0, vp.y * 0.5), "YOU SURVIVED %d WAVE%s" % [survived, "" if survived == 1 else "S"], 44, DANGER, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
			_text(c, Vector2(0, vp.y * 0.5 + 40), "KILLS %d   ·   HEADSHOTS %d   ·   ACCURACY %d%%   ·   SCORE %d" % [dn.kills, dn.headshots, int(acc), dn.score],
					15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
			_text(c, Vector2(0, vp.y * 0.5 + 92), "BEST  ·  WAVE %d  ·  SCORE %d" % [dn.best_wave, dn.best_score], 12, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		else:
			var head := "OPERATOR DOWN"
			if won:
				head = "CAMPAIGN COMPLETE" if main.mode == "ch2" else "CHAPTER 1 COMPLETE"
			_text(c, Vector2(0, vp.y * 0.5), head, 44, ACCENT if won else DANGER, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
			_text(c, Vector2(0, vp.y * 0.5 + 40), "KILLS %d    ·    ACCURACY %d%%    ·    TIME %s" % [total - alive, int(acc), main.time_string()],
					15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
			if won and main.grade != "":
				var gcol := ACCENT if main.grade in ["S", "A"] else WARN
				_text(c, Vector2(0, vp.y * 0.5 + 112), "GRADE  " + main.grade, 40, gcol, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
				_text(c, Vector2(0, vp.y * 0.5 + 136), "SCORE %d   ·   HEADSHOTS %d   ·   DAMAGE TAKEN %d   ·   BEST %s" % [main.mission_score, main.headshot_kills, int(main.damage_taken), main.best_grade],
						12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		var prompt := "Enter / A to redeploy"
		if won and main.mode == "ch1":
			prompt = "Enter / A  ·  CONTINUE TO CHAPTER 2: NIGHTFALL"
		elif won and main.mode == "ch2":
			prompt = "Enter / A  ·  BACK TO CHAPTER 1"
		if Net.active:
			if not Net.is_server():
				prompt = "WAITING FOR THE HOST   ·   Esc LEAVE"
			elif won and main.mode == "ch1":
				prompt = "Enter  ·  CONTINUE TO CHAPTER 2 TOGETHER   ·   Esc LEAVE"
			elif won and main.mode == "ch2":
				prompt = "Enter  ·  BACK TO CHAPTER 1 TOGETHER   ·   Esc LEAVE"
			else:
				prompt = "Enter  ·  RESTART FOR EVERYONE   ·   Esc LEAVE"
		_text(c, Vector2(0, vp.y * 0.5 + 70), prompt, 14, WARN if won else DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


func _draw_title(c: Control, vp: Vector2) -> void:
	if _needs_auth():
		_draw_auth(c, vp)
		return
	if settings_open:
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.025, 0.03, 0.85))
		_draw_settings(c, vp)
		return
	if gunsmith.is_open:
		gunsmith.draw(c, vp)
		return
	if mp_open:
		_draw_mp(c, vp)
		return
	if armory.is_open:
		armory.draw(c, vp)
		return
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.028, 0.04, 0.60))
	var y := 0.0
	while y < vp.y:
		c.draw_line(Vector2(0, y), Vector2(vp.x, y), Color(0, 0, 0, 0.05), 1.0)
		y += 3.0
	var pulse := 0.92 + 0.08 * sin(_time * 2.0)
	var logo_w := minf(vp.x * 0.62, 980.0)
	_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.3), logo_w, pulse)
	var sub := "ZOMBIE SURVIVAL  //  OUTBREAK"
	if main.is_campaign():
		var ci := Campaign.chapter_info(main.mode)
		sub = "CHAPTER %d  //  %s" % [int(ci.num), String(ci.name)]
	_text(c, Vector2(0, vp.y * 0.3 + logo_w * 0.2), sub, 15, Color(RED, 0.95), HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	if main.is_zombie_mode() and main.director.best_wave > 0:
		_text(c, Vector2(0, vp.y * 0.3 + logo_w * 0.2 + 22), "BEST  ·  WAVE %d  ·  SCORE %d" % [main.director.best_wave, main.director.best_score], 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)

	var items := _menu_items()
	_menu_rects.clear()
	var top := vp.y * 0.54
	for i in items.size():
		var r := Rect2(vp.x * 0.5 - 170, top + i * 46 - 28, 340, 38)
		_menu_rects.append(r)
		var sel := i == menu_index
		if sel:
			c.draw_rect(r, Color(RED, 0.22))
			_brackets(c, r, 10.0, RED, 2.0)
		var label: String = items[i]
		if sel and i in ARROW_ITEMS:
			label = "<  " + label + "  >"
		_text(c, Vector2(r.position.x, r.position.y + 26), label, 18, TEXT if sel else DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	_text(c, Vector2(0, vp.y - 40), "W/S or D-pad select   ·   A/D change   ·   Enter / Space / A confirm", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_brackets(c, Rect2(Vector2(24, 24), vp - Vector2(48, 48)), 40.0, Color(TEXT, 0.3), 1.5)


func _draw_briefing(c: Control, vp: Vector2) -> void:
	var t := briefing_t
	var a := clampf(t / 0.3, 0.0, 1.0) * clampf((6.0 - t) / 0.8, 0.0, 1.0)
	var bar_h := 60.0 * clampf(1.0 - maxf(t - 4.8, 0.0) / 0.8, 0.0, 1.0)
	c.draw_rect(Rect2(0, 0, vp.x, bar_h), Color(0, 0, 0, 0.85))
	c.draw_rect(Rect2(0, vp.y - bar_h, vp.x, bar_h), Color(0, 0, 0, 0.85))
	var lines := [
		["TECTICA  //  ZOMBIE SURVIVAL", RED, 20],
		["LOCATION   PINEWOOD VALLEY - LOGGING CAMP, OVERRUN", TEXT, 14],
		["SITREP     NIGHT IS FALLING. THEY COME OUT OF THE TREES IN WAVES", TEXT, 14],
		["OBJECTIVE  SURVIVE AS LONG AS POSSIBLE", TEXT, 14],
		["INTEL      HEADSHOTS SAVE AMMO - RESUPPLY BETWEEN WAVES  -  [T] FLASHLIGHT", TEXT, 14],
		["ROE        KILL EVERYTHING THAT MOVES", ACCENT, 14],
	] if main.is_zombie_mode() else (_pvp_briefing() if main.mode == "pvp" else _campaign_briefing())
	var chars := int(t * 75.0)
	var y := vp.y * 0.36
	for line in lines:
		var s: String = line[0]
		if chars <= 0:
			break
		var shown := s.substr(0, mini(chars, s.length()))
		chars -= s.length() + 6
		var lc: Color = line[1]
		_text(c, Vector2(70, y), shown, line[2], Color(lc, a * lc.a), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		y += 30.0 if line[2] > 16 else 22.0
	if int(_time * 3.0) % 2 == 0:
		c.draw_rect(Rect2(62, vp.y * 0.36 - 18, 3, 20), Color(RED, a))


func _pvp_briefing() -> Array:
	return [
		["TECTICA  //  DEATHMATCH", RED, 20],
		["LOCATION   PINEWOOD VALLEY", TEXT, 14],
		["OBJECTIVE  FIRST TO %d KILLS  -  10 MINUTES" % main.PVP_KILL_LIMIT, TEXT, 14],
		["INTEL      SHOTS SHOW YOU ON THEIR RADAR  -  BUSHES HIDE YOU", TEXT, 14],
		["ROE        FREE FOR ALL", ACCENT, 14],
	]


func _campaign_briefing() -> Array:
	var ci: Dictionary = Campaign.chapter_info(main.mode)
	var objs: Array = []
	for o in main.campaign.objectives:
		objs.append(String(o.text))
	return [
		["TECTICA  //  CHAPTER %d: %s" % [int(ci.num), String(ci.name)], RED, 20],
		["LOCATION   " + String(ci.location), TEXT, 14],
		["TIME       " + main.tod.clock_string().replace(":", "") + " HRS LOCAL", TEXT, 14],
		["SITREP     " + String(ci.sitrep), TEXT, 14],
		["OBJECTIVE  " + String(objs[0]) + "  >  " + String(objs[1]), TEXT, 14],
		["INTEL      " + String(ci.intel), TEXT, 14],
		["ROE        WEAPONS FREE", ACCENT, 14],
	]


## Objective marker: diamond + distance, clamped to the screen edge.
func _draw_waypoint(c: Control, vp: Vector2) -> void:
	var cp = main.campaign
	var wp = cp.objective_pos()
	if wp == null or player.is_dead:
		return
	var target: Vector3 = (wp as Vector3) + Vector3(0, 1.6, 0)
	var cam: Camera3D = camera_rig.active_camera()
	var dist: float = Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length()
	var sp: Vector2
	var behind := cam.is_position_behind(target)
	if behind:
		var rel := cam.global_transform.affine_inverse() * target
		sp = vp * 0.5 + Vector2(-rel.x, rel.y).normalized() * vp.length()
	else:
		sp = cam.unproject_position(target)
	var margin := 60.0
	var clamped := Vector2(clampf(sp.x, margin, vp.x - margin), clampf(sp.y, margin + 80.0, vp.y - margin - 40.0))
	var edge := behind or clamped.distance_to(sp) > 1.0
	var pulse := 0.75 + 0.25 * sin(_time * 4.0)
	var col := Color(WARN, pulse)
	var d := 9.0
	var poly := PackedVector2Array([clamped + Vector2(0, -d), clamped + Vector2(d, 0), clamped + Vector2(0, d), clamped + Vector2(-d, 0)])
	c.draw_colored_polygon(poly, Color(0, 0, 0, 0.45))
	poly.append(poly[0])
	c.draw_polyline(poly, col, 2.0)
	if edge:
		var dir := (sp - vp * 0.5).normalized()
		c.draw_line(clamped + dir * 12.0, clamped + dir * 22.0, col, 2.0)
	_text(c, clamped + Vector2(-40, 26), "%d m" % int(dist), 12, col, HORIZONTAL_ALIGNMENT_CENTER, 80, true)


## "HOLD [F] ..." prompt with a progress bar while the key is held.
func _draw_interact(c: Control, vp: Vector2) -> void:
	var cp = main.campaign
	if not cp.can_interact():
		return
	var key := "X" if player.using_pad else "F"
	var r := Rect2(vp.x * 0.5 - 150, vp.y * 0.64, 300, 40)
	c.draw_rect(r, Color(0, 0, 0, 0.55))
	_brackets(c, r, 8.0, WARN, 2.0)
	_text(c, Vector2(r.position.x, r.position.y + 18), "HOLD [%s]  %s" % [key, cp.interact_label()], 15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	c.draw_rect(Rect2(r.position.x + 12, r.end.y - 11, r.size.x - 24, 4), Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(r.position.x + 12, r.end.y - 11, (r.size.x - 24) * clampf(cp.hold_progress, 0.0, 1.0), 4), ACCENT)


func _draw_compass(c: Control, vp: Vector2) -> void:
	var width := 440.0
	var cx := vp.x * 0.5
	var y := 46.0
	var heading := fposmod(rad_to_deg(-player.aim_yaw), 360.0)
	var ppd := width / 120.0
	c.draw_rect(Rect2(cx - width * 0.5, y - 26, width, 34), Color(0, 0, 0, 0.3))
	var labels := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
	var start := int(floor((heading - 60.0) / 5.0)) * 5
	for d in range(start, int(heading + 61.0), 5):
		var x := cx + (d - heading) * ppd
		if absf(x - cx) > width * 0.5:
			continue
		var fade := 1.0 - absf(x - cx) / (width * 0.5)
		var dd := posmod(d, 360)
		if labels.has(dd):
			_text(c, Vector2(x - 20, y - 6), labels[dd], 14, Color(RED if dd == 0 else TEXT, fade), HORIZONTAL_ALIGNMENT_CENTER, 40, true)
		elif dd % 15 == 0:
			c.draw_line(Vector2(x, y - 14), Vector2(x, y - 4), Color(TEXT, fade * 0.8), 1.5)
			_text(c, Vector2(x - 20, y + 6), str(dd), 9, Color(DIM, fade * 0.8), HORIZONTAL_ALIGNMENT_CENTER, 40)
		else:
			c.draw_line(Vector2(x, y - 10), Vector2(x, y - 5), Color(DIM, fade * 0.6), 1.0)
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx, y - 18), Vector2(cx - 6, y - 26), Vector2(cx + 6, y - 26)]), RED)
	_text(c, Vector2(cx - 30, y + 22), "%03d" % int(heading), 11, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 60, true)


func _draw_radar(c: Control, center: Vector2, radius: float) -> void:
	var sc := radius / 24.0
	var view_yaw: float = player.aim_yaw if player.first_person else camera_rig.yaw
	var inv := Basis(Vector3.UP, -view_yaw)
	var ppos: Vector3 = player.global_position
	c.draw_circle(center, radius + 3.0, Color(0, 0, 0, 0.55))
	c.draw_circle(center, radius, Color(0.06, 0.09, 0.07, 0.75))
	var circle := PackedVector2Array()
	for i in 40:
		circle.append(center + Vector2.RIGHT.rotated(TAU * i / 40.0) * radius)
	for r in main.level.map_rects:
		var rc: Vector2 = r.c
		var rs: Vector2 = r.s
		if Vector2(rc.x - ppos.x, rc.y - ppos.z).length() > 24.0 + rs.length() * 0.5:
			continue
		var poly := PackedVector2Array()
		var rb := Basis(Vector3.UP, float(r.r))
		var hs := rs * 0.5
		for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var wp := Vector3(rc.x, 0, rc.y) + rb * Vector3(k.x * hs.x, 0, k.y * hs.y)
			var lp := inv * (wp - ppos)
			poly.append(center + Vector2(lp.x, lp.z) * sc)
		for clipped in Geometry2D.intersect_polygons(poly, circle):
			if clipped.size() < 3 or Geometry2D.triangulate_polygon(clipped).is_empty():
				continue
			c.draw_colored_polygon(clipped, Color(0.55, 0.7, 0.55, 0.55) if r.tall else Color(0.5, 0.6, 0.45, 0.3))
	if main.level.has_method("trees_near"):
		for t in main.level.trees_near(ppos, 24.0):
			var lt: Vector3 = inv * (Vector3(t.x, 0, t.y) - ppos)
			var tp := center + Vector2(lt.x, lt.z) * sc
			if tp.distance_to(center) < radius - 2.0:
				c.draw_circle(tp, maxf(t.z * sc * 2.2, 1.6), Color(0.35, 0.55, 0.3, 0.55))
	if main.campaign != null and main.campaign.objective_pos() != null:
		var lo: Vector3 = inv * ((main.campaign.objective_pos() as Vector3) - ppos)
		var op := center + Vector2(lo.x, lo.z) * sc
		if op.distance_to(center) > radius - 6.0:
			op = center + (op - center).normalized() * (radius - 6.0)
		var dd := 5.0
		c.draw_colored_polygon(PackedVector2Array([op + Vector2(0, -dd), op + Vector2(dd, 0), op + Vector2(0, dd), op + Vector2(-dd, 0)]), WARN)
	c.draw_arc(center, radius * 0.5, 0, TAU, 40, Color(ACCENT, 0.12), 1.0)
	c.draw_arc(center, radius, 0, TAU, 48, Color(ACCENT, 0.5), 1.5, true)
	c.draw_line(center, center + Vector2.RIGHT.rotated(_sweep) * radius, Color(ACCENT, 0.25), 2.0)
	for e in _spotted.keys():
		if not is_instance_valid(e) or e.is_dead:
			continue
		var lp: Vector3 = inv * (e.global_position - ppos)
		var p := center + Vector2(lp.x, lp.z) * sc
		if p.distance_to(center) > radius - 4.0:
			p = center + (p - center).normalized() * (radius - 4.0)
		var a: float = clampf(_spotted[e], 0.0, 1.0)
		c.draw_circle(p, 4.0, Color(DANGER, a))
	var fwd_yaw: float = player.aim_yaw - view_yaw
	var tip := center + Vector2(0, -9).rotated(-fwd_yaw)
	var l := center + Vector2(-5, 6).rotated(-fwd_yaw)
	var rr := center + Vector2(5, 6).rotated(-fwd_yaw)
	c.draw_colored_polygon(PackedVector2Array([tip, l, rr]), ACCENT)
	_text(c, center + Vector2(-radius, -radius - 8), "TAC-MAP", 10, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)


func _draw_fps(c: Control, vp: Vector2) -> void:
	var col := ACCENT if _fps >= 55.0 else (WARN if _fps >= 30.0 else DANGER)
	var r := Rect2(vp.x - 330, 14, 96, 22)
	c.draw_rect(r, Color(0, 0, 0, 0.45))
	_text(c, Vector2(r.position.x + 8, r.position.y + 16), "FPS  %d" % int(round(_fps)), 13, col, HORIZONTAL_ALIGNMENT_LEFT, -1, true)


func _draw_debug(c: Control) -> void:
	var d: Dictionary = player.rig.debug_info()
	var lines := [
		["TOP-DOWN  /  independent facing", DIM],
		["INPUT  ·  " + String(d.state), TEXT],
		["speed        %.2f m/s" % d.speed, TEXT],
		["direction    %.1f°" % d.direction, TEXT],
		["cadence      %.2f cycles/s" % d.cadence, TEXT],
		["posture      %d%% crouch" % int(d.crouch * 100.0), TEXT],
		["aim          %d%% blend" % int(d.aim * 100.0), TEXT],
		["locomotion   %d%% blend" % int(d.blend * 100.0), TEXT],
		["torso twist  %.1f°" % d.twist, TEXT],
		["peek         %d%%" % int(d.lean * 100.0), TEXT],
		["input        " + ("GAMEPAD" if player.using_pad else "KEYBOARD / MOUSE"), DIM],
		["graphics     " + Settings.PRESETS[main.quality] + "   fps %d" % int(_fps), DIM],
	]
	c.draw_rect(Rect2(24, 130, 300, 22 + lines.size() * 18), Color(0.03, 0.04, 0.04, 0.6))
	for i in lines.size():
		_text(c, Vector2(34, 150 + i * 18), lines[i][0], 13, lines[i][1])


func _draw_reticle(c: Control) -> void:
	var m := c.get_local_mouse_position()
	var spread_px: float
	if player.first_person:
		m = c.size * 0.5
		var cam: Camera3D = camera_rig.fp_cam
		spread_px = tan(deg_to_rad(player.current_spread())) / tan(deg_to_rad(cam.fov) * 0.5) * c.size.y * 0.5
	else:
		if player.using_pad:
			m = camera_rig.cam.unproject_position(player.aim_point)
		var ppm: float = camera_rig.screen_pixels_per_meter(c.size.y)
		var dist: float = Vector2(player.aim_point.x - player.global_position.x, player.aim_point.z - player.global_position.z).length()
		spread_px = tan(deg_to_rad(player.current_spread())) * maxf(dist, 3.0) * ppm
	var r := clampf(7.0 + spread_px, 7.0, 120.0)
	var col := Color(1, 1, 1, 0.92)
	if player.hovered_enemy != null:
		col = Color(1.0, 0.35, 0.3, 0.95)
	var ads: bool = player.first_person and player.rig.aim_amt > 0.7
	if player.is_scoped():
		_draw_scope(c, m, bool(player.current_weapon().stats.scope))
		return
	if ads:
		pass  # the weapon's own red dot / iron sights take over
	elif player.first_person and player.rig.aim_amt > 0.15:
		c.draw_circle(m, 1.6, Color(col, 1.0 - player.rig.aim_amt))
	else:
		c.draw_arc(m, 3.5, 0, TAU, 16, col, 1.5, true)
		for k in 4:
			var d := Vector2.RIGHT.rotated(k * PI * 0.5)
			c.draw_line(m + d * r, m + d * (r + 8.0), col, 2.0, true)
	if player.reload_timer > 0.0:
		var t: float = 1.0 - player.reload_timer / player.reload_duration
		c.draw_arc(m, r + 14.0, -PI * 0.5, -PI * 0.5 + TAU * t, 40, WARN, 2.5, true)
	if hit_marker > 0.0:
		var hc := DANGER if hit_kill else (WARN if hit_head else Color(1, 1, 1))
		hc.a = hit_marker / 0.25
		for k in 4:
			var d := Vector2(1, 1).normalized().rotated(k * PI * 0.5)
			c.draw_line(m + d * 9.0, m + d * 18.0, hc, 2.5, true)


func _draw_scope(c: Control, m: Vector2, sniper: bool) -> void:
	var vp := c.size
	var r := vp.y * (0.44 if sniper else 0.4)
	c.draw_arc(m, r + vp.x, 0, TAU, 96, Color.BLACK, vp.x * 2.0)
	c.draw_arc(m, r, 0, TAU, 96, Color(0, 0, 0, 0.9), 10.0, true)
	c.draw_arc(m, r - 18.0, 0, TAU, 96, Color(0, 0, 0, 0.35), 26.0, true)
	var col := Color(0, 0, 0, 0.9)
	if not sniper:
		# ACOG: illuminated chevron + bullet-drop stadia
		var amber := Color(1.0, 0.45, 0.1)
		c.draw_colored_polygon(PackedVector2Array([m, m + Vector2(-9, 13), m + Vector2(-5, 13), m + Vector2(0, 5), m + Vector2(5, 13), m + Vector2(9, 13)]), amber)
		c.draw_line(m + Vector2(0, 13), m + Vector2(0, r * 0.55), col, 1.5)
		for k in range(1, 5):
			var yy := 13.0 + k * r * 0.1
			c.draw_line(m + Vector2(-14 + k * 2, yy), m + Vector2(14 - k * 2, yy), col, 1.5)
		c.draw_line(m - Vector2(r, 0), m - Vector2(r * 0.55, 0), col, 3.0)
		c.draw_line(m + Vector2(r * 0.55, 0), m + Vector2(r, 0), col, 3.0)
		return
	c.draw_line(m - Vector2(r, 0), m - Vector2(14, 0), col, 1.5)
	c.draw_line(m + Vector2(14, 0), m + Vector2(r, 0), col, 1.5)
	c.draw_line(m - Vector2(0, r), m - Vector2(0, 14), col, 1.5)
	c.draw_line(m + Vector2(0, 14), m + Vector2(0, r), col, 1.5)
	for k in range(1, 6):
		var o := k * r * 0.12
		for d in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o)]:
			c.draw_circle(m + d, 2.0, col)
	c.draw_circle(m, 1.8, Color(1.0, 0.15, 0.1))


func _draw_enemy_markers(c: Control) -> void:
	var cam: Camera3D = camera_rig.active_camera()
	for e in main.enemies:
		if e.is_dead:
			continue
		var head: Vector3 = e.global_position + Vector3(0, 2.25, 0)
		if cam.is_position_behind(head):
			continue
		if player.first_person and not _spotted.has(e):
			continue
		var p := cam.unproject_position(head)
		if e.is_in_combat():
			if e.alert_flash > 0.0:
				_text(c, p + Vector2(-7, 0), "!", 28, Color(DANGER, minf(e.alert_flash, 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		elif e.awareness > 0.02:
			c.draw_arc(p, 10.0, -PI * 0.5, -PI * 0.5 + TAU * e.awareness, 24, WARN, 3.0, true)
			_text(c, p + Vector2(-4, 6), "?", 15, WARN, HORIZONTAL_ALIGNMENT_LEFT, -1, true)


func _draw_blend_space(c: Control, rect: Rect2, rig) -> void:
	c.draw_rect(rect, Color(0.03, 0.04, 0.04, 0.6))
	var title_s := ("CROUCH" if rig.crouch_amt > 0.5 else "STANDING") + " BLEND SPACE  ·  35 SAMPLES"
	_text(c, rect.position + Vector2(10, 18), title_s, 11, DIM)
	var grid := Rect2(rect.position + Vector2(16, 30), rect.size - Vector2(32, 42))
	var max_v := 7.0
	for gx in 7:
		for gy in 5:
			c.draw_circle(grid.position + Vector2(grid.size.x * gx / 6.0, grid.size.y * gy / 4.0), 2.0, Color(DIM, 0.6))
	c.draw_line(Vector2(grid.get_center().x, grid.position.y), Vector2(grid.get_center().x, grid.end.y), Color(DIM, 0.25), 1.0)
	c.draw_line(Vector2(grid.position.x, grid.get_center().y), Vector2(grid.end.x, grid.get_center().y), Color(DIM, 0.25), 1.0)
	var prev := Vector2.ZERO
	for i in blend_trail.size():
		var lm: Vector2 = blend_trail[i]
		var p := grid.get_center() + Vector2(lm.x / max_v * grid.size.x * 0.5, lm.y / max_v * grid.size.y * 0.5)
		if i > 0:
			c.draw_line(prev, p, Color(ACCENT, 0.5 * (1.0 - float(i) / blend_trail.size())), 2.0, true)
		prev = p
	if blend_trail.size() > 0:
		var lm0: Vector2 = blend_trail[0]
		c.draw_circle(grid.get_center() + Vector2(lm0.x / max_v * grid.size.x * 0.5, lm0.y / max_v * grid.size.y * 0.5), 5.0, ACCENT)


# ================================================================ pause & settings

func _pause_items() -> Array:
	if Net.active and Net.is_server() and Net.transport == "ws":
		return ["RESUME", "SETTINGS", "COPY INVITE LINK  ·  ONLINE", "RESTART MATCH", "LEAVE GAME"]
	if Net.active and Net.is_server():
		return ["RESUME", "SETTINGS", "COPY INVITE LINK  ·  LAN", "COPY INVITE LINK  ·  INTERNET", "RESTART MATCH", "LEAVE GAME"]
	if Net.active:
		return ["RESUME", "SETTINGS", "RESTART  (HOST ONLY)", "LEAVE GAME"]
	return PAUSE_ITEMS


func _copy_invite(internet: bool) -> void:
	if Net.transport == "ws":
		if Net.funnel_url != "":
			var olink := Net.invite_link(Net.funnel_url)
			DisplayServer.clipboard_set(olink)
			add_feed("INVITE COPIED  ·  " + olink, ACCENT)
			add_feed("ANYONE WITH THIS LINK CAN JOIN  ·  NO TAILSCALE NEEDED ON THEIR SIDE", DIM)
		elif Net.funnel_error != "":
			add_feed(Net.funnel_error, DANGER)
		else:
			add_feed("TAILSCALE FUNNEL STILL STARTING  ·  TRY AGAIN IN A MOMENT", WARN)
		return
	if not internet:
		var link := Net.invite_link(Net.lan_ip())
		DisplayServer.clipboard_set(link)
		add_feed("INVITE COPIED  ·  " + link, ACCENT)
		return
	if Net.public_ip != "":
		_copy_public()
		return
	# asks a public "what is my IP" service, only when the host picks this item
	add_feed("LOOKING UP YOUR INTERNET ADDRESS ...", DIM)
	var req := HTTPRequest.new()
	req.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		req.queue_free()
		var ip := body.get_string_from_utf8().strip_edges()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.count(".") == 3:
			Net.public_ip = ip
			_copy_public()
		else:
			add_feed("COULD NOT FIND YOUR INTERNET ADDRESS  ·  USE THE LAN LINK OR TAILSCALE", DANGER))
	if req.request("https://api.ipify.org") != OK:
		req.queue_free()
		add_feed("COULD NOT FIND YOUR INTERNET ADDRESS", DANGER)


func _copy_public() -> void:
	var link := Net.invite_link(Net.public_ip)
	DisplayServer.clipboard_set(link)
	add_feed("INVITE COPIED  ·  " + link, ACCENT)
	add_feed("FRIENDS OVER THE INTERNET NEED UDP PORT %d FORWARDED ON YOUR ROUTER" % Net.port, WARN)


func _resume() -> void:
	mp_pause = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if player.first_person else Input.MOUSE_MODE_CONFINED_HIDDEN


func _pause_activate(i: int) -> void:
	var items := _pause_items()
	if i < 0 or i >= items.size():
		return
	var item: String = items[i]
	if item == "RESUME":
		_resume()
	elif item == "SETTINGS":
		settings_open = true
		settings_row = 0
	elif item.begins_with("COPY INVITE LINK"):
		_copy_invite(item.ends_with("INTERNET") or item.ends_with("ONLINE"))
	elif item.begins_with("RESTART"):
		if Net.active and not Net.is_server():
			add_feed("ONLY THE HOST CAN RESTART", DIM)
			_resume()
		else:
			main.restart()
	else:
		if Net.active:
			main.leave_to_title()
		else:
			main.set_mode(main.mode)


func _pause_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_resume()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		pause_index = posmod(pause_index - 1, _pause_items().size())
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		pause_index = posmod(pause_index + 1, _pause_items().size())
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("vault"):
		_pause_activate(pause_index)
	elif event is InputEventMouseMotion:
		for i in _pause_rects.size():
			if (_pause_rects[i] as Rect2).has_point(event.position):
				pause_index = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _pause_rects.size():
			if (_pause_rects[i] as Rect2).has_point(event.position):
				_pause_activate(i)


func _settings_input(event: InputEvent) -> void:
	var rows: Array = Settings.rows(settings_tab)
	var n: int = rows.size() + 1
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("crouch"):
		_close_settings()
	elif event.is_action_pressed("peek_left") or event.is_action_pressed("cam_rot_left"):
		_settings_set_tab(settings_tab - 1)
	elif event.is_action_pressed("peek_right") or event.is_action_pressed("cam_rot_right") or event.is_action_pressed("ui_focus_next"):
		_settings_set_tab(settings_tab + 1)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		settings_row = posmod(settings_row - 1, n)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		settings_row = posmod(settings_row + 1, n)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		if settings_row < rows.size():
			_settings_adjust(rows[settings_row], -1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		if settings_row < rows.size():
			_settings_adjust(rows[settings_row], 1)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("vault"):
		if settings_row >= rows.size():
			_close_settings()
		else:
			_settings_adjust(rows[settings_row], 1)
	elif event is InputEventMouseMotion:
		for i in _settings_rects.size():
			if (_settings_rects[i] as Rect2).has_point(event.position):
				settings_row = _settings_rects_index(i, rows.size())
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			settings_row = maxi(settings_row - 1, 0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			settings_row = mini(settings_row + 1, n - 1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			for t in _tab_rects.size():
				if (_tab_rects[t] as Rect2).has_point(event.position):
					_settings_set_tab(t)
					return
			for i in _settings_rects.size():
				var r: Rect2 = _settings_rects[i]
				if r.has_point(event.position):
					var idx := _settings_rects_index(i, rows.size())
					settings_row = idx
					if idx >= rows.size():
						_close_settings()
					else:
						_settings_adjust(rows[idx], -1 if event.position.x < r.position.x + r.size.x * 0.5 else 1)


## Visible rect i -> row index (rects cover the scrolled window, then BACK).
func _settings_rects_index(i: int, row_count: int) -> int:
	return mini(int(_settings_idx[i]) if i < _settings_idx.size() else row_count, row_count)


func _settings_set_tab(t: int) -> void:
	settings_tab = posmod(t, Settings.TABS.size())
	settings_row = 0
	_settings_scroll = 0


func _settings_adjust(row: Array, dir: int) -> void:
	Settings.adjust(row, dir)


func _close_settings() -> void:
	settings_open = false
	Settings.save()


func _draw_pause(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.64))
	_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.28), minf(vp.x * 0.4, 600.0), 0.95)
	_text(c, Vector2(0, vp.y * 0.47), "MENU  ·  THE MATCH CONTINUES" if Net.active else "PAUSED", 28, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_pause_rects.clear()
	var items := _pause_items()
	for i in items.size():
		var r := Rect2(vp.x * 0.5 - 150, vp.y * 0.52 + i * 44, 300, 36)
		_pause_rects.append(r)
		if i == pause_index:
			c.draw_rect(r, Color(RED, 0.22))
			_brackets(c, r, 10.0, RED, 2.0)
		_text(c, Vector2(r.position.x, r.position.y + 25), items[i], 17, TEXT if i == pause_index else DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	_text(c, Vector2(0, vp.y - 36), "F2 graphics   ·   M music   ·   F1 debug", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


func _draw_settings(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.62))
	var w := minf(680.0, vp.x - 40.0)
	var x0 := vp.x * 0.5 - w * 0.5
	var y := vp.y * 0.11
	_text(c, Vector2(x0, y), "SETTINGS", 30, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	# tabs
	y += 22.0
	_tab_rects.clear()
	var tw := w / Settings.TABS.size()
	for t in Settings.TABS.size():
		var r := Rect2(x0 + t * tw, y, tw - 6.0, 34.0)
		_tab_rects.append(r)
		var on := t == settings_tab
		c.draw_rect(r, Color(ACCENT, 0.2) if on else Color(1, 1, 1, 0.04))
		c.draw_rect(Rect2(r.position.x, r.end.y - 3.0, r.size.x, 3.0), ACCENT if on else Color(DIM, 0.3))
		_text(c, Vector2(r.position.x, r.position.y + 24), Settings.TABS[t], 17, TEXT if on else DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	y += 62.0
	var rows: Array = Settings.rows(settings_tab)
	var row_h := 34.0
	var visible := maxi(3, int((vp.y * 0.9 - y) / row_h) - 1)
	if settings_row < rows.size():
		if settings_row < _settings_scroll:
			_settings_scroll = settings_row
		elif settings_row >= _settings_scroll + visible:
			_settings_scroll = settings_row - visible + 1
	_settings_scroll = clampi(_settings_scroll, 0, maxi(rows.size() - visible, 0))
	_settings_rects.clear()
	_settings_idx.clear()
	var last := mini(rows.size(), _settings_scroll + visible)
	if _settings_scroll > 0:
		_text(c, Vector2(x0, y - 26), "▲", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	for i in range(_settings_scroll, last + 1):
		var is_back := i == last
		var idx := rows.size() if is_back else i
		if is_back:
			if last < rows.size():
				_text(c, Vector2(x0, y - 12), "▼", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
			y += 8.0
		var r := Rect2(x0, y - 23, w, row_h - 4.0)
		_settings_rects.append(r)
		_settings_idx.append(idx)
		var sel := idx == settings_row
		if sel:
			c.draw_rect(r, Color(RED, 0.22))
			_brackets(c, r, 8.0, RED, 2.0)
		if not is_back:
			var row: Array = rows[i]
			_text(c, Vector2(x0 + 14, y), row[1], 15, TEXT if sel else DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			var val := Settings.label_value(row)
			_text(c, Vector2(x0, y), ("<  " + val + "  >") if sel else val, 15, WARN if sel else TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w - 14, true)
			var k := Settings.slider_frac(row)
			if k >= 0.0:
				var bx := x0 + w * 0.47
				c.draw_rect(Rect2(bx, y - 7, w * 0.25, 4), Color(1, 1, 1, 0.1))
				c.draw_rect(Rect2(bx, y - 7, w * 0.25 * k, 4), ACCENT if sel else Color(TEXT, 0.6))
		else:
			_text(c, Vector2(x0 + 14, y), "SAVE & BACK", 15, TEXT if sel else DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		y += row_h
	_text(c, Vector2(0, vp.y - 30), "Q/E or LB/RB tabs   ·   W/S select   ·   A/D or click adjust   ·   Esc / B back", 13, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


# ================================================================ threat indicators

func _draw_threats(c: Control, vp: Vector2) -> void:
	if player.is_dead:
		return
	var center := vp * 0.5
	var view_yaw: float = player.aim_yaw if player.first_person else camera_rig.yaw
	var inv := Basis(Vector3.UP, -view_yaw)
	# damage direction arcs
	for d in _dmg_dirs:
		var lp: Vector3 = inv * ((d.pos as Vector3) - player.global_position)
		var a := atan2(lp.x, -lp.z) - PI * 0.5
		var alpha: float = clampf(d.t / 1.6, 0.0, 1.0)
		c.draw_arc(center, 150.0, a - 0.32, a + 0.32, 24, Color(DANGER, 0.85 * alpha), 7.0, true)
	# incoming grenades
	var cam: Camera3D = camera_rig.active_camera()
	var warn := false
	for g in get_tree().get_nodes_in_group("grenades"):
		var gp: Vector3 = g.global_position
		var dist := gp.distance_to(player.global_position)
		if dist > 8.0:
			continue
		warn = true
		var pulse := 0.6 + 0.4 * sin(_time * 18.0)
		if not cam.is_position_behind(gp):
			var sp := cam.unproject_position(gp)
			if Rect2(Vector2.ZERO, vp).has_point(sp):
				c.draw_arc(sp, 16.0, 0, TAU, 24, Color(DANGER, pulse), 3.0, true)
				_text(c, sp + Vector2(-5, 7), "!", 18, Color(DANGER, pulse), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		var lp2: Vector3 = inv * (gp - player.global_position)
		var a2 := atan2(lp2.x, -lp2.z) - PI * 0.5
		var tip := center + Vector2(cos(a2), sin(a2)) * 120.0
		c.draw_circle(tip, 7.0, Color(DANGER, pulse))
	if warn:
		_text(c, Vector2(0, vp.y * 0.5 + 70), "GRENADE!", 22, Color(DANGER, 0.7 + 0.3 * sin(_time * 18.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


# ================================================================ multiplayer

func _mp_open() -> void:
	mp_open = true
	mp_row = 0
	if Net.player_name == "" and Profile.signed_in():
		Net.player_name = Profile.current.to_upper()
	if Net.player_name == "":
		Net.player_name = String(Settings.v.get("mp_name", ""))
	if Net.player_name == "":
		Net.player_name = Net.default_name()
	Net.join_ip = String(Settings.v.get("mp_ip", Net.join_ip))
	Net.port = int(Settings.v.get("mp_port", Net.port))
	_mp_port_text = str(Net.port)
	_mp_coop_mode = main.mode if main.mode in MODES else "ch1"


func _mp_save() -> void:
	Net.port = clampi(int(_mp_port_text) if _mp_port_text.is_valid_int() else Net.DEFAULT_PORT, 1024, 65535)
	_mp_port_text = str(Net.port)
	Settings.v.mp_name = Net.player_name
	Settings.v.mp_ip = Net.join_ip
	Settings.v.mp_port = Net.port
	Settings.save()


func _mp_items() -> Array:
	var cur := "_" if int(_time * 2.0) % 2 == 0 else " "
	return [
		"NAME:  " + Net.player_name + (cur if mp_row == 0 else ""),
		"HOST CO-OP:  " + _mode_label(_mp_coop_mode),
		"HOST PVP DEATHMATCH",
		"JOIN  (IP OR INVITE LINK):  " + Net.join_ip + (cur if mp_row == 3 else ""),
		"PORT:  " + _mp_port_text + (cur if mp_row == 4 else ""),
		"CONNECTION:  " + ("ONLINE  ·  TAILSCALE FUNNEL" if mp_online else "DIRECT  ·  LAN / UDP"),
		"BACK",
	]


func _mp_activate(i: int, dir: int = 0) -> void:
	match i:
		0:
			mp_row = 1
		1:
			if dir != 0:
				_mp_coop_mode = MODES[posmod(MODES.find(_mp_coop_mode) + dir, MODES.size())]
				return
			_mp_save()
			if Net.host("coop", Net.port, mp_online) == OK:
				main.net_enter_world(_mp_coop_mode)
		2:
			_mp_save()
			if Net.host("pvp", Net.port, mp_online) == OK:
				main.net_enter_world("pvp")
		3, 4:
			var inv := Net.parse_invite(Net.join_ip)   # a pasted / typed link works too
			if not inv.is_empty():
				Net.join_ip = String(inv[0])
				if Net.join_ip.length() > 0 and int(inv[1]) != Net.DEFAULT_PORT and int(inv[1]) > 0:
					_mp_port_text = str(int(inv[1]))
			_mp_save()
			Net.join(Net.join_ip.strip_edges(), Net.port)
		5:
			mp_online = not mp_online
			Net.status = "HOSTING GOES ONLINE THROUGH TAILSCALE FUNNEL  ·  FRIENDS NEED NO TAILSCALE" if mp_online else "HOSTING ON YOUR LOCAL NETWORK (UDP %d)" % Net.port
		6:
			_mp_save()
			Net.leave()
			Net.status = ""
			mp_open = false


func _mp_input(event: InputEvent) -> void:
	# typing into the text rows (name / IP / port)
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_V and mp_row in [3, 4]:
		var inv := Net.parse_invite(DisplayServer.clipboard_get())
		if not inv.is_empty():
			Net.join_ip = String(inv[0])
			if int(inv[1]) > 0:
				_mp_port_text = str(int(inv[1]))
			Net.status = "INVITE PASTED  ·  PRESS ENTER TO JOIN"
		return
	if event is InputEventKey and event.pressed and mp_row in [0, 3, 4]:
		var k: int = event.keycode
		if k == KEY_BACKSPACE:
			match mp_row:
				0:
					Net.player_name = Net.player_name.substr(0, maxi(Net.player_name.length() - 1, 0))
				3:
					Net.join_ip = Net.join_ip.substr(0, maxi(Net.join_ip.length() - 1, 0))
				4:
					_mp_port_text = _mp_port_text.substr(0, maxi(_mp_port_text.length() - 1, 0))
			return
		var u: int = event.unicode
		if u >= 32 and u < 127 and k != KEY_ENTER and k != KEY_KP_ENTER:
			var ch := char(u)
			match mp_row:
				0:
					if Net.player_name.length() < 16:
						Net.player_name += ch.to_upper()
				3:
					if Net.join_ip.length() < 120 and ch != " ":
						Net.join_ip += ch
				4:
					if _mp_port_text.length() < 5 and ch.is_valid_int():
						_mp_port_text += ch
			return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_mp_activate(6)
	elif event.is_action_pressed("ui_up"):
		mp_row = posmod(mp_row - 1, 7)
	elif event.is_action_pressed("ui_down"):
		mp_row = posmod(mp_row + 1, 7)
	elif (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")) and mp_row == 5:
		_mp_activate(5)
	elif event.is_action_pressed("ui_left") and mp_row == 1:
		_mp_activate(1, -1)
	elif event.is_action_pressed("ui_right") and mp_row == 1:
		_mp_activate(1, 1)
	elif event.is_action_pressed("ui_accept"):
		_mp_activate(mp_row)
	elif event is InputEventMouseMotion:
		for i in _mp_rects.size():
			if (_mp_rects[i] as Rect2).has_point(event.position):
				mp_row = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _mp_rects.size():
			if (_mp_rects[i] as Rect2).has_point(event.position):
				mp_row = i
				if i != 0 and i != 3 and i != 4:
					_mp_activate(i)


func _draw_mp(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.028, 0.04, 0.82))
	_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.2), minf(vp.x * 0.4, 600.0), 0.95)
	_text(c, Vector2(0, vp.y * 0.36), "MULTIPLAYER", 30, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_text(c, Vector2(0, vp.y * 0.36 + 24), "CO-OP: CAMPAIGN CHAPTERS OR ZOMBIE SURVIVAL TOGETHER   ·   PVP: FREE-FOR-ALL, FIRST TO %d" % main.PVP_KILL_LIMIT, 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	var items := _mp_items()
	_mp_rects.clear()
	var top := vp.y * 0.46
	for i in items.size():
		var r := Rect2(vp.x * 0.5 - 230, top + i * 46 - 28, 460, 38)
		_mp_rects.append(r)
		var sel := i == mp_row
		if sel:
			c.draw_rect(r, Color(RED, 0.22))
			_brackets(c, r, 10.0, RED, 2.0)
		var label: String = items[i]
		if sel and (i == 1 or i == 5):
			label = "<  " + label + "  >"
		_text(c, Vector2(r.position.x, r.position.y + 26), label, 17, TEXT if sel else DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	var st := Net.status
	if st != "":
		_text(c, Vector2(0, top + items.size() * 46 + 6), st, 14, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_text(c, Vector2(0, vp.y - 58), "HOST: share your IP with friends (LAN) - over the internet forward UDP port %s or use Tailscale / ZeroTier" % _mp_port_text, 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_text(c, Vector2(0, vp.y - 40), "Up/Down select   ·   type on NAME / IP / PORT   ·   Ctrl+V paste an invite link   ·   Enter confirm   ·   Esc back", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Squad (co-op HP) or scoreboard (PvP), top-left.
func _draw_squad(c: Control, vp: Vector2) -> void:
	var x := 26.0
	var y := 150.0
	if main.mode == "pvp":
		var ids: Array = main.pvp_scores.keys()
		ids.sort_custom(func(a, b): return int(main.pvp_scores[a][1]) > int(main.pvp_scores[b][1]))
		_text(c, Vector2(x, y), "SCOREBOARD   K / D", 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		for id in ids:
			y += 18.0
			var e: Array = main.pvp_scores[id]
			var col := ACCENT if id == Net.my_id() else TEXT
			_text(c, Vector2(x, y), "%-16s  %2d / %d" % [String(e[0]), int(e[1]), int(e[2])], 12, col)
		return
	if Net.is_server():
		var inv_s := Net.invite_link(Net.lan_ip())
		if Net.transport == "ws":
			inv_s = Net.invite_link(Net.funnel_url) if Net.funnel_url != "" else (Net.funnel_error if Net.funnel_error != "" else "STARTING TAILSCALE FUNNEL ...")
		_text(c, Vector2(x, y - 18), "INVITE  " + inv_s + "   (Esc  >  COPY)", 10, DANGER if Net.funnel_error != "" and Net.transport == "ws" else DIM)
	_text(c, Vector2(x, y), "SQUAD", 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var ids2: Array = main.players.keys()
	ids2.sort()
	for id in ids2:
		var p = main.players[id]
		if not is_instance_valid(p):
			continue
		y += 20.0
		var hpf: float = 0.0 if p.is_dead else clampf(p.health / p.max_health, 0.0, 1.0)
		var nm: String = main.display_name_of(id)
		_text(c, Vector2(x, y), nm + ("   DOWN" if p.is_dead else ""), 12, ACCENT if id == Net.my_id() else (DANGER if p.is_dead else TEXT))
		c.draw_rect(Rect2(x + 150, y - 8, 70, 5), Color(0, 0, 0, 0.5))
		c.draw_rect(Rect2(x + 150, y - 8, 70 * hpf, 5), ACCENT if hpf > 0.5 else (WARN if hpf > 0.25 else DANGER))


func _draw_pvp_over(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
	_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.22), minf(vp.x * 0.34, 520.0), 0.9)
	var w: int = main.pvp_winner
	var head := "VICTORY" if w == Net.my_id() else ("%s WINS" % main.pvp_scores[w][0] if main.pvp_scores.has(w) else "MATCH OVER")
	_text(c, Vector2(0, vp.y * 0.42), head, 44, ACCENT if w == Net.my_id() else DANGER, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	var ids: Array = main.pvp_scores.keys()
	ids.sort_custom(func(a, b): return int(main.pvp_scores[a][1]) > int(main.pvp_scores[b][1]))
	var y := vp.y * 0.42 + 44
	for id in ids:
		var e: Array = main.pvp_scores[id]
		_text(c, Vector2(0, y), "%s     %d KILLS  /  %d DEATHS" % [String(e[0]), int(e[1]), int(e[2])], 16, ACCENT if id == Net.my_id() else TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
		y += 26
	var prompt := "Enter  ·  REMATCH FOR EVERYONE   ·   Esc LEAVE" if Net.is_server() else "WAITING FOR THE HOST   ·   Esc LEAVE"
	_text(c, Vector2(0, y + 20), prompt, 14, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


# ================================================================ sign in

var _auth_user := ""
var _auth_pin := ""
var _auth_row := 0
var _auth_msg := ""
var _auth_bad := false
var _auth_rects: Array = []
var _auth_acc_rects: Array = []
const AUTH_ROWS := ["USERNAME", "PASSWORD", "SIGN IN", "CREATE ACCOUNT", "QUIT"]


func _needs_auth() -> bool:
	return title and not Profile.signed_in()


func _auth_submit(create: bool) -> void:
	var err := Profile.create(_auth_user, _auth_pin) if create else Profile.sign_in(_auth_user, _auth_pin)
	if err != "":
		_auth_msg = err
		_auth_bad = true
		_auth_pin = ""
		_auth_row = 1
		Sfx.play(player, "dry", player.global_position, -6.0, 0.0)
		return
	Sfx.play(player, "mag_in", player.global_position, -2.0, 0.0)
	_switch_profile()


## Load the signed-in account's progress: reset the cached saves, rebuild the title.
func _switch_profile() -> void:
	Collection._loaded = false
	Collection.credits = Collection.START_CREDITS
	Collection.owned = {}
	Collection.equipped = {}
	Collection.packs_opened = 0
	Loadout._loaded = false
	Loadout.classes = []
	Loadout.class_index = 0
	Campaign.completed = {}
	Net.player_name = Profile.current.to_upper() if Profile.signed_in() else ""
	last_menu_index = 0
	main.set_mode(main.mode)


func _sign_out() -> void:
	Profile.sign_out()
	_switch_profile()


func _auth_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and _auth_row in [0, 1]:
		var k: int = event.keycode
		if k == KEY_BACKSPACE:
			if _auth_row == 0:
				_auth_user = _auth_user.substr(0, maxi(_auth_user.length() - 1, 0))
			else:
				_auth_pin = _auth_pin.substr(0, maxi(_auth_pin.length() - 1, 0))
			return
		if k == KEY_TAB:
			_auth_row = (_auth_row + 1) % 2
			return
		var u: int = event.unicode
		if u > 32 and u < 127 and k != KEY_ENTER and k != KEY_KP_ENTER:
			var ch := char(u)
			if _auth_row == 0 and _auth_user.length() < 16 and (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-"):
				_auth_user += ch
			elif _auth_row == 1 and _auth_pin.length() < Profile.PIN_LEN and ch.is_valid_int():
				_auth_pin += ch
				if _auth_pin.length() == Profile.PIN_LEN:
					_auth_row = 2
			return
	if event.is_action_pressed("ui_up"):
		_auth_row = posmod(_auth_row - 1, AUTH_ROWS.size())
	elif event.is_action_pressed("ui_down"):
		_auth_row = posmod(_auth_row + 1, AUTH_ROWS.size())
	elif event.is_action_pressed("ui_accept"):
		_auth_activate(_auth_row)
	elif event is InputEventMouseMotion:
		for i in _auth_rects.size():
			if (_auth_rects[i] as Rect2).has_point(event.position):
				_auth_row = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _auth_acc_rects.size():
			if (_auth_acc_rects[i][0] as Rect2).has_point(event.position):
				_auth_user = String(_auth_acc_rects[i][1])
				_auth_pin = ""
				_auth_row = 1
				return
		for i in _auth_rects.size():
			if (_auth_rects[i] as Rect2).has_point(event.position):
				_auth_row = i
				if i >= 2:
					_auth_activate(i)


func _auth_activate(i: int) -> void:
	match i:
		0:
			_auth_row = 1
		1, 2:
			_auth_submit(false)
		3:
			_auth_submit(true)
		4:
			print("[quit] sign-in QUIT row")
			get_tree().quit()


func _draw_auth(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.025, 0.035, 0.86))
	_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.2), minf(vp.x * 0.42, 640.0), 0.95)
	var pw := 460.0
	var px := vp.x * 0.5 - pw * 0.5
	var top := vp.y * 0.38
	c.draw_rect(Rect2(px - 30, top - 50, pw + 60, 360), Color(0.03, 0.045, 0.055, 0.85))
	_brackets(c, Rect2(px - 30, top - 50, pw + 60, 360), 16.0, Color(TEXT, 0.35), 1.5)
	_text(c, Vector2(0, top - 18), "SIGN IN", 24, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	var cur := "_" if int(_time * 2.0) % 2 == 0 else " "
	var pin_show := ""
	for i in Profile.PIN_LEN:
		pin_show += ("*" if i < _auth_pin.length() else "_") + ("  " if i < Profile.PIN_LEN - 1 else "")
	var values := [_auth_user + (cur if _auth_row == 0 else ""), pin_show, "", "", ""]
	_auth_rects.clear()
	for i in AUTH_ROWS.size():
		var y := top + 22 + i * 48.0 + (14.0 if i >= 2 else 0.0)
		var r := Rect2(px, y, pw, 38)
		_auth_rects.append(r)
		var sel := i == _auth_row
		if i < 2:
			c.draw_rect(r, Color(0, 0, 0, 0.45))
			c.draw_rect(r, Color(RED, 0.9) if sel else Color(TEXT, 0.25), false, 2.0 if sel else 1.0)
			_text(c, Vector2(r.position.x + 14, r.position.y + 25), AUTH_ROWS[i], 13, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			_text(c, Vector2(r.position.x + 150, r.position.y + 26), values[i], 18, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		else:
			if sel:
				c.draw_rect(r, Color(RED, 0.22))
				_brackets(c, r, 10.0, RED, 2.0)
			_text(c, Vector2(r.position.x, r.position.y + 26), AUTH_ROWS[i], 17, TEXT if sel else DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	if _auth_msg != "":
		_text(c, Vector2(0, top + 330), _auth_msg, 14, DANGER if _auth_bad else ACCENT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	# accounts on this PC (click to pick)
	_auth_acc_rects.clear()
	var accs := Profile.accounts()
	if not accs.is_empty():
		_text(c, Vector2(0, top + 368), "ACCOUNTS ON THIS PC", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
		var shown := accs.slice(0, 6)
		var w := 150.0
		var x0 := vp.x * 0.5 - (shown.size() * (w + 10) - 10) * 0.5
		for i in shown.size():
			var r := Rect2(x0 + i * (w + 10), top + 380, w, 28)
			_auth_acc_rects.append([r, shown[i]])
			c.draw_rect(r, Color(1, 1, 1, 0.05))
			c.draw_rect(r, Color(TEXT, 0.25), false, 1.0)
			_text(c, Vector2(r.position.x, r.position.y + 19), String(shown[i]).to_upper(), 12, TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	_text(c, Vector2(0, vp.y - 40), "Type your username and %d-digit password   ·   Tab / Up / Down move   ·   Enter sign in   ·   new here? CREATE ACCOUNT" % Profile.PIN_LEN,
			12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_text(c, Vector2(0, vp.y - 22), "Accounts are stored on this PC only  ·  each one keeps its own credits, skins, loadouts and campaign progress", 11, Color(DIM, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
