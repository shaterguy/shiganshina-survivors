extends RefCounted
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
func run(t) -> void:
	var ui = load("res://game/ui/game_ui.gd").new()
	t.root.add_child(ui)
	t.check(ui.has_method("reset_obsolete_presentation"),"UI exposes explicit obsolete-authority presentation reset")
	if not ui.has_method("reset_obsolete_presentation"):
		ui.free()
		return
	var emitted: Array = []
	ui.upgrade_chosen.connect(func(_offer,_option): emitted.append("upgrade"))
	ui.shop_closed.connect(func(): emitted.append("shop_closed"))
	ui.resume_requested.connect(func(): emitted.append("resume"))
	ui.present_progression(Fixture.new().progression_view("ready"))
	ui.open_evolution_details("evo_wing_cut")
	ui.reset_obsolete_presentation({},true)
	t.check(ui._growth_view.is_empty() and ui._detail_id.is_empty() and ui._return_focus_id.is_empty(),"reset discards obsolete recipe DTO and return focus")
	t.check(ui._mode == "title" and ui._checkpoint_available and ui.focused_semantic_id() == "이어서 출격","reset presents the supplied authoritative resume state")
	t.check(emitted.is_empty(),"obsolete reset performs no gameplay or shop-close semantic action")
	ui.navigate("cancel")
	t.check(ui._mode == "title" and ui._growth_view.is_empty(),"B after obsolete reset cannot rebuild old mandatory growth")
	ui.accept_released()
	ui.navigate("accept")
	t.check(emitted == ["resume"],"fresh focused accept emits only the current explicit resume")
	# Obsolete detail must not obscure a newly authoritative terminal result either.
	ui.present_progression(Fixture.new().progression_view("ready"))
	ui.open_evolution_details("evo_wing_cut")
	var terminal: Dictionary = Fixture.new().run_state()
	terminal.phase = "dead"
	ui.reset_obsolete_presentation(terminal,false)
	t.check(ui._mode == "dead" and ui._snapshot.phase == "dead" and ui._growth_view.is_empty() and ui._detail_id.is_empty(),"reset presents authoritative terminal result without stale detail")
	await t.process_frame
	await t.process_frame
	t.check(ui._scroll.follow_focus,"reset preserves current deferred-layout and focus-follow behavior")
	ui.free()
