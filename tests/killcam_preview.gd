extends SceneTree
## Screenshot of the kill cam on a Juggernaut (needs a window).
##   godot --path . -s res://tests/killcam_preview.gd -- <out_dir>
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "town"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 90: await process_frame
	var main = current_scene
	main.director.timer = 999.0
	main.director._spawn_one("boss")
	var z = main.enemies[main.enemies.size() - 1]
	z.global_position = main.player.global_position + Vector3(2, 0, -7)
	for i in 10: await physics_frame
	main.player.apply_damage(99999.0, main.player.global_position + Vector3.UP, Vector3.FORWARD, z)
	await create_timer(1.6, true, false, true).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(out + "/killcam.jpg", 0.85)
	preload("res://scripts/core/settings.gd").mark_clean_exit()   # a windowed test run is not a crash
	quit(0)
