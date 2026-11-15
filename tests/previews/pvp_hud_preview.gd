extends SceneTree
## Solo deathmatch vs AI screenshots (needs a window): the in-match HUD with
## the scoreboard after the bots have fought for a while, a close look at the
## bots (team markers), and the end-of-match screen.
##   godot --path . -s res://tests/previews/pvp_hud_preview.gd -- <out_dir> [tdm|ffa] [bots]

const Main = preload("res://scripts/main.gd")
const Net = preload("res://scripts/net/net.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var kind := args[1] if args.size() > 1 else "tdm"
	var bots := int(args[2]) if args.size() > 2 else 6
	get_root().size = Vector2i(1600, 900)
	preload("res://scripts/core/profile.gd").current = "pvp_hud_preview"
	Net.host("pvp", 17896, false)
	Main.saved_mode = "pvp"
	Main.saved_map = "desert"
	Main.saved_tdm = kind == "tdm"
	Main.saved_bots = bots
	Main.saved_quality = 1
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var m = current_scene
	m.player.health = 1.0e9
	m.player.max_health = 1.0e9
	for i in Engine.physics_ticks_per_second * 25: await physics_frame
	await _shot("%s/%s_hud.png" % [out, kind])
	# nearest bot in view of the operator's camera
	var near = null
	for e in m.enemies:
		if is_instance_valid(e) and not e.is_dead and (near == null or e.global_position.distance_to(m.player.global_position) < near.global_position.distance_to(m.player.global_position)):
			near = e
	if near != null:
		m.player.global_position = near.global_position + Vector3(0, 0, 5)
		for i in 20: await process_frame
		await _shot("%s/%s_near.png" % [out, kind])
	m._pvp_end(m._pvp_leader())
	for i in 10: await process_frame
	await _shot("%s/%s_over.png" % [out, kind])
	quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("saved ", path)
