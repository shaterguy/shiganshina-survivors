extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const Earned = preload("res://tests/fantasy_skills/test_actual_ultimate_flow.gd")
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
# Production failures caught: missing/wrong recipe, fake scheduled cast, duplicate
# fields, changed cast identity after evolution, premature retirement, replayed flash.
func run(t) -> void:
	_recipes(t)
	_chain(t,"")
	_chain(t,"evo_storm_chain")
	_fire(t,"")
	_fire(t,"evo_inferno_zone")
	_before_first_execute(t)
func _recipes(t) -> void:
	var catalog := Catalog.new()
	var art_ids := []
	for pair in [["chain_lightning",""],["chain_lightning","evo_storm_chain"],["fire_zone",""],["fire_zone","evo_inferno_zone"]]:
		var recipe: Dictionary = catalog.recipe(pair[0],pair[1],"cast")
		t.check(not recipe.is_empty(),"new fantasy recipe exists "+str(pair))
		if not recipe.is_empty(): art_ids.append(recipe.art_id)
	t.check(art_ids.size() == 4 and _unique(art_ids).size() == 4,"four fantasy casts use four distinct original art identities")
	var eruption: Dictionary = catalog.recipe("fire_zone","evo_inferno_zone","eruption")
	t.check(eruption.get("core_art_id") == "vfx_inferno_eruption" and eruption.get("art_id") == "vfx_crossfire_contact_blast","final core eruption identity explicitly maps to the existing original blast raster")
	for evo in ["","evo_inferno_zone"]:
		var area: Dictionary = catalog.recipe("fire_zone",evo,"area")
		t.check(not area.is_empty() and area.get("role") == "area" and area.get("render_pass") == "ground","persistent fire has dedicated ground recipe "+evo)
func _chain(t, evolution: String) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"chain_lightning":5 if not evolution.is_empty() else 1}
	if not evolution.is_empty():
		state = _earned_empty(t,sim,evolution)
		if state.is_empty(): return
	var commands := []
	for i in 12: commands.append(F.spawn("chain-"+str(i),[80+i*40,0],"brute"))
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,commands)
	var snapshot: Dictionary = sim.snapshot(state)
	var attacks := events.filter(func(e): return e.type == "player_attack" and e.payload.base_item_id == "chain_lightning")
	var director := Director.new()
	director.consume(events,snapshot)
	var effects := director.present(snapshot).filter(func(e): return e.get("base_item_id") == "chain_lightning")
	t.check(attacks.size() > 0 and effects.size() == attacks.size(),"exactly one visible effect per executed chain link "+evolution)
	for event in attacks:
		var found := effects.filter(func(e): return e.attack_id == event.payload.attack_id)
		if found.is_empty(): continue
		var effect: Dictionary = found[0]
		t.check(effect.geometry == event.payload.geometry,"chain preserves actual previous-target segment geometry")
		t.check(effect.get("cast_id") == event.payload.cast_id,"each chain segment retains cast identity")
		t.check(effect.start_tick == snapshot.active_tick and effect.animation_start_tick == snapshot.active_tick,"chain contact starts at executed tick")
		t.check(effect.art_id == ("vfx_storm_chain" if evolution != "" else "vfx_chain_lightning"),"chain ultimate has different authored art")
	director.consume(events,snapshot)
	t.check(director.present(snapshot).filter(func(e): return e.get("base_item_id") == "chain_lightning").size() == effects.size(),"duplicate batch cannot duplicate links")
