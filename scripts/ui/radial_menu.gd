## RadialMenu — a context menu that pops up at the controller tip.
##
## Displayed as a ring of option cards rendered in a SubViewport.
## The user navigates with the thumbstick: tilt toward an option to highlight it,
## then release the thumbstick (back to center) to confirm.
##
## Usage:
##   var menu = RadialMenu.new()
##   menu.open(options, controller_position, on_select_callback)
##
## Options format:
##   [{ "id": String, "label": String, "color": Color (optional) }, …]
class_name RadialMenu
extends Node3D

signal option_selected(option_id: String)
signal menu_closed

# ─── Config ──────────────────────────────────────────────────────────────────

@export var ring_radius: float = 0.10   # metres — radius of the option ring
@export var card_size: Vector2 = Vector2(0.06, 0.04)
@export var confirm_dead_zone: float = 0.25  # joystick center dead zone for confirm

# ─── State ───────────────────────────────────────────────────────────────────

var _options: Array[Dictionary] = []
var _highlighted: int = -1
var _is_open: bool = false
var _controller: Node  # XRController3D with ControllerInput
var _on_select: Callable

# ─── Nodes ───────────────────────────────────────────────────────────────────

var _cards: Array[MeshInstance3D] = []
var _highlight_ring: MeshInstance3D


func _ready() -> void:
	visible = false
	_build_highlight_ring()


# ─── Public API ──────────────────────────────────────────────────────────────

func open(options: Array[Dictionary], controller: Node, on_select: Callable = Callable()) -> void:
	_options = options
	_controller = controller
	_on_select = on_select

	_clear_cards()
	_build_cards()

	visible = true
	_is_open = true
	_highlighted = -1

	# Connect to controller thumbstick
	if _controller and _controller.has_signal("thumbstick_changed"):
		if not _controller.thumbstick_changed.is_connected(_on_thumbstick):
			_controller.thumbstick_changed.connect(_on_thumbstick)
		if not _controller.thumbstick_released.is_connected(_on_thumbstick_released):
			_controller.thumbstick_released.connect(_on_thumbstick_released)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false

	if _controller:
		if _controller.thumbstick_changed.is_connected(_on_thumbstick):
			_controller.thumbstick_changed.disconnect(_on_thumbstick)
		if _controller.thumbstick_released.is_connected(_on_thumbstick_released):
			_controller.thumbstick_released.disconnect(_on_thumbstick_released)

	menu_closed.emit()


# ─── Building ────────────────────────────────────────────────────────────────

func _build_highlight_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius - 0.004
	torus.outer_radius = ring_radius + 0.004
	torus.rings = 32
	torus.ring_segments = 6

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_highlight_ring = MeshInstance3D.new()
	_highlight_ring.mesh = torus
	_highlight_ring.material_override = mat
	_highlight_ring.visible = false
	add_child(_highlight_ring)


func _build_cards() -> void:
	var n: int = _options.size()
	if n == 0:
		return

	for i in range(n):
		var angle: float = (TAU / n) * i - PI * 0.5  # start from top
		var x: float = cos(angle) * ring_radius
		var y: float = sin(angle) * ring_radius

		var card := _make_card(_options[i])
		card.position = Vector3(x, y, 0)
		add_child(card)
		_cards.append(card)


func _make_card(option: Dictionary) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = card_size

	var color: Color = option.get("color", Color(0.2, 0.3, 0.5))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = mat
	mesh.name = "Card_%s" % option.get("id", "?")

	# Add a Label3D for the text
	var label := Label3D.new()
	label.text = option.get("label", "?")
	label.font_size = 18
	label.modulate = Color(0.9, 0.95, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 0, 0.001)
	mesh.add_child(label)

	return mesh


func _clear_cards() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()


# ─── Navigation ──────────────────────────────────────────────────────────────

func _on_thumbstick(stick_value: Vector2) -> void:
	if not _is_open or _options.is_empty():
		return

	if stick_value.length() < confirm_dead_zone:
		_set_highlighted(-1)
		return

	# Map joystick angle to option index
	var angle: float = stick_value.angle()  # -PI to PI; 0 = right
	# Offset so index 0 is at the top (angle = -PI/2)
	var adjusted: float = fposmod(angle + PI * 0.5, TAU)
	var index: int = int(round(adjusted / (TAU / _options.size()))) % _options.size()
	_set_highlighted(index)


func _on_thumbstick_released() -> void:
	if not _is_open:
		return
	if _highlighted >= 0 and _highlighted < _options.size():
		_confirm_selection(_highlighted)


func _set_highlighted(index: int) -> void:
	if index == _highlighted:
		return

	# Restore previous card color
	if _highlighted >= 0 and _highlighted < _cards.size():
		var opt: Dictionary = _options[_highlighted]
		var prev_color: Color = opt.get("color", Color(0.2, 0.3, 0.5)).darkened(0.3)
		var mat := _cards[_highlighted].material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = prev_color

	_highlighted = index

	# Highlight new card
	if _highlighted >= 0 and _highlighted < _cards.size():
		var mat := _cards[_highlighted].material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.3, 0.75, 1.0)
		if _controller and _controller.has_method("haptic_click"):
			_controller.haptic_click()


func _confirm_selection(index: int) -> void:
	var option_id: String = _options[index].get("id", "")
	option_selected.emit(option_id)
	if _on_select.is_valid():
		_on_select.call(option_id)
	if _controller and _controller.has_method("haptic_confirm"):
		_controller.haptic_confirm()
	close()


# ─── Helpers ─────────────────────────────────────────────────────────────────

func is_open() -> bool:
	return _is_open
