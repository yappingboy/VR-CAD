## ControllerInput — attached to each XRController3D node in xr_rig.tscn
##
## Reads all controller inputs and translates them into high-level signals
## that other systems (interaction ray, wrist menu, etc.) consume.
##
## Usage:
##   In xr_rig.tscn, set `hand_side = 0` for left, `1` for right.
##
## Signals are emitted on this node. Other nodes connect to the specific
## controller they care about via get_node("LeftController") etc.
extends XRController3D

# ─── Exports ─────────────────────────────────────────────────────────────────

## 0 = left hand, 1 = right hand
@export var hand_side: int = 0

# ─── Signals ─────────────────────────────────────────────────────────────────

## Trigger (index finger)
signal trigger_pressed
signal trigger_released
signal trigger_value_changed(value: float)

## Grip (middle + ring finger squeeze)
signal grip_pressed
signal grip_released
signal grip_value_changed(value: float)

## Primary face button (A on right, X on left)
signal primary_button_pressed
signal primary_button_released

## Secondary face button (B on right, Y on left)
signal secondary_button_pressed
signal secondary_button_released

## Thumbstick
signal thumbstick_pressed
signal thumbstick_released
signal thumbstick_changed(value: Vector2)

## Menu button (left controller only)
signal menu_pressed

# ─── State ───────────────────────────────────────────────────────────────────

var trigger_value: float = 0.0
var grip_value: float = 0.0
var thumbstick_value: Vector2 = Vector2.ZERO

var _trigger_pressed: bool = false
var _grip_pressed: bool = false
var _primary_pressed: bool = false
var _secondary_pressed: bool = false
var _thumbstick_pressed: bool = false

## Thresholds for analog → digital conversion
const TRIGGER_PRESS_THRESHOLD: float = 0.7
const TRIGGER_RELEASE_THRESHOLD: float = 0.3
const GRIP_PRESS_THRESHOLD: float = 0.6
const GRIP_RELEASE_THRESHOLD: float = 0.25

# ─── Per-frame ───────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not is_active():
		return

	_update_trigger()
	_update_grip()
	_update_buttons()
	_update_thumbstick()


func _update_trigger() -> void:
	var new_val: float = get_float("trigger")
	if abs(new_val - trigger_value) > 0.01:
		trigger_value = new_val
		trigger_value_changed.emit(trigger_value)

	if not _trigger_pressed and trigger_value >= TRIGGER_PRESS_THRESHOLD:
		_trigger_pressed = true
		trigger_pressed.emit()
	elif _trigger_pressed and trigger_value <= TRIGGER_RELEASE_THRESHOLD:
		_trigger_pressed = false
		trigger_released.emit()


func _update_grip() -> void:
	var new_val: float = get_float("grip")
	if abs(new_val - grip_value) > 0.01:
		grip_value = new_val
		grip_value_changed.emit(grip_value)

	if not _grip_pressed and grip_value >= GRIP_PRESS_THRESHOLD:
		_grip_pressed = true
		grip_pressed.emit()
	elif _grip_pressed and grip_value <= GRIP_RELEASE_THRESHOLD:
		_grip_pressed = false
		grip_released.emit()


func _update_buttons() -> void:
	# Primary = A (right) / X (left)
	var primary_down: bool = is_button_pressed("ax_button")
	if primary_down != _primary_pressed:
		_primary_pressed = primary_down
		if _primary_pressed:
			primary_button_pressed.emit()
		else:
			primary_button_released.emit()

	# Secondary = B (right) / Y (left)
	var secondary_down: bool = is_button_pressed("by_button")
	if secondary_down != _secondary_pressed:
		_secondary_pressed = secondary_down
		if _secondary_pressed:
			secondary_button_pressed.emit()
		else:
			secondary_button_released.emit()

	# Thumbstick click
	var stick_click: bool = is_button_pressed("primary_click")
	if stick_click != _thumbstick_pressed:
		_thumbstick_pressed = stick_click
		if _thumbstick_pressed:
			thumbstick_pressed.emit()
		else:
			thumbstick_released.emit()

	# Menu button (only on left controller)
	if hand_side == 0 and is_button_pressed("menu_button"):
		menu_pressed.emit()


func _update_thumbstick() -> void:
	var new_val: Vector2 = get_vector2("primary")
	if new_val.distance_to(thumbstick_value) > 0.02:
		thumbstick_value = new_val
		thumbstick_changed.emit(thumbstick_value)


# ─── Haptics ─────────────────────────────────────────────────────────────────

## Trigger a haptic pulse on this controller.
##   duration  — seconds (e.g. 0.1)
##   frequency — Hz (e.g. 100.0); 0 = default
##   amplitude — 0.0 to 1.0
func haptic_pulse(duration: float = 0.05, frequency: float = 0.0, amplitude: float = 0.5) -> void:
	trigger_haptic_pulse("haptic", frequency, amplitude, duration, 0.0)


## Short click feel
func haptic_click() -> void:
	haptic_pulse(0.02, 200.0, 0.6)


## Soft confirmation buzz
func haptic_confirm() -> void:
	haptic_pulse(0.08, 100.0, 0.4)


## Error / rejection buzz
func haptic_error() -> void:
	haptic_pulse(0.15, 50.0, 0.8)


# ─── Helpers ─────────────────────────────────────────────────────────────────

func is_left_hand() -> bool:
	return hand_side == 0


func is_right_hand() -> bool:
	return hand_side == 1


## Returns the tip position in world space (aim pose forward, ~30cm out)
func get_ray_origin() -> Vector3:
	return global_position


func get_ray_direction() -> Vector3:
	return -global_transform.basis.z
