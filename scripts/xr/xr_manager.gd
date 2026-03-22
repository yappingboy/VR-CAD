## XRManager — attached to the root Node3D in main.tscn
##
## Responsibilities:
##   • Initialize the OpenXR interface
##   • Enable Meta Quest passthrough (blend mode + vendor API)
##   • Set up the scene environment for transparency
##   • Provide a global access point for the XR camera
##   • Emit signals when XR session state changes
extends Node3D

signal xr_started
signal xr_stopped
signal xr_init_failed

## Convenience: other scripts can call XRManager.get_xr_camera()
var xr_camera: XRCamera3D
var _xr_interface: XRInterface
var _is_xr_active: bool = false


func _ready() -> void:
	# Defer so the scene tree is fully built before we start XR
	call_deferred("_initialize_xr")


func _initialize_xr() -> void:
	_xr_interface = XRServer.find_interface("OpenXR")

	if _xr_interface == null:
		push_warning("VR-CAD: OpenXR interface not found. Running in desktop fallback mode.")
		_setup_desktop_fallback()
		xr_init_failed.emit()
		return

	if not _xr_interface.initialize():
		push_error("VR-CAD: OpenXR failed to initialize.")
		_setup_desktop_fallback()
		xr_init_failed.emit()
		return

	# Tell this viewport to use XR rendering
	get_viewport().use_xr = true

	_setup_passthrough_environment()
	_connect_xr_signals()

	# Grab the camera reference for other systems to use
	xr_camera = _find_xr_camera()

	_is_xr_active = true
	xr_started.emit()
	print("VR-CAD: XR started successfully.")


# ─── Passthrough ────────────────────────────────────────────────────────────

func _setup_passthrough_environment() -> void:
	# Method 1: Use the Meta vendors plugin if available (preferred)
	if _try_meta_passthrough_api():
		print("VR-CAD: Passthrough enabled via Meta vendor API.")
		return

	# Method 2: Rely on project.godot environment_blend_mode = 2 (AlphaBlend).
	# The XR compositor blends the real world with rendered content automatically.
	# We just need to make sure the scene background is transparent.
	_set_transparent_background()
	print("VR-CAD: Passthrough enabled via AlphaBlend blend mode.")


func _try_meta_passthrough_api() -> bool:
	# The Godot OpenXR Vendors plugin registers this singleton when available.
	if not Engine.has_singleton("OpenXRFbPassthroughExtensionWrapper"):
		return false

	var passthrough = Engine.get_singleton("OpenXRFbPassthroughExtensionWrapper")
	if passthrough == null:
		return false

	passthrough.start_passthrough()
	return true


func _set_transparent_background() -> void:
	var world_env: WorldEnvironment = get_node_or_null("WorldEnvironment")
	if world_env == null or world_env.environment == null:
		return

	var env: Environment = world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)


# ─── XR Signals ──────────────────────────────────────────────────────────────

func _connect_xr_signals() -> void:
	if _xr_interface.has_signal("session_begun"):
		_xr_interface.session_begun.connect(_on_session_begun)
	if _xr_interface.has_signal("session_stopping"):
		_xr_interface.session_stopping.connect(_on_session_stopping)
	if _xr_interface.has_signal("session_focussed"):
		_xr_interface.session_focussed.connect(_on_session_focussed)
	if _xr_interface.has_signal("session_visible"):
		_xr_interface.session_visible.connect(_on_session_visible)


func _on_session_begun() -> void:
	print("VR-CAD: XR session begun.")
	xr_started.emit()


func _on_session_stopping() -> void:
	print("VR-CAD: XR session stopping.")
	_is_xr_active = false
	xr_stopped.emit()


func _on_session_focussed() -> void:
	print("VR-CAD: XR session focused (app is in foreground).")


func _on_session_visible() -> void:
	print("VR-CAD: XR session visible (app in background/overlay).")


# ─── Desktop Fallback ────────────────────────────────────────────────────────

func _setup_desktop_fallback() -> void:
	# When running on desktop without a headset, set up a basic 3D view
	# so the scene is still usable for development/testing.
	print("VR-CAD: Desktop fallback active. Use WASD + mouse to look around.")
	var cam: Camera3D = Camera3D.new()
	cam.name = "DesktopCamera"
	cam.position = Vector3(0, 1.6, 2)
	add_child(cam)
	cam.make_current()


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _find_xr_camera() -> XRCamera3D:
	return _find_node_of_type(self, "XRCamera3D") as XRCamera3D


func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result := _find_node_of_type(child, type_name)
		if result:
			return result
	return null


func is_xr_active() -> bool:
	return _is_xr_active


func get_xr_camera() -> XRCamera3D:
	return xr_camera
