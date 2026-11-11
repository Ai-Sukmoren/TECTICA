extends StaticBody3D
## Destructible cover / prop. Bullets chip it (pieces get knocked loose, the
## prop visibly sags), explosions wreck it. When destroyed it bursts into
## physics fragments built from its own meshes, its cover points and radar
## footprint are removed and the level re-bakes navigation around the gap.
## Red barrels are explosive and chain-react.

const FX = preload("res://scripts/fx/fx.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Layers = preload("res://scripts/core/layers.gd")
const ML = preload("res://scripts/core/mesh_lib.gd")
const Blast = preload("res://scripts/weapons/blast.gd")
const Fragment = preload("res://scripts/world/fragment.gd")
const Net = preload("res://scripts/net/net.gd")

## kind -> [health, bullet multiplier, blast multiplier, chip colour, sound family]
const KINDS := {
	"wood": [170.0, 1.0, 2.5, Color(0.55, 0.45, 0.3), "wood"],
	"desk": [200.0, 0.9, 2.5, Color(0.35, 0.34, 0.32), "hard"],
	"sand": [480.0, 0.35, 3.4, Color(0.6, 0.55, 0.42), "sand"],
	"concrete": [650.0, 0.12, 2.4, Color(0.62, 0.62, 0.6), "hard"],
	"metal": [150.0, 0.7, 2.5, Color(0.4, 0.42, 0.42), "hard"],
	"rack": [260.0, 0.6, 2.5, Color(0.35, 0.37, 0.38), "hard"],
	"log": [600.0, 0.25, 2.0, Color(0.45, 0.33, 0.2), "wood"],
	"hesco": [1100.0, 0.15, 1.6, Color(0.6, 0.55, 0.42), "sand"],
	"explosive": [40.0, 1.0, 3.0, Color(0.6, 0.25, 0.15), "hard"],
}
const MAX_PIECES := 34

var kind := "wood"
## Stable id shared by every peer (level build order is deterministic).
var net_id := -1
var health := 100.0
var max_health := 100.0
var destroyed := false
var level: Node
var covers: Array = []
var rects: Array = []
var dependents: Array = []   # props resting on this one fall with it
var last_attacker: Node
var _damage_stage := 0
var _size := Vector3.ONE     # local AABB size (set by the level after building)
var _center_local := Vector3(0, 0.5, 0)


func setup_kind(p_kind: String, p_level: Node) -> void:
	kind = p_kind
	level = p_level
	max_health = float(KINDS[kind][0]) * randf_range(0.9, 1.1)
	health = max_health
	add_to_group("destructibles")
	if level != null and level.has_method("register_prop"):
		net_id = level.register_prop(self)


## Called by the level once all meshes / shapes are attached.
func finalize() -> void:
	var box := AABB()
	var first := true
	for c in get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var a := AABB(c.position - c.shape.size * 0.5, c.shape.size)
			box = a if first else box.merge(a)
			first = false
		elif c is CollisionShape3D and c.shape is CylinderShape3D:
			var r: float = c.shape.radius
			var h: float = c.shape.height
			var a := AABB(c.position - Vector3(r, h * 0.5, r), Vector3(r * 2.0, h, r * 2.0))
			box = a if first else box.merge(a)
			first = false
	if not first:
		_size = box.size
		_center_local = box.get_center()


func center() -> Vector3:
	return global_transform * _center_local


func extent() -> float:
	return _size.length() * 0.5


func health_frac() -> float:
	return health / max_health


# ------------------------------------------------------------------ damage

func apply_damage(amount: float, hit_pos: Vector3, dir: Vector3, attacker: Node) -> bool:
	if destroyed:
		return false
	last_attacker = attacker
	var k: Array = KINDS[kind]
	var normal := -dir
	FX.chips(self, hit_pos, normal, k[3], 7 if kind != "concrete" else 5, 0.025, 3, 0.6)
	Sfx.play(self, "impact_" + String(k[4]), hit_pos, -10.0, 0.2)
	_knock_loose(hit_pos, dir)
	if not Net.is_server():
		# the host owns prop health; it broadcasts the destruction
		if Net.sync:
			Net.sync.send_prop(self, "hit", amount, hit_pos, dir)
		return false
	_take(amount * float(k[1]), hit_pos, dir)
	return false


func apply_blast(amount: float, origin: Vector3) -> void:
	if destroyed:
		return
	if not Net.is_server():
		if Net.sync:
			Net.sync.send_prop(self, "blast", amount, origin, Vector3.ZERO)
		return
	var dir := center() - origin
	dir.y = maxf(dir.y, 0.0) + 0.4
	_take(amount * float(KINDS[kind][2]), center(), dir.normalized(), origin)


func _take(amount: float, hit_pos: Vector3, dir: Vector3, blast_origin = null) -> void:
	health -= amount
	if health <= 0.0:
		destroy(hit_pos if blast_origin == null else blast_origin, dir, blast_origin != null)
		return
	var stage := 2 if health_frac() < 0.33 else (1 if health_frac() < 0.66 else 0)
	while _damage_stage < stage:
		_damage_stage += 1
		_sag()


## Visible wear: meshes shift, tilt and darken as the prop is shot up.
func _sag() -> void:
	var amt := 0.035 * _damage_stage
	for c in get_children():
		if c is MeshInstance3D and c.visible:
			var mi := c as MeshInstance3D
			mi.rotation += Vector3(randf_range(-amt, amt), randf_range(-amt, amt) * 1.5, randf_range(-amt, amt))
			mi.position += Vector3(randf_range(-amt, amt) * 0.4, -randf() * amt * 0.3, randf_range(-amt, amt) * 0.4)
			mi.transparency = 0.0
	if kind == "sand" and _damage_stage == 2:
		# top row of bags spills off
		var top := -INF
		for c in get_children():
			if c is MeshInstance3D and c.visible:
				top = maxf(top, (c as MeshInstance3D).position.y)
		for c in get_children():
			if c is MeshInstance3D and c.visible and (c as MeshInstance3D).position.y > top - 0.05 and randf() < 0.6:
				_spawn_piece(c, global_position + Vector3.UP * 0.2, Vector3.ZERO, 2.0)


## A bullet knocks a small nearby piece (bag, board, ammo box, frame bar) off.
func _knock_loose(hit_pos: Vector3, dir: Vector3) -> void:
	var chance := 0.22 if kind != "concrete" else 0.05
	if randf() > chance:
		return
	var best: MeshInstance3D = null
	var best_d := 0.45
	for c in get_children():
		if not (c is MeshInstance3D) or not c.visible:
			continue
		var mi := c as MeshInstance3D
		var sz := mi.mesh.get_aabb().size * mi.scale.abs()
		if maxf(sz.x, maxf(sz.y, sz.z)) > 0.62:
			continue
		var d := (mi.global_transform * mi.mesh.get_aabb().get_center()).distance_to(hit_pos)
		if d < best_d:
			best_d = d
			best = mi
	if best != null:
		_spawn_piece(best, hit_pos - dir * 0.3, dir, 1.5)


# ------------------------------------------------------------------ destruction

func destroy(origin: Vector3, dir: Vector3, from_blast: bool) -> void:
	if destroyed:
		return
	destroyed = true
	if Net.active and Net.is_server() and Net.sync:
		Net.sync.send_prop_destroyed(self, origin, dir, from_blast)
	remove_from_group("destructibles")
	collision_layer = 0
	var k: Array = KINDS[kind]
	var c := center()
	var power := 1.8 if from_blast else 1.0
	# fragments from our own meshes
	var parts: Array = []
	for n in get_children():
		if n is MeshInstance3D and n.visible:
			_collect_parts(n as MeshInstance3D, parts)
	parts.shuffle()
	for i in mini(parts.size(), MAX_PIECES):
		var p: Array = parts[i]
		Fragment.spawn(self, p[0], p[1], p[2], p[3], origin, dir, power)
	FX.chips(self, c, Vector3.UP, k[3], 22, 0.05, 14, 2.2)
	Sfx.play(self, "break_" + String(k[4]), c, 2.0, 0.12)
	get_tree().call_group("enemies", "hear_noise", c, 18.0)
	for d in dependents:
		if is_instance_valid(d) and not d.destroyed:
			d.call_deferred("destroy", c, Vector3.UP, false)
	if level != null and level.has_method("on_prop_destroyed"):
		level.on_prop_destroyed(self)
	if kind == "explosive":
		var by := last_attacker
		var me := get_rid()
		var at := c
		var lvl := level
		# short delay so chained barrels ripple rather than pop together
		get_tree().create_timer(0.08 if from_blast else 0.0, false, true).timeout.connect(
				func(): Blast.detonate(lvl, at, 130.0, 5.5, by, [me], Net.is_server()))
	queue_free()


## Large boxes break into chunks; small meshes fly off whole.
## Each entry: [mesh, material, global transform, half-size]
func _collect_parts(mi: MeshInstance3D, out: Array) -> void:
	var aabb := mi.mesh.get_aabb()
	var sz := aabb.size * mi.scale.abs()
	var mat := mi.material_override
	var xf := mi.global_transform
	var biggest := maxf(sz.x, maxf(sz.y, sz.z))
	if biggest <= 0.6 or not (mi.mesh is BoxMesh):
		out.append([mi.mesh, mat, xf * Transform3D(Basis.IDENTITY, aabb.get_center()), sz * 0.5])
		return
	var cell := 0.42 if kind != "concrete" else 0.36
	var n := Vector3i(maxi(1, ceili(sz.x / cell)), maxi(1, ceili(sz.y / cell)), maxi(1, ceili(sz.z / cell)))
	while n.x * n.y * n.z > 18:
		if n.x >= n.y and n.x >= n.z:
			n.x -= 1
		elif n.z >= n.y:
			n.z -= 1
		else:
			n.y -= 1
	var step := Vector3(sz.x / n.x, sz.y / n.y, sz.z / n.z)
	var rot := Transform3D(xf.basis.orthonormalized(), xf.origin)
	for ix in n.x:
		for iy in n.y:
			for iz in n.z:
				var local := Vector3((ix + 0.5) * step.x, (iy + 0.5) * step.y, (iz + 0.5) * step.z) - sz * 0.5
				var piece := step * Vector3(randf_range(0.75, 0.95), randf_range(0.75, 0.95), randf_range(0.75, 0.95))
				out.append([ML.box(piece.snapped(Vector3.ONE * 0.01)), mat, rot * Transform3D(Basis.IDENTITY, local), piece * 0.5])


func _spawn_piece(mi: MeshInstance3D, origin: Vector3, dir: Vector3, power: float) -> void:
	var aabb := mi.mesh.get_aabb()
	var sz := aabb.size * mi.scale.abs()
	Fragment.spawn(self, mi.mesh, mi.material_override, mi.global_transform * Transform3D(Basis.IDENTITY, aabb.get_center()),
			sz * 0.5, origin, dir, power * 0.6)
	mi.visible = false