func _fire(t, evolution: String) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"fire_zone":5 if not evolution.is_empty() else 1}
	if not evolution.is_empty():
		state = _earned_empty(t,sim,evolution)
		if state.is_empty(): return
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("field-target",[100,0],"brute")])
	state.player.attack_ready_ticks.fire_zone = 999999
	var director := Director.new()
	var first: Dictionary = sim.snapshot(state)
	director.consume(events,first)
	var first_effects := director.present(first)
	var fields := _fields(first_effects)
	t.check(fields.size() == 1,"one persistent field per real fire cast "+evolution)
	if fields.is_empty(): return
	var cast_id: String = state.player_attack_instances[0].cast_id
	var last := int(state.player_attack_instances[-1].execute_tick)
	var radius := float(state.player_attack_instances[0].radius)
	t.check(fields[0].attack_id == cast_id and fields[0].get("cast_id") == cast_id,"floor identity is cast rather than stage")
	t.check(fields[0].end_tick == last and fields[0].geometry.radius == radius,"finite floor uses frozen actual radius and last pending stage")
	var original: Dictionary = first.duplicate(true)
	director.present(first)
	t.check(first == original and _fields(director.present(first)).size() == 1,"repeated snapshot leaves core immutable and area deduplicated")
	var pulse_ticks := [int(first.active_tick)]
	for tick in range(int(first.active_tick)+1,last+1):
		events = F.step(sim,state,Vector2.ZERO)
		var current: Dictionary = sim.snapshot(state)
		director.consume(events,current)
		var current_effects := director.present(current)
		var current_fields := _fields(current_effects)
		var attacks := events.filter(func(e): return e.type == "player_attack" and e.payload.base_item_id == "fire_zone" and e.payload.phase == "executed")
		if not attacks.is_empty(): pulse_ticks.append(tick)
		if tick < last:
			t.check(current_fields.size() == 1 and is_equal_approx(float(current_fields[0].geometry.radius),radius),"field survives between pulses without adopting eruption radius")
			t.check(director.present(current) == current_effects,"paused active tick leaves floor and pulses unchanged")
			if tick == int(first.active_tick)+11 or tick == last-1:
				var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(current)))
				t.check(restored.get("ok",false),"real fire snapshot cold restores")
				if restored.get("ok",false):
					var cold := Director.new()
					var cold_effects := cold.present(sim.snapshot(restored.state))
					t.check(cold_effects.size() == 1 and _fields(cold_effects).size() == 1,"cold restore reconstructs ongoing floor only, never historical pulse")
					if not cold_effects.is_empty():
						t.check(cold_effects[0] == current_fields[0],"cold floor equals warm floor even in final eruption-only gap")
		else:
			t.check(current_fields.is_empty(),"field expires exactly at last actual stage")
			var actual := current_effects.filter(func(e): return e.get("base_item_id") == "fire_zone")
			t.check(actual.size() == 1,"final actual stage is one cast or eruption, not a permanent floor")
			if not actual.is_empty():
				t.check(actual[0].recipe_id == ("evo_inferno_zone.eruption" if evolution != "" else "fire_zone.cast"),"ultimate last stage uses distinct eruption recipe")
	var expected := [0,30,60,90] if evolution == "" else [0,20,40,60,80,100,120,150]
	for index in expected.size(): expected[index] += int(first.active_tick)
	t.check(pulse_ticks == expected,"actual fire contact cadence unchanged "+evolution)
func _before_first_execute(t) -> void:
	var d := Director.new()
	var snapshot := {"run_id":"not-started","active_tick":9,"event_seq":0,"player_attack_instances":[{"attack_id":"not-started:attack:1:0","cast_id":"not-started:attack:1","base_item_id":"fire_zone","evolution_id":"","attack_started_tick":10,"execute_tick":10,"stage_index":0,"stage_count":4,"cast_level":1,"origin":[1,2],"direction":[1,0],"shape":"circle","radius":42.0}]}
	t.check(d.present(snapshot).is_empty(),"no fire floor before first actual execution")
func _fields(effects: Array) -> Array:
	return effects.filter(func(e): return e.get("role") == "area")
func _unique(values: Array) -> Array:
	var found := []
	for value in values:
		if not value in found: found.append(value)
	return found

func _earned_empty(t,sim,evolution: String) -> Dictionary:
	var state: Dictionary = Earned.new()._evolve(t,sim,evolution)
	if state.is_empty(): return {}
	for id in state.equipment: state.player.attack_ready_ticks[id] = 999999
	var last := int(state.active_tick)
	for record in state.player_attack_instances: last = maxi(last,int(record.execute_tick))
	while int(state.active_tick) <= last: F.step(sim,state,Vector2.ZERO)
	var base := "chain_lightning" if evolution == "evo_storm_chain" else "fire_zone"
	state.player.attack_ready_ticks[base] = state.active_tick
	return state
