extends Node
## A gun on a turntable in its own small 3D world, drawn into a HUD rectangle: the gunsmith's and the zombie
## shop's preview. It turns slowly by itself; left-drag turns it by hand, the wheel zooms, reset_view() goes back.
## show() builds the gun only when what it shows changes.

const Weapon = preload("res://scripts/weapons/weapon.gd")

const ROTATION_SPEED := 0.01
const PITCH_LIMIT := PI * 0.47
const ZOOM_MIN := 0.3
const ZOOM_MAX := 1.6

var zoom := 1.0
## the gun shown (null before the first show())
var weapon: Node3D
var _sv: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _key := ""
var _rect := Rect2()
var _dragging := false
var _manual_rotation := false
var _spin := 0.0
var _base_dist := 1.4


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sv = SubViewport.new()
	_sv.size = Vector2i(960, 480)
	_sv.transparent_bg = true
	_sv.own_world_3d = true
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_sv.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 2.4
	_sv.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 1.4
	rim.light_color = Color(1.0, 0.55, 0.45)
	_sv.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_sv.add_child(_cam)
	_pivot = Node3D.new()
	_sv.add_child(_pivot)


## Rendering on (a screen showing it opened) or off.
func set_active(on: bool) -> void:
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		_key = ""
		_rect = Rect2()
		reset_view()
	else:
		_dragging = false


## Back to the slow automatic turn at the default framing.
func reset_view() -> void:
	_manual_rotation = false
	_spin = 0.0
	zoom = 1.0


## Shows weapon `id` with attachments `att`, skin, part skins and charm. Rebuilt only when any of them changes.
func show_weapon(id: String, att: Dictionary, skin: String = "", parts: Dictionary = {}, charm: String = "") -> void:
	var k := id + str(att) + skin + str(parts) + charm
	if k == _key:
		return
	_key = k
	for c in _pivot.get_children():
		c.queue_free()
	var w := Weapon.new()
	w.setup(id, att)
	w.apply_skin(skin, parts)
	w.apply_charm(charm)
	_pivot.add_child(w)
	var pistol: bool = w.is_pistol() or w.is_melee()
	w.position = Vector3(0, -0.02, 0.1 if pistol else 0.26)
	_base_dist = (0.55 if w.is_melee() else 0.75) if pistol else (1.75 if id == "uar10" else 1.4)
	weapon = w


## Drag to turn, wheel to zoom, inside the rectangle drawn last. Returns true when the event was used.
func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and _rect.has_point(event.position)
		return _dragging
	if event is InputEventMouseButton and event.pressed and _rect.has_point(event.position) \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# wheel up moves in, down backs off
		zoom = clampf(zoom * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), ZOOM_MIN, ZOOM_MAX)
		return true
	if event is InputEventMouseMotion and _dragging:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_manual_rotation = true
			_pivot.rotation.y = wrapf(_pivot.rotation.y + event.relative.x * ROTATION_SPEED, -PI, PI)
			_pivot.rotation.x = clampf(_pivot.rotation.x + event.relative.y * ROTATION_SPEED, -PITCH_LIMIT, PITCH_LIMIT)
			return true
		_dragging = false
	return false


## Turned by hand (a capture or a test sets the angle itself).
func set_turn(rot: Vector3) -> void:
	_manual_rotation = true
	_pivot.rotation = rot


func turn() -> Vector3:
	return _pivot.rotation


## Draws the gun into `rect` (and remembers it for the mouse).
func draw(c: Control, rect: Rect2) -> void:
	_rect = rect
	c.draw_texture_rect(_sv.get_texture(), rect, false)


func _process(delta: float) -> void:
	if _sv == null or _sv.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return
	_cam.position = Vector3(0, 0.12 * zoom, _base_dist * zoom)
	_cam.look_at(Vector3(0, 0.02, 0), Vector3.UP)
	if not _manual_rotation and not _dragging:
		_spin += delta * 0.45
		_pivot.rotation = Vector3(0.12 * sin(_spin * 0.7), -PI * 0.5 + sin(_spin) * 0.9, 0)
