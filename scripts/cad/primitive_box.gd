## PrimitiveBox — a rectangular box CAD primitive.
##
## Dimensions are in metres (real-world scale).
## Changing any dimension live-updates the mesh and collision shape.
class_name PrimitiveBox
extends CADObject

signal dimensions_changed(new_dims: Vector3)

@export var dimensions: Vector3 = Vector3(0.1, 0.1, 0.1):
	set(value):
		dimensions = value.max(Vector3(0.001, 0.001, 0.001))  # clamp > 0
		_update_geometry()
		dimensions_changed.emit(dimensions)


func _ready() -> void:
	super._ready()
	object_label = "Box"
	_setup_nodes()
	_update_geometry()


func _setup_nodes() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	add_child(mesh_instance)

	collision_shape = CollisionShape3D.new()
	collision_shape.name = "Collision"
	collision_shape.shape = BoxShape3D.new()
	add_child(collision_shape)


func _update_geometry() -> void:
	if mesh_instance == null:
		return

	var box_mesh := BoxMesh.new()
	box_mesh.size = dimensions
	mesh_instance.mesh = box_mesh

	var box_shape := collision_shape.shape as BoxShape3D
	if box_shape == null:
		box_shape = BoxShape3D.new()
		collision_shape.shape = box_shape
	box_shape.size = dimensions

	_update_visual_state()
	geometry_changed.emit(self)


# ─── Handles (resize grips shown when selected) ──────────────────────────────

var _handles: Array[MeshInstance3D] = []
const HANDLE_RADIUS: float = 0.012

func _show_handles() -> void:
	_clear_handles()
	# One handle per face: ±X, ±Y, ±Z
	var offsets: Array[Vector3] = [
		Vector3(dimensions.x * 0.5, 0, 0),
		Vector3(-dimensions.x * 0.5, 0, 0),
		Vector3(0, dimensions.y * 0.5, 0),
		Vector3(0, -dimensions.y * 0.5, 0),
		Vector3(0, 0, dimensions.z * 0.5),
		Vector3(0, 0, -dimensions.z * 0.5),
	]
	for offset in offsets:
		var h := _make_handle(offset)
		add_child(h)
		_handles.append(h)


func _make_handle(local_pos: Vector3) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = HANDLE_RADIUS
	sphere.height = HANDLE_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var h := MeshInstance3D.new()
	h.mesh = sphere
	h.material_override = mat
	h.position = local_pos
	h.name = "Handle"
	return h


func _clear_handles() -> void:
	for h in _handles:
		h.queue_free()
	_handles.clear()


# ─── State changes ───────────────────────────────────────────────────────────

func on_select(hit_pos: Vector3 = Vector3.ZERO) -> void:
	super.on_select(hit_pos)
	_show_handles()


func on_deselect() -> void:
	super.on_deselect()
	_clear_handles()


# ─── Serialization ───────────────────────────────────────────────────────────

func _serialize_params() -> Dictionary:
	return {
		"width": dimensions.x,
		"height": dimensions.y,
		"depth": dimensions.z,
	}


func _deserialize_params(params: Dictionary) -> void:
	dimensions = Vector3(
		params.get("width", dimensions.x),
		params.get("height", dimensions.y),
		params.get("depth", dimensions.z)
	)


# ─── Convenience ─────────────────────────────────────────────────────────────

func set_width(v: float) -> void:
	dimensions = Vector3(v, dimensions.y, dimensions.z)

func set_height(v: float) -> void:
	dimensions = Vector3(dimensions.x, v, dimensions.z)

func set_depth(v: float) -> void:
	dimensions = Vector3(dimensions.x, dimensions.y, v)
