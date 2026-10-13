extends RefCounted
# Additional presentation arrangements use actual current catalog decoration;
# these are not evidence of naturally earned progression or game balance.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Offers = preload("res://game/progression/growth_offer_service.gd")
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
	evolution.equipment = {"blade_slash":5,"wall_cannon":5,"odm_dash":1,"ally_cover":1}
	evolution.passives = {"movement":1,"fire_interval":1,"armor":1}
	evolution.tactical_seals = 2
	var evolution_checked := false
	for state in [ordinary,slots,evolution]:
		state.player.level = 2
		state.offer_seq = 1
		state.upgrade_offer = {}
		var materialized: Dictionary = Offers.new(catalog).materialize(state,{"offer_id":state.run_id+":offer:1","source":"level","level_ordinal":2})
		t.check(materialized.get("ok",false),"edge cards use the real offer materializer")
		var options: Array = catalog.candidates(state)
		for option in materialized.get("offer",{}).get("options",[]):
			if option.kind == "evolution": options.append(option)
		for original in options:
			# Keep three actual choices so every candidate is tested at the
			# responsive landscape width, including last-slot warnings.
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
			t.check(card.text.split("\n")[0] == option.name,"every actual card keeps its complete authored identity on the first row")
			# An irreversible slot warning can legitimately say '이 선택으로'.
			# Match the action prompt itself, never delete that meaningful warning.
			t.check(not card.text.contains("터치/A") and not card.text.contains("A · 선택") and not ui._subtitle.text.contains("터치/A") and not ui._subtitle.text.contains("i 상세"),"actual cards and subtitle omit persistent manipulation instructions")
			if not option.slot_warning.is_empty():
				t.check(card.text.contains(option.slot_warning),"irreversible last-slot warning remains visible before choosing")
			if option.kind == "evolution":
				evolution_checked = true
				t.check(card.text.split("\n")[1] == "5/6 → 6/6" and card.display_text().contains("진화") and not card.text.contains("궁극"),"evolution face keeps the sixth-stage numbers on one compact row and details preserve the run evolution label")
				for requirement in option.requirements:
					if requirement.kind == "seal" and int(requirement.required) > 0: t.check(card.text.contains("개조권 %d개 소비" % int(requirement.required)),"legacy recipe summary discloses an actual seal consumption")
				ui._buttons[1].grab_focus()
				ui.navigate("accept")
				await _settle(t)
				var content := ui._choices.get_node("GrowthDetails") as Label
				t.check(content.text.contains(Card.player_text(option.tradeoff_text)),"evolution detail preserves its complete authored tactical cost")
				t.check(content.text.contains(Card.player_text(option.description)),"evolution detail presents authored fixed ticks as seconds")
				t.check(not content.text.ends_with("A · 선택"),"read-only detail never suggests an active growth choice")
			ui.free()
	t.check(evolution_checked,"edge-card test actually visits a selectable final evolution")
