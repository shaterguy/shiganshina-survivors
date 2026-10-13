extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const View = preload("res://game/progression/progression_view.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	var catalog := Catalog.new()
	# Pure existing wire comparison; no read/write or product rounding occurs.
	var wire_store := Save.new("user://unused_final_replay_wire_comparison",Callable())
	for id in catalog.evolutions.ids():
		var recipe: Dictionary = catalog.evolutions.definition(id)
		if recipe.seal_cost != 0: continue
		var sim := Core.new(Current.new())
		var state := sim.new_run(F.chapter(),42,F.run_config())
		t.check(not state.has("error_code"),"current Core constructs for final choice: "+id)
		if state.has("error_code"): continue
		state.equipment = {recipe.base_item_id:5}
		for required in recipe.get("required_equipment",[]): state.equipment[required.equipment_id] = int(required.level)
		for required in recipe.required_passives: state.passives[required.passive_id] = int(required.level)
		for base in state.equipment: state.player.attack_ready_ticks[base] = 2147483647
		t.check(sim.restore(state).get("ok",false),"zero-boss final-ready state restores: "+id)
		F.drop_xp(sim,state,24,"final:xp:"+id)
		var offer: String = state.upgrade_offer.get("offer_id","")
		var result := sim.choose_upgrade(state,offer,"evolution:"+id)
		t.check(result.get("ok",false),"real XP offer applies final evolution without boss seal: "+id)
		if not result.get("ok",false): continue
		t.check(state.equipment[recipe.base_item_id] == 5 and state.evolutions[recipe.base_item_id] == id and state.tactical_seals == 0 and state.stats.minibosses_defeated == 0,"free final stage preserves base levels and boss reward ledger: "+id)
		var before := state.duplicate(true)
		t.check(not sim.choose_upgrade(state,offer,"evolution:"+id).get("ok",true) and state == before,"duplicate final choice is transactional and refused: "+id)
		var resumed := sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state),"",true,true)))
		t.check(resumed.get("ok",false) and resumed.state == state,"chosen final stage survives exact JSON save/resume: "+id)
		var owned: Array = View.new(catalog).build(state).get("owned",{}).get("equipment",[])
		for row in owned:
			if row.item_id == recipe.base_item_id: t.check(row.level == 6 and row.max_level == 6,"real choice appears as six of six: "+id)
		# Execute a real cast, then replay all delayed stages from the saved snapshot.
		state.player.attack_ready_ticks[recipe.base_item_id] = state.active_tick
		var position: Array = [float(state.player.position[0])+60.0,float(state.player.position[1])]
		var damage_before := float(state.stats.damage_dealt)
		var events := F.step(sim,state,Vector2.ZERO,[F.spawn("final:target:"+id,position,"brute")])
		var attacks := F.types(events,"player_attack").filter(func(event): return event.payload.base_item_id == recipe.base_item_id)
		t.check(not attacks.is_empty() and attacks.all(func(event): return event.payload.evolution_id == id),"selected final stage drives actual combat events: "+id)
		state.player.attack_ready_ticks[recipe.base_item_id] = 2147483647
		var cold := sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state),"",true,true)))
		t.check(cold.get("ok",false),"pending final-stage attacks cold restore: "+id)
		if not cold.get("ok",false): continue
		var replay := Core.new(Current.new())
		_replay_comparison_guards(t,state,wire_store)
		if state != cold.state: print("FINAL_COLD_INITIAL_DIFF ",JSON.stringify({"recipe":id,"difference":_first_difference(state,cold.state,"state")}))
		var reported := false
		for tick in 151:
			var live_events := F.step(sim,state,Vector2.ZERO)
			var replay_events := F.step(replay,cold.state,Vector2.ZERO)
			if not reported and (live_events != replay_events or not _same_replay_state(state,cold.state,wire_store)):
				print("FINAL_REPLAY_FIRST_DIFF ",JSON.stringify({"recipe":id,"relative_tick":tick+1,"active_tick":state.active_tick,"events_equal":live_events == replay_events,"state_difference":_first_difference(state,cold.state,"state"),"event_difference":_first_difference(live_events,replay_events,"events")}))
				reported = true
			t.check(live_events == replay_events and _same_replay_state(state,cold.state,wire_store),"cold final replay keeps events and every physical/reserved field exact; damage tally follows existing wire contract: "+id)
		t.check(float(state.stats.damage_dealt) > damage_before,"final pattern produces real enemy damage: "+id)
		t.check(state.player_attack_instances.is_empty(),"all final-stage reservations retire once: "+id)

# First-difference diagnostics retain the exact 151-tick equality assertion.
func _first_difference(left: Variant, right: Variant, path: String) -> Dictionary:
	if typeof(left) != typeof(right): return {"path":path,"left_type":typeof(left),"right_type":typeof(right),"left":left,"right":right}
	if left is Dictionary:
		if left.size() != right.size(): return {"path":path+".keys","left":left.keys(),"right":right.keys()}
		for key in left:
			if not right.has(key): return {"path":path+"."+str(key),"missing":"right"}
			var nested := _first_difference(left[key],right[key],path+"."+str(key))
			if not nested.is_empty(): return nested
	elif left is Array:
		if left.size() != right.size(): return {"path":path+".size","left":left.size(),"right":right.size()}
		for index in left.size():
			var nested := _first_difference(left[index],right[index],path+"["+str(index)+"]")
			if not nested.is_empty(): return nested
	elif left != right:
		return {"path":path,"left":String.num(left,17) if left is float else left,"right":String.num(right,17) if right is float else right}
	return {}

# Only this cumulative display scalar uses the already-established save wire
# equality. Every other key/value (HP, damage records, geometry, IDs, RNG and
# clocks included) still uses raw exact equality; no epsilon is introduced.
func _same_replay_state(left: Dictionary, right: Dictionary, store) -> bool:
	for state in [left,right]:
		if not state.get("stats") is Dictionary or not state.stats.has("damage_dealt"): return false
		var damage = state.stats.damage_dealt
		if not (damage is int or damage is float) or not is_finite(float(damage)) or float(damage) < 0.0: return false
	if not store._same(left.stats.damage_dealt,right.stats.damage_dealt): return false
	var a := left.duplicate(true)
	var b := right.duplicate(true)
	a.stats.erase("damage_dealt")
	b.stats.erase("damage_dealt")
	return a == b
func _replay_comparison_guards(t,state: Dictionary,store) -> void:
	for mutation in ["missing_tally","nan_tally","string_tally","invented_tally","player_hp","position","reserved_damage"]:
		var bad := state.duplicate(true)
		match mutation:
			"missing_tally": bad.stats.erase("damage_dealt")
			"nan_tally": bad.stats.damage_dealt = NAN
			"string_tally": bad.stats.damage_dealt = str(state.stats.damage_dealt)
			"invented_tally": bad.stats.damage_dealt += 0.000001
			"player_hp": bad.player.hp += 0.000001
			"position": bad.player.position[0] += 0.000001
			"reserved_damage":
				if bad.player_attack_instances.is_empty(): continue
				bad.player_attack_instances[0].damage += 0.000001
		t.check(not _same_replay_state(state,bad,store),"wire-stat comparison still rejects missing/unsafe tally and exact physical tampering: "+mutation)
