extends SceneTree
## Close-ups of attachment fit: one sheet per slot, a row per gun and a column
## per option, each tile a side view centred on that slot's anchor. Needs a window.
##   godot --path . -s res://tests/previews/attachment_zoom.gd -- <out_dir> [slot...] [--guns=a,b]
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

const TILE := Vector2i(300, 200)
## slot -> [anchor node name, offset in weapon space, view height in metres]
const FOCUS := {
	"muzzle": ["MuzzleAt", Vector3(0, 0, -0.02), 0.14],
	"underbarrel": ["UnderAt", Vector3(0, -0.03, 0), 0.16],
	"optic": ["", Vector3.ZERO, 0.16],
	"stock": ["StockAt", Vector3(0, -0.02, 0.06), 0.2],
	"magazine": ["MagAt", Vector3(0, -0.07, 0), 0.24],
}

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _find(n: Node, nm: String) -> Node3D:
	if String(n.name) == nm:
		return n as Node3D
	for c in n.get_children():
		var f := _find(c, nm)
		if f != null:
			return f
	return null

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var slots: Array = []
	var guns: Array = Data.PRIMARIES + Data.SECONDARIES
	for a in args.slice(1):
		if String(a).begins_with("--guns="):
			guns = String(a).substr(7).split(",")
		else:
			slots.append(a)
	if slots.is_empty():
		slots = FOCUS.keys()
	root.size = TILE
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.75, 0.77, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 60, 0)
	key.light_energy = 1.2
	world.add_child(key)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	cam.make_current()
	for slot in slots:
		var cols := 0
		for id in guns:
			cols = maxi(cols, (Data.WEAPONS[id].options[slot] as Array).size())
		var sheet := Image.create(TILE.x * cols, TILE.y * guns.size() + 0, false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.3, 0.3, 0.32))
		for gi in guns.size():
			var id: String = guns[gi]
			var options: Array = Data.WEAPONS[id].options[slot]
			for oi in options.size():
				var att: Dictionary = Data.WEAPONS[id].defaults.duplicate()
				att[slot] = options[oi]
				var w := Weapon.new()
				world.add_child(w)
				w.setup(id, att)
				w.rotation.y = PI * 0.5   # muzzle to the left
				await frames(1)
				var f: Array = FOCUS[slot]
				var centre: Vector3
				if slot == "optic":
					var lp := Vector3(0, 0.12, -0.06) if not w.stats.kind == "pistol" else Vector3(0, 0.07, -0.04)
					centre = w.global_transform * lp
				else:
					var anchor := _find(w, String(f[0]))
					if anchor == null:
						w.queue_free()
						continue
					centre = anchor.global_position + w.global_transform.basis * (f[1] as Vector3)
				cam.size = float(f[2])
				cam.global_position = centre + Vector3(0, 0, 2.0)
				await frames(3)
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				img.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(oi * TILE.x, gi * TILE.y))
				w.queue_free()
			print("  %s %s done" % [slot, id])
		var path := "%s/zoom_%s.jpg" % [out, slot]
		sheet.save_jpg(path, 0.9)
		print("saved ", path)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
