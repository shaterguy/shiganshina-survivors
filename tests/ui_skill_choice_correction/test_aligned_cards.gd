extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(16): await t.process_frame
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = F.earn_offer(sim,21,24)
	var original: Dictionary = View.new().build(state)
	var before := state.duplicate(true)
	var vp := SubViewport.new()
	vp.size = Vector2i(960,432)
	t.root.add_child(vp)
	var ui := UI.new()
	vp.add_child(ui)
	ui.present(sim.snapshot(state))
	ui.present_progression(original)
	var ids := ui._growth_cards.map(func(card): return card.get_instance_id())
	for screen in [Vector2i(960,432),Vector2i(450,800),Vector2i(360,800),Vector2i(800,450),Vector2i(960,432)]:
		vp.size = screen
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		await _settle(t)
		var first: Control = ui._growth_cards[0]
		var first_title: Label = first.get_node_or_null("CardTitle")
		var first_effect: Label = first.get_node_or_null("CardEffect")
		t.check(first_title != null and first_effect != null,"UI-03 identity and benefit have distinct top-aligned layout controls")
		if first_title == null or first_effect == null: continue
		for card in ui._growth_cards:
			t.check(card.accessibility_name == card.face_text(),"UI-04 selecting button retains its visible accessible name")
			var title: Label = card.get_node("CardTitle")
			var effect: Label = card.get_node("CardEffect")
			var info: Control = ui._growth_details[ui._growth_cards.find(card)]
			t.check(absf(card.size.x-first.size.x) <= 1 and absf(card.size.y-first.size.y) <= 1,"UI-03 all offer cards have equal dimensions "+str(screen))
			t.check(title.position == first_title.position and effect.position == first_effect.position,"UI-03 title and benefit start on shared local baselines "+str(screen))
			t.check(card.get_global_rect().grow(1).encloses(title.get_global_rect()) and card.get_global_rect().grow(1).encloses(effect.get_global_rect()),"wrapped text stays inside card")
			t.check(not title.get_global_rect().intersects(info.get_global_rect()) and not effect.get_global_rect().intersects(info.get_global_rect()),"readable text never hides under i button")
			t.check(title.mouse_filter == Control.MOUSE_FILTER_IGNORE and effect.mouse_filter == Control.MOUSE_FILTER_IGNORE,"labels preserve parent selection hit target")
		var settled := ui._growth_cards.map(func(card): return card.size)
		var resizes := [0]
		var observe := func(): resizes[0] += 1
		for card in ui._growth_cards:
			card.resized.connect(observe)
			card.layout_metrics_changed.connect(observe)
			card.get_node("CardTitle").theme_changed.connect(observe)
			card.get_node("CardEffect").theme_changed.connect(observe)
		for frame in range(24):
			await t.process_frame
			t.check(settled == ui._growth_cards.map(func(card): return card.size),"UI-03 every consecutive settled frame keeps exact dimensions")
		for card in ui._growth_cards:
			card.resized.disconnect(observe)
			card.layout_metrics_changed.disconnect(observe)
			card.get_node("CardTitle").theme_changed.disconnect(observe)
			card.get_node("CardEffect").theme_changed.disconnect(observe)
		t.check(resizes[0] == 0,"UI-03 no resize, metrics or label theme callbacks oscillate after settling")
		var gap: float = ui._growth_groups[1].position.x-ui._growth_groups[0].position.x-first.size.x if ui._choices.columns == 2 else ui._growth_groups[1].position.y-ui._growth_groups[0].position.y-first.size.y
		t.check(absf(gap-10) <= 1,"UI-03 native grid keeps uniform ten pixel gap")
	# Deliberately arranged presentation-only longer text, then the original DTO.
	var arranged := original.duplicate(true)
	arranged.active_offer.offer_id += ":long_title"
	arranged.active_offer.options[0].name = "긴 이름의 입체기동 돌진 베기"
	arranged.active_offer.options[1].evolution_previews = []
	var snapshot: Dictionary = sim.snapshot(state)
	snapshot.upgrade_offer.offer_id = arranged.active_offer.offer_id
	ui.present(snapshot)
	ui.present_progression(arranged)
	await _settle(t)
	var long_title: Label = ui._growth_cards[0].get_node("CardTitle")
	t.check(long_title.text.begins_with(arranged.active_offer.options[0].name) and long_title.get_line_count() >= 1 and long_title.size.y >= long_title.get_combined_minimum_size().y and ui._growth_cards[0].get_global_rect().encloses(long_title.get_global_rect()),"long authored name remains complete")
	t.check(ui._growth_cards[0].size.y == ui._growth_cards[1].size.y and ui._growth_cards[1].size.y == ui._growth_cards[2].size.y,"mixed empty and long content remains equal height")
	var disabled_view := arranged.duplicate(true)
	disabled_view.active_offer.offer_id += ":disabled"
	disabled_view.active_offer.options[0].can_select = false
	disabled_view.active_offer.options[0].blocked_reason = "missing_weapon"
	snapshot.upgrade_offer.offer_id = disabled_view.active_offer.offer_id
	ui.present(snapshot)
	ui.present_progression(disabled_view)
	await _settle(t)
	var disabled_card: Button = ui._growth_cards[0]
	t.check(disabled_card.disabled and disabled_card.get_node("CardTitle").get_theme_color("font_color") == disabled_card.get_theme_color("font_disabled_color") and disabled_card.get_node("CardEffect").get_theme_color("font_color") == disabled_card.get_theme_color("font_disabled_color"),"UI-04 disabled card retains native disabled text contrast")
	ui.present(sim.snapshot(state))
	ui.present_progression(original)
	await _settle(t)
	t.check(ids == ui._growth_cards.map(func(card): return card.get_instance_id()),"resize and rebind reuse the same three cards")
	t.check(before == state and ui._growth_view == original,"UI-04 actual state and source DTO stay unchanged")
	vp.free()
