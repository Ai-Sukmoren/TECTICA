extends CanvasLayer
## Smooth map changes and the loading screen: fade to black, show the loading screen, reload the scene while
## the screen is covered, let the new map render a few frames (shader warm-up, streaming) and only then fade
## back in. The overlay lives on the window root, so it survives reload_current_scene().
##
## The loading screen shows real progress only: loading.gd reports the scene's resources loading (0-25 %),
## main.gd each stage of building the map (25-95 %), and the reveal the last frames drawn (100 %). The number
## on screen eases toward the reported value and never runs ahead of it.

const Retro = preload("res://scripts/ui/retro.gd")
const LOGO_PATH := "res://assets/logo.png"
var _logo: Texture2D

const FADE_OUT := 0.22
const FADE_IN := 0.45
## Frames the new map draws under the loading screen before it is revealed.
const SETTLE_FRAMES := 6
## Blocks in the progress bar.
const TIPS := [
	"CROUCH IN BUSHES TO STAY HIDDEN - TREES STOP BULLETS",
	"SPACE AT A LEDGE CLIMBS IT - JUMP AND HOLD SPACE TO GRAB A HIGH ONE",
	"SPRINT INTO LOW COVER TO VAULT IT WITHOUT SLOWING DOWN",
	"Q / E LEAN ROUND CORNERS - LESS OF YOU SHOWS",
	"HEADSHOTS END ZOMBIES FAST - SAVE AMMO FOR THE BRUTES",
	"BUY FROM THE SHOP BETWEEN WAVES - THE COUNTDOWN SHOWS HOW LONG YOU HAVE",
	"A KNIFE TAKEDOWN FROM BEHIND IS SILENT",
	"TOSS A DECOY TO PULL A GUARD'S EYES AWAY",
	"AIM OR FIRE MID-VAULT WITH FOCUS FOR BULLET TIME",
	"RELOAD BEHIND COVER - AN EMPTY MAGAZINE IN THE OPEN IS A BAD DAY",
]

static var _inst: CanvasLayer

var _rect: ColorRect
var _screen: Control
var _busy := false
var _target := 0.0
var _shown := 0.0
var _title := ""
var _subtitle := ""
var _stage_text := "LOADING"
var _tip := ""
var _t := 0.0
var _title_t := 0.0
var _rng := RandomNumberGenerator.new()   # never the global one: map layouts are seeded while this draws


static func _instance(tree: SceneTree) -> CanvasLayer:
	if _inst == null or not is_instance_valid(_inst):
		_inst = load("res://scripts/ui/transition.gd").new()
		_inst.name = "MapTransition"
		tree.root.add_child.call_deferred(_inst)
	return _inst


## Fades out, then reloads the current scene. Safe to call from anywhere.
static func change_map(tree: SceneTree) -> void:
	var t := _instance(tree)
	t.call_deferred("_run", tree)


static func begin_loading(tree: SceneTree) -> void:
	var t := _instance(tree)
	t.call_deferred("_show_loading")


static func reveal(tree: SceneTree) -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.call_deferred("_reveal", tree)


## True while the loading screen covers the window (a map change from the game, not a test opening a scene).
static func is_loading() -> bool:
	return _inst != null and is_instance_valid(_inst) and _inst._busy


## The map and mode being loaded (main.gd, as soon as it knows them).
static func set_info(tree: SceneTree, title: String, subtitle: String) -> void:
	var t := _instance(tree)
	t._title = title
	t._subtitle = subtitle
	t._title_t = 0.0


## A loading stage: the progress reached (0-100) and what is being done now.
static func stage(tree: SceneTree, percent: float, what: String) -> void:
	var t := _instance(tree)
	t._stage_text = what
	t.set_progress(int(percent))


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.modulate.a = 0.0
	_screen.draw.connect(_draw_screen)
	_rect.add_child(_screen)


func _begin() -> void:
	_target = 0.0
	_shown = 0.0
	_stage_text = "LOADING"
	_tip = TIPS[_rng.randi() % TIPS.size()]


func _show_loading() -> void:
	if not is_inside_tree():
		await ready
	if _busy:
		return
	_busy = true
	_begin()
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.color.a = 1.0
	_screen.modulate.a = 1.0


## Called by main.gd once the new map is built.
func _run(tree: SceneTree) -> void:
	if _busy:
		return
	_busy = true
	if not is_inside_tree():
		await ready
	_begin()
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rect, "color:a", 1.0, FADE_OUT)
	tw.tween_property(_screen, "modulate:a", 1.0, FADE_OUT)
	await tw.finished
	# one fully covered frame on screen before the heavy rebuild starts
	await tree.process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	tree.paused = false
	await _teardown(tree)
	var error := tree.change_scene_to_file("res://scenes/loading.tscn")
	if error != OK:
		push_error("Map reload failed: %s" % error_string(error))
		_reveal(tree)


