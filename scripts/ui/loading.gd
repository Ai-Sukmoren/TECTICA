extends Control
## Loads the game scene in the background. The loading screen itself is drawn by transition.gd's overlay; this
## reports the resources' real progress to it (0-25 %), and main.gd reports building the map (25-100 %).
const TARGET := "res://scenes/main.tscn"
## Share of the loading bar for the scene's resources (the rest is building the map).
const LOAD_SHARE := 25.0
const Transition = preload("res://scripts/ui/transition.gd")
var _finishing := false
## The map's model file (a model map), loaded on the same background thread. Held here past this scene, so
## the map build finds it in the cache instead of loading it with the screen frozen.
static var _held: Resource
var _asset := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # a pause left over from the last map must not stall the load
	Transition.begin_loading(get_tree())
	var background := ColorRect.new()
	background.color = Color(0.012, 0.02, 0.028)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	Transition.stage(get_tree(), 0.0, "LOADING ASSETS")
	_held = null
	_asset = _map_asset()
	if _asset != "":
		ResourceLoader.load_threaded_request(_asset)
	var error := ResourceLoader.load_threaded_request(TARGET)
	if error != OK:
		_fail(error_string(error))


## The model file of the map about to load, or "" (the forest is built in code). Read from main.gd's choice of
## map only when that script is already loaded, so this scene never loads the game's scripts itself.
func _map_asset() -> String:
	const MAIN := "res://scripts/main.gd"
	const MODEL := "res://scripts/world/model_level.gd"
	if not (ResourceLoader.has_cached(MAIN) and ResourceLoader.has_cached(MODEL)):
		return ""
	var main_script = load(MAIN)
	var model = load(MODEL)
	var map := String(main_script.saved_map)
	if not String(main_script.saved_mode) in ["zombie", "pvp"] or not model.CONFIGS.has(map):
		return ""
	var path: String = model.MAP_DIR + String(model.CONFIGS[map].glb)
	return path if ResourceLoader.exists(path) else ""


func _process(_delta: float) -> void:
	if _finishing:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(TARGET, progress)
	var done: float = progress[0] if not progress.is_empty() else 0.0
	if _asset != "" and status != ResourceLoader.THREAD_LOAD_FAILED:
		var p2: Array = []
		var s2 := ResourceLoader.load_threaded_get_status(_asset, p2)
		done = (done + (float(p2[0]) if not p2.is_empty() else 0.0)) * 0.5
		if s2 == ResourceLoader.THREAD_LOAD_LOADED:
			_held = ResourceLoader.load_threaded_get(_asset)
			_asset = ""
		elif s2 == ResourceLoader.THREAD_LOAD_IN_PROGRESS and status == ResourceLoader.THREAD_LOAD_LOADED:
			status = ResourceLoader.THREAD_LOAD_IN_PROGRESS   # the scene is in: wait for the map's model too
		elif s2 != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_asset = ""   # failed: the map build loads it itself
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		Transition.stage(get_tree(), done * LOAD_SHARE, "LOADING ASSETS")
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		_finishing = true
		Transition.stage(get_tree(), LOAD_SHARE, "STARTING")
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		var scene := ResourceLoader.load_threaded_get(TARGET) as PackedScene
		var error := get_tree().change_scene_to_packed(scene)
		if error != OK:
			_fail(error_string(error))
	else:
		_fail("LOADING FAILED - RESTART TO RETRY")


func _fail(message: String) -> void:
	_finishing = true
	Transition.stage(get_tree(), 0.0, message)
	push_error(message)
