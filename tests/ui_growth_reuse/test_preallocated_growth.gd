extends RefCounted
# Actual GUI down/up must not retarget a recycled slot across binding changes.
# The fixed controls must already be attached, empty and hidden before any offer.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Card = preload("res://game/ui/growth_card.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _mouse(point: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = point
	e.global_position = point
	e.button_index = MOUSE_BUTTON_LEFT
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.pressed = down
	return e
func _cards(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child.get_script() == Card: result.append(child)
		result.append_array(_cards(child))
	return result
func _ids(nodes: Array) -> Array:
	return nodes.map(func(node): return node.get_instance_id())
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var state: Dictionary = Fixture.earn_offer(sim,21,24)
	var view: Dictionary = View.new().build(state)
	var vp := SubViewport.new()
	vp.size = Vector2i(800,450)
	t.root.add_child(vp)
	var ui = UI.new()
	vp.add_child(ui)
	await _settle(t)
	var prepared := _cards(ui)
	t.check(prepared.size() == 3,"startup attaches exactly three fixed growth cards before any offer")
	var prepared_ids := _ids(prepared)
	for card in prepared:
		t.check(card.is_inside_tree() and not card.is_visible_in_tree() and card.text.is_empty(),"prepared cards are attached, hidden and contain no warmed offer text")
	ui.present(sim.snapshot(state))
	ui.present_progression(view)
	ui.reflow(vp.size,Rect2i(Vector2i.ZERO,vp.size))
	await _settle(t)
	t.check(_ids(_cards(ui)) == prepared_ids,"first authored Korean offer uses the preattached cards")
	var stable_ids := _ids(ui._buttons.slice(0,6))
	var events: Array = []
	ui.upgrade_chosen.connect(func(offer,id): events.append([offer,id]))
	# Material content, reorder/removal, and authority replacement all cancel a
	# held card OR detail action. Stable nodes must never imply stale authority.
	for kind in ["new_offer","reorder","remove","effect","disabled","authority"]:
		for detail in [false,true]:
			ui.present_progression(view)
			await _settle(t)
			var old: Button = ui._buttons[1 if detail else 0]
			var point := old.get_global_rect().get_center()
			events.clear()
			vp.push_input(_mouse(point,true),true)
			t.check(old.is_pressed(),kind+": real GUI starts held action")
			var next := view.duplicate(true)
			match kind:
				"new_offer": next.active_offer.offer_id += ":next"
				"reorder": next.active_offer.options.reverse()
				"remove": next.active_offer.options = next.active_offer.options.slice(1)
				"effect": next.active_offer.options[0].effect_delta = {"damage":17.0}
				"disabled": next.active_offer.options[0].can_select = false
				"authority": ui.reset_obsolete_presentation({},false)
			ui.present_progression(next)
			await _settle(t)
			vp.push_input(_mouse(point,false),true)
			await _settle(t)
			t.check(events.is_empty() and ui._detail_id.is_empty(),kind+": stale release neither chooses nor opens replacement detail")
			t.check(_ids(_cards(ui)) == prepared_ids,kind+": cards stay attached through binding/authority replacement")
			t.check(ui._growth_view == next,kind+": all current authored data retained")
			var current: Button = ui._buttons[1 if detail else (2 if kind == "disabled" else 0)]
			var current_semantic := str(current.get_meta("semantic_id",""))
			var slot := int(ui._buttons.find(current)/2)
			t.check(ui._buttons[slot*2]._option == next.active_offer.options[slot],kind+": visible slot has the complete current option DTO")
			point = current.get_global_rect().get_center()
			vp.push_input(_mouse(point,true),true)
			await _settle(t)
			vp.push_input(_mouse(point,false),true)
			await _settle(t)
			if detail:
				t.check(ui._detail_id == "option:"+current_semantic.trim_prefix("growth_detail:"),kind+": new detail press opens only current binding")
				ui.navigate("cancel")
			else:
				t.check(events == [[next.active_offer.offer_id,current_semantic]],kind+": fresh press selects current binding exactly once")
			await _settle(t)
	# Detail gamepad accept is a synthetic pressed signal without pointer down.
	ui.present_progression(view)
	await _settle(t)
	ui._buttons[1].grab_focus()
	ui.accept_released()
	ui.navigate("accept")
	await _settle(t)
	t.check(ui._mode == "evolution_detail","gamepad accept opens reused detail action without pointer down")
	ui.navigate("accept")
	t.check(ui._mode == "evolution_detail","held accept cannot immediately activate detail Back")
	ui.accept_released()
	ui.navigate("accept")
	await _settle(t)
	t.check(ui._mode == "upgrade" and ui.focused_semantic_id() == "growth_detail:"+str(view.active_offer.options[0].option_id),"gamepad Back returns focus to same reused detail action")
	t.check(_ids(ui._buttons.slice(0,6)) == stable_ids,"detail round-trip preserves all six fixed Control identities")
	events.clear()
	ui._buttons[0].grab_focus()
	ui.navigate("accept")
	t.check(events.is_empty(),"held Back accept cannot select a growth card on return")
	ui.accept_released()
	ui.navigate("accept")
	t.check(events == [[view.active_offer.offer_id,view.active_offer.options[0].option_id]],"released and renewed gamepad accept chooses current reused card exactly once")
	# Empty/reset state cannot leave stale choices active or visible.
	ui.reset_obsolete_presentation({},false)
	await _settle(t)
	t.check(_ids(_cards(ui)) == prepared_ids,"authority reset retains only the UI-local fixed allocation")
	for card in _cards(ui):
		t.check(not card.is_visible_in_tree() and card.text.is_empty() and card._option.is_empty(),"reset clears hidden slot text, DTO and activity")
	vp.free()
