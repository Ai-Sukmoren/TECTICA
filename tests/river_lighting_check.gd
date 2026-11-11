extends SceneTree
var main
var camera: Camera3D
var frames := 0
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
func _process(_dt):
	frames += 1
	if frames == 2:
		main.hud.hide()
		main.hud.set_process_unhandled_input(false)
		main.set_process_unhandled_input(false)
		main.player.set_process_input(false)
		main.camera_rig.set_process(false)
		camera = Camera3D.new()
		main.add_child(camera)
		camera.current = true
		camera.fov = 65
		camera.global_position = main.level.bridge + Vector3(13, 6, 9)
		camera.look_at(main.level.bridge + Vector3(8, 0, 0))
		main.tod.hour = 12
		main.tod.apply_now()
		for entry in main.level.lamp_lights:
			if entry.group in ["interior", "outpost_interior"]:
				assert(entry.light.visible and entry.light.light_energy > 0.0)
	if frames == 100:
		save.call_deferred("river-preview.png")
	if frames == 110:
		main.tod.hour = 22
		main.tod.apply_now()
		var center = main.level.camp + Vector3(-9, 0, -8)
		camera.global_position = center + Vector3(0, 1.65, 1.9)
		camera.look_at(center + Vector3(0, 1.4, -1))
	if frames == 180:
		save.call_deferred("room-preview.png")
	if frames == 190:
		var count := 0
		for entry in main.level.lamp_lights:
			if entry.group in ["interior", "outpost_interior"]:
				assert(entry.light.visible and entry.light.light_energy > 0.0)
				count += 1
		assert(count == 11)
		main.level.outpost_powered = false
		main.tod.apply_now()
		for entry in main.level.lamp_lights:
			if entry.group == "outpost_interior": assert(not entry.light.visible)
		var map: RID = main.level.get_world_3d().navigation_map
		var bridge: Vector3 = main.level.bridge
		var start := NavigationServer3D.map_get_closest_point(map, bridge + Vector3(0, 0, 6))
		var finish := NavigationServer3D.map_get_closest_point(map, bridge - Vector3(0, 0, 6))
		var path := NavigationServer3D.map_get_path(map, start, finish, true)
		assert(path.size() >= 2)
		print("RIVER: navigation across crossing passed, path points=", path.size())
		print("ROOM LIGHTS: ", count, " fixtures; nighttime and generator checks passed")
		quit()
	return false
func save(filename):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + filename)

