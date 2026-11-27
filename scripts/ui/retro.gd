extends RefCounted
## UI theme, from the logo: Saira (SIL Open Font License, see assets/fonts) on an earth-tone palette shared by every
## screen: sand text, khaki labels, an olive accent on dark-brown panels; ochre warns, rust marks danger.
##   body, labels, headlines   Saira (regular / semibold weights of the variable font, headlines a touch condensed);
##                             a Bahnschrift-style system sans if it is missing

const BODY_PATH := "res://assets/fonts/Saira.ttf"

const ACCENT := Color(0.66, 0.74, 0.38)       # olive (the logo's green, lifted to read on dark)
const TEXT := Color(0.93, 0.87, 0.76, 0.96)   # sand
const DIM := Color(0.72, 0.65, 0.53, 0.88)    # khaki
const WARN := Color(0.88, 0.64, 0.3)          # ochre
const DANGER := Color(0.86, 0.36, 0.24)       # rust
const RED := Color(0.78, 0.3, 0.2)            # danger / hostile accent (kill cam, enemies, damage)
const BRAND := Color(0.45, 0.52, 0.23)        # olive fill: the primary button, selection marks
const PANEL := Color(0.075, 0.06, 0.048)      # dark-brown panel
const LINE := Color(0.93, 0.87, 0.76, 0.14)   # hairline rules and frames

static var _body: Font
static var _bold: Font
static var _display: Font


static func _load(path: String) -> FontFile:
	# the imported font (the only form an exported game has); straight from the
	# .ttf when it has not been imported yet
	var f: FontFile = (load(path) as FontFile).duplicate() if ResourceLoader.exists(path) else null
	if f == null:
		f = FontFile.new()
		if f.load_dynamic_font(path) != OK:
			return null
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.generate_mipmaps = false
	return f


static func _fallback() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New"])
	return sf


## Fallback UI face when the pixel font cannot be loaded (Bahnschrift ships with
## Windows 10/11), with common sans fallbacks elsewhere.
static func _clean() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "DejaVu Sans"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_LIGHT
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return sf


static func body() -> Font:
	if _body == null:
		_body = _load(BODY_PATH)
		if _body == null:
			_body = _clean()
	return _body


static func bold() -> Font:
	if _bold == null:
		var fv := FontVariation.new()
		fv.base_font = body()
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 600}
		_bold = fv
	return _bold


## Headlines: bold and a touch condensed, like the logo's lettering.
static func display() -> Font:
	if _display == null:
		var fv := FontVariation.new()
		fv.base_font = body()
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 700, ts.name_to_tag("wdth"): 87.5}
		_display = fv
	return _display


## Makes the UI font the default for every Control / Label3D.
static func install() -> void:
	ThemeDB.fallback_font = body()
