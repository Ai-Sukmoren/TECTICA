extends RefCounted
## TECTICA stealth: the shared pieces every guard and the operator use.
##   * sound events: every noise has a kind and a radius; walls muffle it and
##     guards hear a guess of where it came from (enemy.gd hear_sound)
##   * light: how lit a spot is (time of day, lamps, the operator's flashlight)
##   * the area's alert level: incidents (gunfire, bodies, witnessed takedowns)
##     raise it, it settles slowly back to a floor that serious incidents lift
##   * bodies: which are hidden, which the guards already know about
##   * coordinated search: each searcher claims a different spot to check
##   * takedowns: who can be taken down from where
## One map runs at a time, so the state is static; main.gd calls reset() per map
## and tick() every physics frame.

const Layers = preload("res://scripts/core/layers.gd")

# ------------------------------------------------------------------ sound

## How alarming each kind of sound is to a guard who hears it:
## 0 curious (looks, may go and check), 1 alarming (weapon up, checks it out),
## 2 combat-grade (calls it in, moves on it with the squad).
const SOUND_ALARM := {
	"footstep": 0, "reload": 0, "impact": 0, "distraction": 0, "body": 0,
	"takedown": 1, "suppressed": 1, "break": 1,
	"gunshot": 2, "explosion": 2,
}
## Share of a sound's radius that carries through a wall or a building.
const WALL_MUFFLE := 0.5


## Tells every guard in earshot about a sound at `pos` that carries `radius` metres.
## Walls between the sound and a guard cut its range (WALL_MUFFLE). Zombies and
## older listeners get their own hear_noise / hear_footstep calls.
static func emit_sound(ctx: Node, pos: Vector3, radius: float, kind: String, source: Node = null) -> void:
	if ctx == null or not ctx.is_inside_tree() or radius <= 0.0 or muted:
		return
	var tree := ctx.get_tree()
	var space: PhysicsDirectSpaceState3D = null
	if ctx is Node3D:
		space = (ctx as Node3D).get_world_3d().direct_space_state
	sounds_emitted += 1
	for e in tree.get_nodes_in_group("enemies"):
		if e.get("is_dead") == true or e == source:
			continue
		var d: float = (e as Node3D).global_position.distance_to(pos)
		if d > radius:
			continue
		var r := radius
		if space != null and d > 2.0 and _blocked(space, pos, e):
			r *= WALL_MUFFLE
			if d > r:
				continue
		if e.has_method("hear_sound"):
			e.hear_sound(pos, r, kind, source)
		elif kind == "footstep" and e.has_method("hear_footstep"):
			e.hear_footstep(pos, r)
		elif e.has_method("hear_noise"):
			e.hear_noise(pos, r)


## Counts sound events (tests and the debug overlay).
static var sounds_emitted := 0
## True while a cutscene runs: guards hear nothing the operator does on camera.
static var muted := false


static func _blocked(space: PhysicsDirectSpaceState3D, pos: Vector3, listener: Node) -> bool:
	var from := pos + Vector3(0, 1.0, 0)
	var to: Vector3 = (listener as Node3D).global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	return not space.intersect_ray(q).is_empty()


# ------------------------------------------------------------------ light

## 0 = pitch dark, 1 = broad daylight: the time of day, plus any lamp in reach.
static func light_at(level, pos: Vector3) -> float:
	var night := 0.0
	if level != null and level.get("night") != null:
		night = float(level.night)
	var amb := lerpf(1.0, 0.15, night)
	var best := amb
	for l in _level_lights(level):
		var light := l as Light3D
		if not is_instance_valid(light) or not light.is_visible_in_tree() or light.light_energy <= 0.05:
			continue
		var reach: float = (light as OmniLight3D).omni_range if light is OmniLight3D else (light as SpotLight3D).spot_range
		var to := pos + Vector3(0, 1.0, 0) - light.global_position
		var d := to.length()
		if d >= reach:
			continue
		if light is SpotLight3D:
			var fwd := -light.global_transform.basis.z
			if fwd.angle_to(to) > deg_to_rad((light as SpotLight3D).spot_angle):
				continue
		var k := (1.0 - d / reach) * clampf(light.light_energy / 2.0, 0.25, 1.0)
		best = maxf(best, minf(amb + k, 1.0))
	return best


