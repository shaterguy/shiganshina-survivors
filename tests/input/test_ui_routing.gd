extends RefCounted
func run(t) -> void:
	var root := Node.new()
	t.root.add_child(root)
	var router = load("res://game/input/input_router.gd").new()
	root.add_child(router)
	var ui = load("res://game/ui/game_ui.gd").new()
	root.add_child(ui)
	var calls: Array = []
	ui.new_run_requested.connect(func(): calls.append("start"))
	router.ui_action.connect(ui.navigate)
	await t.process_frame
	ui._buttons[0].grab_focus()
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_A
	down.pressed = true
	Input.parse_input_event(down)
	await t.process_frame
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_A
	up.pressed = false
	Input.parse_input_event(up)
	await t.process_frame
	t.check(calls.size() == 1,"one gamepad A press produces one UI accept")
	root.free()
