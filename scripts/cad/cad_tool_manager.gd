## CADToolManager — wires wrist-menu tool selection to actual CAD operations.
##
## Add as a child of Main (Node3D) in main.tscn.
## Finds WristMenu, RightRay, RightController, and CADRoot at startup via
## deferred call, then connects all necessary signals.
##
## Tool behaviours:
##   select   — interaction_ray handles hover / select / grab natively.
##   box      — trigger while pointing at a surface → spawn a PrimitiveBox.
##   cylinder — trigger while pointing at a surface → spawn a PrimitiveCylinder.
##   sphere   — trigger while pointing at a surface → spawn a PrimitiveSphere.
##   plane    — trigger on any surface → create a WorkPlane aligned to the normal.
##   measure  — first trigger stores point A; second trigger draws line A→B + label.
##   delete   — trigger on a CAD object → delete it (with undo).
##
## Controller shortcuts (right hand):
##   B button (secondary) → Undo
##   A button (primary)   → Redo
extends Node

# ─── State ───────────────────────────────────────────────────────────────────

var _active_tool: String = "select"

# ─── Cached references ───────────────────────────────────────────────────────

var _cad_root: Node3D
var _right_ray    # InteractionRay (RayCast3D + script)
var _right_ctrl   # XRController3D with ControllerInput
var _wrist_menu   # WristMenu node

# ─── Measure state ───────────────────────────────────────────────────────────

var _measure_step: int = 0
var _measure_start: Vector3 = Vector3.ZERO
var _measure_visual: Node3D = null   # holds dots, line mesh, and label

# ─── Placement preview ghost ─────────────────────────────────────────────────

var _preview: MeshInstance3D = null


# ─── Init ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	call_deferred("_connect_nodes")


func _connect_nodes() -> void:
	var root := get_tree().get_root()
	_cad_root   = root.find_child("CADRoot",         true, false) as Node3D
	_right_ray  = root.find_child("RightRay",        true, false)
	_right_ctrl = root.find_child("RightController", true, false)
	_wrist_menu = root.find_child("WristMenu",       true, false)

	if _wrist_menu and _wrist_menu.has_signal("tool_selected"):
		_wrist_menu.tool_selected.connect(_on_tool_selected)

	if _right_ctrl:
		if _right_ctrl.has_signal("trigger_pressed"):
			_right_ctrl.trigger_pressed.connect(_on_trigger_pressed)
		if _right_ctrl.has_signal("secondary_button_pressed"):
			_right_ctrl.secondary_button_pressed.connect(_on_undo)   # B button
		if _right_ctrl.has_signal("primary_button_pressed"):
			_right_ctrl.primary_button_pressed.connect(_on_redo)     # A button

	if _right_ray and _right_ray.has_signal("selected"):
		_right_ray.selected.connect(_on_ray_object_selected)

	print("CADToolManager: connected — ray=", _right_ray != null,
		  " menu=", _wrist_menu != null, " ctrl=", _right_ctrl != null)


# ─── Per-frame preview ────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_update_preview()


func _update_preview() -> void:
	var show := _active_tool in ["box", "cylinder", "sphere"]
	if not show:
		_clear_preview()
		return

	# Hide preview if ray hits an existing object or misses everything
	if _right_ray == null or not _right_ray.is_colliding() \
			or _right_ray.get_hovered_object() != null:
		if _preview:
			_preview.visible = false
		return

	var hit := _right_ray.get_collision_point()
	var plane := _find_work_plane(_right_ray.get_collider())
	if plane:
		hit = plane.snap_world_position(hit)

	if _preview == null:
		_preview = _build_preview_mesh(_active_tool)
		if _preview:
			get_tree().get_root().add_child(_preview)

	if _preview:
		_preview.visible = true
		var up := plane.get_normal() if plane else Vector3.UP
		_preview.global_position = hit + up * _default_half_height()


func _build_preview_mesh(type: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "PlacementPreview"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 1.0, 0.30)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	match type:
		"box":
			var m := BoxMesh.new()
			m.size = Vector3(0.1, 0.1, 0.1)
			mi.mesh = m
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = 0.05
			m.bottom_radius = 0.05
			m.height = 0.1
			mi.mesh = m
		"sphere":
			var m := SphereMesh.new()
			m.radius = 0.05
			m.height = 0.1
			mi.mesh = m
		_:
			return null
	mi.material_override = mat
	return mi


