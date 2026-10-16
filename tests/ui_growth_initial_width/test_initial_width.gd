extends RefCounted
# Regression mutation: without pre-show horizontal preparation, native visibility
# sees the first real Korean card only at its style-minimum width.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for ignored in range(8): await t.process_frame
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var state: Dictionary = Fixture.earn_offer(sim,21,24)
	var view: Dictionary = View.new().build(state)
	var vp := SubViewport.new()
	vp.size = Vector2i(450,450)
	t.root.add_child(vp)
	var ui = UI.new()
	vp.add_child(ui)
	ui.reflow(vp.size,Rect2i(Vector2i.ZERO,vp.size))
	await _settle(t)
	var shown: Array = []
	for card in ui._growth_cards:
		card.visibility_changed.connect(func():
			if card.is_visible_in_tree() and not card.face_text().is_empty():
				shown.append({"width":card.size.x,"style_min":card.get_theme_stylebox("normal").get_minimum_size().x}))
	ui.present_progression(view)
	ui.present(sim.snapshot(state))
	await _settle(t)
	t.check(shown.size()==view.active_offer.options.size(),"first real offer observes each non-empty card as it becomes visible")
	for slot in range(shown.size()):
		var final_width: float = ui._growth_cards[slot].size.x
		t.check(final_width>shown[slot].style_min,"fixture has a valid column wider than the native style minimum")
		t.check(shown[slot].width>shown[slot].style_min,"first show uses available horizontal geometry before text becomes visible, slot "+str(slot))
		t.check(shown[slot].width>=final_width,"first-show seed reaches the usable column before native AUTO scrollbar refinement")
	vp.free()
