extends SceneTree
## Loads every asset-pack-4 model and prints its native size.
const PP = preload("res://scripts/core/pack_props.gd")

func _init() -> void:
	var bad := 0
	for id in PP.PATHS:
		var ok := PP.available(id)
		if not ok:
			bad += 1
		print("[pack4] %-18s %s  size=%s" % [id, "OK " if ok else "MISSING", PP.native_size(id)])
		var n := Node3D.new()
		var made := PP.add(n, id, Vector3.ZERO, 0.5, 1.0)
		n.free()
	print("[pack4] %d missing" % bad)
	quit(1 if bad > 0 else 0)
