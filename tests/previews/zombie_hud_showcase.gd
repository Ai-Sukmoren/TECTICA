extends SceneTree
## Movie-writer clip: the loading screen into Zombie Survival, then the wave HUD through a wave (kills counting
## down, points popping), the wave-cleared banner, the countdown to the next wave and a boss wave's banner.
##   godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie hud.avi -s res://tests/previews/zombie_hud_showcase.gd
const Main = preload("res://scripts/main.gd")
const Zombie = preload("res://scripts/characters/zombie.gd")

var main


func _initialize() -> void:
	call_deferred("run")


func frames(n: int, turn: float = 0.0) -> void:
	for i in n:
		if main != null and is_instance_valid(main) and main.get("player") != null:
			main.player.aim_yaw += turn / 60.0
			main.player.health = 100000.0
		await process_frame


func live() -> Array:
	return main.enemies.filter(func(e): return is_instance_valid(e) and e is Zombie and not e.is_dead)


func run() -> void:
	load("res://scripts/core/profile.gd").current = "lilin"
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	Main._new_player_checked = true
	Main.saved_first_person = true
	print("SHOT loading ", Engine.get_frames_drawn())
	change_scene_to_file("res://scenes/loading.tscn")
	while not (current_scene != null and current_scene.get_script() == Main and not root.get_node("MapTransition")._busy):
		await process_frame
	main = current_scene
	var d = main.director
	main.tod.set("running", false)
	main.tod.set("hour", 18.6)
	print("SHOT countdown ", Engine.get_frames_drawn())
	d.wave = 3
	d.timer = 4.2
	await frames(260, 0.25)
	print("SHOT wave ", Engine.get_frames_drawn())
	# the wave runs: kill one every so often so the count drops and points pop
	for k in 14:
		await frames(40, 0.3)
		var zs := live()
		if not zs.is_empty():
			var z = zs[0]
			z.apply_damage(9999.0, z.global_position + Vector3(0, 1.65, 0), Vector3.FORWARD, main.player)
	print("SHOT clear ", Engine.get_frames_drawn())
	d.to_spawn = 0
	for z in live():
		z.apply_damage(9999.0, z.global_position + Vector3(0, 1.65, 0), Vector3.FORWARD, main.player)
	await frames(240, 0.2)
	print("SHOT boss ", Engine.get_frames_drawn())
	d.wave = 4
	d.timer = 3.4
	await frames(480, 0.25)
	print("SHOT_END ", Engine.get_frames_drawn())
	quit(0)
