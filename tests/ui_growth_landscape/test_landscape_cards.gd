extends RefCounted
# Actual Core offer and native Control layout, including repeated rotations.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
	for frame in range(10): await t.process_frame
func run(t) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = F.earn_offer(sim,21,24)
	var before := state.duplicate(true)
	var view: Dictionary = View.new().build(state)
	var vp := SubViewport.new()
	t.root.add_child(vp)
	var ui := UI.new()
	vp.add_child(ui)
	ui.present(sim.snapshot(state))
	ui.present_progression(view)
	var nodes := ui._growth_cards.map(func(card): return card.get_instance_id())
	for screen in [Vector2i(800,450),Vector2i(960,432),Vector2i(844,390),Vector2i(640,360),Vector2i(360,800),Vector2i(800,450)]:
		vp.size = screen
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		await _settle(t)
		for index in view.active_offer.options.size():
			var card: Button = ui._growth_cards[index]
			var info: Button = ui._growth_details[index]
			var rows: Control = card.get_node("Requirements")
			var style := card.get_theme_stylebox("normal")
			var body := Rect2(card.get_global_rect().position+Vector2(style.get_margin(SIDE_LEFT),style.get_margin(SIDE_TOP)),card.size-style.get_minimum_size())
			var available := body.size.x-card.get_theme_constant("icon_max_width")-card.get_theme_constant("h_separation")
			var context := str(screen)+" "+str(card.get_meta("semantic_id"))
			for label in [card.get_node("CardTitle"),card.get_node("CardEffect")]:
				t.check(label.get_total_character_count() > 0 and label.size.x <= available+1 and body.grow(1).encloses(label.get_global_rect()),"visible wrapped title and benefit stay in the reserved summary: "+context)
			t.check(card.get_global_rect().encloses(info.get_global_rect()) and info.size.x >= 48 and info.size.y >= 48,"independent 48px i stays inside card: "+context)
			t.check(card.get_global_rect().encloses(rows.get_global_rect()),"conditions stay inside card: "+context)
			t.check(not rows.get_global_rect().intersects(info.get_global_rect()) and not body.intersects(rows.get_global_rect()) and not body.intersects(info.get_global_rect()),"summary, conditions and i occupy separate regions: "+context)
			for target in [card,info]:
				target.grab_focus()
				await _settle(t)
				t.check(ui._scroll.get_global_rect().grow(1).encloses(card.get_global_rect()),"focus reveals entire card within viewport: "+context)
			t.check(Rect2(Vector2.ZERO,Vector2(screen)).encloses(ui._panel.get_global_rect()),"panel stays within resized screen: "+context)
		t.check(nodes == ui._growth_cards.map(func(card): return card.get_instance_id()),"rotation reuses attached cards")
	t.check(state == before and ui._growth_view == view,"layout does not mutate authority or derived requirements")
	vp.free()
