extends SceneTree
## Footage for the full-game trailer, one scene per run, under the movie writer:
##   godot --path . --resolution 1920x1080 --fixed-fps 60 --write-movie <scene>.avi \
##         -s res://tests/previews/trailer_shots.gd -- <scene>
## Scenes: menu campaign switch zombie_td zombie_fp move guns sidearms knife
##         grenade night shop daycycle
## Prints "MARK <name> <frame>" at every cut point.
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Nature = preload("res://scripts/world/nature.gd")

var scene := "zombie_fp"
var main
var p

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		scene = a[0]
	call_deferred("run")

func wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await process_frame

func mark(n: String) -> void:
	print("MARK %s %d" % [n, Engine.get_frames_drawn()])

func tap(action: String) -> void:
	Input.action_press(action)
	await process_frame
	await process_frame
	Input.action_release(action)

func nearest(group: String, from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for z in get_nodes_in_group(group):
		if not is_instance_valid(z) or z.get("is_dead") or z == p:
			continue
		var d: float = (z as Node3D).global_position.distance_to(from)
		if d < bd:
			bd = d
			best = z
	return best

## Aim at the nearest live target and fire; `every` = frames between shots.
func fight(group: String, frames_n: int, every: int, reach: float = 30.0) -> void:
	for f in frames_n:
		var z := nearest(group, p.global_position)
		if z != null:
			var d: Vector3 = z.global_position - p.global_position
			var want := atan2(-d.x, -d.z)
			p.aim_yaw = lerp_angle(p.aim_yaw, want, 0.25)
			p.fp_pitch = lerpf(p.fp_pitch, 0.0, 0.2)
			if d.length() < reach and f % every == 0:
				p.current_weapon().cooldown = 0.0
				if p.current_weapon().ammo <= 0:
					p.current_weapon().ammo = int(p.current_weapon().stats.mag)
				p.try_fire(z.global_position + Vector3(0, 1.15, 0))
		p.health = 100000.0
		await process_frame

func fire_forward(n: int, gap: float) -> void:
	for i in n:
		p.current_weapon().cooldown = 0.0
		var fwd := Vector3(-sin(p.aim_yaw), 0, -cos(p.aim_yaw))
		p.try_fire(p.global_position + Vector3(0, 1.4, 0) + fwd * 30.0)
		await wait(gap)

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	var forest := scene in ["campaign", "campaign2", "daycycle", "move"]
	Main.saved_mode = "ch1" if scene in ["campaign", "campaign2"] else "zombie"
	Main.saved_map = "forest" if forest else "town"
	Main.quick_restart = scene != "menu"
	Main.saved_first_person = scene not in ["zombie_td"]
	change_scene_to_file("res://scenes/main.tscn")
	for i in 80:
		await process_frame
	main = current_scene
	for k in Settings.PRESET_VALUES:
		Settings.v[k] = Settings.PRESET_VALUES[k][3]
	Settings.v.preset = 3
	Settings.v.show_fps = false
	main.apply_graphics()
	if scene == "menu":
		var mc = main.hud.menu_cam
		mc.shot = 0
		mc.t = 0.0
		await wait(0.5)
		mark("menu")
		await wait(6.0)
		return finish()
	p = main.player
	p.health = 100000.0
	if main.director != null:
		main.director.timer = 9999.0
	main.hud.visible = scene in ["zombie_td", "shop", "corner", "street", "campaign2"]
	var lvl = main.level
	var rig = get_nodes_in_group("camera_rig")[0]
	match scene:
		"campaign":
			main.tod.set("hour", 9.5)
			p.set_first_person(true)
			await wait(0.5)
			var e := nearest("enemies", p.global_position)
			if e != null:
				var at: Vector3 = e.global_position + (p.global_position - e.global_position).normalized() * 16.0
				p.global_position = Vector3(at.x, lvl.ground_y(at.x, at.z) + 0.05, at.z)
			await wait(0.6)
			mark("campaign")
			await fight("enemies", 60 * 7, 7, 60.0)
		"switch":
			main.tod.set("hour", 14.2)
			p.global_position = Vector3(2.2, 0.05, 44)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.03
			p.set_first_person(true)
			await wait(0.7)
			mark("switch")
			Input.action_press("move_forward")
			await wait(1.6)
			var z0: float = p.global_position.z
			await tap("toggle_view")
			# top-down: keep walking up the road (aim follows the stick, not the mouse)
			p.using_pad = true
			rig.yaw = 0.0
			for f in 170:
				p.set("_pad_dir", Vector3.FORWARD)
				await process_frame
			print("TD_MOVED %.2f" % (z0 - p.global_position.z))
			p.using_pad = false
			await tap("toggle_view")
			await wait(1.6)
			Input.action_release("move_forward")
		"zombie_td":
			main.tod.set("hour", 15.5)
			p.global_position = Vector3(0.5, 0.05, 1.0)
			p.set_loadout([["hk33", {"optic": "reddot"}], ["g17", {}], ["knife_combat", {}]])
			p.set_first_person(false)
			main.director.timer = 0.5
			await wait(5.0)
			mark("zombie_td")
			# fight on the move: back away from the pack, strafing, gun on the nearest
			p.using_pad = true
			var p0: Vector3 = p.global_position
			for f in 60 * 8:
				var z := nearest("zombies", p.global_position)
				for act in ["move_forward", "move_back", "move_left", "move_right"]:
					Input.action_release(act)
				if z != null:
					var d: Vector3 = z.global_position - p.global_position
					p.set("_pad_dir", Vector3(d.x, 0, d.z).normalized())
							# a fighting retreat down the road, weaving a little
					Input.action_press("move_back")
					if (f / 50) % 3 == 0:
						Input.action_press("move_left")
					elif (f / 50) % 3 == 2:
						Input.action_press("move_right")
					if d.length() < 24.0 and f % 6 == 0:
						p.current_weapon().cooldown = 0.0
						if p.current_weapon().ammo <= 0:
							p.current_weapon().ammo = int(p.current_weapon().stats.mag)
						p.try_fire(z.global_position + Vector3(0, 1.15, 0))
				p.health = 100000.0
				await process_frame
			for act in ["move_forward", "move_back", "move_left", "move_right"]:
				Input.action_release(act)
			print("TD_MOVED %.2f" % p0.distance_to(p.global_position))
		"zombie_fp":
			main.tod.set("hour", 18.4)
			p.global_position = Vector3(0.5, 0.05, 1.0)
			p.set_loadout([["hk33", {"optic": "holo"}], ["g17", {}], ["knife_combat", {}]])
			p.set_first_person(true)
			main.director.timer = 0.5
			await wait(6.0)
			mark("zombie_fp")
			await fight("zombies", 60 * 8, 5, 26.0)
		"move":
			main.tod.set("hour", 13.0)
			var camp: Vector3 = lvl.camp
			p.global_position = Vector3(camp.x, lvl.ground_y(camp.x, camp.z + 16) + 0.05, camp.z + 16)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.02
			p.set_first_person(false)
			rig.yaw = 0.0
			# a crate to vault, dead ahead
			var cz: float = camp.z + 4.0
			lvl.crate(Vector3(camp.x, lvl.ground_y(camp.x, cz), cz), Vector3(1.6, 0.95, 0.9))
			await wait(0.8)
			mark("move")
			p.using_pad = true
			Input.action_press("move_forward")
			Input.action_press("sprint")
			for f in 50:
				p.set("_pad_dir", Vector3.FORWARD)
				await process_frame
			await tap("crouch")          # slide
			for f in 70:
				p.set("_pad_dir", Vector3.FORWARD)
				await process_frame
			mark("vault")
			for f in 110:               # sprint into the crate: auto vault
				p.set("_pad_dir", Vector3.FORWARD)
				if f % 20 == 0:
					Input.action_press("vault")
				elif f % 20 == 2:
					Input.action_release("vault")
				await process_frame
			mark("kick")
			await tap("kick")
			for f in 70:
				p.set("_pad_dir", Vector3.FORWARD)
				await process_frame
			Input.action_release("sprint")
			Input.action_release("move_forward")
			await wait(0.4)
		"guns":
			main.tod.set("hour", 14.5)
			p.global_position = Vector3(2.0, 0.05, 30)
			p.aim_yaw = 0.0
			p.fp_pitch = -0.01
			p.set_first_person(true)
			for g in [["uar10", {"optic": "scope"}, 2, 1.2, true], ["marlin", {"optic": "reddot"}, 3, 0.75, false],
					["as_val", {"optic": "holo"}, 14, 0.07, false], ["mgp7", {"optic": "reddot"}, 16, 0.065, false],
					["aug_a1", {"optic": "acog"}, 10, 0.1, true]]:
				p.set_loadout([[g[0], g[1]], ["g17", {}], ["knife_combat", {}]])
				p.set_first_person(true)
				await wait(0.9)
				if g[4]:
					Input.action_press("aim")
					await wait(0.7)
				mark(String(g[0]))
				await fire_forward(int(g[2]), float(g[3]))
				await wait(0.5)
				Input.action_release("aim")
				await wait(0.3)
		"sidearms":
			main.tod.set("hour", 13.0)
			p.global_position = Vector3(2.0, 0.05, 30)
			p.aim_yaw = 0.0
			p.fp_pitch = -0.02
			for g in ["g17", "vp9"]:
				p.set_loadout([[g, {}], ["knife_combat", {}]])
				p.set_first_person(true)
				await wait(1.0)
				mark(g)
				for sh in 2:
					await tap("fire")
					await wait(1.0)
		"knife":
			main.tod.set("hour", 17.6)
			p.global_position = Vector3(0, 0.05, 38)
			p.aim_yaw = 0.0
			p.set_loadout([["hk33", {}], ["g17", {}], ["butterfly", {}]])
			p.weapon_index = 2
			p._equip_current()
			p.set_first_person(true)
			await wait(0.8)
			mark("knife")
			p.rig.play_inspect()
			while p.rig.inspect_t >= 0.0:
				await process_frame
			mark("slash")
			for n in 3:
				p.current_weapon().cooldown = 0.0
				p.try_fire(p.global_position + Vector3(0, 1.2, -3))
				await wait(0.55)
		"grenade":
			main.tod.set("hour", 15.0)
			p.global_position = Vector3(2.0, 0.05, 30)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.0
			p.set_first_person(true)
			for k in 5:
				lvl.crate(Vector3(0.6 + (k % 3) * 1.25, 0.0 if k < 3 else 1.0, 19.0 + (0.2 if k >= 3 else 0.0)), Vector3(1.1, 1.0, 1.1), 0.1 * k)
			p.grenades = 3
			await wait(1.0)
			mark("grenade")
			await tap("grenade")
			await wait(4.5)
		"night":
			main.tod.set("hour", 23.0)
			p.global_position = Vector3(-6.0, 0.05, 24)
			p.aim_yaw = 0.6
			p.fp_pitch = 0.05
			p.set_first_person(true)
			await wait(1.0)
			mark("dark")
			await wait(0.8)
			p.set_flashlight(true)
			mark("torch")
			for f in 150:
				p.aim_yaw = 0.6 - f / 150.0 * 1.0
				await process_frame
			mark("nvg")
			await tap("nvg")
			for f in 200:
				p.aim_yaw = -0.4 + f / 200.0 * 1.2
				await process_frame
		"shop":
			main.tod.set("hour", 16.0)
			p.global_position = Vector3(0.5, 0.05, 6.0)
			p.set_first_person(true)
			main.director.shop.points = 4200
			await wait(1.0)
			var ev := InputEventAction.new()
			ev.action = "shop"
			ev.pressed = true
			Input.parse_input_event(ev)
			await wait(0.4)
			mark("shop")
			for k in 4:
				var dn := InputEventAction.new()
				dn.action = "ui_down"
				dn.pressed = true
				Input.parse_input_event(dn)
				await wait(0.7)
			await wait(1.0)
		"corner":
			# hold the corner of a house, lean out, shoot, get back in
			main.tod.set("hour", 16.6)
			lvl.zombie_spawns = [Vector3(-12.5, 0, -40), Vector3(-11, 0, -36), Vector3(-13, 0, -33), Vector3(-10.5, 0, -44)]
			p.set_loadout([["hk33", {"optic": "reddot", "underbarrel": "vgrip"}], ["g17", {}], ["knife_combat", {}]])
			p.set_first_person(true)
			p.global_position = Vector3(-14.45, 0.05, -12.75)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.0
			main.director.timer = 0.5
			await wait(3.0)
			mark("corner")
			for rep_i in 3:
				await wait(0.5)
				Input.action_press("peek_right")
				await wait(0.3)
				Input.action_press("aim")
				await wait(0.35)
				for f in 80:
					var z := nearest("zombies", p.global_position)
					if z != null:
						var d: Vector3 = z.global_position - (p.global_position + Vector3(0.6, 0, 0))
						p.aim_yaw = lerp_angle(p.aim_yaw, atan2(-d.x, -d.z), 0.2)
						if f % 6 == 0 and f > 8 and f % 30 < 20:
							p.current_weapon().cooldown = 0.0
							p.try_fire(z.global_position + Vector3(0, 1.25, 0))
					p.health = 100000.0
					await process_frame
				Input.action_release("aim")
				Input.action_release("peek_right")
				p.aim_yaw = lerp_angle(p.aim_yaw, 0.0, 0.6)
				await wait(0.35)
				if rep_i == 0:
					await tap("reload")
					await wait(1.6)
			mark("corner_end")
		"street":
			# advance up the road, sights up, bursts into the wave ahead
			main.tod.set("hour", 17.2)
			lvl.zombie_spawns = [Vector3(1, 0, 6), Vector3(-2, 0, 2), Vector3(3, 0, 0), Vector3(0, 0, -4), Vector3(-3, 0, 9)]
			p.set_loadout([["hk33", {"optic": "holo", "underbarrel": "vgrip"}], ["g17", {}], ["knife_combat", {}]])
			p.set_first_person(true)
			p.global_position = Vector3(1.5, 0.05, 40)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.0
			main.director.timer = 0.5
			await wait(3.2)
			mark("street")
			Input.action_press("move_forward")
			for f in 60 * 9:
				var z := nearest("zombies", p.global_position)
				var ads := z != null and z.global_position.distance_to(p.global_position) < 26.0
				if ads:
					Input.action_press("aim")
					if f % 90 > 60:
						Input.action_release("move_forward")
					else:
						Input.action_press("move_forward")
					var d: Vector3 = z.global_position - p.global_position
					p.aim_yaw = lerp_angle(p.aim_yaw, atan2(-d.x, -d.z), 0.18)
					if f % 7 == 0 and f % 40 < 26 and p.rig.aim_amt > 0.7:
						p.current_weapon().cooldown = 0.0
						if p.current_weapon().ammo <= 0:
							p.current_weapon().ammo = int(p.current_weapon().stats.mag)
						p.try_fire(z.global_position + Vector3(0, 1.3, 0))
				else:
					Input.action_release("aim")
				p.health = 100000.0
				await process_frame
			Input.action_release("aim")
			Input.action_release("move_forward")
		"fpmove":
			main.tod.set("hour", 14.5)
			p.set_first_person(true)
			p.global_position = Vector3(1.8, 0.05, 44)
			p.aim_yaw = 0.0
			p.fp_pitch = 0.02
			lvl.crate(Vector3(1.8, 0, 24.0), Vector3(1.8, 0.95, 0.9))
			await wait(0.8)
			mark("fpmove")
			Input.action_press("move_forward")
			Input.action_press("sprint")
			await wait(1.1)
			await tap("crouch")
			await wait(1.1)
			mark("fpvault")
			for f in 130:
				if f % 16 == 0:
					Input.action_press("vault")
				elif f % 16 == 2:
					Input.action_release("vault")
				await process_frame
			mark("fpkick")
			await tap("kick")
			await wait(1.0)
			Input.action_release("sprint")
			Input.action_release("move_forward")
			await wait(0.3)
		"campaign2":
			main.tod.set("hour", 9.5)
			p.set_loadout([["hk33", {"optic": "reddot"}], ["g17", {}], ["knife_combat", {}]])
			p.set_first_person(true)
			await wait(0.5)
			var e := nearest("enemies", p.global_position)
			var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
			if e != null:
				# a spot 13 m out with a clear line to the enemy
				for k in 16:
					var a := TAU * k / 16.0
					var at: Vector3 = e.global_position + Vector3(cos(a), 0, sin(a)) * 13.0
					at.y = lvl.ground_y(at.x, at.z) + 0.05
					var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.5, 0), e.global_position + Vector3(0, 1.3, 0), 1)
					if space.intersect_ray(q).is_empty():
						p.global_position = at
						var d: Vector3 = e.global_position - at
						p.aim_yaw = atan2(-d.x, -d.z)
						break
			await wait(0.4)
			mark("campaign2")
			Input.action_press("aim")
			await fight("enemies", 60 * 7, 8, 45.0)
			Input.action_release("aim")
		"ak":
			main.tod.set("hour", 14.5)
			p.global_position = Vector3(2.0, 0.05, 30)
			p.aim_yaw = 0.0
			p.fp_pitch = -0.01
			p.set_loadout([["aug_a1", {"optic": "reddot"}], ["g17", {}], ["knife_combat", {}]])
			p.set_first_person(true)
			await wait(0.9)
			mark("aug_a1")
			await fire_forward(5, 0.1)
			Input.action_press("aim")
			await wait(0.5)
			await fire_forward(8, 0.1)
			await wait(0.4)
			Input.action_release("aim")
		"daycycle":
			rig.override = true
			var cam := Camera3D.new()
			cam.fov = 62
			root.add_child(cam)
			var camp2: Vector3 = lvl.camp
			var from := camp2 + Vector3(-14, 6.5, 20)
			cam.global_position = from
			cam.look_at(camp2 + Vector3(0, 5, -10))
			for f in 40:
				cam.make_current()
				Nature.set_view(from)
				main.tod.set("hour", 5.6)
				await process_frame
			mark("daycycle")
			for f in 420:
				var u := f / 419.0
				main.tod.set("hour", lerpf(5.6, 22.5, u))
				cam.global_position = from + Vector3(8.0 * u, 0.6 * u, -3.0 * u)
				cam.look_at(camp2 + Vector3(0, 5, -10))
				cam.make_current()
				Nature.set_view(cam.global_position)
				await process_frame
	finish()

func finish() -> void:
	mark("end")
	Settings.mark_clean_exit()
	quit(0)
