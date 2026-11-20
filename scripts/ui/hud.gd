extends CanvasLayer
## Tactical HUD: title screen with logo + menu, mission briefing, compass,
## radar minimap (spotted / firing hostiles), weapon & health readouts,
## reticle (top-down and first person), awareness markers, call-out feed,
## animation debug panel + blend-space widget (F1), pause and debrief.

const LOGO_PATH := "res://assets/logo.png"
const Gunsmith = preload("res://scripts/ui/gunsmith.gd")
const WeaponPreview = preload("res://scripts/ui/weapon_preview.gd")
const RoomBrowser = preload("res://scripts/ui/room_browser.gd")
const Armory = preload("res://scripts/ui/armory.gd")
const AdminDashboard = preload("res://scripts/ui/admin_dashboard.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Profile = preload("res://scripts/core/profile.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const WData = preload("res://scripts/weapons/weapon_data.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Progression = preload("res://scripts/core/progression.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const PAUSE_ITEMS := ["RESUME", "SETTINGS", "RESTART", "QUIT TO TITLE"]
const Campaign = preload("res://scripts/modes/campaign.gd")
const MODES := ["ch1", "ch2", "zombie"]
const Net = preload("res://scripts/net/net.gd")
const PlayerScript = preload("res://scripts/characters/player.gd")
const SoldierScript = preload("res://scripts/characters/soldier.gd")
const ALLY := SoldierScript.ALLY_COLOR
const FOE := SoldierScript.FOE_COLOR

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
## Flashbang white-out: seconds left and total.
var _flash_t := 0.0
var _flash_len := 1.0
## Floating damage numbers: {pos, text, t, head, kill}
var _dmg_nums: Array = []
const DMG_NUM_LIFE := 0.9
var _heartbeat := 0.0
var _settings_rects: Array = []
var _pause_rects: Array = []
static var last_menu_index := 0
var _banner := ""
var _banner_sub := ""
var _banner_t := 0.0
## Zombie wave panel: change tracking for its small animations (points gained, a kill, a new wave).
var _zw_points := -1
var _zw_pop := 0
var _zw_pop_t := 0.0
var _zw_left := -1
var _zw_hit_t := 0.0
var _zw_wave := -1
var _zw_wave_t := 0.0
var _zw_break := 0.0
## multiplayer menu (title) and non-pausing in-game menu
var mp_open := false
var mp_row := 0
var mp_pause := false
## Zombie shop panel (between waves).
var shop_open := false
var shop_index := 0
var _shop_rects: Array = []
## the shop list's first visible line; it follows the selection only when that moves by keys / pad
var _shop_scroll := 0
var _shop_follow := true
## the gun of the selected row, on the gunsmith's turntable
var shop_preview: WeaponPreview
var _shop_rows: Array = []
var _shop_msg := ""
var _shop_msg_t := 0.0
var _mp_rects: Array = []
var _mp_coop_mode := "ch1"
var _mp_pvp_map := "forest"
var _mp_tdm_bots := 0
## Bots in a solo team deathmatch (split evenly between both teams).
## Title menu: a solo match against AI picked as the MODE ("" = the scene's own
## mode: a campaign chapter or Zombie Survival). Static: picking it reloads the
## title scene on a map backdrop, and the pick must survive that.
static var vs_ai := ""
var _solo_tdm_bots := 6
## Bots in a solo free-for-all deathmatch.
var _solo_ffa_bots := 5
var _mp_port_text := ""
var _mp_replace_join_text := true
## host online through Tailscale Funnel (WebSocket) instead of direct UDP
static var mp_online := true
var room_browser: RoomBrowser
var _open_rooms_rect := Rect2()

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
var admin_dash: AdminDashboard
## On-screen sticks and buttons (phones only, see platform.gd).
var touch: CanvasLayer


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
	shop_preview = WeaponPreview.new()
	add_child(shop_preview)
	gunsmith = Gunsmith.new()
	add_child(gunsmith)
	gunsmith.setup(self)
	room_browser = RoomBrowser.new()
	add_child(room_browser)
	room_browser.setup(self)
	armory = Armory.new()
	add_child(armory)
	armory.setup(self)
	admin_dash = AdminDashboard.new()
	add_child(admin_dash)
	admin_dash.setup(self)
	if preload("res://scripts/core/platform.gd").touch_mode():
		touch = preload("res://scripts/ui/touch_controls.gd").new()
		touch.name = "TouchControls"
		add_child(touch)
		touch.setup(self)

	menu_index = last_menu_index
	Profile.seed_admin()
	if not Profile.signed_in():
		_auth_user = Profile.last_user()
		_auth_row = 1 if _auth_user != "" else 0
		if Profile.accounts().filter(func(a): return String(a).to_lower() != Profile.ADMIN_NAME).is_empty():
			_auth_msg = "NO ACCOUNTS YET  ·  PICK A USERNAME + %d-DIGIT PASSWORD, THEN CREATE ACCOUNT" % Profile.PIN_LEN
		if Profile._from_guest:
			# the guest chose CREATE ACCOUNT: a fresh name, and its progress comes along
			_auth_user = ""
			_auth_row = 0
			_auth_msg = "PICK A USERNAME + %d-DIGIT PASSWORD, THEN CREATE ACCOUNT  ·  YOUR GUEST PROGRESS COMES WITH YOU" % Profile.PIN_LEN
	if Net.pending_join != "" and not Net.active:
		# launched from a clicked invite link: straight to joining
		var inv := Net.parse_invite(Net.pending_join)
		Net.pending_join = ""
		if not inv.is_empty():
			_mp_open()
			Net.join_ip = String(inv[0])
			if int(inv[1]) > 0:
				_mp_port_text = str(int(inv[1]))
			_mp_save()
			Net.join(Net.join_ip, Net.port)
			mp_row = 3
	if main.quick_restart:
		main.quick_restart = false
		# straight back in on a restart; "continue to the next chapter" still gets its cutscene
		var intro: bool = main.get_script().play_intro_next
		main.get_script().play_intro_next = false
		call_deferred("_deploy", intro)
		return
	# title screen: the world is visible but frozen until DEPLOY
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_cam = preload("res://scripts/ui/menu_camera.gd").new()
	menu_cam.name = "MenuCamera"
	main.add_child(menu_cam)
	menu_cam.setup(main)


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

func on_hit(killed: bool, headshot: bool, damage: float = 0.0, at: Vector3 = Vector3.ZERO, target: Object = null) -> void:
	hit_marker = 0.25
	hit_kill = killed
	hit_head = headshot
	var ear: Vector3 = player.global_position + Vector3.UP * 1.6
	if headshot:
		Sfx.play(player, "headshot", ear, -7.0, 0.04)
	if killed:
		Sfx.play(player, "kill", ear, -6.0 if not headshot else -2.0, 0.0)
		# kill confirm: a camera punch and (single-player) a split-second freeze
		if camera_rig:
			camera_rig.add_shake(0.45 if headshot else 0.3)
		_hitstop(0.06 if headshot else 0.04)
	elif not headshot:
		Sfx.play(player, "hitmarker", ear, -10.0, 0.05)
	if damage > 0.0 and at != Vector3.ZERO and bool(Settings.v.get("damage_numbers", true)):
		# rapid hits on the same target add up into one number that pops again
		var tid := target.get_instance_id() if target != null else 0
		for n in _dmg_nums:
			if tid != 0 and n.id == tid and n.t < 0.35 and not n.kill:
				n.value += damage
				n.text = str(int(round(n.value)))
				n.t = 0.0
				n.pos = at + Vector3(0, 0.15, 0)
				n.head = n.head or headshot
				n.kill = killed
				return
		_dmg_nums.append({"pos": at + Vector3(randf_range(-0.12, 0.12), 0.15, randf_range(-0.12, 0.12)),
				"text": str(int(round(damage))), "value": damage, "id": tid, "t": 0.0, "head": headshot, "kill": killed})
		if _dmg_nums.size() > 24:
			_dmg_nums.pop_front()


## Blinded by a flashbang: white screen, muffled sound, ringing ears.
func flash_white(seconds: float, strength: float) -> void:
	_flash_len = maxf(seconds, 0.3)
	_flash_t = _flash_len
	if player:
		Sfx.play(player, "tinnitus", player.global_position + Vector3.UP * 1.6, lerpf(-14.0, -4.0, strength), 0.0)
	var bus := AudioServer.get_bus_index("SFX")
	if bus >= 0:
		var base := AudioServer.get_bus_volume_db(bus)
		AudioServer.set_bus_volume_db(bus, base - 14.0 * strength)
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_method(func(v: float): AudioServer.set_bus_volume_db(bus, v), base - 14.0 * strength, base, seconds)


## Freezes the action for a moment on a kill. Never in multiplayer: other
## players' games must keep running at full speed.
func _hitstop(sec: float) -> void:
	slowmo(0.06, sec, false)


var _slowmo_tw: Tween
## The speed the game settles at: 1, or the operator's bullet time. Kill freezes and slow-mos ease back to it.
var time_base := 1.0
var _bt_amt := 0.0
var _real_us := 0


## Slows the game to `scale` for `sec` real seconds, then eases back
## (dropkick impacts, kill freeze). Single-player only.
func slowmo(scale: float, sec: float, ease_back: bool = true) -> void:
	if Net.active or Engine.time_scale < scale:
		return
	if _slowmo_tw and _slowmo_tw.is_valid():
		_slowmo_tw.kill()
	Engine.time_scale = scale
	_slowmo_tw = create_tween().set_ignore_time_scale(true)
	_slowmo_tw.tween_interval(sec)
	if ease_back:
		_slowmo_tw.tween_method(func(v: float): Engine.time_scale = v, scale, time_base, 0.15)
	_slowmo_tw.tween_callback(func(): Engine.time_scale = time_base)


## Bullet time: eases the game to the operator's FOCUS speed and back (in real time), pitches all sound down with it.
## A running kill freeze / slow-mo owns the speed until it ends.
func _update_time_scale() -> void:
	var now := Time.get_ticks_usec()
	var real := clampf((now - _real_us) / 1000000.0, 0.0, 0.1) if _real_us > 0 else 0.0
	_real_us = now
	var bt: bool = player != null and is_instance_valid(player) and bool(player.get("bullet_time")) and Net.alone()
	time_base = float(player.FOCUS_SCALE) if bt else 1.0
	_bt_amt = move_toward(_bt_amt, 1.0 if bt else 0.0, real * 6.0)
	if not Net.alone() or (_slowmo_tw and _slowmo_tw.is_valid() and _slowmo_tw.is_running()):
		return
	if not is_equal_approx(Engine.time_scale, time_base):
		Engine.time_scale = move_toward(Engine.time_scale, time_base, real * 5.0)
	AudioServer.playback_speed_scale = lerpf(1.0, 0.72, _bt_amt)


func on_player_damaged(amount: float, attacker: Node = null) -> void:
	if attacker is Node3D and attacker != player:
		_dmg_dirs.append({"pos": (attacker as Node3D).global_position, "t": 1.6})
		if _dmg_dirs.size() > 6:
			_dmg_dirs.pop_front()
	damage_flash = clampf(damage_flash + amount / 35.0, 0.0, 1.0)
	if player.using_pad:
		Input.start_joy_vibration(0, 0.5, 0.8, 0.2)


func wave_banner(text: String, sub: String = "") -> void:
	_banner = text
	_banner_sub = sub
	_banner_t = 3.0


func ping_enemy(e: Node) -> void:
	_spotted[e] = maxf(_spotted.get(e, 0.0), 1.6)


func add_feed(text: String, color: Color = TEXT) -> void:
	feed.push_front({"text": text, "t": 5.0, "color": color})
	if feed.size() > 5:
		feed.pop_back()


## Title menu rows in navigation order. Each: id, section, label, value
## (shown right-aligned), arrow (A/D or the arrows change it), big (DEPLOY).
## PLAY is one MODE choice with only the rows that mode uses under it: a
## campaign chapter plays its own map; Zombie Survival takes a MAP; a match
## against AI takes a MAP and a number of BOTS. DEPLOY starts what is shown.
func _menu_entries() -> Array:
	var kind := _play_kind()
	var e: Array = [
		{"id": "deploy", "sec": "PLAY", "label": "DEPLOY", "value": _deploy_summary(), "big": true},
		{"id": "mode", "sec": "PLAY", "label": "MODE", "value": _play_label(kind), "arrow": true},
	]
	if kind != "campaign":
		e.append({"id": "map", "sec": "PLAY", "label": "MAP", "value": String(main.MAPS[main.map_id]), "arrow": true})
	if kind in ["tdm", "ffa"]:
		e.append({"id": "bots", "sec": "PLAY", "label": "AI BOTS", "value": str(_solo_tdm_bots if kind == "tdm" else _solo_ffa_bots), "arrow": true})
	e += [
		{"id": "mp", "sec": "PLAY", "label": "MULTIPLAYER", "value": "CO-OP  /  PVP"},
		{"id": "rooms", "sec": "PLAY", "label": "OPEN ROOMS", "value": "CLICK TO JOIN"},
		{"id": "loadout", "sec": "OPERATOR", "label": "LOADOUT", "value": Loadout.class_label(), "arrow": true},
		{"id": "armory", "sec": "OPERATOR", "label": "ARMORY", "value": "CR " + str(Collection.credits)},
		{"id": "view", "sec": "SYSTEM", "label": "VIEW", "value": "FIRST PERSON" if main.start_first_person else "TOP-DOWN", "arrow": true},
		# graphics quality and music live in SETTINGS (VIDEO / AUDIO); M still mutes music
		{"id": "settings", "sec": "SYSTEM", "label": "SETTINGS", "value": "QUALITY " + Settings.PRESETS[main.quality]},
		{"id": "update", "sec": "SYSTEM", "label": "↓  UPDATE GAME", "value": "LATEST RELEASE"},
	]
	if Profile.is_admin():
		e.append({"id": "admin", "sec": "SYSTEM", "label": "ADMIN DASHBOARD"})
	if Profile.is_guest():
		e.append({"id": "account", "sec": "SYSTEM", "label": "CREATE ACCOUNT", "value": "KEEPS YOUR PROGRESS"})
	else:
		e.append({"id": "account", "sec": "SYSTEM", "label": "SIGN OUT", "value": Profile.current.to_upper()})
	e.append({"id": "quit", "sec": "SYSTEM", "label": "QUIT"})
	return e


func _menu_items() -> Array:
	return _menu_entries()


## What the PLAY section is set to: "campaign", "zombie", "tdm" or "ffa".
func _play_kind() -> String:
	if vs_ai != "" and main.mode == "zombie":
		return vs_ai
	return "zombie" if main.mode == "zombie" else "campaign"


## Every MODE choice in order: training, campaign chapters, Zombie Survival, then
## the matches against AI (those keep the Zombie Survival scene as the map backdrop).
## Training plays its own map like a chapter (kind "campaign": no MAP row).
func _play_choices() -> Array:
	return ["training"] + MODES + ["tdm", "ffa"]


func _play_label(kind: String) -> String:
	match kind:
		"tdm":
			return "TEAM DEATHMATCH  ·  VS AI"
		"ffa":
			return "FREE FOR ALL  ·  VS AI"
		"campaign":
			return _mode_label(main.mode)
	return _mode_label("zombie")


## One line under DEPLOY: exactly what starts.
func _deploy_summary() -> String:
	var kind := _play_kind()
	if kind == "campaign":
		return "TRAINING  ·  THE RANGE" if main.mode == "training" else "CAMPAIGN  ·  PINEWOOD VALLEY"
	var map := String(main.MAPS[main.map_id])
	if kind == "zombie":
		return "ZOMBIE SURVIVAL  ·  " + map
	return "%s  ·  %s  ·  %d BOTS" % ["TEAM DEATHMATCH" if kind == "tdm" else "FREE FOR ALL", map, _solo_tdm_bots if kind == "tdm" else _solo_ffa_bots]


func _menu_index_of(id: String) -> int:
	var e := _menu_entries()
	for i in e.size():
		if String(e[i].id) == id:
			return i
	return 0


func _menu_arrow(i: int) -> bool:
	var e := _menu_entries()
	return i >= 0 and i < e.size() and bool(e[i].get("arrow", false))


func _mode_label(m: String) -> String:
	if m == "zombie":
		return "ZOMBIE SURVIVAL"
	if m == "training":
		return "TRAINING  ·  LEARN THE CONTROLS" + ("  [DONE]" if Campaign.completed.has("training") else "")
	var inf := Campaign.chapter_info(m)
	var lbl := "CHAPTER %d  %s" % [int(inf.num), String(inf.name)]
	if Campaign.completed.has(m):
		lbl += "  [" + String(Campaign.completed[m]) + "]"
	return lbl


func _menu_activate(i: int, dir: int = 0) -> void:
	var e := _menu_entries()
	if i < 0 or i >= e.size():
		return
	match String(e[i].id):
		"rooms":
			room_browser.open()
		"update":
			OS.shell_open("https://github.com/Ai-Sukmoren/TECTICA/releases/latest")
		"deploy":
			var kind := _play_kind()
			if kind in ["tdm", "ffa"]:
				# a local match (no network) on the chosen map: TDM splits the bots between
				# the operator's team and the other side, in FFA every bot fights everyone
				var bots := _solo_tdm_bots if kind == "tdm" else _solo_ffa_bots
				if Net.host("pvp", Net.port, false) == OK:
					main.net_enter_world("%s%d@%s" % [kind, bots, main.map_id])
			else:
				_deploy()
		"mp":
			_mp_open()
		"bots":
			last_menu_index = i
			var step := dir if dir != 0 else 1
			if _play_kind() == "tdm":
				_solo_tdm_bots = 2 + posmod(_solo_tdm_bots - 2 + 2 * step, 8)   # 2, 4, 6, 8 (even teams)
			else:
				_solo_ffa_bots = 1 + posmod(_solo_ffa_bots - 1 + step, 8)       # 1 .. 8
		"map":
			last_menu_index = i
			var ids: Array = main.playable_maps()
			main.set_map(ids[posmod(ids.find(main.map_id) + (dir if dir != 0 else 1), ids.size())])
		"armory":
			armory.open()
		"mode":
			last_menu_index = i
			var choices := _play_choices()
			var kind := _play_kind()
			var next: String = choices[posmod(choices.find(main.mode if kind in ["campaign", "zombie"] else kind) + (dir if dir != 0 else 1), choices.size())]
			if next in ["tdm", "ffa"]:
				vs_ai = next
				if main.mode != "zombie":
					main.set_mode("zombie")   # load a map backdrop to pick from
			else:
				vs_ai = ""
				if next != main.mode:
					main.set_mode(next)
		"loadout":
			if dir == 0:
				gunsmith.open()
			else:
				Loadout.cycle_class(dir)
				Loadout.save()
		"view":
			main.start_first_person = not main.start_first_person
		"settings":
			settings_open = true
			settings_row = 0
		"admin":
			admin_dash.open()
		"account":
			_sign_out()
		"quit":
			print("[quit] title menu QUIT (menu_index=%d)" % menu_index)
			Settings.mark_clean_exit()
			get_tree().quit()


## Cinematic title-screen camera (freed on deploy).
var menu_cam: Camera3D


const CutsceneDirector = preload("res://scripts/cinematics/cutscene_director.gd")
const ChapterCutscenes = preload("res://scripts/cinematics/chapter_cutscenes.gd")
## the chapter cutscene playing before the mission starts (null otherwise)
var cutscene: Node


## DEPLOY: a campaign chapter opens with its cutscene (cutscene_director.gd), the
## mission starts when it hands back; restarts go straight in.
func _deploy(allow_cutscene: bool = true) -> void:
	title = false
	if is_instance_valid(menu_cam):
		menu_cam.release()
		menu_cam.queue_free()
		menu_cam = null
	if allow_cutscene and CutsceneDirector.wanted(main):
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		cutscene = CutsceneDirector.new()
		cutscene.finished.connect(func(_skipped): _finish_deploy(true))
		cutscene.play(main, ChapterCutscenes.build(String(main.mode), main))
		return
	_finish_deploy()


func _finish_deploy(after_cutscene: bool = false) -> void:
	cutscene = null
	briefing_t = -1.0 if after_cutscene else 0.0   # the cutscene was the briefing
	help_timer = 0.0 if main.training != null else 18.0
	get_tree().paused = false
	player.set_first_person(main.start_first_person)
	if not main.start_first_person:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	main.on_deploy()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(cutscene):
		return   # the cutscene owns the screen (hold to skip is handled there)
	if main != null and main.killcam_active() and (event.is_action_pressed("ui_accept") or event.is_action_pressed("vault")
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)):
		main.killcam.finish()
		get_viewport().set_input_as_handled()
		return
	if settings_open:
		_settings_input(event)
		return
	if _needs_auth():
		_auth_input(event)
		return
	if title and room_browser.is_open:
		if room_browser.handle(event):
			room_browser.close()
		return
	if title and gunsmith.is_open:
		if gunsmith.handle(event):
			gunsmith.close()
		return
	if title and mp_open:
		_mp_input(event)
		return
	if title and admin_dash.is_open:
		if admin_dash.handle(event):
			admin_dash.close()
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
			if _menu_arrow(menu_index):
				_menu_activate(menu_index, -1)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
			if _menu_arrow(menu_index):
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

	if gunsmith.is_open:
		if gunsmith.handle(event):
			gunsmith.close()
			_gunsmith_closed_in_match()
		return
	if armory.is_open:
		if armory.handle(event):
			armory.close()
			_apply_armory_skins_in_match()
		return
	if (get_tree().paused or mp_pause) and not main.game_over:
		_pause_input(event)
		return
	if shop_open:
		_shop_input(event)
		return
	if (event.is_action_pressed("interact") or event.is_action_pressed("shop")) and _shop_available():
		_open_shop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible
	elif event.is_action_pressed("quality"):
		main.set_quality(posmod(main.quality + 1, Settings.CUSTOM))
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
		if main.victory and main.mode == "training":
			main.continue_to("ch1")
		elif main.victory and main.mode == "ch1":
			main.continue_to("ch2")
		elif main.victory and main.mode == "ch2":
			main.set_mode("ch1")
		else:
			main.restart()


