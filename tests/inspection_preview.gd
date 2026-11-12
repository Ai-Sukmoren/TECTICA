extends SceneTree
## Small deterministic viewmodel preview; no world generation or gameplay.
var rig
var camera: Camera3D
var frames := 0
var scene: Node3D
var capture_index := 0
const CAPTURES := [0.28, 0.7]

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	root.size = Vector2i(1280, 720)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.07, 0.1, 0.14)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.65, 0.75, 0.9)
	environment.environment.ambient_light_energy = 0.6
	scene.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -40, 0)
	key.light_energy = 2.0
	scene.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(15, 130, 0)
	fill.light_color = Color(0.5, 0.7, 1.0)
	fill.light_energy = 1.0
	scene.add_child(fill)
	rig = load("res://scripts/characters/soldier_rig.gd").new()
	scene.add_child(rig)
	rig.build(load("res://scripts/core/palettes.gd").player())
	var weapon = load("res://scripts/weapons/weapon.gd").new()
	weapon.setup("m4a1")
	rig.set_weapon(weapon, [])
	rig.set_first_person(true)
	rig.set_process(false)
	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.03
	scene.add_child(camera)
	camera.make_current()
	RenderingServer.frame_post_draw.connect(_capture)

func _process(_delta: float) -> bool:
	if rig == null or capture_index >= CAPTURES.size():
		return false
	frames += 1
	rig.inspect_t = CAPTURES[capture_index]
	rig._animate(0.0)
	camera.global_transform = rig.fp_eye
	return false

func _capture() -> void:
	if frames < 30:
		return
	var path := "res://inspection-preview-%d.png" % capture_index
	root.get_texture().get_image().save_png(path)
	print("[inspect-preview] saved ", path)
	capture_index += 1
	frames = 0
	if capture_index == CAPTURES.size():
		RenderingServer.frame_post_draw.disconnect(_capture)
		quit()
