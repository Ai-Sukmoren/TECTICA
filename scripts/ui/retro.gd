extends RefCounted
## Retro UI theme: pixel fonts (both SIL Open Font License, see assets/fonts)
## and the phosphor / amber palette shared by every screen.
##   body + labels   Pixelify Sans (regular / bold weights of the variable font)
##   headlines       Press Start 2P (8-bit arcade)

const BODY_PATH := "res://assets/fonts/PixelifySans.ttf"
const DISPLAY_PATH := "res://assets/fonts/PressStart2P.ttf"

const ACCENT := Color(0.42, 1.0, 0.55)        # phosphor green
const TEXT := Color(0.94, 0.94, 0.9, 0.95)    # neutral off-white
const DIM := Color(0.86, 0.7, 0.46, 0.88)     # amber
const WARN := Color(1.0, 0.72, 0.1)
const DANGER := Color(1.0, 0.24, 0.18)
const RED := Color(0.92, 0.16, 0.12)

static var _body: Font
static var _bold: Font
static var _display: Font


static func _load(path: String) -> FontFile:
	var f := FontFile.new()
	# load straight from the .ttf so it works without an editor import step
	if f.load_dynamic_font(path) != OK:
		return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	return f


static func _fallback() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New"])
	return sf


## Clean DIN-style UI face (Bahnschrift ships with Windows 10/11), with
## common sans fallbacks elsewhere. The pixel fonts stay in assets/fonts.
static func _clean() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "DejaVu Sans"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_LIGHT
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return sf


static func body() -> Font:
	if _body == null:
		_body = _clean()
	return _body


static func bold() -> Font:
	if _bold == null:
		var fv := FontVariation.new()
		fv.base_font = body()
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 700}
		_bold = fv
	return _bold


## Headlines: bold, slightly condensed (uses Bahnschrift's width axis).
static func display() -> Font:
	if _display == null:
		var fv := FontVariation.new()
		fv.base_font = body()
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 700, ts.name_to_tag("wdth"): 85}
		fv.spacing_glyph = 1
		_display = fv
	return _display


## Makes the pixel font the default for every Control / Label3D.
static func install() -> void:
	ThemeDB.fallback_font = body()
