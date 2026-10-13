extends RefCounted
const Fixture = preload("res://tests/progression/progression_test_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	var state := Fixture.state()
	state.equipment = {"wall_cannon":5,"blade_slash":4,"reentry_combo":2}
	state.passives = {"movement":2,"damage":2,"fire_interval":3}
	var before := state.duplicate(true)
	var builder := View.new()
	var view := builder.build(state)
	t.check(view.has("owned"),"owned progress is available outside an active offer")
	if not view.has("owned"): return
	t.check(view.owned.equipment.size() == 3 and view.owned.passives.size() == 3,"view lists each actual owned item once")
	var blade: Dictionary = view.owned.equipment[0]
	t.check(blade.item_id == "blade_slash" and blade.level == 4 and blade.max_level == 6 and not blade.is_max,"stable catalog order and bounded current level are visible")
	t.check(blade.evolution_id == "evo_wing_cut" and blade.evolution_status == "collecting" and not blade.is_evolved,"owned base exposes its own recipe state")
	t.check(blade.requirements[0].current == 4 and blade.requirements[1].current == 0,"owned recipe requirements show actual prerequisite progress")
	t.check(is_equal_approx(blade.effect_stats.damage,39) and blade.effect_stats.cooldown_ticks == 30,"owned attack statistics include passive modifiers from runtime catalog")
	t.check(not blade.attack_summary.is_empty() and not blade.attack_summary.contains("틱"),"attack summary uses readable seconds")
	var combo: Dictionary = view.owned.equipment[1]
	t.check(combo.evolution_id == "evo_echo_assault" and combo.evolution_status == "collecting" and combo.requirements.size() == 2,"combo exposes its own final recipe rather than borrowing the selected target")
	t.check(combo.effect_stats.hits == 3 and is_equal_approx(combo.effect_stats.total_damage,46.8),"combo view reports actual consolidated three-hit damage")
	var cannon: Dictionary = view.owned.equipment[2]
	t.check(not cannon.is_max and cannon.level == 5 and cannon.max_level == 6 and not cannon.is_evolved and cannon.evolution_status == "collecting","maximum base level is distinguished from ultimate evolution")
	for passive in view.owned.passives:
		t.check(passive.level >= 1 and passive.level <= passive.max_level and passive.effect_stats.has_all(["stat","value"]),"passive row uses the same bounded catalog authority")
	view.owned.equipment[0].requirements[0].current = 99
	view.owned.equipment[0].effect_stats.damage = 999
	for index in 10: builder.build(state)
	t.check(state == before,"owned views are detached read-only projections and consume no RNG")
	state.equipment.blade_slash = 5
	state.equipment.odm_dash = 1
	state.passives.movement = 3
	state.tactical_seals = 0
	view = builder.build(state)
	t.check(view.owned.equipment[0].evolution_status == "ready","readiness uses base five plus the other attack owned at level one")
	state.evolutions.blade_slash = "evo_wing_cut"
	state.tactical_seals = 0
	view = builder.build(state)
	blade = view.owned.equipment[0]
	t.check(blade.is_evolved and blade.is_max and blade.level == 6 and blade.base_level == 5 and blade.evolution_status == "evolved","evolution displays six while retaining internal base level five")
	t.check(blade.effect_stats.stages == 2 and blade.effect_stats.stage_delays == [0,12] and is_equal_approx(blade.effect_stats.stage_damage[0],35.1),"ultimate view matches actual delayed two-stage combat values")
	t.check(blade.attack_summary.contains("2") and blade.attack_summary.contains("0.2"),"ultimate summary makes stage count and delayed hit visible")
	state.equipment.blade_slash = 6
	t.check(builder.build(state).is_empty(),"over-cap state cannot produce plausible growth UI")
