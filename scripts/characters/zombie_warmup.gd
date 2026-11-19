extends Node3D
## Zombie Survival's version of gun_warmup.gd: one zombie of every kind is built
## and drawn for a few frames at a microscopic size in front of the camera,
## under the loading screen. The first time each kind was drawn mid-wave its
## materials compiled on the spot (a 200-500 ms freeze as the first wave
## arrived); now that happens while the map loads. The stand-ins never think,
## move, collide or count as enemies, and the node frees itself when done.

const Zombie = preload("res://scripts/characters/zombie.gd")

const KINDS := ["walker", "runner", "crawler", "brute", "armored", "berserker", "bloater", "dog", "bat", "boss"]
const FRAMES := 4
const SCALE := 0.002

var skin_id := ""


func _ready() -> void:
	scale = Vector3.ONE * SCALE
	var target := Node3D.new()   # init_zombie only reads its position, to face it
	add_child(target)
	for i in KINDS.size():
		var z := Zombie.new()
		z.skin_id = skin_id
		z.process_mode = Node.PROCESS_MODE_DISABLED   # no AI, physics or sounds
		add_child(z)
		z.position = Vector3((i - KINDS.size() * 0.5) * 1.2, 0, 0)
		z.init_zombie(target, KINDS[i], 1.0, 0.0, 0.0, i)
		z.collision_layer = 0
		z.collision_mask = 0
		for g in ["enemies", "zombies", "bosses"]:
			z.remove_from_group(g)
	for i in FRAMES:
		_follow_camera()
		await get_tree().process_frame
	queue_free()


## Keeps the stand-ins in view: the camera can move while the map settles.
func _follow_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	global_transform = cam.global_transform.translated_local(Vector3(0, -0.002, -0.5)).scaled_local(Vector3.ONE * SCALE)
