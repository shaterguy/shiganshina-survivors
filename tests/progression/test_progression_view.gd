extends RefCounted
const Fixture = preload("res://tests/progression/progression_test_fixture.gd")
const R0 = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	var path := "res://game/progression/progression_view.gd"
	t.check(ResourceLoader.exists(path),"NEW read-only progression view exists")
	if not ResourceLoader.exists(path): return
	var catalog = Fixture.legacy_catalog()
	var builder = load(path).new(catalog)
	var state := Fixture.state()
	state.equipment.blade_slash = 4
	state.passives.movement = 2
	state.upgrade_offer = R0.new().progression_source_offer("missing")
	var before := state.duplicate(true)
	var view: Dictionary = builder.build(state)
	t.check(view.keys().size() == 6 and view.has_all(["view_revision","slots","target","evolutions","active_offer","owned"]),"view preserves R0 fields and adds derived owned progress")
	if not view.has("active_offer"): return
	t.check(view.slots == {"equipment":{"used":1,"max":4},"passive":{"used":1,"max":4}},"singular passive slot consumer shape")
	t.check(view.target.evolution_id == "evo_wing_cut" and view.target.requirements[0].current == 4 and view.target.requirements[1].current == 2,"view shows actual target progress")
	t.check(view.active_offer.offer_id == state.upgrade_offer.offer_id and view.active_offer.selected_option_id == state.upgrade_offer.selected_option_id,"source offer and semantic focus preserved")
	var option: Dictionary = view.active_offer.options[0]
	t.check(option.option_id == "equipment:blade_slash" and option.level == 4 and option.next_level == 5,"materialized option identity and levels never rebased by view")
	t.check(option.effect_delta.damage_before == 30 and option.effect_delta.damage_after == 36 and option.effect_delta.cooldown_ticks_before == 39 and option.effect_delta.cooldown_ticks_after == 36,"upgrade card reports hand-computed actual damage/cooldown")
	t.check(is_equal_approx(option.effect_delta.range_before,72) and is_equal_approx(option.effect_delta.range_after,78),"upgrade card reports actual range")
	view.active_offer.options[0].next_level = 99
	view.target.requirements[0].current = 99
	t.check(state == before,"deep mutation of view never aliases source state")
	for index in range(20): builder.build(state)
	t.check(state == before,"repeated UI rebuild neither mutates state nor consumes RNG")
	state = Fixture.state()
	state.equipment.blade_slash = 5
	state.passives = {"damage":1,"max_health":1,"recovery":1}
	state.tactical_seals = 1
	state.upgrade_offer = {"offer_id":Fixture.RUN_ID+":offer:1","source":"level","level_ordinal":2,"options":[{"option_id":"passive:armor","item_id":"armor","kind":"passive","level":0,"next_level":1}],"selected_option_id":"passive:armor"}
	view = builder.build(state)
	t.check(view.target.status == "collecting" and view.active_offer.options[0].can_select,"prospective fourth-slot choice remains legal")
	t.check(view.active_offer.options[0].slot_warning == "이 선택으로 목표 진화의 필수 기술을 새로 배울 수 없습니다","exact warning before blocking missing target passive")
	state.passives.armor = 1
	state.upgrade_offer = {}
	t.check(builder.build(state).target.status == "blocked","after fourth-slot choice target becomes blocked")
	state = Fixture.state()
	state.upgrade_offer = {"offer_id":Fixture.RUN_ID+":offer:1","source":"level","level_ordinal":2,"options":[{"option_id":"passive:movement","item_id":"movement","kind":"passive","level":0,"next_level":1}],"selected_option_id":"passive:movement"}
	state.passives.movement = 1
	view = builder.build(state)
	t.check(view.active_offer.options[0].level == 0 and not view.active_offer.options[0].can_select,"stale levels are disabled rather than silently rebased")
	state = Fixture.state()
	state.equipment = {"blade_slash":5,"spin_slash":1,"odm_dash":1}
	state.run_config.target_evolution_id = "evo_crossfire"
	state.upgrade_offer = {"offer_id":Fixture.RUN_ID+":offer:1","source":"level","level_ordinal":2,"options":[{"option_id":"equipment:ally_cover","item_id":"ally_cover","kind":"equipment","level":0,"next_level":1}],"selected_option_id":"equipment:ally_cover"}
	view = builder.build(state)
	t.check(not view.active_offer.options[0].slot_warning.is_empty(),"last equipment slot also warns when target cannon would be blocked")
