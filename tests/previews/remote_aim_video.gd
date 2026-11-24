extends SceneTree
## Movie-writer clip for v1.51: how a teammate looks on your screen while they aim up and down.
## Run once with "before" and once with "after" and put the two side by side.
## before: before v1.51 (the network carried no aim pitch for the body, so the rifle stayed level at the hip).
## after: v1.51 (SoldierRig.tp_aim_pitch follows the sent pitch and the rifle is raised while firing).
## A red line runs along the barrel; the yellow line and dot are where the player is really looking.
##   godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie aim.avi -s res://tests/previews/remote_aim_video.gd -- before|after
const Rig = preload("res://scripts/characters/soldier_rig.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Palettes = preload("res://scripts/core/palettes.gd")
const SECONDS := 9.0

func _initialize() -> void:
	run.call_deferred()

func make_line(color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material_override = mat
	current_scene.add_child(m)
	return m

func draw_line(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var im := m.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()

func dot(color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material_override = mat
	current_scene.add_child(m)
	return m

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.34, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.8
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 60, 0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor.mesh = pm
	scene.add_child(floor)
	var after := OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "after"
	var rig = Rig.new()
	scene.add_child(rig)
	rig.build(Palettes.player())
	rig.set_process(false)
	var w = Weapon.new()
	w.setup("hk33")
	rig.set_weapon(w, [])
	w.set_process(false)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.fov = 45.0
	var fwd0: Vector3 = -rig.global_transform.basis.z
	var mid: Vector3 = rig.global_position + fwd0 * 1.6 + Vector3(0, 1.45, 0)
	cam.global_position = mid + rig.global_transform.basis.x * 6.0
	cam.look_at(mid, Vector3.UP)
	var barrel := make_line(Color(1, 0.15, 0.15))
	var sight := make_line(Color(1, 0.9, 0.2))
	var tgt := dot(Color(1, 0.9, 0.2))
	for f in int(SECONDS * 60.0):
		var t := f / 60.0
		var pitch := 0.55 * sin(t * TAU / 4.5)        # the teammate looks up and down
		var firing := fmod(t, 3.0) > 0.8               # and fires from the hip every few seconds
		if after:
			rig.tp_aim_pitch = pitch                     # v1.51: the body follows the sent pitch
			rig.aim_target = 1.0 if firing else 0.0     # and the rifle comes up while they fire
		else:
			rig.tp_aim_pitch = 0.0                       # before: no pitch on the body, rifle stays level
			rig.aim_target = 0.0
		rig._animate(1.0 / 60.0)
		var muz := w.find_child("MuzzleAt", true, false) as Node3D
		var tr: Transform3D = muz.global_transform if muz != null else w.global_transform
		draw_line(barrel, tr.origin, tr.origin - tr.basis.z.normalized() * 4.0)
		var eye: Vector3 = rig.global_position + Vector3(0, 1.62, 0)
		var target := eye + (fwd0 * cos(pitch) + Vector3.UP * sin(pitch)) * 4.5
		tgt.global_position = target
		draw_line(sight, eye, target)
		await process_frame
	quit(0)
