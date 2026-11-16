extends Node3D
## Builds every gun once while the map is loading, plus each attachment the
## gunsmith offers, and draws them for a few frames at a microscopic size just
## in front of the camera (under the loading screen). Their model files load,
## their meshes are made and their shaders compile here, instead of the first
## time a gun appears mid-match, which was a sudden burst of CPU and GPU work.
## Frees itself when done.

const Data = preload("res://scripts/weapons/weapon_data.gd")
const Model = preload("res://scripts/weapons/weapon_model.gd")
## Frames the models are drawn for (Transition shows the map after 6).
const FRAMES := 4
## Small enough to cover less than a pixel, big enough to be drawn.
const SCALE := 0.002

var _models: Array[Node3D] = []


func _ready() -> void:
	var seen := {}
	for id in Data.PRIMARIES + Data.SMGS + Data.SECONDARIES:
		var w: Dictionary = Data.WEAPONS[id]
		_add(String(w.model), w.defaults)
		# each attachment once, on the first gun that takes it
		for slot in w.options:
			for value in w.options[slot]:
				var key := "%s:%s" % [slot, value]
				if seen.has(key) or value == w.defaults.get(slot):
					continue
				seen[key] = true
				_add(String(w.model), Data.sanitize(id, {slot: value}))
	for i in FRAMES:
		_follow_camera()
		await get_tree().process_frame
	queue_free()


func _add(model: String, att: Dictionary) -> void:
	var root: Node3D = Model.build(model, att).root
	root.scale = Vector3.ONE * SCALE
	add_child(root)
	_models.append(root)


## Keeps the models in view: the camera can move while the map settles.
func _follow_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	global_transform = cam.global_transform.translated_local(Vector3(0, 0, -0.5))
