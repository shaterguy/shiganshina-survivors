extends RefCounted
# Real Core offer -> ProgressionView -> live Control geometry. A full-height
# button (or focus auto-scroll clipping its top) must fail these checks.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Card = preload("res://game/ui/growth_card.gd")
const SHORT_STATS := {"damage_multiplier":"피해","cooldown_multiplier":"간격","move_multiplier":"이동","max_hp":"체력","regen_per_second":"회복/초","pickup_radius":"수집 반경","range_multiplier":"공격 범위","armor":"피해 감소"}
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func _button(ui, id: String):
	for button in ui._buttons:
		if str(button.get_meta("semantic_id","")) == id: return button
	return null
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var state := Fixture.earn_offer(sim,21,24)
	var view := View.new().build(state)
	t.check(not view.get("active_offer",{}).is_empty(),"readability fixture uses an actual current Core growth offer")
	var before := state.duplicate(true)
	var ui := UI.new()
	t.root.add_child(ui)
	ui.present(sim.snapshot(state))
	ui.present_progression(view)
	var selected: Array = []
	ui.upgrade_chosen.connect(func(offer,option): selected.append([offer,option]))
	for screen in [Vector2i(800,450),Vector2i(450,800),Vector2i(360,800)]:
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		await _settle(t)
		for option in view.active_offer.options:
			var card = _button(ui,option.option_id)
			t.check(card != null,"each offered option retains a semantic selection button")
			if card == null: continue
			card.grab_focus()
			await _settle(t)
			var viewport: Rect2 = ui._scroll.get_global_rect()
			t.check(viewport.grow(1).encloses(card.get_global_rect()),"%s selected card is fully visible including name and choice affordance: %s"%[str(screen),option.option_id])
			t.check(card.face_text().begins_with(option.name),"card begins with its real name")
			t.check(not ui._subtitle.text.contains("터치/A") and not ui._subtitle.text.contains("i 상세") and not card.face_text().contains("A · 선택"),"readable identity and effects need no repeated manipulation instruction")
			var delta: Dictionary = option.effect_delta
			var before_value := str(delta.get("before",delta.get("damage_before",""))).trim_suffix(".0")
			var after_value := str(delta.get("after",delta.get("damage_after",""))).trim_suffix(".0")
			var benefit: String = card.face_text().split("\n")[1] if card.face_text().split("\n").size() >= 2 else ""
			t.check(not benefit.is_empty() and (benefit.contains(before_value) and benefit.contains(after_value) if not before_value.is_empty() else benefit.contains(Card.effect_text(delta).split("\n")[0])),"card keeps actual measured before/after benefit values in its short change row")
			if delta.has("stat"):
				t.check(benefit.begins_with(str(SHORT_STATS.get(str(delta.stat),str(delta.stat)))+" "),"short measured benefit names the actual authored stat rather than another effect")
			elif delta.has("damage_before"):
				t.check(benefit.begins_with("피해 "),"short attack benefit correctly labels its actual damage change")
			var details = _button(ui,"growth_detail:"+str(option.option_id))
			t.check(details != null,"each card exposes explicit full effects and requirements without hover")
			if details == null: continue
			details.grab_focus()
			ui.navigate("accept")
			await _settle(t)
			t.check(ui._mode == "evolution_detail" and ui._scroll.scroll_vertical == 0,"controller detail opens at top rather than scrolling to bottom back action")
			var detail_text := ""
			for child in ui._choices.get_children():
				if child is Label: detail_text += child.text
			t.check(detail_text.contains(option.description),"detail preserves complete authored description")
			t.check(detail_text.contains(Card.effect_text(option.effect_delta)),"detail preserves every measured effect")
			if option.has("evolution_previews"):
				for recipe in option.evolution_previews:
					t.check(detail_text.contains(Card.evolution_previews_text([recipe],str(option.item_id) if option.kind in ["equipment","passive"] else "")),"detail preserves this skill's own ultimate and actual requirement progress")
			else:
				t.check(detail_text.contains(Card.requirements_text(option.requirements.filter(func(required): return required.item_id != option.item_id))),"evolution detail preserves named requirement progress and missing reasons")
			ui.accept_released()
			ui.navigate("down")
			await _settle(t)
			var bar: VScrollBar = ui._scroll.get_v_scroll_bar()
			t.check(ui._scroll.scroll_vertical > 0 or bar.max_value <= bar.page,"controller scrolls overflowing details; otherwise all details already fit")
			ui.navigate("cancel")
			await _settle(t)
			t.check(ui._mode == "upgrade" and ui.focused_semantic_id() == "growth_detail:"+str(option.option_id),"B returns to the same explicit detail control without selecting growth")
			t.check(selected.is_empty(),"browsing and returning from details never chooses growth")
	var chosen_id: String = view.active_offer.options[0].option_id
	_button(ui,chosen_id).grab_focus()
	ui.accept_released()
	ui.navigate("accept")
	t.check(selected == [[view.active_offer.offer_id,chosen_id]],"one controller accept emits exactly the current offer and semantic option")
	t.check(state == before,"layout, detail and selection presentation never mutate Core state")
	ui.free()

