extends Node3D
## Zombie Survival's version of gun_warmup.gd: one zombie of every kind is built
## and drawn for a few frames at a microscopic size in front of the camera,
## under the loading screen. The first time each kind was drawn mid-wave its
## materials compiled on the spot (a 200-500 ms freeze as the first wave
## arrived); now that happens while the map loads. The stand-ins never think,
## move, collide or count as enemies, and the node frees itself when done.
## Their skinned bodies are built here too (SoldierRig.bake_skinned), plus a walker of every look: the first wave is
## all walkers and each new look built mid-wave cost a 20-40 ms frame as it arrived.

const Zombie = preload("res://scripts/characters/zombie.gd")

const KINDS := ["walker", "runner", "crawler", "brute", "armored", "berserker", "bloater", "dog", "bat", "boss"]
const FRAMES := 4
## Looks cycle with the spawn number (Palettes.zombie: skin x3, camo x2, headgear x4).
const WALKER_LOOKS := 12
const SCALE := 0.002
## Stand-ins built per frame (each ~3 ms plus ~10 ms for its body): main.gd waits for `done` under the loading
## screen, which keeps moving instead of freezing for one long frame.
const PER_FRAME := 2

## Every stand-in is built with its body (they are still drawn for FRAMES more frames before the node frees itself).
var done := false

var skin_id := ""


func _ready() -> void:
	# built full size and hidden: their deferred optimize_detail() sizes each part in world space (tiny parts lose
	# their shadow), so a shrunken stand-in would get a different body from a real zombie of the same look
	visible = false
	var target := Node3D.new()   # init_zombie only reads its position, to face it
	add_child(target)
	var stand_ins := []
	for i in KINDS.size():
		stand_ins.append([KINDS[i], i])
	for v in WALKER_LOOKS:
		if v != 0:   # walker look 0 is already in
			stand_ins.append(["walker", v])
	for i in stand_ins.size():
		var z := Zombie.new()
		z.skin_id = skin_id
		z.process_mode = Node.PROCESS_MODE_DISABLED   # no AI, physics or sounds
		add_child(z)
		z.position = Vector3((i - stand_ins.size() * 0.5) * 1.2, 0, 0)
		z.init_zombie(target, stand_ins[i][0], 1.0, 0.0, 0.0, stand_ins[i][1])
		z.collision_layer = 0
		z.collision_mask = 0
		for g in ["enemies", "zombies", "bosses"]:
			z.remove_from_group(g)
		z.rig.bake_now = true   # its deferred optimize_detail() builds the body now, not one per frame
		if i % PER_FRAME == PER_FRAME - 1:
			await get_tree().process_frame
	await get_tree().process_frame   # optimize_detail() runs: parts merged, bodies built
	done = true
	visible = true
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
