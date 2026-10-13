extends RefCounted
# Test-only XP, clock and remaining-health arrangements. All offers, choices,
# casts, hits and restores below go through the real Core API.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const View = preload("res://game/progression/progression_view.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	for recipe in ["evo_wing_cut","evo_crossfire"]: _flow(t,recipe)
func _flow(t,recipe: String) -> void:
	var sim := Core.new(Current.new())
	var catalog := Catalog.new()
	var definition: Dictionary = catalog.evolutions.definition(recipe)
	var base: String = definition.base_item_id
	var state := sim.new_run(F.chapter(),42,F.run_config(1,"doctrine_standard",recipe))
	state.equipment = {base:4}
	state.passives = {"damage":5,"attack_range":5}
	state.passives["movement" if base == "blade_slash" else "fire_interval"] = 3
	for required in definition.get("required_equipment",[]):
		state.equipment[required.equipment_id] = int(required.level)
		state.player.attack_ready_ticks[required.equipment_id] = 2147483647
	for required in definition.required_passives: state.passives[required.passive_id] = int(required.level)
	t.check(sim.restore(state).get("ok",false),"arranged near-max build is a real restorable run: "+recipe)
	F.drop_xp(sim,state,24,"fixture:xp:weapon")
	var offer: String = state.upgrade_offer.get("offer_id","")
	var result := sim.choose_upgrade(state,offer,"equipment:"+base)
	t.check(result.get("ok",false) and state.equipment[base] == 5,"actual level offer reaches bounded base maximum: "+recipe)
	var owned := _weapon(View.new().build(state),base)
	t.check(not owned.get("is_max",true) and not owned.get("is_evolved",true) and owned.get("evolution_status") == "ready" and owned.get("max_level",0) == 6,"base five plus owned partner one leaves exactly the final stage ready: "+recipe)
	var before := state.duplicate(true)
	t.check(not sim.choose_upgrade(state,offer,"equipment:"+base).ok and state == before,"duplicate maximum-level selection is rejected without mutation")
	for option in catalog.candidates(state):
		t.check(option.item_id != base,"maximum base weapon has no ordinary sixth-level card")
	F.drop_xp(sim,state,32,"fixture:xp:final")
	t.check(not state.upgrade_offer.is_empty(),"earned XP opens the actual final-stage offer without a boss")
	if state.upgrade_offer.is_empty(): return
	offer = state.upgrade_offer.offer_id
	var view := View.new().build(state)
	t.check(_weapon(view,base).evolution_status == "ready" and view.active_offer.options[0].option_id == "evolution:"+recipe,"owned readiness and actual final offer share authority")
	var pending := sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state),"",true,true)))
	t.check(pending.get("ok",false),"materialized final-stage offer restores without reroll")
	if not pending.get("ok",false): return
	var chosen := sim.choose_upgrade(state,offer,"evolution:"+recipe)
	var resumed_choice := sim.choose_upgrade(pending.state,offer,"evolution:"+recipe)
	t.check(chosen.ok and chosen == resumed_choice and state == pending.state,"pending-offer resume produces the same choice and events")
	t.check(state.equipment[base] == 5 and state.tactical_seals == 0 and state.stats.minibosses_defeated == 0 and state.evolutions[base] == recipe,"final evolution needs no boss or seal and preserves the base level and owned material")
	before = state.duplicate(true)
	t.check(not sim.choose_upgrade(state,offer,"evolution:"+recipe).ok and state == before,"duplicate final choice cannot apply twice")
	# Isolate one cast from XP pickup and later recasts, without changing damage,
	# geometry, stage times or the authoritative selected evolution.
	state.drops.clear()
	state.player.attack_ready_ticks[base] = state.active_tick
	var events := F.step(sim,state,Vector2.ZERO,[F.spawn("fixture:cast-target",[60,0],"brute")])
	var scheduled := F.types(events,"player_attack").filter(func(event): return event.payload.phase == "scheduled")
	t.check(scheduled.size() == 2,"selected ultimate schedules both actual attack stages")
	if scheduled.size() != 2: return
	var cast_id: String = scheduled[0].payload.cast_id
	owned = _weapon(View.new().build(state),base)
	for stage in 2:
		var payload: Dictionary = scheduled[stage].payload
		t.check(payload.evolution_id == recipe and payload.base_item_id == base and payload.stage_count == owned.effect_stats.stages,"DTO evolution matches actual cast identity and stage count")
		t.check(is_equal_approx(payload.damage,owned.effect_stats.stage_damage[stage]) and payload.execute_tick-payload.attack_started_tick == owned.effect_stats.stage_delays[stage] and is_equal_approx(payload.geometry.radius,owned.effect_stats.radius),"HUD damage, delay and geometry match actual scheduled attack")
	state.player.attack_ready_ticks[base] = 2147483647
	var restored := sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state),"",true,true)))
	t.check(restored.get("ok",false),"delayed ultimate checkpoint survives exact JSON save/restore")
	if not restored.get("ok",false): return
	var replay_sim := Core.new(Current.new())
	var executed: Array = F.types(events,"player_attack").filter(func(event): return event.payload.phase == "executed")
	var hits: Array = F.types(events,"damage")
	for tick in int(owned.effect_stats.stage_delays[1]):
		var left := F.step(sim,state,Vector2.ZERO)
		var right := F.step(replay_sim,restored.state,Vector2.ZERO)
		t.check(left == right and state == restored.state,"cold resume produces identical ultimate ticks and combat events: "+recipe)
		executed.append_array(F.types(left,"player_attack").filter(func(event): return event.payload.phase == "executed"))
		hits.append_array(F.types(left,"damage"))
	t.check(executed.size() == 2 and state.player_attack_instances.is_empty(),"both stages execute once and their reservations retire")
	var total := 0.0
	var hit_stages := {}
	for hit in hits:
		if hit.payload.get("base_item_id","") != base: continue
		t.check(hit.payload.attack_id.begins_with(cast_id+":"),"each actual damage event binds the cast stage for hit feedback")
		hit_stages[hit.payload.attack_id] = true
		total += float(hit.payload.amount)
	t.check(hit_stages.size() == 2 and total > 0,"both ultimate stages cause real target damage")
	t.check(_weapon(View.new().build(state),base).is_evolved and sim.restore(state).get("ok",false),"ultimate HUD and restorable Core remain consistent after combat")
func _weapon(view: Dictionary, id: String) -> Dictionary:
	for row in view.get("owned",{}).get("equipment",[]):
		if row.item_id == id: return row
	return {}
