## PlaneManager — autoload singleton that manages all WorkPlane instances.
##
## Usage from any script:
##   PlaneManager.create_plane_on_surface(hit_point, surface_normal)
##   PlaneManager.active_plane.snap_world_position(pos)
##
## The active plane is the one new objects are placed on.
extends Node

signal active_plane_changed(plane: WorkPlane)
signal plane_created(plane: WorkPlane)
signal plane_deleted(plane: WorkPlane)

# ─── State ───────────────────────────────────────────────────────────────────

var active_plane: WorkPlane:
	set(value):
		active_plane = value
		active_plane_changed.emit(value)

var planes: Array[WorkPlane] = []

var _cad_root: Node  # parent node for planes in the scene


func _ready() -> void:
	# Defer until the main scene is ready so we can find CADRoot
	call_deferred("_find_cad_root")


func _find_cad_root() -> void:
	_cad_root = get_tree().get_root().find_child("CADRoot", true, false) as Node
	if _cad_root == null:
		push_warning("PlaneManager: CADRoot not found. Planes will be added to scene root.")
		_cad_root = get_tree().get_root()


# ─── Creation ────────────────────────────────────────────────────────────────

## Create a plane aligned to a real-world surface (e.g. a table or floor).
func create_plane_on_surface(hit_point: Vector3, surface_normal: Vector3) -> WorkPlane:
	var plane := _new_plane()
	plane.place_on_surface(hit_point, surface_normal)
	return plane


## Create a horizontal plane at eye level, facing upward.
func create_horizontal_plane(at_position: Vector3) -> WorkPlane:
	var plane := _new_plane()
	plane.global_position = at_position
	plane.global_transform.basis = Basis.IDENTITY  # XZ is horizontal
	return plane


## Create a vertical plane (like a wall) facing the camera.
func create_vertical_plane(at_position: Vector3, camera: Camera3D) -> WorkPlane:
	var plane := _new_plane()
	plane.place_facing_camera(at_position, camera)
	return plane


func _new_plane() -> WorkPlane:
	var plane := WorkPlane.new()
	plane.name = "WorkPlane_%d" % planes.size()

	var parent: Node = _cad_root if _cad_root else get_tree().get_root()
	parent.add_child(plane)

	planes.append(plane)
	active_plane = plane

	plane_created.emit(plane)
	return plane


# ─── Management ──────────────────────────────────────────────────────────────

func set_active_plane(plane: WorkPlane) -> void:
	if plane in planes:
		active_plane = plane


func delete_plane(plane: WorkPlane) -> void:
	if not plane in planes:
		return

	planes.erase(plane)
	plane_deleted.emit(plane)

	if active_plane == plane:
		active_plane = planes.back() if planes.size() > 0 else null

	plane.queue_free()


func delete_all_planes() -> void:
	for plane in planes.duplicate():
		delete_plane(plane)


# ─── Query ───────────────────────────────────────────────────────────────────

## Snap a world position to the active plane's grid.
## Returns the position unchanged if there's no active plane.
func snap(world_pos: Vector3) -> Vector3:
	if active_plane:
		return active_plane.snap_world_position(world_pos)
	return world_pos


## Returns true if there is an active plane ready to accept new geometry.
func has_active_plane() -> bool:
	return active_plane != null


## Return the index of a plane in the list.
func get_plane_index(plane: WorkPlane) -> int:
	return planes.find(plane)
