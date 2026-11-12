extends SceneTree
## Headless smoke test: loads the game, provokes combat, exercises reload,
## weapon switch, damage and death paths. Run:
##   godot --headless --path . -s res://tests/smoke_test.gd

var main
var frame := 0

func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _process(_delta: float) -> bool:
	frame += 1
	var p = main.player
	if frame == 2:
		main.hud._deploy()
	match frame:
		30:
			p.global_position = Vector3(0, 0, 9.5)  # warehouse doorway, in view of guards
			print("[test] moved player into warehouse doorway")
		60:
			p.start_reload()
			print("[test] reload started, timer=", p.reload_timer)
		240:
			p.switch_to(1)
			print("[test] switching weapon")
		320:
			print("[test] active weapon: ", p.current_weapon().stats.name)
			for i in 6:
				p.try_fire(p.global_position + Vector3(0, 1.2, -10))
		360:
			var e = main.enemies[2]
			e.apply_damage(500.0, e.global_position + Vector3(0, 1.1, 0), Vector3(0, 0, -1), p)   # body: helmets stop headshots
			print("[test] killed enemy 2 dead=", e.is_dead)
	if frame == 600:
		var states := []
		for e in main.enemies:
			states.append("%s:%s" % [e.state, "dead" if e.is_dead else "alive"])
		print("[test] enemy states: ", states)
		print("[test] player health=", p.health, " dead=", p.is_dead, " cover points=", main.level.cover_points.size())
		var in_cover := 0
		for e in main.enemies:
			if e.cover != null: in_cover += 1
		print("[test] enemies holding cover: ", in_cover)
		for e in main.enemies:
			if not e.is_dead:
				e.apply_damage(999.0, e.global_position + Vector3.UP, Vector3.FORWARD, p)
	if frame == 700:
		print("[test] game_over=", main.game_over, " victory=", main.victory)
		return true
	return false
