extends SceneTree
## Attachments you cannot see: every gun is rendered bare (its defaults) and with each attachment option, from the
## side, above and below; an option that changes almost no pixels in every view is reported (hidden inside the gun,
## or not drawn). A sheet of the flagged ones is saved for a look. Needs a window.
##   godot --path . -s res://tests/previews/attachment_pixel_audit.gd -- <out_dir>
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
const NOTHING := ["none", "standard", "iron", "integral"]
## the least share of the gun's own pixels an attachment must change in at least one view (0.5%: a small muzzle
## brake on a long rifle changes ~2%, a part hidden inside the gun nothing)
const MIN_CHANGE := 0.005

var cam: Camera3D
var holder: Node3D


func _initialize() -> void:
	call_deferred("run")


func frames(n: int) -> void:
	for i in n:
		await process_frame


func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## Pixels that differ between two renders, and pixels of the gun (not background) in the first.
func diff(a: Image, b: Image, bg: Color) -> Vector2i:
	var changed := 0
	var gun := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - bg.r) + absf(ca.g - bg.g) + absf(ca.b - bg.b) > 0.06:
				gun += 1
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				changed += 1
	return Vector2i(changed, gun)


func views(id: String, att: Dictionary) -> Array:
	for ch in holder.get_children():
		ch.free()
	var w := Weapon.new()
	holder.add_child(w)
	w.setup(id, att)
	var out: Array = []
	for v in [[Vector3(1, 0, 0), Vector3.UP], [Vector3(0, 1, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(0, 0, -1)], [Vector3(-1, 0, 0), Vector3.UP]]:
		cam.position = (v[0] as Vector3) * 3.0
		cam.look_at(Vector3.ZERO, v[1])
		await frames(2)
		out.append(await grab())
	return out


func run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://"
	root.size = Vector2i(720, 360)
	var world := Node3D.new()
	root.add_child(world)
	var bg := Color(0.62, 0.64, 0.68)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 25, 0)
	world.add_child(key)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	world.add_child(cam)
	cam.make_current()
	holder = Node3D.new()
	world.add_child(holder)
	var flagged: Array = []
	var checked := 0
	for id in Data.WEAPONS:
		if Data.WEAPONS[id].get("kind", "") == "melee":
			continue
		cam.size = 1.6 if String(id) in ["uar10", "l96a1", "mosin", "m700", "marlin", "scar_h"] else (0.7 if Data.WEAPONS[id].get("kind", "") == "pistol" else 1.25)
		var base := await views(String(id), {})
		var opts: Dictionary = Data.WEAPONS[id].options
		var defaults: Dictionary = Data.WEAPONS[id].defaults
		for slot in opts:
			for opt in opts[slot]:
				if String(opt) in NOTHING or String(opt) == String(defaults.get(slot, "")) or String(opt).begins_with("builtin"):
					continue
				if slot == "magazine" and String(opt) in ["ap", "hollow", "fast"]:
					continue   # rounds / a lighter mag: nothing new to see
				var shots := await views(String(id), {slot: opt})
				checked += 1
				var best := 0.0
				for i in shots.size():
					var d := diff(base[i], shots[i], bg)
					best = maxf(best, float(d.x) / maxf(1.0, d.y))
				if best < MIN_CHANGE:
					flagged.append([id, slot, opt, best, shots[0]])
					print("  FLAG %s %s=%s changes %.1f%% of the gun at most" % [id, slot, opt, best * 100.0])
	print("  %d attachments checked, %d flagged" % [checked, flagged.size()])
	for f in flagged:
		(f[4] as Image).save_jpg(out + "/flag_%s_%s_%s.jpg" % [f[0], f[1], f[2]], 0.85)
	print("PIXEL AUDIT: flagged=%d" % flagged.size())
	quit(0)
