extends RefCounted
## Starting balance values, not measured difficulty targets. See README playtest notes.
const UNLOCKS := {"crawler": 3, "armored": 5, "berserker": 6}
const RAGE_HEALTH := 0.5
const RAGE_SPEED := 1.55
const RAGE_DAMAGE := 1.3
const ARMOR_MULTIPLIER := 0.4

static func pick(wave: int, roll: float) -> String:
	# One roll; new variants replace walkers rather than adding extra enemies.
	var pool := [["walker", 45.0]]
	if wave >= 2: pool.append(["runner", minf(8.0 * wave, 35.0)])
	if wave >= 3: pool.append(["crawler", 15.0])
	if wave >= 4: pool.append(["brute", 10.0])
	if wave >= 5: pool.append(["armored", 12.0])
	if wave >= 6: pool.append(["berserker", 12.0])
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
	return {"hp": hp, "damage": damage, "speed": speed}
