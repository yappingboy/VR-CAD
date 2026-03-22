## PropertyPanel — a floating panel showing and editing properties of the
## currently selected CADObject.
##
## Rendered via a SubViewport + QuadMesh so it works in 3D VR.
## It appears near the selected object and follows it when moved.
##
## The interaction ray can point at this panel; UV coordinates are used
## to hit-test which field/button the user is pointing at.
extends Node3D

signal value_changed(property: String, new_value: Variant)
signal delete_pressed
signal duplicate_pressed
signal close_pressed

# ─── Config ──────────────────────────────────────────────────────────────────

@export var panel_size: Vector2 = Vector2(0.20, 0.28)
@export var follow_offset: Vector3 = Vector3(0.15, 0.0, 0.0)

# ─── State ───────────────────────────────────────────────────────────────────

var _target: CADObject = null
var _fields: Dictionary = {}   # property_name → { label, value_label }

# ─── Nodes ───────────────────────────────────────────────────────────────────

var _board: MeshInstance3D
var _viewport: SubViewport
var _root_control: Control


func _ready() -> void:
	_build_board()
	_build_viewport()
	visible = false


# ─── Board & Viewport ────────────────────────────────────────────────────────

func _build_board() -> void:
	var quad := QuadMesh.new()
	quad.size = panel_size

	_board = MeshInstance3D.new()
	_board.name = "PropertyBoard"
	_board.mesh = quad
	add_child(_board)


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PropertyViewport"
	_viewport.size = Vector2i(400, 560)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_board.material_override = mat

	_build_ui()


func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.size = Vector2(400, 560)
	_viewport.add_child(_root_control)

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.14, 0.90)
	bg.size = Vector2(400, 560)
	_root_control.add_child(bg)

	# Title bar
	var title_bg := ColorRect.new()
	title_bg.color = Color(0.1, 0.2, 0.4, 0.95)
	title_bg.position = Vector2(0, 0)
	title_bg.size = Vector2(400, 36)
	_root_control.add_child(title_bg)

	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "Properties"
	title_lbl.position = Vector2(10, 8)
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_root_control.add_child(title_lbl)

	# Close button hint
	var close_lbl := Label.new()
	close_lbl.name = "CloseLabel"
	close_lbl.text = "[B] Close"
	close_lbl.position = Vector2(300, 8)
	close_lbl.add_theme_font_size_override("font_size", 12)
	close_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	_root_control.add_child(close_lbl)

	# Properties section (rebuilt per object)
	var prop_container := VBoxContainer.new()
	prop_container.name = "PropContainer"
	prop_container.position = Vector2(10, 44)
	prop_container.size = Vector2(380, 420)
	_root_control.add_child(prop_container)

	# Action buttons row
	_build_action_buttons()


func _build_action_buttons() -> void:
	var btn_y: float = 490.0

	var dup_btn := _make_action_button("[ Duplicate ]", Color(0.2, 0.6, 0.3))
	dup_btn.position = Vector2(10, btn_y)
	_root_control.add_child(dup_btn)

	var del_btn := _make_action_button("[ Delete ]", Color(0.7, 0.2, 0.2))
	del_btn.position = Vector2(210, btn_y)
	_root_control.add_child(del_btn)


func _make_action_button(text: String, color: Color) -> ColorRect:
	var btn := ColorRect.new()
	btn.color = color.darkened(0.3)
	btn.size = Vector2(180, 36)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchors_preset = Control.PRESET_FULL_RECT
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	btn.add_child(lbl)
	return btn


# ─── Public API ──────────────────────────────────────────────────────────────

func show_for(obj: CADObject) -> void:
	_target = obj
	visible = true
	_rebuild_properties()

	if obj.has_signal("geometry_changed"):
		if not obj.geometry_changed.is_connected(_on_geometry_changed):
			obj.geometry_changed.connect(_on_geometry_changed)


