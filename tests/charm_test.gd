extends SceneTree
const Charm = preload("res://scripts/skins/charm.gd")
const Loadout = preload("res://scripts/core/loadout.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")
const Data = preload("res://scripts/weapons/weapon_data.gd")
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	print("[charm] ", message, " PASS=", ok)
	failed = failed or not ok

func _run() -> void:
	_check(Charm.sanitize("unknown") == "", "unknown saves fall back to none")
	_check(Charm.label("") == "NONE", "factory has no charm")
	for id in ["dog_tags", "cartridge", "compass"]:
		for pistol in [false, true]:
			var c := Charm.new()
			c.setup(id, pistol)
			root.add_child(c)
			c.set_process(false)
			for hz in [30, 60, 144]:
				c.kick()
				for i in hz:
					c.rotation = Vector3(sin(float(i) / hz * TAU), 0, 0.4)
					c.position.z = sin(float(i) / hz * TAU) * 0.02
					c._process(1.0 / hz)
				c._process(1.0)
				_check(c._swing.rotation.is_finite() and absf(c._angle.x) <= Charm.MAX_SWING and absf(c._angle.y) <= Charm.MAX_SWING, "%s pistol=%s %d Hz + hitch stays bounded" % [id, pistol, hz])
			c.free()
	# Exercise save-compatible entry cycling in memory without changing user files.
	var saved_classes := Loadout.classes.duplicate(true)
	var saved_loaded := Loadout._loaded
	var saved_index := Loadout.class_index
	Loadout.classes = [Loadout._preset(0)]
	Loadout.class_index = 0
	Loadout._loaded = true
	Loadout.cycle_charm("primary", -1)
	_check(Loadout.entry("primary").charm == "compass", "selector wraps backwards")
	Loadout.cycle_charm("primary", 1)
	_check(Loadout.entry("primary").charm == "", "selector returns to none")
	Loadout.cycle_charm("primary", 1)
	Loadout.cycle_weapon("primary", 1)
	_check(Loadout.entry("primary").charm == "dog_tags", "weapon change preserves chosen charm")
	Loadout.reset_class()
	_check(Loadout.entry("primary").charm == "", "reset clears charm")
	Loadout.classes = saved_classes
	Loadout._loaded = saved_loaded
	Loadout.class_index = saved_index
	for weapon_id in Data.PRIMARIES + Data.SECONDARIES:
		var w := Weapon.new()
		w.setup(weapon_id)
		root.add_child(w)
		var original_muzzle := w.muzzle.transform
		for charm_id in ["dog_tags", "cartridge", "compass"]:
			w.apply_charm(charm_id)
			w.apply_charm(charm_id)
			_check(w.charm == charm_id and w.get_node_or_null("WeaponCharm") == w._charm and w._charm.position.is_finite(), "%s mounts %s once" % [weapon_id, charm_id])
		w.apply_charm("unknown")
		_check(w._charm == null and w.get_node_or_null("WeaponCharm") == null and w.muzzle.transform == original_muzzle, "%s removes charm without changing gun markers" % weapon_id)
		w.free()
	await process_frame
	quit(1 if failed else 0)
