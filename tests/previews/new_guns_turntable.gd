extends SceneTree
## Movie-writer clip: each gun on a slow turntable in a studio, SECONDS each, then the next.
## An id written as id+kit is fitted with what it accepts of the side-rail laser, the angled foregrip and a suppressor;
## id+vfg with the side-rail laser and the vertical foregrip.
## Prints "GUN <id> <first frame>" so captions can be timed.
##   godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie guns.avi -s res://tests/previews/new_guns_turntable.gd -- <ids...>
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const SECONDS := 3.5

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.18, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.85, 0.95)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	scene.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.8
	scene.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	scene.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 0.18, 1.55)
	cam.look_at(Vector3(0, 0.0, 0), Vector3.UP)
	for id in ids:
		var pivot := Node3D.new()
		scene.add_child(pivot)
		var w = Weapon.new()
		pivot.add_child(w)
		var gid := String(id).trim_suffix("+kit").trim_suffix("+vfg")
		var att := {}
		if String(id).ends_with("+kit"):
			att = Data.sanitize(gid, {"side": "laser", "underbarrel": "afg", "muzzle": "suppressor"})
		elif String(id).ends_with("+vfg"):
			att = Data.sanitize(gid, {"side": "laser", "underbarrel": "vfg"})
		w.setup(gid, att)
		w.set_process(false)
		# the laser beam is aimed every frame by the weapon's own update, which is off here
		for beam in [w.get("_beam"), w.get("_beam_dot")]:
			if beam != null:
				beam.visible = false
		await process_frame
		# centre the gun on the pivot from its drawn bounds
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for n in w.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var a: AABB = pivot.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
			lo = lo.min(a.position)
			hi = hi.max(a.end)
		w.position = -(lo + hi) * 0.5
		var size := (hi - lo).length()
		cam.position = Vector3(0, 0.1, 0.3 + size * 1.25)
		cam.look_at(Vector3.ZERO, Vector3.UP)
		print("GUN ", id, " ", Engine.get_frames_drawn(), " ", w.attachments)
		var n := int(SECONDS * 60.0)
		for f in n:
			pivot.rotation.y = -PI * 0.5 + 0.9 * sin(f / float(n) * PI - PI * 0.5) + 0.2
			pivot.rotation.x = 0.08
			await process_frame
		pivot.queue_free()
		await process_frame
	quit(0)