func hide_panel() -> void:
	if _target and _target.has_signal("geometry_changed"):
		if _target.geometry_changed.is_connected(_on_geometry_changed):
			_target.geometry_changed.disconnect(_on_geometry_changed)
	_target = null
	visible = false


func _on_geometry_changed(_obj: CADObject) -> void:
	if visible:
		_rebuild_properties()


# ─── Property rebuild ────────────────────────────────────────────────────────

func _rebuild_properties() -> void:
	if _target == null:
		return

	var container: VBoxContainer = _root_control.get_node_or_null("PropContainer")
	if container == null:
		return

	# Clear old rows
	for child in container.get_children():
		child.queue_free()
	_fields.clear()

	# Update title
	var title: Label = _root_control.get_node_or_null("TitleLabel")
	if title:
		title.text = "%s — Properties" % _target.object_label

	# Common properties
	_add_prop_row(container, "Label", _target.object_label)
	_add_prop_row(container, "Pos X", "%.3f m" % _target.global_position.x)
	_add_prop_row(container, "Pos Y", "%.3f m" % _target.global_position.y)
	_add_prop_row(container, "Pos Z", "%.3f m" % _target.global_position.z)

	# Type-specific dimensions
	if _target is PrimitiveBox:
		var b := _target as PrimitiveBox
		_add_separator(container)
		_add_prop_row(container, "Width",  "%.1f mm" % (b.dimensions.x * 1000.0))
		_add_prop_row(container, "Height", "%.1f mm" % (b.dimensions.y * 1000.0))
		_add_prop_row(container, "Depth",  "%.1f mm" % (b.dimensions.z * 1000.0))
		_add_separator(container)
		_add_prop_row(container, "Volume",
			"%.1f cm³" % (b.dimensions.x * b.dimensions.y * b.dimensions.z * 1_000_000.0))

	elif _target is PrimitiveCylinder:
		var c := _target as PrimitiveCylinder
		_add_separator(container)
		_add_prop_row(container, "Radius", "%.1f mm" % (c.radius * 1000.0))
		_add_prop_row(container, "Height", "%.1f mm" % (c.height * 1000.0))
		_add_separator(container)
		var vol := PI * c.radius * c.radius * c.height
		_add_prop_row(container, "Volume", "%.1f cm³" % (vol * 1_000_000.0))

	elif _target is PrimitiveSphere:
		var s := _target as PrimitiveSphere
		_add_separator(container)
		_add_prop_row(container, "Radius",   "%.1f mm" % (s.radius * 1000.0))
		_add_prop_row(container, "Diameter", "%.1f mm" % (s.radius * 2000.0))
		_add_separator(container)
		var vol := (4.0 / 3.0) * PI * pow(s.radius, 3)
		_add_prop_row(container, "Volume", "%.1f cm³" % (vol * 1_000_000.0))

	# Constraints
	if not _target.constraints.is_empty():
		_add_separator(container)
		_add_section_header(container, "Constraints")
		for c_data in _target.constraints:
			_add_prop_row(container, c_data.get("type", "?"),
				str(c_data.get("value", "")))


func _add_prop_row(parent: VBoxContainer, prop_name: String, value_str: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_lbl := Label.new()
	name_lbl.text = prop_name
	name_lbl.custom_minimum_size = Vector2(110, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
	row.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = value_str
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	row.add_child(val_lbl)

	parent.add_child(row)
	_fields[prop_name] = {"name_lbl": name_lbl, "val_lbl": val_lbl}


func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator_color", Color(0.2, 0.3, 0.5, 0.5))
	sep.custom_minimum_size = Vector2(0, 6)
	parent.add_child(sep)


func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text.to_upper()
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	parent.add_child(lbl)


# ─── Per-frame (follow target) ───────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _target and visible:
		global_position = _target.global_position + follow_offset
		# Face camera
		var cam := get_viewport().get_camera_3d()
		if cam:
			look_at(cam.global_position, Vector3.UP)