func _process(delta: float) -> void:
	_time += delta
	_update_time_scale()
	PlayerScript.input_blocked = (Net.active and (mp_pause or settings_open)) or shop_open or is_instance_valid(cutscene)
	_shop_msg_t = maxf(_shop_msg_t - delta, 0.0)
	if shop_open and not _shop_available():
		_close_shop()   # the next wave started (or the operator went down)
	hit_marker = maxf(hit_marker - delta, 0.0)
	_flash_t = maxf(_flash_t - delta, 0.0)
	for n in _dmg_nums:
		n.t += delta
	_dmg_nums = _dmg_nums.filter(func(n): return n.t < DMG_NUM_LIFE)
	damage_flash = maxf(damage_flash - delta * 0.9, 0.0)
	help_timer -= delta
	_banner_t = maxf(_banner_t - delta, 0.0)
	_zw_pop_t = maxf(_zw_pop_t - delta, 0.0)
	_zw_hit_t = maxf(_zw_hit_t - delta, 0.0)
	_zw_wave_t += delta
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
	_show_progression()
	_host_codes_t -= delta
	overlay.queue_redraw()


## Level-ups, weapon levels and finished challenges from progression.gd.
func _show_progression() -> void:
	while not Progression.pending.is_empty():
		var e: Array = Progression.pending.pop_front()
		var kind := String(e[1])
		var col := Color(1.0, 0.82, 0.3) if kind == "level" else (Color(0.5, 0.9, 1.0) if kind == "weapon" else Color(0.55, 1.0, 0.6))
		add_feed(String(e[0]), col)
		if kind == "level":
			wave_banner("RANK UP")
		if player != null:
			Sfx.play(player, "kill" if kind != "weapon" else "mag_in", player.global_position + Vector3.UP, -2.0, 0.0)


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
		if main.mode == "pvp" and e.team == player.team:
			continue   # a teammate bot: shown in blue, not as a contact
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


