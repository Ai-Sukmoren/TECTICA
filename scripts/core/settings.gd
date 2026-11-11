extends RefCounted
## Player options, persisted to user://settings.cfg.
## Rows are grouped into tabs. Row formats:
##   [key, label, min, max, step]     slider
##   [key, label, null]               on/off toggle
##   [key, label, [option labels]]    choice (value = option index)

const PATH := "user://settings.cfg"

const TABS := ["GAME", "VIDEO", "AUDIO"]
const PRESETS := ["LOW", "HIGH", "ULTRA", "CUSTOM"]
const AA := ["OFF", "FXAA", "MSAA 2X", "MSAA 4X", "TAA", "MSAA 2X + FXAA"]
const SHADOWS := ["OFF", "LOW", "HIGH", "ULTRA"]
const WINDOW := ["WINDOWED", "FULLSCREEN", "BORDERLESS"]
const FPS_CAPS := [30, 60, 120, 144, 240, 0]

const ROWS := {
	"GAME": [
		["sensitivity", "LOOK SENSITIVITY", 0.2, 3.0, 0.1],
		["shake", "CAMERA SHAKE", 0.0, 1.5, 0.1],
		["show_fps", "SHOW FPS", null],
	],
	"VIDEO": [
		["preset", "QUALITY PRESET", PRESETS],
		["fov", "FIRST-PERSON FOV", 60.0, 110.0, 2.0],
		["tactical_fov", "TOP-DOWN FOV", 28.0, 60.0, 2.0],
		["render_scale", "RENDER SCALE", 0.5, 1.0, 0.05],
		["aa", "ANTI-ALIASING", AA],
		["shadows", "SHADOWS", SHADOWS],
		["ssao", "AMBIENT OCCLUSION", null],
		["ssr", "REFLECTIONS", null],
		["ssil", "INDIRECT LIGHT (SSIL)", null],
		["gi", "GLOBAL ILLUMINATION", null],
		["fog", "VOLUMETRIC FOG", null],
		["bloom", "BLOOM", null],
		["brightness", "BRIGHTNESS", 0.6, 1.6, 0.05],
		["retro_crt", "RETRO CRT FILTER", null],
		["film_grain", "FILM GRAIN & LENS FX", null],
		["window_mode", "DISPLAY MODE", WINDOW],
		["max_fps", "FRAME RATE LIMIT", ["30", "60", "120", "144", "240", "UNLIMITED"]],
		["vsync", "V-SYNC", null],
	],
	"AUDIO": [
		["master_volume", "MASTER VOLUME", 0.0, 1.0, 0.05],
		["music_volume", "MUSIC VOLUME", 0.0, 1.0, 0.05],
		["sfx_volume", "EFFECTS VOLUME", 0.0, 1.0, 0.05],
	],
}

## Settings each preset controls (LOW, HIGH, ULTRA).
const PRESET_VALUES := {
	"aa": [1, 2, 3],
	"shadows": [1, 2, 3],
	"ssao": [false, true, true],
	"ssr": [false, true, true],
	"ssil": [false, false, true],
	"gi": [false, false, true],
	"fog": [false, true, true],
	"render_scale": [0.85, 1.0, 1.0],
}

static var v := {
	"sensitivity": 1.0, "fov": 78.0, "master_volume": 0.9, "music_volume": 0.7, "sfx_volume": 0.9,
	"shake": 1.0, "show_fps": false, "film_grain": true, "vsync": true,
	"preset": 1, "tactical_fov": 38.0, "render_scale": 1.0, "aa": 2, "shadows": 2,
	"ssao": true, "ssr": true, "ssil": false, "gi": false, "fog": true, "bloom": true,
	"brightness": 1.0, "retro_crt": false, "window_mode": 1, "max_fps": 5,
	"mp_name": "", "mp_ip": "127.0.0.1", "mp_port": 7777,
}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in v.keys():
			var val = cfg.get_value("settings", k, v[k])
			if typeof(val) == typeof(v[k]) or (typeof(v[k]) == TYPE_FLOAT and typeof(val) == TYPE_INT):
				v[k] = val
	apply()


static func save() -> void:
	var cfg := ConfigFile.new()
	for k in v.keys():
		cfg.set_value("settings", k, v[k])
	cfg.save(PATH)


static func rows(tab: int) -> Array:
	return ROWS[TABS[clampi(tab, 0, TABS.size() - 1)]]


static func is_toggle(row: Array) -> bool:
	return row[2] == null


static func is_choice(row: Array) -> bool:
	return row[2] is Array


## Applies LOW / HIGH / ULTRA to every setting the preset controls.
static func set_preset(p: int) -> void:
	p = clampi(p, 0, 2)
	v.preset = p
	for k in PRESET_VALUES:
		v[k] = PRESET_VALUES[k][p]
	apply()


static func adjust(row: Array, dir: int) -> void:
	var key: String = row[0]
	if key == "preset":
		set_preset(posmod(int(v.preset) + dir, 3) if int(v.preset) < 3 else (0 if dir > 0 else 2))
		return
	if is_toggle(row):
		v[key] = not bool(v[key])
	elif is_choice(row):
		v[key] = posmod(int(v[key]) + dir, (row[2] as Array).size())
	else:
		v[key] = clampf(snappedf(float(v[key]) + float(row[4]) * dir, float(row[4])), float(row[2]), float(row[3]))
	if PRESET_VALUES.has(key):
		v.preset = 3   # CUSTOM
	apply()


static func label_value(row: Array) -> String:
	var key: String = row[0]
	var val = v[key]
	if is_toggle(row):
		return "ON" if bool(val) else "OFF"
	if is_choice(row):
		return String(row[2][int(val)])
	if key.ends_with("volume") or key == "render_scale" or key == "brightness":
		return "%d%%" % int(round(float(val) * 100.0))
	if key.ends_with("fov"):
		return "%d°" % int(val)
	return "%.1f" % float(val)


## 0..1 position of a slider row (for the bar), -1 for non-sliders.
static func slider_frac(row: Array) -> float:
	if is_toggle(row) or is_choice(row):
		return -1.0
	return (float(v[row[0]]) - float(row[2])) / (float(row[3]) - float(row[2]))


static func apply() -> void:
	_set_bus("Master", float(v.master_volume))
	_set_bus("Music", float(v.music_volume))
	_set_bus("SFX", float(v.sfx_volume))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(v.vsync) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FPS_CAPS[clampi(int(v.max_fps), 0, FPS_CAPS.size() - 1)]
	if DisplayServer.get_name() != "headless":
		var want: int = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_FULLSCREEN][clampi(int(v.window_mode), 0, 2)]
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	# scene-side graphics (environment, lights, cameras) live in main.gd
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.call_group("graphics_listener", "apply_graphics")


static func _set_bus(bus_name: String, vol: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))
		AudioServer.set_bus_mute(idx, vol <= 0.001)
