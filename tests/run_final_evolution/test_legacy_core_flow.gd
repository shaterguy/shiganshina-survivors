extends RefCounted
# Preserved dev4 seal/passive Core flow with immutable definitions.
# Test-only XP, clock and remaining-health arrangements. All offers, choices,
# boss reward, casts, hits and restores below go through the real Core API.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Legacy = preload("res://tests/run_final_evolution/legacy_flow_provider.gd")
const View = preload("res://game/progression/progression_view.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
func run(t) -> void:
	for recipe in ["evo_wing_cut","evo_crossfire"]: _flow(t,recipe)
func _flow(t,recipe: String) -> void:
	var sim := Core.new(Legacy.new(),null,Legacy.inputs())
	var catalog := Catalog.new(null,null,Legacy.inputs()["data/evolutions.json"])
	var definition: Dictionary = catalog.evolutions.definition(recipe)
	var base: String = definition.base_item_id
	var prerequisite: String = definition.required_passives[0].passive_id
	var state := sim.new_run(Legacy.new().load_chapter("chapter_01_shiganshina").chapter,42,F.run_config(1,"doctrine_standard",recipe))
	state.equipment = {base:4,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	state.passives = {prerequisite:2,"damage":5,"attack_range":5,"armor":5}
	for id in state.equipment:
		if id != base: state.player.attack_ready_ticks[id] = 2147483647
	t.check(sim.restore(state).get("ok",false),"arranged near-max build is a real restorable run: "+recipe)
	F.drop_xp(sim,state,24,"fixture:xp:weapon")
	var offer: String = state.upgrade_offer.get("offer_id","")
	var result := sim.choose_upgrade(state,offer,"equipment:"+base)
	t.check(result.get("ok",false) and state.equipment[base] == 5,"actual level offer reaches bounded weapon maximum: "+recipe)
	var owned := _weapon(View.new(catalog).build(state),base)
	t.check(not owned.get("is_max",true) and owned.get("max_level",0) == 6 and not owned.get("is_evolved",true) and owned.get("evolution_status") == "collecting","legacy recipe base five retains its final UI stage while old gates remain unmet: "+recipe)
	var before := state.duplicate(true)
	t.check(not sim.choose_upgrade(state,offer,"equipment:"+base).ok and state == before,"duplicate maximum-level selection is rejected without mutation")
	for option in catalog.candidates(state):
		t.check(option.item_id != base,"maximum weapon cannot be offered a sixth level")
	F.drop_xp(sim,state,32,"fixture:xp:prerequisite")
	result = sim.choose_upgrade(state,state.upgrade_offer.offer_id,"passive:"+prerequisite)
	t.check(result.get("ok",false) and state.passives[prerequisite] == 3,"actual separate-skill offer completes the passive prerequisite: "+recipe)
	owned = _weapon(View.new(catalog).build(state),base)
	t.check(owned.requirements[1].met and not owned.requirements[2].met and owned.evolution_status == "collecting","prerequisite alone cannot grant ultimate without boss seal")
	state.active_tick = 17999
	state.survival_tick = 17999
	state.player.attack_ready_ticks[base] = 18001
	F.step(sim,state,Vector2.ZERO,[F.boss("ch01_b05",[60,0])])
	t.check(state.entities.size() == 1,"authored five-minute boss was spawned")
	if state.entities.is_empty(): return
	state.entities[0].hp = 1.0
	t.check(sim.restore(state).get("ok",false),"arranged remaining boss HP is accepted before real killing attack")
	for tick in 180:
		F.step(sim,state,Vector2.ZERO)
		if state.stats.minibosses_defeated == 1: break
	t.check(state.tactical_seals == 1 and state.stats.minibosses_defeated == 1,"real boss killing hit grants exactly one prerequisite seal")
	t.check(not state.upgrade_offer.is_empty(),"earned boss reward opens a real offer")
	if state.upgrade_offer.is_empty(): return
	offer = state.upgrade_offer.offer_id
	var view := View.new(catalog).build(state)
	t.check(_weapon(view,base).evolution_status == "ready" and view.active_offer.options[0].option_id == "evolution:"+recipe,"owned readiness and actual offered ultimate share authority")
	var pending := sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state),"",true,true)))
	t.check(pending.get("ok",false),"materialized ultimate offer restores without reroll")
	if not pending.get("ok",false): return
	var chosen := sim.choose_upgrade(state,offer,"evolution:"+recipe)
	var resumed_choice := sim.choose_upgrade(pending.state,offer,"evolution:"+recipe)
	t.check(chosen.ok and chosen == resumed_choice and state == pending.state,"pending-offer resume produces the same choice and events")
	t.check(state.equipment[base] == 5 and state.passives[prerequisite] == 3 and state.tactical_seals == 0 and state.evolutions[base] == recipe,"evolution consumes one seal and preserves weapon/passive levels")
	before = state.duplicate(true)
	t.check(not sim.choose_upgrade(state,offer,"evolution:"+recipe).ok and state == before,"duplicate ultimate choice cannot spend twice")
	# Isolate one cast from XP pickup and later recasts, without changing damage,
	# geometry, stage times or the authoritative selected evolution.
	state.drops.clear()
	state.player.attack_ready_ticks[base] = state.active_tick
	var events := F.step(sim,state,Vector2.ZERO,[F.spawn("fixture:cast-target",[60,0],"brute")])
	var scheduled := F.types(events,"player_attack").filter(func(event): return event.payload.phase == "scheduled")
	t.check(scheduled.size() == 2,"selected ultimate schedules both actual attack stages")
	if scheduled.size() != 2: return
	var cast_id: String = scheduled[0].payload.cast_id
	owned = _weapon(View.new(catalog).build(state),base)
	for stage in 2:
		var payload: Dictionary = scheduled[stage].payload
		t.check(payload.evolution_id == recipe and payload.base_item_id == base and payload.stage_count == owned.effect_stats.stages,"DTO evolution matches actual cast identity and stage count")
		t.check(is_equal_approx(payload.damage,owned.effect_stats.stage_damage[stage]) and payload.execute_tick-payload.attack_started_tick == owned.effect_stats.stage_delays[stage] and is_equal_approx(payload.geometry.radius,owned.effect_stats.radius),"HUD damage, delay and geometry match actual scheduled attack")
	state.player.attack_ready_ticks[base] = 2147483647
	var restored := sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state),"",true,true)))
	t.check(restored.get("ok",false),"delayed ultimate checkpoint survives exact JSON save/restore")
	if not restored.get("ok",false): return
	var replay_sim := Core.new(Legacy.new(),null,Legacy.inputs())
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
	t.check(_weapon(View.new(catalog).build(state),base).is_evolved and sim.restore(state).get("ok",false),"ultimate HUD and restorable Core remain consistent after combat")
func _weapon(view: Dictionary, id: String) -> Dictionary:
	for row in view.get("owned",{}).get("equipment",[]):
		if row.item_id == id: return row
	return {}
