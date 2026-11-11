extends SceneTree
const Zombie = preload("res://scripts/characters/zombie.gd")
var main
var frames := 0
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
func _process(_delta):
	frames += 1
	if frames == 2:
		main.hud.hide()
		main.player.rig.hide()
		main.hud.set_process_unhandled_input(false)
		main.set_process_unhandled_input(false)
		main.camera_rig.set_process(false)
		main.player.set_process_input(false)
		main.tod.hour = 12
		main.tod.apply_now()
		var cam := Camera3D.new()
		main.add_child(cam)
		cam.position = main.level.lz_south + Vector3(0,2.4,9)
		cam.look_at(main.level.lz_south + Vector3(0,1,0))
		cam.current = true
		cam.fov = 55
		for i in 3:
			var z := Zombie.new()
			main.add_child(z)
			z.position = main.level.lz_south + Vector3((i-1)*3.0,0,0)
			z.init_zombie(main.player,["crawler","armored","berserker"][i],100,2,10,i)
			z.set_physics_process(false)
			z.aim_yaw = PI
			z.rig.snap_yaw(PI)
			z.rig._process(0.016)
			if i == 2: z._set_enraged(true)
			var label := Label3D.new()
			label.text = z.kind.to_upper()
			label.position = Vector3(0,2.5,0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 40
			z.add_child(label)
	if frames == 120: capture.call_deferred()
	return false
func capture():
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://zombie-types-preview.png")
	quit()
