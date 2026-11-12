extends SceneTree
## Shoots zombies in Zombie Survival and screenshots the hit feedback
## (damage numbers, hit flash, headshot marker). Needs a GPU:
##   godot --path . -s res://tests/hitfx_preview.gd -- <out.png>
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	var p = main.player
	p.health = 100000.0
	main.director.active = true
	main.director.timer = 999.0
	main.director.to_spawn = 0
	for k in 3:
		main.director._spawn_one()
	await physics_frame
	var i := 0
	var targets: Array = []
	for e in main.enemies:
		e.global_position = p.global_position + Vector3(-2.0 + i * 2.0, 0, -5.5)
		e.max_health = 400.0
		e.health = 400.0
		e.set_physics_process(false)
		targets.append(e)
		i += 1
	await physics_frame
	var nums_seen := 0
	for shot in 9:
		var t = targets[shot % targets.size()]
		var head: bool = shot % 3 == 2
		var aim: Vector3 = t.global_position + Vector3.UP * (t.head_height() if head else 1.1)
		p.current_weapon().cooldown = 0.0
		p.try_fire(aim)
		nums_seen = maxi(nums_seen, main.hud._dmg_nums.size())
		for k in 4: await process_frame
	print("[hitfx] damage numbers on screen: ", main.hud._dmg_nums.size(), " max seen ", nums_seen,
			"  flash overlay on target: ", targets[2]._flash_meshes.size() > 0)
	var out := OS.get_cmdline_user_args()
	if not out.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out[0])
	quit(0)