## Takes the old map apart a slice at a time under the loading screen, leaves first, at most TEARDOWN_MS of
## work a frame: dropping a big map (thousands of nodes, their meshes and collision) in one go froze the screen for
## up to 2 s. The old scene stops processing first, so nothing runs against a half-removed map.
const TEARDOWN_MS := 12
func _teardown(tree: SceneTree) -> void:
	var old := tree.current_scene
	if old == null or old.get_node_or_null("Level") == null:
		return   # not a map (the title screen, the loading screen)
	old.process_mode = Node.PROCESS_MODE_DISABLED
	_stage_text = "CLEARING MAP"
	var nodes: Array[Node] = old.get_node("Level").find_children("*", "", true, false)
	var i := nodes.size() - 1
	while i >= 0:
		var t0 := Time.get_ticks_usec()
		while i >= 0 and Time.get_ticks_usec() - t0 < TEARDOWN_MS * 1000:
			var n: Node = nodes[i]
			i -= 1
			if is_instance_valid(n) and n.get_child_count() == 0:
				n.free()
		await tree.process_frame


func _reveal(tree: SceneTree) -> void:
	if not _busy:
		return
	_rect.color.a = 1.0
	_screen.modulate.a = 1.0
	_stage_text = "READY"
	set_progress(100)
	for i in SETTLE_FRAMES:
		await tree.process_frame
	_shown = 100.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the map is ready: input reaches it while the screen fades in
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rect, "color:a", 0.0, FADE_IN)
	tw.tween_property(_screen, "modulate:a", 0.0, FADE_IN * 0.6)
	await tw.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func set_progress(percent: int) -> void:
	_target = maxf(_target, clampf(float(percent), 0.0, 100.0))


func _process(delta: float) -> void:
	if _screen == null or _screen.modulate.a <= 0.0:
		return
	_t += delta
	_title_t += delta
	# frames can be long while a stage builds: catch up quickly, but never pass the real value
	_shown = minf(_target, _shown + maxf((_target - _shown) * minf(delta * 7.0, 1.0), 25.0 * delta))
	_screen.queue_redraw()


# ------------------------------------------------------------------ drawing

func _draw_screen() -> void:
	var c := _screen
	var sz := c.size
	var s := sz.y / 720.0
	var accent := Retro.ACCENT
	var amber := Retro.DIM
	var text := Retro.TEXT
	# background: plain dark brown, a little darker along the bottom
	c.draw_rect(Rect2(Vector2.ZERO, sz), Retro.PANEL)
	c.draw_rect(Rect2(0, sz.y * 0.72, sz.x, sz.y * 0.28), Color(0, 0, 0, 0.25))

	var body := Retro.body()
	var display := Retro.display()
	var left := 64.0 * s
	# brand and corner marks
	if _logo == null and ResourceLoader.exists(LOGO_PATH):
		_logo = load(LOGO_PATH)
	if _logo != null:
		var lw := 200.0 * s
		c.draw_texture_rect(_logo, Rect2(left, 40.0 * s, lw, lw * _logo.get_height() / _logo.get_width()), false)
	else:
		c.draw_string(display, Vector2(left, 64.0 * s), "TECTICA", HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * s), text)
	c.draw_string(body, Vector2(left, 92.0 * s), "v" + str(ProjectSettings.get_setting("application/config/version", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), Color(text.r, text.g, text.b, 0.4))
	# what is loading: mode (green) over the map name (large), sliding in when it becomes known
	var slide := 1.0 - pow(1.0 - clampf(_title_t / 0.5, 0.0, 1.0), 3.0)
	var ty := sz.y * 0.43
	if _title != "":
		var off := (1.0 - slide) * -30.0 * s
		c.draw_string(body, Vector2(left + off, ty - 44.0 * s), _subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * s),
				Color(accent.r, accent.g, accent.b, slide))
		c.draw_string(display, Vector2(left + off, ty), _title, HORIZONTAL_ALIGNMENT_LEFT, sz.x * 0.62, int(46 * s),
				Color(text.r, text.g, text.b, slide))
		c.draw_rect(Rect2(left + off, ty + 16.0 * s, 120.0 * s * slide, 2.0 * s), accent)
	# the stage, with a blinking cursor
	c.draw_string(body, Vector2(left, ty + 56.0 * s), _stage_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(20 * s), amber)
	# progress: a big percentage over a thin bar
	var pct := int(floor(_shown))
	var by := sz.y - 120.0 * s
	var bw := sz.x - left * 2.0
	c.draw_string(display, Vector2(left, by - 22.0 * s), "%d%%" % pct, HORIZONTAL_ALIGNMENT_RIGHT, bw, int(40 * s), text)
	c.draw_string(body, Vector2(left, by - 22.0 * s), "LOADING", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * s),
			Color(text.r, text.g, text.b, 0.55))
	# one thin bar on a hairline track
	var bh := 3.0 * s
	c.draw_rect(Rect2(left, by + 6.0 * s, bw, 1.0), Retro.LINE)
	c.draw_rect(Rect2(left, by + 6.0 * s - bh * 0.5, bw * clampf(_shown / 100.0, 0.0, 1.0), bh), accent)
	# a tip
	if _tip != "":
		c.draw_string(body, Vector2(left, sz.y - 62.0 * s), "TIP  " + _tip, HORIZONTAL_ALIGNMENT_LEFT, bw, int(17 * s),
				Color(text.r, text.g, text.b, 0.62))
