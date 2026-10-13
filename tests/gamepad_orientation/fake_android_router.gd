extends "res://game/input/input_router.gd"
# Only platform boundaries are fake. _ready, connection policy and input routing
# execute the production router; this cannot certify an Android screen rotation.
var startup_devices: Array[int] = []
var orientation_supported := true
var current_orientation := DisplayServer.SCREEN_SENSOR
var orientation_reads := 0
var orientation_requests: Array[int] = []
func _connected_joypads() -> Array[int]:
	return startup_devices.duplicate()
func _supports_controller_orientation() -> bool:
	return orientation_supported
func _read_screen_orientation() -> int:
	orientation_reads += 1
	return current_orientation
func _write_screen_orientation(value: int) -> void:
	orientation_requests.append(value)
	current_orientation = value
