extends RefCounted
func run(t) -> void:
	var path := "res://game/input/input_router.gd"
	t.check(FileAccess.file_exists(path), "InputRouter exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	if script == null or not script.can_instantiate():
		t.check(false, "InputRouter compiles")
		return
	var router = script.new()
	var event := InputEventJoypadMotion.new()
	event.device = 1
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = 0.19
	router.handle_event(event)
	t.check(router.sample_move() == Vector2.ZERO, "stick noise is ignored")
	event.axis_value = 0.21
	router.handle_event(event)
	t.check(router.sample_move().x > 0, "stick beyond deadzone moves")
	router.set_touch_vector(Vector2(1,1))
	t.check(router.sample_move().length() <= 1.00001, "diagonal normalized")
	router.clear_transient_input()
	t.check(router.sample_move() == Vector2.ZERO, "rotation clears movement")
	router.set_active(false)
	event.axis_value = 1.0
	router.handle_event(event)
	t.check(router.sample_move() == Vector2.ZERO, "unfocused input ignored")
	router.free()
	var dpad = script.new()
	var button := InputEventJoypadButton.new()
	button.device = 2
	button.button_index = JOY_BUTTON_DPAD_LEFT
	button.pressed = true
	dpad.handle_event(button)
	button.button_index = JOY_BUTTON_DPAD_RIGHT
	dpad.handle_event(button)
	t.check(dpad.sample_move() == Vector2.ZERO,"opposite D-pad inputs cancel")
	button.pressed = false
	dpad.handle_event(button)
	t.check(dpad.sample_move().x == -1,"releasing right preserves held left")
	dpad.free()
