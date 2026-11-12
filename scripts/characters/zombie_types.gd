extends RefCounted
## Starting balance values, not measured difficulty targets. See README playtest notes.
const UNLOCKS := {"dog": 2, "crawler": 3, "bat": 3, "bloater": 4, "armored": 5, "berserker": 6}
## Kinds drawn by creature_body.gd instead of the humanoid rig.
const CREATURES := ["dog", "bat"]
const BLOAT_DAMAGE := 75.0
const BLOAT_RADIUS := 4.5
const RAGE_HEALTH := 0.5
const RAGE_SPEED := 1.55
const RAGE_DAMAGE := 1.3
const ARMOR_MULTIPLIER := 0.4
## Juggernaut boss: one joins every BOSS_EVERY-th wave (never from pick()).
const BOSS_EVERY := 5
const BOSS_SCALE := 1.6
const BOSS_SLAM_RANGE := 4.0     # starts a slam when the target is this close
const BOSS_SLAM_RADIUS := 4.6    # slam shockwave reach
const BOSS_SLAM_WINDUP := 0.9
const BOSS_SLAM_CD := 5.0
const BOSS_CHARGE_MIN := 7.0     # charges targets between these distances
const BOSS_CHARGE_MAX := 22.0
const BOSS_CHARGE_WINDUP := 0.7
const BOSS_CHARGE_TIME := 1.6
const BOSS_CHARGE_SPEED := 7.5
const BOSS_CHARGE_CD := 8.0
const BOSS_WALL_STUN := 2.2      # charged into a wall: dazed, takes extra damage
const BOSS_STUN_DAMAGE := 1.5
const BOSS_RAGE_HEALTH := 0.5    # phase 2 below this fraction of health
const BOSS_SCORE := 1500
const BOSS_CREDITS := 200

static func is_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % BOSS_EVERY == 0

static func pick(wave: int, roll: float) -> String:
	# One roll; new variants replace walkers rather than adding extra enemies.
	var pool := [["walker", 45.0]]
	if wave >= 2: pool.append(["runner", minf(8.0 * wave, 35.0)])
	if wave >= 3: pool.append(["crawler", 15.0])
	if wave >= 4: pool.append(["brute", 10.0])
	if wave >= 5: pool.append(["armored", 12.0])
	if wave >= 6: pool.append(["berserker", 12.0])
	if wave >= 2: pool.append(["dog", minf(5.0 * wave, 18.0)])
	if wave >= 3: pool.append(["bat", 10.0])
	if wave >= 4: pool.append(["bloater", 8.0])
	var total := 0.0
	for entry in pool: total += entry[1]
	var cursor := clampf(roll, 0.0, 0.999999) * total
	for entry in pool:
		cursor -= entry[1]
		if cursor < 0.0: return entry[0]
	return "walker"

static func stats(kind: String, wave: int) -> Dictionary:
	var hp := 60.0 * (1.0 + 0.18 * (wave - 1))
	var damage := 8.0 + 1.2 * wave
	var speed := minf(1.75 + 0.05 * wave, 2.7)
	match kind:
		"runner":
			hp *= 0.8
			speed = minf(3.6 + 0.08 * wave, 4.6)
		"brute":
			hp *= 3.0
			damage *= 2.0
			speed = 1.5
		"crawler":
			hp *= 0.65
			damage *= 0.8
			speed = 2.1
		"armored":
			hp *= 1.6
			speed = 1.65
		"berserker":
			hp *= 1.2
			speed = 2.7
		"dog":
			hp *= 0.55
			damage *= 0.7
			speed = minf(4.4 + 0.06 * wave, 5.2)
		"bat":
			hp *= 0.3
			damage *= 0.45
			speed = 3.8
		"bloater":
			hp *= 1.4
			speed = 1.3
		"boss":
			hp *= 16.0 * (1.0 + 0.25 * maxf(floorf(float(wave) / BOSS_EVERY) - 1.0, 0.0))
			damage *= 2.2
			speed = 1.7
	return {"hp": hp, "damage": damage, "speed": speed}


static func is_creature(kind: String) -> bool:
	return kind in CREATURES
