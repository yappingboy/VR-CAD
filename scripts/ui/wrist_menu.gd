## WristMenu — a tool palette that appears on the left wrist.
##
## Setup in the scene:
##   LeftController (XRController3D, ControllerInput script)
##   └── WristMenu (Node3D, this script)
##       ├── MenuBoard (MeshInstance3D) ← flat quad showing the SubViewport
##       └── MenuViewport (SubViewport)
##           └── (Control nodes for the UI)
##
## Visibility detection: the menu appears when the user rotates their left
## wrist palm-up toward their face (inner-wrist facing the HMD camera).
##
## Tool selection emits `tool_selected` so the rest of the app can respond.
extends Node3D

signal tool_selected(tool_id: String)
signal plane_requested(mode: String)

# ─── Tool IDs ────────────────────────────────────────────────────────────────

const TOOL_SELECT   := "select"
const TOOL_BOX      := "box"
const TOOL_CYLINDER := "cylinder"
const TOOL_SPHERE   := "sphere"
const TOOL_PLANE    := "plane"
const TOOL_MEASURE  := "measure"
const TOOL_DELETE   := "delete"

# ─── Config ──────────────────────────────────────────────────────────────────

## How far above the wrist the menu floats (metres)
@export var vertical_offset: float = 0.06
## Palm-toward-face dot threshold (0 = 90°, 1 = looking straight at face)
@export var visibility_threshold: float = 0.2
## Size of the board in the scene (metres)
@export var board_size: Vector2 = Vector2(0.18, 0.12)

# ─── State ───────────────────────────────────────────────────────────────────

var active_tool: String = TOOL_SELECT
var _is_visible: bool = false
var _camera: Camera3D

# ─── Nodes ───────────────────────────────────────────────────────────────────

var _board: MeshInstance3D
var _viewport: SubViewport
var _buttons: Dictionary = {}  # tool_id → ColorRect/Label pair
var _collision_shape: CollisionShape3D


func _ready() -> void:
	_build_menu_board()
	_build_viewport_ui()
	_hide_menu()
	call_deferred("_find_camera")


func _find_camera() -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		# XR camera might not be the viewport camera; search the tree
		_camera = get_tree().get_root().find_child("XRCamera3D", true, false) as Camera3D


# ─── Board & Viewport ────────────────────────────────────────────────────────

func _build_menu_board() -> void:
	var quad := QuadMesh.new()
	quad.size = board_size

	_board = MeshInstance3D.new()
	_board.name = "MenuBoard"
	_board.mesh = quad
	_board.position = Vector3(0, vertical_offset, 0)
	# Tilt slightly toward the user's face
	_board.rotation_degrees = Vector3(-20, 0, 0)
	add_child(_board)

	# Collision body so the interaction ray can detect hits on this board
	var body := StaticBody3D.new()
	body.name = "MenuCollision"
	_board.add_child(body)
	_collision_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(board_size.x, board_size.y, 0.01)
	_collision_shape.shape = box
	_collision_shape.disabled = true  # starts hidden; enabled in _show_menu()
	body.add_child(_collision_shape)


func _build_viewport_ui() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "MenuViewport"
	_viewport.size = Vector2i(360, 240)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	# Apply viewport texture to the board
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	_board.material_override = mat

	_build_ui_controls()


