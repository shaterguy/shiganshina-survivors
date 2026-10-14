extends RefCounted
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _button(ui, id: String):
	for button in ui._buttons:
		if button.get_meta("semantic_id","") == id: return button
	return null
func _mouse(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.device = -1
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	return event
func _tap(t, viewport, ui, id: String) -> void:
	var point: Vector2 = _button(ui,id).get_global_rect().get_center()
	viewport.push_input(_mouse(point,true),true)
	viewport.push_input(_mouse(point,false),true)
	await _settle(t)
func run(t) -> void:
	var viewport := SubViewport.new()
	t.root.add_child(viewport)
	var ui := UI.new()
	viewport.add_child(ui)
	ui.set_checkpoint_available(true,"test:1")
	for size in [Vector2i(800,450),Vector2i(360,800),Vector2i(640,360)]:
		viewport.size = size
		ui.reflow(size,Rect2i(Vector2i.ZERO,size))
		for mode in ["scenario_select","scenario_briefing","new_run_confirm"]:
			ui.open_scenario_selection()
			if mode != "scenario_select": ui.open_scenario_briefing("chapter_01_shiganshina")
			if mode == "new_run_confirm": ui._request_new_run()
			await _settle(t)
			t.check(ui._mode == mode,"navigation exposes requested page "+mode)
			t.check(Rect2(Vector2.ZERO,Vector2(size)).grow(1).encloses(ui._panel.get_global_rect()),"navigation panel stays inside "+str(size)+" "+mode)
			for button in ui._buttons:
				t.check(button.size.y >= 48 and ui._scroll.get_global_rect().grow(1).encloses(button.get_global_rect()),"complete touch action is visible "+button.text+" "+str(size))
	viewport.size = Vector2i(800,450)
	ui.reflow(viewport.size,Rect2i(Vector2i.ZERO,viewport.size))
	ui.finish_new_run_navigation()
	ui.set_checkpoint_available(false)
	ui.present({})
	var starts: Array = []
	ui.new_run_requested.connect(func(): starts.append(true))
	await _settle(t)
	await _tap(t,viewport,ui,"new_run_open")
	t.check(ui._mode == "scenario_select" and starts.is_empty(),"actual touch on main only opens selection")
	await _tap(t,viewport,ui,"scenario:chapter_01_shiganshina")
	t.check(ui._mode == "scenario_briefing" and starts.is_empty(),"actual touch selects the scenario without starting")
	await _tap(t,viewport,ui,"scenario_start")
	t.check(starts.size() == 1,"actual final touch starts once")
	ui.finish_new_run_navigation()
	ui.open_scenario_selection()
	ui._restore_focus("scenario:chapter_01_shiganshina")
	ui.navigate("accept")
	ui.navigate("accept")
	t.check(ui._mode == "scenario_briefing" and starts.size() == 1,"held pad accept cannot skip selection and briefing")
	ui.accept_released()
	ui.navigate("accept")
	t.check(starts.size() == 2,"released then pressed pad accept starts the chosen scenario")
	viewport.free()
