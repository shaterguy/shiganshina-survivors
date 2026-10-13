extends RefCounted
# Legacy definitions are test inputs; production must obtain the exact preserved
# definitions through its authorized compatibility provider, never reset saves.
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const View = preload("res://game/progression/progression_view.gd")
const F = preload("res://tests/progression/progression_test_fixture.gd")
func run(t) -> void:
	var data := F.read("res://tests/run_final_evolution/fixtures/dev4-evolutions.json")
	var catalog := Catalog.new(null,null,data)
	t.check(catalog.validate().is_empty(),"legacy schema-one recipes remain accepted")
	var state := F.state()
	state.equipment = {"blade_slash":5}
	state.passives = {"movement":3}
	t.check(not catalog.evolutions.evaluate(state,"evo_wing_cut").get("can_evolve",true),"legacy recipe still requires its actual seal")
	state.tactical_seals = 1
	var detail: Dictionary = catalog.evolutions.evaluate(state,"evo_wing_cut")
	t.check(detail.get("can_evolve",false) and detail.get("requirements",[]).size() == 3,"legacy five-plus-passive-three-plus-seal recipe is unchanged")
	var option := {"option_id":"evolution:evo_wing_cut","item_id":"blade_slash","kind":"evolution","level":5,"next_level":5,"evolution_id":"evo_wing_cut"}
	t.check(catalog.option_valid(state,option),"legacy materialized five-to-five offer remains selectable")
	state.evolutions.blade_slash = "evo_wing_cut"
	state.tactical_seals = 0
	t.check(catalog.evolutions.progression_state_valid(state),"legacy evolved authority remains accepted")
	var view := View.new(catalog).build(state)
	t.check(not view.is_empty() and view.owned.equipment[0].get("display_level",0) == 6,"legacy evolution receives final-stage UI without changing stored levels")
	t.check(state.equipment.blade_slash == 5 and state.passives.movement == 3 and state.tactical_seals == 0,"legacy projection does not rewrite progression authority")

	# Schema-one has no recipe for spin_slash. Card and owned caps must agree.
	state = F.state()
	state.equipment = {"blade_slash":1,"spin_slash":4}
	var spin_option := {"option_id":"equipment:spin_slash","item_id":"spin_slash","kind":"equipment","level":4,"next_level":5}
	var decorated: Dictionary = catalog.decorate_option(state,spin_option,true)
	t.check(not decorated.is_empty() and decorated.get("max_level",0) == 5 and decorated.get("display_max_level",0) == 5,"legacy non-recipe attack card remains four-to-five of five")
	state.upgrade_offer = {"offer_id":F.RUN_ID+":offer:1","source":"level","level_ordinal":2,"options":[spin_option],"selected_option_id":"equipment:spin_slash"}
	view = View.new(catalog).build(state)
	t.check(not view.is_empty() and view.active_offer.options[0].max_level == 5 and view.active_offer.options[0].display_max_level == 5,"legacy active offer preserves the same five-stage cap")
	state.upgrade_offer = {}
	state.equipment.spin_slash = 5
	view = View.new(catalog).build(state)
	if view.is_empty(): return
	for row in view.owned.equipment:
		if row.item_id == "spin_slash": t.check(row.level == 5 and row.max_level == 5 and row.is_max,"legacy non-recipe attack completes five of five without a fictitious sixth stage")
