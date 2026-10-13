extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Growth = preload("res://game/progression/growth_offer_service.gd")
func run(t) -> void:
	for recipe in ["evo_storm_chain","evo_inferno_zone"]:
		var sim = X.simulation()
		var state := _evolve(t,sim,recipe)
		if state.is_empty(): continue
		if recipe == "evo_storm_chain": _chain_ultimate(t,sim,state)
		else: _fire_ultimate(t,sim,state)
func _evolve(t,sim,recipe: String) -> Dictionary:
	var config: Dictionary = F.run_config(1,"doctrine_standard",recipe)
	config.permanent_upgrades = {"permanent_might":1}
	var state: Dictionary = sim.new_run(X.chapter(),27,config)
	t.check(not state.has("error_code"),"new ultimate can be an actual run target")
	if state.has("error_code"): return {}
	var definition: Dictionary = Catalog.new().evolutions.definition(recipe)
	var base: String = definition.base_item_id
	var choices := 0
	while not _ready_for_final(state,definition) and choices < 60:
		var needed := Catalog.xp_to_next(int(state.player.level),state.rules.progression)-int(state.player.xp)
		F.drop_xp(sim,state,needed,"xp-"+str(choices))
		t.check(not state.upgrade_offer.is_empty(),"actual level gain materializes a selectable offer")
		if state.upgrade_offer.is_empty(): return {}
		var option := _choose(state,definition)
		t.check(not option.is_empty(),"real offers retain a route to cross-skill prerequisites")
		if option.is_empty(): return {}
		var picked: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,option)
		t.check(picked.get("ok",false),"real offer choice passes transactional Core validation")
		if not picked.get("ok",false): return {}
		choices += 1
	t.check(_ready_for_final(state,definition),"actual selection sequence reaches base five plus its approved attack or support owned at one")
	if not _ready_for_final(state,definition): return {}
	t.check(Catalog.new().evolutions.evaluate(state,recipe).can_evolve and state.tactical_seals == 0,"base five plus owned partner is ready before any boss or seal")
	state.active_tick = 17999
	state.survival_tick = 17999
	for id in state.equipment: state.player.attack_ready_ticks[id] = 18001
	F.step(sim,state,Vector2.ZERO,[F.boss("ch01_b05",[45,0])])
	t.check(state.entities.size() == 1,"actual scheduled miniboss spawns for earned-seal route")
	if state.entities.size() != 1: return {}
	state.entities[0].hp = 1.0
	F.step(sim,state,Vector2.ZERO)
	t.check(state.tactical_seals == 1 and state.stats.minibosses_defeated == 1,"actual killing hit earns one seal and boss offer")
	var option := "evolution:"+recipe
	t.check(state.upgrade_offer.get("options",[]).any(func(o): return o.option_id == option),"ready new ultimate is included in actual boss offer")
	var picked: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.get("offer_id",""),option)
	t.check(picked.get("ok",false) and state.evolutions.get(base) == recipe and state.tactical_seals == 1,"actual final selection preserves the independently earned boss seal and internal base five")
	if not picked.get("ok",false): return {}
	for id in state.equipment: state.player.attack_ready_ticks[id] = 20000
	state.player.attack_ready_ticks[base] = state.active_tick
	return state
func _material_rows(recipe: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for required in recipe.get("required_equipment",[]): rows.append({"kind":"equipment","owned":"equipment","id":required.equipment_id,"level":int(required.level)})
	for required in recipe.required_passives: rows.append({"kind":"passive","owned":"passives","id":required.passive_id,"level":int(required.level)})
	return rows
func _ready_for_final(state: Dictionary, recipe: Dictionary) -> bool:
	if int(state.equipment.get(recipe.base_item_id,0)) != 5: return false
	for material in _material_rows(recipe):
		if int(state[material.owned].get(material.id,0)) < int(material.level): return false
	return true
func _choose(state: Dictionary, recipe: Dictionary) -> String:
	var wanted := [{"kind":"equipment","owned":"equipment","id":recipe.base_item_id,"level":5}]
	wanted.append_array(_material_rows(recipe))
	for material in wanted:
		if int(state[material.owned].get(material.id,0)) >= int(material.level): continue
		for option in state.upgrade_offer.options:
			if option.kind == material.kind and option.item_id == material.id: return option.option_id
	for option in state.upgrade_offer.options:
		if (option.kind == "equipment" and state.equipment.has(option.item_id)) or option.kind == "passive": return option.option_id
	return ""
func _chain_ultimate(t,sim,state: Dictionary) -> void:
	var commands := []
	for index in 12: commands.append(F.spawn("storm-"+str(index),[90+index*24,45],"brute"))
	var events := F.step(sim,state,Vector2.ZERO,commands)
	var attacks := F.types(events,"player_attack").filter(func(e): return e.payload.base_item_id == "chain_lightning")
	t.check(attacks.size() == 12,"storm ultimate changes actual behavior from seven to twelve chained targets")
	var ids := {}
	for attack in attacks:
		t.check(not ids.has(attack.payload.target_id),"ultimate never damages the same target twice in a cast")
		ids[attack.payload.target_id] = true
		t.check(attack.payload.evolution_id == "evo_storm_chain" and attack.payload.art_id == "vfx_storm_chain","actual ultimate events carry distinct visual identity")
	t.check(sim.restore(JSON.parse_string(JSON.stringify(state))).get("ok",false),"earned chain ultimate actual combat cold restores")
func _fire_ultimate(t,sim,state: Dictionary) -> void:
	# Any base-field cast from the boss-killing tick remains legally frozen.
	t.check(sim.restore(JSON.parse_string(JSON.stringify(state))).get("ok",false),"old fire field remains valid after actual ultimate choice")
	var events := F.step(sim,state,Vector2.ZERO,[F.spawn("inferno-target",[110,0],"brute")])
	var attacks := F.types(events,"player_attack").filter(func(e): return e.payload.base_item_id == "fire_zone" and e.payload.phase == "executed" and e.payload.evolution_id == "evo_inferno_zone")
	var saved: Dictionary = sim.snapshot(state)
	var cold: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(saved)))
	t.check(cold.get("ok",false),"old base field and new ultimate field with permanent damage cold restore together")
	if not cold.get("ok",false): return
	for tick in 150:
		var live := F.step(sim,state,Vector2.ZERO)
		var replay := F.step(sim,cold.state,Vector2.ZERO)
		t.check(live == replay,"mixed old/new fire reservations replay exact boosted damage")
		attacks.append_array(F.types(live,"player_attack").filter(func(e): return e.payload.base_item_id == "fire_zone" and e.payload.phase == "executed" and e.payload.evolution_id == "evo_inferno_zone"))
	t.check(attacks.size() >= 8,"ultimate executes seven faster pulses and a final eruption")
	if attacks.size() >= 8:
		var first: Dictionary = attacks[0].payload
		var last: Dictionary = attacks[7].payload
		t.check(last.execute_tick-first.execute_tick == 150 and last.radius > first.radius and last.damage > first.damage*2,"final eruption changes timing, radius and damage rather than only the name")
		t.check(last.art_id == "vfx_inferno_eruption","final eruption has its own VFX identity")
