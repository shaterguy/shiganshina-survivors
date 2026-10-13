extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	var ui := UI.new()
	t.root.add_child(ui)
	ui.pause_changed.connect(func(enabled):
		sim.set_pause(state,"user",enabled)
		ui.present(sim.snapshot(state)))
	ui.present(sim.snapshot(state))
	ui.present_progression(View.new().build(state))
	var hud: Control = ui._owned_hud
	for screen in [Vector2i(360,800),Vector2i(450,800),Vector2i(800,450),Vector2i(640,360)]:
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		await _settle(t)
		t.check(hud.slot_controls().size() == 8,"sparse HUD retains the fixed four attack and four support slots")
		for index in hud.slot_controls().size():
			var slot: Control = hud.slot_controls()[index]
			var name: Label = slot.get_node("Name")
			var status: Label = slot.get_node("Status")
			var icon: TextureRect = slot.get_node("Icon")
			t.check(name.text.is_empty() or not name.is_visible_in_tree(),"HUD identity is an icon rather than a repeated tiny name row")
			if str(slot.get_meta("item_id","")).is_empty():
				t.check(name.text.is_empty() and status.text.is_empty() and icon.texture == null and slot.modulate.a < 1,"empty slot is a faint unlabelled placeholder without a fake skill icon")
			else:
				t.check(status.text == "1/6" and icon.texture != null and icon.size.x >= 24 and icon.size.y >= 24 and icon.is_visible_in_tree() and status.is_visible_in_tree(),"owned attack has a visibly readable identity icon and exact current/max level")
				t.check(slot.tooltip_text.contains("쌍검 전방 베기") and slot.tooltip_text.contains("1/6"),"sparse acquired icon retains its full real skill name and level in information")
				t.check(hud.get_global_rect().encloses(icon.get_global_rect()) and hud.get_global_rect().encloses(status.get_global_rect()),"sparse HUD icon and numeric level remain inside native safe bounds")
		var target: Label = hud.get_node("TargetRequirements")
		t.check(not target.text.contains("보유 기술에서 조건 보기") and target.text.split("\n").size() <= 1,"HUD target has no repeated reader instruction or multi-line explanation")
	var tick: int = state.active_tick
	hud.get_node("OwnedSkillsEntry").pressed.emit()
	await _settle(t)
	t.check("user" in state.pause_reasons and ui._mode == "owned_skills","clicking sparse HUD still establishes actual Core pause before its full skill reader")
	F.step(sim,state,Vector2.ZERO)
	t.check(state.active_tick == tick,"sparse HUD information never advances paused combat")
	ui._buttons[0].grab_focus()
	ui.accept_released()
	ui.navigate("accept")
	await _settle(t)
	t.check(ui._mode == "evolution_detail" and ui._detail_id == "owned:blade_slash","controller A still reaches the exact acquired skill from the sparse HUD reader")
	var detail_text := ""
	for node in ui._choices.get_children():
		if node.has_method("display_text"): detail_text += node.display_text()
	t.check(detail_text.contains("쌍검 전방 베기") and detail_text.contains("타격당 피해"),"sparse HUD reader exposes the full actual acquired name and measured effect")
	ui.navigate("cancel")
	await _settle(t)
	t.check(ui._mode == "owned_skills" and "user" in state.pause_reasons,"B returns to the owned reader and preserves Core pause")
	ui.free()
