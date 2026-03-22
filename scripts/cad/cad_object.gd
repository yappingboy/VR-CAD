## CADObject — base class for all geometry in the CAD scene.
##
## Extends StaticBody3D so that RayCast3D can hit it automatically.
## Each subclass (PrimitiveBox, PrimitiveCylinder, …) must call
## _setup_mesh_and_collision() and keep a CollisionShape3D up to date.
##
## Interaction states drive visual feedback (color changes).
## The undo/redo system stores and restores serialized snapshots.
class_name CADObject
extends StaticBody3D

# ─── Signals ─────────────────────────────────────────────────────────────────

signal selected(obj: CADObject)
signal deselected(obj: CADObject)
signal geometry_changed(obj: CADObject)
signal label_changed(new_label: String)

# ─── Interaction state ───────────────────────────────────────────────────────

enum State { IDLE, HOVERED, SELECTED, BEING_MOVED }

var state: State = State.IDLE:
	set(value):
		state = value
		_update_visual_state()

# ─── Properties ──────────────────────────────────────────────────────────────

@export var object_label: String = "Object":
	set(value):
		object_label = value
		label_changed.emit(value)

@export var object_color: Color = Color(0.4, 0.7, 1.0):
	set(value):
		object_color = value
		_apply_color()

## Constraints are stored as a dictionary array so they can be serialized.
## Each entry: { "type": String, "value": Variant, "other": NodePath }
var constraints: Array[Dictionary] = []

# ─── Internal nodes (created by subclasses) ──────────────────────────────────

var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

# ─── Materials ───────────────────────────────────────────────────────────────

var _mat_idle: StandardMaterial3D
var _mat_hover: StandardMaterial3D
var _mat_selected: StandardMaterial3D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("cad_objects")
	_build_materials()


func _build_materials() -> void:
	_mat_idle = _make_material(object_color)

	_mat_hover = _make_material(object_color.lightened(0.3))
	_mat_hover.emission_enabled = true
	_mat_hover.emission = object_color.lightened(0.2)
	_mat_hover.emission_energy_multiplier = 0.4

	_mat_selected = _make_material(object_color.lightened(0.1))
	_mat_selected.emission_enabled = true
	_mat_selected.emission = Color(0.2, 0.8, 1.0)
	_mat_selected.emission_energy_multiplier = 0.8


func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.metallic = 0.1
	return mat


func _apply_color() -> void:
	_build_materials()
	_update_visual_state()


func _update_visual_state() -> void:
	if mesh_instance == null:
		return
	match state:
		State.IDLE:
			mesh_instance.material_override = _mat_idle
		State.HOVERED:
			mesh_instance.material_override = _mat_hover
		State.SELECTED:
			mesh_instance.material_override = _mat_selected
		State.BEING_MOVED:
			mesh_instance.material_override = _mat_selected


# ─── Interaction callbacks (called by InteractionRay) ────────────────────────

func on_hover() -> void:
	if state == State.IDLE:
		state = State.HOVERED


func on_unhover() -> void:
	if state == State.HOVERED:
		state = State.IDLE


func on_select(_hit_pos: Vector3 = Vector3.ZERO) -> void:
	state = State.SELECTED
	selected.emit(self)


func on_deselect() -> void:
	state = State.IDLE
	deselected.emit(self)


func on_grab() -> void:
	state = State.BEING_MOVED


func on_release() -> void:
	state = State.SELECTED


# ─── Serialization ───────────────────────────────────────────────────────────

## Returns a Dictionary snapshot used by UndoRedoManager.
func serialize() -> Dictionary:
	return {
		"class": get_class(),
		"label": object_label,
		"color": [object_color.r, object_color.g, object_color.b, object_color.a],
		"transform": _transform_to_array(global_transform),
		"constraints": constraints.duplicate(true),
		"params": _serialize_params(),
	}


## Restore state from a snapshot.
func deserialize(data: Dictionary) -> void:
	object_label = data.get("label", object_label)
	var c: Array = data.get("color", [])
	if c.size() == 4:
		object_color = Color(c[0], c[1], c[2], c[3])
	global_transform = _array_to_transform(data.get("transform", []))
	constraints = data.get("constraints", []).duplicate(true)
	_deserialize_params(data.get("params", {}))


## Override in subclasses to include geometry parameters.
func _serialize_params() -> Dictionary:
	return {}


## Override in subclasses to restore geometry parameters.
func _deserialize_params(_params: Dictionary) -> void:
	pass


# ─── Geometry ────────────────────────────────────────────────────────────────

## Returns the world-space AABB of this object.
func get_world_aabb() -> AABB:
	if mesh_instance == null:
		return AABB(global_position, Vector3.ZERO)
	var local_aabb: AABB = mesh_instance.get_aabb()
	return global_transform * local_aabb


## Returns the center point of the object in world space.
func get_center() -> Vector3:
	return global_position


# ─── Constraint helpers ──────────────────────────────────────────────────────

func add_constraint(type: String, value: Variant, other: Node = null) -> void:
	var entry := {"type": type, "value": value}
	if other:
		entry["other"] = get_path_to(other)
	constraints.append(entry)


func remove_constraint(index: int) -> void:
	if index >= 0 and index < constraints.size():
		constraints.remove_at(index)


func clear_constraints() -> void:
	constraints.clear()


# ─── Transform serialization helpers ─────────────────────────────────────────

func _transform_to_array(t: Transform3D) -> Array:
	var b: Basis = t.basis
	return [
		b.x.x, b.x.y, b.x.z,
		b.y.x, b.y.y, b.y.z,
		b.z.x, b.z.y, b.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]


func _array_to_transform(a: Array) -> Transform3D:
	if a.size() < 12:
		return Transform3D.IDENTITY
	return Transform3D(
		Basis(
			Vector3(a[0], a[1], a[2]),
			Vector3(a[3], a[4], a[5]),
			Vector3(a[6], a[7], a[8])
		),
		Vector3(a[9], a[10], a[11])
	)
