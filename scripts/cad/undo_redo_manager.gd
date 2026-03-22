## UndoRedoManager — autoload singleton for undo/redo in the CAD scene.
##
## Uses the Command pattern. Every operation that modifies the scene
## creates an UndoRedoAction and pushes it here.
##
## Built-in operations:
##   • create_object   — add a CADObject to the scene
##   • delete_object   — remove a CADObject
##   • transform_object — move/rotate/scale an object
##   • change_params   — modify primitive dimensions
##   • create_plane    — add a WorkPlane
##
## Custom operations can use push_custom() with undo/redo callables.
##
## Example:
##   UndoRedoManager.create_object(my_box)
##   UndoRedoManager.undo()
extends Node

signal history_changed(can_undo: bool, can_redo: bool)
signal action_done(action_name: String)
signal action_undone(action_name: String)

const MAX_HISTORY: int = 64

# ─── Internal types ───────────────────────────────────────────────────────────

class UndoRedoAction:
	var name: String
	var do_action: Callable
	var undo_action: Callable

	func _init(n: String, do_fn: Callable, undo_fn: Callable) -> void:
		name = n
		do_action = do_fn
		undo_action = undo_fn

# ─── State ───────────────────────────────────────────────────────────────────

var _history: Array[UndoRedoAction] = []
var _redo_stack: Array[UndoRedoAction] = []
var _cad_root: Node3D


func _ready() -> void:
	call_deferred("_find_cad_root")


func _find_cad_root() -> void:
	_cad_root = get_tree().get_root().find_child("CADRoot", true, false) as Node3D


# ─── Core push / undo / redo ─────────────────────────────────────────────────

## Push a custom action. The action is executed immediately.
func push_custom(action_name: String, do_fn: Callable, undo_fn: Callable) -> void:
	var action := UndoRedoAction.new(action_name, do_fn, undo_fn)
	do_fn.call()
	_history.append(action)
	_redo_stack.clear()

	# Trim history to max length
	while _history.size() > MAX_HISTORY:
		_history.pop_front()

	_emit_change()
	action_done.emit(action_name)


func undo() -> void:
	if _history.is_empty():
		return
	var action: UndoRedoAction = _history.pop_back()
	action.undo_action.call()
	_redo_stack.append(action)
	_emit_change()
	action_undone.emit(action.name)


func redo() -> void:
	if _redo_stack.is_empty():
		return
	var action: UndoRedoAction = _redo_stack.pop_back()
	action.do_action.call()
	_history.append(action)
	_emit_change()
	action_done.emit(action.name)


func can_undo() -> bool:
	return not _history.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func clear() -> void:
	_history.clear()
	_redo_stack.clear()
	_emit_change()


func _emit_change() -> void:
	history_changed.emit(can_undo(), can_redo())


# ─── Convenience helpers ─────────────────────────────────────────────────────

## Record the creation of a CADObject.
func create_object(obj: CADObject) -> void:
	var parent: Node3D = _cad_root if _cad_root else get_tree().get_root()
	var obj_ref := obj  # capture for closures

	push_custom(
		"Create %s" % obj.object_label,
		func(): parent.add_child(obj_ref),
		func(): obj_ref.get_parent().remove_child(obj_ref)
	)


## Record the deletion of a CADObject.
func delete_object(obj: CADObject) -> void:
	var original_parent: Node = obj.get_parent()
	var obj_ref := obj

	push_custom(
		"Delete %s" % obj.object_label,
		func():
			if obj_ref.get_parent():
				obj_ref.get_parent().remove_child(obj_ref),
		func():
			if original_parent:
				original_parent.add_child(obj_ref)
	)


## Record a transform change (call BEFORE applying the transform).
## `old_xf` is the current transform; `new_xf` is what it will become.
func transform_object(obj: CADObject, old_xf: Transform3D, new_xf: Transform3D) -> void:
	var obj_ref := obj

	push_custom(
		"Move %s" % obj.object_label,
		func(): obj_ref.global_transform = new_xf,
		func(): obj_ref.global_transform = old_xf
	)


## Record a parameter change for a PrimitiveBox (dimensions).
func change_box_dimensions(obj: PrimitiveBox, old_dims: Vector3, new_dims: Vector3) -> void:
	var obj_ref := obj

	push_custom(
		"Resize %s" % obj.object_label,
		func(): obj_ref.dimensions = new_dims,
		func(): obj_ref.dimensions = old_dims
	)


## Record a radius change for a PrimitiveCylinder or PrimitiveSphere.
func change_radius(obj: CADObject, old_radius: float, new_radius: float) -> void:
	var obj_ref := obj

	push_custom(
		"Resize %s" % obj.object_label,
		func(): obj_ref.set("radius", new_radius),
		func(): obj_ref.set("radius", old_radius)
	)


## Record a WorkPlane creation.
func create_plane(plane: WorkPlane) -> void:
	var parent: Node3D = plane.get_parent()
	var plane_ref := plane

	push_custom(
		"Create Work Plane",
		func(): parent.add_child(plane_ref),
		func(): plane_ref.get_parent().remove_child(plane_ref)
	)


## Record a WorkPlane move.
func move_plane(plane: WorkPlane, old_xf: Transform3D, new_xf: Transform3D) -> void:
	var plane_ref := plane

	push_custom(
		"Move Work Plane",
		func(): plane_ref.global_transform = new_xf,
		func(): plane_ref.global_transform = old_xf
	)


# ─── Debug ───────────────────────────────────────────────────────────────────

func get_history_names() -> Array[String]:
	var names: Array[String] = []
	for a in _history:
		names.append(a.name)
	return names
