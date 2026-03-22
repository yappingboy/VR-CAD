## XRManager — attached to the root Node3D in main.tscn
##
## Handles WebXR session lifecycle for browser deployment.
## On page load it shows an "Enter VR" overlay; the browser requires a user
## gesture before a WebXR session may be created.
##
## When WebXR is not available (desktop browser, no headset) the script falls
## back to a plain Camera3D so the scene is still viewable.
extends Node3D

signal xr_started
signal xr_stopped
signal xr_init_failed

## Convenience: other scripts can call XRManager.get_xr_camera()
var xr_camera: XRCamera3D

var _xr_interface: WebXRInterface
var _is_xr_active: bool = false

# Landing-screen overlay nodes
var _overlay_layer: CanvasLayer
var _enter_btn: Button
var _status_label: Label


func _ready() -> void:
	call_deferred("_initialize_webxr")


func _initialize_webxr() -> void:
	_xr_interface = XRServer.find_interface("WebXR") as WebXRInterface

	if _xr_interface == null:
		push_warning("VR-CAD: WebXR interface not found — running desktop fallback.")
		_setup_desktop_fallback()
		xr_init_failed.emit()
		return

	# Configure before the user triggers initialise()
	_xr_interface.session_mode = "immersive-vr"
	_xr_interface.required_features = "local-floor"
	_xr_interface.optional_features = "bounded-floor,hand-tracking"
	_xr_interface.requested_reference_space_types = "bounded-floor,local-floor,local"

	_xr_interface.session_started.connect(_on_session_started)
	_xr_interface.session_ended.connect(_on_session_ended)
	_xr_interface.session_failed.connect(_on_session_failed)

	_show_overlay()


# ─── Browser Landing Overlay ──────────────────────────────────────────────────

func _show_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10
	add_child(_overlay_layer)

	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.05, 0.12, 0.92)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left  = -180
	vbox.offset_right =  180
	vbox.offset_top   = -100
	vbox.offset_bottom =  100
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	_overlay_layer.add_child(vbox)

	var title := Label.new()
	title.text = "VR-CAD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	_enter_btn = Button.new()
	_enter_btn.text = "Enter VR"
	_enter_btn.custom_minimum_size = Vector2(220, 56)
	_enter_btn.pressed.connect(_on_enter_vr_pressed)
	vbox.add_child(_enter_btn)

	_status_label = Label.new()
	_status_label.text = "Requires Quest Browser, Chrome, or Edge with a WebXR headset"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.custom_minimum_size = Vector2(340, 0)
	vbox.add_child(_status_label)


func _hide_overlay() -> void:
	if _overlay_layer:
		_overlay_layer.queue_free()
		_overlay_layer = null
		_enter_btn = null
		_status_label = null


func _on_enter_vr_pressed() -> void:
	if _enter_btn:
		_enter_btn.disabled = true
	if _status_label:
		_status_label.text = "Starting VR session…"
	# initialize() triggers the browser's WebXR permission prompt.
	# The result arrives asynchronously via session_started / session_failed.
	if not _xr_interface.initialize():
		if _status_label:
			_status_label.text = "Could not start WebXR — check browser permissions."
		if _enter_btn:
			_enter_btn.disabled = false
		xr_init_failed.emit()


# ─── Session Lifecycle ────────────────────────────────────────────────────────

func _on_session_started() -> void:
	get_viewport().use_xr = true
	xr_camera = _find_xr_camera()
	_is_xr_active = true
	_hide_overlay()
	xr_started.emit()
	print("VR-CAD: WebXR session started.")


func _on_session_ended() -> void:
	get_viewport().use_xr = false
	_is_xr_active = false
	# Re-show overlay so the user can re-enter without a page reload
	_show_overlay()
	xr_stopped.emit()
	print("VR-CAD: WebXR session ended.")


func _on_session_failed(message: String) -> void:
	push_error("VR-CAD: WebXR session failed — " + message)
	if _status_label:
		_status_label.text = "Error: " + message
	if _enter_btn:
		_enter_btn.disabled = false
	xr_init_failed.emit()


# ─── Desktop Fallback ─────────────────────────────────────────────────────────

func _setup_desktop_fallback() -> void:
	print("VR-CAD: Desktop fallback active. No VR headset detected.")
	var cam := Camera3D.new()
	cam.name = "DesktopCamera"
	cam.position = Vector3(0, 1.6, 2)
	add_child(cam)
	cam.make_current()


# ─── Helpers ──────────────────────────────────────────────────────────────────

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
