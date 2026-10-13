extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Router = preload("res://game/input/input_router.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _mouse(point: Vector2,down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = point; e.global_position = point; e.button_index = MOUSE_BUTTON_LEFT
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0; e.pressed = down
	return e
func _joy(down: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new(); e.button_index = JOY_BUTTON_A; e.pressed = down
	return e
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var state: Dictionary = Fixture.earn_offer(sim,21,24)
	var view: Dictionary = View.new().build(state)
	var vp := SubViewport.new(); vp.size = Vector2i(800,450); t.root.add_child(vp)
	var ui = UI.new(); vp.add_child(ui)
	ui.present(sim.snapshot(state)); ui.present_progression(view)
	ui.reflow(vp.size,Rect2i(Vector2i.ZERO,vp.size))
	await _settle(t)
	var events: Array = []
	ui.upgrade_chosen.connect(func(offer,id):events.append([offer,id]))
	# The separate information action is the persistent read-only focus target.
	var target: Button = ui._growth_details[0]
	target.grab_focus()
	await _settle(t)
	var point := target.get_global_rect().get_center()
	vp.push_input(_mouse(point,true),true)
	t.check(target.is_pressed(),"real GUI holds the persistent information action")
	var revised := view.duplicate(true)
	revised.target.name = "바뀐 진화 목표"
	ui.present_progression(revised)
	await _settle(t)
	vp.push_input(_mouse(point,false),true)
	await _settle(t)
	t.check(ui._detail_id.is_empty(),"old information release cannot open a materially replaced recipe")
	if not ui._detail_id.is_empty(): ui.navigate("cancel")
	# An empty progression update is an authority boundary even before the next
	# synchronous snapshot arrives; no retained button may dispatch old IDs.
	ui.present_progression(view)
	await _settle(t)
	var card: Button = ui._buttons[0]
	point = card.get_global_rect().get_center()
	vp.push_input(_mouse(point,true),true)
	t.check(card.is_pressed(),"real GUI holds card before offer removal")
	ui.present_progression({})
	vp.push_input(_mouse(point,false),true)
	await _settle(t)
	t.check(events.is_empty(),"empty progression update invalidates old held selection")
	t.check(ui._buttons.is_empty(),"empty progression has no active growth actions")
	# Actual Router + viewport gamepad delivery, including release and native
	# Button dispatch, must produce exactly one intent from each real down.
	ui.present_progression(view)
	await _settle(t)
	var router = Router.new(); vp.add_child(router); router.ui_action.connect(ui.navigate)
	ui._buttons[0].grab_focus(); ui.accept_released(); events.clear()
	vp.push_input(_joy(true),true)
	await _settle(t)
	t.check(events == [[view.active_offer.offer_id,view.active_offer.options[0].option_id]],"real gamepad A selects current fixed slot once")
	var choice: Dictionary = sim.choose_upgrade(state,view.active_offer.offer_id,view.active_offer.options[0].option_id)
	t.check(choice.get("ok",false),"next offer comes from a real accepted Core choice")
	if state.upgrade_offer.is_empty(): Fixture.drop_xp(sim,state,40,"binding_next_offer")
	var next: Dictionary = View.new().build(state)
	t.check(next.active_offer.offer_id != view.active_offer.offer_id,"real next offer identity differs")
	ui.present_progression(next)
	await _settle(t)
	vp.push_input(_joy(true),true)
	vp.push_input(_joy(false),true)
	await _settle(t)
	t.check(events.size()==1,"held gamepad A and its release do not choose the next offer")
	ui._buttons[0].grab_focus()
	vp.push_input(_joy(true),true); vp.push_input(_joy(false),true)
	await _settle(t)
	t.check(events.size()==2 and events[1]==[next.active_offer.offer_id,next.active_offer.options[0].option_id],"renewed gamepad down chooses only the real next offer")
	# A material refresh during detail reading cancels a held old Back action;
	# supply-only refresh preservation is covered by ui_growth_refresh_detail.
	ui.open_evolution_details("option:"+str(next.active_offer.options[0].option_id))
	await _settle(t)
	ui._scroll.scroll_vertical = 100000
	await _settle(t)
	var back: Button = ui._buttons[0]
	point = back.get_global_rect().get_center()
	vp.push_input(_mouse(point,true),true)
	t.check(back.is_pressed(),"real GUI holds detail Back before material replacement")
	revised = next.duplicate(true)
	revised.active_offer.options[0].description += " 새 설명"
	ui.present_progression(revised)
	await _settle(t)
	vp.push_input(_mouse(point,false),true)
	await _settle(t)
	t.check(ui._mode=="evolution_detail","old Back release does not close newly rendered material detail")
	t.check(ui._choices.get_node("GrowthDetails").text.contains("새 설명"),"material detail replacement shows complete fresh text")
	ui.accept_released(); ui.navigate("accept")
	await _settle(t)
	t.check(ui._mode=="upgrade","fresh Back action returns to current material offer")
	ui.open_evolution_details("option:"+str(revised.active_offer.options[0].option_id))
	await _settle(t)
	ui.present_progression({})
	t.check(ui._buttons.is_empty() and ui._detail_id.is_empty(),"empty progression invalidates obsolete detail actions and return identity")
	vp.free()
