extends RefCounted
# Real Core focus mutation + the controller's keyed view refresh, delivered
# between actual viewport pointer press/release events. Replacing a focused
# card mid-press must fail; preserving changed offers must also fail.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Router = preload("res://game/input/input_router.gd")
class FocusRefresh extends Node:
	var simulation
	var state: Dictionary
	var ui
	var router
	var view_key := ""
	var last_source: Dictionary = {}
	var choices: Array = []
	func _ready() -> void:
		ui = UI.new()
		add_child(ui)
		ui.present(simulation.snapshot(state))
		router = Router.new()
		add_child(router)
		router.ui_action.connect(ui.navigate)
		ui.upgrade_focus_changed.connect(func(id): simulation.set_offer_focus(state,id))
		ui.upgrade_chosen.connect(func(offer,id): choices.append([offer,id]))
		ui.reflow(Vector2i(800,450),Rect2i(0,0,800,450))
	func _process(_delta: float) -> void:
		var key := "%d:%s" % [state.view_revision,state.upgrade_offer.selected_option_id]
		if key != view_key:
			view_key = key
			last_source = View.new().build(state)
			ui.present_progression(last_source)
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _mouse(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	return event
func _button(ui, id: String):
	for button in ui._buttons:
		if str(button.get_meta("semantic_id","")) == id: return button
	return null
func run(t) -> void:
	var simulation = Fixture.simulation(t)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800,450)
	t.root.add_child(viewport)
	var bridge := FocusRefresh.new()
	bridge.simulation = simulation
	bridge.state = Fixture.earn_offer(simulation,21,24)
	viewport.add_child(bridge)
	await _settle(t)
	var option_id: String = bridge.state.upgrade_offer.options[2].option_id
	var button = _button(bridge.ui,option_id)
	var instance_id: int = button.get_instance_id()
	var control_ids: Array = bridge.ui._buttons.map(func(control): return control.get_instance_id())
	var center: Vector2 = button.get_global_rect().get_center()
	var before := bridge.state.duplicate(true)
	var original_source: Dictionary = bridge.last_source
	var source_before := original_source.duplicate(true)
	viewport.push_input(_mouse(center,true),true)
	t.check(bridge.state.upgrade_offer.selected_option_id == option_id,"pointer down reaches a previously unfocused third growth card through real GUI focus")
	t.check(bridge.state.view_revision > before.view_revision,"real Core focus updates the view revision before pointer release")
	await _settle(t)
	t.check(_button(bridge.ui,option_id).get_instance_id() == instance_id,"focus-only controller refresh preserves the pressed Control instance")
	t.check(bridge.ui._buttons.map(func(control): return control.get_instance_id()) == control_ids,"focus-only refresh preserves every growth action and recipe Control instance")
	var expected := before.duplicate(true)
	expected.upgrade_offer.selected_option_id = option_id
	expected.view_revision = bridge.state.view_revision
	t.check(bridge.state == expected,"focus refresh changes only Core's explicit focus/revision fields")
	t.check(bridge.ui._growth_view == bridge.last_source,"preserved controls still retain the latest exact progression view")
	t.check(original_source == source_before,"actual prior source DTO is not aliased or mutated by focus refresh")
	t.check(bridge.last_source == View.new().build(bridge.state),"actual refreshed source DTO is unchanged from Core-derived presentation")
	viewport.push_input(_mouse(center,false),true)
	await _settle(t)
	t.check(bridge.choices == [[before.upgrade_offer.offer_id,option_id]],"first down/frame/up on an unfocused card emits one selection without requiring a second tap")
	# Additional pointer presses do not require reconstruction after focus-only
	# source changes, and the input DTO must never become UI-owned mutable data.
	var submitted := bridge.last_source.duplicate(true)
	var submitted_before := submitted.duplicate(true)
	bridge.ui.present_progression(submitted)
	t.check(submitted == submitted_before,"same-view presentation leaves its caller-owned DTO immutable")
	submitted.active_offer.options[0].description = "caller mutation after presentation"
	t.check(bridge.ui._growth_view == submitted_before,"retained view is a deep copy independent of later caller mutation")
	bridge.set_process(false)
	await _content_changes(t,bridge,viewport)
	viewport.free()
func _content_changes(t,bridge,viewport) -> void:
	var baseline: Dictionary = bridge.last_source.duplicate(true)
	var cases: Array[Dictionary] = []
	var replacement := baseline.duplicate(true)
	replacement.active_offer.offer_id += ":replacement"
	cases.append(replacement)
	replacement = baseline.duplicate(true)
	replacement.active_offer.options[0].description += " changed"
	cases.append(replacement)
	replacement = baseline.duplicate(true)
	replacement.active_offer.options[0].effect_delta = {"text":"new benefit"}
	cases.append(replacement)
	replacement = baseline.duplicate(true)
	replacement.active_offer.options[0].can_select = false
	replacement.active_offer.options[0].blocked_reason = "passive_slots"
	cases.append(replacement)
	replacement = baseline.duplicate(true)
	replacement.target.requirements[0].current += 1
	cases.append(replacement)
	replacement = baseline.duplicate(true)
	replacement.slots.equipment.used += 1
	cases.append(replacement)
	for updated in cases:
		bridge.ui.present_progression(baseline)
		await _settle(t)
		var old: Button = bridge.ui._buttons[0]
		var old_id := old.get_instance_id()
		bridge.ui.present_progression(updated)
		t.check(bridge.ui._buttons[0].get_instance_id() == old_id,"material changes reuse fixed controls while updating their complete binding")
		t.check(bridge.ui._growth_view == updated,"material replacement retains all newly supplied details")
		await _settle(t)
	# A genuinely changed offer, or a removed option within the same offer, must
	# cancel the old press rather than dispatch either old or new IDs on release.
	for remove_option in [false,true]:
		bridge.ui.present_progression(baseline)
		await _settle(t)
		var old_offer: String = baseline.active_offer.offer_id
		var target: Button = bridge.ui._buttons[0]
		var point := target.get_global_rect().get_center()
		bridge.choices.clear()
		viewport.push_input(_mouse(point,true),true)
		replacement = baseline.duplicate(true)
		if remove_option:
			replacement.active_offer.options = replacement.active_offer.options.slice(1)
			replacement.active_offer.selected_option_id = replacement.active_offer.options[0].option_id
		else:
			replacement.active_offer.offer_id = old_offer+":next"
		bridge.ui.present_progression(replacement)
		await _settle(t)
		viewport.push_input(_mouse(point,false),true)
		await _settle(t)
		t.check(bridge.choices.is_empty(),"release from removed offer/option cannot dispatch old or replacement IDs")
		var current: Button = bridge.ui._buttons[0]
		point = current.get_global_rect().get_center()
		viewport.push_input(_mouse(point,true),true)
		await _settle(t)
		viewport.push_input(_mouse(point,false),true)
		await _settle(t)
		t.check(bridge.choices == [[replacement.active_offer.offer_id,replacement.active_offer.options[0].option_id]],"new press after replacement chooses only current offer and option IDs")
