extends SceneTree
## Progression: XP -> level -> rank, weapon levels, daily challenges (same
## three for a date, progress, rewards, reset next day), and the gameplay
## hooks (a real kill in Zombie Survival). Runs in a throwaway account.
##   godot --headless --path . -s res://tests/progression_test.gd
const Main = preload("res://scripts/main.gd")
const Progression = preload("res://scripts/core/progression.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Profile = preload("res://scripts/core/profile.gd")
const TEST_USER := "zz_progress_test"
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func _wipe() -> void:
	Profile.current = TEST_USER
	var dir := ProjectSettings.globalize_path(Profile.path("progress.cfg").get_base_dir())
	for f in ["progress.cfg", "armory.cfg", "loadout.cfg", "campaign.cfg"]:
		if FileAccess.file_exists(dir + "/" + f):
			DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)

func run() -> void:
	_wipe()
	Profile.current = TEST_USER
	Collection._loaded = false
	Progression.reset_cache()

	# levels and ranks
	check(Progression.level_of(0) == 1, "new operator is level 1")
	check(Progression.level_of(Progression.xp_to_next(1)) == 2, "one level's XP reaches level 2")
	check(Progression.rank_name(1) == "RECRUIT I" and Progression.rank_name(6) == "PRIVATE I" and Progression.rank_name(55) == "GENERAL V", "rank names (%s, %s)" % [Progression.rank_name(6), Progression.rank_name(55)])
	check(Progression.level_of(10_000_000) == Progression.MAX_LEVEL, "level caps at %d" % Progression.MAX_LEVEL)
	Progression.ensure()
	var cr0 := Collection.credits
	Progression.add_xp(Progression.xp_to_next(1) + 10)
	check(Progression.level() == 2, "adding XP levels up")
	check(Collection.credits == cr0 + Progression.LEVEL_CREDITS, "level-up pays credits")
	check(Progression.pending.size() == 1 and String(Progression.pending[0][1]) == "level", "level-up pop-up queued")
	Progression.pending.clear()

	# daily challenges
	var a := Progression.roll_daily("2026-11-12")
	var b := Progression.roll_daily("2026-11-12")
	var c := Progression.roll_daily("2026-11-13")
	check(a.size() == 3 and str(a) == str(b), "same date gives the same 3 challenges")
	var ids := {}
	for ch in a: ids[ch.id] = true
	check(ids.size() == 3, "the 3 challenges are different")
	check(str(a) != str(c), "a new day brings new challenges")
	Progression.daily = [{"id": "kills", "tier": 0, "goal": 3, "progress": 0, "done": false},
			{"id": "headshots", "tier": 1, "goal": 2, "progress": 0, "done": false},
			{"id": "boss", "tier": 2, "goal": 1, "progress": 0, "done": false}]
	cr0 = Collection.credits
	for i in 3:
		Progression.on_kill("m4a1", "M4A1", false, i < 2)
	check(bool(Progression.daily[0].done) and bool(Progression.daily[1].done), "kill + headshot challenges complete")
	check(Collection.credits >= cr0 + Progression.REWARD_CR[0] + Progression.REWARD_CR[1], "challenge rewards paid")
	Progression.on_kill("m4a1", "M4A1", false, false)
	check(int(Progression.daily[0].progress) == 3, "finished challenge stops counting")
	Progression.on_boss_kill()
	check(bool(Progression.daily[2].done), "boss challenge completes")
	Progression.day = "1999-01-01"
	Progression.ensure()
	check(Progression.day == Progression.today() and not bool(Progression.daily[0].done), "challenges reset on a new day")

	# weapon levels
	var before := Progression.weapon_level("ak47")
	for i in 5:
		Progression.on_kill("ak47", "AK-47", false, false)
	check(Progression.weapon_level("ak47") == before + 1, "5 kills level the AK-47 to %d" % Progression.weapon_level("ak47"))
	check(Progression.pending.any(func(e): return String(e[1]) == "weapon"), "weapon level pop-up queued")

	# saved per account
	var xp_now := Progression.xp
	Progression.reset_cache()
	Progression.ensure()
	check(Progression.xp == xp_now and Progression.weapon_level("ak47") == before + 1, "progress is saved and reloads")

	# real gameplay hook: shoot a zombie dead
	Main.saved_mode = "zombie"
	Main.saved_map = "forest"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	for i in 60: await process_frame
	var main = current_scene
	main.player.health = 100000.0
	main.director.timer = 999.0
	var xp0 := Progression.xp
	main.director._spawn_one()
	var z = main.enemies[main.enemies.size() - 1]
	z.health = 1.0
	var w = main.player.current_weapon()
	main._on_fired(main.player, w, {"hit": z, "killed": true, "headshot": false, "damage": 30.0, "hit_at": z.global_position, "position": z.global_position})
	check(Progression.xp == xp0 + Progression.XP_KILL, "a kill in game gives %d XP" % Progression.XP_KILL)
	await process_frame
	check(Progression.pending.is_empty(), "HUD shows the pop-ups")
	var lines: Array = main.hud._daily_lines()
	check(lines.size() >= 6, "main menu lists the daily challenges")

	_wipe()
	Profile.current = "lilin"
	Progression.reset_cache()
	Collection._loaded = false
	print("PROGRESSION: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
