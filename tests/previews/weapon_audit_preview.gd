extends SceneTree
## Weapon audit: for each gun, side views (both sides, bare and with optic +
## rail laser), then first person at the hip, aiming, through the inspect and
## through the action cycle after a shot, and the top-down view. Needs a window.
##   godot --path . -s res://tests/previews/weapon_audit_preview.gd -- <out_dir> [gun ids...]
const Main = preload("res://scripts/main.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")

var out := "user://"

func _initialize() -> void:
	call_deferred("run")

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/" + name + ".jpg", 0.85)

## The richest legal attachment set for the side view: an optic on the top rail
## and the rail + laser underneath, where the gun offers them.
func _kit(id: String) -> Dictionary:
	var opts: Dictionary = Data.WEAPONS[id].options
	var att := {}
	for o in ["holo", "reddot", "micro_dot"]:
		if o in opts.get("optic", []):
			att.optic = o
			break
	for m in ["brake", "flash_hider", "suppressor"]:
		if m in opts.get("muzzle", []):
			att.muzzle = m
			break
	if "laser" in opts.get("underbarrel", []):
		att.underbarrel = "laser"
	if "rail" in opts.get("rail", []):
		att.rail = "rail"
	return Data.sanitize(id, att)

func run() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else "user://"
	var ids: Array = a.slice(1) if a.size() > 1 else Data.PRIMARIES + Data.SMGS + Data.SECONDARIES
	root.size = Vector2i(1280, 720)
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.director.set_physics_process(false)
	main.hud.visible = false
	main.tod.set("hour", 13.0)
	p.global_position = Vector3(2.0, 0.05, 30)
	p.aim_yaw = 0.0
	# --- side views, a studio camera on its own
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 30.0
	main.camera_rig.set_process(false)
	main.camera_rig.set_physics_process(false)
	p.visible = false
	for id in ids:
		for v in [["bare", Data.WEAPONS[id].defaults], ["kit", _kit(id)]]:
			var w = Weapon.new()
			main.add_child(w)
			w.setup(id, v[1])
			w.global_position = Vector3(0, 1.4, 60)
			# frame the gun's own bounds (with attachments) to fill the picture
			var faces: PackedVector3Array = w._model_faces()
			var box := AABB(faces[0], Vector3.ZERO)
			for f in faces:
				box = box.expand(f)
			var d := maxf(box.size.z, box.size.y * 1.8) * 1.05 / (2.0 * tan(deg_to_rad(15.0)) * 1.778)
			for side in [1.0, -1.0]:
				w.rotation = Vector3(0, PI * 0.5 * side, 0)
				var c: Vector3 = w.global_transform * box.get_center()
				cam.global_position = c + Vector3(0, 0, d)
				cam.look_at(c)
				cam.current = true
				await frames(6)
				await shot("%s_side_%s_%s" % [id, v[0], "R" if side > 0 else "L"])
			# close-ups (left side): the optic on its rail, and the underside from below
			w.rotation = Vector3(0, PI * 0.5, 0)
			var mount = w.find_child("OpticMount", true, false)
			if mount != null and v[0] == "kit":
				var mc: Vector3 = (mount as Node3D).global_position + Vector3(0, 0.03, 0)
				cam.global_position = mc + Vector3(0, 0, 0.42)
				cam.look_at(mc)
				await frames(4)
				await shot("%s_zoom_optic" % id)
			var c2: Vector3 = w.global_transform * box.get_center()
			cam.global_position = c2 + Vector3(0, -d * 0.75, d * 0.2)
			cam.look_at(c2)
			await frames(4)
			await shot("%s_under_%s" % [id, v[0]])
			w.queue_free()
	cam.queue_free()   # the game camera takes over again
	main.camera_rig.set_process(true)
	main.camera_rig.set_physics_process(true)
	p.visible = true
	p.set_first_person(false)
	p.set_first_person(true)
	# --- first person
	for id in ids:
		p.set_loadout([[id, Data.WEAPONS[id].defaults], ["knife_combat", {}]])
		p.set_first_person(true)
		p.fp_pitch = -0.02
		await frames(70)
		await shot("%s_fp_hip" % id)
		Input.action_press("aim")
		await frames(60)
		await shot("%s_fp_ads" % id)
		Input.action_release("aim")
		await frames(50)
		p.rig.play_inspect()
		var marks := [0.1, 0.22, 0.38, 0.52, 0.66, 0.8, 0.92]
		var k := 0
		while p.rig.inspect_t >= 0.0 and k < marks.size():
			await process_frame
			if p.rig.inspect_t >= marks[k]:
				await shot("%s_fp_inspect_%d" % [id, k])
				k += 1
		await frames(30)
		var w = p.current_weapon()
		if String(w.stats.get("cycle", "")) != "":
			w.cycle_pending = 0.001
			var cm := [0.1, 0.25, 0.4, 0.55, 0.7, 0.85]
			var c := 0
			await frames(2)
			while p.rig.cycle_t >= 0.0 and c < cm.size():
				await process_frame
				if p.rig.cycle_t >= cm[c]:
					await shot("%s_fp_cycle_%d" % [id, c])
					c += 1
			await frames(20)
		# empty reload: mag swap, then the gun's own chambering (rack, slide release, bolt)
		w.ammo = 0
		if w.is_pistol():
			w.fire(p, p.global_position + Vector3.UP, p.global_position + Vector3(0, 1, -10), 0.0)   # locks the slide
			w.ammo = 0
			await frames(10)
		p.start_reload()
		var rm := [0.06, 0.14, 0.5, 0.78, 0.82, 0.86, 0.93]
		var r := 0
		while p.rig.reload_t >= 0.0 and r < rm.size():
			await process_frame
			if p.rig.reload_t >= rm[r]:
				await shot("%s_fp_reload_%d" % [id, r])
				r += 1
		await frames(30)
	# --- top-down / third person
	p.set_first_person(false)
	for id in ids:
		p.set_loadout([[id, Data.WEAPONS[id].defaults], ["knife_combat", {}]])
		await frames(50)
		await shot("%s_tp" % id)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(0)
