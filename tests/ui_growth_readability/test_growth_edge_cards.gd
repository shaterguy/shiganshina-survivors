extends RefCounted
# Additional presentation arrangements use actual current catalog decoration;
# these are not evidence of naturally earned progression or game balance.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Card = preload("res://game/ui/growth_card.gd")
func _settle(t) -> void:
	for frame in range(6): await t.process_frame
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var catalog := Catalog.new()
	var ordinary: Dictionary = sim.new_run(Fixture.chapter(),51,Fixture.run_config())
	var slots := ordinary.duplicate(true)
	slots.equipment = {"spin_slash":1,"odm_dash":1,"reentry_combo":1}
	var evolution := ordinary.duplicate(true)
	evolution.equipment = {"blade_slash":5,"wall_cannon":5}
	evolution.passives = {"movement":3,"fire_interval":3}
	evolution.tactical_seals = 2
	for state in [ordinary,slots,evolution]:
		var options: Array = catalog.candidates(state)
		for original in options:
			# Keep three columns populated so every candidate is tested at the
			# actual narrow landscape width, including last-slot warnings.
			var displayed := [original]
			for other in options:
				if other.option_id != original.option_id and displayed.size() < 3: displayed.append(other)
			state.upgrade_offer = {"offer_id":state.run_id+":offer:1","source":"level","level_ordinal":2,"selected_option_id":original.option_id,"options":displayed}
			var view := View.new(catalog).build(state)
			t.check(not view.is_empty() and not view.active_offer.is_empty(),"catalog candidate has a valid derived presentation DTO")
			if view.is_empty() or view.active_offer.is_empty(): continue
			var option: Dictionary = view.active_offer.options[0]
			var ui := UI.new()
			t.root.add_child(ui)
			ui.present(sim.snapshot(state))
			ui.present_progression(view)
			ui.reflow(Vector2i(800,450),Rect2i(0,0,800,450))
			await _settle(t)
			var card: Button = ui._buttons[0]
			t.check(ui._scroll.get_global_rect().grow(1).encloses(card.get_global_rect()),"800x450 complete primary card fits for "+option.option_id)
			t.check(card.text.contains(option.name) and card.text.contains("선택"),"every selectable ordinary/evolution card retains name and action")
			if not option.slot_warning.is_empty():
				t.check(card.text.contains(option.slot_warning),"irreversible last-slot warning remains visible before choosing")
			if option.kind == "evolution":
				t.check(card.text.contains("개조권 1개 소비") and card.text.contains("대가"),"evolution summary discloses its consumption and tradeoff")
				ui._buttons[1].grab_focus()
				ui.navigate("accept")
				await _settle(t)
				var content := ui._choices.get_node("GrowthDetails") as Label
				t.check(content.text.contains(Card.player_text(option.tradeoff_text)),"evolution detail preserves its complete authored tactical cost")
				t.check(content.text.contains(Card.player_text(option.description)),"evolution detail presents authored fixed ticks as seconds")
				t.check(not content.text.ends_with("A · 선택"),"read-only detail never suggests an active growth choice")
			ui.free()
