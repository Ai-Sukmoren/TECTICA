extends SceneTree
## Before / after for "a weapon skin paints the gun's body only".
## Top: today (the skin paints every part, attachments too). Bottom: only the body panels of the gun itself (its
## coloured factory surfaces: receiver, handguard, stock) take the skin; metal, grip, controls, magazine and every
## attachment keep their factory look.
## godot --path . -s res://tests/previews/skin_body_only_preview.gd -- out.png [gun] [finish]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Skins = preload("res://scripts/skins/skins.gd")

## the attachment slots: everything that is not the gun itself
var REVERSE := false
const ATTACHMENT_SLOTS := ["optic", "muzzle", "rail", "side", "underbarrel"]

## The body shell only: on the gun's own meshes (no skin part), the plastic shell ("polymer") takes the skin;
## a gun with no polymer (a painted rifle) skins only its main paint, the cerakote. Painted metal, steel,
## aluminium, controls, the magazine and every attachment keep their factory look.
func body_only(w, finish: String) -> void:
	var fm := Skins.material(finish, true)
	var hits: Array = []
	var fallback: Array = []
	for node in w.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or String(mi.get_meta("skin_part", "")) != "":
			continue
		for s in mi.mesh.get_surface_count():
			var m = mi.get_surface_override_material(s)
			if m == null: m = mi.mesh.surface_get_material(s)
			if not (m is BaseMaterial3D): continue
			var n := String((m as BaseMaterial3D).resource_name).to_lower()
			if REVERSE:   # the other way round: the painted metal body (H-190; on a painted rifle its other paints)
				if n.contains("h-190"): hits.append([mi, s])
				elif n.contains("coyote") and not n.contains("cerakote"): fallback.append([mi, s])
			elif n.contains("polymer"): hits.append([mi, s])
			elif n.contains("cerakote"): fallback.append([mi, s])
	for h in (hits if not hits.is_empty() else fallback):
		(h[0] as MeshInstance3D).set_surface_override_material(h[1], fm)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	var gid: String = a[1] if a.size() > 1 else "mcx_spear"
	var finish: String = a[2] if a.size() > 2 else "crimson_tiger"
	REVERSE = a.size() > 3 and a[3] == "reverse"
	root.size = Vector2i(1600, 1000)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.11, 0.12, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.environment.ambient_light_energy = 0.9
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 60, 0)
	sun.light_energy = 1.6
	scene.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	scene.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(2.15, 0.12, -0.12), Vector3(0, 0.0, -0.12), Vector3.UP)
	var kit := {"optic": "holo", "underbarrel": "vfg", "muzzle": "suppressor", "side": "laser"} if gid == "mcx_spear" else {}
	var factory := {"magazine": Skins.FACTORY}
	for s in ATTACHMENT_SLOTS:
		factory[s] = Skins.FACTORY
	var y := 0.27
	for parts in [{}, factory]:
		var w = Weapon.new()
		w.setup(gid, kit)
		scene.add_child(w)
		w.position = Vector3(0, y, 0)
		w.rotation_degrees = Vector3(0, 0, 0)
		if parts.is_empty():
			w.apply_skin(finish, parts)
		else:
			body_only(w, finish)
		y -= 0.5
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	quit()
