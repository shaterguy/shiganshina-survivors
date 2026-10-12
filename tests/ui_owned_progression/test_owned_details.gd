extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	var app = Support.new().make(t).app
	app.start_run(42)
	t.check(app.ui.has_method("open_owned_skills"),"combat owned skills has an explicit safe entry")
	if not app.ui.has_method("open_owned_skills"):
		app.free()
		return
	app.input_router.set_touch_vector(Vector2.RIGHT)
	var tick: int = app.state.active_tick
	app.ui.get_node("ProgressionHUD/OwnedSkillsEntry").pressed.emit()
	t.check("user" in app.state.pause_reasons and app.ui._mode == "owned_skills","HUD entry establishes actual Core user pause before opening details")
	app.advance_frame(1.0)
	t.check(app.state.active_tick == tick and app.input_router.sample_move() == Vector2.ZERO,"HUD reader freezes simulation and clears held movement")
	var row: Button = app.ui._buttons[0]
	row.grab_focus()
	var id: String = app.ui.focused_semantic_id()
	app.ui.navigate("accept")
	t.check(app.ui._mode == "evolution_detail","owned row reuses existing read-only detail mode")
	var content: String = app.ui._choices.get_child(3).display_text() if app.ui._choices.get_child_count() > 3 and app.ui._choices.get_child(3).has_method("display_text") else ""
	for child in app.ui._choices.get_children():
		if child.has_method("display_text"): content = child.display_text()
	t.check(content.contains("Lv 1/5") and content.contains("전방") and content.contains("선행조건"),"owned detail shows current level, real attack and recipe conditions")
	app.ui.navigate("cancel")
	t.check(app.ui._mode == "owned_skills" and app.ui.focused_semantic_id() == id,"B returns one step to originating owned item")
	app.ui.navigate("accept")
	t.check(app.ui._mode == "owned_skills","held A cannot reopen after the modal transition")
	app.ui.accept_released()
	app.ui.navigate("accept")
	t.check(app.ui._mode == "evolution_detail","fresh A can reopen the same owned detail")
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	app.ui.reflow(Vector2i(320,568),Rect2i(8,8,304,552))
	app.ui.navigate("cancel")
	app.ui.navigate("cancel")
	t.check(app.ui._mode == "pause" and "user" in app.state.pause_reasons and "background" in app.state.pause_reasons,"owned close and rotation never clear user or background pause")
	app.advance_frame(1.0)
	t.check(app.state.active_tick == tick,"closing details does not implicitly resume combat")
	app.request_resume()
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == tick+1,"combat resumes only after existing explicit continue")
	app.free()
