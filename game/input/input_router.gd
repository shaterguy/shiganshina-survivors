class_name InputRouter
extends Node
signal ui_action(action: String)
signal active_controller_lost
signal input_hint_changed(kind: String)
var deadzone := 0.20
var active_device := -1
var input_kind := "touch"
var _enabled := true
var _stick := Vector2.ZERO
var _touch := Vector2.ZERO
var _dpad := Vector2.ZERO
var _keys := Vector2.ZERO
var _pressed_keys := {}
var _pressed_dpad := {}
var _accept_armed := true
var _menu_direction := ""
var _repeat_remaining := 0.0
func _ready() -> void:
	Input.joy_connection_changed.connect(_on_connection)
func _input(event: InputEvent) -> void:
	handle_event(event)
func handle_event(event: InputEvent) -> void:
	if not _enabled: return
	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_LEFT_X: _stick.x = event.axis_value
		elif event.axis == JOY_AXIS_LEFT_Y: _stick.y = event.axis_value
		else: return
		if _stick.length() > deadzone:
			active_device = event.device
			_touch = Vector2.ZERO
			_hint("gamepad")
	elif event is InputEventJoypadButton:
		active_device = event.device
		var pressed: bool = event.pressed
		match event.button_index:
			JOY_BUTTON_A:
				if pressed and _accept_armed: ui_action.emit("accept")
				_accept_armed = not pressed
			JOY_BUTTON_B:
				if pressed: ui_action.emit("cancel")
			JOY_BUTTON_START:
				if pressed: ui_action.emit("pause")
			JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN:
				_pressed_dpad[event.button_index] = pressed
				_dpad = Vector2(int(_pressed_dpad.get(JOY_BUTTON_DPAD_RIGHT,false))-int(_pressed_dpad.get(JOY_BUTTON_DPAD_LEFT,false)),int(_pressed_dpad.get(JOY_BUTTON_DPAD_DOWN,false))-int(_pressed_dpad.get(JOY_BUTTON_DPAD_UP,false)))
		if pressed:
			_hint("gamepad")
			_touch = Vector2.ZERO
	elif event is InputEventKey and not event.echo:
		_pressed_keys[event.physical_keycode] = event.pressed
		_keys = Vector2(int(_down(KEY_D) or _down(KEY_RIGHT)) - int(_down(KEY_A) or _down(KEY_LEFT)), int(_down(KEY_S) or _down(KEY_DOWN)) - int(_down(KEY_W) or _down(KEY_UP)))
		if event.pressed:
			if event.keycode in [KEY_ENTER, KEY_SPACE]: ui_action.emit("accept")
			elif event.keycode == KEY_ESCAPE: ui_action.emit("cancel")
			elif event.keycode == KEY_P: ui_action.emit("pause")
func _down(key: int) -> bool:
	return _pressed_keys.get(key, false)
func _process(delta: float) -> void:
	if not _enabled: return
	var vector := _filtered_stick() + _dpad + _keys
	var direction := ""
	if vector.length() >= 0.45:
		if absf(vector.x) > absf(vector.y): direction = "right" if vector.x > 0 else "left"
		else: direction = "down" if vector.y > 0 else "up"
	if direction != _menu_direction:
		_menu_direction = direction
		_repeat_remaining = 0.30
		if not direction.is_empty(): ui_action.emit(direction)
	elif not direction.is_empty():
		_repeat_remaining -= delta
		if _repeat_remaining <= 0:
			ui_action.emit(direction)
			_repeat_remaining += 0.10
func _filtered_stick() -> Vector2:
	var length := _stick.length()
	if length <= deadzone: return Vector2.ZERO
	return _stick.normalized() * clampf((length-deadzone)/(1.0-deadzone), 0, 1)
func sample_move() -> Vector2:
	if not _enabled: return Vector2.ZERO
	if not _touch.is_zero_approx(): return _touch.limit_length()
	return (_filtered_stick() + _dpad + _keys).limit_length()
func set_touch_vector(vector: Vector2) -> void:
	if not _enabled: return
	_touch = vector.limit_length()
	if not vector.is_zero_approx(): _hint("touch")
func clear_transient_input() -> void:
	_stick = Vector2.ZERO
	_touch = Vector2.ZERO
	_dpad = Vector2.ZERO
	_keys = Vector2.ZERO
	_pressed_keys.clear()
	_pressed_dpad.clear()
	_menu_direction = ""
func set_active(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		clear_transient_input()
		_accept_armed = false
func _on_connection(device: int, connected: bool) -> void:
	if connected:
		_accept_armed = false
	elif device == active_device:
		clear_transient_input()
		_accept_armed = false
		active_device = -1
		active_controller_lost.emit()
func _hint(kind: String) -> void:
	if input_kind != kind:
		input_kind = kind
		input_hint_changed.emit(kind)
