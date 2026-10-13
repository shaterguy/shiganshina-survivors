extends RefCounted
const Fixture = preload("res://tests/progression/progression_test_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	var state := Fixture.state()
	state.rules.permanent_damage_bonus = 0.05
	state.upgrade_offer = {"offer_id":Fixture.RUN_ID+":offer:1","source":"level","level_ordinal":2,"options":[{"option_id":"equipment:wall_cannon","item_id":"wall_cannon","kind":"equipment","level":0,"next_level":1},{"option_id":"passive:damage","item_id":"damage","kind":"passive","level":0,"next_level":1}],"selected_option_id":"equipment:wall_cannon"}
	var original := state.duplicate(true)
	var view := View.new().build(state)
	for option in view.active_offer.options:
		t.check(option.get("max_level",0) == (6 if option.kind == "equipment" else 5),"current attack final6 and passive5 caps are projected in view only")
	var delta: Dictionary = view.active_offer.options[1].effect_delta
	t.check(is_equal_approx(delta.before,1.05) and is_equal_approx(delta.after,1.2),"damage passive card includes immutable permanent contribution")
	t.check(state == original and not state.upgrade_offer.options[0].has("max_level"),"offer DTO cap does not alter stored decoration or source metadata")
	state.rules.erase("permanent_damage_bonus")
	var legacy: Dictionary = View.new().build(state).active_offer.options[1].effect_delta
	t.check(legacy.before == 1.0 and legacy.after == 1.15,"legacy damage card retains the original one-point-zero baseline")
	state.equipment.blade_slash = 5
	state.equipment.odm_dash = 1
	state.tactical_seals = 0
	state.upgrade_offer.options = [{"option_id":"evolution:evo_wing_cut","item_id":"blade_slash","kind":"evolution","level":5,"next_level":6,"evolution_id":"evo_wing_cut"}]
	state.upgrade_offer.selected_option_id = "evolution:evo_wing_cut"
	var current_before := state.duplicate(true)
	view = View.new().build(state)
	t.check(not view.is_empty(),"current base5 plus owned-Lv1 material produces a valid final6 offer DTO")
	if not view.is_empty():
		t.check(view.active_offer.options[0].get("max_level",0) == 6 and view.active_offer.options[0].next_level == 6 and view.active_offer.options[0].can_select,"current evolution card exposes a selectable final6 step without a seal")
	t.check(state == current_before and state.tactical_seals == 0,"current evolution projection does not alter authority or invent seal requirements")
	var legacy_state := Fixture.state()
	legacy_state.equipment.blade_slash = 5
	legacy_state.passives.movement = 3
	legacy_state.tactical_seals = 1
	legacy_state.upgrade_offer = {"offer_id":Fixture.RUN_ID+":offer:1","source":"level","level_ordinal":2,"options":[{"option_id":"evolution:evo_wing_cut","item_id":"blade_slash","kind":"evolution","level":5,"next_level":5,"evolution_id":"evo_wing_cut"}],"selected_option_id":"evolution:evo_wing_cut"}
	var legacy_before := legacy_state.duplicate(true)
	var legacy_view: Dictionary = View.new(Fixture.legacy_catalog()).build(legacy_state)
	t.check(not legacy_view.is_empty(),"preserved schema1 old5-to5 offer remains a valid presentation input")
	if not legacy_view.is_empty():
		t.check(legacy_view.active_offer.options[0].display_max_level == 6 and legacy_view.active_offer.options[0].display_next_level == 6,"schema1 presentation shows final6 without rewriting stored old5-to5")
	t.check(legacy_state == legacy_before and legacy_state.tactical_seals == 1 and legacy_state.upgrade_offer.options[0].next_level == 5,"schema1 projection preserves original seal1 and exact stored offer authority")
	for invalid in [-0.05,0.3,NAN,INF,"0.05",true]:
		state.rules.permanent_damage_bonus = invalid
		t.check(not Catalog.new().state_valid(state),"invalid permanent bonus fails closed at catalog view boundary")
