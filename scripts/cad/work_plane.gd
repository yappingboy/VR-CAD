## WorkPlane — a positioned, oriented working plane in 3D space.
##
## Features:
##   • Procedural grid mesh (minor + major divisions)
##   • Snap-to-grid in local plane coordinates
##   • Can be pinned to a real-world surface hit by the interaction ray
##   • Optional world-lock (spatial anchor placeholder)
##   • Raycast collision so the ray can "land" on the plane
##
## Coordinate convention: the plane lies in its local XZ plane (Y = 0).
class_name WorkPlane
extends Node3D

signal moved
signal snap_toggled(enabled: bool)
signal grid_size_changed(new_size: float)

# ─── Config ──────────────────────────────────────────────────────────────────

## Total half-extent of the visible grid in metres
@export var grid_half_extent: float = 2.5

## Distance between major grid lines (e.g. 0.1 m = 10 cm)
@export var major_spacing: float = 0.1:
	set(value):
		major_spacing = max(0.001, value)
		_rebuild_grid()
		grid_size_changed.emit(major_spacing)

## How many minor divisions per major cell
@export var minor_divisions: int = 10:
	set(value):
		minor_divisions = clampi(value, 1, 20)
		_rebuild_grid()

@export var snap_enabled: bool = true:
	set(value):
		snap_enabled = value
		snap_toggled.emit(snap_enabled)

@export var snap_to_minor: bool = true  # snap to minor grid; false = major only

# ─── State ───────────────────────────────────────────────────────────────────

var is_world_locked: bool = false
var _world_lock_transform: Transform3D

# ─── Internal nodes ───────────────────────────────────────────────────────────

var _grid_mesh: MeshInstance3D
var _plane_body: StaticBody3D  # lets the interaction ray hit the plane


func _ready() -> void:
	_build_collision_plane()
	_build_grid_mesh()
	_rebuild_grid()


# ─── Setup ───────────────────────────────────────────────────────────────────

func _build_collision_plane() -> void:
	_plane_body = StaticBody3D.new()
	_plane_body.name = "PlaneBody"
	add_child(_plane_body)
	_plane_body.add_to_group("work_plane_collision")

	var shape := WorldBoundaryShape3D.new()  # infinite flat plane at local Y=0
	# WorldBoundaryShape is axis-aligned, so we use a large box instead
	# to support arbitrary plane orientations.
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(grid_half_extent * 2.0, 0.002, grid_half_extent * 2.0)
	col.shape = box_shape
	_plane_body.add_child(col)


func _build_grid_mesh() -> void:
	_grid_mesh = MeshInstance3D.new()
	_grid_mesh.name = "Grid"
	_grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid_mesh)


func _rebuild_grid() -> void:
	if _grid_mesh == null:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var minor_spacing: float = major_spacing / float(minor_divisions)
	var step_count: int = int(ceil(grid_half_extent / minor_spacing))
	var half: float = step_count * minor_spacing  # actual half-extent after rounding

	for i in range(-step_count, step_count + 1):
		var pos: float = i * minor_spacing
		var is_major: bool = (i % minor_divisions) == 0
		var is_origin: bool = i == 0

		var color: Color
		if is_origin:
			color = Color(0.9, 0.9, 0.9, 0.9)
		elif is_major:
			color = Color(0.0, 0.75, 1.0, 0.55)
		else:
			color = Color(0.0, 0.45, 0.75, 0.22)

		st.set_color(color)
		st.add_vertex(Vector3(pos, 0.0, -half))
		st.add_vertex(Vector3(pos, 0.0,  half))

		st.set_color(color)
		st.add_vertex(Vector3(-half, 0.0, pos))
		st.add_vertex(Vector3( half, 0.0, pos))

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_grid_mesh.mesh = st.commit()
	_grid_mesh.material_override = mat


# ─── Coordinate helpers ──────────────────────────────────────────────────────

## Snap a world-space position to the nearest grid point on this plane.
## The Y component is clamped to sit exactly on the plane surface.
func snap_world_position(world_pos: Vector3) -> Vector3:
	var local_pos: Vector3 = to_local(world_pos)
	local_pos.y = 0.0  # project onto plane

	if snap_enabled:
		var spacing: float = (major_spacing / float(minor_divisions)) if snap_to_minor else major_spacing
		local_pos.x = round(local_pos.x / spacing) * spacing
		local_pos.z = round(local_pos.z / spacing) * spacing

	return to_global(local_pos)


## Project an arbitrary world point onto this plane (no snapping).
func project_to_plane(world_pos: Vector3) -> Vector3:
	var local_pos: Vector3 = to_local(world_pos)
	local_pos.y = 0.0
	return to_global(local_pos)


## The plane's normal in world space.
func get_normal() -> Vector3:
	return global_transform.basis.y.normalized()


## A point on the plane in world space.
func get_origin() -> Vector3:
	return global_position


## Distance from a world point to the plane surface.
func distance_to_plane(world_pos: Vector3) -> float:
	return (world_pos - global_position).dot(get_normal())


# ─── Placement ───────────────────────────────────────────────────────────────

## Place the plane at `point` and orient it so its normal matches `surface_normal`.
func place_on_surface(point: Vector3, surface_normal: Vector3) -> void:
	global_position = point
	# Orient Y axis toward the surface normal
	if surface_normal.is_normalized() and not surface_normal.is_zero_approx():
		var up_hint: Vector3 = Vector3.UP if abs(surface_normal.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		global_transform.basis = Basis.looking_at(-surface_normal, up_hint).rotated(
			Vector3.RIGHT, -PI * 0.5
		)
	moved.emit()


## Place the plane at `point` facing the camera (convenient free-floating placement).
func place_facing_camera(point: Vector3, camera: Camera3D) -> void:
	global_position = point
	var cam_dir: Vector3 = (camera.global_position - point).normalized()
	place_on_surface(point, cam_dir)


## Lift the plane up/down along its normal by `delta` metres.
func offset_along_normal(delta: float) -> void:
	global_position += get_normal() * delta
	moved.emit()


# ─── World lock ──────────────────────────────────────────────────────────────

func world_lock() -> void:
	_world_lock_transform = global_transform
	is_world_locked = true
	print("WorkPlane: World-locked at ", global_position)


func world_unlock() -> void:
	is_world_locked = false


func _process(_delta: float) -> void:
	# When world-locked, restore position each frame so XROrigin movement
	# doesn't drag the plane along with the player.
	if is_world_locked:
		global_transform = _world_lock_transform


# ─── Visibility ──────────────────────────────────────────────────────────────

func set_grid_visible(v: bool) -> void:
	if _grid_mesh:
		_grid_mesh.visible = v


func toggle_grid() -> void:
	if _grid_mesh:
		_grid_mesh.visible = not _grid_mesh.visible
