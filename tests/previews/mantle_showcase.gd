extends SceneTree
## Movie-writer clip of mantling: a 1.6 m wall from the side, a deep crate in
## first person, and a jump-and-grab onto a 2.3 m ledge.
##   godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie mantle.avi -s res://tests/previews/mantle_showcase.gd
const Main = preload("res://scripts/main.gd")
const Layers = preload("res://scripts/core/layers.gd")

var main
var p
var cam: Camera3D
var props: Node3D
var start: Vector3


func _initialize() -> void:
	call_deferred("run")


func box(center: Vector3, size: Vector3, color: Color) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	bm.material = mat
	mi.mesh = bm
	b.add_child(mi)
	props.add_child(b)
	b.global_position = center


## Walks the operator at a ledge `top` m high (a block `depth` deep, sunk 1 m into the ground) and presses Space
## in front of it (or jumps first and holds Space when `grab`), watched by `view` (third person side) or first person.
func shot(top: float, depth: float, grab: bool, fp: bool, view: Vector3) -> void:
	for c in props.get_children():
		c.queue_free()
	await process_frame
	var face := start + Vector3(0, 0, -2.6)
	box(face + Vector3(0, (top - 1.0) * 0.5, -depth * 0.5), Vector3(3.2, top + 1.0, depth), Color(0.42, 0.43, 0.4))
	p.global_position = start + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	p.aim_yaw = 0.0
	p.set("_pad_dir", Vector3.FORWARD)
	p.set_first_person(fp)
	main.camera_rig.override = not fp
	if not fp:
		cam.make_current()
	p.reset_physics_interpolation()
	for i in 30:
		await frame(view, fp)
	Input.action_press("move_forward", 0.55)
	var pressed := false
	for i in 200:
		var to_face: float = p.global_position.z - face.z
		if not pressed and ((grab and to_face < 1.6) or (not grab and to_face < 0.75)):
			pressed = true
			Input.action_press("vault")
		if pressed and not grab and i % 2 == 0:
			Input.action_release("vault")
		if p.vaulting:
			Input.action_release("move_forward")
		await frame(view, fp)
		if pressed and not p.vaulting and p.global_position.y > start.y + top - 0.2 and p.is_on_floor():
			break
	Input.action_release("vault")
	Input.action_release("move_forward")
	for i in 45:
		await frame(view, fp)


func frame(view: Vector3, fp: bool) -> void:
	main.camera_rig.yaw = 0.0
	if not fp:
		var c: Vector3 = start + Vector3(0, 1.3, -2.0)
		cam.global_position = c + view
		cam.look_at(c)
	await process_frame


func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	Main.saved_first_person = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120: await process_frame
	main = current_scene
	p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.director.set_physics_process(false)
	main.hud.visible = false
	main.tod.set("running", false)
	main.tod.set("hour", 15.0)
	p.set_loadout([["hk33", {"optic": "reddot"}], ["g17", {}], ["knife_combat", {}]])
	cam = Camera3D.new()
	main.add_child(cam)
	cam.fov = 45.0
	props = Node3D.new()
	main.add_child(props)
	for i in 40: await process_frame
	start = p.global_position
	print("SHOT_START ", Engine.get_frames_drawn())
	await shot(1.6, 1.5, false, false, Vector3(5.5, 0.4, 0.6))
	print("SHOT_START ", Engine.get_frames_drawn())
	await shot(1.25, 2.2, false, true, Vector3.ZERO)
	print("SHOT_START ", Engine.get_frames_drawn())
	await shot(2.3, 1.5, true, false, Vector3(5.0, 0.8, 1.6))
	print("SHOT_END ", Engine.get_frames_drawn())
	quit(0)