func _build_ui_controls() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.12, 0.88)
	bg.size = Vector2(360, 240)
	_viewport.add_child(bg)

	var title := Label.new()
	title.text = "VR-CAD Tools"
	title.position = Vector2(10, 6)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_viewport.add_child(title)

	# Tool buttons — two rows of four
	var tools: Array[Dictionary] = [
		{"id": TOOL_SELECT,   "label": "Select",   "color": Color(0.3, 0.6, 1.0)},
		{"id": TOOL_BOX,      "label": "Box",      "color": Color(0.4, 0.8, 0.4)},
		{"id": TOOL_CYLINDER, "label": "Cylinder", "color": Color(0.4, 0.8, 0.4)},
		{"id": TOOL_SPHERE,   "label": "Sphere",   "color": Color(0.4, 0.8, 0.4)},
		{"id": TOOL_PLANE,    "label": "Plane",    "color": Color(0.9, 0.7, 0.2)},
		{"id": TOOL_MEASURE,  "label": "Measure",  "color": Color(0.9, 0.5, 0.9)},
		{"id": TOOL_DELETE,   "label": "Delete",   "color": Color(0.9, 0.3, 0.3)},
	]

	var cols: int = 4
	var btn_w: float = 80.0
	var btn_h: float = 44.0
	var pad: float = 6.0
	var start_y: float = 32.0

	for i in range(tools.size()):
		var tool_info: Dictionary = tools[i]
		var col: int = i % cols
		var row: int = i / cols

		var x: float = pad + col * (btn_w + pad)
		var y: float = start_y + row * (btn_h + pad)

		var btn := _make_tool_button(tool_info["id"], tool_info["label"], tool_info["color"])
		btn.position = Vector2(x, y)
		btn.size = Vector2(btn_w, btn_h)
		_viewport.add_child(btn)
		_buttons[tool_info["id"]] = btn

	_refresh_button_states()


func _make_tool_button(tool_id: String, label_text: String, color: Color) -> ColorRect:
	var btn := ColorRect.new()
	btn.color = color.darkened(0.4)
	btn.name = "Btn_" + tool_id

	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchors_preset = Control.PRESET_FULL_RECT
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	btn.add_child(lbl)

	return btn


func _refresh_button_states() -> void:
	for tool_id in _buttons:
		var btn: ColorRect = _buttons[tool_id]
		if tool_id == active_tool:
			btn.color = Color(0.2, 0.6, 1.0)
		else:
			btn.color = Color(0.1, 0.15, 0.25, 0.9)


# ─── Per-frame ───────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_update_visibility()


func _update_visibility() -> void:
	if _camera == null:
		return

	# Vector from camera to controller, and the controller's palm normal (local +Y)
	var to_camera: Vector3 = (_camera.global_position - global_position).normalized()
	var palm_up: Vector3 = global_transform.basis.y.normalized()
	var dot: float = palm_up.dot(to_camera)

	if dot > visibility_threshold and not _is_visible:
		_show_menu()
	elif dot <= visibility_threshold and _is_visible:
		_hide_menu()


# ─── Visibility ──────────────────────────────────────────────────────────────

func _show_menu() -> void:
	_is_visible = true
	_board.visible = true
	if _collision_shape:
		_collision_shape.disabled = false


func _hide_menu() -> void:
	_is_visible = false
	_board.visible = false
	if _collision_shape:
		_collision_shape.disabled = true


# ─── Interaction ray interface ───────────────────────────────────────────────
# interaction_ray.gd walks up the tree from the collision body and looks for
# a node that has on_hover(). These methods satisfy that contract.

func on_hover() -> void:
	pass  # cursor sphere already gives position feedback


func on_unhover() -> void:
	pass


## Called by interaction_ray when the trigger fires while pointing at this menu.
## hit_position is a world-space point on the board surface.
func on_select(hit_position: Vector3) -> void:
	on_ray_trigger(_world_to_uv(hit_position))


## Convert a world-space hit point on the board into a 0-1 UV coordinate.
func _world_to_uv(world_pos: Vector3) -> Vector2:
	var local := _board.global_transform.affine_inverse() * world_pos
	var uv := Vector2(
		local.x / board_size.x + 0.5,
		-local.y / board_size.y + 0.5
	)
	return uv.clamp(Vector2.ZERO, Vector2.ONE)


# ─── Tool selection (called by the interaction ray hitting the board) ─────────

## Call this with a UV coordinate (0-1 range) when the ray hits the menu board.
func on_ray_trigger(uv: Vector2) -> void:
	# Convert UV to viewport pixel coords
	var vp_size := _viewport.size
	var pixel := Vector2(uv.x * vp_size.x, uv.y * vp_size.y)

	for tool_id in _buttons:
		var btn: ColorRect = _buttons[tool_id]
		var rect := Rect2(btn.position, btn.size)
		if rect.has_point(pixel):
			select_tool(tool_id)
			return


func select_tool(tool_id: String) -> void:
	active_tool = tool_id
	_refresh_button_states()
	tool_selected.emit(tool_id)
	print("WristMenu: Tool selected → ", tool_id)


func get_active_tool() -> String:
	return active_tool