## A number in the display face with a drop outline (_text keeps digits in the body face).
func _num(c: Control, pos: Vector2, s: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	c.draw_string_outline(_font_display, pos + Vector2(2, 2), s, align, width, size, 5, Color(0, 0, 0, color.a * 0.6))
	c.draw_string(_font_display, pos, s, align, width, size, color)


## Zombie Survival's wave panel, top centre: the wave, how many infected are left (with the wave's progress), the
## points to spend, and between waves a countdown to the next one. Dark plate and outlined text so it reads over
## snow, fog, muzzle flash or a night sky alike.
func _draw_wave_panel(c: Control, vp: Vector2, d) -> void:
	var pts: int = d.shop.points
	if _zw_points >= 0 and pts > _zw_points:
		_zw_pop = pts - _zw_points
		_zw_pop_t = 1.4
	_zw_points = pts
	var left: int = d.remaining()
	if _zw_left >= 0 and left < _zw_left:
		_zw_hit_t = 0.35
	_zw_left = left
	if d.wave != _zw_wave:
		_zw_wave = d.wave
		_zw_wave_t = 0.0
	if not d.active:
		_zw_break = maxf(_zw_break, float(d.timer))
	else:
		_zw_break = 0.0
	var w := 470.0
	var r := Rect2(vp.x * 0.5 - w * 0.5, 70, w, 66)
	c.draw_rect(r, Color(0.02, 0.025, 0.03, 0.62))
	var edge := Color(ACCENT, 0.55) if d.active else Color(WARN, 0.7)
	_brackets(c, r, 12.0, edge, 2.0)
	var x0 := r.position.x
	var y0 := r.position.y
	# divider ticks between the three blocks
	for dx in [128.0, 330.0]:
		c.draw_line(Vector2(x0 + dx, y0 + 12), Vector2(x0 + dx, y0 + 54), Color(TEXT, 0.12), 1.0)
	# --- the wave: flashes red for a moment when a new one starts
	var fresh := clampf(1.0 - _zw_wave_t / 1.2, 0.0, 1.0)
	if d.active:
		_text(c, Vector2(x0 + 16, y0 + 20), "WAVE", 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		_num(c, Vector2(x0 + 16, y0 + 56), str(d.wave), 34, TEXT.lerp(RED, fresh))
		if d.boss_frac >= 0.0 or d.get("_boss_pending"):
			_text(c, Vector2(x0 + 70, y0 + 54), "BOSS", 11, DANGER, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	else:
		_text(c, Vector2(x0 + 16, y0 + 20), "NEXT WAVE", 11, WARN, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		_num(c, Vector2(x0 + 16, y0 + 56), str(d.wave + 1), 34, Color(TEXT, 0.55))
	# --- middle: infected left in this wave, or the countdown to the next
	var mx := x0 + 144
	var bar := Rect2(mx, y0 + 50, 170, 5)
	c.draw_rect(bar, Color(0, 0, 0, 0.55))
	if d.active:
		var total: int = 6 + 4 * d.wave + (1 if d.wave > 0 and d.wave % 5 == 0 else 0)
		var done := clampf(1.0 - float(left) / maxf(float(total), 1.0), 0.0, 1.0)
		_text(c, Vector2(mx, y0 + 20), "INFECTED LEFT", 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		var col := Color(1.0, 0.42, 0.32).lerp(Color.WHITE, _zw_hit_t / 0.35)
		_num(c, Vector2(mx, y0 + 46), str(left), 28 + int(_zw_hit_t * 10.0), col)
		_text(c, Vector2(mx, y0 + 44), "%d%% CLEARED" % int(done * 100.0), 10, Color(TEXT, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 170)
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * done, bar.size.y)), ACCENT)
	else:
		var tl := maxf(float(d.timer), 0.0)
		var urgent := tl <= 5.0
		var pulse := 0.6 + 0.4 * absf(sin(_time * 6.0)) if urgent else 1.0
		_text(c, Vector2(mx, y0 + 20), "STARTS IN", 11, WARN, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		_num(c, Vector2(mx, y0 + 46), "%d" % int(ceil(tl)), 28, Color(DANGER if urgent else WARN, pulse))
		_text(c, Vector2(mx, y0 + 44), "SEC", 10, Color(TEXT, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 170)
		var frac := clampf(tl / maxf(_zw_break, 0.01), 0.0, 1.0)
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(DANGER if urgent else WARN, 0.9))
	# --- points, with the latest gain rising off them
	var px := x0 + 346
	_text(c, Vector2(px, y0 + 20), "POINTS", 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_num(c, Vector2(px, y0 + 52), str(pts), 24, Color(1.0, 0.84, 0.4))
	if _zw_pop_t > 0.0:
		var k := 1.0 - _zw_pop_t / 1.4
		_num(c, Vector2(px + 64, y0 + 30 - k * 16.0), "+%d" % _zw_pop, 14, Color(ACCENT, clampf(_zw_pop_t / 0.5, 0.0, 1.0)))
	# --- under the panel: the shop between waves, run stats during them
	if not d.active:
		var hint := _arcade_hint()
		var hw := _font_bold.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 28.0
		c.draw_rect(Rect2(vp.x * 0.5 - hw * 0.5, y0 + 72, hw, 22), Color(0.02, 0.025, 0.03, 0.55))
		_text(c, Vector2(0, y0 + 88), hint, 12, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
		# the last three seconds, large in the middle of the screen
		var tl2 := float(d.timer)
		if tl2 > 0.0 and tl2 <= 3.0:
			var n := int(ceil(tl2))
			var f: float = tl2 - floor(tl2) if tl2 != floor(tl2) else 1.0
			_num(c, Vector2(0, vp.y * 0.34), str(n), int(64 + 26 * f), Color(DANGER, clampf(f * 1.6, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	else:
		_text(c, Vector2(0, y0 + 84), "KILLS %d   ·   %s   ·   T+ %s" % [d.kills, main.tod.clock_string(), main.time_string()], 11, Color(TEXT, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## The big announcement (a new wave, a wave cleared, a boss, a chapter objective): a dark band across the screen
## that opens from the middle, the headline in a colour that says what kind of news it is, and a detail line under it.
func _draw_banner(c: Control, vp: Vector2) -> void:
	var age := 3.0 - _banner_t
	var open := 1.0 - pow(1.0 - clampf(age / 0.28, 0.0, 1.0), 3.0)
	var a := open * clampf(_banner_t / 0.6, 0.0, 1.0)
	var col := WARN
	if "CLEARED" in _banner or "COMPLETE" in _banner:
		col = ACCENT
	elif "BOSS" in _banner or "DOWN" in _banner:
		col = DANGER
	elif _banner.begins_with("WAVE"):
		col = RED
	var cy := vp.y * 0.28
	var bw := vp.x * open
	var band := Rect2(vp.x * 0.5 - bw * 0.5, cy - 52, bw, 92 if _banner_sub != "" else 76)
	c.draw_rect(band, Color(0, 0, 0, 0.5 * a))
	c.draw_rect(Rect2(band.position, Vector2(band.size.x, 2)), Color(col, 0.85 * a))
	c.draw_rect(Rect2(band.position + Vector2(0, band.size.y - 2), Vector2(band.size.x, 2)), Color(col, 0.85 * a))
	var slide := (1.0 - open) * 40.0
	_text(c, Vector2(slide, cy + 6), _banner, 48, Color(col.lerp(Color.WHITE, 0.15), a), HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	if _banner_sub != "":
		_text(c, Vector2(-slide, cy + 30), _banner_sub, 14, Color(TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


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
	if _bt_amt > 0.01 and not title:
		# bullet time: a warm tint closing in from the edges
		c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, vp), false, Color(1.0, 0.62, 0.2, 0.6 * _bt_amt))
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.75, 0.4, 0.06 * _bt_amt))
	if main.killcam_active():
		_draw_killcam(c, vp)   # the kill cam replaces the whole HUD while it runs
		return

	if title:
		_draw_title(c, vp)
		return
	if _flash_t > 0.0:
		# full white for the first part, then a slow fade back to sight
		var k := _flash_t / _flash_len
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 0.97, clampf(k * 1.6, 0.0, 1.0)))

	if briefing_t >= 0.0:
		_draw_letterbox(c, vp)
	# Quiet backing plates keep telemetry readable over bright surfaces.
	var focus_bar := Net.alone()   # bullet time only with no other player connected
	for panel in [_weapon_panel_rect(vp), Rect2(16, vp.y - (124 if focus_bar else 100), 224, 106 if focus_bar else 82)]:
		c.draw_rect(panel, Color(0.025, 0.045, 0.055, 0.78))
		c.draw_rect(panel, Color(0.42, 0.66, 0.69, 0.24), false, 1.0)
		c.draw_rect(Rect2(panel.position, Vector2(3, panel.size.y)), Color(ACCENT, 0.8))
	_draw_enemy_markers(c)
	_draw_damage_numbers(c)
	_brackets(c, Rect2(Vector2(14, 14), vp - Vector2(28, 28)), 26.0, Color(TEXT, 0.25), 1.5)
	_draw_compass(c, vp)
	if touch != null:
		_draw_radar(c, Vector2(vp.x - 410.0, 92.0), 66.0)   # phones: the corner belongs to FIRE
	else:
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
	wname += "  ·  LV %d" % Progression.weapon_level(String(w.id))
	if main.director != null and main.director.shop.upgrade_tag(String(w.id)) != "":
		wname += "  ·  " + main.director.shop.upgrade_tag(String(w.id))
	_text(c, Vector2(vp.x - 330, 46), wname, 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
	if w.is_melee():
		_text(c, Vector2(vp.x - 330, 86), "MELEE", 30, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
		_text(c, Vector2(vp.x - 330, 120), "BACKSTAB x%.1f  ·  HOLD FIRE TO KEEP SLASHING" % float(w.stats.get("backstab", 1.0)), 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	else:
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
		var mode := ("AUTO" if bool(w.stats.auto) else ("BOLT" if w.stats.cycle == "bolt" else ("PUMP" if w.stats.cycle == "pump" else ("LEVER" if w.stats.cycle == "lever" else "SEMI"))))
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
	else:
		_text(c, Vector2(vp.x - 330, 140), "INSPECTING  ·  AIM / FIRE TO CANCEL" if player.rig.inspect_t >= 0.0 else "[%s]  INSPECT WEAPON" % Settings.Controls.short("inspect"), 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	_text(c, Vector2(vp.x - 330, 160), "FRAG  x%d   [%s]" % [player.grenades, Settings.Controls.short("grenade")], 12, WARN if player.grenades > 0 else Color(DIM, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
	_text(c, Vector2(vp.x - 330, 178), "FLASH  x%d   [%s]" % [player.flashbangs, Settings.Controls.short("flashbang")], 12, TEXT if player.flashbangs > 0 else Color(DIM, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
	if w.launcher != null:
		var gl := "40MM  x%d   [%s]" % [player.launcher_rounds, Settings.Controls.short("launcher")]
		if player.launcher_cd > 0.0:
			gl = "40MM  RELOADING"
		_text(c, Vector2(vp.x - 330, 196), gl, 12, WARN if player.launcher_rounds > 0 and player.launcher_cd <= 0.0 else Color(DIM, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300, true)
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
		_draw_pvp_header(c, vp)
	elif dir_node != null:
		_draw_wave_panel(c, vp, dir_node)
	elif main.training != null:
		_draw_training(c, vp)
		_draw_stealth_prompt(c, vp)
	else:
		var cp = main.campaign
		if cp != null:
			var ci: Dictionary = cp.info()
			_text(c, Vector2(0, 92), "> " + cp.objective_text(), 14, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
			_text(c, Vector2(0, 110), "CH.%d %s   ·   %s   ·   T+ %s" % [int(ci.num), String(ci.name), main.tod.clock_string(), main.time_string()],
					11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
			_draw_stealth_status(c, vp)
			_draw_waypoint(c, vp)
			_draw_interact(c, vp)
	if dir_node != null and dir_node.boss_frac >= 0.0:
		_draw_boss_bar(c, vp, dir_node.boss_frac, dir_node.boss_name)
	if _banner_t > 0.0:
		_draw_banner(c, vp)

	# ---- FOCUS (bottom-left, over health): filled by kills, spent on bullet time
	if focus_bar:
		var fk: float = clampf(float(player.focus), 0.0, 1.0)
		var ready: bool = fk >= float(player.FOCUS_MIN)
		var fcol := Color(1.0, 0.68, 0.25) if ready else Color(DIM, 0.8)
		var tag := "BULLET TIME" if player.bullet_time else ("READY  ·  JUMP + AIM" if ready else "KILLS FILL IT")
		_text(c, Vector2(26, vp.y - 96), "FOCUS", 13, fcol, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		_text(c, Vector2(80, vp.y - 96), tag, 9, Color(fcol, 0.85) if player.bullet_time else DIM, HORIZONTAL_ALIGNMENT_LEFT, 130)
		var fb := Rect2(26, vp.y - 88, 184, 5)
		c.draw_rect(fb, Color(0, 0, 0, 0.5))
		var pulse := 0.75 + 0.25 * sin(_time * 10.0) if player.bullet_time else 1.0
		c.draw_rect(Rect2(fb.position, Vector2(fb.size.x * fk, fb.size.y)), Color(fcol, pulse))
		var mark := fb.position.x + fb.size.x * float(player.FOCUS_MIN)
		c.draw_line(Vector2(mark, fb.position.y - 1), Vector2(mark, fb.end.y + 1), Color(TEXT, 0.5), 1.0)

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
		stance = "DROPKICK"
	if player.vaulting:
		stance = "VAULT"
	if absf(player.rig.lean_amt) > 0.4:
		stance += "  ·  PEEK " + ("R" if player.rig.lean_amt > 0.0 else "L")
	if player.walking:
		stance += "  ·  SLOW WALK"
	if not main.is_zombie_mode() and main.mode != "pvp":
		var lit := Stealth.light_at(main.level, player.global_position)
		var conceal: float = main.level.concealment(player.global_position) if main.level.has_method("concealment") else 0.0
		if conceal >= 0.5 and player.crouching:
			stance += "  ·  CONCEALED"
		elif lit < 0.45:
			stance += "  ·  IN SHADOW"
		if player.decoy_cd <= 0.0:
			stance += "  ·  DECOY [%s]" % Settings.Controls.short("decoy")
	stance += "  ·  " + ("FPV" if player.first_person else "TOP-DOWN")
	if player.flashlight_on:
		stance += "  ·  LIGHT"
	if player.nvg_on:
		stance += "  ·  NVG"
	_text(c, Vector2(26, vp.y - 34), stance, 11, DIM)

	if debug_visible:
		_draw_debug(c)
		_draw_blend_space(c, Rect2(24, vp.y - 260, 230, 150), player.rig)

	if not player.is_dead:
		_draw_reticle(c)

	if briefing_t >= 0.0:
		_draw_briefing(c, vp)
	elif help_timer > 0.0 and touch == null:
		var a := clampf(help_timer / 2.0, 0.0, 1.0)
		var help := "WASD move  ·  Mouse aim  ·  LMB fire  ·  RMB ADS  ·  Wheel switch weapon  ·  Shift sprint  ·  V dropkick (sprinting, or mid-jump: flying kick)  ·  Space vault / jump  ·  Q/E peek  ·  C crouch  ·  R reload  ·  G frag  ·  T flashlight  ·  N night vision  ·  F interact / first person  ·  Z/V rotate  ·  M music"
		if player.using_pad:
			help = "L-stick move  ·  R-stick aim  ·  RT fire  ·  LT ADS  ·  L3 sprint  ·  A vault  ·  LB/RB peek  ·  B crouch  ·  X reload / interact  ·  Y weapon  ·  Back flashlight  ·  R3 first person  ·  Start pause"
		# two centred lines between the health panel and the radar
		var parts := help.split("  ·  ")
		var half := int(ceil(parts.size() / 2.0))
		var lx := 260.0
		var lw := vp.x - lx * 2.0
		_text(c, Vector2(lx, vp.y - 44), "  ·  ".join(parts.slice(0, half)), 12, Color(TEXT, a * 0.75), HORIZONTAL_ALIGNMENT_CENTER, lw)
		_text(c, Vector2(lx, vp.y - 26), "  ·  ".join(parts.slice(half)), 12, Color(TEXT, a * 0.75), HORIZONTAL_ALIGNMENT_CENTER, lw)

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
	elif gunsmith.is_open:
		gunsmith.draw(c, vp)
	elif armory.is_open:
		armory.draw(c, vp)
	elif (get_tree().paused or mp_pause) and not main.game_over:
		_draw_pause(c, vp)
	elif shop_open:
		_draw_shop(c, vp)
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
			_text(c, Vector2(0, vp.y * 0.5 + 40), "KILLS %d   ·   HEADSHOTS %d   ·   ACCURACY %d%%   ·   SCORE %d   ·   %d PTS EARNED" % [dn.kills, dn.headshots, int(acc), dn.score, dn.shop.earned],
					15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
			_text(c, Vector2(0, vp.y * 0.5 + 92), "BEST  ·  WAVE %d  ·  SCORE %d" % [dn.best_wave, dn.best_score], 12, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		else:
			var head := "OPERATOR DOWN"
			if won:
				head = {"ch2": "CAMPAIGN COMPLETE", "training": "TRAINING COMPLETE"}.get(main.mode, "CHAPTER 1 COMPLETE")
			_text(c, Vector2(0, vp.y * 0.5), head, 44, ACCENT if won else DANGER, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
			_text(c, Vector2(0, vp.y * 0.5 + 40), "KILLS %d    ·    ACCURACY %d%%    ·    TIME %s" % [total - alive, int(acc), main.time_string()],
					15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
			if won and main.grade != "":
				var gcol := ACCENT if main.grade in ["S", "A"] else WARN
				_text(c, Vector2(0, vp.y * 0.5 + 112), "GRADE  " + main.grade, 40, gcol, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
				_text(c, Vector2(0, vp.y * 0.5 + 136), "SCORE %d   ·   HEADSHOTS %d   ·   DAMAGE TAKEN %d   ·   BEST %s" % [main.mission_score, main.headshot_kills, int(main.damage_taken), main.best_grade],
						12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
		var prompt := "Enter / A to redeploy"
		if won and main.mode == "training":
			prompt = "Enter / A  ·  START CHAPTER 1: TIMBERLINE"
		elif won and main.mode == "ch1":
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
	if room_browser.is_open:
		room_browser.draw(c, vp)
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
	if admin_dash.is_open:
		admin_dash.draw(c, vp)
		return
	_draw_main_menu(c, vp)


## Title screen: command panel on the left (logo + grouped menu), mission and
## operator cards on the right, status bar along the bottom. The frozen world
## stays visible behind it.
func _draw_main_menu(c: Control, vp: Vector2) -> void:
	# phones: the menu is two columns (PLAY + OPERATOR | SYSTEM) under a
	# smaller logo, so every row fits the short screen at a thumb-sized height
	var two_col := touch != null
	var panel_w := clampf(vp.x * 0.56, 640.0, 900.0) if two_col else clampf(vp.x * 0.34, 400.0, 520.0)
	if is_instance_valid(menu_cam) and float(menu_cam.fade) > 0.01:
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, float(menu_cam.fade)))
	# world dimmed, left panel solid, soft edge between them
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.01, 0.02, 0.03, 0.28))
	c.draw_rect(Rect2(0, 0, panel_w, vp.y), Color(0.012, 0.02, 0.028, 0.86))
	for k in 24:
		c.draw_rect(Rect2(panel_w + k * 4.0, 0, 4.0, vp.y), Color(0.012, 0.02, 0.028, 0.86 * (1.0 - (k + 1) / 24.0)))
	c.draw_rect(Rect2(panel_w - 2, 0, 2, vp.y), Color(RED, 0.55))
	var y := 0.0
	while y < vp.y:
		c.draw_line(Vector2(0, y), Vector2(vp.x, y), Color(0, 0, 0, 0.045), 1.0)
		y += 3.0

	# logo + context line
	var pad := 44.0
	var logo_w := minf(panel_w - pad * 2.0, 300.0) if two_col else panel_w - pad * 2.0
	var pulse := 0.94 + 0.06 * sin(_time * 2.0)
	var logo_h := logo_w * (float(_logo.get_height()) / float(_logo.get_width()) if _logo != null else 0.22)
	_draw_logo(c, Vector2(pad + logo_w * 0.5, 40.0 + logo_h * 0.5), logo_w, pulse)
	var beta_rect := Rect2(panel_w - pad - 70.0, 40.0 + logo_h + 7.0, 70.0, 24.0)
	c.draw_rect(beta_rect, Color(0.025, 0.035, 0.045, 0.95))
	c.draw_rect(beta_rect, Color(WARN, 0.9), false, 1.0)
	_text(c, beta_rect.position + Vector2(0, 17), "BETA", 12, WARN, HORIZONTAL_ALIGNMENT_CENTER, beta_rect.size.x, true)
	var sub := "TACTICAL OPERATIONS"
	_text(c, Vector2(pad, 40.0 + logo_h + 26.0), sub, 13, Color(RED, 0.95), HORIZONTAL_ALIGNMENT_LEFT, -1, true)

	# grouped menu
	var entries := _menu_entries()
	_menu_rects.clear()
	var row_w := (panel_w - pad * 3.0) * 0.5 if two_col else panel_w - pad * 2.0
	var top := 40.0 + logo_h + 56.0
	var avail := vp.y - top - 70.0
	var row_h := clampf(avail / (entries.size() + 3.6), 30.0, 40.0)
	if two_col:
		var counts := [0, 0]
		for e in entries:
			counts[1 if String(e.sec) == "SYSTEM" else 0] += 1
		var secs := 2.0   # section headers in the busier column
		row_h = clampf((avail - secs * 30.0) / (maxf(counts[0] + 0.45, counts[1])), 30.0, 48.0)
	var col_y := [top, top]
	var cy := top
	var sec := ""
	var col := 0
	var x0 := pad
	for i in entries.size():
		var e: Dictionary = entries[i]
		if two_col:
			col = 1 if String(e.sec) == "SYSTEM" else 0
			x0 = pad + col * (row_w + pad)
			cy = col_y[col]
		if String(e.sec) != sec:
			sec = String(e.sec)
			cy += 10.0
			_text(c, Vector2(x0, cy + 12.0), sec, 11, Color(DIM, 0.8), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			c.draw_line(Vector2(x0 + 8.0 + sec.length() * 8.5, cy + 8.0), Vector2(x0 + row_w, cy + 8.0), Color(DIM, 0.25), 1.0)
			cy += 20.0
		var big := bool(e.get("big", false))
		var h := row_h * (1.45 if big else 1.0)
		var r := Rect2(x0, cy, row_w, h - 4.0)
		_menu_rects.append(r)
		var sel := i == menu_index
		if big:
			c.draw_rect(r, Color(RED, 0.92 if sel else 0.7))
			if sel:
				c.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3.0), Vector2(r.size.x, 3.0)), Color(1, 1, 1, 0.5))
			_text(c, Vector2(r.position.x + 18.0, r.position.y + r.size.y * 0.5 + 10.0), String(e.label), 26, Color(1, 1, 1, 0.97), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			_text(c, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 6.0), "ENTER  ▶", 13, Color(1, 1, 1, 0.85),
					HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 18.0, true)
		else:
			if sel:
				c.draw_rect(r, Color(RED, 0.18))
				c.draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), RED)
			var ty := r.position.y + r.size.y * 0.5 + 6.0
			_text(c, Vector2(r.position.x + 14.0, ty), String(e.label), 16, TEXT if sel else Color(TEXT, 0.72), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			var val := String(e.get("value", ""))
			if val != "":
				if sel and bool(e.get("arrow", false)):
					val = "‹  " + val + "  ›"
				_text(c, Vector2(r.position.x, ty - 1.0), val, 13, ACCENT if sel else DIM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12.0, sel)
		cy += h
		if two_col:
			col_y[col] = cy

	# right-hand cards (hidden when the window is narrow)
	if vp.x - panel_w > 560.0:
		var cw := clampf(vp.x * 0.26, 340.0, 440.0)
		var cx := vp.x - cw - 48.0
		var card_y := 64.0
		card_y = _menu_card(c, Rect2(cx, card_y, cw, 0), "MISSION", _mission_lines()) + 18.0
		card_y = _menu_card(c, Rect2(cx, card_y, cw, 0), "OPERATOR", _operator_lines()) + 18.0
		_menu_card(c, Rect2(cx, card_y, cw, 0), "DAILY CHALLENGES", _daily_lines())

	# status bar
	c.draw_rect(Rect2(0, vp.y - 44.0, vp.x, 44.0), Color(0, 0, 0, 0.55))
	c.draw_line(Vector2(0, vp.y - 44.0), Vector2(vp.x, vp.y - 44.0), Color(TEXT, 0.12), 1.0)
	_text(c, Vector2(pad, vp.y - 17.0), "TAP A ROW TO OPEN IT  ·  TAP A ‹ › ROW TO CHANGE IT" if two_col else "W/S  SELECT     A/D  CHANGE     ENTER  CONFIRM     MOUSE  CLICK", 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var ver := "v" + String(ProjectSettings.get_setting("application/config/version", "1.5.0-beta")).to_upper()
	_text(c, Vector2(vp.x - 420.0, vp.y - 17.0), ver + "  ·  BETA BUILD", 11, Color(WARN, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 380.0, true)
	if main.title_notice != "":
		var tr := Rect2(panel_w + 40.0, vp.y - (160.0 if Settings.crash_recovered else 104.0), vp.x - panel_w - 80.0, 48.0)
		c.draw_rect(tr, Color(0.06, 0.03, 0.0, 0.9))
		c.draw_rect(tr, Color(WARN, 0.9), false, 1.0)
		_text(c, Vector2(tr.position.x, tr.position.y + 29.0), main.title_notice, 12, WARN, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, true)
	if Settings.crash_recovered:
		var nr := Rect2(panel_w + 40.0, vp.y - 104.0, vp.x - panel_w - 80.0, 48.0)
		c.draw_rect(nr, Color(0.06, 0.03, 0.0, 0.9))
		c.draw_rect(nr, Color(WARN, 0.9), false, 1.0)
		_text(c, Vector2(nr.position.x, nr.position.y + 20.0), "LAST SESSION ENDED WITH THE PC SHUTTING OFF  ·  GRAPHICS SWITCHED TO SAFE (60 FPS)", 12, WARN, HORIZONTAL_ALIGNMENT_CENTER, nr.size.x, true)
		_text(c, Vector2(nr.position.x, nr.position.y + 38.0), "THIS POINTS TO A POWER / HARDWARE FAULT  ·  YOU CAN RAISE QUALITY AGAIN IN SETTINGS", 10, Color(TEXT, 0.75), HORIZONTAL_ALIGNMENT_CENTER, nr.size.x, true)


## Boss health bar under the wave line. The trailing light segment drains
## behind the real value so big hits read clearly.
var _boss_trail := 1.0


func _draw_boss_bar(c: Control, vp: Vector2, frac: float, boss_name: String) -> void:
	_boss_trail = maxf(frac, move_toward(_boss_trail, frac, get_process_delta_time() * 0.35))
	var w := minf(560.0, vp.x * 0.5)
	var r := Rect2((vp.x - w) * 0.5, 140.0, w, 10.0)
	var rage := frac <= 0.5
	_text(c, Vector2(0, r.position.y - 6.0), boss_name + ("  ·  ENRAGED" if rage else ""), 13, RED if rage else TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	c.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * _boss_trail, r.size.y)), Color(1.0, 0.85, 0.7, 0.55))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), Color(RED, 0.95))
	c.draw_line(r.position + Vector2(r.size.x * 0.5, -2), r.position + Vector2(r.size.x * 0.5, r.size.y + 2), Color(TEXT, 0.5), 1.0)
	c.draw_rect(r.grow(2.0), Color(TEXT, 0.35), false, 1.0)


## Kill cam overlay: letterbox, KILLCAM tag and the killer card.
func _draw_killcam(c: Control, vp: Vector2) -> void:
	var kc = main.killcam
	var k: float = clampf(float(kc.t) / 0.4, 0.0, 1.0) * clampf((float(kc.TIME) - float(kc.t)) / 0.3, 0.0, 1.0)
	var bar := 70.0 * k
	c.draw_rect(Rect2(0, 0, vp.x, bar), Color(0, 0, 0, 0.92))
	c.draw_rect(Rect2(0, vp.y - bar, vp.x, bar), Color(0, 0, 0, 0.92))
	if int(_time * 2.5) % 2 == 0:
		c.draw_circle(Vector2(48, 44), 7.0, Color(RED, k))
	_text(c, Vector2(64, 52), "KILLCAM", 22, Color(RED, k), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var info: Dictionary = kc.info
	var w := minf(560.0, vp.x * 0.6)
	var r := Rect2((vp.x - w) * 0.5, vp.y - bar - 118.0, w, 96.0)
	c.draw_rect(r, Color(0.02, 0.03, 0.04, 0.85 * k))
	c.draw_rect(Rect2(r.position, Vector2(6, r.size.y)), Color(RED, k))
	_text(c, r.position + Vector2(22, 26), "KILLED BY", 12, Color(DIM, k), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_text(c, r.position + Vector2(22, 60), String(info.get("name", "")), 30, Color(TEXT, k), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var parts: Array = ["%d M" % int(round(float(info.get("dist", 0.0))))]
	if String(info.get("weapon", "")) != "":
		parts.append(String(info.weapon))
	parts.append("HP LEFT %d%%" % int(round(float(info.get("hp", 0.0)) * 100.0)))
	_text(c, r.position + Vector2(22, 84), "   ·   ".join(parts), 13, Color(WARN, k), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var hpw := r.size.x - 44.0
	c.draw_rect(Rect2(r.position.x + 22, r.end.y - 6, hpw, 3), Color(1, 1, 1, 0.12 * k))
	c.draw_rect(Rect2(r.position.x + 22, r.end.y - 6, hpw * float(info.get("hp", 0.0)), 3), Color(RED, k))
	_text(c, Vector2(0, vp.y - bar * 0.5 + 6), "SPACE / CLICK  SKIP", 11, Color(DIM, k), HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Lines for the daily challenges card.
func _daily_lines() -> Array:
	Progression.ensure()
	var out: Array = []
	for ch in Progression.daily:
		var done := bool(ch.done)
		var line := "%s   %d/%d" % [Progression.challenge_text(ch), int(ch.progress), int(ch.goal)]
		out.append([("DONE  " if done else "") + line, 13, ACCENT if done else TEXT])
		out.append(["   REWARD  CR %d  ·  %d XP" % [Progression.REWARD_CR[int(ch.tier)], Progression.REWARD_XP[int(ch.tier)]], 10, Color(DIM, 0.9)])
	out.append(["New challenges every day at midnight.", 10, Color(DIM, 0.7)])
	return out


## Lines for the mission card: [text, size, color].
func _mission_lines() -> Array:
	var kind := _play_kind() if title else ""
	if kind in ["tdm", "ffa"]:
		var bots := _solo_tdm_bots if kind == "tdm" else _solo_ffa_bots
		return [["TEAM DEATHMATCH" if kind == "tdm" else "FREE FOR ALL", 26, TEXT],
				[String(main.MAPS[main.map_id]) + "  ·  VS AI", 12, RED],
				["%d AI bots split between your team and theirs." % bots if kind == "tdm" else "%d AI bots, everyone for themselves." % bots, 13, Color(TEXT, 0.8)],
				["FIRST TO %d KILLS  ·  10 MINUTES" % main.PVP_KILL_LIMIT, 13, ACCENT]]
	if main.is_zombie_mode():
		var out: Array = [["ZOMBIE SURVIVAL", 26, TEXT], [String(main.MAPS[main.map_id]) + "  ·  OUTBREAK", 12, RED]]
		out.append(["Survive endless waves after dark.", 13, Color(TEXT, 0.8)])
		if main.director != null and main.director.best_wave > 0:
			out.append(["BEST  WAVE %d   ·   SCORE %d" % [main.director.best_wave, main.director.best_score], 13, ACCENT])
		return out
	if main.mode == "training":
		return [["TRAINING", 12, RED], ["THE RANGE", 28, TEXT],
				["A guided course: every move in 16 short steps.", 13, Color(TEXT, 0.8)],
				["DONE  ·  REPLAY ANY TIME" if Campaign.completed.has("training") else "FINISH IT ONCE FOR +250 CREDITS", 13,
						ACCENT if Campaign.completed.has("training") else WARN]]
	var ci := Campaign.chapter_info(main.mode)
	var lines: Array = [
		["CHAPTER %d" % int(ci.num), 12, RED],
		[String(ci.name), 28, TEXT],
		[String(ci.location), 12, Color(TEXT, 0.75)],
		["%02d00 HRS LOCAL" % int(float(ci.hour)), 12, DIM],
	]
	if Campaign.completed.has(main.mode):
		lines.append(["COMPLETED  ·  GRADE " + String(Campaign.completed[main.mode]), 13, ACCENT])
	else:
		lines.append(["NOT YET COMPLETED", 13, WARN])
	return lines


func _operator_lines() -> Array:
	var cur := Loadout.current()
	var pri := String(WData.WEAPONS[cur.primary.id].name)
	var smg := String(WData.WEAPONS[cur.smg.id].name)
	var sec := String(WData.WEAPONS[cur.secondary.id].name)
	var lvl := Progression.level()
	var lp: Array = Progression.level_progress()
	var xp_line := "MAX LEVEL" if int(lp[1]) == 0 else "XP  %d / %d" % [int(lp[0]), int(lp[1])]
	return [
		[Profile.current.to_upper(), 24, TEXT],
		["LV %d  ·  %s  ·  %s" % [lvl, Progression.rank_name(lvl), xp_line], 12, WARN],
		[Loadout.class_label() + "  ·  " + Loadout.class_desc(), 12, Color(TEXT, 0.75)],
		["PRIMARY     " + pri, 13, TEXT],
		["SMG         " + smg, 13, TEXT],
		["PISTOL      " + sec, 13, TEXT],
		["CREDITS  %d     SKINS  %d" % [Collection.credits, Collection.total_owned()], 13, ACCENT],
	]


## Draws a titled card sized to its lines; returns its bottom edge.
func _menu_card(c: Control, r: Rect2, heading: String, lines: Array) -> float:
	var h := 60.0
	for l in lines:
		h += float(l[1]) + 12.0
	r.size.y = h
	c.draw_rect(r, Color(0.012, 0.02, 0.028, 0.78))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), Color(RED, 0.8))
	_brackets(c, r, 12.0, Color(TEXT, 0.25), 1.0)
	_text(c, r.position + Vector2(18, 28), heading, 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var y := r.position.y + 44.0
	for l in lines:
		y += float(l[1]) + 6.0
		_text(c, Vector2(r.position.x + 18.0, y), String(l[0]), int(l[1]), l[2], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0, int(l[1]) >= 16)
		y += 6.0
	return r.end.y


## The briefing's cinema bars (first ~5 s). Drawn under the HUD so the compass,
## ammo and health stay readable while they are up.
## The weapon / ammo panel in the top-right corner.
func _weapon_panel_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - 344, 24, 328, 126)


func _draw_letterbox(c: Control, vp: Vector2) -> void:
	var bar_h := 60.0 * clampf(1.0 - maxf(briefing_t - 4.8, 0.0) / 0.8, 0.0, 1.0)
	if bar_h <= 0.0:
		return
	c.draw_rect(Rect2(0, 0, vp.x, bar_h), Color(0, 0, 0, 0.85))
	c.draw_rect(Rect2(0, vp.y - bar_h, vp.x, bar_h), Color(0, 0, 0, 0.85))


func _draw_briefing(c: Control, vp: Vector2) -> void:
	var t := briefing_t
	var a := clampf(t / 0.3, 0.0, 1.0) * clampf((6.0 - t) / 0.8, 0.0, 1.0)
	var lines := [
		["TECTICA  //  ZOMBIE SURVIVAL", RED, 20],
		[String({"warehouse": "LOCATION   WAREHOUSE - LOADING FLOOR, OVERRUN", "backrooms": "LOCATION   THE BACKROOMS - LEVEL 0, NO EXIT", "tokyo": "LOCATION   TOKYO - CANAL STREET BY THE RAIL LINE, WALLED IN"}.get(main.map_id, "LOCATION   PINEWOOD VALLEY - LOGGING CAMP, OVERRUN")), TEXT, 14],
		[String({"warehouse": "SITREP     CLOSE QUARTERS BETWEEN THE CRATES. WATCH EVERY AISLE", "backrooms": "SITREP     THE LIGHTS HUM. SOMETHING WALKS THE YELLOW HALLS", "tokyo": "SITREP     THEY COME OVER THE BRIDGE AND DOWN THE TRACKS. HOLD THE STREET"}.get(main.map_id, "SITREP     NIGHT IS FALLING. THEY COME OUT OF THE TREES IN WAVES")), TEXT, 14],
		["OBJECTIVE  SURVIVE AS LONG AS POSSIBLE", TEXT, 14],
		["INTEL      PISTOL ONLY - KILLS EARN POINTS - [" + Settings.Controls.short("interact") + "] SHOP AT THE ARCADE BETWEEN WAVES  -  [" + Settings.Controls.short("flashlight") + "] FLASHLIGHT", TEXT, 14],
		["ROE        KILL EVERYTHING THAT MOVES", ACCENT, 14],
	] if main.is_zombie_mode() else (_pvp_briefing() if main.mode == "pvp" else (_training_briefing() if main.training != null else _campaign_briefing()))
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
		["TECTICA  //  " + _pvp_title(), RED, 20],
		["LOCATION   " + String(main.MAPS[main.map_id]), TEXT, 14],
		["OBJECTIVE  FIRST %s TO %d KILLS  -  10 MINUTES" % ["TEAM" if main.saved_tdm else "FIGHTER", main.PVP_KILL_LIMIT], TEXT, 14],
		["INTEL      SHOTS SHOW YOU ON THEIR RADAR  -  BUSHES HIDE YOU", TEXT, 14],
		["ROE        BLUE TAGS AND ARMBANDS ARE YOUR TEAM  -  RED ARE THE ENEMY", ALLY, 14] if main.saved_tdm
				else ["ROE        FREE FOR ALL  -  EVERYONE ELSE IS A TARGET", ACCENT, 14],
	]


func _training_briefing() -> Array:
	return [
		["TECTICA  //  TRAINING", RED, 20],
		["LOCATION   THE RANGE", TEXT, 14],
		["OBJECTIVE  LEARN TO MOVE, SHOOT AND FIGHT, ONE STEP AT A TIME", TEXT, 14],
		["INTEL      EACH STEP IS AT THE TOP OF THE SCREEN, WITH YOUR KEYS", TEXT, 14],
		["ROE        TARGETS STAND STILL  -  THE KILL HOUSE SHOOTS BACK", ACCENT, 14],
	]


## Training: the current step, how to do it with this operator's keys, the
## step count, the waypoint, and the countdown while down.
func _draw_training(c: Control, vp: Vector2) -> void:
	var tr = main.training
	_text(c, Vector2(0, 92), "> " + tr.objective_text(), 15, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_text(c, Vector2(0, 112), tr.how_text(), 13, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_text(c, Vector2(0, 130), "TRAINING   ·   STEP %d / %d" % [mini(tr.step + 1, tr.STEPS.size()), tr.STEPS.size()], 10, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	if player.is_dead and tr.respawn_t >= 0.0:
		_text(c, Vector2(0, vp.y * 0.62), "BACK UP IN %d" % int(ceil(tr.respawn_t)), 26, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_draw_waypoint(c, vp)


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
	var cp = main.objectives()
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
	# keep off the weapon panel with the grenade lines and feed under it (top right)
	# and the radar (bottom right): slide below / above
	var column := _weapon_panel_rect(vp)
	column.end.y = 200.0 + feed.size() * 22.0
	var avoid := [[column, 1.0]]
	if touch == null:
		avoid.append([Rect2(vp.x - 236, vp.y - 248, 216, 216), -1.0])
	for a in avoid:
		var r: Rect2 = (a[0] as Rect2).grow(18.0)
		if r.has_point(clamped):
			clamped.y = r.end.y + 12.0 if float(a[1]) > 0.0 else r.position.y - 30.0
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
	if _draw_stealth_prompt(c, vp):
		return
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


## Radar shapes are built facing north at _radar_pos and drawn through a
## rotation for the current view, so turning never rebuilds them; moving more
## than RADAR_REBUILD metres does (the clip circle is rotation-invariant, and a
## shift that small moves the rim by about a pixel).
const RADAR_REBUILD := 0.25
var _radar_pos := Vector3.INF
var _radar_center := Vector2.INF
var _radar_shapes: Array = []


## Radar map shapes in screen space: [polygon, color] or [point, color, radius].
func _build_radar_shapes(center: Vector2, radius: float, sc: float, inv: Basis, ppos: Vector3) -> Array:
	var out: Array = []
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
			out.append([clipped, Color(0.55, 0.7, 0.55, 0.55) if r.tall else Color(0.5, 0.6, 0.45, 0.3)])
	if main.level.has_method("trees_near"):
		for t in main.level.trees_near(ppos, 24.0):
			var lt: Vector3 = inv * (Vector3(t.x, 0, t.y) - ppos)
			var tp := center + Vector2(lt.x, lt.z) * sc
			if tp.distance_to(center) < radius - 2.0:
				out.append([tp, Color(0.35, 0.55, 0.3, 0.55), maxf(t.z * sc * 2.2, 1.6)])
	return out


func _draw_radar(c: Control, center: Vector2, radius: float) -> void:
	var sc := radius / 24.0
	var view_yaw: float = player.aim_yaw if player.first_person else camera_rig.yaw
	var inv := Basis(Vector3.UP, -view_yaw)
	var ppos: Vector3 = player.global_position
	c.draw_circle(center, radius + 3.0, Color(0, 0, 0, 0.55))
	c.draw_circle(center, radius, Color(0.06, 0.09, 0.07, 0.75))
	# buildings + trees: clipping and triangulating every outline is costly, so
	# the shapes are built facing north and only rebuilt after moving a little
	if center != _radar_center or Vector2(ppos.x - _radar_pos.x, ppos.z - _radar_pos.z).length() > RADAR_REBUILD:
		_radar_center = center
		_radar_pos = ppos
		_radar_shapes = _build_radar_shapes(center, radius, sc, Basis.IDENTITY, ppos)
	# north-up shapes -> current view: shift by the move since the build, turn by the view yaw
	var d := Vector2(ppos.x - _radar_pos.x, ppos.z - _radar_pos.z) * sc
	var ex: Vector3 = inv * Vector3.RIGHT
	var ez: Vector3 = inv * Vector3.BACK
	var xa := Vector2(ex.x, ex.z)
	var ya := Vector2(ez.x, ez.z)
	c.draw_set_transform_matrix(Transform2D(xa, ya, center - (xa * (center.x + d.x) + ya * (center.y + d.y))))
	for sh in _radar_shapes:
		if sh[0] is PackedVector2Array:
			c.draw_colored_polygon(sh[0], sh[1])
		else:
			c.draw_circle(sh[0], sh[2], sh[1])
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	var obj = main.objectives()
	if obj != null and obj.objective_pos() != null:
		var lo: Vector3 = inv * ((obj.objective_pos() as Vector3) - ppos)
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
	if main.mode == "pvp" and main.saved_tdm:
		# teammates always show, in their side colour
		for f in get_tree().get_nodes_in_group("player"):
			if f == player or f.is_dead or f.team != player.team:
				continue
			var lf: Vector3 = inv * (f.global_position - ppos)
			var pf := center + Vector2(lf.x, lf.z) * sc
			if pf.distance_to(center) > radius - 4.0:
				pf = center + (pf - center).normalized() * (radius - 4.0)
			c.draw_circle(pf, 4.0, ALLY)
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


## Numbers pop up where the round landed, rise and fade. Gold = headshot,
## red = the shot that killed.
func _draw_damage_numbers(c: Control) -> void:
	if _dmg_nums.is_empty() or camera_rig == null:
		return
	var cam: Camera3D = camera_rig.active_camera()
	if cam == null:
		return
	for n in _dmg_nums:
		var t: float = n.t
		var p: Vector3 = n.pos + Vector3.UP * (0.25 + t * 0.9)
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - t / 0.12)
		var size := int((22.0 if n.head else 17.0) * pop)
		var col: Color = DANGER if n.kill else (WARN if n.head else Color(1, 1, 1))
		col.a = clampf((DMG_NUM_LIFE - t) / 0.35, 0.0, 1.0)
		var txt: String = n.text + ("!" if n.head else "")
		_text(c, sp + Vector2(-60 + 1.5, 1.5), txt, size, Color(0, 0, 0, col.a * 0.7), HORIZONTAL_ALIGNMENT_CENTER, 120, true)
		_text(c, sp + Vector2(-60, 0), txt, size, col, HORIZONTAL_ALIGNMENT_CENTER, 120, true)


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
	var col := crosshair_color()
	if player.hovered_enemy != null:
		# over an enemy: red, or yellow when the crosshair itself is red
		col = Color(Color(1.0, 0.85, 0.2) if int(Settings.v.crosshair_color) == 4 else Color(1.0, 0.35, 0.3), col.a)
	var ads: bool = player.first_person and player.rig.aim_amt > 0.7
	if player.is_scoped():
		_draw_scope(c, m, bool(player.current_weapon().stats.scope), bool(player.current_weapon().stats.get("ring", false)))
		return
	if ads:
		pass  # the weapon's own red dot / iron sights take over
	elif player.first_person and player.rig.aim_amt > 0.15:
		c.draw_circle(m, 1.6, Color(col, 1.0 - player.rig.aim_amt))
	else:
		draw_crosshair(c, m, r, col)
	if player.reload_timer > 0.0:
		var t: float = 1.0 - player.reload_timer / player.reload_duration
		c.draw_arc(m, r + 14.0, -PI * 0.5, -PI * 0.5 + TAU * t, 40, WARN, 2.5, true)
	if hit_marker > 0.0:
		var hc := DANGER if hit_kill else (WARN if hit_head else Color(1, 1, 1))
		hc.a = hit_marker / 0.25
		for k in 4:
			var d := Vector2(1, 1).normalized().rotated(k * PI * 0.5)
			c.draw_line(m + d * 9.0, m + d * 18.0, hc, 2.5, true)


## Crosshair colour and opacity from the settings.
func crosshair_color() -> Color:
	var base: Color = Settings.CROSSHAIR_RGB[clampi(int(Settings.v.crosshair_color), 0, Settings.CROSSHAIR_RGB.size() - 1)]
	return Color(base, float(Settings.v.crosshair_alpha))


## The chosen crosshair style at `m`. `spread_r` is the gap the weapon's
## spread asks for (ignored when "shows spread" is off).
func draw_crosshair(c: Control, m: Vector2, spread_r: float, col: Color) -> void:
	var style := int(Settings.v.crosshair)
	var s := float(Settings.v.crosshair_size)
	var gap: float = (spread_r if bool(Settings.v.crosshair_spread) else 7.0) * lerpf(1.0, s, 0.5)
	var arm := 8.0 * s
	var w := maxf(1.5 * s, 1.2)
	var outline := bool(Settings.v.crosshair_outline) and style != 8
	var oc := Color(0, 0, 0, col.a * 0.75) if col.get_luminance() > 0.25 else Color(1, 1, 1, col.a * 0.6)
	var shapes: Array = []   # [kind, args...] drawn twice: outline first, then colour
	match style:
		0:   # classic: small ring + four ticks that open with spread
			shapes.append(["ring", 3.5 * s])
			for k in 4:
				shapes.append(["tick", Vector2.RIGHT.rotated(k * PI * 0.5), gap, arm])
		1:   # dot
			shapes.append(["dot", 2.2 * s])
		2, 3:   # cross (+ dot)
			for k in 4:
				shapes.append(["tick", Vector2.RIGHT.rotated(k * PI * 0.5), gap * 0.6, arm])
			if style == 3:
				shapes.append(["dot", 1.6 * s])
		4, 5:   # circle (+ dot)
			shapes.append(["ring", maxf(gap, 9.0 * s)])
			if style == 5:
				shapes.append(["dot", 1.6 * s])
		6:   # T: no top arm
			for k in [0, 1, 2]:
				shapes.append(["tick", Vector2.RIGHT.rotated(k * PI * 0.5), gap * 0.6, arm])
		7:   # chevron
			shapes.append(["chevron", 7.0 * s])
		_:
			return   # none
	for pass_i in (2 if outline else 1):
		var o := pass_i == 0 and outline
		var cc := oc if o else col
		var ww := w + (2.0 if o else 0.0)
		for sh in shapes:
			match String(sh[0]):
				"dot":
					c.draw_circle(m, float(sh[1]) + (1.0 if o else 0.0), cc)
				"ring":
					c.draw_arc(m, float(sh[1]), 0, TAU, 32, cc, ww, true)
				"tick":
					var d: Vector2 = sh[1]
					var a := m + d * float(sh[2]) - (d * 1.0 if o else Vector2.ZERO)
					var b := m + d * (float(sh[2]) + float(sh[3])) + (d * 1.0 if o else Vector2.ZERO)
					c.draw_line(a, b, cc, ww, true)
				"chevron":
					var h := float(sh[1])
					c.draw_polyline(PackedVector2Array([m + Vector2(-h, h * 0.7), m, m + Vector2(h, h * 0.7)]), cc, ww, true)


func _draw_scope(c: Control, m: Vector2, sniper: bool, ring: bool = false) -> void:
	var vp := c.size
	var r := vp.y * (0.44 if sniper else 0.4)
	c.draw_arc(m, r + vp.x, 0, TAU, 96, Color.BLACK, vp.x * 2.0)
	c.draw_arc(m, r, 0, TAU, 96, Color(0, 0, 0, 0.9), 10.0, true)
	c.draw_arc(m, r - 18.0, 0, TAU, 96, Color(0, 0, 0, 0.35), 26.0, true)
	var col := Color(0, 0, 0, 0.9)
	if ring:
		# AUG 1.5x: a black ring sized to a man at 300 m, with a fine centre dot
		c.draw_arc(m, r * 0.11, 0, TAU, 64, col, 3.0, true)
		c.draw_circle(m, 1.6, col)
		return
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
	if not main.is_zombie_mode() and main.mode != "pvp":
		_draw_awareness_markers(c)
		return
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


# ---------------------------------------------------------------- stealth HUD

const Stealth = preload("res://scripts/stealth/stealth.gd")
const STEALTH_GLYPH := {1: "?", 4: "?", 3: "?", 5: "!"}   # SUSPICIOUS, INVESTIGATE, SEARCH, ALERTED


## Colour of a guard's suspicion: white while it builds, amber, then red.
func _awareness_color(aw: float) -> Color:
	return Color(1, 1, 1).lerp(WARN, smoothstep(0.1, 0.5, aw)).lerp(DANGER, smoothstep(0.6, 1.0, aw))


## Over each guard who is noticing you, or who is checking something / searching:
## a ring that fills with his suspicion and a ? or !. Guards noticing you from
## off screen get a small arrow on a ring round the crosshair. In first person only
## guards you have spotted, or who are noticing you right now, are marked.
func _draw_awareness_markers(c: Control) -> void:
	var cam: Camera3D = camera_rig.active_camera()
	var vp := c.size
	var screen := Rect2(Vector2.ZERO, vp).grow(-24.0)
	for e in main.enemies:
		if e.is_dead or e.get("dummy") == true:
			continue
		var st := int(e.state)
		var aw := float(e.awareness)
		var noticing: bool = e.sees_player and aw > 0.03 and not e.is_in_combat()
		if player.first_person and not _spotted.has(e) and not noticing:
			continue
		var head: Vector3 = e.global_position + Vector3(0, 2.25, 0)
		var behind := cam.is_position_behind(head)
		var p := Vector2.ZERO if behind else cam.unproject_position(head)
		if behind or not screen.has_point(p):
			if noticing:
				var rel: Vector3 = cam.global_transform.affine_inverse() * e.global_position
				var dir := Vector2(rel.x, rel.z).normalized()
				var at := vp * 0.5 + dir * 110.0
				var col := _awareness_color(aw)
				var tip := at + dir * 10.0
				var side := Vector2(-dir.y, dir.x) * 7.0
				c.draw_colored_polygon(PackedVector2Array([tip, at - dir * 4.0 + side, at - dir * 4.0 - side]), Color(col, 0.35 + 0.65 * aw))
			continue
		if e.is_in_combat():
			if e.alert_flash > 0.0:
				_text(c, p + Vector2(-7, 0), "!", 28, Color(DANGER, minf(e.alert_flash, 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			continue
		if aw <= 0.02 and not STEALTH_GLYPH.has(st):
			continue
		var col := _awareness_color(aw)
		if st == 5:
			col = Color(1.0, 0.55, 0.2)
		c.draw_arc(p, 11.0, 0.0, TAU, 28, Color(0, 0, 0, 0.45), 4.0, true)
		if aw > 0.0:
			c.draw_arc(p, 11.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(aw, 0.0, 1.0), 28, col, 3.0, true)
		_text(c, p + Vector2(-5, 6), String(STEALTH_GLYPH.get(st, "?")), 15, col, HORIZONTAL_ALIGNMENT_LEFT, -1, true)


## One line under the objective: how aware the area is of you.
func _draw_stealth_status(c: Control, vp: Vector2) -> void:
	var worst := 0
	var labels := ["UNDETECTED", "SUSPICIOUS", "INVESTIGATING", "SEARCHING", "ALERTED", "COMBAT"]
	var rank := {0: 0, 1: 1, 4: 2, 3: 3, 5: 4, 2: 5}   # state -> severity
	for e in main.enemies:
		if e.is_dead or e.get("dummy") == true:
			continue
		worst = maxi(worst, int(rank.get(int(e.state), 0)))
	var cols := [Color(0.55, 0.85, 0.6), Color(1, 1, 1), WARN, WARN, Color(1.0, 0.55, 0.2), DANGER]
	var line := String(labels[worst])
	if Stealth.bodies_found > 0:
		line += "   ·   BODIES FOUND %d" % Stealth.bodies_found
	_text(c, Vector2(0, 126), line, 11, Color(cols[worst], 0.9), HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


## Takedown / body prompts near the middle of the screen. True when one is shown.
func _draw_stealth_prompt(c: Control, vp: Vector2) -> bool:
	var f := Settings.Controls.short("interact")
	var v := Settings.Controls.short("kick")
	var text := ""
	var sub := ""
	var frac := -1.0
	if player.is_taking_down():
		text = "TAKEDOWN" if player.takedown_lethal else "KNOCKING OUT..."
		frac = player._td_t / (player.TD_TIME_KILL if player.takedown_lethal else player.TD_TIME_KO)
	elif player.dragging != null:
		var hidden := Stealth.body_hidden(main.level, player.dragging)
		text = "[%s]  PUT DOWN BODY" % f
		sub = "HIDDEN SPOT" if hidden else "IN THE OPEN  ·  BUSHES AND SHADOWS HIDE IT"
	elif player.td_candidate != null:
		text = "[%s]  KNOCK OUT     [%s]  KILL" % [f, v]
		sub = "SILENT  ·  FROM BEHIND"
	elif player.body_candidate != null:
		text = "[%s]  DRAG BODY" % f
	else:
		return false
	var r := Rect2(vp.x * 0.5 - 170, vp.y * 0.64, 340, 40 if sub == "" and frac < 0.0 else 52)
	c.draw_rect(r, Color(0, 0, 0, 0.55))
	_brackets(c, r, 8.0, ACCENT, 2.0)
	_text(c, Vector2(r.position.x, r.position.y + 18), text, 15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	if sub != "":
		_text(c, Vector2(r.position.x, r.position.y + 38), sub, 11, ACCENT if sub == "HIDDEN SPOT" else DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	if frac >= 0.0:
		c.draw_rect(Rect2(r.position.x + 12, r.end.y - 11, r.size.x - 24, 4), Color(1, 1, 1, 0.12))
		c.draw_rect(Rect2(r.position.x + 12, r.end.y - 11, (r.size.x - 24) * clampf(frac, 0.0, 1.0), 4), ACCENT)
	return true


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

## The gunsmith opens mid-match in every mode; Zombie Survival also keeps its
## own supply shop.
func _gunsmith_in_match() -> bool:
	return true


func _pause_items() -> Array:
	var its := _pause_items_base()
	if _gunsmith_in_match():
		its.insert(2, "GUNSMITH")
		its.insert(3, "LOADOUT  ·  SKINS")
	return its


func _pause_items_base() -> Array:
	if Net.active and Net.is_server() and Net.transport == "ws":
		return ["RESUME", "SETTINGS", "COPY INVITE LINK  ·  ONLINE", "RESTART MATCH", "LEAVE GAME"]
	if Net.active and Net.is_server():
		var its: Array = ["RESUME", "SETTINGS"]
		for a in Net.host_addresses():
			if String(a.code) != "":
				its.append("COPY JOIN CODE  ·  %s  ·  %s" % [String(a.code), String(a.label)])
			else:
				its.append("COPY INVITE LINK  ·  LAN")
		its.append_array(["COPY INVITE LINK  ·  INTERNET", "RESTART MATCH", "LEAVE GAME"])
		return its
	if Net.active:
		return ["RESUME", "SETTINGS", "RESTART  (HOST ONLY)", "LEAVE GAME"]
	return PAUSE_ITEMS.duplicate()


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
	var icode := Net.join_code(Net.public_ip, Net.port)
	if icode != "":
		add_feed("INTERNET JOIN CODE  ·  %s" % icode, ACCENT)
	match Net.upnp_state:
		"open":
			add_feed("ROUTER PORT %d OPENED AUTOMATICALLY  ·  FRIENDS CAN JOIN DIRECTLY" % Net.port, ACCENT)
		"busy":
			add_feed("STILL ASKING YOUR ROUTER TO OPEN UDP PORT %d  ·  TRY AGAIN IN A MOMENT" % Net.port, WARN)
		_:
			add_feed("ROUTER DID NOT OPEN UDP PORT %d (UPnP OFF?)  ·  FORWARD IT OR HOST ONLINE" % Net.port, WARN)


# ================================================================ zombie shop

func _shop_available() -> bool:
	var d = main.director if main != null else null
	return d != null and not d.active and _deployed_hud() and player != null and not player.is_dead and not main.game_over 			and main.arcade != null and main.arcade.in_reach(player)


## Where the shop is: the key when the arcade is in reach, its distance otherwise.
func _arcade_hint() -> String:
	var a = main.arcade
	if a == null or not a.placed or player == null:
		return "SHOP AT THE ARCADE"
	if a.in_reach(player):
		return "[%s] OPEN SHOP" % Settings.Controls.short("interact")
	return "ARCADE SHOP  %d M" % int(round(player.global_position.distance_to(a.global_position)))


func _deployed_hud() -> bool:
	return not title and bool(main.get("_deployed"))


func _open_shop() -> void:
	shop_open = true
	shop_index = 0
	_shop_scroll = 0
	_shop_follow = true
	main.director.shop.fit_to = ""   # attachments start on the gun in hand
	shop_preview.set_active(true)
	main.director.shop_open = true
	player.rig.cancel_inspect()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play(player, "mag_in", player.global_position, -4.0, 0.0)


func _close_shop() -> void:
	shop_open = false
	shop_preview.set_active(false)
	if main.director != null:
		main.director.shop_open = false
	if player != null and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if player.first_person else Input.MOUSE_MODE_CONFINED_HIDDEN


func _shop_rows_now() -> Array:
	var rows: Array = main.director.shop.items(player)
	# solo / host: skip the rest of the break
	if not Net.active or Net.is_server():
		rows.append({"id": "start", "section": "", "label": "START NEXT WAVE", "desc": "", "price": 0, "ok": true, "note": "", "afford": true})
	return rows


func _shop_activate(i: int) -> void:
	var rows := _shop_rows_now()
	if i < 0 or i >= rows.size():
		return
	var r: Dictionary = rows[i]
	if r.id == "start":
		main.director.timer = 0.0
		_close_shop()
		return
	if r.id == "fit_to":
		main.director.shop.cycle_fit(player, 1)
		Sfx.play(player, "switch", player.global_position, -10.0, 0.0)
		return
	var msg: String = main.director.shop.buy(String(r.id), player)
	if msg == "":
		_shop_msg = "ALREADY OWNED" if String(r.note) != "" else ("NOT ENOUGH POINTS" if not bool(r.afford) else "NOT NEEDED RIGHT NOW")
		_shop_msg_t = 1.6
		Sfx.play(player, "dry", player.global_position, -6.0, 0.0)
		return
	_shop_msg = msg
	_shop_msg_t = 2.0
	add_feed(msg, Color(1.0, 0.82, 0.35))
	main.refresh_ammo()
	Sfx.play(player, "mag_in", player.global_position, 0.0, 0.05)


func _shop_input(event: InputEvent) -> void:
	var n := _shop_rows_now().size()
	if event.is_action_pressed("shop") or event.is_action_pressed("interact") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_close_shop()
	elif shop_preview.handle(event):
		pass   # turning / zooming the gun
	elif event.is_action_pressed("reload"):
		shop_preview.reset_view()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# the wheel scrolls the list; the selection stays where the mouse points
		_shop_scroll += -3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 3
		_shop_follow = false
	elif (event.is_action_pressed("ui_left") or event.is_action_pressed("move_left") or event.is_action_pressed("ui_right") \
			or event.is_action_pressed("move_right")) and String(_shop_rows_now()[clampi(shop_index, 0, n - 1)].id) == "fit_to":
		var dir := -1 if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left") else 1
		main.director.shop.cycle_fit(player, dir)
		Sfx.play(player, "switch", player.global_position, -10.0, 0.0)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		shop_index = posmod(shop_index - 1, n)
		_shop_follow = true
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		shop_index = posmod(shop_index + 1, n)
		_shop_follow = true
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("vault"):
		_shop_activate(shop_index)
	elif event is InputEventMouseMotion:
		# hovering picks a row but never scrolls: a list that moved under the pointer picked the next row, and so on
		for i in _shop_rects.size():
			if (_shop_rects[i] as Rect2).has_point(event.position):
				shop_index = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _shop_rects.size():
			if (_shop_rects[i] as Rect2).has_point(event.position):
				shop_index = i
				_shop_activate(i)
	get_viewport().set_input_as_handled()


## The gun a shop row is about, as [id, attachments, the carried gun it is compared with]: a gun or SMG as it is sold
## (bare, against the gun in hand); an upgrade, the FIT TO row or an attachment on its own gun (an attachment
## fitted); anything else the gun in hand as it is.
func _shop_row_gun(r: Dictionary) -> Array:
	var id := String(r.id)
	var shop = main.director.shop
	if id.begins_with("gun_") or id.begins_with("smg_"):
		var gid := id.substr(4)
		return [gid, WData.sanitize(gid, {}), player.current_weapon()]
	var w = player.current_weapon()
	if id.begins_with("upgrade:"):
		for g in shop.guns(player):
			if String(g.id) == id.substr(8):
				w = g
	elif id == "fit_to" or id.begins_with("att_"):
		w = shop.fit_gun(player)
	var att: Dictionary = (w.attachments as Dictionary).duplicate()
	if id.begins_with("att_"):
		var part := id.substr(4).split(":")   # gun, slot, option
		att[part[1]] = part[2]
	return [String(w.id), WData.sanitize(String(w.id), att), w]


func _draw_shop(c: Control, vp: Vector2) -> void:
	var d = main.director
	var rows := _shop_rows_now()
	shop_index = clampi(shop_index, 0, rows.size() - 1)
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.025, 0.03, 0.97))   # nothing of the HUD shows through
	_text(c, Vector2(70, 70), "ARCADE SHOP  //  SUPPLIES", 26, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_text(c, Vector2(0, 70), "%d PTS" % d.shop.points, 26, WARN, HORIZONTAL_ALIGNMENT_RIGHT, vp.x - 70.0, true)
	var sub := "NEXT WAVE IN %d" % int(ceil(d.timer))
	if not Net.active:
		sub += "  ·  CLOCK STOPPED WHILE SHOPPING"
	_text(c, Vector2(70, 96), sub, 13, DIM)

	# --- the list (left), scrolling
	var lx := 70.0
	var lw := vp.x * 0.42 - 110.0
	var top := 140.0
	var row_h := 30.0
	var lines: Array = []   # [row index or -1 for a header, section name]
	var section0 := ""
	for i in rows.size():
		var sec := String(rows[i].section)
		if sec != section0 and sec != "":
			section0 = sec
			lines.append([-1, sec])
		lines.append([i, sec])
	var cap := maxi(6, int((vp.y - 70.0 - top) / row_h))
	var sel_line := 0
	for k in lines.size():
		if int(lines[k][0]) == shop_index:
			sel_line = k
	if _shop_follow:
		if sel_line < _shop_scroll:
			_shop_scroll = sel_line
		elif sel_line >= _shop_scroll + cap:
			_shop_scroll = sel_line - cap + 1
	_shop_scroll = clampi(_shop_scroll, 0, maxi(0, lines.size() - cap))
	_shop_rects.clear()
	for i in rows.size():
		_shop_rects.append(Rect2())   # rows scrolled out of view take no clicks
	if _shop_scroll > 0:
		_text(c, Vector2(lx, top - 8), "▲  MORE", 10, DIM, HORIZONTAL_ALIGNMENT_RIGHT, lw)
	var y := top
	for ln in lines.slice(_shop_scroll, _shop_scroll + cap):
		var i: int = ln[0]
		if i < 0:
			_text(c, Vector2(lx, y + row_h * 0.72), String(ln[1]), 11, Color(ACCENT, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, true)
			y += row_h
			continue
		var r: Dictionary = rows[i]
		var rect := Rect2(lx, y, lw, row_h - 4.0)
		_shop_rects[i] = rect
		var sel := i == shop_index
		if sel:
			c.draw_rect(rect, Color(RED, 0.22))
			_brackets(c, rect, 8.0, RED, 1.5)
		var ok := bool(r.ok)
		if r.id == "start":
			_text(c, Vector2(rect.position.x, rect.position.y + row_h * 0.64), "START NEXT WAVE  ▶", 15, TEXT if sel else WARN, HORIZONTAL_ALIGNMENT_CENTER, lw, true)
		else:
			_text(c, Vector2(rect.position.x + 10, rect.position.y + row_h * 0.64), String(r.label), 14, TEXT if ok else Color(DIM, 0.7), HORIZONTAL_ALIGNMENT_LEFT, lw - 90.0, true)
			var tag: String = String(r.note) if String(r.note) != "" else "%d" % int(r.price)
			var tcol := Color(DIM, 0.8) if String(r.note) != "" else (WARN if bool(r.afford) else DANGER)
			_text(c, Vector2(rect.position.x, rect.position.y + row_h * 0.64), tag, 14, tcol, HORIZONTAL_ALIGNMENT_RIGHT, lw - 10.0, true)
		y += row_h
	if _shop_scroll + cap < lines.size():
		_text(c, Vector2(lx, y + 12), "▼  MORE", 10, DIM, HORIZONTAL_ALIGNMENT_RIGHT, lw)

	# --- the selected row (right): its gun on the turntable, what it does, the stats against the gun in hand
	var r2: Dictionary = rows[shop_index]
	var g := _shop_row_gun(r2)
	var gid := String(g[0])
	shop_preview.show_weapon(gid, g[1], Collection.skin_for(gid), Collection.parts_for(gid))
	var pr := Rect2(vp.x * 0.42, 110, vp.x * 0.54, vp.x * 0.27)
	c.draw_rect(pr, Color(0.06, 0.07, 0.08, 0.8))
	_brackets(c, pr, 18.0, Color(TEXT, 0.4), 1.5)
	shop_preview.draw(c, pr)
	var title := "START NEXT WAVE" if r2.id == "start" else String(r2.label)
	_text(c, pr.position + Vector2(18, 34), title, 24, TEXT, HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 36.0, true)
	_text(c, pr.position + Vector2(18, 56), String(r2.desc), 12, DIM, HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 36.0)
	if r2.id != "start":
		var price := ""
		var pcol := WARN
		if String(r2.note) != "":
			price = String(r2.note)
			pcol = DIM
		elif bool(r2.ok):
			price = "%d PTS  ·  [ENTER] OR CLICK TO BUY" % int(r2.price)
		else:
			price = "%d PTS  ·  NOT ENOUGH POINTS" % int(r2.price)
			pcol = DANGER
		_text(c, pr.position + Vector2(18, 78), price, 12, pcol, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_text(c, Vector2(pr.position.x + 18, pr.end.y - 14), "Drag to rotate  ·  Wheel to zoom  ·  [%s] reset view" % Settings.Controls.short("reload"), 12, DIM)
	var held = g[2]
	var st: Dictionary = WData.compute(gid, g[1])
	var ref: Dictionary = WData.compute(String(held.id), held.attachments)
	gunsmith.draw_stats(c, st, ref, Vector2(pr.position.x, pr.end.y + 34.0), pr.size.x,
			"Green = better than your %s as it is now, red = worse." % String(held.stats.name))
	if _shop_msg_t > 0.0:
		_text(c, Vector2(pr.position.x, vp.y - 56), _shop_msg, 14, Color(WARN, clampf(_shop_msg_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_LEFT, pr.size.x, true)
	_text(c, Vector2(0, vp.y - 30), "W/S or mouse select   ·   Wheel scroll   ·   Enter / click buy   ·   [%s] or Esc close" % Settings.Controls.short("interact"), 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## A gunsmith pick in a solo match: the operator is re-issued the loadout at
## once, so the gun in hand changes live. Multiplayer waits for the respawn.
func gunsmith_live_update() -> void:
	if title or Net.active or player == null or player.is_dead:
		return
	if main.director != null:
		_reissue_loadout()
	else:
		player.apply_loadout(true)   # only the gun that changed is rebuilt


## Re-issues the operator's guns. In Zombie Survival the shop's list (bare guns,
## attachments bought this run) keeping ammo, upgrades and perks; else the loadout.
func _reissue_loadout() -> void:
	if main.director != null:
		main.director.shop.reissue(player, player.weapon_index)
	else:
		player.apply_loadout()


## Back from the gunsmith to the pause menu. Solo the new loadout is issued at
## once; in multiplayer it waits for the next respawn so nobody swaps guns
## mid-fight.
func _gunsmith_closed_in_match() -> void:
	if Net.active:
		add_feed("LOADOUT SAVED  ·  YOU DEPLOY WITH IT ON YOUR NEXT RESPAWN", ACCENT)
	elif player != null and not player.is_dead:
		_reissue_loadout()
		add_feed("LOADOUT UPDATED" if main.director == null else "LOADOUT UPDATED  ·  ATTACHMENTS ARE BOUGHT AT THE ARCADE", ACCENT)


## Applies equipped finishes without rebuilding the inventory (Zombie Survival
## weapons may carry run upgrades), then syncs updated specs to teammates.
func _apply_armory_skins_in_match() -> void:
	if player == null:
		return
	for w in player.weapons:
		if not is_instance_valid(w):
			continue
		var weapon_id := String(w.id)
		w.apply_skin(Collection.skin_for(weapon_id), Collection.parts_for(weapon_id))
		w.apply_sticker(Collection.sticker_for(weapon_id))
	if not PlayerScript.zombie_specs.is_empty():
		for i in PlayerScript.zombie_specs.size():
			var spec = PlayerScript.zombie_specs[i]
			if spec is Array and not spec.is_empty():
				var spec_weapon_id := String(spec[0])
				if spec.size() > 2:
					spec[2] = Collection.skin_for(spec_weapon_id)
				if spec.size() > 3:
					spec[3] = Collection.sticker_for(spec_weapon_id)
				if spec.size() > 5:
					spec[5] = Collection.parts_for(spec_weapon_id)
		if Net.active and Net.is_server():
			Net.roster[1] = {"name": Net.default_name(), "loadout": PlayerScript.net_loadout()}
	if Net.active and Net.sync != null:
		Net.sync.send_event(player, "loadout", [PlayerScript.net_loadout()])
	add_feed("EQUIPPED SKINS APPLIED", ACCENT)


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
	elif item == "GUNSMITH":
		gunsmith.open()
	elif item == "LOADOUT  ·  SKINS":
		armory.open()
	elif item.begins_with("COPY JOIN CODE"):
		var code := String(item.split("  ·  ")[1])
		DisplayServer.clipboard_set(code)
		add_feed("JOIN CODE COPIED  ·  %s  ·  FRIENDS TYPE IT UNDER MULTIPLAYER > JOIN" % code, ACCENT)
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


## Action waiting for its new key on the CONTROLS tab ("" = none).
var _binding := ""


func _settings_input(event: InputEvent) -> void:
	var rows: Array = Settings.rows(settings_tab)
	var n: int = rows.size() + 1
	if _binding != "":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_binding = ""
			elif Settings.Controls.rebind(_binding, event):
				_binding = ""
				Sfx.play(player, "mag_in", player.global_position, -4.0, 0.0)
		elif event is InputEventMouseButton and event.pressed:
			if Settings.Controls.rebind(_binding, event):
				_binding = ""
				Sfx.play(player, "mag_in", player.global_position, -4.0, 0.0)
		get_viewport().set_input_as_handled()
		return
	var on_bind: bool = settings_row < rows.size() and Settings.is_bind(rows[settings_row])
	if on_bind and (event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER])):
		_bind_row(rows[settings_row])
		return
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
					elif Settings.is_bind(rows[idx]):
						_bind_row(rows[idx])
					else:
						_settings_adjust(rows[idx], -1 if event.position.x < r.position.x + r.size.x * 0.5 else 1)


## Visible rect i -> row index (rects cover the scrolled window, then BACK).
func _settings_rects_index(i: int, row_count: int) -> int:
	return mini(int(_settings_idx[i]) if i < _settings_idx.size() else row_count, row_count)


## Enter on a CONTROLS row: wait for a key, or reset everything.
func _bind_row(row: Array) -> void:
	if String(row[2]) == "reset":
		Settings.Controls.reset_all()
		Sfx.play(player, "mag_in", player.global_position, -4.0, 0.0)
		return
	_binding = String(row[0])


func _settings_set_tab(t: int) -> void:
	_binding = ""
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
			if Settings.is_bind(row):
				var clash: Array = Settings.Controls.conflicts(String(row[0])) if row[2] == "bind" else []
				if _binding == String(row[0]):
					val = "PRESS A KEY OR MOUSE BUTTON  ·  ESC CANCEL"
				elif not clash.is_empty():
					val = val + "   (ALSO " + String(clash[0]) + ")"
				_text(c, Vector2(x0, y), val, 15, WARN if _binding == String(row[0]) else (DANGER if not clash.is_empty() else (TEXT if not sel else WARN)), HORIZONTAL_ALIGNMENT_RIGHT, w - 14, true)
			else:
				_text(c, Vector2(x0, y), ("<  " + val + "  >") if sel else val, 15, WARN if sel else TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w - 14, true)
			var k := Settings.slider_frac(row)
			if k >= 0.0:
				var bx := x0 + w * 0.47
				c.draw_rect(Rect2(bx, y - 7, w * 0.25, 4), Color(1, 1, 1, 0.1))
				c.draw_rect(Rect2(bx, y - 7, w * 0.25 * k, 4), ACCENT if sel else Color(TEXT, 0.6))
		else:
			_text(c, Vector2(x0 + 14, y), "SAVE & BACK", 15, TEXT if sel else DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		y += row_h
	if settings_row < rows.size() and String(rows[settings_row][0]).begins_with("crosshair"):
		_draw_crosshair_preview(c, Rect2(x0 + w + 24.0, vp.y * 0.11 + 84.0, 200.0, 200.0))
	var hint := "Q/E or LB/RB tabs   ·   W/S select   ·   A/D or click adjust   ·   Esc / B back"
	if Settings.TABS[settings_tab] == "CONTROLS":
		hint = "Q/E tabs   ·   W/S select   ·   Enter or click  rebind   ·   Esc back   ·   controller buttons stay as they are"
	_text(c, Vector2(0, vp.y - 30), hint, 13, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Crosshair preview on a light and a dark backdrop, with the spread gap
## breathing so the effect of every option is visible.
func _draw_crosshair_preview(c: Control, r: Rect2) -> void:
	if r.end.x > c.size.x - 10.0:
		r.position.x = c.size.x - r.size.x - 10.0
	var half := Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y))
	c.draw_rect(half, Color(0.72, 0.74, 0.7))
	c.draw_rect(Rect2(half.position + Vector2(half.size.x, 0), half.size), Color(0.08, 0.09, 0.1))
	c.draw_rect(r, Color(ACCENT, 0.5), false, 1.5)
	_text(c, r.position + Vector2(0, -8), "PREVIEW", 12, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	var spread := 8.0 + 10.0 * (0.5 + 0.5 * sin(_time * 2.0))
	draw_crosshair(c, r.position + Vector2(r.size.x * 0.25, r.size.y * 0.5), spread, crosshair_color())
	draw_crosshair(c, r.position + Vector2(r.size.x * 0.75, r.size.y * 0.5), spread, crosshair_color())


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
	_mp_replace_join_text = true
	Net.port = int(Settings.v.get("mp_port", Net.port))
	_mp_port_text = str(Net.port)
	_mp_coop_mode = main.mode_token() if main.mode_token() in _mp_coop_options() else "ch1"
	_mp_pvp_map = main.map_id if main.map_available(main.map_id) else "forest"


## Co-op host choices: each campaign chapter, then Zombie Survival on every map
## ("zombie" = Pinewood Valley, "zombie@town" = Dead End, ...).
func _mp_coop_options() -> Array:
	var out: Array = []
	for m in MODES:
		if m != "zombie":
			out.append(m)
	for id in main.playable_maps():
		out.append("zombie" if id == "forest" else "zombie@" + String(id))
	return out


func _mp_coop_label(token: String) -> String:
	var parts := token.split("@")
	if parts[0] != "zombie":
		return _mode_label(token)
	var map_id := parts[1] if parts.size() > 1 else "forest"
	return "ZOMBIE SURVIVAL  ·  " + String(main.MAPS.get(map_id, map_id))


func _mp_input_port() -> int:
	return clampi(int(_mp_port_text) if _mp_port_text.is_valid_int() else Net.DEFAULT_PORT, 1024, 65535)


func _mp_save() -> void:
	Net.port = _mp_input_port()
	_mp_port_text = str(Net.port)
	Settings.v.mp_name = Net.player_name
	Settings.v.mp_ip = Net.join_ip
	Settings.v.mp_port = Net.port
	Settings.save()


func _mp_items() -> Array:
	var cur := "_" if int(_time * 2.0) % 2 == 0 else " "
	return [
		"NAME:  " + Net.player_name + (cur if mp_row == 0 else ""),
		"HOST CO-OP:  " + _mp_coop_label(_mp_coop_mode),
		"HOST PVP DEATHMATCH:  " + String(main.MAPS[_mp_pvp_map]),
		"JOIN  (CODE, IP OR LINK):  " + Net.join_ip + (cur if mp_row == 3 else ""),
		"PORT:  " + _mp_port_text + (cur if mp_row == 4 else ""),
		"CONNECTION:  " + ("ONLINE  ·  TAILSCALE FUNNEL" if mp_online else "DIRECT  ·  LAN / UDP"),
		"BACK",
		"HOST TEAM DEATHMATCH",
		"AI BOTS:  " + ("OFF" if _mp_tdm_bots == 0 else str(_mp_tdm_bots)),
	]


func _mp_activate(i: int, dir: int = 0) -> void:
	match i:
		7:
			_mp_save()
			if Net.host("pvp", Net.port, mp_online) == OK:
				main.net_enter_world("tdm%d@%s" % [_mp_tdm_bots, _mp_pvp_map])
		8:
			_mp_tdm_bots = posmod(_mp_tdm_bots + (2 * dir if dir != 0 else 2), 10)
		0:
			mp_row = 1
		1:
			if dir != 0:
				var opts := _mp_coop_options()
				_mp_coop_mode = opts[posmod(opts.find(_mp_coop_mode) + dir, opts.size())]
				return
			_mp_save()
			if Net.host("coop", Net.port, mp_online) == OK:
				main.net_enter_world(_mp_coop_mode)
		2:
			if dir != 0:
				var ids: Array = main.playable_maps()
				_mp_pvp_map = ids[posmod(ids.find(_mp_pvp_map) + dir, ids.size())]
				return
			_mp_save()
			if Net.host("pvp", Net.port, mp_online) == OK:
				main.net_enter_world("pvp" + ("@" + _mp_pvp_map if _mp_pvp_map != "forest" else ""))
		3, 4:
			var inv := Net.parse_invite(Net.join_ip, _mp_input_port())
			if inv.is_empty():
				Net.status = "ENTER A JOIN CODE, IP ADDRESS OR INVITE LINK"
				return
			Net.join_ip = String(inv[0])
			_mp_replace_join_text = true
			if int(inv[1]) > 0:
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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _open_rooms_rect.has_point(event.position):
		room_browser.open()
		return
	# typing into the text rows (name / IP / port)
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_V and mp_row in [3, 4]:
		var inv := Net.parse_invite(DisplayServer.clipboard_get(), _mp_input_port())
		if not inv.is_empty():
			Net.join_ip = String(inv[0])
			_mp_replace_join_text = false
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
					Net.join_ip = "" if _mp_replace_join_text else Net.join_ip.substr(0, maxi(Net.join_ip.length() - 1, 0))
					_mp_replace_join_text = false
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
					if _mp_replace_join_text:
						Net.join_ip = ""
						_mp_replace_join_text = false
					if Net.join_ip.length() < 120 and ch != " ":
						Net.join_ip += ch
				4:
					if _mp_port_text.length() < 5 and ch.is_valid_int():
						_mp_port_text += ch
			return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_mp_activate(6)
	elif event.is_action_pressed("ui_up"):
		mp_row = posmod(mp_row - 1, _mp_items().size())
	elif event.is_action_pressed("ui_down"):
		mp_row = posmod(mp_row + 1, _mp_items().size())
	elif (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")) and mp_row == 5:
		_mp_activate(5)
	elif event.is_action_pressed("ui_left") and mp_row in [1, 2, 8]:
		_mp_activate(mp_row, -1)
	elif event.is_action_pressed("ui_right") and mp_row in [1, 2, 8]:
		_mp_activate(mp_row, 1)
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
	_open_rooms_rect = Rect2(vp.x - 280, 50, 220, 44)
	c.draw_rect(_open_rooms_rect, Color(ACCENT, 0.18))
	_text(c, _open_rooms_rect.position + Vector2(0, 28), "OPEN ROOMS  →", 16, ACCENT, HORIZONTAL_ALIGNMENT_CENTER, _open_rooms_rect.size.x, true)
	_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.2), minf(vp.x * 0.4, 600.0), 0.95)
	_text(c, Vector2(0, vp.y * 0.36), "MULTIPLAYER", 30, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_text(c, Vector2(0, vp.y * 0.36 + 24), "CO-OP: CAMPAIGN CHAPTERS OR ZOMBIE SURVIVAL TOGETHER   ·   PVP: FREE-FOR-ALL, FIRST TO %d" % main.PVP_KILL_LIMIT, 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	var items := _mp_items()
	_mp_rects.clear()
	var top := vp.y * 0.40
	for i in items.size():
		var r := Rect2(vp.x * 0.5 - 230, top + i * 34 - 28, 460, 30)
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
		_text(c, Vector2(0, top + items.size() * 34 + 6), st, 14, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	# what the host will tell friends, shown before they even start
	var cy := vp.y - 104.0
	var preview: Array = [] if mp_online else Net.host_addresses()
	var shown := 0
	for a in preview:
		if String(a.code) == "":
			continue
		_text(c, Vector2(0, cy), "YOUR JOIN CODE  ·  %s  ·  %s" % [String(a.code), String(a.label)], 15, ACCENT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
		cy += 20.0
		shown += 1
	if shown == 0 and not mp_online:
		_text(c, Vector2(0, cy), "JOIN CODES NEED THE DEFAULT PORT %d" % Net.DEFAULT_PORT, 12, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_text(c, Vector2(0, vp.y - 58), "HOST: start a game and tell friends your join code (same Wi-Fi or same Tailscale network)   ·   over the internet: forward UDP port %s" % _mp_port_text, 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_text(c, Vector2(0, vp.y - 40), "JOIN: select JOIN, type the code, press Enter   ·   Up/Down select   ·   Ctrl+V paste   ·   Esc back", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


## Host's join codes, refreshed every few seconds (adapters can change).
var _host_codes: Array = []
var _host_codes_t := 0.0


## Squad (co-op HP) or scoreboard (PvP), top-left.
func _draw_squad(c: Control, vp: Vector2) -> void:
	var x := 26.0
	var y := 150.0
	if Net.is_server() and Net.transport == "enet":
		if _host_codes_t <= 0.0:
			_host_codes = Net.host_addresses()
			_host_codes_t = 5.0
		var jy := 118.0
		for a in _host_codes:
			if String(a.code) != "":
				_text(c, Vector2(x, jy), "JOIN CODE  %s" % String(a.code), 13, ACCENT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
				_text(c, Vector2(x + 150, jy), String(a.label), 10, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
				jy += 16.0
	if main.mode == "pvp":
		_draw_pvp_scoreboard(c, Vector2(x, y))
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
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.6))
	_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.2), minf(vp.x * 0.3, 460.0), 0.9)
	var w: int = main.pvp_winner
	var head := "MATCH OVER"
	var head_col := WARN
	var sub := ""
	var sub_col := TEXT
	if main.saved_tdm:
		var mine: int = player.team
		var ours: int = main.team_scores[mine]
		var theirs: int = main.team_scores[1 - mine]
		head = "DRAW" if w < 0 else ("YOUR TEAM WINS" if w == mine else "YOUR TEAM LOST")
		head_col = WARN if w < 0 else (ACCENT if w == mine else DANGER)
		sub = "%d  :  %d" % [ours, theirs]
	else:
		var rank: int = main.pvp_ranked().find(Net.my_id()) + 1
		head = "VICTORY" if w == Net.my_id() else ("%s WINS" % main.pvp_scores[w][0] if main.pvp_scores.has(w) else "MATCH OVER")
		head_col = ACCENT if w == Net.my_id() else DANGER
		sub = "YOU FINISHED  #%d  OF  %d" % [rank, main.pvp_scores.size()]
	var y := vp.y * 0.38
	_text(c, Vector2(0, y), head, 44, head_col, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_text(c, Vector2(0, y + 34), sub, 18, sub_col, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	# results table: name, kills, deaths in fixed columns
	var w2 := 420.0
	var x := vp.x * 0.5 - w2 * 0.5
	y += 70.0
	var rows := _pvp_rows()
	c.draw_rect(Rect2(x - 16, y - 18, w2 + 32, 26 + rows.size() * 24), Color(0, 0, 0, 0.5))
	_text(c, Vector2(x, y), "PLAYER", 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_text(c, Vector2(x + w2 - 120, y), "KILLS", 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 60, true)
	_text(c, Vector2(x + w2 - 60, y), "DEATHS", 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 60, true)
	for r in rows:
		y += 24.0
		_score_row(c, x, y, w2, r, 15)
	var prompt := "Enter  ·  REMATCH FOR EVERYONE   ·   Esc LEAVE" if Net.is_server() else "WAITING FOR THE HOST   ·   Esc LEAVE"
	_text(c, Vector2(0, y + 40), prompt, 14, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)


func _pvp_title() -> String:
	return "TEAM DEATHMATCH" if main.saved_tdm else "FREE FOR ALL"


## Rows for the scoreboards: team deathmatch puts a heading over each side
## (yours first); free for all is one ranked list.
## Each row: {head, text, kills, deaths, col, me, dead}.
func _pvp_rows() -> Array:
	var bodies := {}
	for e in main.enemies:
		if is_instance_valid(e) and e.has_meta("tdm_bot"):
			bodies[int(e.get_meta("tdm_bot"))] = e
	for id in main.players:
		bodies[int(id)] = main.players[id]
	var ranked: Array = main.pvp_ranked()
	var rows: Array = []
	if main.saved_tdm:
		var mine: int = player.team
		for side in [mine, 1 - mine]:
			var ally: bool = side == mine
			rows.append({"head": true, "text": "YOUR TEAM" if ally else "ENEMY TEAM", "kills": main.team_scores[side], "deaths": -1, "col": ALLY if ally else FOE})
			for id in ranked:
				if int(main.team_assignments.get(id, -1)) == side:
					rows.append(_row_for(id, bodies, ALLY if ally else FOE))
	else:
		var n := 0
		for id in ranked:
			n += 1
			var r := _row_for(id, bodies, FOE)
			r.text = "%d.  %s" % [n, r.text]
			rows.append(r)
	return rows


func _row_for(id, bodies: Dictionary, side_col: Color) -> Dictionary:
	var e: Array = main.pvp_scores[id]
	var me: bool = int(id) == Net.my_id()
	var body = bodies.get(int(id))
	return {"head": false, "text": String(e[0]).left(16), "kills": int(e[1]), "deaths": int(e[2]),
			"col": ACCENT if me else side_col, "me": me, "dead": body != null and is_instance_valid(body) and body.is_dead}


## One scoreboard line at (x, y), `w` wide: side stripe, name, kills, deaths.
func _score_row(c: Control, x: float, y: float, w: float, r: Dictionary, size: int) -> void:
	if r.head:
		_text(c, Vector2(x, y), String(r.text), size - 2, r.col, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
		_text(c, Vector2(x + w - 120, y), str(r.kills), size - 2, r.col, HORIZONTAL_ALIGNMENT_RIGHT, 60, true)
		c.draw_line(Vector2(x, y + 5), Vector2(x + w, y + 5), Color(r.col, 0.5), 1.0)
		return
	var col: Color = r.col
	if r.dead:
		col = Color(col, 0.45)
	if r.me:
		c.draw_rect(Rect2(x - 6, y - size + 1, w + 12, size + 5), Color(ACCENT, 0.12))
	c.draw_rect(Rect2(x - 6, y - size + 3, 3, size), Color(r.col, 0.9))
	_text(c, Vector2(x + 4, y), String(r.text) + ("   DOWN" if r.dead else ""), size, col, HORIZONTAL_ALIGNMENT_LEFT, -1, r.me)
	_text(c, Vector2(x + w - 120, y), str(r.kills), size, col, HORIZONTAL_ALIGNMENT_RIGHT, 60, r.me)
	_text(c, Vector2(x + w - 60, y), str(r.deaths), size, col, HORIZONTAL_ALIGNMENT_RIGHT, 60, r.me)


## Live scoreboard panel (top-left).
func _draw_pvp_scoreboard(c: Control, at: Vector2) -> void:
	var rows := _pvp_rows()
	var w := 236.0
	var x := at.x + 10
	var y := at.y
	c.draw_rect(Rect2(at.x, y - 16, w + 20, 26 + rows.size() * 18), Color(0, 0, 0, 0.45))
	_text(c, Vector2(x, y), "SCOREBOARD", 11, DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	_text(c, Vector2(x + w - 120, y), "K", 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 60, true)
	_text(c, Vector2(x + w - 60, y), "D", 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 60, true)
	for r in rows:
		y += 18.0
		_score_row(c, x, y, w, r, 12)


## Top-centre match line: mode and kill limit, the score, time left.
func _draw_pvp_header(c: Control, vp: Vector2) -> void:
	var tl := maxf(main.pvp_time_left, 0.0)
	_text(c, Vector2(0, 92), "%s  ·  FIRST TO %d" % [_pvp_title(), main.PVP_KILL_LIMIT], 13, WARN, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	var cx := vp.x * 0.5
	if main.saved_tdm:
		var mine: int = player.team
		_text(c, Vector2(cx - 300, 118), "YOUR TEAM  %d" % main.team_scores[mine], 20, ALLY, HORIZONTAL_ALIGNMENT_RIGHT, 284, true)
		_text(c, Vector2(cx - 16, 118), ":", 20, TEXT, HORIZONTAL_ALIGNMENT_CENTER, 32, true)
		_text(c, Vector2(cx + 16, 118), "%d  ENEMY" % main.team_scores[1 - mine], 20, FOE, HORIZONTAL_ALIGNMENT_LEFT, 284, true)
	else:
		var mine_s: Array = main.pvp_scores.get(Net.my_id(), ["", 0, 0])
		var ranked: Array = main.pvp_ranked()
		var lead_s := ""
		if not ranked.is_empty() and int(ranked[0]) != Net.my_id():
			lead_s = "   ·   LEADER  %s  %d" % [main.pvp_scores[ranked[0]][0], int(main.pvp_scores[ranked[0]][1])]
		_text(c, Vector2(0, 118), "YOU  %d KILLS   ·   #%d OF %d%s" % [int(mine_s[1]), ranked.find(Net.my_id()) + 1, ranked.size(), lead_s], 16, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_text(c, Vector2(0, 148), "%d:%02d LEFT   ·   %s" % [int(tl) / 60, int(tl) % 60, main.tod.clock_string()], 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)


# ================================================================ sign in

var _auth_user := ""
var _auth_pin := ""
var _auth_row := 0
var _auth_msg := ""
var _auth_bad := false
var _auth_rects: Array = []
var _auth_acc_rects: Array = []
const AUTH_ROWS := ["USERNAME", "PASSWORD", "SIGN IN", "CREATE ACCOUNT", "PLAY AS GUEST", "QUIT"]


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


## No account needed: plays at once, progress kept for a later CREATE ACCOUNT.
func _play_as_guest() -> void:
	Profile.play_as_guest()
	Sfx.play(player, "mag_in", player.global_position, -2.0, 0.0)
	_switch_profile()


## Load the signed-in account's progress: reset the cached saves, rebuild the title.
func _switch_profile() -> void:
	Collection._loaded = false
	Progression.reset_cache()
	Collection.credits = Collection.START_CREDITS
	Collection.owned = {}
	Collection.equipped = {}
	Collection.equipped_parts = {}
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


## Phone sign-in: the fields and buttons live in the keyboard's top bar
## (touch_controls.gd); this draws the logo, the message and the accounts
## saved on this phone above it. Tap an account to fill in its name.
func _draw_auth_touch(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.025, 0.035, 0.9))
	var kb_top := 9999.0
	for k in touch._keys:
		kb_top = minf(kb_top, (k[0] as Rect2).position.y)
	if kb_top > vp.y:
		kb_top = vp.y * 0.38
	var room := kb_top - 12.0
	_draw_logo(c, Vector2(vp.x * 0.5, room * 0.3), minf(vp.x * 0.3, room * 1.1), 0.95)
	_auth_rects.clear()   # the fields are in the keyboard bar
	var msg := _auth_msg if _auth_msg != "" else "Tap USERNAME or PASSWORD, type, then SIGN IN  ·  first time on this phone? CREATE ACCOUNT"
	_text(c, Vector2(0, room * 0.66), msg, 15, (DANGER if _auth_bad else ACCENT) if _auth_msg != "" else DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_auth_acc_rects.clear()
	var accs := Profile.accounts()
	if not accs.is_empty():
		var shown := accs.slice(0, 5)
		var w := 170.0
		var h := 40.0
		var x0 := vp.x * 0.5 - (shown.size() * (w + 10) - 10) * 0.5
		var y := room - h
		for i in shown.size():
			var r := Rect2(x0 + i * (w + 10), y, w, h)
			_auth_acc_rects.append([r, shown[i]])
			c.draw_rect(r, Color(1, 1, 1, 0.07))
			c.draw_rect(r, Color(TEXT, 0.35), false, 1.5)
			_text(c, Vector2(r.position.x, r.position.y + 27), String(shown[i]).to_upper(), 16, TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)


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
			_play_as_guest()
		5:
			print("[quit] sign-in QUIT row")
			Settings.mark_clean_exit()
			get_tree().quit()


func _draw_auth(c: Control, vp: Vector2) -> void:
	if touch != null:
		_draw_auth_touch(c, vp)
		return
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.025, 0.035, 0.86))
	_draw_logo(c, Vector2(vp.x * 0.5, vp.y * 0.2), minf(vp.x * 0.42, 640.0), 0.95)
	var pw := 460.0
	var px := vp.x * 0.5 - pw * 0.5
	var top := vp.y * 0.38
	c.draw_rect(Rect2(px - 30, top - 50, pw + 60, 408), Color(0.03, 0.045, 0.055, 0.85))
	_brackets(c, Rect2(px - 30, top - 50, pw + 60, 408), 16.0, Color(TEXT, 0.35), 1.5)
	_text(c, Vector2(0, top - 18), "SIGN IN", 24, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	_text(c, Vector2(0, top + 336), "Successful sign-ins report your username, time and game version to the game owner.", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	var cur := "_" if int(_time * 2.0) % 2 == 0 else " "
	var pin_show := ""
	for i in Profile.PIN_LEN:
		pin_show += ("*" if i < _auth_pin.length() else "_") + ("  " if i < Profile.PIN_LEN - 1 else "")
	var values := [_auth_user + (cur if _auth_row == 0 else ""), pin_show, "", "", "", ""]
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
		_text(c, Vector2(0, top + 378), _auth_msg, 14, DANGER if _auth_bad else ACCENT, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
	# accounts on this PC (click to pick)
	_auth_acc_rects.clear()
	var accs := Profile.accounts()
	if not accs.is_empty():
		_text(c, Vector2(0, top + 416), "ACCOUNTS ON THIS PC", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x, true)
		var shown := accs.slice(0, 6)
		var w := 150.0
		var x0 := vp.x * 0.5 - (shown.size() * (w + 10) - 10) * 0.5
		for i in shown.size():
			var r := Rect2(x0 + i * (w + 10), top + 428, w, 28)
			_auth_acc_rects.append([r, shown[i]])
			c.draw_rect(r, Color(1, 1, 1, 0.05))
			c.draw_rect(r, Color(TEXT, 0.25), false, 1.0)
			_text(c, Vector2(r.position.x, r.position.y + 19), String(shown[i]).to_upper(), 12, TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	_text(c, Vector2(0, vp.y - 40), "Type your username and %d-digit password   ·   Tab / Up / Down move   ·   Enter sign in   ·   just want to play? PLAY AS GUEST" % Profile.PIN_LEN,
			12, DIM, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	_text(c, Vector2(0, vp.y - 22), "Accounts are stored on this PC only  ·  each one keeps its own credits, skins, loadouts and campaign progress", 11, Color(DIM, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vp.x)
