extends Camera3D
## Kill cam: when the local operator goes down, fly from their view to
## whoever killed them and circle the killer for a few seconds (the first
## moment in slow motion), then hand the screen back. The HUD reads `info`
## for the "KILLED BY" card. Skippable.

const TIME := 3.6        # seconds on screen (real time)
const FLY := 0.75        # fly-over from the victim's view

var main: Node
var killer: Node3D
var info: Dictionary = {}
var t := 0.0
var _from: Transform3D
var _focus := Vector3.ZERO
var _yaw := 0.0
var _dist := 3.6
var _done := false

const ZOMBIE_NAMES := {"boss": "JUGGERNAUT", "walker": "WALKER", "runner": "RUNNER", "brute": "BRUTE",
		"crawler": "CRAWLER", "armored": "ARMORED INFECTED", "berserker": "BERSERKER", "dog": "INFECTED DOG",
		"bat": "INFECTED BAT", "bloater": "BLOATER"}


## Starts the kill cam on `p_killer`; returns false when there is nothing to show.
func start(p_main: Node, p_killer: Node3D, victim: Node3D) -> bool:
	main = p_main
	killer = p_killer
	if not is_instance_valid(killer) or not is_instance_valid(victim):
		return false
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var cur: Camera3D = main.camera_rig.active_camera()
	_from = cur.global_transform
	fov = 55.0
	_focus = _chest(killer)
	var to_victim := victim.global_position - killer.global_position
	to_victim.y = 0.0
	_yaw = atan2(to_victim.x, to_victim.z) if to_victim.length() > 0.1 else 0.0
	var kind := String(killer.get("kind")) if killer.get("kind") != null else ""
	_dist = 6.5 if kind == "boss" else (2.6 if kind in ["dog", "bat", "crawler"] else 3.6)
	info = describe(killer, victim)
	global_transform = _from
	make_current()
	main.camera_rig.override = true
	return true


static func describe(k: Node3D, victim: Node3D) -> Dictionary:
	var kind := String(k.get("kind")) if k.get("kind") != null else ""
	var name := ""
	if k.is_in_group("player"):
		name = String(k.get("display_name")) if String(k.get("display_name")) != "" else "OPERATOR"
	elif kind != "" and k.is_in_group("zombies"):
		name = String(ZOMBIE_NAMES.get(kind, kind.to_upper()))
	else:
		name = "HOSTILE SOLDIER"
	var weapon := ""
	if k.has_method("current_weapon"):
		var ws = k.get("weapons")
		if ws != null and not (ws as Array).is_empty():
			weapon = String(k.current_weapon().stats.name)
	var hp := 0.0
	if k.get("max_health") != null and float(k.max_health) > 0.0:
		hp = clampf(float(k.health) / float(k.max_health), 0.0, 1.0)
	return {"name": name, "weapon": weapon, "hp": hp, "dist": k.global_position.distance_to(victim.global_position)}


func _chest(n: Node3D) -> Vector3:
	var h := 1.2
	if n.has_method("chest_height"):
		h = float(n.chest_height())
	return n.global_position + Vector3.UP * h


func _process(delta: float) -> void:
	if _done:
		return
	var real := delta / maxf(Engine.time_scale, 0.05)
	t += real
	if is_instance_valid(killer):
		_focus = _focus.lerp(_chest(killer), 1.0 - exp(-8.0 * real))
	var a := _yaw + t * 0.32
	var orbit := _focus + Vector3(sin(a) * _dist, _dist * 0.32, cos(a) * _dist)
	if t < FLY:
		var u := t / FLY
		var e := u * u * (3.0 - 2.0 * u)
		global_position = _from.origin.lerp(orbit, e)
		var look := (_from.origin - _from.basis.z * 6.0).lerp(_focus, e)
		look_at(look, Vector3.UP)
	else:
		global_position = orbit
		look_at(_focus, Vector3.UP)
	if t >= TIME:
		finish()


## Back to the normal camera (also used to skip).
func finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(main) and main.camera_rig != null:
		main.camera_rig.override = false
	queue_free()


func active() -> bool:
	return not _done and is_inside_tree()
