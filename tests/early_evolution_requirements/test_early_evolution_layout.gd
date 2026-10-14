extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Text = preload("res://tests/early_evolution_requirements/test_early_evolution_requirements.gd")
func _settle(t) -> void:
	for frame in range(8): await t.process_frame
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var state: Dictionary = sim.new_run(Fixture.chapter(),1,Fixture.run_config())
	state.player.level = 2
	state.offer_seq = 1
	state.upgrade_offer = {"offer_id":state.run_id+":offer:1","source":"level","level_ordinal":2,"selected_option_id":"equipment:spin_slash","options":[
		{"option_id":"equipment:spin_slash","item_id":"spin_slash","kind":"equipment","level":0,"next_level":1},
		{"option_id":"passive:armor","item_id":"armor","kind":"passive","level":0,"next_level":1},
		{"option_id":"equipment:blade_slash","item_id":"blade_slash","kind":"equipment","level":1,"next_level":2}]}
	var view: Dictionary = View.new().build(state)
	var before := state.duplicate(true)
	var text_reader := Text.new()
	for screen in [Vector2i(800,450),Vector2i(450,800),Vector2i(360,800)]:
		var viewport := SubViewport.new()
		viewport.size = screen
		t.root.add_child(viewport)
		var ui := UI.new()
		viewport.add_child(ui)
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		ui.present(sim.snapshot(state))
		ui.present_progression(view)
		var choices: Array = []
		ui.upgrade_chosen.connect(func(offer,id): choices.append([offer,id]))
		await _settle(t)
		for index in view.active_offer.options.size():
			var option: Dictionary = view.active_offer.options[index]
			var card: Button = ui._growth_cards[index]
			card.grab_focus()
			await _settle(t)
			var rows: VBoxContainer = card.get_node("Requirements")
			var recipe: Dictionary = option.evolution_previews[0]
			t.check(rows.visible and text_reader._labels(rows).contains(recipe.name),"early ultimate is visible directly on the selection card: "+str(screen)+" "+option.item_id)
			t.check(text_reader._labels(rows).contains("Lv %d/5" % int(recipe.requirements[0].current)),"selection card shows the base level progress without opening details")
			t.check(text_reader._icon_count(rows) == recipe.requirements.size(),"every authored prerequisite has its icon")
			t.check(card.get_global_rect().grow(1).encloses(rows.get_global_rect()),"requirement block stays within its card at "+str(screen))
			t.check(not rows.get_global_rect().intersects(ui._growth_details[index].get_global_rect()),"prerequisite block never covers the independent i hit target")
			t.check(ui._scroll.get_global_rect().grow(1).encloses(card.get_global_rect()),"focused early-recipe card is fully visible at "+str(screen))
			ui._growth_details[index].grab_focus()
			ui.accept_released()
			ui.navigate("accept")
			await _settle(t)
			t.check(ui._mode == "evolution_detail" and text_reader._labels(ui._choices).contains(recipe.name),"i opens this exact early recipe")
			ui.accept_released()
			ui.navigate("cancel")
			await _settle(t)
			t.check(ui._mode == "upgrade" and ui.focused_semantic_id() == "growth_detail:"+option.option_id,"closing detail returns to the same growth choice")
			t.check(choices.is_empty(),"reading a future ultimate never selects an upgrade")
		viewport.free()
		await _settle(t)
	t.check(state == before,"responsive early-recipe browsing does not change game state")
