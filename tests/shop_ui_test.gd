extends SceneTree
## The arcade shop screen (needs a window: the list lays itself out while it draws):
##  - hovering rows never scrolls the list (it used to re-centre on the hovered row, which moved the list under the
##    pointer, which picked the next row: the list ran away while the mouse rested on it);
##  - the wheel scrolls the list and leaves the selection alone;
##  - keys / pad moving past the bottom bring the selection into view;
##  - an attachment row shows the gun in hand with that attachment on the turntable, a gun row that gun bare.
##   godot --path . --resolution 1280x720 -s res://tests/shop_ui_test.gd
const Main = preload("res://scripts/main.gd")
var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


func _initialize() -> void:
	run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func motion(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)   # positions in the viewport's own coordinates, as the HUD lays out


func wheel(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = Vector2(200, 400)
	root.push_input(ev, true)   # positions in the viewport's own coordinates, as the HUD lays out


func key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	root.push_input(ev, true)   # positions in the viewport's own coordinates, as the HUD lays out


func run() -> void:
	load("res://scripts/core/profile.gd").current = "shop_ui_test"
	Main.saved_mode = "zombie"
	Main.saved_map = "warehouse"
	Main.quick_restart = true
	change_scene_to_file("res://scenes/main.tscn")
	await frames(90)
	var main = current_scene
	var hud = main.hud
	var shop = main.director.shop
	var p = main.player
	main.director.timer = 999.0
	shop.points = 20000
	shop.buy("gun_m700", p)
	var arcade = main.arcade
	p.global_position = arcade.global_position + arcade.global_transform.basis.z * 1.4   # the shop opens at the arcade
	await frames(5)
	hud._open_shop()
	await frames(10)
	var rows: Array = hud._shop_rows_now()
	print("  rows: ", rows.size())

	# hover: rest the pointer on a lower visible row for a while; the list must not move
	var visible: Array = []
	for i in hud._shop_rects.size():
		if (hud._shop_rects[i] as Rect2).size.x > 0.0:
			visible.append(i)
	var target: int = visible[visible.size() - 2]
	var at: Vector2 = (hud._shop_rects[target] as Rect2).get_center()
	var scroll0: int = hud._shop_scroll
	for k in 30:
		motion(at + Vector2(0, (k % 3) - 1))
		await frames(1)
	check(hud._shop_scroll == scroll0, "hovering rows does not scroll the list (scroll %d -> %d)" % [scroll0, hud._shop_scroll])
	check(hud.shop_index == target, "hovering picks the row under the pointer")

	# wheel: scrolls the list, the selection stays
	var sel: int = hud.shop_index
	wheel(true)
	await frames(3)
	check(hud._shop_scroll > scroll0, "the wheel scrolls the list down (%d -> %d)" % [scroll0, hud._shop_scroll])
	check(hud.shop_index == sel, "and leaves the selection where it was")
	wheel(false)
	wheel(false)
	await frames(3)
	check(hud._shop_scroll == 0, "the wheel scrolls back to the top")

	# keys: walking down past the bottom brings the selection into view
	hud.shop_index = 0
	for k in rows.size() - 1:
		key("ui_down")
		await frames(1)
	await frames(2)
	var last_rect: Rect2 = hud._shop_rects[rows.size() - 1]
	check(hud.shop_index == rows.size() - 1 and last_rect.size.x > 0.0, "keys down to the last row scroll it into view")

	# preview: an attachment row puts that attachment on the gun in hand; a gun row shows that gun bare
	for i in rows.size():
		if String(rows[i].id) == "att_m700:muzzle:suppressor":
			hud.shop_index = i
	hud._shop_follow = true
	await frames(4)
	var w = hud.shop_preview.weapon
	check(w != null and String(w.id) == "m700" and String(w.attachments.muzzle) == "suppressor", "an attachment row previews the Remington with the suppressor on")
	for i in rows.size():
		if String(rows[i].id) == "gun_scar_h":
			hud.shop_index = i
	await frames(4)
	w = hud.shop_preview.weapon
	check(w != null and String(w.id) == "scar_h" and String(w.attachments.muzzle) == "none", "a gun row previews that gun bare, as it is sold")
	hud._close_shop()
	print("SHOP UI: failures=%d" % failures)
	preload("res://scripts/core/settings.gd").mark_clean_exit()
	quit(failures)
