extends Camera3D
## Title-screen background: slow cinematic camera moves around the frozen
## world (the operator at spawn, a wide crane over the area, a low dolly and a
## landmark of the current map), cross-fading every SHOT_TIME seconds.
## The subject is framed right of centre, clear of the menu panel on the left.

const SHOT_TIME := 9.0
const FADE := 0.6

var shots: Array = []        # [from, to, look_from, look_to]
var shot := 0
var t := 0.0
## 0..1 black overlay strength for the cut (the HUD draws it).
var fade := 1.0
## The operator on the title screen: the world is paused, so its body is told
## to keep animating (breathing, weapon held ready) and slowly looks around.
var _rig: Node
var _base_yaw := 0.0
var _idle_t := 0.0


func setup(main: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = 52.0
	var p: Vector3 = main.player.global_position
	var yaw: float = main.player.aim_yaw
	_rig = main.player.rig
	_base_yaw = yaw
	if _rig != null:
		_rig.process_mode = Node.PROCESS_MODE_ALWAYS
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var chest := p + Vector3.UP * 1.25
	# hero: slow arc in front of the operator
	shots.append([chest + fwd * 3.2 + right * 1.6 + Vector3.UP * 0.2, chest + fwd * 3.0 - right * 1.4 + Vector3.UP * 0.4, chest, chest + Vector3.UP * 0.1])
	# crane: high and wide, drifting
	shots.append([p + Vector3(16, 10, 16), p + Vector3(9, 8, 21), p, p + Vector3(-2, 0, 0)])
	# landmark of the map
	var lm := _landmark(main, p)
	shots.append([lm + Vector3(15, 9.5, 13), lm + Vector3(8, 7.5, 18), lm + Vector3(0, 1.0, 0), lm + Vector3(-2, 1.0, 0)])
	# low dolly past the operator's boots
	shots.append([chest - fwd * 2.6 + right * 2.2 + Vector3.DOWN * 0.8, chest - fwd * 1.8 + right * 3.2 + Vector3.DOWN * 0.6, chest + fwd * 4.0, chest + fwd * 4.0 + Vector3.UP * 0.6])
	shot = 0
	t = 0.0
	_apply(0.0)
	make_current()


## Logging camp (forest), gas station (DEAD END), else a spot near spawn.
func _landmark(main: Node, fallback: Vector3) -> Vector3:
	if String(main.get("map_id")) == "town":
		return Vector3(18, 0, -16)
	var camp = main.level.get("camp")
	if camp is Vector3 and (camp as Vector3).distance_to(fallback) > 12.0:
		return camp
	var outpost = main.level.get("outpost")
	if outpost is Vector3:
		return outpost
	return fallback + Vector3(14, 0, -14)


## Hand the operator back to the game (called on deploy).
func release() -> void:
	if is_instance_valid(_rig):
		_rig.process_mode = Node.PROCESS_MODE_INHERIT
		_rig.aim_yaw = _base_yaw


func _process(delta: float) -> void:
	t += delta
	_idle_t += delta
	if is_instance_valid(_rig):
		# an unhurried scan left and right, with a second slower drift on top
		_rig.aim_yaw = _base_yaw + sin(_idle_t * 0.45) * 0.42 + sin(_idle_t * 0.17 + 1.3) * 0.2
	if t >= SHOT_TIME:
		t = 0.0
		shot = (shot + 1) % shots.size()
	# fade in after each cut, out before the next
	fade = maxf(clampf(1.0 - t / FADE, 0.0, 1.0), clampf((t - (SHOT_TIME - FADE)) / FADE, 0.0, 1.0))
	_apply(t / SHOT_TIME)


func _apply(u: float) -> void:
	if shots.is_empty():
		return
	var s: Array = shots[shot]
	var e := u * u * (3.0 - 2.0 * u)
	var pos: Vector3 = (s[0] as Vector3).lerp(s[1], e)
	var look: Vector3 = (s[2] as Vector3).lerp(s[3], e)
	if pos.distance_to(look) < 0.05:
		return
	global_position = pos
	look_at(look, Vector3.UP)
	# push the subject right of centre (the menu panel covers the left third)
	var d := pos.distance_to(look)
	look_at(look - global_transform.basis.x * d * 0.22, Vector3.UP)
