extends Node

const Net = preload("res://scripts/net/net.gd")
var hud
var is_open := false
var selected := 0
var _rects: Array = []
var _rooms: Array = []
var _service
var _message := ""


func setup(p_hud) -> void:
	hud = p_hud
	process_mode = Node.PROCESS_MODE_ALWAYS
	_service = get_tree().root.get_node("Community")
	_service.rooms_updated.connect(_refresh)


func open() -> void:
	is_open = true
	_message = ""
	_refresh()
	_service.browse_rooms(true)


func close() -> void:
	is_open = false
	_service.browse_rooms(false)


func _refresh() -> void:
	var selected_id := str(_rooms[selected].id) if selected < _rooms.size() else ""
	_rooms = _service.rooms.duplicate(true)
	selected = 0
	for i in _rooms.size():
		if str(_rooms[i].id) == selected_id:
			selected = i


func _join() -> void:
	if _rooms.is_empty():
		return
	var room: Dictionary = _rooms[selected]
	if str(room.version) != str(ProjectSettings.get_setting("application/config/version")):
		_message = "This host uses v%s. Update both games to the same version." % room.version
		return
	if int(room.players) >= 8:
		_message = "This room is full."
		return
	Net.player_name = preload("res://scripts/core/profile.gd").current.to_upper()
	if Net.join(str(room.address)) == OK:
		_message = "Connecting to " + str(room.name) + "..."
	else:
		_message = Net.status


func handle(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		return true
	if event.is_action_pressed("ui_up"):
		selected = posmod(selected - 1, maxi(_rooms.size(), 1))
	elif event.is_action_pressed("ui_down"):
		selected = posmod(selected + 1, maxi(_rooms.size(), 1))
	elif event.is_action_pressed("ui_accept"):
		_join()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_service.refresh_rooms()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			selected = maxi(selected - 1, 0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			selected = mini(selected + 1, maxi(_rooms.size() - 1, 0))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			for entry in _rects:
				if (entry[0] as Rect2).has_point(event.position):
					selected = int(entry[1])
					_join()
	return false


func draw(c: Control, vp: Vector2) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.015, 0.025, 0.035, 0.96))
	hud._text(c, Vector2(60, 70), "OPEN ROOMS", 28, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
	hud._text(c, Vector2(60, 100), str(_service.rooms_status), 13, hud.DIM)
	var visible_rows := maxi(int((vp.y - 230) / 60), 1)
	var first := maxi(selected - visible_rows + 1, 0)
	_rects.clear()
	for i in range(first, mini(first + visible_rows, _rooms.size())):
		var room: Dictionary = _rooms[i]
		var r := Rect2(60, 130 + (i - first) * 60, vp.x - 120, 52)
		_rects.append([r, i])
		c.draw_rect(r, Color(hud.RED, 0.22) if i == selected else Color(1, 1, 1, 0.04))
		hud._text(c, r.position + Vector2(14, 23), str(room.name), 16, hud.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.45, true)
		hud._text(c, r.position + Vector2(14, 43), "%s  ·  %s  ·  v%s" % [str(room.mode).to_upper(), str(room.map).to_upper(), room.version], 11, hud.DIM)
		hud._text(c, r.position + Vector2(0, 31), "%d / 8     JOIN  →" % int(room.players), 14, hud.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 20, true)
	var status := Net.status if Net.status != "" else _message
	if _message != "" and not _message.begins_with("Connecting"):
		status = _message
	hud._text(c, Vector2(60, vp.y - 70), status, 13, hud.WARN)
	hud._text(c, Vector2(60, vp.y - 35), "Click a room or press Enter to join   ·   F5 refresh   ·   Esc back", 12, hud.DIM)
