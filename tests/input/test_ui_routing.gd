extends RefCounted
func _a(t, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = pressed
	Input.parse_input_event(event)
	await t.process_frame
func _focus(ui, semantic: String) -> void:
	for button in ui._buttons:
		if button.get_meta("semantic_id","") == semantic: button.grab_focus(); return
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
	_focus(ui,"new_run_open")
	await _a(t,true)
	t.check(ui._mode == "scenario_select" and calls.is_empty(),"first real A opens scenario selection without prematurely starting")
	await _a(t,true)
	t.check(ui._mode == "scenario_select" and calls.is_empty(),"held A cannot advance a second navigation step")
	await _a(t,false)
	_focus(ui,"scenario:chapter_01_shiganshina")
	await _a(t,true)
	t.check(ui._mode == "scenario_briefing" and calls.is_empty(),"next released A opens the actual selected scenario briefing")
	await _a(t,false)
	_focus(ui,"scenario_start")
	await _a(t,true)
	await _a(t,true)
	await _a(t,false)
	t.check(calls == ["start"],"one final gamepad A press produces exactly one new-run request")
	root.free()
