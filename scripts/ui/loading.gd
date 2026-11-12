extends Control
## Resource progress comes from Godot. World initialization stays at 90%.
const TARGET := "res://scenes/main.tscn"
var _label: Label
var _bar: ProgressBar
var _finishing := false


func _ready() -> void:
	preload("res://scripts/ui/transition.gd").begin_loading(get_tree())
	var background := ColorRect.new()
	background.color = Color(0.012, 0.02, 0.028)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.position -= Vector2(240, 60)
	box.size = Vector2(480, 120)
	add_child(box)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(480, 12)
	box.add_child(_bar)
	var version := Label.new()
	version.text = "TECTICA  v" + str(ProjectSettings.get_setting("application/config/version"))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(version)
	_progress(0)
	var error := ResourceLoader.load_threaded_request(TARGET)
	if error != OK:
		_fail(error_string(error))


func _progress(percent: int) -> void:
	_bar.value = percent
	_label.text = "LOADING  %d%%" % percent
	var transition = get_tree().root.get_node_or_null("MapTransition")
	if transition != null:
		transition.set_progress(percent)


func _process(_delta: float) -> void:
	if _finishing:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(TARGET, progress)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not progress.is_empty():
			_progress(int(float(progress[0]) * 90.0))
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		_finishing = true
		_progress(90)
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		var scene := ResourceLoader.load_threaded_get(TARGET) as PackedScene
		var error := get_tree().change_scene_to_packed(scene)
		if error != OK:
			_fail(error_string(error))
	else:
		_fail("Loading failed. Restart to retry.")


func _fail(message: String) -> void:
	_finishing = true
	_label.text = message
	push_error(message)
