## alstraInfinite "PPS Shooter Essentials" props (asset pack 4).
## Licence: alstrainfinite.com/fal — free for games, credit "Alstra Infinite".
##
## Models are flattened into plain MeshInstance3D children of the caller's node
## so destructibles can still sag / knock loose / shatter them piece by piece.
extends RefCounted

const ROOT := "res://assets/thirdparty/alstra_shooter_essentials/"
const PATHS := {
	"sandbag": "Props/SandbagV1.glb",
	"sandbag_wall": "Props/SandbagWallV1.glb",
	"sandbag_wall2": "Props/SandbagWallV2.glb",
	"sandbag_curve": "Props/SandbagCurvedWallV1.glb",
	"sandbag_curve2": "Props/SandbagCurvedWallV2.glb",
	"fuel_barrel": "Props/FuelBarrelV1.glb",
	"fuel_barrel_wreck": "Props/FuelBarrelV1_Destroyed.glb",
	"ammo_box": "Props/AmmoBox_9_V1.glb",
	"metal_ammo_box": "Props/MetalAmmoBoxV1_Large.glb",
	"medkit": "Props/MedKitV1.glb",
	"radio": "Props/FieldRadioV1.glb",
	"canteen": "Props/CanteenV1.glb",
	"knife": "Props/CombatKnifeV1.glb",
	"belt_556": "Props/Bullets/Bullet_556_V1_Belt.glb",
	"m67": "Guns/Grenades/M67V1_Rigged.glb",
	"m84": "Guns/Grenades/M84V1_Rigged.glb",
}

## id -> Array of [Mesh, Transform3D] in model space, plus "aabb" entry.
static var _cache: Dictionary = {}


## Returns {"parts": [[mesh, xform], ...], "aabb": AABB} or {} if unavailable.
static func _parts(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var out := {}
	var path: String = ROOT + String(PATHS.get(id, ""))
	if PATHS.has(id) and ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var inst := ps.instantiate()
			var parts: Array = []
			var box := AABB()
			var first := true
			_walk(inst, Transform3D.IDENTITY, parts)
			for p in parts:
				var a: AABB = p[1] * (p[0] as Mesh).get_aabb()
				box = a if first else box.merge(a)
				first = false
			inst.free()
			if not parts.is_empty():
				out = {"parts": parts, "aabb": box}
	_cache[id] = out
	return out


static func _walk(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, here])
	for c in n.get_children():
		_walk(c, here, out)


static func available(id: String) -> bool:
	return not _parts(id).is_empty()


## Native size of a model in metres (before fitting).
static func native_size(id: String) -> Vector3:
	var d := _parts(id)
	return (d["aabb"] as AABB).size if not d.is_empty() else Vector3.ZERO


## Adds the model under `parent`, bottom-centred at `pos`, rotated `rot_y`.
## `height` > 0 scales uniformly to that height; `size` (any non-zero axis)
## stretches to fit a footprint instead. Returns the created meshes (empty if
## the asset is missing, so callers can fall back to procedural meshes).
static func add(parent: Node3D, id: String, pos: Vector3 = Vector3.ZERO, rot_y: float = 0.0,
		height: float = 0.0, size: Vector3 = Vector3.ZERO) -> Array:
	var d := _parts(id)
	var made: Array = []
	if d.is_empty():
		return made
	var box: AABB = d["aabb"]
	var s := Vector3.ONE
	if size != Vector3.ZERO:
		s = Vector3(
				size.x / box.size.x if size.x > 0.0 else 1.0,
				size.y / box.size.y if size.y > 0.0 else 1.0,
				size.z / box.size.z if size.z > 0.0 else 1.0)
		# axes left at 0 follow the average of the given ones
		var given: Array = []
		for i in 3:
			if size[i] > 0.0:
				given.append(s[i])
		var avg := 0.0
		for g in given:
			avg += g
		avg /= maxf(1.0, given.size())
		for i in 3:
			if size[i] <= 0.0:
				s[i] = avg
	elif height > 0.0:
		s = Vector3.ONE * (height / maxf(0.001, box.size.y))
	var c := box.get_center()
	var fit := Transform3D(Basis(Vector3.UP, rot_y) * Basis.from_scale(s), pos) \
			* Transform3D(Basis.IDENTITY, -Vector3(c.x, box.position.y, c.z))
	for p in d["parts"]:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = fit * (p[1] as Transform3D)
		parent.add_child(mi)
		made.append(mi)
	return made
