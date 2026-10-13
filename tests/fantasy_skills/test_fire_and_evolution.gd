extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const View = preload("res://game/progression/progression_view.gd")
func run(t) -> void:
	var catalog := Catalog.new()
	t.check(catalog.equipment.has("fire_zone"),"fire zone is registered in equipment")
	t.check(catalog.evolutions.ids().has("evo_storm_chain") and catalog.evolutions.ids().has("evo_inferno_zone"),"both new ultimate recipes are registered")
	if not catalog.equipment.has("fire_zone") or not catalog.evolutions.ids().has("evo_storm_chain"): return
	_pulses(t)
	_requirements(t,catalog)
func _pulses(t) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"fire_zone":1}
	var events := F.step(sim,state,Vector2.ZERO,[F.spawn("fire-target",[100,0],"brute")])
	var attacks := _attacks(events)
	t.check(attacks.size() == 1,"fire field first pulse hits immediately")
	t.check(state.player_attack_instances.size() == 3,"Lv1 fire reserves only three future pulses")
	if state.player_attack_instances.size() != 3: return
	var saved: Dictionary = sim.snapshot(state)
	var cold: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(saved)))
	t.check(cold.get("ok",false),"pending base fire is accepted by cold JSON restore")
	if not cold.get("ok",false): return
	for step in 90:
		var live := F.step(sim,state,Vector2.ZERO)
		var replay := F.step(sim,cold.state,Vector2.ZERO)
		t.check(live == replay,"fire cold replay preserves exact events at every pulse tick")
		if not _attacks(live).is_empty(): attacks.append_array(_attacks(live))
	t.check(attacks.size() == 4 and state.player_attack_instances.is_empty(),"finite four-pulse field expires without permanent damage aura")
	var ticks := []
	for event in attacks: ticks.append(int(event.payload.execute_tick))
	t.check(ticks == [1,31,61,91],"fire tick rhythm is exactly 30 ticks")
	for field in ["damage","radius","execute_tick","stage_count","cast_level"]:
		var bad: Dictionary = saved.duplicate(true)
		bad.player_attack_instances[0][field] += 1
		t.check(not sim.restore(bad).get("ok",false),"forged fire "+field+" fails closed")
	var missing: Dictionary = saved.duplicate(true)
	missing.player_attack_instances.remove_at(0)
	t.check(not sim.restore(missing).get("ok",false),"missing future pulse fails closed rather than shortening saved field")
func _requirements(t,catalog) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"chain_lightning":5}
	state.tactical_seals = 0
	var detail: Dictionary = catalog.evolutions.evaluate(state,"evo_storm_chain")
	t.check(detail.status == "collecting" and not detail.can_evolve,"chain final stage requires another owned attack")
	state.equipment.fire_zone = 1
	detail = catalog.evolutions.evaluate(state,"evo_storm_chain")
	t.check(detail.status == "ready" and detail.requirements.size() == 2,"other attack at one is sufficient with zero seals")
	state.equipment = {"chain_lightning":5,"blade_slash":5,"odm_dash":5,"spin_slash":5}
	detail = catalog.evolutions.evaluate(state,"evo_storm_chain")
	t.check(detail.status == "blocked" and detail.requirements[1].blocked_reason == "equipment_slots","full slots expose impossible missing cross-skill instead of bypassing it")
	state.equipment = {"chain_lightning":5,"fire_zone":1}
	state.evolutions = {"chain_lightning":"evo_storm_chain"}
	state.tactical_seals = 0
	var view: Dictionary = View.new().build(state)
	t.check(not view.is_empty() and view.owned.equipment[0].level == 6 and view.owned.equipment[0].base_level == 5 and view.owned.equipment[0].max_level == 6,"new evolved skill uses existing owned progression DTO")
func _attacks(events: Array) -> Array:
	return events.filter(func(e): return e.type == "player_attack" and e.payload.base_item_id == "fire_zone" and e.payload.phase == "executed")