func _default_half_height() -> float:
	match _active_tool:
		"box", "cylinder": return 0.05
		"sphere":          return 0.05
	return 0.0


func _clear_preview() -> void:
	if _preview:
		_preview.queue_free()
		_preview = null


# ─── Tool selection ───────────────────────────────────────────────────────────

func _on_tool_selected(tool_id: String) -> void:
	_active_tool = tool_id
	_clear_preview()
	_clear_measure()
	print("CADToolManager: active tool = ", tool_id)


# ─── Trigger dispatch ────────────────────────────────────────────────────────

func _on_trigger_pressed() -> void:
	match _active_tool:
		"box":      _place_primitive("box")
		"cylinder": _place_primitive("cylinder")
		"sphere":   _place_primitive("sphere")
		"plane":    _place_work_plane()
		"measure":  _handle_measure()
		# "select"  — handled by interaction_ray natively.
		# "delete"  — handled via the ray's `selected` signal (_on_ray_object_selected).


# ─── Object creation ──────────────────────────────────────────────────────────

func _place_primitive(type: String) -> void:
	if _right_ray == null or not _right_ray.is_colliding():
		return
	# Don't spawn while pointing at an existing CAD object
	if _right_ray.get_hovered_object() != null:
		return

	var hit := _right_ray.get_collision_point()
	var plane := _find_work_plane(_right_ray.get_collider())
	if plane:
		hit = plane.snap_world_position(hit)

	# Build the primitive and pre-set its label so the undo history reads correctly
	var obj: CADObject
	match type:
		"box":
			var b := PrimitiveBox.new()
			b.object_label = "Box"
			obj = b
		"cylinder":
			var c := PrimitiveCylinder.new()
			c.object_label = "Cylinder"
			obj = c
		"sphere":
			var s := PrimitiveSphere.new()
			s.object_label = "Sphere"
			obj = s
	if obj == null:
		return

	# UndoRedoManager.create_object calls add_child immediately via push_custom,
	# triggering _ready() on the object before returning.
	UndoRedoManager.create_object(obj)

	# Set world position after _ready() so global_transform is valid
	var up := plane.get_normal() if plane else Vector3.UP
	obj.global_position = hit + up * _object_half_height(obj)

	if _right_ctrl and _right_ctrl.has_method("haptic_click"):
		_right_ctrl.haptic_click()


func _object_half_height(obj: CADObject) -> float:
	if obj is PrimitiveBox:
		return (obj as PrimitiveBox).dimensions.y * 0.5
	if obj is PrimitiveCylinder:
		return (obj as PrimitiveCylinder).height * 0.5
	if obj is PrimitiveSphere:
		return (obj as PrimitiveSphere).radius
	return 0.05


# ─── Work plane creation ─────────────────────────────────────────────────────

func _place_work_plane() -> void:
	if _right_ray == null or not _right_ray.is_colliding():
		return

	var hit    := _right_ray.get_collision_point()
	var normal := _right_ray.get_collision_normal()
	var parent := _cad_root if _cad_root else get_tree().get_root() as Node3D
	var plane  := WorkPlane.new()
	plane.name  = "WorkPlane_%d" % PlaneManager.planes.size()

	var plane_ref := plane

	# do_fn runs immediately (first placement) and again on redo.
	# undo_fn removes the plane and unregisters it from PlaneManager.
	UndoRedoManager.push_custom(
		"Create Work Plane",
		func():
			parent.add_child(plane_ref)
			plane_ref.place_on_surface(hit, normal)
			if not plane_ref in PlaneManager.planes:
				PlaneManager.planes.append(plane_ref)
			PlaneManager.active_plane = plane_ref
			PlaneManager.plane_created.emit(plane_ref),
		func():
			PlaneManager.planes.erase(plane_ref)
			PlaneManager.plane_deleted.emit(plane_ref)
			if PlaneManager.active_plane == plane_ref:
				PlaneManager.active_plane = \
					PlaneManager.planes.back() if PlaneManager.planes.size() > 0 else null
			if plane_ref.get_parent():
				plane_ref.get_parent().remove_child(plane_ref)
	)

	if _right_ctrl and _right_ctrl.has_method("haptic_click"):
		_right_ctrl.haptic_click()


