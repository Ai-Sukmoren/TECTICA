extends Node
## Persistent delivery of successful local sign-ins and live online rooms.
signal rooms_updated
signal dashboard_updated

const BASE_URL := "https://plantstism.tail453247.ts.net/tectica"
const STATE_PATH := "user://community.cfg"
const Net = preload("res://scripts/net/net.gd")
var rooms: Array = []
var rooms_status := ""
var dashboard: Dictionary = {}
var dashboard_status := ""
var _token := ""
var _pending: Array = []
var _sent := 0
var _retry := 1.0
var _room_timer := 0.0
var _published := false
var _room_busy := false
var _room_removing := false
var _browse := false
var _browse_timer := 0.0
var _enabled := true
var _send_request: HTTPRequest
var _room_request: HTTPRequest
var _list_request: HTTPRequest
var _admin_request: HTTPRequest


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Automated scene-tree scripts never send player records.
	_enabled = get_tree().get_script() == null
	if not _enabled:
		set_process(false)
		return
	var cfg := ConfigFile.new()
	if cfg.load(STATE_PATH) == OK:
		_token = str(cfg.get_value("client", "token", ""))
		_pending = cfg.get_value("client", "pending", [])
	if _token.length() != 64:
		_token = Crypto.new().generate_random_bytes(32).hex_encode()
	_save()
	_send_request = _request_node()
	_send_request.request_completed.connect(_sent_logins)
	_room_request = _request_node()
	_room_request.request_completed.connect(_room_result)
	_list_request = _request_node()
	_list_request.request_completed.connect(_listed_rooms)
	_admin_request = _request_node()
	_admin_request.request_completed.connect(_read_dashboard)


func _request_node() -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = 12.0
	request.body_size_limit = 1048576
	request.max_redirects = 0
	add_child(request)
	return request


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("client", "token", _token)
	cfg.set_value("client", "pending", _pending)
	if cfg.save(STATE_PATH + ".tmp") == OK:
		DirAccess.rename_absolute(STATE_PATH + ".tmp", STATE_PATH)


func record_login(player_name: String) -> void:
	if not _enabled:
		return
	_pending.append({"id": Crypto.new().generate_random_bytes(32).hex_encode(),
		"player": player_name, "time": Time.get_unix_time_from_system(),
		"version": str(ProjectSettings.get_setting("application/config/version"))})
	_save()
	_retry = 0.0


func _headers() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _token])


func _process(delta: float) -> void:
	_retry -= delta
	if _retry <= 0.0 and _sent == 0 and not _pending.is_empty():
		_sent = mini(_pending.size(), 32)
		if _send_request.request(BASE_URL + "/logins", _headers(), HTTPClient.METHOD_POST,
				JSON.stringify({"events": _pending.slice(0, _sent)})) != OK:
			_sent = 0
		_retry = 30.0
	_room_timer -= delta
	if _room_timer <= 0.0:
		_room_timer = 10.0
		_publish_room()
	if _browse:
		_browse_timer -= delta
		if _browse_timer <= 0.0:
			refresh_rooms()


func _sent_logins(result: int, code: int, _headers_in: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_pending = _pending.slice(_sent)
		_save()
		_retry = 1.0
	_sent = 0


func _publish_room() -> void:
	if _room_busy:
		return
	var hosting := Net.active and Net.is_server() and Net.transport == "ws" and Net.funnel_url != ""
	if hosting:
		var scene = get_tree().current_scene
		if scene == null or scene.get("map_id") == null:
			return
		var body := {"name": Net.default_name() + "'s room", "address": Net.funnel_url,
			"mode": Net.kind, "map": str(scene.map_id), "players": Net.roster.size(),
			"version": str(ProjectSettings.get_setting("application/config/version"))}
		_published = true
		_room_removing = false
		_room_busy = _room_request.request(BASE_URL + "/room", _headers(), HTTPClient.METHOD_POST, JSON.stringify(body)) == OK
	elif _published:
		_room_removing = true
		_room_busy = _room_request.request(BASE_URL + "/room", _headers(), HTTPClient.METHOD_DELETE) == OK


func _room_result(result: int, code: int, _headers_in: PackedStringArray, _body: PackedByteArray) -> void:
	_room_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and _room_removing:
		_published = false


func browse_rooms(on: bool) -> void:
	_browse = on
	if on:
		refresh_rooms()


func refresh_rooms() -> void:
	if not _enabled:
		return
	_browse_timer = 10.0
	rooms_status = "CHECKING OPEN ROOMS..."
	if _list_request.request(BASE_URL + "/rooms") != OK:
		rooms_status = "CHECKING OPEN ROOMS..."


func _listed_rooms(result: int, code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	rooms = []
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data is Dictionary and data.get("rooms") is Array:
		rooms = data.rooms
		rooms_status = "NO OPEN ROOMS" if rooms.is_empty() else "%d OPEN ROOMS" % rooms.size()
	else:
		rooms_status = "ROOM SERVICE OFFLINE  ·  RETRY WITH F5"
	rooms_updated.emit()


func refresh_dashboard() -> void:
	if not _enabled:
		return
	var cfg := ConfigFile.new()
	var key := ""
	if cfg.load("user://community_admin.cfg") == OK:
		key = str(cfg.get_value("owner", "key", ""))
	if key == "":
		dashboard_status = "Owner access is configured on the server PC."
		dashboard_updated.emit()
		return
	dashboard_status = "Loading global sign-ins..."
	_admin_request.request(BASE_URL + "/admin/logins",
		PackedStringArray(["Authorization: Bearer " + key]))


func _read_dashboard(result: int, code: int, _headers_in: PackedStringArray, body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data is Dictionary and data.get("rows") is Array:
		dashboard = data
		dashboard_status = "Updated " + Time.get_datetime_string_from_system(false, true)
	else:
		dashboard_status = "Could not refresh global sign-ins. Showing the last received records."
	dashboard_updated.emit()
