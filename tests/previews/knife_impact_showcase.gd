extends SceneTree
## Knife impact showcase for the movie writer: first-person slashes into a
## zombie (hits, then a kill), a backstab, then the same from top-down.
##   godot --path . --fixed-fps 60 --write-movie knife.avi -s res://tests/previews/knife_impact_showcase.gd
## Prints SHOT_START <frame> so the loading can be trimmed.
const Main = preload("res://scripts/main.gd")
const Settings = preload("res://scripts/core/settings.gd")

func _initialize() -> void:
	call_deferred("run")

func wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await process_frame

## A walker `dist` m in front of the player with `hp` health, held still.
func zombie(main, dist: float, hp: float, facing_away: bool = false, side: float = 0.0) -> Node:
	var p = main.player
	main.director._spawn_one("walker")
	var z = main.enemies[main.enemies.size() - 1]
	z.max_health = hp
	z.health = hp
	z.set_physics_process(false)
	var fwd := Vector3(-sin(p.aim_yaw), 0, -cos(p.aim_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	z.global_position = p.global_position + fwd * dist + right * side
	z.aim_yaw = p.aim_yaw if facing_away else wrapf(p.aim_yaw + PI, -PI, PI)
	z.reset_physics_interpolation()
	await wait(0.05)
	return z

func slash(p, z) -> void:
	p.current_weapon().cooldown = 0.0
	p.try_fire(z.global_position + Vector3.UP * 1.2)

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	Main.saved_first_person = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 70:
		await process_frame
	var main = current_scene
	for k in Settings.PRESET_VALUES:
		Settings.v[k] = Settings.PRESET_VALUES[k][3]
	Settings.v.preset = 3
	main.apply_graphics()
	var p = main.player
	p.health = 100000.0
	main.director.timer = 9999.0
	main.hud.visible = false
	main.tod.set("hour", 17.4)
	p.global_position = Vector3(1.5, 0.05, 30)
	p.aim_yaw = 0.0
	p.fp_pitch = -0.06
	p.weapon_index = p._slot("knife")
	p._equip_current()
	p.set_first_person(true)
	await wait(0.8)
	print("SHOT_START ", Engine.get_frames_drawn())

	# first person: two hits, then the kill
	var z = await zombie(main, 1.35, 150.0)
	await wait(0.5)
	for n in 3:
		slash(p, z)
		await wait(0.62)
	await wait(0.9)
	# backstab: one heavy cut
	z = await zombie(main, 1.3, 1000.0, true)
	await wait(0.5)
	slash(p, z)
	await wait(1.2)
	z.queue_free()
	main.enemies.erase(z)

	# top-down: three infected in a row, cut down one after another
	p.set_first_person(false)
	main.camera_rig.zoom = 7.0   # close in so the cuts read
	main.camera_rig._target_zoom = 7.0
	await wait(0.6)
	var row: Array = []
	for i in 3:
		row.append(await zombie(main, 1.25, 50.0, false, (i - 1) * 0.0))
		row[i].global_position += Vector3(-sin(p.aim_yaw), 0, -cos(p.aim_yaw)) * i * 0.0
	# space them out around the operator
	var angles := [0.0, 1.2, -1.2]
	for i in 3:
		var a: float = p.aim_yaw + angles[i]
		row[i].global_position = p.global_position + Vector3(-sin(a), 0, -cos(a)) * 1.3
		row[i].aim_yaw = wrapf(a + PI, -PI, PI)
		row[i].reset_physics_interpolation()
	await wait(0.6)
	for i in 3:
		var a: float = p.aim_yaw + angles[i]
		for f in 12:
			p.aim_yaw = lerp_angle(p.aim_yaw, a, 0.35)
			await process_frame
		p.aim_yaw = a
		slash(p, row[i])
		await wait(0.65)
	await wait(1.2)
	Settings.mark_clean_exit()
	quit(0)