# ─── Delete ───────────────────────────────────────────────────────────────────

## Fired by interaction_ray.selected signal whenever the trigger selects an object.
func _on_ray_object_selected(obj: Node3D, _hit_pos: Vector3) -> void:
	if _active_tool == "delete" and obj is CADObject:
		UndoRedoManager.delete_object(obj as CADObject)
		if _right_ctrl and _right_ctrl.has_method("haptic_confirm"):
			_right_ctrl.haptic_confirm()


# ─── Measure tool ─────────────────────────────────────────────────────────────

func _handle_measure() -> void:
	if _right_ray == null or not _right_ray.is_colliding():
		return

	var hit := _right_ray.get_collision_point()

	if _measure_step == 0:
		# First click — store point A and show a dot
		_clear_measure()
		_measure_start = hit
		_measure_step  = 1
		_show_measure_dot(hit)
		if _right_ctrl and _right_ctrl.has_method("haptic_click"):
			_right_ctrl.haptic_click()
	else:
		# Second click — draw the full line with distance label
		_show_measure_line(_measure_start, hit)
		_measure_step = 0
		if _right_ctrl and _right_ctrl.has_method("haptic_confirm"):
			_right_ctrl.haptic_confirm()


func _show_measure_dot(world_pos: Vector3) -> void:
	_measure_visual = Node3D.new()
	_measure_visual.name = "MeasureDot"
	get_tree().get_root().add_child(_measure_visual)
	_add_dot(_measure_visual, world_pos, Color(1.0, 0.8, 0.1))


func _show_measure_line(from: Vector3, to: Vector3) -> void:
	_clear_measure()
	var dist: float = from.distance_to(to)

	var root := Node3D.new()
	root.name = "MeasureLine"
	get_tree().get_root().add_child(root)
	_measure_visual = root

	# Endpoint dots
	_add_dot(root, from, Color(1.0, 0.8, 0.1))
	_add_dot(root, to,   Color(1.0, 0.8, 0.1))

	# Line rendered as PRIMITIVE_LINES — no orientation math needed.
	# root is at world origin so world coords == local coords here.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.add_vertex(from)
	st.add_vertex(to)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color  = Color(1.0, 0.9, 0.2)
	var line_mi := MeshInstance3D.new()
	line_mi.mesh = st.commit()
	line_mi.material_override = line_mat
	root.add_child(line_mi)

	# Billboard label always facing the camera
	var lbl := Label3D.new()
	lbl.text         = "%.1f cm" % (dist * 100.0)
	lbl.pixel_size   = 0.0008
	lbl.font_size    = 32
	lbl.billboard    = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate     = Color(1.0, 1.0, 0.3)
	root.add_child(lbl)
	lbl.global_position = (from + to) * 0.5 + Vector3.UP * 0.04


func _add_dot(parent: Node3D, world_pos: Vector3, color: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.010
	sm.height = 0.020
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dot := MeshInstance3D.new()
	dot.mesh = sm
	dot.material_override = mat
	parent.add_child(dot)
	dot.global_position = world_pos


func _clear_measure() -> void:
	if _measure_visual:
		_measure_visual.queue_free()
		_measure_visual = null
	_measure_step = 0


# ─── Undo / Redo ──────────────────────────────────────────────────────────────

func _on_undo() -> void:
	UndoRedoManager.undo()
	if _right_ctrl and _right_ctrl.has_method("haptic_click"):
		_right_ctrl.haptic_click()


func _on_redo() -> void:
	UndoRedoManager.redo()
	if _right_ctrl and _right_ctrl.has_method("haptic_click"):
		_right_ctrl.haptic_click()


# ─── Helpers ─────────────────────────────────────────────────────────────────

## Walk up the scene tree from `collider` to find a WorkPlane ancestor.
func _find_work_plane(collider: Object) -> WorkPlane:
	if collider == null:
		return null
	var node := collider as Node
	while node != null:
		if node is WorkPlane:
			return node as WorkPlane
		node = node.get_parent()
	return null