static var _lights_for: Object = null
static var _lights: Array = []


## Lamps and other placed lights of the current map (cached per level).
static func _level_lights(level) -> Array:
	if level == null:
		return []
	if _lights_for != level:
		_lights_for = level
		_lights = []
		for key in ["lamp_lights", "lights"]:
			var arr = level.get(key)
			if arr is Array:
				for entry in arr:
					var l = entry.get("light") if entry is Dictionary else entry
					if l is Light3D and not _lights.has(l):
						_lights.append(l)
	return _lights


## How exposed the operator is to a watching guard: 0.3 (crouched in the dark,
## barely moving) .. about 2 (sprinting under a lamp with the flashlight on).
## Multiplies how fast that guard's suspicion builds.
static func exposure(level, p) -> float:
	var light := light_at(level, p.global_position)
	if p.get("flashlight_on") == true:
		light = maxf(light, 1.0) + 0.3
	var k := lerpf(0.35, 1.15, clampf(light, 0.0, 1.0)) + maxf(light - 1.0, 0.0)
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if p.get("sprinting") == true:
		k *= 1.6
	elif speed < 0.3:
		k *= 0.7     # holding still draws less attention than moving
	elif p.get("walking") == true:
		k *= 0.8
	if p.get("crouching") == true:
		k *= 0.6
	return k


# ------------------------------------------------------------------ alert level

## 0 calm, 1 cautious (something happened), 2 high (bodies, an attack).
static var alert := 0.0
## Where alert settles back to; serious incidents lift it for the rest of the map.
static var alert_floor := 0.0
static var bodies_found := 0
## instance ids of bodies the guards have found
static var known_bodies := {}
## Last place a guard placed the operator, shared over the radio, and when.
static var last_known := Vector3.INF
static var last_known_t := -100.0
static var _now := 0.0
## search spot claims: enemy instance id -> claimed point
static var _claims := {}


static func reset() -> void:
	alert = 0.0
	alert_floor = 0.0
	bodies_found = 0
	known_bodies = {}
	last_known = Vector3.INF
	last_known_t = -100.0
	_now = 0.0
	_claims = {}
	_lights_for = null
	_lights = []
	sounds_emitted = 0
	muted = false


## Called every physics frame by main.gd: the alert level settles back toward its floor.
static func tick(delta: float) -> void:
	_now += delta
	if alert > alert_floor:
		alert = maxf(alert - 0.02 * delta, alert_floor)


static func now() -> float:
	return _now


static func raise_alert(level_to: float, floor_to: float = -1.0) -> void:
	alert = maxf(alert, level_to)
	if floor_to >= 0.0:
		alert_floor = maxf(alert_floor, floor_to)


## A guard puts the operator somewhere (seen, heard close, a witness): squadmates
## searching later start from here.
static func report_contact(pos: Vector3) -> void:
	last_known = pos
	last_known_t = _now


# ------------------------------------------------------------------ bodies

## A body is hidden while it lies in a bush or a really dark spot (and isn't being dragged).
static func body_hidden(level, body: Node3D) -> bool:
	if body.get_meta("dragged", false):
		return false
	var pos := body.global_position
	if level != null and level.has_method("concealment") and float(level.concealment(pos)) >= 0.5:
		return true
	return light_at(level, pos) < 0.22


static func is_knocked_out(body: Node) -> bool:
	return body.get_meta("knocked_out", false)


## Bodies of fallen guards that are not hidden and not yet known to the guards.
static func open_bodies(tree: SceneTree, level) -> Array:
	var out: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		if e.get("is_dead") != true or e.get("dummy") == true:
			continue
		if known_bodies.has(e.get_instance_id()):
			continue
		if body_hidden(level, e):
			continue
		out.append(e)
	return out


## A guard found `body`: remembered for the rest of the map, and the alert climbs.
## Returns false if it was already known.
static func report_body(body: Node) -> bool:
	var id := body.get_instance_id()
	if known_bodies.has(id):
		return false
	known_bodies[id] = true
	bodies_found += 1
	if bodies_found >= 2:
		raise_alert(2.0, 1.6)        # a pattern: someone is hunting us
	elif is_knocked_out(body):
		raise_alert(1.4, 1.0)
	else:
		raise_alert(1.8, 1.2)
	return true


