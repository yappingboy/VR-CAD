## PrimitiveSphere — a sphere CAD primitive.
class_name PrimitiveSphere
extends CADObject

signal params_changed

@export var radius: float = 0.05:
	set(value):
		radius = max(0.001, value)
		_update_geometry()
		params_changed.emit()

@export var rings: int = 16:
	set(value):
		rings = clampi(value, 4, 64)
		_update_geometry()

@export var radial_segments: int = 24:
	set(value):
		radial_segments = clampi(value, 4, 64)
		_update_geometry()


func _ready() -> void:
	super._ready()
	object_label = "Sphere"
	_setup_nodes()
	_update_geometry()


func _setup_nodes() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	add_child(mesh_instance)

	collision_shape = CollisionShape3D.new()
	collision_shape.name = "Collision"
	collision_shape.shape = SphereShape3D.new()
	add_child(collision_shape)


func _update_geometry() -> void:
	if mesh_instance == null:
		return

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	sphere_mesh.rings = rings
	sphere_mesh.radial_segments = radial_segments
	mesh_instance.mesh = sphere_mesh

	var sphere_shape := collision_shape.shape as SphereShape3D
	if sphere_shape == null:
		sphere_shape = SphereShape3D.new()
		collision_shape.shape = sphere_shape
	sphere_shape.radius = radius

	_update_visual_state()
	geometry_changed.emit(self)


func _serialize_params() -> Dictionary:
	return {
		"radius": radius,
		"rings": rings,
		"radial_segments": radial_segments,
	}


func _deserialize_params(params: Dictionary) -> void:
	rings = params.get("rings", rings)
	radial_segments = params.get("radial_segments", radial_segments)
	radius = params.get("radius", radius)
