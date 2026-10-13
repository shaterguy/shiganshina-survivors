extends RefCounted
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Offers = preload("res://game/progression/growth_offer_service.gd")
const PF = preload("res://tests/progression/progression_test_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Card = preload("res://game/ui/growth_card.gd")
const View = preload("res://game/progression/progression_view.gd")
func run(t) -> void:
	var catalog := Catalog.new()
	var sim = F.simulation(t)
	for id in ["evo_whirlwind","evo_sky_lance","evo_echo_assault","evo_wing_squad"]:
		var recipe: Dictionary = catalog.evolutions.definition(id)
		t.check(not recipe.is_empty(),"actual geometry recipe exists for UI copy: "+id)
		if recipe.is_empty(): continue
		var state: Dictionary = sim.new_run(F.chapter(),93,F.run_config())
		state.equipment = {recipe.base_item_id:5}
		state.passives = {}
		for material in recipe.get("required_equipment",[]): state.equipment[material.equipment_id] = int(material.level)
		for material in recipe.get("required_passives",[]): state.passives[material.passive_id] = int(material.level)
		var delta: Dictionary = catalog.evolutions.evaluate(state,id).effect_delta
		var text := Card.effect_text(delta)
		for field in ["length","width","advance_step","radius_step"]:
			if not delta.has(field): continue
			var label: String = {"length":"직선 길이","width":"직선 폭","advance_step":"타격당 전진","radius_step":"타격당 반경 증가"}[field]
			t.check(text.contains(label+" "+str(delta[field])),"actual geometry field is accurately named and measured: "+id+field)
		if delta.has("length"): t.check(not text.contains("반경 0"),"line detail omits an unused zero circle radius")
		if delta.has("point_offset"): t.check(text.contains("좌우 지점 간격") and not text.contains("포격 지점"),"mixed slash/support geometry uses neutral point-offset terminology")
	var path := "res://tests/run_final_evolution/fixtures/dev4-evolutions.json"
	t.check(FileAccess.file_exists(path),"exact preserved legacy recipes are available for the UI projection test")
	if not FileAccess.file_exists(path): return
	var legacy := Catalog.new(null,null,PF.read(path))
	var state := PF.state()
	state.equipment = {"blade_slash":5}
	state.passives = {"movement":3}
	state.tactical_seals = 1
	var materialized: Dictionary = Offers.new(legacy).materialize(state,PF.descriptor())
	t.check(materialized.get("ok",false),"legacy UI option comes from the real schema-one offer materializer")
	state.upgrade_offer = materialized.get("offer",{}).duplicate(true)
	var before_state: Dictionary = state.duplicate(true)
	var presentation: Dictionary = View.new(legacy).build(state)
	t.check(not presentation.get("active_offer",{}).is_empty(),"materialized legacy offer reaches the actual presentation-only View path")
	var legacy_evolution_checked := false
	for option in materialized.get("offer",{}).get("options",[]):
		if option.get("kind","") != "evolution": continue
		legacy_evolution_checked = true
		var before: Dictionary = option.duplicate(true)
		t.check(option.level == 5 and option.next_level == 5,"legacy materialized authority keeps the stored five-to-five contract")
		var projected: Dictionary = {}
		for row in presentation.get("active_offer",{}).get("options",[]):
			if row.get("option_id","") == option.option_id: projected = row
		t.check(not projected.is_empty() and projected.get("display_level") == 5 and projected.get("display_next_level") == 6 and projected.get("display_max_level") == 6,"legacy View projects sixth-stage display fields for the same materialized identity")
		t.check(Card.level_change_text(projected).contains("5/6") and Card.level_change_text(projected).contains("6/6"),"legacy UI prioritizes display fields for the sixth final stage")
		t.check(option == before,"legacy display copy leaves authoritative offer values untouched")
	t.check(legacy_evolution_checked,"legacy sixth-stage copy is actually checked on a materialized evolution")
	t.check(state == before_state,"legacy View display fields never change the authoritative materialized state")