# ------------------------------------------------------------------ search

const SEARCH_RINGS := [4.5, 8.5]
const CLAIM_GAP := 3.5


## A spot near `center` for `who` to check that no squadmate is checking: cover
## points first (hiding spots), then a ring of points around the centre. The
## spot is claimed until `who` asks again or leaves the search.
static func search_point(level, center: Vector3, who: Node3D, visited: Array) -> Vector3:
	var cands: Array = []
	if level != null and level.get("cover_points") is Array:
		for c in level.cover_points:
			if not bool(c.get("valid", true)) or bool(c.get("destroyed", false)):
				continue
			var p: Vector3 = c.pos
			if p.distance_to(center) < 11.0:
				cands.append(p)
	var nav_map: RID = who.get_world_3d().navigation_map
	for r in SEARCH_RINGS:
		for i in 8:
			var a := TAU * i / 8.0 + (0.4 if r > 5.0 else 0.0)
			var q := center + Vector3(cos(a), 0, sin(a)) * float(r)
			cands.append(NavigationServer3D.map_get_closest_point(nav_map, q))
	release_claim(who)
	var best := Vector3.INF
	var best_score := INF
	for p in cands:
		var taken := false
		for k in _claims:
			if (_claims[k] as Vector3).distance_to(p) < CLAIM_GAP:
				taken = true
				break
		if taken:
			continue
		var seen := false
		for v in visited:
			if (v as Vector3).distance_to(p) < 2.5:
				seen = true
				break
		if seen:
			continue
		# near the searcher, but spread around the centre
		var score: float = who.global_position.distance_to(p) + randf() * 3.0
		if score < best_score:
			best_score = score
			best = p
	if best == Vector3.INF:
		best = center
	_claims[who.get_instance_id()] = best
	return best


static func release_claim(who: Node) -> void:
	_claims.erase(who.get_instance_id())


static func claims() -> Dictionary:
	return _claims


# ------------------------------------------------------------------ takedowns

const TAKEDOWN_RANGE := 1.7
## how far behind the guard's shoulders the operator must be (cosine of the angle
## between the guard's facing and the direction to the operator)
const TAKEDOWN_BEHIND := -0.25


## True when `p` can take `e` down right now: a living, unaware guard, within
## reach, from behind, on the same level and with nothing in between.
static func can_takedown(p: Node3D, e: Node3D) -> bool:
	if e.get("is_dead") == true or e.get("dummy") == true or e.get("puppet") == true:
		return false
	if e.has_method("is_aware_of") and e.is_aware_of(p):
		return false
	var to_p := p.global_position - e.global_position
	if absf(to_p.y) > 0.7:
		return false
	to_p.y = 0.0
	if to_p.length() > TAKEDOWN_RANGE or to_p.length() < 0.2:
		return false
	var yaw: float = e.get("aim_yaw")
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	if fwd.dot(to_p.normalized()) > TAKEDOWN_BEHIND:
		return false
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 1.1, 0), e.global_position + Vector3(0, 1.1, 0), Layers.WORLD)
	return space.intersect_ray(q).is_empty()


## The closest guard `p` can take down, or null.
static func takedown_target(p: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in p.get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or not e.has_method("is_aware_of"):
			continue
		var d: float = (e as Node3D).global_position.distance_to(p.global_position)
		if d < best_d and d <= TAKEDOWN_RANGE + 0.3 and can_takedown(p, e):
			best = e
			best_d = d
	return best


## Guards who can see `pos` react to what happened there (a takedown, a body
## dropped in the open): each one decides how through its witness() method.
static func notify_witnesses(tree: SceneTree, pos: Vector3, what: String, actor: Node, exclude: Array = []) -> int:
	var n := 0
	for e in tree.get_nodes_in_group("enemies"):
		if e.get("is_dead") == true or exclude.has(e) or not e.has_method("can_see_point"):
			continue
		if e.can_see_point(pos):
			e.witness(pos, what, actor)
			n += 1
	return n
