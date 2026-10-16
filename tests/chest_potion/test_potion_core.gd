extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	if sim == null: return
	for version in [1,2]:
		var config: Dictionary = F.run_config()
		config.loot_rules_version = version
		var state: Dictionary = sim.new_run(F.v2_chapter(),42,config)
		t.check(state.has("loot"),"POTION constructor version accepted")
		if not state.has("loot"): continue
		t.check(state.loot.has("potions") == (version == 2),"POTION v1 preserves exact old shape")
		t.check(sim.restore(state).get("ok",false),"POTION initial cold restore")
		if version == 1: continue
		var rng: String = state.rng_state
		var growth_rng: String = state.progression_rng_state
		var events: Array[Dictionary] = []
		state.active_tick = 10800
		state.survival_tick = 10800
		sim._update_loot(state,events)
		var chest: Dictionary = state.loot.chests[0]
		chest.status = "placed"
		Loot.set_position(state,chest,Vector2(state.player.position[0],state.player.position[1]))
		sim._update_loot(state,events)
		t.check(state.loot.gold == 5 and state.loot.potions.size() == 1,"POTION adds one without replacing five gold")
		t.check(state.loot.potions[0].status == "placed","POTION full HP leaves bottle")
		t.check(Loot.validate(state) and sim.restore(state).get("ok",false),"POTION placed validates at cold boundary")
		var placed := state.duplicate(true)
		sim._update_loot(state,events)
		t.check(state.loot.potions.size() == 1 and state.loot.gold == 5,"POTION repeated chest tick cannot duplicate")
		state.player.hp = float(state.player.max_hp)-7.0
		sim._update_loot(state,events)
		t.check(state.player.hp == state.player.max_hp and state.loot.potions[0].healed_amount == 7.0,"POTION clamps actual recovery to deficit")
		t.check(state.loot.potions[0].status == "claimed" and Loot.validate(state),"POTION consumption receipt validates")
		state.player.hp -= 30.0
		sim._update_loot(state,events)
		t.check(state.player.hp == float(state.player.max_hp)-30.0,"POTION consumed bottle cannot heal twice")
		t.check(state.rng_state == rng and state.progression_rng_state == growth_rng,"POTION collection consumes neither RNG")
		t.check(sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true))).get("ok",false),"POTION claimed JSON restore")
		t.check(not Loot.transition_valid(state,placed),"POTION transition rejects consumption rollback")
		for key in ["id","chest_id","status","stage","born_tick","heal_amount","healed_amount","position","address"]:
			var bad := placed.duplicate(true)
			bad.loot.potions[0][key] = null
			t.check(not Loot.validate(bad),"POTION rejects malformed "+key)
		var bad := placed.duplicate(true)
		bad.loot.potions.append(bad.loot.potions[0].duplicate(true))
		t.check(not Loot.validate(bad),"POTION rejects duplicate identity")
		bad = placed.duplicate(true)
		bad.loot.potions.clear()
		t.check(not Loot.validate(bad),"POTION opened field cannot lose bottle record")
		for hp in [0.0,1.0,float(state.player.max_hp)-0.005]:
			var candidate := placed.duplicate(true)
			candidate.player.hp = hp
			sim._collect_potions(candidate,events)
			t.check(candidate.player.hp == (minf(hp+20.0,float(candidate.player.max_hp)) if hp > 0.0 else 0.0),"POTION alive recovery and no resurrection")
		_all_sources(t,sim,config)

func _all_sources(t,sim,config: Dictionary) -> void:
	var state: Dictionary = sim.new_run(F.v2_chapter(),42,config)
	var events: Array[Dictionary] = []
	for tick in Loot.FIELD_TICKS:
		state.active_tick = tick
		state.survival_tick = tick
		sim._update_loot(state,events)
		for chest in state.loot.chests:
			if chest.status not in ["pending","placed"]: continue
			chest.status = "placed"
			Loot.set_position(state,chest,Vector2(state.player.position[0],state.player.position[1]))
		sim._update_loot(state,events)
		t.check(Loot.validate(state),"POTION each field schedule preserves source relationships")
	t.check(state.loot.potions.size() == 5 and state.loot.gold == 15 and state.pending_offers.size() == 2,"POTION all five field rewards and bottles preserved")
	for boss in Loot.BOSS_IDS:
		state.boss_ids_fired.append(boss)
		sim._claim_boss_reward(state,{"boss_id":boss,"entity_id":"test:"+boss,"position":state.player.position.duplicate()},events)
		sim._update_loot(state,events)
	t.check(state.loot.potions.size() == 5,"POTION boss rewards add no extra bottles")

