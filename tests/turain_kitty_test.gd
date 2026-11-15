extends SceneTree
## Mythic Kitty weapon finish and outfit: reserved for the account Turain
## (any capitalisation), never in packs, hidden from everyone else including
## admin. Read-only: never writes user://accounts.cfg or any profile file.
const Skins = preload("res://scripts/skins/skins.gd")
const Outfits = preload("res://scripts/skins/outfits.gd")
const Collection = preload("res://scripts/skins/collection.gd")
const Profile = preload("res://scripts/core/profile.gd")

var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	call_deferred("run")


func as_user(name: String, admin: bool) -> void:
	Profile.current = name
	Profile._admin_for = name
	Profile._admin_val = admin


func run() -> void:
	Collection._loaded = true
	check(Skins.rarity_of("kitty_mythic") == Skins.Rarity.MYTHIC, "Kitty finish is MYTHIC")
	check(int(Outfits.info("kitty").rarity) == 4, "Kitty outfit is MYTHIC")
	for r in 6:
		check(not ("kitty_mythic" in Skins.finishes_of(r)), "Kitty never in pack pools")

	for who in [["", false], ["turian", false], ["lilin", false], ["test_admin", true]]:
		as_user(who[0], who[1])
		check(not ("kitty_mythic" in Skins.finish_ids(true)), "Kitty finish hidden from '%s'" % who[0])
		check(not Collection.has_skin("hk33", "kitty_mythic"), "'%s' can't use Kitty finish" % who[0])
		check(not ("kitty" in Outfits.ids()), "Kitty outfit hidden from '%s'" % who[0])
		check(not Collection.has_outfit("kitty"), "'%s' can't wear Kitty outfit" % who[0])
		check(Collection.buy_outfit("kitty") != "", "'%s' can't buy Kitty outfit" % who[0])

	for name in ["Turain", "turain", "TURAIN"]:
		as_user(name, false)
		check("kitty_mythic" in Skins.finish_ids(), "%s sees Kitty finish" % name)
		check("kitty" in Outfits.ids(), "%s sees Kitty outfit" % name)
		for w in Skins.weapon_ids():
			check(Collection.has_skin(w, "kitty_mythic") and Collection.count(w, "kitty_mythic") == 1, "%s owns Kitty on %s" % [name, w])
		check(Collection.has_outfit("kitty"), "%s owns Kitty outfit" % name)
	check(Skins.exclusive_tag("kitty_mythic").contains("TURAIN EXCLUSIVE"), "armory tag names Turain")

	# materials build and the outfit palette is complete
	var pal := Outfits.palette("kitty")
	for k in ["camo", "vest", "gear", "helmet", "detail", "face", "gloves", "boots"]:
		check(pal.get(k) is Material, "kitty palette has %s" % k)
	check((pal.vest as StandardMaterial3D).clearcoat_enabled, "kitty plates are glossy")
	check(Skins.material("kitty_mythic", false).get_shader_parameter("pattern") == Skins.P.KITTY, "kitty finish material")

	as_user("", false)
	Profile._admin_for = "?"
	print("turain_kitty_test: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
