## PrimitiveCylinder — a cylinder/tube CAD primitive.
class_name PrimitiveCylinder
extends CADObject

signal params_changed

@export var radius: float = 0.05:
	set(value):
		radius = max(0.001, value)
		_update_geometry()
		params_changed.emit()

@export var height: float = 0.1:
	set(value):
		height = max(0.001, value)
		_update_geometry()
		params_changed.emit()

@export var radial_segments: int = 24:
	set(value):
		radial_segments = clampi(value, 3, 64)
		_update_geometry()

@export var cap_top: bool = true:
	set(value):
		cap_top = value
		_update_geometry()

@export var cap_bottom: bool = true:
	set(value):
		cap_bottom = value
		_update_geometry()


func _ready() -> void:
	super._ready()
	object_label = "Cylinder"
	_setup_nodes()
	_update_geometry()


func _setup_nodes() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	add_child(mesh_instance)

	collision_shape = CollisionShape3D.new()
	collision_shape.name = "Collision"
	collision_shape.shape = CylinderShape3D.new()
	add_child(collision_shape)


func _update_geometry() -> void:
	if mesh_instance == null:
		return

	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = radius
	cyl_mesh.bottom_radius = radius
	cyl_mesh.height = height
	cyl_mesh.radial_segments = radial_segments
	cyl_mesh.rings = 1
	cyl_mesh.cap_top = cap_top
	cyl_mesh.cap_bottom = cap_bottom
	mesh_instance.mesh = cyl_mesh

	var cyl_shape := collision_shape.shape as CylinderShape3D
	if cyl_shape == null:
		cyl_shape = CylinderShape3D.new()
		collision_shape.shape = cyl_shape
	cyl_shape.radius = radius
	cyl_shape.height = height

	_update_visual_state()
	geometry_changed.emit(self)


func _serialize_params() -> Dictionary:
	return {
		"radius": radius,
		"height": height,
		"radial_segments": radial_segments,
		"cap_top": cap_top,
		"cap_bottom": cap_bottom,
	}


func _deserialize_params(params: Dictionary) -> void:
	radial_segments = params.get("radial_segments", radial_segments)
	cap_top = params.get("cap_top", cap_top)
	cap_bottom = params.get("cap_bottom", cap_bottom)
	radius = params.get("radius", radius)
	height = params.get("height", height)
