extends CanvasLayer
## Smooth map changes: fade to black, show LOADING, reload the scene while the
## screen is covered, let the new map render a few frames (shader warm-up,
## streaming) and only then fade back in. The overlay lives on the window root,
## so it survives reload_current_scene().

const FADE_OUT := 0.22
const FADE_IN := 0.45
## Frames the new map draws under the black screen before it is revealed.
const SETTLE_FRAMES := 6

static var _inst: CanvasLayer

var _rect: ColorRect
var _label: Label
var _busy := false


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


## Called by main.gd once the new map is built.
static func reveal(tree: SceneTree) -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.call_deferred("_reveal", tree)


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_label = Label.new()
	_label.text = "LOADING"
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.91, 0.85, 0.66))
	_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.position = Vector2(-190, -70)
	_label.modulate.a = 0.0
	_rect.add_child(_label)


func _run(tree: SceneTree) -> void:
	if _busy:
		return
	_busy = true
	if not is_inside_tree():
		await ready
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rect, "color:a", 1.0, FADE_OUT)
	tw.tween_property(_label, "modulate:a", 1.0, FADE_OUT)
	await tw.finished
	# one fully black frame on screen before the heavy rebuild starts
	await tree.process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	tree.paused = false
	var error := tree.reload_current_scene()
	if error != OK:
		push_error("Map reload failed: %s" % error_string(error))
		_reveal(tree)


func _reveal(tree: SceneTree) -> void:
	if not _busy:
		return
	for i in SETTLE_FRAMES:
		await tree.process_frame
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_rect, "color:a", 0.0, FADE_IN)
	tw.tween_property(_label, "modulate:a", 0.0, FADE_IN * 0.5)
	await tw.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
