## InteractionRay — attached to a RayCast3D node under each XRController3D
##
## Handles all pointer-style interaction in the VR scene:
##   • Draws a visual laser ray
##   • Shows a cursor dot at the hit point
##   • Detects hover / unhover on interactive objects
##   • Translates trigger presses into select / deselect actions
##   • Translates grip presses into grab / move actions
##
## Objects that want to receive hover/select events should:
##   1. Be in the "interactable" group  OR  have a CollisionShape3D
##   2. Implement on_hover(), on_unhover(), on_select(), on_deselect() if desired
extends RayCast3D

# ─── Signals ─────────────────────────────────────────────────────────────────

signal hovered(object: Node3D, hit_position: Vector3, hit_normal: Vector3)
signal unhovered(object: Node3D)
signal selected(object: Node3D, hit_position: Vector3)
signal deselected(object: Node3D)
signal grabbed(object: Node3D)
signal released(object: Node3D)

## Emitted every frame with the world position the ray is pointing at.
## Useful for work plane placement and cursor feedback.
signal ray_pointing_at(world_position: Vector3, hit_normal: Vector3, hit_object)

# ─── Config ──────────────────────────────────────────────────────────────────

@export var ray_length: float = 8.0
@export var ray_color: Color = Color(0.0, 0.8, 1.0, 0.7)
@export var ray_hit_color: Color = Color(0.2, 1.0, 0.6, 0.9)
@export var cursor_radius: float = 0.012

# ─── Private state ───────────────────────────────────────────────────────────

var _controller: Node  # XRController3D (ControllerInput script)
var _hovered_object: Node3D = null
var _grabbed_object: Node3D = null
var _grabbed_offset: Transform3D

var _ray_mesh: MeshInstance3D
var _ray_material: StandardMaterial3D
var _cursor_mesh: MeshInstance3D


func _ready() -> void:
	target_position = Vector3(0, 0, -ray_length)
	enabled = true

	_controller = get_parent()
	_build_ray_visual()
	_build_cursor_visual()

	# Connect to parent controller's signals
	if _controller.has_signal("trigger_pressed"):
		_controller.trigger_pressed.connect(_on_trigger_pressed)
		_controller.trigger_released.connect(_on_trigger_released)
	if _controller.has_signal("grip_pressed"):
		_controller.grip_pressed.connect(_on_grip_pressed)
		_controller.grip_released.connect(_on_grip_released)


func _process(_delta: float) -> void:
	_update_ray_visual()
	_update_hover()
	_update_grabbed_object()


# ─── Visual construction ─────────────────────────────────────────────────────

func _build_ray_visual() -> void:
	_ray_material = StandardMaterial3D.new()
	_ray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ray_material.albedo_color = ray_color

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.001
	cyl.bottom_radius = 0.001
	cyl.height = ray_length
	cyl.radial_segments = 6

	_ray_mesh = MeshInstance3D.new()
	_ray_mesh.mesh = cyl
	_ray_mesh.material_override = _ray_material
	# CylinderMesh is along Y; rotate 90° so it points along -Z (ray direction)
	# then translate half the length forward so origin is at the controller tip
	_ray_mesh.rotation_degrees = Vector3(90, 0, 0)
	_ray_mesh.position = Vector3(0, 0, -ray_length * 0.5)
	add_child(_ray_mesh)


func _build_cursor_visual() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = cursor_radius
	sphere.height = cursor_radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_cursor_mesh = MeshInstance3D.new()
	_cursor_mesh.mesh = sphere
	_cursor_mesh.material_override = mat
	_cursor_mesh.visible = false
	# Cursor lives in world space — add it to the scene root so it doesn't
	# move with the controller transform.
	get_tree().get_root().add_child.call_deferred(_cursor_mesh)


# ─── Per-frame updates ───────────────────────────────────────────────────────

func _update_ray_visual() -> void:
	if not is_colliding():
		_ray_material.albedo_color = ray_color
		# Restore full-length ray
		var cyl := _ray_mesh.mesh as CylinderMesh
		if cyl:
			cyl.height = ray_length
		_ray_mesh.position = Vector3(0, 0, -ray_length * 0.5)
		_cursor_mesh.visible = false
		return

	var hit_dist: float = global_position.distance_to(get_collision_point())
	_ray_material.albedo_color = ray_hit_color

	# Shorten ray to hit point
	var cyl := _ray_mesh.mesh as CylinderMesh
	if cyl:
		cyl.height = hit_dist
	_ray_mesh.position = Vector3(0, 0, -hit_dist * 0.5)

	# Place cursor at hit point
	_cursor_mesh.visible = true
	_cursor_mesh.global_position = get_collision_point()

	ray_pointing_at.emit(get_collision_point(), get_collision_normal(), get_collider())


func _update_hover() -> void:
	var new_target: Node3D = null

	if is_colliding():
		var collider := get_collider()
		# Walk up to find a CADObject or any interactable group member
		new_target = _find_interactable(collider)

	if new_target != _hovered_object:
		# Unhover previous
		if _hovered_object != null:
			if _hovered_object.has_method("on_unhover"):
				_hovered_object.on_unhover()
			unhovered.emit(_hovered_object)

		_hovered_object = new_target

		# Hover new
		if _hovered_object != null:
			if _hovered_object.has_method("on_hover"):
				_hovered_object.on_hover()
			hovered.emit(_hovered_object, get_collision_point(), get_collision_normal())


func _update_grabbed_object() -> void:
	if _grabbed_object == null:
		return

	# Move grabbed object so it maintains its offset from the controller
	_grabbed_object.global_transform = global_transform * _grabbed_offset


# ─── Input handlers ──────────────────────────────────────────────────────────

func _on_trigger_pressed() -> void:
	if _hovered_object == null:
		return

	if _hovered_object.has_method("on_select"):
		_hovered_object.on_select(get_collision_point())
	selected.emit(_hovered_object, get_collision_point())

	if _controller.has_method("haptic_click"):
		_controller.haptic_click()


func _on_trigger_released() -> void:
	if _hovered_object == null:
		return

	if _hovered_object.has_method("on_deselect"):
		_hovered_object.on_deselect()
	deselected.emit(_hovered_object)


func _on_grip_pressed() -> void:
	if _hovered_object == null:
		return

	_grabbed_object = _hovered_object
	# Store the transform of the object relative to the controller
	_grabbed_offset = global_transform.inverse() * _grabbed_object.global_transform

	if _grabbed_object.has_method("on_grab"):
		_grabbed_object.on_grab()
	grabbed.emit(_grabbed_object)

	if _controller.has_method("haptic_confirm"):
		_controller.haptic_confirm()


func _on_grip_released() -> void:
	if _grabbed_object == null:
		return

	if _grabbed_object.has_method("on_release"):
		_grabbed_object.on_release()
	released.emit(_grabbed_object)

	_grabbed_object = null


# ─── Helpers ─────────────────────────────────────────────────────────────────

## Walk up the tree from a collider to find the topmost interactable ancestor.
func _find_interactable(node: Node) -> Node3D:
	var current: Node = node
	while current != null:
		if current is Node3D:
			if current.is_in_group("interactable"):
				return current as Node3D
			if current.has_method("on_hover"):
				return current as Node3D
		current = current.get_parent()
	return null


func get_hovered_object() -> Node3D:
	return _hovered_object


func get_grabbed_object() -> Node3D:
	return _grabbed_object
