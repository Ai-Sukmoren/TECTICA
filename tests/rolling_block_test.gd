extends SceneTree
## RB-45 rolling-block pistol: data, model pivots, and the rest pose of the action.
const Data = preload("res://scripts/weapons/weapon_data.gd")
const Model = preload("res://scripts/weapons/weapon_model.gd")

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _initialize() -> void:
	var d: Dictionary = Data.WEAPONS["rb45"]
	check(d.cycle == "roll" and d.kind == "pistol", "rb45 is a pistol that cycles by rolling")
	check("rb45" in Data.SECONDARIES, "rb45 can be picked as a secondary")
	var parts: Dictionary = Model.build("rolling", d.defaults)
	check(parts.roll is Node3D and parts.hammer is Node3D, "model has breech block and hammer pivots")
	check(is_zero_approx(parts.roll.rotation.x), "breech block rests closed")
	check(is_equal_approx(parts.hammer.rotation.x, Model.ROLL_HAMMER_COCKED), "hammer rests at full cock")
	check(parts.bolt == null and parts.pump == null, "no bolt or pump on a rolling block")
	var m4: Dictionary = Model.build("m4", Data.WEAPONS["m4a1"].defaults)
	check(m4.roll == null, "other guns have no rolling block")
	var db: Dictionary = Data.WEAPONS["db2"]
	check(int(db.mag) == 2 and db.cycle == "twirl", "db2 holds two shells and twirls after a shot")
	check("db2" in Data.SECONDARIES, "db2 can be picked as a secondary")
	var sawed: Dictionary = Model.build("sawed", db.defaults)
	check(sawed.twirl is Node3D and sawed.roll == null, "sawed-off has a twirl pivot and no rolling block")
	sawed.root.free()
	parts.root.free()
	m4.root.free()
	print("ROLLING: failures=%d" % failures)
	quit(1 if failures > 0 else 0)
